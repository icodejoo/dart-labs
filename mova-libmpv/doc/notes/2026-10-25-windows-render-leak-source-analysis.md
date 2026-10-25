# Windows 渲染内存增长：源码审查（media_kit_video 2.0.1 / mpv v0.41.0 / ANGLE）

日期：2026-10-25。纯只读源码分析，没有运行任何程序、没有改仓库代码。"明确缺陷"指源码里直接看到的；"推断"未经验证。

审查对象：
- `C:\Users\Administrator\AppData\Local\Pub\Cache\hosted\pub.dev\media_kit_video-2.0.1\windows\{angle_surface_manager.cc,video_output.cc}`
- `D:\whep-win\libmpv\src\mpv-v0.41.0\video\out\{vo_libmpv.c,opengl\context.c,opengl\libmpv_gl.c,opengl\common.c}`（我们的构建就是这份，仅打了 `patches/mpv-v041` 里 5 个补丁，均不碰 GL 路径）

## 一、最可能的泄漏点：mpv v0.41.0 的 GL 同步对象（fence）每帧新建、从不释放

### 代码证据（明确）

1. `video/out/opengl/context.c:227-251` `ra_gl_ctx_submit_frame`：只要 `gl->FenceSync` 非空，**每帧**都 `FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE)` 并 `MP_TARRAY_APPEND(p->vsync_fences, ...)`（235-239 行）。
2. 这些 fence 只在 `context.c:268-298` `ra_gl_ctx_swap_buffers` 的 `while (num_vsync_fences >= swapchain_depth)` 里 `ClientWaitSync + DeleteSync + REMOVE_AT`（293-297 行）被回收。
3. libmpv 路径从不调用 `swap_buffers`：`grep` 全树，调用点只有 `vo_gpu.c:100`、`vo_gpu_next.c:1457`；`libmpv_gl.c:87-94` 的 `done_frame` 只调 `ra_gl_ctx_submit_frame`。`libmpv_gl.c:41-50` 的注释明说 libmpv 不提供 swap 函数（`gl_params = {0}`），把它当"外部交换链"。
4. `FenceSync/ClientWaitSync/DeleteSync` 的加载条件是 `.ver_es_core = 300`（`opengl/common.c:277-285`），ANGLE 报 OpenGL ES 3.0（见 angle-replacement-verify 3 节），所以在我们的环境里一定可用，上面的路径一定走到。
5. 上游已修：mpv master 的同一处现为 `if (gl->FenceSync && p->params.swap_buffers) {`（WebFetch 读 raw.githubusercontent.com/mpv-player/mpv/master/video/out/opengl/context.c，只确认到这行条件，没有查具体提交号与它是否进了 0.41.x）。libmpv 传空 params，`swap_buffers` 为 NULL，master 上就不再建 fence。**v0.41.0 缺这个条件。**

结论：v0.41.0 的 libmpv OpenGL 渲染每渲染一帧就在 ANGLE 里留下一个永不删除的 GLsync（mpv 侧 `vsync_fences` 数组同时线性增长，每帧 8 字节，可忽略；大头在 ANGLE）。

### ANGLE 侧机制（推断）

ANGLE D3D11 后端的 `Sync11` 每个 sync 对象持有 `ID3D11Query`（EVENT 类），驱动（NVIDIA UMD）为 query 在 CPU 侧分配内存，没 DeleteSync 就一直在。这是推断，我没有读 ANGLE 的 `Sync11.cpp`，也没量单个 query 的驻留大小。

### 与已测现象的对照

| 现象 | 吻合情况 |
|---|---|
| 9.6 MiB/min，线性 | 25fps × 60 = 1500 帧/min，折合约 6.7 KB/个 sync/帧。按"ID3D11Query + 驱动内部分配"量级，**合理但未验证**；若 mpv 实际 render 次数高于 25（redraw、OSD），单个更小。**需要计数确认** |
| 与视频源无关（本地 mp4 循环、HTTP、WHEP 都涨） | 吻合：只要渲染就每帧一个 |
| 软件渲染不涨 | 吻合：SW 路径不走 GL、没有 fence |
| 不放 Video 控件仍涨（r_nowidget） | 吻合：`Render()` 由 mpv update 回调驱动，与 Flutter 取纹理无关（`video_output.cc:150-156`） |
| 不创建 VideoController 不涨 | 吻合：没有 render context |
| 114/115/116 同样涨 | 吻合：泄漏在 mpv 侧调用方式，与 ANGLE 版本无关，只要 ANGLE 能出画就涨 |
| 2025-08 / 2026-03 ANGLE "不涨" | 因为那些版本不出画（`mpv_render_context_render` 没被调用，见第三节），没有帧→没有 fence，**不是修复**，与既有笔记的判断一致 |
| 260~430 KB 私有块，数量大 | **不吻合/未解释**：每个 fence 若只有几 KB，应表现为小块或堆内增长。块大小逐级 +32KB（266,240 / 299,008 / 331,776）更像 NT 堆段或 vector 扩容的形状。可能是 ANGLE/驱动把 query 放进了大 slab。没法下结论，建议用堆栈抓取（见验证） |
| 2025-08 之后 ANGLE 才"修复" | 不涉及 |

