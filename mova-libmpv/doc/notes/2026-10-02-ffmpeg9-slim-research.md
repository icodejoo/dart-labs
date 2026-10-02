# ffmpeg n9.0.2 瘦身调研：+500KB 从哪来、怎么压回去

日期：2026-10-02。承接 [T0.2 spike](2026-10-02-t02-real-flavor-spike.md) 的遗留问题（n6.0.1→n9.0.2 同 configure 参数下 stripped +499,888B，来源未拆）。
只记结论与证据；工作目录 WSL `/root/w/sl9`（换机器即失，命令见 §8）。

## 0. 结论（先看这个）

1. **+500KB 里约 46%（229,376B）不是 n9 本身变大，而是 `--enable-bsfs`/默认全开 bsf 在 n9 上多拖了 9 个 bsf 和一堆 cbs 代码**。
   n6 现行配置（Android `flavors-mova-slim.sh:119` 的 `--enable-bsfs`；CI linux/windows job 虽然写了 `--enable-bsf=白名单`，但没有 `--disable-bsfs`，ffmpeg 默认全开）
   实际启用的是**全部 bsf**（n6 41 个、n9 50 个），白名单那行只是"再点一遍"。n9 新增的 `cbs_h266`（~122KB）、`cbs_lcevc`、`cbs_apv`、`cbs_vp8`、`dovi_rpuenc`
   都是被 `vvc_metadata`/`lcevc_metadata`/`apv_metadata`/`trace_headers`/`dovi_rpu` 这些用不上的 bsf 拉进来的。
2. **一个 configure 参数 `--disable-bsfs`（放在 `--enable-bsf=白名单` 之前）就省 524,288B（n9）/294,912B（n6）**。再叠 `--disable-iamf`（n9 独有，−20,480）和
   `--disable-swscale-alpha`（n9 −32,768 / n6 −24,576），n9 合计 −573,440B。
3. **同口径目标"n9 ≤ n6.0.1"（n6 取现行产物形态，即 bsf 全开）：达成**，Linux x86_64 实测：
   Linux job 解码器集 6,647,720 vs 6,721,272（**−73,552，−1.1%**）；Android 解码器集 4,886,440 vs 4,894,456（**−8,016，−0.2%**，余量很薄）。
4. **但这不是"n9 比 n6 小"，是"n9 瘦身后追平 n6 没瘦身"**。如果 n6 也同样加 `--disable-bsfs --disable-swscale-alpha`，n9 仍然贵 **+250,032B（Linux 集，+3.9%）/ +323,760B（Android 集，+7.1%）**。
   这部分是 n9 的结构性增长（swscale 重写 +80KB、mov/avformat +56KB、avutil +35KB、avcodec 里 aac USAC/film grain/exif/hevc 重组等），**没有 configure 开关能去掉**，见 §4。
   这是 x86_64 数据；其中 x86 asm 专属的增量（vp9 avx2/avx512 约 +45KB、hevc/swscale 的 x86 dsp）在 arm64 上不存在，**Android arm64 的真实差距大概率小于这个数，但没测，是推断**。
5. **把 mpv v0.41.0 + 静态 libplacebo（摘 vo_gpu_next）也算进来（真实升级路径）**：Linux 集 6,828,648 vs n6+钉死 mpv 6,721,272，仍 **+107,376（+1.6%）**；Android 集 5,067,368 vs 4,894,456，**+172,912（+3.5%）**。
   这 +107K~+173K 来自 mpv 侧（v0.41 本体 + libplacebo，本次不在 ffmpeg 调研范围内），要追平得另找 mpv 侧的手段，或者接受。

**推荐 configure 增量（相对 flavors-mova-slim.sh / CI 现行参数）**：

```
删掉  --enable-bsfs                         （Android flavor 第 119 行；n9 上这一项 = +524KB）
删掉  --disable-postproc                    （n9 报 Unknown option，已知）
加上  --disable-bsfs                        （必须放在 --enable-bsf=白名单 之前；CI linux/windows job 也要加）
加上  --disable-iamf                        （n9 才有这个选项）
保留  --disable-swscale-alpha               （n9 上仍有效，Android flavor 已有；CI linux/windows job 没有，建议补上）
可选  --disable-bzlib --disable-lzma --disable-iconv --disable-xlib --disable-libxcb --disable-sdl2 --disable-alsa   （再 −8,480，仅对 autodetect 环境有意义）
```

## 1. 口径（必读）

