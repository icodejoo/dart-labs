# Windows slim 包切换到 WHEP 版 libmpv（2026-10-25）

## 做了什么

- `media_kit_libs_windows_video_slim/windows/CMakeLists.txt`：libmpv-2.dll 与 libmpv.dll.a 改为同目录取，
  优先 `mova/libmpv/windows-x86_64-whep/`，次选 `mova/libmpv/windows-x86_64/`（要求 dll 与 .dll.a 都在）；
  不再读包内 `windows/libmpv-2.dll`。候选根目录两个：宿主 app `windows/` 相对（example 用法）与本包相对。
  原因：flutter 把插件目录做成链接，`CMAKE_CURRENT_SOURCE_DIR` 的 `..` 与 REALPATH 都不可靠（实测踩过），
  所以必须保留 `CMAKE_SOURCE_DIR` 候选。ANGLE 的 sha256 校验逻辑未动。
- git rm 旧产物：`windows/libmpv-2.dll`、`windows-devlib/libmpv-2.def`、`windows-devlib/libmpv.dll.a`。
  `mpv-headers/` 保留（仍是旧配方 pin 的头文件，见风险）。
- 旧配方 workflow（`build-mova-libmpv.yml` windows 提交步骤）：产物改写到 `mova/libmpv/windows-x86_64/`
  （dll、def、.dll.a），不再写 slim 包，也不再写 mpv-headers。YAML 语法已校验，LF 行尾。

## 验证（D:\tmp\win_new_mova\example 临时副本，fvm flutter 3.47.1，explorer 启动 release 构建）

- 构建通过，CMake 用的是 whep 目录；build 输出 `libmpv-2.dll` 10,876,416 B，sha256 前缀 313f45d8f017f659。
- `build/windows/x64/libmpv/` 下为 whep 的 dll、libmpv.dll.a 与 include；链接无报错。
- 播放本地 `test_video.mp4`，PrintWindow 截图（`D:\tmp\win_new_mova\example\shot.png`，1898x1024）出画正常。

## 风险

- `mpv-headers/` 仍是旧配方 pin 的 commit（78d43740）的头文件，而 DLL 是 mpv v0.41.0。
  media_kit_video 只用 client/render 等稳定 C API，本次构建与出画正常，但应择机换成 v0.41.0 头文件。
- 仓库里 `mova/libmpv/windows-x86_64/libmpv-2.dll` 目前是 LFS 指针且缺 .dll.a，次选路径实际不可用，
  仅当 whep 目录缺失时才会报错提示。旧配方 CI 手动触发后才会补齐。
- 未验证 WHEP 推流出画（本次用本地 mp4）；WHEP 与内存斜率此前已在本机用同一 DLL 验证。