## 二、media_kit_video 2.0.1 逐函数审查

### 每帧路径（`Render` → `ANGLESurfaceManager::Draw`）

`video_output.cc:158-199`、`angle_surface_manager.cc:50-57`：`WaitForSingleObject(mutex)` → `eglMakeCurrent(surface)` → `mpv_render_context_render`（FBO id=0、没传 `ADVANCED_CONTROL`、没传 `BLOCK_FOR_TARGET_TIME`，因此默认阻塞等 present）→ `glFinish()` → `eglMakeCurrent(NO_*)` → `ReleaseMutex`。

**每帧没有创建 EGL surface、没有创建 D3D 纹理、没有 `CreateSharedHandle/OpenSharedResource`、没有堆分配。** 所以任务书里最担心的"每帧 `eglCreatePbufferFromClientBuffer` 缺 `eglDestroySurface`"在这份代码里**不成立**（pbuffer 只在 `Create()` 里建，`angle_surface_manager.cc:294`，销毁在 `CleanUp` 127-134 行）。没有 `ReportSwap` 调用，没有 `MPV_RENDER_PARAM_SKIP_RENDERING`。

`GetVideoWidth/Height`（`video_output.cc:366-462`）每次 update 各调用一次 `mpv_get_property("video-out-params")`，只在 `MPV_FORMAT_NODE_MAP` 时 `mpv_free_node_contents`；非 MAP 时 mpv 不分配，无泄漏；SW 路径同样调用却不涨，也不是它。

### 明确缺陷（与持续线性增长无关，只在 Resize 时触发）

1. `angle_surface_manager.cc:223` 与 `:234`：对 `ComPtr` 接收的 `internal_d3d_11_texture_2D_`、`d3d_11_texture_2D_` 又手动 `AddRef()`，而 `CleanUp` 只 `Release()` 一次（136-143 行）。**引用计数 2→1，不归零，每次 `SetSize`（分辨率变化触发的 `Create`）泄漏两张 D3D11 纹理（BGRA，w×h×4 字节，主要是 GPU 内存；共享句柄也一并留着）**。注：这两个成员是裸指针还是 ComPtr，我看了 `.cc` 里 `.Get()`/`->Release()` 的混用，推断是 `ComPtr`（`resource->` 之外的用法一致）；`.h` 没读，未核实。
2. `angle_surface_manager.cc:300-305`：`CreateAndBindEGLSurface` 每次 `glGenTextures` 一个纹理 `t` 且从不 `glDeleteTextures`，每次 `Create`（含 Resize）泄漏一个 GL 纹理名及其 `eglBindTexImage` 绑定。
3. `:36` 析构里对未持有的 mutex 调 `ReleaseMutex`（无害，返回失败）。

这些都是 Resize 一次性的泄漏，**解释不了固定尺寸下的线性增长**（本地循环测试里没有 resize；实际是否有 resize 没有日志确认，见验证）。mova 里窗口缩放会放大这个问题，建议一并修。

### 其他审查结论

- `texture_update_callback_` 的 lambda：`SetTextureUpdateCallback` 只是赋值，没有循环 `shared_ptr`（全文没用 `shared_ptr`）。
- GPU 纹理 `release_callback = [](void*){}`、`release_context = nullptr`（`video_output.cc:308-309`）：Flutter 不会替插件释放什么，无泄漏。`textures_` 在 Resize/析构里被 erase。
- `Read()`（`angle_surface_manager.cc:59-67`）在 Flutter 的 raster 线程每次取纹理时 `CopyResource + Flush`，无分配。
- 线程池里 `NotifyRender` 每次 update post 两个任务（`CheckAndResize`、`Render`），`std::bind` 小对象，随任务执行释放，不会堆积（除非 Render 卡住，见第三节）。
- 同步方式：ANGLE 自己的 D3D11 设备写 `internal_handle_`（旧式非 NT 共享句柄，`D3D11_RESOURCE_MISC_SHARED`，无 keyed mutex）；media_kit 自己另一个设备对它 `CopyResource`。全靠 `glFinish()` 保证写完。

## 三、117+ 不出画的机制（**源码里没有直接答案，以下均为推断**）

