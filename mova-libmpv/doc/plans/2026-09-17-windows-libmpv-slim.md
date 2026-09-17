# Windows `libmpv-2.dll` 编译器/链接器级瘦身 — 执行计划（2026-09-17）

> **执行者说明**：本计划由 opus 定架构，交 sonnet 逐步执行。**每个 Task 是一次独立
> commit + 一次 CI run + 一次体积实测**，不允许把多个 Task 合并成一次推送——
> 本项目已经在 Windows 上吃过一次"三个变量一起改，体积反而从 34.62MiB 涨到 53.53MiB、
> 回滚拆开重测才定位到真凶"的亏（见 [../../README.md](../../README.md) "极限压缩实验记录"）。
> 遇到本计划没覆盖的判断（某个库源码构建报缺依赖、某个 flag 让链接失败），
> **停下来，把报错原样记录到"执行记录"一节**，不要自行 improvise 换库或加依赖。

只改 `.github/workflows/build-mova-libmpv.yml` 的 `windows` job（文件第 843 行起）
与文档。**不动 `linux` job、不动 `lib/`、不动 `flavors-mova-slim*.sh`。**

## 0. 这个计划要回答的问题

**"Windows 的 `libmpv-2.dll` 在不砍功能的前提下，补齐 Android 那一层编译器/链接器
手段 + 把 pacman 预编译依赖换成源码构建，能从 14.66 MiB 瘦到多少？"**

### 0.1 基线（今日实测）

| 参照物 | 字节 | MiB | 说明 |
|---|---:|---:|---|
| media_kit 官方预编译 `libmpv-2.dll` | 29,764,622 | 28.4 | `libmpv-win32-video-build` 2023-09-24 发行版解压实测。同为"单个自包含静态链接 DLL"，策略跟我们一样，只是完全没裁剪（GPL + 完整 libplacebo/vulkan） |
| **本 job 当前产物**（`dist/windows-x86_64/libmpv-2.dll`） | **15,368,704** | **14.66** | 相对官方 **−48%**。这是起点，不是问题 |
| 本地 MSYS2 cmake 构建链（另一套配方，不可比） | 28,274,176 | 26.97 | 见 README "Windows 瘦身构建"一节，带完整 libplacebo/vulkan，跟本 job 不是同一套东西 |
| Linux job（同一份 ffmpeg configure 清单，依赖走 apt **动态**链接） | 8,189,568 | 7.81 | **本计划最重要的对照系**，见 §0.2 |
| Android arm64-v8a 定稿 | 6,044,040 | 5.76 | 已吃满编译器/链接器手段 |

### 0.2 14.66 MiB 是怎么构成的（推断，Task 0 负责证伪/证实）

`linux` job 和 `windows` job 用的是**同一份 ffmpeg 组件清单、同一个 mpv commit**，
唯一结构差异是：Linux 的 libass/freetype/harfbuzz/fribidi/dav1d/mbedtls 走 apt 的
**共享库**（代码字节不在 `libmpv.so` 里），Windows 走 `--prefer-static` 把 pacman 的
**静态归档全部吸进 DLL**。

> 14.66 MiB（Windows，含依赖） − 7.81 MiB（Linux，不含依赖） ≈ **6.8 MiB 是被静态
> 吸进来的第三方依赖**。

这个减法直接决定了本计划的优先级排序：**"给 ffmpeg/mpv 加 flag"最多只能动那 7.8 MiB
那一半，真正的大头（6.8 MiB）在 pacman 预编译库上**——它们是发行版通用优化产物
（`-O2`、带 tools/tests/全 bitdepth/全 ASM、无 `-ffunction-sections`），我们从来
没有对它们做过任何体积控制。所以 Task 4–6（源码重建依赖）的量级预期高于 Task 2–3。

### 0.3 Android 的手段清单，逐条判定是否适用于 Windows

| Android 手段 | Windows 适用 | 依据 |
|---|---|---|
| `-ffunction-sections -fdata-sections` + `-Wl,--gc-sections` | ✅ 适用 | 跟 ELF 同机制，mingw ld 支持。Linux 实测这一组（含 visibility）−4.6% |
| `-Os`（meson `buildtype=minsize`） | ✅ 适用 | 当前 mpv meson **完全没传 `-Dbuildtype`**，默认是 `debugoptimized`（`-O2` + `debug=true` + 保留 assert），跟 Linux 那次"漏配置"是同一个洞 |
| `-fomit-frame-pointer` | ✅ 适用 | 低风险，随 cflags 一起带 |
| `-fvisibility=hidden(-inlines-hidden)` | ❌ **不做** | **已在 Windows 上实测过，byte-for-byte 零变化**（README "极限压缩实验记录"）。PE/COFF 的 DLL 默认**不**导出符号，必须 `__declspec(dllexport)`（mpv 的 `MPV_EXPORT` 宏）才进导出表——这个 flag 在 Windows 上是在解决一个不存在的问题。加了只会多一个变量 |
| `-flto` 全链路 | ⚠️ 排到最后，独立 Task | Linux 上实测**失败**（ffmpeg NASM 目标文件与 LTO bitcode 混链报 `R_X86_64_PC32 ... recompile with -fPIC`）；Windows PE 没有这条 `-fPIC` 约束，理论上可行，但 MinGW 的 `ar` 缺 LTO plugin 是本项目踩过的已知坑。收益不确定、失败概率实打实，单独一个可回滚 Task |
| `-Wl,--icf=safe` | ❌ 不做 | Linux 实测 gold+ICF 反而 **+8,544 字节**；MinGW 的 bfd ld 也不支持 `--icf` |
| `-Wl,-z,max-page-size=16384` | ❌ 不适用 | ELF 专属，PE 无此概念 |
| `default_library = 'static'` | ✅ 已具备 | 本 job 的 `--prefer-static` 已经是这个语义 |

### 0.4 明确不在范围内（不要做）

- 不动 `linux` job（见 §9 后续项登记）。
- 不改 mpv/ffmpeg 源码（物理删代码，跟 iOS/Windows 已评估并放弃的方向同级）。
- 不上 UPX（DLL 加壳的 `LoadLibrary`/Dart FFI 兼容性未验证，且杀软误报）。
- 不换 ffmpeg/mpv 版本（`n6.0.1` + mpv `78d43740f5` 这对配对是踩过 binutils≥2.41
  内联汇编坑之后定下来的，不要动）。
- 不砍任何 decoder/demuxer/protocol/bsf——**本计划是纯编译期手段，功能范围零变化**。
  功能取舍是另一份文档的事。

## 1. 贯穿全程的三条硬规则

**规则 A：一个 Task = 一个变量 = 一次 CI run = 一个体积数字。**
每个 Task 的 commit message 末尾带上实测字节数，例如
`perf(mova-libmpv): windows ffmpeg -ffunction-sections (15,368,704 → X B)`。
CI 的 "Strip and verify" 步骤已经把字节数写进 `$GITHUB_STEP_SUMMARY`，直接抄。

