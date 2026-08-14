# mova ffmpeg 瘦身产物（消费侧）

构建配方、flavor 脚本、CI 定义已迁到独立子工程 [`mova-libmpv`](../../../mova-libmpv/README.md)
（2026-08-13）。本目录只保留 CI 回写的构建产物：

- `dist/<平台>/libmpv.*`：各平台瘦身后的 libmpv 二进制，由 `mova-libmpv` 的 CI
  （`.github/workflows/build-mova-libmpv.yml`）构建完成后直接 commit 到这里。
- mova 工程侧的接入方式（Gradle jniLibs 合并、`pickFirsts` 等）不变，见
  `mova-libmpv/README.md` 的"接入 mova 工程"一节。

改 flavor 脚本、patch、构建选项、平台支持范围，去 `mova-libmpv` 改；这里不要再放
任何构建配方文件。