- 所有体积是 `strip --strip-all` 后的 `libmpv.so` 字节数，**只能在本表内互比**，不能和仓库里 Android/iOS 的数字比。平台 Linux x86_64、gcc 15.2、WSL。
- **P 栈**：钉死 mpv `78d43740f5`（n9 用旧 342 行兼容补丁版，对象文件取自 `/root/w/t02/bPN6`、`bPN9`）+ 各自 ffmpeg。n6 基线 6,721,272、n9 基线 7,221,160，**与 T0.2 的数字逐字节一致**（用 `relink.sh` 复现，非引用）。
- **B 栈**：mpv v0.41.0 + b3（摘 vo_gpu_next）+ 静态 libplacebo（`/root/w/t02/bBN9`），只有 n9（v0.41 要求 ffmpeg ≥ 6.1，n6.0.1 配不了）。基线 7,406,184，与 T0.2 一致。
- 方法：每个 ffmpeg 变体各自 `configure → make -j8 → make install` 到独立 prefix，然后**只重链** libmpv（mpv 对象文件固定不变），所以字节差**只来自 ffmpeg 那一侧**。变体的 `Enabled bsfs/decoders` 摘要已核对。
- 两套解码器集：
  - **L 集** = T0.2 的 Linux job 白名单（h264/hevc/vp9/dav1d/png/aac/aac_latm/mp3/mp3float/opus/ac3/eac3/flac/vorbis/pcm*/字幕）。
  - **A 集** = `flavors-mova-slim.sh` 的 Android 软解集合（hevc、libdav1d、png、aac、aac_latm、mp3float、opus、flac、vorbis、pcm*、字幕；**没有软 h264/vp9/ac3/mp3**）。
    `*_mediacodec`、`--enable-jni/mediacodec` 在 Linux 上不存在，**没测**；parser/demuxer 列表按 flavor 的（无 ac3/eac3 demuxer 与 parser 项）。
- **没做**：Android 交叉编译、arm64、clang `-Oz`、`--enable-lto`（Linux 上 LTO 要改链接命令，本次没做）、真机。凡是 arm64/Android 的说法都是推断，已标注。

## 2. 归因：n9 比 n6 大在哪（实测，基线 c6→c9，+499,888B）

### 2.1 ELF 节层面（`readelf -SW`）

| 节 | n6 | n9 | Δ |
|---|---:|---:|---:|
| `.text` | 4,704,571 | 5,012,583 | +308,012 |
| `.rodata` | 567,584 | 658,368 | +90,784 |
| `.eh_frame` | 604,776 | 637,848 | +33,072 |
| `.data.rel.ro` | 409,448 | 439,760 | +30,312 |
| `.rela.dyn` | 305,208 | 328,032 | +22,824 |
| `.eh_frame_hdr` +6,296、`.dynsym`/`.dynstr`/`.rela.plt`/`.gnu.version` 合计 +3,349 | | | +9,645 |

（`.bss` 反而从 17.9MB 降到 2.3MB——n6 的 libavutil tx 表在 bss，n9 改了；bss 不占文件体积，**对 stripped 字节无影响**。T0.2 里 `film_grain_db`（692,248B）同样是 `.bss`，已用 `nm` 的 `b` 类型核实，不是那 500KB 的来源，**T0.2 的推断成立**。）

### 2.2 按库（`-Wl,-Map`，只统计 text/rodata/eh_frame/relro/data，排除 .bss 与调试节）

| 库 | n6 | n9 | Δ |
|---|---:|---:|---:|
| libavcodec | 3,492,639 | 3,695,581 | +202,942 |
| libswscale | 461,868 | 545,635 | +83,767 |
| libavformat | 422,547 | 496,029 | +73,482 |
| libavutil | 441,048 | 477,527 | +36,479 |
| libavfilter | 45,649 | 58,683 | +13,034 |
| libswresample | 79,595 | 78,091 | −1,504 |
| mpv 对象 | 22,522 | 23,021 | +499 |
| 合计 | 6,289,547 | 6,751,407 | +461,860（其余约 38KB 在动态符号/重定位/hdr 节） |

### 2.3 libavcodec 里的大头（成员级，n9 新增 / n6 消失，`ar`/map 成员名在多目录下重名，如 `dsp_init.o`，下面按符号与目录核对过）

