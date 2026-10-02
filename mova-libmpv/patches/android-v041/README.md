# Android 补丁集：mpv v0.41.0 + ffmpeg n9.0.2（WHEP flavor 用）

默认 flavor 仍是 ffmpeg n6.0.1 + mpv `78d43740f5`，本目录**不影响默认路径**。只有 WHEP flavor
（`ffmpeg_ref=9.0.2`、`mpv_ref=v0.41.0`）才用这里的补丁。来源与上下文见
[../../doc/plans/2026-10-01-whep-receiver.md](../../doc/plans/2026-10-01-whep-receiver.md) T0.6、
[../../doc/notes/2026-10-02-android-size-measure.md](../../doc/notes/2026-10-02-android-size-measure.md)。

## 文件

| 文件 | 作用 | 验证 |
|---|---|---|
| `../mpv-v041/0002-client-lavc-set-java-vm.patch` | 导出 `mpv_lavc_set_java_vm(void*)`（media_kit 在 Android 上靠它把 JavaVM 交给 libavcodec，MediaCodec 硬解必需） | 实测：对干净 v0.41.0 `git apply --check` 通过；arm64 产物导出该符号 |
| `../mpv-v041/0001-vo-drop-gpu-next.patch` | 摘掉 `vo_gpu_next`（含 4 个源文件、`gl_next_conf` 引用），保留 libplacebo 作为 `vo_gpu` 的依赖 | 实测：同上，产物无 `gpu-next` 字符串 |
| `local-build-arm64.sh` | WSL 本地构建脚本（`$1`=0/1 控制整链 LTO），含 dav1d 1.2.0；**写死 `/root/w/...` 路径，仅留作证据** | 实测跑通，数字见下 |

按序 `git apply`（先 0001 后 0002，两者改的是 `client.h/client.c` 与 `meson.build/options.c/vo.c`，互不重叠）。

## 与原补丁的对照（核对结论）

原补丁 `libmpv-android-video-build@1ecf510` 的 `buildscripts/patches/mpv/mpv_lavc_set_java_vm.patch` 涉及三处：

1. `libmpv/client.h`：声明。v0.41 头文件已挪到 `include/mpv/client.h`——**路径变了，所以原 hunk 打不上**，0001 已改路径。
2. `player/client.c`：`#include <libavcodec/jni.h>` + 函数体。v0.41 该文件上下文变了（头部 include 顺序、`mpv_wakeup` 附近），0001 把定义放到文件末尾。
3. `libmpv/mpv.def`：原补丁里这一段是个**空的残缺 hunk**（只有 `diff --git` 头，没有内容），且 v0.41 已没有 `libmpv/mpv.def`（`find . -name '*.def'` 无结果）；`.def` 只服务 Windows，Android 无关。**不需要对应改动**。

ffmpeg 侧的 JNI 绑定点：`av_jni_set_java_vm`/`av_jni_get_java_vm` 在 n9.0.2 的 `libavcodec/jni.h`（36/44 行）仍在，`jni.c`、`mediacodecdec.c`、`ffjni.c` 使用 `av_jni_get_java_vm`，**不需要改 ffmpeg**。
mpv 自身（`misc/jni.c`、`video/out/android_common.c`）已经只调 `av_jni_get_java_vm`，无需补丁。即：JavaVM 的"注入口"只有 `mpv_lavc_set_java_vm` 一处，补丁面就是上面这两个文件。
实测（unstripped 符号表）：`av_jni_set_java_vm`/`av_jni_get_java_vm` 都被链进来（局部符号），`mpv_lavc_set_java_vm` 导出。

## 本地构建结果（实测，arm64 API24，NDK r25c，llvm-strip -s，make -j8）

n9.0.2（`--disable-bsfs --disable-iamf --disable-swscale-alpha`，无 `--disable-postproc`，含 `--enable-libdav1d` 的 dav1d 1.2.0 `-Dbitdepths=8`）
+ mpv v0.41.0（0001+0002）+ libplacebo + mbedtls 3.6.7：

| | stripped 字节 |
|---|---:|
| 非 LTO | 7,096,264 |
| 整链 LTO | 6,753,456 |

口径：仍**不是** CI 真实链——缺 libxml2（dash 用）、mbedtls 3.6.7 非 3.4.0、freetype/harfbuzz/fribidi/libass 版本非 CI 的；dav1d 已补（1.2.0，与 CI 同版本）。
**不能直接和仓库里 6,050,104 比**。同口径对照见 android-size-measure.md §7（无 dav1d 的 (d) 行 6,603,344 / 6,261,144，差值 492,920（非 LTO）/ 492,312（LTO）即 dav1d 增量）。