事实（来自 mpv 源码）：日志那句 `mpv_render_context_render() not being called or stuck.` 出自 `vo_libmpv.c:513-519` 的 `flip_page`：VO 线程等 200ms，`ctx->next_frame` 仍未被 `mpv_render_context_render` 取走。**它说明 `Render()` 没在 200ms 内走到 `mpv_render_context_render` 取帧**，不说明 ANGLE 画了空内容。也就是说，`pos` 前进、EGL/GL 都初始化成功、日志无 Failure，但渲染调用本身没发生或没返回。

可能的位置（media_kit 侧，`Render()` 运行条件）：
- `video_output.cc:159`：`if (texture_id_)`——`texture_id_` 为 0 时整个 `Render` 空转。`texture_id_` 只在 `Resize()` 里设置（323 行），而 `Resize` 在构造时被调用（48 行），并且要求 `eglCreatePbuffer...` 成功后才继续；`CheckAndResize` 在视频尺寸变化时重建。假设：新 ANGLE 下某个 EGL/D3D 调用 `throw`（`Create()` 里的 `runtime_error`，被构造函数的 `catch(...)` 吞掉，`video_output.cc:77-81`）→ 会落到 S/W 路径并打印 `Using S/W rendering.`，但笔记里 EGL 创建成功，所以更像下一条。
- `Draw` 里 `WaitForSingleObject(mutex_, INFINITE)`（`:51`）与 `Read()` 共用一把锁；若 Flutter 的纹理回调被新 ANGLE 的行为卡住，或 `eglMakeCurrent`/`glFinish` 在 117+ 里阻塞（如线程池线程上的 context 当前性被破坏），`Render` 会"stuck"。构造时 `MakeCurrent(true)` 在线程池线程 A 上做，而线程池是否多线程我没读 `ThreadPool` 的实现——**若线程池有多个线程，则 `eglMakeCurrent` 在不同线程之间交替，ANGLE 117+ 对"context 仍绑定在另一线程"的处理比旧版严格是可能的**，但没有证据。这点要先读 `thread_pool.cc`。

关于 ANGLE 116→117 的变化：我没有去 chromium.googlesource.com/google/angle 查提交（本次未联网查证，也不想编造提交号）。已知线索是笔记里"扩展仍广告、pbuffer 创建成功"，因此"扩展被删"不是原因。**我不知道 117 具体改了什么**，不要把任何关于"共享句柄语义改了"的说法当成事实。

## 四、可验证假设（≤3 个）

### 假设 1（最强）：libmpv 在 v0.41.0 每帧留一个 GLsync（泄漏主因）

- 位置：`mpv-v0.41.0/video/out/opengl/context.c:235-239`（创建）、`:293-297`（唯一回收点，libmpv 不走）；`libmpv_gl.c:87-94`。
- 吻合点：见第一节表；不吻合点：260~430KB 块形状未解释、单帧 6.7KB 量级待确认。
- 验证（不用桌面跑也行，但要跑得在 CPU 采样之外）：
  1. 最便宜：在 `ra_gl_ctx_submit_frame` 的 append 处加一行 `MP_VERBOSE/MP_WARN` 打 `num_vsync_fences`，用 `D:\tmp\w14` 的最小 app 跑 60s，看是否 ≈1500 并线性增长。
  2. 或者直接打下面补丁重编 libmpv（`build-windows.sh` 的 whep 模式，按序打 `patches/mpv-v041/*.patch`），用同一 app 跑 5 分钟，看私有斜率是否从 ~9.6 掉到 ≤1 MiB/min。
  3. 对照：不改源码，也可在 media_kit 里不可行（拿不到 mpv 内部数组），所以走补丁。
- 修复：给 mpv 打一行补丁（草案，**未创建文件**，建议命名 `0006-opengl-no-fence-without-swap-buffers.patch`）：

```diff
--- a/video/out/opengl/context.c
+++ b/video/out/opengl/context.c
@@ -232,7 +232,7 @@ bool ra_gl_ctx_submit_frame(struct ra_swapchain *sw, const struct vo_frame *frame)
     if (p->opts->use_glfinish)
         gl->Finish();
 
-    if (gl->FenceSync) {
+    if (gl->FenceSync && p->params.swap_buffers) {
         GLsync fence = gl->FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
         if (fence)
             MP_TARRAY_APPEND(p, p->vsync_fences, p->num_vsync_fences, fence);
```
  （与 master 的条件一致；行号来自 v0.41.0，应用时用 `git apply --check`。）
