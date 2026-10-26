# ffmpeg 9 线瘦身配置（旧分支存档，仅供对比参考）

这里是旧分支 `mova-libmpv-winbuild-zhangfly`（最后提交 `813f99b`，2026-08-11）里 ffmpeg n9.0 + mpv v0.41.0 + libplacebo 那条
"v9 线"的瘦身配置，**原样拷贝、逐字节一致**（拷贝时逐个文件用 `cmp` 比对过），方便以后和 n6 线、
以及本分支正在做的 n9.0.2 配置对着看。

> **这是存档，不是现行配置。** 不要直接拿去构建，也不要当成已验证结论引用。
> 现行方案见 [../../doc/plans/2026-10-01-whep-receiver.md](../../doc/plans/2026-10-01-whep-receiver.md)
> 与 [../../doc/notes/2026-10-02-extreme-slim-config.md](../../doc/notes/2026-10-02-extreme-slim-config.md)。

## 内容

路径保持和旧分支一致，对照时好找：

| 文件 | 是什么 |
|---|---|
| `tools/ffmpeg-slim/experiments/build-android-libmpv-v9.sh` | Android arm64 v9 实验线，头部注释有逐步体积记录（10.62→9.30MB）与三个真机坑 |
| `tools/ffmpeg-slim/experiments/build-win-libmpv-v9.sh` | Windows v9 实验线，头部注释有体积记录（13.60→11.91MB）、schannel 替 mbedtls、D3D11 硬解踩坑 |
| `tools/ffmpeg-slim/libmpv-darwin-build.patch` | iOS/macOS 的 `movaslim` flavor（v9 线，nix 配方补丁） |
| `tools/ffmpeg-slim/README.md` | 当时的总览，含 Darwin movaslim 一节和各平台体积表 |
| `tools/ffmpeg-slim/flavors-mova-slim.sh` | 当时的 Android 生产 flavor（v6 线）|
| `tools/ffmpeg-slim/libmpv-android-video-build.patch` | 当时的 Android 构建链补丁 |
| `tools/ffmpeg-slim/configure-ffmpeg-slim.sh` | 当时的 ffmpeg configure 脚本 |
| `.github/workflows/experiment-libmpv-v9.yml` | v9 实验线的 CI |
| `.github/workflows/build-mova-libmpv.yml` | 当时的主 CI（与 main 上现行版本不同，仅供对照）|

## 没拷的东西

- `dist/` 下的 `.so` 二进制（走 LFS，体积大，对比配置用不上）。
- `tools/ffmpeg-slim/experiments/.gitattributes`（只有 `*.sh text eol=lf`，本仓库根已有等价规则）。

## 放在子目录里为什么不会触发 CI

GitHub 只认仓库根的 `.github/workflows/`，这里的 `reference/.../.github/workflows/` 只是存档，不会被执行。

## 读的时候要注意

- 那条线的数字是**它自己当时测的**，口径（平台、NDK、是否 LTO、是否去 dav1d）和本分支的评估不同，
  不能直接拿来和 n6 线的 6,050,104 字节比。
- 旧分支自称"tentative，未决定是否全平台采纳"。
- 它对 mpv 0.41.0 的一个说法（需要 ffmpeg n9.0 才有的 `avcodec_get_supported_config()`）和本分支实测不一致
  （0.41.0 的 `meson.build` 只要求 ffmpeg ≥ 6.1），谁对未核实，详见计划文档 T0.2 的旁证一节。