## CI 衔接方案（只给方案，未改 workflow）

现状：`workflow_dispatch` 的 `ffmpeg_ref`/`mpv_ref` 在 "Override ffmpeg/mpv refs" 步骤里 sed 改 `depinfo.sh` / `download-deps.sh`；
`patch.sh` 对 `buildscripts/patches/<dep>/*` 逐个 `git apply` 到 `deps/<dep>`；`libmpv-android-video-build.patch` 只改 build.sh/各 scripts 的编译旗标，**不含 javavm 补丁**
（javavm 补丁在上游仓库自带的 `patches/mpv/mpv_lavc_set_java_vm.patch`）。所以"换 mpv 时 javavm 要换掉"具体是：

1. **补丁目录替换**（在 Override 步骤里 `if: mpv_ref` 为 v0.41 时，`rm -rf patches/ffmpeg` 同处追加）：
   ```
   rm -f patches/mpv/mpv_lavc_set_java_vm.patch
   cp ../../mova-libmpv/patches/mpv-v041/000*.patch patches/mpv/
   ```
   `patch.sh` 按文件名字典序 `git apply`，`0001`（摘 gpu-next）/`0002`（javavm）/`0003`（whep 特判）顺序正确。`mova-libmpv/libmpv-android-video-build.patch` **本身不用动**（它没有 javavm 部分）。
2. **`mpv_ref` 要传 tag/hash**：现 sed 把旧 hash 替换为 `$MPV_REF`，`download-deps.sh` 里是 `git clone` 后 `git reset --hard $MPV_REF`，传 `v0.41.0` 可用（克隆带 tag，**推断，未在 CI 跑**）。
3. **mpv.sh 要整体换**（v0.41 与旧 mpv 的 meson 选项不兼容；这是比 javavm 更大的改动）：
   - 去掉 `-Dlibplacebo=disabled`：v0.41 `meson.options` 里没有这个选项，`meson.build:29` 把 `libplacebo >= 6.338.2` 当**必选依赖**（实测）。
   - 新增 libplacebo 构建脚本（我本地用的是 `tools/libplacebo-eval/and-plc.sh`：静态、`-Dvulkan/d3d11/glslang/shaderc/lcms/dovi/libdovi/xxhash/unwind=disabled`，v7.360）并把它加入 `depinfo.sh` 的 `dep_mpv`。
   - mpv 选项用 `-Dauto_features=disabled` + 显式开 `gl/plain-gl/egl-android/android-media-ndk/opensles/audiotrack`（见 `local-build-arm64.sh`），否则 auto 会引入不需要的后端。
   - libplacebo 的 C++ 运行时需 `-lc++_static -lc++abi`（旧分支记录的 `__gxx_personality_v0` 坑）；本地产物未出现该未定义符号（实测）。
   - freetype 的 bz2 自动探测要处理（见 `tools/libplacebo-eval/README.md`，尚未做成补丁）。
4. **ffmpeg 补丁**：现 workflow 在设 `ffmpeg_ref` 时整个删掉 `patches/ffmpeg`（`dash_base_url_escape.patch`、`hls_mp4_seek.patch`，n9.0.2 上都打不上，是否被上游吸收未核实），这一点沿用即可。
5. **flavor**：`flavors-mova-slim.sh` 对 n9 需要的差异（**未改文件**，由本地脚本核实）：加 `--disable-iamf`；`--disable-postproc` 在 n9 不再存在（n9.0.2 的 configure 里已无 postproc 字样，实测 grep；本地脚本未传，构建通过）；`--enable-lto` 保持。
6. 缓存 key 已含 ffmpeg/mpv ref，无需再改。
7. 其他：`commit_artifact=false` 才能做实验构建，别回写 `packages/`。

## 上游构建链实跑（2026-10-02，arm64，T0.6 续）