**规则 B：从源码构建某个依赖之后，必须把对应的 pacman 包卸掉。**
否则 `PKG_CONFIG_PATH` 里 `/mingw64/lib/pkgconfig` 仍然命中发行版版本，链接的还是老
库，而你会看到"体积没变"并错误地下结论"这个手段没用"。卸掉之后一旦路径配错就是
**硬链接错误**，不会静默走错分支。做法见各 Task。

**规则 C：体积变小 ≠ 成功。**每个 Task 都要过 §7 的符号/自包含核验清单。
"DLL 变小了但字幕渲染没了"这种事在本项目的 Windows 线上真实发生过
（README "修复了一个比体积更重要的功能缺口"：34.62 MiB 的产物**一个视频编码都放不了**，
编译期零报错）。

## 2. Task 0：建立体积归因基线（零体积变化，纯测量）

**改的文件**：`.github/workflows/build-mova-libmpv.yml`（`windows` job 的
"Build mpv" 与 "Strip and verify" 两步）

要先知道 14.66 MiB 里每个输入归档各占多少字节，否则后面每个 Task 都是在盲猜量级。
用链接器 map 文件做归因。

### 2.1 mpv meson 加 map 输出

`-Dc_link_args` **当前已经有值，必须追加而不是替换**（`-lstdc++ -ldwrite -lole32
-lrpcrt4` 少一个都链不过，见该步已有注释）：

```yaml
          meson setup build --prefix="$WS/prefix" --libdir=lib --default-library=shared \
            --prefer-static \
            -Dc_link_args="-lstdc++ -ldwrite -lole32 -lrpcrt4 -Wl,-Map=$WS/libmpv.map" \
            -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false
```

### 2.2 "Strip and verify" 步骤追加归因输出

在 `strip -s "$DLL"` **之前**插入：

