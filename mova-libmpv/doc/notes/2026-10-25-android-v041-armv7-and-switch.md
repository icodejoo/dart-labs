# Android v041 补 armeabi-v7a，并让 example 以新包为主

日期：2026-10-25。分支 `merge/whep-into-main`。

## 结论

1. 在 WSL 里用同一套补丁（ffmpeg 0001-0012、mpv 0001-0007、`--disable-bsfs` + 12 个 bsf 白名单、WHEP flavor）构建出 armeabi-v7a 的 libmpv.so：**strip 后 5,702,540 B（约 5.44 MiB）**，比 arm64 的 6,354,048 B 小 10%。
2. v041 包现在有 arm64-v8a + armeabi-v7a 两个 ABI；`mova/example` 的 Android override 已改指 v041；旧 n6 包保留，只在 pubspec description 加了一句"已被取代"。
3. **armeabi-v7a 没有运行验证**（见下），只做了构建级和符号级验证。
4. **arm64 真机复测本轮没有做成**：任务执行期间 adb 一直没有设备（手机 USB 未连、无线调试未开，ping 192.168.254.136 通但 5555 被拒）。APK 已构建好并确认含两个 ABI，等手机接上即可装。

## 产物

| 文件 | 大小 | sha256 |
|---|---|---|
| armeabi-v7a/libmpv.so（新） | 5,702,540 | `08604e78ae31a64b581fe11e22c96dcfabad8bcd3205373fcd7f324afc844d01` |
| armeabi-v7a/libmediakitandroidhelper.so | 286,812 | `506d0bc7775fe9888be6b6e889d8556ca0574dba65813866e2158cbf52a8c8b1` |
| arm64-v8a/libmpv.so（原有） | 6,354,048 | `b54e16a0be86aacc16c4287aac2b38107d0bf645f7a303a65b0d5edb70821c43` |
| arm64-v8a/libmediakitandroidhelper.so（原有） | 386,696 | `ab55b1d34665dba8fa7a451e82c466ee71b9698e7da6c9a3cb68a7c0ee7610d4` |

- v7a helper 没重编：从旧包 `media_kit_libs_android_video_slim/.../armeabi-v7a/` 拷贝，该文件在旧包里是 LFS 指针，`git lfs pull` 取回后 sha 与指针 oid 完全一致（上游 release jar 原样提取，helper 是纯 JNI 小库，与 libmpv 的 ffmpeg/mpv 版本无关）。
- 未 strip 版 26,695,188 B，只在 WSL（`/root/w/v7build/libmpv.armeabi-v7a.unstripped.so`），不入库。

## 构建步骤

脚本改动：`mova-libmpv/patches/android-v041/e2e-arm64.sh` 加 `ARCH` 环境变量（`arm64` 默认 / `armv7l`），映射产物目录与构建目录后缀（上游 `loadarch` 里 armv7l 的 `ndk_suffix` 为空，所以 mpv 构建目录是 `_build` 而不是 `_build-arm64`），产物文件名带 ABI；新增薄包装 `e2e-armv7.sh`（`ARCH=armv7l exec e2e-arm64.sh "$@"`）。arm64 行为不变。

armv7 的差异不用改 flavor，`flavors-mova-slim-n9.sh` 本来就按 `ndk_triple` 处理：`--arch=arm --cpu=armv7-a`、`-mfpu=neon -mcpu=cortex-a8`、保留 `--enable-runtime-cpudetect`（arm64 才关）；上游 `build.sh` 的 armv7l 用 `armv7a-linux-androideabi21-clang`、meson cross file 的 cpu_family=arm；`config.h` 里 `ARCH_ARM/HAVE_NEON/HAVE_NEON_INLINE` 均为 1。

```
# WSL（Ubuntu）。仓库文件是 CRLF 检出，副本里要转 LF（仓库内不改）
cp -r mova-libmpv /root/w/v7src && cd /root/w/v7src \
  && find . -type f \( -name '*.sh' -o -name '*.patch' -o -name '*.md' \) -exec sed -i 's/\r$//' {} +
WHEP=1 JOBS=16 patches/android-v041/e2e-armv7.sh /root/w/v7build /root/w/ndk/android-ndk-r25c
```

NDK 参数是 r25c 目录本身。一次成功，全程约 10 分钟（含依赖 clone），产物 `libmpv.armeabi-v7a.stripped.so`。

## 构建级 / 符号级验证