- **hevc 重组**：n6 的 `hevcdsp_init/hevc_mc/hevcdsp/hevcpred/idct/deblock/sao`（合计约 −640KB）整体搬进 `libavcodec/hevc/` 并重命名为 `dsp_init/dsp/pred/mc/idct/deblock/sao...`（+640KB），**净值约 0**，另新增 `h2656_inter.o`（+57KB，hevc/vvc 共用的帧间预测）、`tab.o`（+17KB）。所以"n9 的 hevc 解码器更大"这个说法只对了一小半：hevc 软解本身 n6 约 720,896B、n9 约 741,376B（`DROPDEC=hevc` 对照，见 §3 表），差 +20K。
- **cbs 家族**：n6 的 `cbs_h2645.o`（−152KB）拆成 `cbs_h264/h265/h266`，n9 的 `cbs_h266`（+122KB）、`cbs_lcevc`（+20KB）、`cbs_apv`（+13KB）、`cbs_vp8`（+7KB）、`cbs_sei`（+15KB）是**纯新增**，在默认全开 bsf 时被拖进来（见 §3 的 bsfs 实验：把 bsf 关掉后 libavcodec 净增从 +203K 变成 +16K）。
- **n9 新代码，白名单里的组件自带**（`--disable-bsfs` 后仍在）：aac USAC（`aacdec_usac*`/`aacdec_tab`/`aacdec_float`，约 +49KB，aac 解码器自带，无开关）、`aom_film_grain`（+22KB，`libdav1d_decoder_select=itut_t35` 拉入）、`exif`（+17KB，png/mjpeg 解码器用）、`cbs_vp9`（+17KB，n9 的 vp9 软解新依赖，A 集没有 vp9 软解所以不存在）、opus silk/celt 重组（净约 0）。
- **x86 汇编专属**（arm64 上不存在，**推断**）：`vp9itxfm_avx2/avx512/16bpp_avx512`（+45KB，净值已扣掉 n6 `vp9itxfm` 的 −107KB）、hevc x86 dsp、swscale x86 `yuv2rgb`（+36KB）。

### 2.4 libswscale（+84K）与 libavformat（+73K）

- swscale n9 重写出的 ops/uops 后端：`graph/ops*/uops*/format/cms/lut3d/filters` 这组成员在最终产物里只剩 **7,260B（n6 为 6,341B）**，被 `--gc-sections` 基本回收；**新 ops 层不是体积元凶，不需要给它打补丁**。
  swscale 的 +84K 主要是 `yuv2rgb`（+36K）、`input/output/swscale_unscaled`（+40K）这类 x86 像素格式转换代码——无开关，arm64 上具体数量未知。
- avformat：`mov.o` +23K（n9 mov 读取更多 box），`iamf_parse`/`iamf` 约 +22K（`mov_demuxer_suggest="iamfdec"` 自动拉入，**可用 `--disable-iamf` 去掉**），其余为 `--enable-bsfs`/`dovi`/`apv` 相关。

## 3. 逐项手段实测（字节，均整体重编译 ffmpeg + 重链，非加减得出）

**P 栈 / L 集（Linux job 解码器），n9.0.2**

| 变体 | stripped | Δ vs c9 | 说明 |
|---|---:|---:|---|
| c9：T0.2 原样（删 `--disable-postproc`） | 7,221,160 | 0 | 与 T0.2 逐字节一致 |
| `--disable-bsfs`（其后接 `--enable-bsf=白名单`） | 6,696,872 | **−524,288** | bsf 从 50→12 个（只剩白名单 12 个，已核对 Enabled bsfs） |
| `--disable-iamf` | 7,200,680 | −20,480 | n9 独有选项 |
| `--disable-swscale-alpha` | 7,188,392 | −32,768 | n9 上仍有效 |
| `--disable-hwaccels` | 7,221,160 | 0 | 无 hwaccel 库时本来就空 |
| `--disable-faan --disable-pixelutils` | 7,221,160 | 0 | 无效果 |
| **bsfs + iamf + alpha**（v_all） | **6,647,720** | **−573,440** | 推荐组合 |
| v_all + `--disable-bzlib --disable-lzma --disable-iconv --disable-xlib --disable-libxcb --disable-sdl2 --disable-alsa`（v_auto） | 6,639,240 | −581,920 | 只比 v_all 再省 8,480 |
| v_all 去掉 hevc 软解（`DROPDEC=hevc`，仅作成本参考，不是推荐） | 5,906,344 | −741,376 | 产品决策项，见 §5 |

**P 栈 / L 集，n6.0.1（同样手段对照）**