- 工作量：补丁 5 分钟，重编 libmpv（Windows 一次）约一小时级，验证 5~15 分钟。**还需要同步到 Android/其他平台的 mpv 补丁序列，因为 Android 的 libmpv 也走同一 GL 路径，同样会涨。**
- 副作用评估：libmpv 的 fence 本来就没人等，去掉不改变渲染结果。

### 假设 2：Resize 路径的纹理/GL 名泄漏（次要，Resize 一次性）

- 位置：`angle_surface_manager.cc:223、234`（多余 `AddRef`）、`:300-305`（`glGenTextures` 无删除）。
- 吻合点：无（不是线性、不是固定尺寸下增长）；它解释的是缩放窗口后的显存/句柄残留。
- 验证：在最小 app 里反复缩放 100 次，看 GPU 专用显存和句柄数是否阶梯上升；或在这两处加计数日志。
- 修复：删 223/234 行的 `AddRef()`；在 `CleanUp` 里保存并 `glDeleteTextures(&t)`。需要 fork/覆盖 `media_kit_video`，**要你同意**。
- 工作量：改动小，但要维护 fork。

### 假设 3：117+ 不出画是 media_kit `Render()` 线程/上下文问题，而非 ANGLE 内容为空

- 位置：`video_output.cc:34-106、150-199`，`angle_surface_manager.cc:50-57、69-75`，以及 `ThreadPool`（未读）。
- 吻合点：mpv 日志的 `render() not being called or stuck`；EGL 创建成功；`pos` 正常。不吻合：旧版同样在线程池上跑却正常，需解释 117 为何不同——没有答案。
- 验证：在本地覆盖的 `video_output.cc` 里给 `Render()` 入口、`mpv_render_context_render` 前后、`eglMakeCurrent` 返回值、`eglGetError()` 各加计数/日志；或用 WinDbg/`procdump` 在"不出画"时抓线程栈，看池线程是否阻塞在 `WaitForSingleObject` 或 ANGLE 内部。**这个可以不重编任何东西，只换一个调试版 media_kit_video 的 `.cc`。**
- 修复：取决于结果，可能是 `texture_id_` 为 0、context 跨线程、或需要改为 `EGL_ANGLE_d3d_texture_client_buffer`。工作量不确定。
- 注意：**只有假设 1 修好后，假设 3 才对"换新 ANGLE 以降低体积"有意义**；假设 1 修好后，114-116 的旧 ANGLE（能出画）可能已经不涨，那就不需要换 ANGLE，也就不需要解决 117+ 不出画。

## 五、瘦身 libmpv 是否参与

- `patches/mpv-v041/0001-vo-drop-gpu-next.patch` 只摘 `vo_gpu_next`/`gl_next_conf`，保留 `video_out_gpu` 和 libmpv 的 ra_gl 路径；这条泄漏路径在上游标准构建里同样存在，**不是瘦身引入的**。
- `build-windows.sh` 对 mpv 只传 `-Dgpl=false -Dlibmpv=true -Dcplayer=false`，没改 `gl`/`d3d11`/`egl-angle` 选项；libplacebo 构建里关了 vulkan/d3d11/glslang/shaderc，只给 `gpu-next`（已摘）用，与 GL 路径无关。
- 注意：libmpv 未 `ADVANCED_CONTROL`、media_kit 也不调 `mpv_render_context_report_swap`，是正常的"basic"用法，不是缺陷；但它进一步说明 fence 不会被回收。

## 六、推荐方案与待你决定

推荐顺序：
1. 先做假设 1 的最便宜验证（加一行日志，或直接打补丁重编），这最可能把 9.6 MiB/min 压到约 0，同时保留已验证出画的旧 ANGLE，**不用换 ANGLE、不用 fork media_kit**。
2. 通过后：补丁入 `patches/mpv-v041/`，Android 同步（一条补丁，两端都修）。
3. 之后再评估是否还需要换 ANGLE（体积收益）以及假设 2/3。

需要你拍板：
1. 是否允许我新增 mpv 补丁 `0006` 并重编 Windows libmpv（会占用这台机器的编译，另一个 CPU 采样任务结束后再做较好）。
2. 是否允许 fork/覆盖 `media_kit_video`（假设 2、3 需要）。
3. 假设 1 若被证伪（补丁后仍涨），再决定是否上 ETW/UMDH 抓分配栈。

## 七、未核实/限制

- `.h` 文件、`ThreadPool`、Flutter engine 的 `ExternalTextureD3d` 没读。
- 没去 ANGLE 源码查 `Sync11` 与 116→117 的提交；没联网查 ANGLE 发行说明。
- mpv master 的修复只确认了条件行，没有核对提交与发布版本；0.41.x 补丁版本里是否已含，需要查 `v0.41.x` 标签。
- 全程没有运行任何测试程序，数字都来自既有笔记。
