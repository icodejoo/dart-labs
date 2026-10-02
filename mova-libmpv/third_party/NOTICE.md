# 许可声明与第三方代码告知

本软件（mova-libmpv）包含以下开源项目的代码，其许可情况说明如下。

## 1. 主体许可

mova-libmpv 的绝大部分代码遵循 **LGPL version 2.1 或更高版本**，包括：

- FFmpeg（n9.0.2）及其依赖（libass、harfbuzz、freetype、fribidi、mbedtls、libplacebo 等）
- MPV（v0.41.0）及其渲染引擎
- 本项目自行编写的编译脚本、构建补丁与瘦身配置

## 2. 第三方 MPL-2.0 代码

部分代码来自 **Mozilla Public License 2.0（MPL-2.0）** 许可的项目（主要来自 libdatachannel / libjuice），包括：

- NACK 重传检测与多 FCI 打包逻辑
- 相关的 WebRTC 信令与 ICE 处理代码

这些文件的原始许可头已保留，不得删除或修改（MPL §3.4）。

## 3. 源码获取

**FFmpeg 与 MPV 源码**：  
- FFmpeg tag `n9.0.2`：https://git.ffmpeg.org/ffmpeg.git
- MPV tag `v0.41.0`：https://github.com/mpv-player/mpv
- 本项目应用的补丁位置：`mova-libmpv/patches/`（与 git 历史同步）

**MPL-2.0 文件源码**：  
- 见 `third_party/PROVENANCE.md` 列出的源仓库 URL + tag/commit
- 原文件完整路径见 `PROVENANCE.md` 的"来源路径"列

## 4. 双许可分发

根据 MPL-2.0 §3.3，本软件作为"Larger Work"可额外在 **LGPL version 2.1 或更高版本** 下分发。接收方可选择遵循：

- **MPL-2.0**（仅限本软件中的 MPL 代码片段），或
- **LGPL v2.1 或更高版本**（整个软件作为整体）

## 5. 完整许可文本

- **MPL-2.0 完整条文**：`third_party/LICENSES/MPL-2.0.txt`
- **详细登记表**：`third_party/PROVENANCE.md`（每个拷贝/移植文件的来源、版本、修改说明）

## 6. 免责声明

本软件包含的所有代码均按"现状"（"as is"）提供，不附带任何明确或隐含的保证。具体见 MPL-2.0 的第 6–7 条及 LGPL 的相应条款。

---

**更新**：此文档最后更新于 2026-10-02。如对许可有疑问，请参考上述源文档或咨询法务。