| 变体 | stripped | Δ vs c6 |
|---|---:|---:|
| c6：现行配置 | 6,721,272 | 0 |
| `--disable-bsfs` | 6,426,360 | −294,912 |
| `--disable-swscale-alpha` | 6,696,696 | −24,576 |
| bsfs + alpha（w_all） | 6,397,688 | −323,584 |
| w_all 去 hevc 软解 | 5,676,792 | −720,896 |

**P 栈 / A 集（Android 软解集，Linux x86 上近似）**

| 变体 | stripped | 说明 |
|---|---:|---|
| a6：n6 现行（bsf 全开） | 4,894,456 | Android flavor 现状（`--enable-bsfs`） |
| a9：n9 直接照抄 | 5,480,360 | +585,904 vs a6 |
| a6s：n6 + `--disable-bsfs --disable-swscale-alpha` | 4,562,680 | −331,776 vs a6 |
| **a9s：n9 + `--disable-bsfs --disable-iamf --disable-swscale-alpha`** | **4,886,440** | **−8,016 vs a6**；+323,760 vs a6s |
| a9m：a9s 再把 bsf 白名单砍到 5 个（null、h264_mp4toannexb、hevc_mp4toannexb、aac_adtstoasc、extract_extradata） | 4,870,056 | 再 −16,384，**不推荐**：vp9_superframe*/av1_frame_*/mov2textsub/setts/dump_extradata 是 n6 线按 mova remux/seek/字幕路径留的，本次没法验证它们不需要 |

**B 栈（mpv v0.41.0 + b3 + 静态 libplacebo）+ n9**

| 变体 | stripped | Δ vs Bc9 |
|---|---:|---:|
| Bc9（L 集，T0.2 原样） | 7,406,184 | 0 |
| `--disable-bsfs` | 6,881,896 | −524,288 |
| `--disable-iamf` | 7,385,704 | −20,480 |
| **L 集 v_all** | **6,828,648** | −577,536 |
| L 集 v_auto | 6,824,296 | −581,888 |
| L 集 v_all 去 hevc | 6,091,368 | −1,314,816 |
| Ba9（A 集直接照抄） | 5,665,384 | — |
| **A 集 a9s** | **5,067,368** | −598,016 vs Ba9 |
| A 集 a9m | 5,050,984 | −16,384 vs Ba9s |

mpv 侧（不在本次范围）：同一份 n9 ffmpeg，B 栈比 P 栈大 184,976B（`c9` 7,221,160 → `Bc9` 7,406,184），其中 libplacebo 静态库约 26KB（map 可见），其余是 mpv v0.41 本体增长。

**功能冒烟（实测，Linux，B 栈 + n9 + v_all，软渲染 + ao=null，5 轮 create/init/destroy 同 T0.2 程序）**：`h264.mp4`、`h264.mkv`、`h264.flv`、`h264.ts`、`hevc.mp4`、`hevc.ts`、`a.aac`、`b.mp3`、`v.webm`（vp9+opus）、HLS mpegts（`/root/w/t02/hls`）、HLS fmp4（本次 `ffmpeg -f hls -hls_segment_type fmp4` 生成）共 11 个样本，
`Bv_all` 与 `Bv_auto` 全部 `END_FILE reason=0 err=0`、弱客户端 1 次 RESTART + 1 次 END_FILE，帧数与未裁 bsf 的 `Bc9` 对照一致（±1 帧，抽样时序差）。
**没测**：MediaCodec 路径（需要 `h264_mp4toannexb`/`hevc_mp4toannexb`，在白名单内，configure 的 `Enabled bsfs` 摘要里确认在列）、DASH、RTMP、HTTPS、真机。

## 4. 剩余的结构性增长（configure 去不掉，v_all vs w_all，+221,780 非调试字节 / +250,032 stripped）

| 来源 | 字节（map，非调试） | 能不能去 |
|---|---:|---|
| libswscale 整体 | +79,701 | 无开关；ops 层已被 gc；x86 专属部分占大头（推断） |
| libavformat（mov +21K 等） | +56,037 | 无开关（iamf 已关） |
| libavutil | +35,407 | 无开关（`.data.rel.ro` +11K、tx 重构、hdr 元数据） |
| libavcodec 净值 | +15,675 | hevc 重组≈0；aac USAC +49K、film grain +22K、exif +17K、cbs_vp9 +17K，被 vp9/opus/hevc 的 n6 旧代码消失抵消 |
| libavfilter | +13,034 | 框架代码，filters 已全空；mpv 硬依赖 |
| 合计 | +221,780 | 之外约 28K 在重定位/动态符号节 |