**文件**：`buildscripts-v041.patch`（121 行，5 个文件，对「上游 1ecf510 + `libmpv-android-video-build.patch`」）、`apply-v041.sh`（套补丁 + 换 ffmpeg flavor + 换 mpv 补丁 + 删 n6 专用 ffmpeg 补丁）、`../../flavors-mova-slim-n9.sh`（n9 flavor：相对默认版只去 `--disable-postproc`、加 `--disable-iamf`；`--disable-bsfs`/`--disable-swscale-alpha` 默认版本来就有）。
补丁内容：`depinfo.sh` 加 `v_libplacebo=v7.360.0` 并让 `dep_mpv` 依赖 `libplacebo`；`download-deps.sh` 加 libplacebo 克隆（GitHub，递归子模块）；新 `scripts/libplacebo.sh`（最小静态，同 `tools/libplacebo-eval/and-plc.sh` 的开关）；`mpv.sh` 改 `-Dauto_features=disabled` + 显式开 `zlib/gl/plain-gl/egl-android/android-media-ndk/opensles/audiotrack`、去掉 `-Dlibplacebo=disabled/-Diconv/-Dvulkan`；`freetype.sh` 加 `-Dbzip2=disabled`（2-13-0 的 meson 有该选项且生效，**不需要** `patches/freetype-2.13.3` 那个源码补丁，已实测）。`depinfo.sh` 的 `v_ffmpeg`/`v_mpv` 不动，由 CI Override 步骤覆盖。

**复现（本地 WSL）**：clone 上游 → `git apply libmpv-android-video-build.patch` → `apply-v041.sh <root>` → `sed` 把 `v_ffmpeg` 改 `9.0.2`、旧 mpv hash 改 `v0.41.0`（depinfo.sh + include/download-deps.sh）→ NDK r25c 软链到 `buildscripts/sdk/android-sdk-linux/ndk/25.2.9519653` → `download-deps.sh` → `patch.sh` → `build.sh --arch arm64 mpv`。
本机额外处理：videolan/gnome/freedesktop 的 git 源在 WSL 有 CA 问题，用 `GIT_CONFIG_*` 的 `url.<github镜像>.insteadOf` 重定向（不改脚本、不绕过证书校验）；装了 autoconf/automake/libtool（libass、libxml2 需要）。libxml2 的 autogen 会打印 `cannot run C compiled programs`，**不致命**（`|| true` 级别的预配置步骤），后续真正的交叉 configure 正常。

**结果（实测）**：`patch.sh` 通过，整条链（mbedtls 3.4.0、dav1d 1.2.0、libxml2、ffmpeg n9.0.2、freetype/fribidi/harfbuzz/libass、libplacebo v7.360.0、mpv v0.41.0）一次构建成功（arm64 API21，crossfile 自带 LTO）。
- 未 strip 31,325,816 字节；`llvm-strip -s` 后 **6,319,792 字节**。
- 导出符号（`llvm-nm -D`）共 55 个，含 `mpv_lavc_set_java_vm`、`mpv_create_weak_client`、`mpv_wait_event`；四个 `ff_{h264,hevc,vp9,av1}_mediacodec_decoder` 均在（局部符号，非导出，与本地脚本一致）；`ff_libdav1d_decoder` 在；无 `gpu-next` 字符串；无 `__gxx`/`BZ2_` 未定义。NEEDED：libandroid/libEGL/libm/libmediandk/libdl/libOpenSLES/libc。

**与 §本地构建 LTO 行对比**：本地手工脚本 LTO 6,753,456；上游链 6,319,792，**小 433,664（-6.4%）**。
归因（**推断，未逐项量化**）：上游链依赖版本更旧更小（libass 0.17.1/harfbuzz 7.2.0/fribidi 1.0.12/freetype 2-13-0/mbedtls 3.4.0，本地是 0.17.4/10.4.0/1.0.16/2.13.3/3.6.7）；链接参数不同（上游无 version script，改用 `-fvisibility=hidden` + `--exclude-libs,ALL`；API21 vs 本地 API24）；上游依赖全部 `-Os -flto` 并带 `--icf=safe`。本地脚本与上游链的 dav1d（1.2.0、`-Dbitdepths=8`）、ffmpeg 配方一致，所以 dav1d 不是差异来源。相对仓库现行 6,050,104（n6.0.1 默认 flavor）为 +269,688（+4.5%），与 android-size-measure.md §7 的"n9 比 n6 大约 +5%"同量级（(d) 行 +7.7% 未含老依赖的优势）。
**未验证**：真机播放/MediaCodec 硬解/WHEP；其余三个 ABI；CI 里实跑（workflow 未改）；mpv 的 zlib 开关对体积的单独影响没量。

## WHEP 变体（`WHEP=1 apply-v041.sh <root>`）

额外套：`whep-android.patch`（mbedtls.sh 开 `MBEDTLS_SSL_DTLS_SRTP`）、ffmpeg 0001–0009、mpv 0003/0004，并给 ffmpeg flavor 加 `whep` demuxer 与 `dtls` 协议。不设 WHEP 则行为不变。实测数字见 [../../doc/notes/2026-10-02-android-whep-build-and-device.md](../../doc/notes/2026-10-02-android-whep-build-and-device.md)。