```bash
          # 体积归因：按输入归档（.a / .o）汇总 GNU ld map 里各 input section 的字节数。
          # map 行形如 " .text          0x0000000000401000     0x1234 /mingw64/lib/libharfbuzz.a(hb-blob.o)"
          # section 名过长时 ld 会把地址/大小换行到下一行，故对孤立 section 名行做续行拼接。
          if [ -f "$WS/libmpv.map" ]; then
            echo "### 体积归因（按输入归档，链接期字节，未 strip）" >> "$GITHUB_STEP_SUMMARY"
            echo '```' >> "$GITHUB_STEP_SUMMARY"
            awk '
              /^ \.[^ ]+$/ { pending=1; next }
              {
                if (pending) { line = " x " $0; pending = 0 } else { line = $0 }
                n = split(line, f, /[ \t]+/)
                if (n >= 5 && f[3] ~ /^0x/ && f[4] ~ /^0x/ && f[5] ~ /\.(a|o)/) {
                  obj = f[5]; sub(/\(.*/, "", obj)
                  size[obj] += strtonum(f[4])
                }
              }
              END { for (o in size) printf "%12d  %s\n", size[o], o }
            ' "$WS/libmpv.map" | sort -rn | head -40 >> "$GITHUB_STEP_SUMMARY"
            echo '```' >> "$GITHUB_STEP_SUMMARY"
          else
            echo "::warning::libmpv.map 未生成，体积归因缺失（检查 -Wl,-Map 是否被 meson 吞掉）"
          fi

          # 自包含核验：本产物的卖点是"单个 DLL、不拖 MSYS2 运行时"。
          echo "### DLL 导入表" >> "$GITHUB_STEP_SUMMARY"
          objdump -p "$DLL" | grep -i 'DLL Name' | sort -u >> "$GITHUB_STEP_SUMMARY"
```

### 2.3 验证步骤 / 成功判据

- 跑一次 CI，`libmpv-2.dll` 字节数**必须仍是 15,368,704**（map 输出不改变代码生成；
  若变了说明 meson 把 `-Dc_link_args` 覆盖掉了别的东西，先查清再往下走）。
- Step Summary 里拿到归因表，**把前 15 行抄进本文件 §12 执行记录**。这张表是后面
  每个 Task "预估收益"的真实依据。
- 导入表里若出现 `libstdc++-6.dll` / `libgcc_s_seh-1.dll` / `libwinpthread-1.dll` /
  `libdav1d*.dll` / `libass*.dll` 中的任何一个，**这是比体积更严重的功能缺陷**——
  出货的 DLL 会在用户机器上因找不到 MSYS2 运行时而 `LoadLibrary` 失败。
  记录下来，在 Task 1 之前先用 `-static-libgcc -static-libstdc++` 补进
  `-Dc_link_args` 修掉（这会**增大**体积，但正确性优先；并且它解释了为什么产物
  会从历史上的 6.58 MiB 涨到 14.66 MiB 的一部分）。
- **待回答的历史疑点**：README "多平台进度" Windows 行记录过一次 CI 产物
  6,904,180 字节（6.58 MiB），而当前 `dist/` 里是 15,368,704 字节。两者差 8.4 MiB，
  跟 §0.2 推断的"依赖被静态吸进来"量级吻合。Task 0 的归因表 + 导入表应该能一次性
  给出答案（当年那份大概率是**动态**链接了 pacman DLL 的非自包含产物）。
  把结论写进执行记录，README 那一行的 6.58 MiB 说法届时要一起改掉。

## 3. Task 1：TLS 后端 mbedtls → SChannel（预期收益/成本比最高的一步）

**改的文件**：`.github/workflows/build-mova-libmpv.yml`（`setup-msys2` 的 install
列表 + ffmpeg configure）

mbedtls 是 vendored 的第三方密码学库，被整个静态吸进 DLL；SChannel 是 Windows 系统
自带的 TLS 实现，ffmpeg 在 mingw 目标下**默认就支持**，零额外字节。本项目已经在
两条线上验证过这个思路：iOS 换 securetransport、Windows 本地构建换 SChannel
（README 实测 **−7.68 MiB**，那次换掉的是体量更大的 openssl，此处是 mbedtls，
量级会小很多，但方向确定）。

### 3.1 改动

```diff
             mingw-w64-x86_64-dav1d
-            mingw-w64-x86_64-mbedtls
             mingw-w64-x86_64-zlib
```

```diff
-            --disable-gpl --disable-nonfree --enable-version3 \
+            --disable-gpl --disable-nonfree \
             --enable-static --disable-shared --pkg-config-flags=--static \
             --disable-doc --disable-programs --disable-avdevice --disable-postproc \
             --disable-muxers --disable-decoders --disable-encoders --disable-demuxers \
             --disable-parsers --disable-protocols --disable-devices --disable-filters \
             --enable-small --enable-optimizations \
-            --enable-mbedtls --enable-zlib --enable-libdav1d \
+            --enable-schannel --enable-zlib --enable-libdav1d \
```

**`--enable-version3` 一并去掉**：它当初只是为了兼容 mbedtls 的 Apache-2.0/GPL-2.0
双授权而必须开的。换成系统 API 之后，本产物的许可证从 **LGPLv3 降回 LGPLv2.1**——
跟 Linux 那次 mbedtls→openssl、iOS 那次 mbedtls→securetransport 拿到的是同一个收益。
**这是合规收益，不是体积手段，但顺手就能拿到，不要漏。**

### 3.2 验证

- 体积：预期 −0.3 ~ −0.8 MiB。
- **`configure` 摘要必须出现 `schannel` 且 `License: LGPL version 2.1 or later`**。
  在 configure 之后加一行断言，别靠肉眼看日志：
  ```bash
          ./configure ... 2>&1 | tee "$WS/ffconf.log"
          grep -q 'License: LGPL version 2.1' "$WS/ffconf.log" \
            || { echo "::error::许可证不是 LGPLv2.1，schannel 替换没生效或引入了 version3 组件"; exit 1; }
  ```
- **功能回归风险（必须核验）**：`https`/`tls`/`rtmps` 协议依赖 TLS 后端。
  configure 摘要的 `Enabled protocols` 里 `https`、`tls`、`rtmps` 三项**必须还在**。
  若消失说明 SChannel 没被认出来——**立刻回滚这个 Task，不要往下走**，
  静默丢掉 HTTPS 比多 0.5 MiB 严重得多。
- 失败信号：产物变小但 `https` 从协议列表里消失 = 假成功。

## 4. ~~Task 2：ffmpeg 加分节编译参数~~ ——已废弃，实测净负收益 +124%，不要做

> **2026-09-17 本地验证已推翻本 Task**：给 ffmpeg 加 `-ffunction-sections
> -fdata-sections` 不是预测的 ±0，而是让最终产物从 14.70MiB 炸到
> **32.58MiB（+124%）**——`libavcodec.a` 单独从 27.5MB 涨到 32.9MB（+20%），
> 根源是 COFF 格式下逐函数分节的 section 头/重定位开销，在 ffmpeg 这种
> "几乎全部代码都真实被调用、没有死代码可回收"的库上是纯负担，
> `--gc-sections` 完全补不回来。**跳过本 Task，直接进 Task 3。**
> 完整数据见 §12 执行记录"发现 2"。以下原方案内容保留仅供追溯，不要执行。

**改的文件**：~~`.github/workflows/build-mova-libmpv.yml`（ffmpeg configure）~~（已废弃）

```diff
             --enable-small --enable-optimizations \
+            --extra-cflags="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
             --enable-schannel --enable-zlib --enable-libdav1d \
```

### 4.1 三个必须写清楚的要点

1. **这一步单独不会省体积，甚至可能微涨。** `-ffunction-sections -fdata-sections`
   只是把代码拆进独立 section，真正的回收动作是链接期的 `--gc-sections`——
   而 ffmpeg 在本 job 里是 `--enable-static --disable-shared`，**它自己根本不做最终
   链接**，`--extra-ldflags="-Wl,--gc-sections"` 加了也是空转（只会作用于被
   `--disable-programs` 关掉的 ffmpeg 可执行文件）。**收割在 Task 3 的 mpv 链接那一步。**
   Android 之所以两边都写，是因为它那套 buildscripts 的 `LDFLAGS` 是全局导出的。
   这里不照抄，写进注释避免后人以为漏了。
2. **不加 `-fvisibility=hidden`**，理由见 §0.3（Windows 已实测零收益）。
3. **不加 `-Os`**：`--enable-small` 就是 ffmpeg 自己的 `-Os` 开关，已经在参数里了，
   重复传只会跟它内部的优化级别逻辑打架。

### 4.2 验证

- 体积：预期 **−0.05 ~ +0.15 MiB（基本持平或微涨）**。**微涨是正常的、预期内的**，
  不要因此回滚——它是 Task 3 的前置条件。若涨超过 0.3 MiB，记录下来，
  说明 section 碎片开销异常，需要在 Task 3 之后复查这两步的合并净效果。
- `ffconf.log` 里确认 cflags 真的进去了：`grep -- '-ffunction-sections' "$WS/ffconf.log"`。
- 符号核验照常（§8）。

## 5. Task 3：mpv meson 补齐 `minsize` + 分节 + `--gc-sections`

**改的文件**：`.github/workflows/build-mova-libmpv.yml`（mpv `meson setup` 那一步）

这是**当前配方里最明显的一个"漏配置"**：mpv 的 meson 从来没传过 `-Dbuildtype`，
默认 `debugoptimized` = `-O2` + `debug=true` + `b_ndebug=false`（assert 全保留）。
Linux 线补上这一组实测 −286,624 字节（−3.7%），另一组分节/gc 实测 −368,608 字节
（−4.6%，其中含 visibility 的贡献，Windows 拿不到那部分）。

### 5.1 改动

Android 用的是 cross file 的 `[built-in options]`；Windows 是 **runner 上的原生构建，
没有 cross file**，等价机制就是 `meson setup` 的 `-D<option>=` 命令行内建选项
（`c_args`/`cpp_args`/`c_link_args`/`cpp_link_args`/`buildtype`/`b_ndebug` 全都是
meson 的 built-in options，命令行传和写进 cross/native file 完全等价）。

```yaml
          meson setup build --prefix="$WS/prefix" --libdir=lib --default-library=shared \
            --prefer-static \
            -Dbuildtype=minsize -Ddebug=false -Db_ndebug=true \
            -Dc_args="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
            -Dcpp_args="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
            -Dc_link_args="-lstdc++ -ldwrite -lole32 -lrpcrt4 -Wl,--gc-sections -Wl,-Map=$WS/libmpv.map" \
            -Dcpp_link_args="-Wl,--gc-sections" \
            -Dgpl=false -Dlibmpv=true -Dcplayer=false -Dtests=false
```

要点：

- **`-Ddebug=false` 不能省**：`buildtype=minsize` 会顺手把 `debug=true` 打开，
  把 `-g` 编到目标文件里。iOS 和 Linux 两条线都踩过这个坑。
  （strip 之后看不出来，但会拖慢链接、干扰 LTO。）
- **`-Db_ndebug=true`**：去掉运行期 assert 的代码体积，`minsize` 本身不会自动开。
- **`-Dc_link_args` 是追加不是替换**：原有的 `-lstdc++ -ldwrite -lole32 -rpcrt4`
  一个都不能丢（静态 libharfbuzz.a 是 C++ 且用 DirectWrite，libmpv 是 C 目标，
  C 驱动不会自动带这些）。
- **必须是干净的 build 目录**：meson 把这些内建选项缓存在 build dir 里，
  CI 每次都是全新 checkout，天然满足；本地复现时记得 `rm -rf build`。

### 5.2 验证

- 体积：预期 **−0.6 ~ −1.2 MiB**（Task 2+3 合起来算，Linux 同类手段合计 −8%，
  Windows 扣掉 visibility 那份，按 −7% 估在 ffmpeg+mpv 那 7.8 MiB 上）。
- **`--gc-sections` 是本计划里第一个真正有"静默砍掉活代码"风险的 flag。**
  §8 的完整符号核验清单从这个 Task 开始**必须**每次都跑，不能只跑现有的 `dav1d_open`。
- 失败信号：体积明显下降但 `mpv_create`/`ass_library_init`/`hb_shape` 任一符号消失。

## 6. Task 4–6：把 pacman 预编译依赖换成源码构建

### 6.0 通用做法（三个 Task 共用）

这些库的源码在本 job 里**跟 ffmpeg/mpv 一样现拉现编**（该 job 已经在
"Download ffmpeg and mpv sources" 步骤这么做了，结构照抄即可），统一装进
**同一个 `$WS/prefix`**，而 mpv 的 `PKG_CONFIG_PATH` 已经是
`"$WS/prefix/lib/pkgconfig:/mingw64/lib/pkgconfig"`——**我们的 prefix 排在前面，
pkg-config 会优先命中自建版本**。

但"优先命中"不够（规则 B）：每个 Task 都要把被替换的 pacman 包卸掉，
让配错路径变成硬错误：

```bash
      - name: Drop pacman copies of the libs we now build ourselves
        run: |
          # -dd 跳过依赖检查：这些包是 mingw-w64-x86_64-libass 的依赖，
          # 正常 -R 会因为反向依赖而拒绝。我们要的就是"彻底没有第二份"。
          pacman -Rdd --noconfirm mingw-w64-x86_64-dav1d || true
```

统一的源码构建参数模板（meson 系）：

```bash
          meson setup _build --prefix="$WS/prefix" --libdir=lib \
            --default-library=static --buildtype=minsize \
            -Ddebug=false -Db_ndebug=true \
            -Dc_args="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
            -Dcpp_args="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
            <包专属选项>
          ninja -C _build
          ninja -C _build install
```

**注意这里不写 `-Db_lto=true`**——LTO 统一留到 Task 7 一次性打开，保持"一个 Task
一个变量"。

---

### 6.1 Task 4：dav1d 从源码构建

pacman 的 `mingw-w64-x86_64-dav1d` 带 `dav1d.exe` 工具、测试、全 bitdepth、
全 SIMD 变体，是发行版通用配置。

```yaml
      - name: Build dav1d from source (static, minsize)
        run: |
          pacman -Rdd --noconfirm mingw-w64-x86_64-dav1d || true
          git clone --depth 1 --branch 1.2.1 https://code.videolan.org/videolan/dav1d.git dav1d-src
          cd dav1d-src
          meson setup _build --prefix="$WS/prefix" --libdir=lib \
            --default-library=static --buildtype=minsize \
            -Ddebug=false -Db_ndebug=true \
            -Denable_tools=false -Denable_tests=false -Denable_examples=false \
            -Dbitdepths=8,16 \
            -Dc_args="-ffunction-sections -fdata-sections -fomit-frame-pointer"
          ninja -C _build
          ninja -C _build install
```

**`-Dbitdepths` 是一个功能决策，不是免费收益，必须显式表态**：Android 那边设的是
`-Dbitdepths=8`（只留 8-bit，放弃 10-bit AV1）。**Windows 这里保留 `8,16`**——
桌面端 AV1 内容里 10-bit/HDR 的占比远高于移动端，为了省几百 KB 让 10-bit AV1 直接
放不了，代价不对等（参考本项目 AV1 软解那次"真机翻车后改判加回来"的教训：
播放失败比体积大更糟）。若后续有实测数据表明 mova 的内容源里没有 10-bit AV1，
再单独开一个 Task 改成 `8`。

**验证**：预期 −0.4 ~ −0.8 MiB。除现有 `dav1d_open` 检查外，
额外断言 `$WS/prefix/lib/libdav1d.a` 存在（证明真的用了自建版本），
并确认 DLL 导入表里**没有** `libdav1d*.dll`。

---

### 6.2 Task 5：freetype / fribidi / harfbuzz 从源码构建

三个都是 meson 项目，但**构建顺序有硬约束**：harfbuzz 需要 freetype，
freetype 的 harfbuzz 支持（只影响自动 hinting 质量）是可选的——
用标准破环顺序 **freetype（不带 harfbuzz）→ fribidi → harfbuzz（带 freetype）**，
不做 freetype 的第二轮重建（收益是字体 hinting 微调，不值得多一轮构建）。

```yaml
      - name: Build freetype / fribidi / harfbuzz from source (static, minsize)
        run: |
          pacman -Rdd --noconfirm mingw-w64-x86_64-harfbuzz mingw-w64-x86_64-fribidi mingw-w64-x86_64-freetype || true
          export PKG_CONFIG_PATH="$WS/prefix/lib/pkgconfig:/mingw64/lib/pkgconfig"
          COMMON="--prefix=$WS/prefix --libdir=lib --default-library=static --buildtype=minsize -Ddebug=false -Db_ndebug=true"
          CARGS="-ffunction-sections -fdata-sections -fomit-frame-pointer"

          # 1) freetype（先不带 harfbuzz，破循环依赖）
          git clone --depth 1 --branch VER-2-13-2 https://gitlab.freedesktop.org/freetype/freetype.git freetype-src
          meson setup freetype-src/_build freetype-src $COMMON \
            -Dharfbuzz=disabled -Dbrotli=disabled -Dbzip2=disabled -Dpng=disabled \
            -Dzlib=system -Dc_args="$CARGS"
          ninja -C freetype-src/_build install

          # 2) fribidi（bin/docs/tests 全关——它的 CLI 工具是纯构建期产物）
          git clone --depth 1 --branch v1.0.13 https://github.com/fribidi/fribidi.git fribidi-src
          meson setup fribidi-src/_build fribidi-src $COMMON \
            -Ddocs=false -Dtests=false -Dbin=false -Dc_args="$CARGS"
          ninja -C fribidi-src/_build install

          # 3) harfbuzz（带 freetype；glib/gobject/icu/cairo/chafa 全关，
          #    它们只服务 harfbuzz 自己的 CLI 工具与集成场景，libass 用不到）
          git clone --depth 1 --branch 8.3.0 https://github.com/harfbuzz/harfbuzz.git harfbuzz-src
          meson setup harfbuzz-src/_build harfbuzz-src $COMMON \
            -Dtests=disabled -Ddocs=disabled -Dbenchmark=disabled -Dutilities=disabled \
            -Dglib=disabled -Dgobject=disabled -Dicu=disabled -Dcairo=disabled -Dchafa=disabled \
            -Dfreetype=enabled -Dc_args="$CARGS" -Dcpp_args="$CARGS"
          ninja -C harfbuzz-src/_build install
```

要点：

- **harfbuzz 大概率是这三个里最肥的**（C++，pacman 版还带 icu/glib/gobject/cairo
  一整圈可选后端）。Task 0 的归因表会给出确切数字——**按那张表的实际排序决定要不要
  拆成两个 Task**（若 harfbuzz 单独超过 2 MiB，值得为它单独一次 CI run）。
- **`-Ddirectwrite` 保持默认（enabled）**：libass 在 Windows 上靠 DirectWrite 做
  系统字体枚举，关掉会导致"没有外挂字体文件时字幕无字体可用"——
  这是功能，不是体积。`-ldwrite` 这个链接参数因此必须保留。
- **不把 `-Db_lto` 写进来**（Task 7 统一处理）。Android 那边 fribidi 必须
  `-Db_lto=false` 是因为它交叉编译时构建期码表生成器被 cross file 的 LTO 污染；
  Windows 是原生构建，**不存在 native/cross 分裂，这个坑天然不存在**，
  不用照抄 `--native-file` 那套机制。

**验证**：预期 −0.8 ~ −1.5 MiB。核验 `libfreetype.a`/`libfribidi.a`/`libharfbuzz.a`
三个文件都在 `$WS/prefix/lib/`，且 `pkg-config --variable=prefix harfbuzz` 返回
的是 `$WS/prefix` 而**不是** `/mingw64`（这条断言直接抓"改了但没生效"）：

```bash
          test "$(pkg-config --variable=prefix harfbuzz)" = "$WS/prefix" \
            || { echo "::error::harfbuzz 仍然解析到 pacman 版本，源码构建没生效"; exit 1; }
```

---

### 6.3 Task 6：libass 从源码构建（autotools）

libass 走 autotools，不吃 meson 的 `buildtype`，跟 Android 一样直接给 CFLAGS
（**去掉 `-fPIC`（Windows 无意义）和 `-fvisibility=hidden`（PE 零收益）**，
其余照抄 Android 的那串）：

```yaml
      - name: Build libass from source (static, minsize)
        run: |
          pacman -Rdd --noconfirm mingw-w64-x86_64-libass || true
          export PKG_CONFIG_PATH="$WS/prefix/lib/pkgconfig:/mingw64/lib/pkgconfig"
          git clone --depth 1 --branch 0.17.1 https://github.com/libass/libass.git libass-src
          cd libass-src
          ./autogen.sh
          ./configure --prefix="$WS/prefix" \
            --disable-shared --enable-static \
            --disable-test --disable-profile --disable-fontconfig \
            CFLAGS="-Os -ffunction-sections -fdata-sections -fomit-frame-pointer" \
            CXXFLAGS="-Os -ffunction-sections -fdata-sections -fomit-frame-pointer"
          make -j"$(nproc)"
          make install
```

- **`--disable-asm` 不加**（Android 加了是因为 NDK 汇编器兼容性；
  MSYS2 有 nasm 且 job 已经装了，x86_64 上保留 ASM 对字幕渲染性能有实际意义）。
- **`--disable-fontconfig`**：Windows 上字体枚举走 DirectWrite，fontconfig 是
  Linux 路线，pacman 的 libass 大概率带着它（连带一整个 fontconfig+expat）。
  这条可能是本 Task 收益的主要来源。
  **但要核验**：configure 摘要必须显示 DirectWrite 字体后端是 enabled，
  否则就是"两个字体后端都没了"= 字幕彻底没字体。

**验证**：预期 −0.1 ~ −0.3 MiB（若 pacman 版确实拖着 fontconfig，可能到 −0.5）。
必须核验 `ass_library_init`/`ass_renderer_init`/`ass_set_fonts` 符号在，
且 configure 输出里 DirectWrite 后端 enabled。

---

### 6.4 明确不做源码构建的库（附理由）

| 库 | 判定 | 理由 |
|---|---|---|
| **mbedtls** | **整个去掉**，不是源码重建 | Task 1 已换成系统 SChannel，零字节且许可证更宽松。源码重建它是白费功夫 |
| **zlib** | 不做 | pacman 静态 `libz.a` 本身只有百 KB 级，`-Os` 重建最多省几十 KB，不值一次 CI run。**等 Task 0 的归因表；若它意外超过 300 KB，再单开 Task** |
| **libstdc++ / libgcc** | 不做 | 工具链自带运行时，MSYS2 不提供"用自定义 flag 重建 libstdc++"的实际可行路径（要重编整个 GCC）。真要减这块，方向是让 harfbuzz 少用 C++ 特性，不是重建运行时 |
| **libplacebo / vulkan / shaderc** | 不适用 | **本 job 压根没装、没构建这些**（跟本地那套 cmake 构建链的 26.97 MiB 版本最大的结构差异就在这里）。这是本 job 已经比官方 28.4 MiB 小一半的主因之一 |

## 7. Task 7：全链路 LTO（最后做，独立可回滚）

**风险最高、收益最不确定的一个 Task，所以排在最后**——前面每一步的收益都已经落袋，
这一步就算失败也不影响其余成果。

### 7.1 改动（ffmpeg + 各 meson 包 + mpv 一起开）

ffmpeg 侧：

```diff
             --enable-small --enable-optimizations \
+            --enable-lto \
+            --ar=gcc-ar --ranlib=gcc-ranlib --nm=gcc-nm \
             --extra-cflags="-ffunction-sections -fdata-sections -fomit-frame-pointer" \
```

各 meson 包（dav1d/freetype/fribidi/harfbuzz）与 mpv：追加 `-Db_lto=true`。
libass（autotools）：CFLAGS/CXXFLAGS 追加 `-flto`。

### 7.2 三个必须预先知道的 MinGW 坑

1. **`ar`/`ranlib` 必须换成 `gcc-ar`/`gcc-ranlib`**。GCC 的 LTO 字节码存在目标文件的
   特殊 section 里，plain `ar` 不加载 `liblto_plugin` 就不会为它们建符号索引，
   静态归档在最终链接时会退化成"没有 LTO 信息的胖目标文件"——**表现是构建成功、
   体积没变**（假阴性），不是报错。本项目在 Windows 上已经专门踩过一次
   `ar`/`ranlib`/LTO plugin 的坑（README 环境级踩坑第 3 条：MSYS2 只有 `gcc-ar`
   这类包装版本，且 `liblto_plugin.dll` 必须和它同目录，复制到别处就找不到）。
2. **NASM 目标文件与 LTO bitcode 混链**：Linux 上这条路是**实测失败**的
   （`R_X86_64_PC32 against undefined symbol 'bF8' ... recompile with -fPIC`）。
   但那个报错的根因是 **ELF 共享库要求全 PIC**；Windows PE 的 DLL 走 base relocation，
   没有这条约束，所以**理论上 Windows 能走通、Linux 不能**。这是个真问题，
   不是照抄的结论——跑出来才算数。
3. **`-fvisibility=hidden` 在其他平台上是 LTO 的放大器，这里没有**（§0.3）。
   所以不要期待 Android 那种 −521 KB 的跨库消除幅度，Windows 的导出面本来就窄，
   LTO 能多砍的死代码相应也少。

### 7.3 验证与退出条件

- 体积：预期 −0.5 ~ −1.2 MiB。
- **链接失败 / ICE / 链接超过 20 分钟 → 直接回滚整个 Task 7，把报错原文记进执行记录，
  结论写成"Windows 线不上 LTO"**。这跟 Linux 那次的处置一致（"收益不明确、有真实
  链接失败风险，不值得为未知的小体积收益继续折腾，放弃"）。不要为了让 LTO 跑通而
  去动 ffmpeg 的汇编配置或改用 `--disable-asm`——那会牺牲解码性能，得不偿失。
- **若体积零变化**：先怀疑 `gcc-ar` 没生效（第 1 条坑），用
  `nm --plugin "$(gcc -print-file-name=liblto_plugin.dll)" $WS/prefix/lib/libavcodec.a | head`
  确认归档里确实有 LTO 符号，再下"LTO 无收益"的结论。

## 8. 符号与功能核验清单（Task 3 起每次都跑）

**改的文件**：`.github/workflows/build-mova-libmpv.yml`（"Strip and verify" 步骤）

现有核验只有 `dav1d_open` 一条（外加 D3D11VA 走 configure 侧保证）。
加了 `--gc-sections` 和源码重建的依赖之后，这一条远远不够。扩成：

```bash
          # ---- 符号核验：--gc-sections / LTO 静默砍掉活代码的唯一防线 ----
          fail=0
          check_export () {  # $1=符号名 $2=人话说明
            objdump -p "$DLL" | grep -qw "$1" || nm --defined-only "$DLL" 2>/dev/null | grep -qw "$1" \
              || { echo "::error::缺少符号 $1（$2）"; fail=1; }
          }
          # mpv 公开 API（media_kit 直接调用，缺任何一个都是致命的）
          for s in mpv_create mpv_initialize mpv_command mpv_set_option_string \
                   mpv_render_context_create mpv_terminate_destroy; do
            check_export "$s" "mpv 公开 API"
          done

          # 内部但必须存活的依赖入口（strip 后不在导出表，用未 strip 的中间产物查）
          UNSTRIPPED=build/libmpv-2.dll   # ninja 产物，strip 前
          for s in dav1d_open ass_library_init ass_renderer_init ass_set_fonts \
                   hb_shape FT_Init_FreeType fribidi_get_par_embedding_levels_ex; do
            nm --defined-only "$UNSTRIPPED" 2>/dev/null | grep -qw "$s" \
              || { echo "::error::缺少内部符号 $s —— 对应依赖被 gc-sections/LTO 砍掉或根本没链进来"; fail=1; }
          done

          # D3D11VA 硬解（Windows 唯一硬解路径，configure 侧已开，这里确认真的进了产物）
          nm --defined-only "$UNSTRIPPED" 2>/dev/null | grep -q 'ff_d3d11va' \
            || { echo "::error::D3D11VA 硬解符号缺失"; fail=1; }

          # 自包含：不得依赖任何 MSYS2 运行时 DLL
          for bad in libdav1d libass libfreetype libharfbuzz libfribidi libmbed \
                     libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll; do
            objdump -p "$DLL" | grep -i 'DLL Name' | grep -qi "$bad" \
              && { echo "::error::产物导入了 $bad —— 不再自包含，用户机器上会加载失败"; fail=1; }
          done
          test "$fail" = 0 || exit 1
```

### 8.1 这份清单覆盖不到的东西（必须诚实登记，不要假装验完了）

上面全是**静态符号存在性**检查。它能抓住"链接器把东西砍没了"，
**抓不住**"字幕能渲染出来但位置/字体错了"这类运行期行为退化。
本项目的 `feedback_real_device_verification` 规则要求实测真实数字，
对应到这里的最低限度是：

- **每个 Task 之后只跑符号核验（CI 自动，成本为零）。**
- **全部 Task 做完、准备出货前，必须在一台真实 Windows 机器上跑一次
  `example` 应用的实际播放验证**：H.264/HEVC 播放 + D3D11VA 硬解生效
  + **外挂 ASS 字幕渲染（这是 libass/harfbuzz/freetype/fribidi 四个重建库唯一的
  真实出口，符号在不等于渲染对）** + 截图（png 编解码路径）。
  这四项没过，本计划的产物**不算可出货**，只算"CI 绿"。
  Windows 线至今**从未做过任何真机播放验证**（README 已登记为"性价比最高、
  也是唯一必须做的下一步"）——本计划不改变这个事实，只是又多了几个需要它来兜底的变更。
- 可选的低成本加固：在 job 里编一个几十行的 C 冒烟程序，链接 `libmpv-2.dll`，
  调 `mpv_create`→`mpv_initialize`→`mpv_set_option_string("vo","null")`→
  `mpv_terminate_destroy`，能抓住"导出表齐全但初始化就崩"这一类问题。
  runner 上无 GPU/无显示器，只能测到初始化层，**不能替代真机播放验证**。

## 9. 体积预测表（原始估算，**已被 §12 的本地实测结果推翻，仅供追溯**）

> **2026-09-17 更新**：以下预测表是本计划最初写就时的估算，**本地全流程验证
> 已经证明其中好几项预测错误**（Task 2 从"±0"变成实测"+124%"、Task 4/5 的
> `-ffunction-sections` 判断需要修正、Task 5 从"−800K~−1.5M"变成实测"0"，
> 且发现了预测表完全没覆盖的 `-Oz`（−1.57MB，全计划最大单项收益））。
> **要看真实数字，直接看 §12「最终验证结果」表，不要用这张表做决策。**
> 本表保留只是为了让后来者看到"最初以为会怎样"和"实测怎样"的落差，
> 本身就是一条值得记住的教训：**编译期体积优化必须逐项实测，类比其他平台/
> 项目的经验只能定方向，不能定数字，尤其是"分节编译"这类手段的收益/负收益
> 完全取决于目标代码库有多少真实死代码可回收，没有放之四海而皆准的预测。**

基于 §0.2 的拆分（ffmpeg+mpv ≈ 7.8 MiB / 静态依赖 ≈ 6.8 MiB）分别估算，
**不是拿 Android 的 −27% 直接乘**——Android 那 −27% 里贡献最大的
`-fvisibility=hidden`（−669 KB / −8%）在 Windows 上已实测为零，
而 Windows 独有的"从未被优化过的 pacman 依赖"这块 Android 早就自己从源码建了。
两边可省的部位根本不同。

| 阶段 | 作用部位 | 预计字节 | 预计 MiB | 累计 vs 14.66 |
|---|---|---:|---:|---:|
| 当前基线 | — | 15,368,704 | 14.66 | 基线 |
| Task 1 mbedtls → SChannel | 依赖 | −300K ~ −800K | ≈14.1 | −4% |
| Task 2 ffmpeg 分节 cflags | ffmpeg | ±0（可能微涨） | ≈14.1 | −4% |
| Task 3 mpv minsize + `--gc-sections` | ffmpeg+mpv | −600K ~ −1.2M | ≈13.2 | −10% |
| Task 4 dav1d 源码构建 | 依赖 | −400K ~ −800K | ≈12.6 | −14% |
| Task 5 freetype/fribidi/harfbuzz 源码构建 | 依赖 | −800K ~ −1.5M | ≈11.5 | −22% |
| Task 6 libass 源码构建 | 依赖 | −100K ~ −500K | ≈11.2 | −24% |
| Task 7 全链路 LTO（**可能为 0 或失败**） | 全部 | 0 ~ −1.2M | ≈10.5 | −28% |
| **落地目标区间** | | **9.8M ~ 12.3M** | **9.3 ~ 11.7** | **−20% ~ −36%** |

**期望值：≈10.5 MiB（−28%）**，对 media_kit 官方 28.4 MiB 是 **−63%**。

**明确不承诺追平 Android 的 5.76 MiB / iOS 的 5.96 MiB**——理由 README 已经论证过：
那两个平台的硬解走独立系统组件（MediaCodec / VideoToolbox），
Windows 的 D3D11VA 硬解是**寄生在软解 decoder 内部的**（跟 iOS VideoToolbox 同模式，
但 Windows 这边 h264/hevc 软解因此无法收窄成纯硬解），
且桌面端保留了 10-bit AV1、完整字幕字体栈。**把 14.66 MiB 跟 5.76 MiB 直接相除
去定目标是错的。**

## 10. 收尾：文档回写（Task 8）

本项目的约定是"完成一个 Task/里程碑并提交后**立刻**更新文档里的基线数字"
（见 [mova/CLAUDE.md](../../../mova/CLAUDE.md) 开发流程一节；这个数字过时会让
下一份规划文档从错误起点推导）。本计划涉及三处回写：

1. **`mova-libmpv/README.md` 的"多平台进度"表，Windows 那一行**（当前在第 24 行）：
   - 状态改成"✅ CI 跑通并完成编译器/链接器级瘦身"；
   - **把"产物 6,904,180 字节（≈6.58 MiB）"这个说法改掉**——
     它跟 `dist/windows-x86_64/libmpv-2.dll` 当前的 15,368,704 字节矛盾，
     Task 0 的归因/导入表会给出结论（大概率那份是非自包含的动态链接产物），
     把结论一并写进去；
   - 填入本计划的最终定稿字节数 + 相对 media_kit 官方 29,764,622 字节（28.4 MiB）
     的百分比；
   - 追加一句"真机播放验证仍未做"（§8.1，不要因为 CI 绿就把这个 TODO 抹掉）。
2. **`mova-libmpv/README.md` 新增一节 "Windows CI 线编译器/链接器瘦身
   （2026-09-17）"**，放在现有"Windows 瘦身构建（2026-08-13，MSYS2 本地构建链）"
   一节之后，内容是 §9 那张表的**实测版**（估算列换成真数字）+
   每个 Task 的意外发现。**特别是把"哪些 Android 手段在 Windows 上无效"
   写成结论性条目**（visibility 为零、ICF 无收益、LTO 成/败），
   这是下一个平台（Linux/macOS）接手时最省时间的东西。
3. **`dist/windows-x86_64/libmpv-2.dll`** 由 CI 的 "Commit built artifact to dist/"
   步骤自动回写（走 LFS，已修好 `git lfs push`），执行者不用手动放产物，
   但**要确认最后一次 run 的 commit 真的推上去了**（这一步历史上连环炸过三次）。

## 11. 范围外但登记在案：`linux` job 同样欠着这一层

`linux` job 现在也是 "v1, no size tricks yet" 状态，而 README 的
"Linux 瘦身构建" 一节**早就本地实测出了完整配方和数字**
（openssl 替换 mbedtls + visibility/gc-sections/disable-symver +
mpv `buildtype=minsize`/`b_ndebug`，8,189,568 → **7,530,112 字节，−8.05%**），
只是**从来没搬进 workflow**。另外那一节还留了一条"ffmpeg 应提前换成 n6.0.1"的建议
（`ubuntu-22.04` 的 binutils 2.38 只是运气好踩在安全区，runner 镜像一升级就会炸）。

**本计划不做 Linux。** 这里登记它只是为了不被静默遗忘——
Windows 这条线跑完、拿到"哪些手段在非 ELF 平台失效"的对照结论之后，
Linux 那一份反而更好做（它是纯 ELF，Android 的经验可以直接照搬，
包括 Windows 用不上的 `-fvisibility=hidden`）。
建议作为紧接着的下一个独立计划，**不要塞进本计划的任何一个 Task**。

## 12. 执行记录（2026-09-17 本地全流程真实验证，已完成）

> 本节记录的是**本地用真实 MINGW64 工具链（MSYS2，非 CI 本身）跑通整条
> ffmpeg n6.0.1 + mpv 78d43740f5 构建链**得到的结果——每一步都过了完整
> symbol/自包含核验。之所以先在本地验证而不是逐个 push CI，是因为这一轮
> 挖出的三处发现都会直接推翻计划原文的预测，本地一次链路能跑几十次
> 迭代，而 CI 一次 run 要等 10+ 分钟，且每次 push 到 GitHub main 都会因为
> `mova-libmpv/**` 路径过滤器触发全平台重建（见 `mova/CLAUDE.md`「剩余任务」
> libmpv 迁移 Task 6 附近记录的教训）。**这些数字尚未被真实 CI run 复现
> 确认**，下一步是把本节验证通过的配置落进 workflow 并推一次 CI 做最终确认
> （本地 MINGW64 环境的构建结果历史上跟 CI 的差异只有 0.05%，见下方
> "本地环境保真度验证"，可信度高）。

### 本地环境保真度验证

本机没装 MINGW64（只有 UCRT64），先 `pacman -S mingw-w64-x86_64-toolchain` 等
装出跟 CI 完全一致的子系统，然后完整跑一遍**未做任何优化改动**的原始配方，
比对 CI 实测的 15,368,704 字节：本地产出 15,361,536 字节，**差 7,168 字节
（0.05%）**——确认本地构建链忠实复现 CI，后续本地测出的数字可信。

### 三个推翻计划原文预测的发现（按重要性排序）

**发现 1：Task 0 揭露产物其实不自包含（正确性 bug，非体积问题）**——
`meson`/`ninja` 产出的 `libmpv-2.dll` 导入表里有 `libgcc_s_seh-1.dll`/
`libstdc++-6.dll`/`libwinpthread-1.dll`，用户机器没装 MinGW 运行时就会
`LoadLibrary` 失败。用 `-static-libgcc` + `-Wl,-Bstatic -lstdc++ -lwinpthread
-Wl,-Bdynamic` 括号修复（`-static-libstdc++` 单独无效，因为是 C 驱动手动
`-lstdc++`，不是 C++ 驱动自动加的那个），代价 +107,008 字节（+0.7%），
正确性优先于体积。**新真基线：15,475,712 字节**（原 15,368,704 是带 bug
的错误基线，不能拿来当起点）。顺带发现 `-Wl,-Map=$WS/...`（POSIX 路径）会让
`ld.exe` 报 "cannot open map file" 直接链接失败，须用 `cygpath -m` 转换。

**发现 2：`-ffunction-sections`/`-fdata-sections` 不能无脑套用在 ffmpeg/依赖库
上——对这类"几乎全部代码都会被用到"的库是纯负收益，不是计划原文预测的 ±0**：
- 给 ffmpeg 加这两个 flag（Task 2 原方案），`libavcodec.a` 从 27.5MB 涨到
  32.9MB（+20%），最终链接产物从 14.70MiB **炸到 32.58MiB（+124%）**。
  根源：COFF 格式下每个函数独立成 section 带来的 section 头/重定位开销，
  在 gc-sections 找不到死代码可回收时（ffmpeg 的解码器代码路径基本全部
  真实被调用）是纯负担。**Task 2 已从方案中整体剔除，不要加到 ffmpeg**。
- 同一模式在 dav1d 上复现：加了这两个 flag 从源码构建 dav1d，链接后
  **反而 +62,976 字节**；去掉这两个 flag（只留 `buildtype=minsize`/`-Os`），
  从源码构建 dav1d 才真正带来 **−223,232 字节**的净收益，且 archive 本身
  从 pacman 版的 3.11MB 降到 2.84MB。**结论：`-ffunction-sections` 只应用在
  mpv 自己的编译单元上**（mpv 有真实死代码——大量可选子系统在当前功能
  裁剪下不会被触达，gc-sections 在这里才有东西可回收，实测 mpv 单独应用
  两个 flag + `--gc-sections` 拿到 −424,448 字节）；ffmpeg 和所有从源码
  构建的依赖库（dav1d/freetype/fribidi/harfbuzz/libass）**一律不要加**这两个
  flag，只给 `-Os`/`buildtype=minsize`。

**发现 3：`-Oz` 比 `-Os` 有巨大额外收益，但只在 mpv 自己的代码上生效**——
`buildtype=minsize` 默认给的是 `-Os`（已用 `compile_commands.json` 实测确认），
换成更激进的 `-Oz`（GCC 支持，`gcc -Oz` 编译测试成功）：**只在 mpv 的
`c_args`/`cpp_args` 里加，−1,575,424 字节（−11.2%）**，是全计划单项收益
最大的一步，全部符号核验通过（`mpv_create`/`dav1d_open`/`ass_library_init`/
`hb_shape`/`FT_Init_FreeType`/`fribidi_get_par_embedding_levels_ex`/
D3D11VA hwaccel 全部在，导入表干净）。**但同样加到 ffmpeg 上几乎零收益**
（`libavcodec.a` 27,550,380→27,551,636，最终链接产物 +512 字节，噪声级）——
再次印证"ffmpeg 的代码路径已经足够紧，通用编译期优化对它边际收益趋近于零，
真正的空间在 mpv 自己的可选子系统和依赖库的功能裁剪上"这条本轮反复验证的
规律。**灵感来源**：`svgx`（本 monorepo 另一个 Rust 项目）的 `opt-level="z"`
是同一个优化级别的 Rust 说法，他们的 `opt-level` 全对照表独立得出同样结论
（`"z"` 是体积帕累托最优，`"s"` 多付 12% 体积只换 33% 速度）——两个完全不同
工具链、互不知情的项目收敛到同一结论，可信度高。详见 `svgx/doc/SIZE_OPTIMIZATION.md`。

### 两个测过但不采纳的候选

- **`-fno-asynchronous-unwind-tables`**（灵感来自 svgx 的 `panic="abort"`
  移除 unwind 机制）：实测 −87,552 字节（−0.7%，`.pdata`/`.xdata` section
  仍在但变小），**但不采纳**——Windows x64 ABI 强制要求完整 unwind 信息用于
  SEH 栈展开，这个 flag 只影响"精确到每条指令"的展开粒度，削弱后可能在真实
  异常/崩溃场景下让栈展开不完整，播放器的崩溃报告/异常路径可靠性优先于
  0.7% 体积。
- **lld + `--icf=all`**（灵感来自 svgx 在 Android 上用 lld ICF 拿到 −1.29%，
  同时修正了本计划早先"ICF 无收益"的判断——**那个判断只对 GNU bfd ld 成立**，
  lld 的 ICF 实现完全是另一回事）：`pacman -S mingw-w64-x86_64-lld` 装上后
  `-fuse-ld=lld` 直接链接失败——`gcc` 驱动给共享库链接自动注入
  `--allow-shlib-undefined`，这是 bfd/gold 的选项，lld 的 **MinGW/COFF 端口
  不支持**（lld 的 ELF 端口支持，但 mova 这里编译目标是 PE/COFF）。修这个
  需要更深的链接器层面 workaround，而 svgx 自己在 Android 上实测的收益也只有
  −1.29%，投入产出比不划算，**不追**。

### 最终验证结果（本地，2026-09-17）

| 阶段 | 字节 | Δ | 累计 vs 真基线(15,475,712) |
|---|---:|---:|---:|
| CI 原基线（有自包含 bug，不能用） | 15,368,704 | — | — |
| **Task 0 修复自包含（新真基线）** | **15,475,712** | +107,008 | 基线 |
| Task 1 SChannel | 14,702,080 | −773,632 | −5.0% |
| ~~Task 2 ffmpeg 分节~~（已剔除，净负收益） | — | — | — |
| Task 3 mpv `minsize`+分节+`--gc-sections` | 14,277,632 | −424,448 | −7.7% |
| Task 4 dav1d 源码构建（不分节） | 14,054,400 | −223,232 | −9.2% |
| Task 5 freetype/fribidi/harfbuzz 源码构建 | 14,054,400 | **0**（实测无收益，见下） | −9.2% |
| **追加：mpv 用 `-Oz` 替代 `-Os`** | **12,478,976** | **−1,575,424** | **−19.4%** |
| Task 6 libass 源码构建 | 未测（本地 `autoreconf` 环境损坏，见下） | — | — |

**Task 5 追记（重要，推翻计划 §6.2 的预测）**：把 freetype/fribidi/harfbuzz
从 pacman 换成从源码构建（不分节，只 `minsize`），**最终链接字节数一字不差
（14,054,400 前后相同）**。原因：`--gc-sections` 在 Task 3 已经把能省的都省了，
只要保证 `pkg-config` 正确解析到自建版本（`pkg-config --variable=prefix
harfbuzz` 已验证指向自建 prefix），从源码重建这几个库相对 pacman 版本
**没有额外收益**——除非同时对它们做功能裁剪（关掉 harfbuzz 的 icu/glib/
cairo、freetype 的 brotli/bzip2/png、libass 的 fontconfig），但那些功能本来
就没被 mpv 实际调用到，`--gc-sections` 早就会在链接期把它们的代码路径排除，
不需要在源头上关掉编译选项。**结论：Task 5 不值得做**，除非有其他非体积
理由（比如避免拉入 fontconfig 这种"Windows 上本不该存在的 Linux 风格依赖"，
但那是代码卫生问题，不是体积问题）。

**Task 6 未完成原因**：libass 走 autotools，需要 `autoreconf`，本机
`perl-Error`/`Autom4te::ChannelDefs` 模块损坏（`pacman -S perl` 重装无效），
是本地环境问题，不是技术方案问题。CI 的 ubuntu/windows-latest 镜像大概率没有
这个环境损坏，**留给 CI 环境实测**，且基于 Task 5 的模式（`--gc-sections`
早已吃满收益），预期 Task 6 大概率也是零收益或很小收益，优先级降低。

### 下一步

把本节验证通过的最终配置（Task 1 SChannel + Task 3 mpv `-Oz`/`minsize`/
分节/`--gc-sections`/自包含修复 + Task 4 dav1d 源码构建）落进
`.github/workflows/build-mova-libmpv.yml` 的 `windows` job，推一次真实 CI
做最终确认（预期误差 <0.1%，参考本节"本地环境保真度验证"）。Task 5/6
按上述结论降低优先级，不在这一轮落地。