候选**源码补丁**（本次**没做、没实测**，只给方向，**推断**）：给 aac 解码器去掉 USAC（约 −49K，需要改 `libavcodec/aacdec*.c` 与 Makefile，风险是 `aac_latm`/USAC 流播不了——mova 内容是 AAC-LC/HE，但没证据）；
给 libdav1d 包装器去掉 film grain 导出（约 −22K，AV1 胶片颗粒会丢）。这两个收益都在几十 KB 量级，且要长期维护补丁，**不建议为此改源码**。

## 5. 对照现有手段：哪些在 n9 上失效或要调整

| 现有手段（来源） | n9 上的状态 |
|---|---|
| `--disable-postproc`（`flavors-mova-slim.sh:113`、CI `:830/:1096` 等 5 处） | 失效，configure 直接报错，必删（T0.2、extreme-slim §7 #1 已知） |
| **`--enable-bsfs`**（`flavors-mova-slim.sh:119`） | **n9 上代价放大**：n6 全开 41 个 bsf，n9 全开 50 个并拖入 cbs_h266/lcevc/apv/vp8，实测 +524KB（n6 上同一项是 +295KB）。**应该删，换成 `--disable-bsfs`**。[极致配置](2026-10-02-extreme-slim-config.md) §3.2 里"`--enable-bsfs` +520,192"是同一结论，本次独立复现 |
| CI linux/windows job：只写 `--enable-bsf=白名单`、没有 `--disable-bsfs` | 等价于 bsf 全开（ffmpeg 默认），**n6 线也在白白多出约 295KB**；与 n9 无关，但是这次调研顺带发现的现状问题 |
| `--disable-swscale-alpha` | 有效，n9 −32,768（n6 −24,576）。CI linux/windows job 目前没带，建议补 |
| `--disable-vulkan` / `--disable-vaapi/vdpau` / `--disable-bzlib` 等 autodetect 关闭项 | 仍有效但在本 Linux 构建里体积收益极小（合计 −8,480）；`--disable-everything --disable-autodetect` 方案已含这些 |
| `--enable-small --enable-optimizations` | 仍有效（极致配置实测去掉 +4.4MB） |
| `--enable-hwaccels` | 无副作用（本构建里开关不改字节） |
| `--disable-runtime-cpudetect`（仅 arm64） | 未在 n9 上复测；T0.2 无记录，沿用 n6 结论 |
| `-fvisibility=hidden -ffunction-sections -fdata-sections --gc-sections` | 仍有效；本调研所有数字都在带它们的前提下 |
| `--enable-lto`（Android flavor 已有） | **本次未测**；Linux 路径需要改链接命令。极致配置实测 Linux LTO −131KB，对 n9 额外增长是否有额外吞噬效果**未知** |
| `hls_mp4_seek.patch`、`dash_base_url_escape.patch` | n9 上已被上游修，删（T0.2 §5 已知） |

## 6. 能不能让 n9 ≤ n6.0.1：结论与预期字节

**取决于"n6"取哪个版本**：

| 对照 | n9 瘦身后 | n6 | 差 | 结论 |
|---|---:|---:|---:|---|
| n6 现行配置（bsf 全开，P 栈 L 集） | 6,647,720 | 6,721,272 | −73,552 | **达成** |
| n6 现行配置（Android A 集） | 4,886,440 | 4,894,456 | −8,016 | **达成，余量薄**（x86 数据，arm64 未测） |
| n6 也同样瘦身（L 集） | 6,647,720 | 6,397,688 | +250,032 | **未达成**，结构性，configure 无解 |
| n6 也同样瘦身（A 集） | 4,886,440 | 4,562,680 | +323,760 | **未达成** |
| 含 mpv v0.41 + libplacebo（L 集，B 栈 vs P 栈 n6） | 6,828,648 | 6,721,272 | +107,376 | **未达成**，需 mpv 侧再省 |
| 含 mpv v0.41 + libplacebo（A 集） | 5,067,368 | 4,894,456 | +172,912 | **未达成** |

所以：**只靠 ffmpeg 的 configure，n9 能追平 n6 的"现状产物"，不能追平 n6 的"同样瘦身后"**。把 n6 线也改成 `--disable-bsfs` 是一笔独立的免费收益（−295K，n6 线现状问题），但在 n6 线上拿走的是同一块，不能再在 n9 对 n6 的比较里重复计一次。
如果产品接受"硬件解码机型不要软 HEVC"（A 集里去 hevc 软解，Linux 上 −741KB / −721KB），可以再省一大块，但**这是功能取舍，不在本调研的推荐里**，README 对 hevc 软解的保留理由（Android 硬解覆盖率约 65%）没有被本次数据推翻。