- `llvm-readelf -h`：ELF32、DYN、Machine ARM、Flags 0x5000200（EABI v5，硬浮点标记）。
- NEEDED：libandroid、libEGL、libm、libmediandk、libdl、libOpenSLES、libc；SONAME `libmpv.so`。无 libc++_shared、无第三方 so，与 arm64 同形（无多余依赖）。
- `tools/regress/check-symbols-android.sh armeabi-v7a`：PASS 12 / FAIL 1 / SKIP 1。通过：`mpv_lavc_set_java_vm`、10 个公开 API（含 `mpv_create`、`mpv_render_context_create`）、4 个 `*_mediacodec` 与 `libdav1d` 解码器名、VP8/MJPEG 已裁、协议串。**唯一 FAIL 是 `dav1d_open` 不在 dynsym**：arm64 的现仓库 so 同样 FAIL（dav1d 导出数均为 0），原因是 v041 用 `mpv.android.ver` 版本脚本只导出 mpv 符号，dav1d 静态内嵌但符号隐藏；这条检查是老版（n6 无版本脚本）遗留的判据，需要另行更新，非 v7a 回归。解码器靠 `libdav1d` 名字符串 + 下面的 config.mak 证明存在。
- ffmpeg `config.mak`：`CONFIG_WHEP_DEMUXER`、`CONFIG_DTLS_PROTOCOL`、`CONFIG_LIBDAV1D_DECODER`、4 个 `*_MEDIACODEC_DECODER` 均 =yes；`*_BSF=yes` 恰好 12 个（`--disable-bsfs` 生效）。
- 字符串含 `whep` 的行数 arm64 与 v7a 都是 18。

## example 切换

- `mova/example/pubspec.yaml`：`media_kit_libs_android_video` override 改为 `../packages/media_kit_libs_android_video_slim_v041`，注释同步；`pubspec.lock` 随之变化（只有该 path 一行）。
- `mova/example/android/app/build.gradle.kts`：`abiFilters` 原来只有 `arm64-v8a`，不加的话 v7a 根本进不了 APK，已改为 `arm64-v8a` + `armeabi-v7a`。
- v041 `android/build.gradle`：没有 abiFilters/pickFirst，AGP 自动打包 `src/main/jniLibs/<abi>/`，两个 ABI 都对，无需改。minSdk 由 app（`flutter.minSdkVersion`）决定，libmpv 按 API 21 编译。
- 旧包 `media_kit_libs_android_video_slim/pubspec.yaml` description 加"已被 v041 取代，仅作回退保留"，包本身没动。
- APK：fvm flutter 3.47.1，`flutter build apk --release -t lib/main_whep_verify.dart --target-platform android-arm,android-arm64` 成功，`mova/example/build/app/outputs/flutter-apk/app-release.apk`（116.1 MB，大头是 libonnxruntime，与 mpv 无关）。`unzip -l` 确认包含 `lib/arm64-v8a/libmpv.so`（6,354,048）、`lib/armeabi-v7a/libmpv.so`（5,702,540）和两个 ABI 的 helper，大小与上表一致。

## 未验证

- **armeabi-v7a 无运行验证**：本机只有 x86/x86_64 模拟器镜像（android-29 x86/x86_64、android-36 x86_64 带 arm64 翻译，没有 32 位 ARM 翻译），手上设备 STG-AL00 是 arm64 且不能跑 32 位应用。所以 v7a so 没有 dlopen 过，没起播，没验证 NEON 路径、mediacodec 回落、WHEP。
- **arm64 真机用 v041 APK 起播**：本轮没做成（设备不在线）。上一轮（`2026-10-25-android-memory-and-bsfs-verify.md`）已用同版 arm64 so 验证 WHEP/mp4/webm/ts 能播，本轮 arm64 so 没变，风险低，但"example 以 v041 为主打出的 APK 真机能跑"这一条还欠。
  - 补做办法：手机接上并授权后 `adb install -r mova/example/build/app/outputs/flutter-apk/app-release.apk`，沿用 `main_whep_verify.dart` 与 `D:\tmp\amem\` 的 MediaMTX/relay 做法（端口用 18000 以上）。
- v7a 声音、内存基线、32 位地址空间下的内存占用均未测。

## 风险

- `-mcpu=cortex-a8 -mfpu=neon` 是上游默认，v7a 设备必须有 NEON（现役几乎都有，Tegra2 一类没有会 SIGILL）；ffmpeg 保留了运行时 CPU 检测。
- 32 位进程地址空间小，WHEP 预热会涨到 ~100 MiB native heap（见内存笔记），v7a 低内存设备可能先被杀；`demuxer-max-bytes` 限制见 `2026-10-24-realtime-demuxer-cache-limit.md`。
- v7a 的 mpv 补丁 0006（GLsync）/0007（ANGLE 计时器）在 32 位上只有编译通过，行为未验证。
- `.gitignore` 第 8 行忽略了 v041 包下所有 `*.so`（"二进制由 CI 注入"），提交本次 v7a 的两个 so 要 `git add -f`（`.gitattributes` 已把 `mova/packages/**/*.so` 走 LFS，已用 `git check-attr` 确认）。我没有 add 也没有提交。
- 旧 n6 包里的 4 个 ABI 的 so 在本机检出是 LFS 指针（我只 pull 了 v7a helper 这一个文件，working tree 里它变成了真实文件，不产生 diff）。