**最终推荐 ffmpeg n9.0.2 configure 关键差异（其余沿用 flavor / CI 现行参数）**，预期（Linux x86，同口径）：

```
--disable-bsfs --enable-bsf=null,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,aac_adtstoasc,vp9_superframe,vp9_superframe_split,av1_frame_split,av1_frame_merge,mov2textsub,dump_extradata,setts
--disable-iamf
--disable-swscale-alpha
（不带 --enable-bsfs；删 --disable-postproc）
```

| 栈 / 解码器集 | 预期 stripped（Linux x86_64，实测） |
|---|---:|
| P 栈 / L 集 | 6,647,720（可再 −8,480 到 6,639,240） |
| P 栈 / A 集 | 4,886,440 |
| B 栈 / L 集 | 6,828,648（可再 −4,352 到 6,824,296） |
| B 栈 / A 集 | 5,067,368 |

Android arm64 的绝对数不同，**只有相对关系可参考**；预期 `--disable-bsfs` 在 arm64 上同样生效（cbs/bsf 代码与架构无关，**推断**），iamf 与 alpha 同理。T0.4 重量 Android flavor 时请按这份清单增量验证，并对 `Enabled bsfs` 摘要做核对。

## 7. 风险与未覆盖

- `--disable-bsfs` 之后依赖 configure 的 `_select` 机制自动补回必要 bsf；Linux 软解 11 个样本通过，**Android MediaCodec 路径（H.264/HEVC/VP9/AV1 mediacodec 解码器 + mp4toannexb/superframe_split）没验证**，必须真机回归。
- `--disable-iamf` 会让 mov demuxer 解析 IAMF 音轨失败（mova 不涉及；**推断**）。
- `--disable-swscale-alpha`：带 alpha 的 PNG 封面经 swscale 转换时 alpha 被忽略，功能影响**未验证**（沿用 extreme-slim §1.1 的结论）。
- 所有数字是 x86_64 + gcc，含 x86 asm；arm64/clang 的 n9 增长构成**未测**。
- 没有拆 `-flto`/去 unwind 表在 n9 上对增长的二次影响（极致配置已有整体数字：LTO −131K、去 unwind −889K，**本次没复测**）。

## 8. 复现

```bash
# WSL，/root/w/sl9。源码：n6src=git clone --shared /root/w/t02/ff601（n6.0.1），n9src=git clone --shared /root/w/t02/ffmpeg（n9.0.2）
# relink.sh  <N6|N9> <prefix> <tag> ：用 /root/w/t02/bP<N6|N9> 的 ninja 链接命令替换 ffmpeg 前缀后重链，加 -Wl,-Map，再 strip --strip-all
# relinkB.sh <prefix> <tag>          ：同上，对象取 /root/w/t02/bBN9（mpv v0.41.0 + b3 + libplacebo）
# bld2.sh <6|9> <tag> "<PRE>" "<POST>"  环境变量 WL=android 用 A 集；DROPDEC=hevc 去解码器；BSFO=列表 覆盖 bsf 白名单
./bld2.sh 9 v_all "--disable-bsfs --disable-iamf --disable-swscale-alpha" ""   # 输出 v_all <字节> 与 Bv_all <字节>
WL=android ./bld2.sh 9 a9s "--disable-bsfs --disable-iamf --disable-swscale-alpha" ""
# 归因：python3 mapagg2.py out/c6.map out/c9.map 40   （按库/成员，只算 text/rodata/eh_frame/relro/data，排除 .bss 与 .debug_*）
#       python3 symdiff.py out/c6.unstripped out/c9.unstripped 40 40   （按符号族，排除 b 类）
# 冒烟：gcc /root/w/t02/smoke.c -I/root/w/t02/mpvB/include -L<dir> -lmpv -o smoke && LD_LIBRARY_PATH=<dir> ./smoke tag url ...
```

构建目录 `/root/w/sl9/b/<tag>`（`conf.log` 含 `Enabled …` 摘要）、产物 `/root/w/sl9/out/<tag>.so`/`.map`；PRE 参数放在 `--enable-decoder/...` 白名单之前，所以 `--disable-bsfs` 先于 `--enable-bsf=` 生效。
