# Windows x64 libmpv-2.dll 再瘦身调研（归因 + 逐项实测 + 组合）

日期：2026-10-02/03。只新增本笔记，未改仓库任何已有文件（`build-windows.sh`、CI、`dist/` 均未动），未触发 GitHub Actions。构建树都在仓库外：`C:\Users\jelon\whep-win\libmpv\shrink\`（实验脚本、中间产物、测试媒体），原有 `base/n9plain/whep` 三棵树只读使用、没被破坏。

约定：**实测** = 本机跑出来的字节/现象；**推断** = 没实测的判断；**未测** 会明说。所有字节数是 strip 后的 `libmpv-2.dll`。

## 0. 结论先行

| 档位 | 字节 | 相对 whep 基线 14,510,592 | 说明 |
|---|---:|---:|---|
| 基线（本机 whep，`build-windows.sh` 原样复现） | 14,510,592 | — | CI 同配置 14,542,848（+32KB，工具链漂移，见 2026-10-02-windows-libmpv-whep-build.md） |
| **S**：功能无损组合 | **10,936,320** | **−3,574,272（−24.6%）** | 去 `.rsrc` 图标 + win-iconv 换 GNU libiconv + 源码构建 freetype/harfbuzz/libass（libass 只留 DirectWrite）+ ffmpeg `--disable-d3d12va`。整包重编实测 |
| **Sp**：S + `--disable-bzlib --disable-lzma` + gcc `--optflags=-Oz` | **10,816,000** | **−3,694,592（−25.5%）** | 同上，整包重编实测。`-Oz` 只贡献 −56KB，见 §4 风险，可不要 |
| M：Sp + 去 MPEG-2/VC-1 解码 + `HB_NO_AAT` | 10,320,384 | −4,190,208（−28.9%） | 含两个功能取舍，待拍板 |
| X：M + dav1d 仅 8-bit + 全栈去 unwind 表 | 9,088,512 | −5,422,080（−37.4%） | 含四个取舍，其中 unwind 表有崩溃回溯风险，待拍板 |

回归（§3）：S/Sp/M/X 都过了 init×5、本地 mp4、HLS、AV1(8bit)、HEVC 10bit、VP9+Opus、D3D11VA（`d3d11va-copy`）、GBK/Big5/SJIS/CP1251/EUC-KR/GB18030/UTF-16 外挂字幕、ASS 渲染（含中日韩阿拉伯）、WHEP；`check-symbols-windows.sh` 全 PASS；导出符号数与基线同（54 个 `mpv_*` + 1 个非 mpv 前缀项，共 55）。X 里 10bit AV1 软解按预期失败（取舍项）。

**体积的大头不在 ffmpeg/mpv，而在 pacman 预编译的第三方静态库**：GNU libiconv 1.1MB、fontconfig+expat+libintl 约 0.73MB、freetype 的 png/brotli/bz2 与 harfbuzz 的 graphite2/uniscribe 约 0.8MB，加上 mpv.rc 的 274KB 图标，合计 ≈ 3.5MB，且全部不影响功能（逐像素/逐字验证过）。

## 1. 归因（本机 whep 基线 14,510,592）

方法：`-Wl,-Map`（GNU ld）按输入归档/段汇总，只算非 debug 段、不算 `.bss`（脚本 `shrink\attr.py`，思路同 `build-windows.sh` 的 `map-by-archive.txt`，但**去掉了 debug 段和 `.bss`**——原 `map-by-archive.txt` 的数字包含 debug 段，会严重高估，如 libavcodec 23.5MB）。本机没有 bloaty / llvm-size，用的就是 map + `objdump -h`。

### 1.1 按 PE 段（`objdump -h`，字节）

| 段 | 字节 | 占比 | 备注 |
|---|---:|---:|---|
| `.text` | 10,250,448 | 70.6% | |
| `.rdata` | 3,396,160 | 23.4% | 含 libiconv 码表 ~970KB、brotli 字典 126KB、unibreak 表 83KB、fribidi 表 86KB |
| `.rsrc` | 273,912 | 1.9% | mpv.rc：图标 + manifest，libmpv 用不到 |
| `.xdata` | 259,612 | 1.8% | x64 unwind info |
| `.pdata` | 242,028 | 1.7% | x64 RUNTIME_FUNCTION |
| `.reloc` | 47,008 | 0.3% | |
| `.idata` | 22,812 | 0.2% | |
| `.data` | 12,920 | 0.1% | |
| `.edata` / `.tls` | 1,687 / 64 | — | |
| `.bss` | 2,908,400 | 不占文件 | 虚拟大小 |

### 1.2 前三十大头（按输入归档/目标，字节，非 debug、不含 bss）

归档级（合计 14,451,206，与 DLL 14.51MB 吻合）：

| # | 归档 | 字节 | 主要段 |
|---|---|---:|---|
| 1 | libavcodec.a | 3,826,540 | text 3.17M / rdata 0.51M / xdata+pdata 0.16M |
| 2 | libdav1d.a | 1,658,171 | text 1.51M（8/16-bit 两套） |
| 3 | libharfbuzz.a（pacman） | 1,363,120 | text 1.18M |
| 4 | mpv 自身对象 | 1,327,326 | text 0.81M / rdata 0.45M |
| 5 | **libiconv.a（GNU）** | 1,096,512 | **rdata 0.97M**（整张码表） |
| 6 | libswscale.a | 845,612 | |
| 7 | libfreetype.a（pacman） | 717,588 | |
| 8 | libavformat.a | 583,528 | |
| 9 | libavutil.a | 541,004 | |
| 10 | **libfontconfig.a** | 412,096 | |
| 11 | **mpv.rc（.rsrc）** | 273,912 | |
| 12 | libass.a（pacman） | 237,416 | |
| 13 | **libpng16.a** | 195,724 | freetype 的可选依赖 |
| 14 | **libexpat.a** | 192,012 | fontconfig 的依赖 |
| 15 | **libgraphite2.a** | 143,912 | harfbuzz 的可选依赖 |
| 16 | **libintl.a** | 128,348 | |
| 17 | **libbrotlicommon.a** | 129,004 | freetype 的可选依赖 |
| 18 | libfribidi.a | 98,296 | libass 必需 |
| 19 | libunibreak.a | 88,352 | libass 必需（可关，见 §2） |
| 20 | libswresample.a | 88,320 | |
| 21 | libmingwex.a | 85,472 | |
| 22 | libstdc++.a | 74,584 | harfbuzz C++ |
| 23 | libavfilter.a | 69,516 | |
| 24 | **libbz2.a** | 64,880 | ffmpeg matroska + freetype |
| 25 | libz.a | 61,900 | |
| 26 | **libbrotlidec.a** | 44,388 | |
| 27 | libwinpthread.a | 32,596 | |
| 28 | libplacebo.a | 24,501 | |
| 29 | libmsvcrt.a | 21,626 | |
| 30 | libkernel32.a / user32 | ~7,000 | 导入桩 |

加粗的 8 项（iconv、fontconfig、expat、libintl、png、graphite2、brotli、bz2 + mpv.rc）就是"可不砍功能就去掉"的那部分，合计约 2.9MB 原始字节。

目标文件级最大者（节选）：libiconv.a(iconv.o) 1,095,392；osdep_mpv.rc 273,912；harfbuzz hb-ot-layout 265,052 / hb-ot-font 170,540 / hb-aat-layout 126,788；libavcodec vp9recon 204,000、dsp_init(x86 合计)、vp9itxfm 139,456、h264qpel 114,124、vp9lpf 99,620、cbs_av1 69,796；libavutil tx_float 180,812；libswscale output.o 178,992、input.o 80,248、swscale_unscaled 78,512、**uops_backend 67,448 + ops 61,872 + ops_float 48,224 + ops_int 31,968（n9 新增的 ops 层，合计约 210KB，configure 无开关）**；libavformat mov.o 108,928、rtmpproto 31,368、whep.o 25,188；brotli dictionary 123,040；fontconfig fcgenericalias 115,044；mpv player_command 177,467。

### 1.3 瘦身后的归因（X 档，对照）

`.pdata`+`.xdata` 从 463KB 降到 12KB；libdav1d 1.66M → 0.99M；harfbuzz 1.36M → 0.51M；freetype 0.72M → 0.46M；libiconv/fontconfig/expat/libintl/png/brotli/graphite2/bz2/mpv.rc 全部消失。

## 2. 逐项实测

基线统一为 **14,510,592**（`f0` 用同一套脚本复现，字节完全一致，证明实验台可信）。每项只改一个变量；"整包重编"= 用该变量重新 configure + 全量编译 ffmpeg/mpv/依赖。链接类实验复用基线的 mpv 对象仅重链。

### 2.1 链接器 / 优化手段

| 手段 | 字节 | 收益 | 功能影响 | 风险/备注 |
|---|---:|---:|---|---|
| lld 替换 ld.bfd（`-fuse-ld=lld`，去掉 lld 不认的 `--allow-shlib-undefined -Bsymbolic`） | 14,536,192 | **+25,600（更大）** | 无 | 没收益 |
| lld `--icf=all` | 14,515,712 | +5,120（对 bfd）/ −20,480（对 lld） | 无 | `--icf=safe` 字节完全相同；ffmpeg 对象无 `-ffunction-sections`，ICF 无从折叠。**不推荐** |
| `-Wl,--no-insert-timestamp` / `--strip-all` | 14,510,592 | 0 | 无 | 已 strip；不改变字节 |
| 去 `.reloc`（`--disable-dynamicbase`+`--disable-reloc-section`） | 14,510,592 | 0 | — | **ld 对 DLL 直接忽略**（`.reloc` 仍是 47,008），DllCharacteristics 只丢了 ASLR 位。DLL 需要重定位，绝对不可行也不该做 |
| mpv 对象 ThinLTO（`-flto=thin` + lld） | 14,522,368 | +11,776（对 bfd）/ −13,824（对 lld） | 无 | 无收益 |
| ffmpeg gcc `-flto`（NASM 对象与 LTO 混链，用 gcc 驱动链接） | 14,512,640 | +2,048 | 无 | **Windows 上 NASM+gcc LTO 能链接通过**（Linux 曾失败），但零收益，且 LTRANS 串行 87 个很慢 |
| ffmpeg clang ThinLTO | 未测 | — | — | 本机 MSYS2 没有 `llvm-ar`/LLVMgold，GNU `ar` 无法给 bitcode 建符号表；装 `mingw-w64-x86_64-llvm` 才有，我没改系统包 |
| ffmpeg `-ffunction-sections -fdata-sections`（gcc） | 17,174,528 | **+2,663,936（+18%）** | 无 | **复现了 09-17 的旧结论并查清原因**：`-fdata-sections` 让零初始化的大静态表从 `.bss` 变成文件里的 `.data`（libavcodec `.data` 1.55MB、libavutil 1.06MB）；`.text` 也没因 gc 变小（+72KB）。单独 `-ffunction-sections`：14,585,856（+75,264）。都不要 |
| `-fno-asynchronous-unwind-tables -fno-unwind-tables`，仅 ffmpeg | 14,250,496 | −260,096（−1.8%） | 见 §4 | 去 `.pdata/.xdata` 的唯一可行办法，**有崩溃回溯风险** |
| 同上，仅 mpv 对象 | 14,430,720 | −79,872 | 同上 | |
| 同上，全栈整包重编（Sp+unwind，档位 U） | 10,203,648 | 对 Sp **−612,352（−5.7%）** | 同上 | `.pdata/.xdata` 463KB → 12KB |

### 2.2 `-Os` vs `-Oz`、`--enable-small`、编译器

| 手段 | 字节 | 收益 | 说明 |
|---|---:|---:|---|
| ffmpeg gcc `--optflags=-Oz`（默认 `-Os`） | 14,454,272 | −56,320（−0.4%） | 和 gcc 对单个 mpv 对象的 -Os→-Oz 差异（command.c 178,324→176,596，−1%）一致 |
| ffmpeg 改 clang（默认 `-Os`） | 14,719,488 | **+208,896** | clang 编 ffmpeg 更大 |
| ffmpeg clang `--optflags=-Oz` | 14,720,000 | +209,408 | clang 的 -Oz 对 ffmpeg 与 -Os 几乎同字节（.a 29,748,256 vs 29,748,238）。所以"clang 更小"不成立 |
| ffmpeg 去掉 `--enable-small` | 19,833,856 | **+5,323,264** | 现状已吃满，别动 |
| mpv 自身 | — | — | 现 clang + meson `minsize` 已经就是 `-Oz`（编译命令里可见）。mpv 侧没有 `-Os→-Oz` 的余量 |

**CI 上 `-Oz` 只小 11KB、本机小 11.2% 的差异**：我**没能复现 11.2%，也没查出根因**，只给证据：①当前 mpv 对象用 clang，meson `buildtype=minsize` 直接给 `-Oz`（命令行可见），已经生效；②gcc 16.2 的 `-Oz` 对 ffmpeg 只比 `-Os` 小 0.4%，对 mpv 单文件小 1%；③clang 的 `-Oz` 对 ffmpeg 与 `-Os` 同字节。以上三点说明，09-17 记录的"本地 −11.2%"不是靠 gcc 的 `-Oz` 本身能得到的（**推断**：当时本机是混了 clang/gcc 或别的变量），我这里没有那份旧环境，无法证实。

### 2.3 ffmpeg 配置裁剪

| 手段 | 字节 | 收益 | 功能影响 | 备注 |
|---|---:|---:|---|---|
| `--disable-d3d12va` | 14,490,112 | −20,480 | 无（mpv v0.41 不用 d3d12va；D3D11VA 仍在） | n9 自动探测打开了 d3d12va 硬解表 |
| `--disable-iconv --disable-bzlib`（libiconv 仍被 mpv 链入） | 14,508,544 | −2,048 | — | ffmpeg 侧 iconv/bz2 本身只有几 KB；大头在 libiconv.a 本体，见 §2.5 |
| 整包里 `--disable-bzlib --disable-lzma` | S→Sp：−120,320 | 其中 −64KB 属于这两项（余下是 `-Oz`） | 损失：mkv 里 bz2 压缩的头部（几乎不存在）；lzma 本机 configure 探测到了但没代码引用 | 同时让 libbz2.a 出链 |
| 去 rtmpt/rtmpts/ffrtmpcrypt/ffrtmphttp | 14,507,008 | −3,584 | 失去 RTMP 隧道/加密变体，rtmp/rtmps 仍在 | 收益太小 |
| 去整个 RTMP 家族（含 rtmps） | 14,471,168 | −39,424 | 失去 RTMP 直播 | 不值 |
| `--disable-decoder=mpeg2video,vc1`（n9 里 hwaccel 会 select 软解 decoder，`--enable-d3d11va` 把它们带进来了） | 14,098,432 | **−412,160（−2.8%）** | **失去 MPEG-2（DVD/部分 TS 电视流）与 VC-1/WMV3 播放**，连带硬解表。实测 M 档播 mpeg2 ts：`error=-16` | **待用户拍板** |
| `--disable-x86asm` | 12,713,984 | −1,796,608（−12.4%） | 全部 ffmpeg 手写 SIMD 退回 C。实测单线程软解 1080p30 h264 10 秒：基线 1.20–1.27s，去 asm 1.84–1.99s，**约慢 1.6 倍**（合成素材，真实内容通常差距更大）；dav1d 自己的 asm 不受影响 | 软解/低端机体验受伤，**不推荐** |
| ffmpeg libswscale n9 新增 ops 层（~210KB） | 未测 | — | — | configure 无开关，要改源码，没做 |
| filters / 其余 bsf / demuxer | — | — | — | 实测 `config_components.h`：filter 已为 0（只有 png encoder），demuxer/parser/bsf 白名单都是 mova 所需，没发现可再收的 |
| `x86asm` 之外 mpv 侧 meson 开关 | — | — | — | 对照 `config.h`：lua/javascript/cdda/dvdnav/libarchive/uchardet/jpeg/lcms2/vulkan/egl 全是 0，已经最小；`auto_features=disabled` 无可砍项（推断，与 whep-build 笔记一致） |

### 2.4 AV1 / D3D11VA（按用户补充：不再是硬约束，单列取舍）

| 手段 | 字节 | 收益 | 功能后果（实测） |
|---|---:|---:|---|
| dav1d `-Dbitdepths=8`（单变量，relink） | 13,854,208 | **−656,384（−4.5%）** | 8-bit AV1 软解正常；**10-bit/12-bit AV1 软解失败**（`error=-16`）。HDR/10bit AV1 在没有 AV1 硬解的机器上无法播。整包重编（Sp+该项）10,160,128，对 Sp −655,872 |
| 完全去掉 dav1d（`--disable-libdav1d` 并去 decoder 白名单） | 12,846,592 | **−1,664,000（−11.5%）** | 不开硬解时 AV1 全部失败（`Error while decoding frame`，`error=-16`）。**开 `hwdec=d3d11va-copy` 在本机 Intel UHD 770 上 8-bit 和 10-bit AV1 都能播**。结论：不支持 AV1 硬解的机器彻底无法播 AV1 |
| 去 D3D11VA（`--disable-d3d11va`，保留 DXVA2） | 14,497,280 | −13,312 | 只是少了 d3d11va2 hwaccel 表 |
| 去 D3D11VA + DXVA2（`--disable-d3d11va --disable-dxva2`） | 14,477,312 | −33,280（−0.2%） | 再加 mpv 侧 `-Dd3d-hwaccel=disabled -Dd3d9-hwaccel=disabled -Dgl-dxinterop*=disabled` 另有 −17,408（relink）。**总收益约 50KB**。后果：h264/hevc/vp9 软解 decoder 都还在（白名单 `h264,hevc,vp9`），实测 `hwdec=no` 播 h264 正常，代价是高清视频 CPU/功耗上升 |

D3D11VA 收益极小（硬解表很小，真正的体积在软解 decoder 里），**建议保留**；dav1d 是真有量级的取舍项（8-bit 版 −0.66MB，整个去掉 −1.66MB）。这两项我只列收益/代价，不替你决定。

### 2.5 第三方库（pacman 预编译 → 源码重建）

pacman 的 freetype 开了 harfbuzz/png/brotli/bz2；harfbuzz 开了 graphite2/glib/uniscribe(usp10)/DirectWrite/GDI；libass 同时开 fontconfig + DirectWrite；libiconv 是完整 GNU 版。

| 手段 | 字节 | 收益 | 功能影响（实测） | 备注 |
|---|---:|---:|---|---|
| **win-iconv 换 GNU libiconv**（`win_iconv.c` 单文件，走 Windows 代码页 API；relink 实验用 `libiconv_*` 别名版） | 13,431,296 | **−1,079,296（−7.4%）** | 8 种编码外挂字幕解码逐字相同：GBK/Big5/Shift-JIS/CP1251/EUC-KR/CP1252/GB18030（含增补平面字 𠀀）/UTF-16 BOM/UTF-8 BOM。`sub-codepage=auto` 无 uchardet 时的行为（GBK 不指定编码得到乱码）在换前换后**完全一致**，不是回归 | 公有领域许可；ffmpeg 要加 `-DWINICONV_CONST=`（mpv 本来就带这个宏） |
| **libass 源码构建，仅 DirectWrite、无 fontconfig**（连带 expat、libintl 出链） | 13,703,680 | **−806,912（−5.6%）** | ASS 渲染（Arial 拉丁字、微软雅黑 + 中日韩 + 阿拉伯文 + emoji 行）与基线 PNG **逐字节相同（md5 一致）** | `-Dfontconfig=disabled -Ddirectwrite=enabled`。libass 的 iconv 是 `required: false`，不是硬依赖 |
| **freetype 源码构建：仅 zlib，无 png/brotli/bz2/harfbuzz**（clang `minsize`） | 13,915,648 | **−594,944（−4.1%）** | 无可见变化。丢的是 PNG 彩色位图字体（CBDT/sbix）、WOFF2 内嵌字体，ASS 内嵌字体是 TTF/OTF，不受影响 | 该项里保留 libbz2（ffmpeg 还在用）；整包里 bz2 随 `--disable-bzlib` 一起出链 |
| **harfbuzz 源码构建：无 graphite2/glib/uniscribe/GDI/DirectWrite**（在 freetype 项基础上） | 13,115,392 | 在 freetype 项上再 **−800,256**；两项合计 −1,395,200（−9.6%） | 渲染同上无变化 | 一部分来自 clang `-Oz` 与 pacman 的 `-O2`（没单独拆开，**未测**这一块占比） |
| harfbuzz 再加 `-DHB_NO_AAT` | 13,022,208 | 再 −93,184 | 丢 Apple AAT 排版表（苹果字体），字幕基本用不到 | 待拍板，收益小 |
| harfbuzz `-DHB_MINI` | 12,968,960 | 再 −146,432 | 按文档会删更多遗留表；**没做功能回归** | 不推荐 |
| libass `-Dlibunibreak=disabled` | 10,867,200（叠加在全栈 relink 10,956,288 上） | −89,088 | 失去 UAX#14 断行（中日韩等换行质量下降） | 不推荐（目标用户是中文场景） |
| **mpv.rc 去掉**（`osdep/mpv.rc` 仅 `cplayer=true` 时编） | 14,236,672 | **−273,920（−1.9%）** | 无；导出 55 个符号不变 | 补丁见 §6.2 |
| 五项合并 relink（iconv+freetype+harfbuzz+libass+norc） | 10,956,288 | **−3,554,304（−24.5%）** | 回归全过（§3） | 与整包重编 S 档 10,936,320 差 20KB（S 多一个 `--disable-d3d12va`） |

其它核对（回答任务里的点名项）：mbedtls 没链入（导入表仅 SChannel 系：`Secur32/ncrypt/CRYPT32/bcrypt`）；libplacebo 静态仅 24,501 字节；`.rsrc` 就是 mpv.rc 的 273,912；d3d11/ANGLE 相关：本机 v0.41 build 的 `config.h` 是 `HAVE_D3D11=0 HAVE_EGL_ANGLE=0 HAVE_GL_WIN32=1 HAVE_GL_DXINTEROP=1`，mpv 自己没有 shader/ANGLE 资源可砍；**所有实验 `config.h` 的特性集不变**。

另：`HAVE_EGL_ANGLE=0` 意味着当前这个 mpv 构建里没有 d3d11 gpu-context 与 ANGLE hwdec 互操作，这是现状（早于本次调研），我没改也没评估过 mova 在 Windows 上实际走哪条渲染路径，**请确认**任务里"当前所用的 d3d11/ANGLE 渲染后端"是否指别的构建。

## 3. 组合与回归

组合构建：`shrink\build-shrink.sh`（`build-windows.sh` 的拷贝 + 补丁，§6.1），`MODE=whep`，环境变量选档：

```
S   (默认)
Sp  FF_OPTFLAGS=-Oz  FF_ADD="--disable-bzlib --disable-lzma"
M   Sp + FF_ADD+="--disable-decoder=mpeg2video,vc1"  HB_FLAGS=-DHB_NO_AAT
X   M  + DAV1D_BITDEPTHS=8  UNW="-fno-asynchronous-unwind-tables -fno-unwind-tables"
U   Sp + UNW=...            D8  Sp + DAV1D_BITDEPTHS=8
```

整包重编结果：S 10,936,320；Sp 10,816,000；M 10,320,384；X 9,088,512；U 10,203,648；D8 10,160,128。（M−Sp = −495,616 ≈ 单项 mpeg2/vc1 −412,160 + HB_NO_AAT −93,184；X−M = −1,231,872 ≈ D8 −655,872 + U −612,352，吻合。）

回归（`shrink\mt.c`：基于 libmpv API 的小工具，`vo=null ao=null`，除标注外；`shrink\T.sh` 为脚本；以下对基线、S、Sp、M、X 都跑了，**全部符合预期，M/X 的差异只在取舍项**）：

- `mpv_create/initialize/terminate_destroy` ×5：各档 fails=0。
- 本地 mp4（H.264+AAC）、HLS（本地 `python -m http.server`，H.264+AAC）、VP9+Opus(webm)、AV1 8-bit、AV1 10-bit、HEVC 10-bit：time-pos 推进正常；X 档 10-bit AV1 失败（预期）。M/X 档 MPEG-2 ts 失败（预期，基线能播）。
- D3D11VA：`hwdec=d3d11va-copy` 下 h264、hevc10 的 `hwdec-current=d3d11va-copy`，各档一致。
- 外挂字幕编码 8 种（见 §2.5）+ ASS：`sub-text` 与基线一致；`vo=image`(png) 渲染中日韩+阿拉伯+emoji 的 ASS，基线/S/Sp/M 的 md5 完全相同（`82a224fd…`），拉丁 ASS 帧与基线 0 字节差异。
- 异常输入（截断 mkv、截断 mp4、随机 40KB 垃圾）在 Sp 与 X 上返回码/行为一致，无崩溃。
- `check-symbols-windows.sh`：基线/Sp/M/X 都是 PASS=15 FAIL=0 SKIP=2。注意脚本的"导出符号数"行不准（基线显示 108，Sp 显示 3209，数的是 objdump 后续段里别的 `[n]` 行），**真实导出数我用 Export Table 的 Name Pointer 表另数：各档均为 54 个 `mpv_*` + 1 个非 `mpv_` 前缀项（共 55），与基线相同**。
- WHEP（Windows 版 MediaMTX v1.21.1，端口 18554/18889/18189，ffmpeg 推 H264 baseline + Opus；只按自己 PID 停进程，结束后无残留）：`whep+http://127.0.0.1:18889/test/whep` 拉流 12 秒，基线 ×5、Sp ×5（交替跑，同一个 MediaMTX 实例）、M ×2、X ×3，**全部 time-pos 推进到 10.1–10.96s、帧数 253–274、h264+opus**。**一次例外**：Sp 档在一次全新启动 MediaMTX+推流后的首个会话报 `whep: DTLS handshake failed: Unknown error occurred`（`error=-17`）。随后所有会话（含 Sp ×6）都成功；该次发生在上一轮 MediaMTX 刚停的紧接着，我**没有再复现、也没定位根因**，不把它算到 Sp 头上，但也不能保证它是环境问题（**未归因**）。WHEP 详细统计（RTP lost/RTCP）本次没抓：`mt.c` 的日志收集只在收尾 1.5 秒窗口读，没拿到对应行，所以只确认"能出画面/时钟推进/解码"，**没重复** whep-build 笔记里的丢包重传、指纹篡改项。
- 未测：iOS/其他平台、画面输出到真实窗口（`vo=gpu`）、音频设备输出、长时间稳定性、Win11/Server。

## 4. 风险评估

| 项 | CI 可复现性 | 崩溃/功能风险 |
|---|---|---|
| 去 mpv.rc | 高：只改 meson.build 一处（补丁 §6.2），无工具链依赖 | 低。注意 `cplayer=true` 构建仍会编，不影响 |
| win-iconv | 高：源码单文件（tag v0.0.10），无依赖。要注意 **meson 的 `dependency('iconv')` 只走 system 方式，不吃 pkg-config**，必须靠 `CPATH`/`LIBRARY_PATH` 才能让 libass/mpv 选中前缀里的 win-iconv（我踩到了：第一次 libass 仍引用 `libiconv_open`，GNU libiconv 被一并链入，体积不变，看起来像"没生效"）。判据：map 里不能再出现 `/mingw64/lib/libiconv.a` | 低中。行为差异是**编码覆盖面取决于 Windows 代码页**（GBK/Big5/SJIS/KR/GB18030/UTF-16 都实测过；`//TRANSLIT`/`//IGNORE` 之类 GNU 扩展后缀 win-iconv 不全支持，**未测 mpv 是否用到**）。ffmpeg 需要 `-DWINICONV_CONST=` |
| 源码构建 freetype/harfbuzz/libass | 中高：tag 钉死（VER-2-14-3 / 14.4.0 / 0.17.5），比"跟 runner 当日 pacman 滚动版本"更稳；但要多跑 4 个步骤，增加 CI 时长约 4–5 分钟（本机 20 核估计；**CI runner 耗时未测**）。libass 需 `-Dcheckasm=disabled`，否则 checkasm.exe 在 iconv 变化后链接失败 | 低。渲染逐字节对照过。**未测**：clang `-Oz` 编的 harfbuzz/freetype 对字幕渲染 CPU 的影响（pacman 是 `-O2`），极重特效 ASS 可能更吃 CPU |
| ffmpeg `--disable-d3d12va`、`--disable-bzlib --disable-lzma` | 高 | 低 |
| ffmpeg gcc `-Oz` | 中：只带来 −56KB（0.4%），而仓库里有"gcc 16.2 miscompile"史（影响的是 mpv，已换 clang；ffmpeg 仍是 gcc）。本机 gcc 16.2.0 编的 Sp/M/X 全部解码回归通过，但**没有压力测试**。**建议不要为这 0.4% 引入新变量**，Sp 去掉 `-Oz` 的预期体积 ≈ 10.87MB（推断） | 低 |
| MPEG-2 / VC-1 去除 | 高 | 功能取舍，见 §2.3，待拍板 |
| dav1d 仅 8-bit / 去掉 | 高 | 功能取舍，见 §2.4，待拍板 |
| **全栈去 unwind 表（`.pdata/.xdata`）** | 高（只是编译参数） | **有实质风险，不建议默认采用**。实测证据：X 档用 `RtlLookupFunctionEntry` 查 `mpv_create/initialize/command/wait_event`，**全部查不到 unwind 项**（Sp 档都有）。x64 Windows 上这意味着：① 任何经过这些帧的 SEH 异常分发/`RtlUnwindEx`/`longjmp` 展开都会拿不到帧信息；② Dart/Flutter 崩溃回溯、WER 转储、ETW 栈采样在 libmpv 内部断帧；③ 宿主若依赖 vectored/structured exception 处理 libmpv 内部异常，行为变成未定义。X 档我跑了异常输入（垃圾文件、截断流）没崩，但那些路径不走异常展开，**不能证明安全**。收益 −612KB（−5.7%） |
| lld/ICF/LTO | — | 不采用，无收益 |
| 去 `.reloc` | — | 不可行：ld 对 DLL 忽略该选项；去 ASLR 位没有体积收益只有安全损失 |

CI 与本机差异提醒：本机 MSYS2 是滚动快照（clang 22.1.8 / gcc 16.2.0 / binutils 2.47 / freetype 2.14.3 / harfbuzz 14.4.0 / libass 0.17.5），runner 的快照版本没拿到。源码构建的 3 个库钉死 tag 后，只剩 fribidi、libunibreak、zlib 仍随 pacman 漂移。基线 CI 14,542,848 vs 本机 14,510,592 的 32KB 漂移预计会同样出现在新档位上（推断）。

## 5. 推荐

**直接采纳（功能无损，已整包实测）——S/Sp 档：10.82–10.94MB，较 14.51MB 小 24.6–25.5%，较现行 dist 14,075,392 小 22–23%：**

1. 去 mpv.rc 图标（−274KB）
2. win-iconv 替换 GNU libiconv（−1,079KB）
3. libass 源码构建，仅 DirectWrite 去 fontconfig（−807KB，连带 expat/libintl）
4. freetype 去 png/brotli/bzip2/harfbuzz，harfbuzz 去 graphite2/uniscribe/GDI/DirectWrite（合计 −1,395KB）
5. ffmpeg `--disable-d3d12va`（−20KB）；`--disable-bzlib --disable-lzma`（≈ −64KB）

**待用户拍板（收益 / 代价，不替你定）：**

| 项 | 收益 | 代价 |
|---|---:|---|
| 去 MPEG-2 + VC-1 解码 | −412KB | DVD/部分电视 TS/WMV3 无法播 |
| dav1d 仅 8-bit | −656KB | 10-bit/HDR AV1 在无 AV1 硬解机器上无法播 |
| 完全去掉 dav1d | −1,664KB | 无 AV1 硬解的机器完全不能播 AV1；有硬解（本机 UHD770）开 `d3d11va-copy` 可播 |
| 去 D3D11VA/DXVA2 | 约 −50KB | 高清软解，CPU/功耗上升；收益太小，**建议保留** |
| 全栈去 unwind 表 | −612KB | 崩溃回溯/SEH 展开丢帧，见 §4，**不建议默认** |
| harfbuzz `HB_NO_AAT` | −93KB | 丢苹果 AAT 排版 |
| libass 关 libunibreak | −89KB | 中日韩换行质量下降，**不建议** |
| ffmpeg `--disable-x86asm` | −1,797KB | 软解慢约 1.6 倍，**不建议** |
| gcc `--optflags=-Oz` | −56KB | 引入新编译变量，**不建议为此** |

**预期可达字节数**：S/Sp 10.82–10.94MB（已测）；+MPEG-2/VC-1 + HB_NO_AAT ≈ 10.32MB（M，已测）；再 +dav1d 8-bit ≈ 9.7MB（推断：M−656KB；X 里的 9,088,512 还含 unwind −612KB）；去 dav1d 全部再减 ≈ 1.0MB 左右（推断，没整包测）。

## 6. 可复现命令与补丁片段

### 6.1 构建

```bash
# MSYS2 MINGW64 里，源码缓存先放好 $WORK/src（见 build-windows.sh 的 step_fetch + 下面 deps_fetch）
C:\tools\msys64\usr\bin\env.exe MSYSTEM=MINGW64 CHERE_INVOKING=1 MODE=whep TAG=S WORK=/c/Users/jelon/whep-win/libmpv/shrink/full \
  JOBS=12 /usr/bin/bash -l build-shrink.sh                     # S 档
# Sp:  FF_OPTFLAGS=-Oz FF_ADD="--disable-bzlib --disable-lzma"
# X:   另加 DAV1D_BITDEPTHS=8  UNW="-fno-asynchronous-unwind-tables -fno-unwind-tables"  HB_FLAGS=-DHB_NO_AAT
#      FF_ADD 再加 --disable-decoder=mpeg2video,vc1
```

对 `tools/whep-flavor/build-windows.sh` 的补丁（`diff -u` 摘要，**未应用**；`build-shrink.sh` 是仓库外的拷贝）：

```diff
@@ 路径与常量（PATH 之后）
 export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:/mingw64/lib/pkgconfig"
+# meson 的 dependency('iconv') 只走 system，不看 pkg-config；靠这两个变量让头文件/库先命中前缀里的 win-iconv
+export CPATH="$(cygpath -m "$PREFIX")/include" LIBRARY_PATH="$(cygpath -m "$PREFIX")/lib"
@@ step_dav1d
-    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Dbitdepths=8,16) \
+    -Denable_tools=false -Denable_tests=false -Denable_examples=false -Dc_args="${UNW:-}" -Dbitdepths=${DAV1D_BITDEPTHS:-8,16}) \
@@ step_ffmpeg（configure 末尾）
-    --enable-network \
+    --enable-network --extra-cflags="-I$PREFIX/include -DWINICONV_CONST= ${UNW:-}" --extra-ldflags="-L$PREFIX/lib" --disable-d3d12va ${FF_OPTFLAGS:+--optflags=$FF_OPTFLAGS} ${FF_ADD:-} \
@@ 新增步骤，插在 step_ffmpeg 与 step_plc 之间
+FT_TAG="VER-2-14-3"; HB_TAG="14.4.0"; ASS_TAG="0.17.5"; WICONV_TAG="v0.0.10"
+step_deps_fetch() {
+  clone_tag win-iconv https://github.com/win-iconv/win-iconv.git "$WICONV_TAG"
+  clone_tag freetype  https://gitlab.freedesktop.org/freetype/freetype.git "$FT_TAG"
+  clone_tag harfbuzz  https://github.com/harfbuzz/harfbuzz.git "$HB_TAG"
+  clone_tag libass    https://github.com/libass/libass.git "$ASS_TAG"
+}
+step_winiconv() {
+  mkdir -p "$PREFIX/include" "$PREFIX/lib/pkgconfig"
+  clang -Oz -ffunction-sections -fdata-sections -c "$SRC/win-iconv/win_iconv.c" -o "$B/win_iconv.o"
+  rm -f "$PREFIX/lib/libiconv.a"; ar rcs "$PREFIX/lib/libiconv.a" "$B/win_iconv.o"
+  cp "$SRC/win-iconv/iconv.h" "$PREFIX/include/iconv.h"
+  printf 'prefix=%s\nlibdir=${prefix}/lib\nincludedir=${prefix}/include\nName: iconv\nDescription: win-iconv\nVersion: 1.17\nLibs: -L${libdir} -liconv\nCflags: -I${includedir} -DWINICONV_CONST=\n' "$PREFIX" > "$PREFIX/lib/pkgconfig/iconv.pc"
+}
+SH_FL="-ffunction-sections -fdata-sections ${UNW:-}"
+SH_M="--default-library=static --buildtype=minsize -Db_ndebug=true -Ddebug=false"
+step_freetype() {
+  rm -rf "$B/freetype"; cp -a "$SRC/freetype" "$B/freetype"
+  (cd "$B/freetype" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
+    -Dzlib=enabled -Dbzip2=disabled -Dpng=disabled -Dbrotli=disabled -Dharfbuzz=disabled -Dc_args="$SH_FL") > "$LOGS/ft-conf.log" 2>&1
+  ninja -C "$B/freetype/_build" install > "$LOGS/ft-build.log" 2>&1
+}
+step_harfbuzz() {
+  rm -rf "$B/harfbuzz"; cp -a "$SRC/harfbuzz" "$B/harfbuzz"
+  (cd "$B/harfbuzz" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
+    -Dglib=disabled -Dgobject=disabled -Dcairo=disabled -Dchafa=disabled -Dicu=disabled -Dgraphite2=disabled -Dfreetype=enabled \
+    -Dtests=disabled -Ddocs=disabled -Dutilities=disabled -Dbenchmark=disabled -Dintrospection=disabled \
+    -Dc_args="$SH_FL ${HB_FLAGS:-}" -Dcpp_args="$SH_FL ${HB_FLAGS:-}") > "$LOGS/hb-conf.log" 2>&1
+  ninja -C "$B/harfbuzz/_build" install > "$LOGS/hb-build.log" 2>&1
+}
+step_libass() {
+  rm -rf "$B/libass"; cp -a "$SRC/libass" "$B/libass"
+  (cd "$B/libass" && CC=clang CXX=clang++ meson setup _build --prefix="$PREFIX" --libdir=lib $SH_M \
+    -Dfontconfig=disabled -Ddirectwrite=enabled -Dlibunibreak=enabled -Dtest=disabled -Dcompare=disabled -Dprofile=disabled -Dcheckasm=disabled \
+    -Dc_args="$SH_FL") > "$LOGS/ass-conf.log" 2>&1
+  ninja -C "$B/libass/_build" install > "$LOGS/ass-build.log" 2>&1
+}
@@ step_plc
-    -Dc_args="-ffunction-sections -fdata-sections" -Dcpp_args="-ffunction-sections -fdata-sections") \
+    -Dc_args="-ffunction-sections -fdata-sections ${UNW:-}" -Dcpp_args="-ffunction-sections -fdata-sections ${UNW:-}") \
@@ step_mpv（work_copy / patch 之后）
+  git -C "$B/mpv" apply "$PATCHES/mpv-v041/win-no-rc.patch"      # §6.2；Windows-only，不要放进 Android 用的 mpv-v041 目录自动循环
@@ step_mpv meson
-    -Dc_args="-ffunction-sections -fdata-sections" \
+    -Dc_args="-ffunction-sections -fdata-sections ${UNW:-} -I$(cygpath -m $PREFIX)/include" \
-    -Dc_link_args="-Wl,-Bstatic -lstdc++ ...
+    -Dc_link_args="-L$(cygpath -m $PREFIX)/lib -Wl,-Bstatic -lstdc++ ...
@@ 主流程
-STEPS=...(fetch dav1d ffmpeg plc mpv finish)
+STEPS=...(fetch deps_fetch dav1d winiconv freetype harfbuzz libass ffmpeg plc mpv finish)
```

（注意：`patch_mpv_whep` 的 `for p in $PATCHES/mpv-v041/*.patch` 会把新文件一并 apply；放进该目录时需 `case` 排除 Android，或像上面那样单独放。）

### 6.2 mpv v0.41.0 去 mpv.rc 补丁（实测可 `git apply`，−273,920B）

```diff
--- a/meson.build
+++ b/meson.build
@@ -1767,8 +1767,10 @@ if win32
     resources = ['etc/mpv-icon.ico',
                  'osdep/mpv.exe.manifest']
 
-    sources += windows.compile_resources('osdep/mpv.rc', args: res_flags, depend_files: resources,
-                                         depends: version_h, include_directories: res_includes)
+    if get_option('cplayer')
+        sources += windows.compile_resources('osdep/mpv.rc', args: res_flags, depend_files: resources,
+                                             depends: version_h, include_directories: res_includes)
+    endif
 endif
```

### 6.3 CI 里的验收判据（建议加到 Strip and verify）

- map 中**不得**出现 `libiconv.a`（来自 `/mingw64`）、`libfontconfig`、`libexpat`、`libpng16`、`libbrotli*`、`libgraphite2`、`libintl`；
- `objdump -h`：`.rsrc` 段不存在；
- `check-symbols-windows.sh` 照旧；导出数请改用 Export Table 的 Name Pointer 表计数（现脚本计数不准）。

## 7. agy（Antigravity）说法核对

资料调研部分交给了 agy，本机逐条核对：

| agy 的说法 | 核对结果 |
|---|---|
| libass 0.17 "硬依赖 iconv，去掉只能兼容 UTF-8" | **证伪**：libass `meson.build:90` 是 `dependency('iconv', required: false)`；且实测 win-iconv 替换后外挂字幕编码全部不变 |
| mpv 无 MultiByteToWideChar 回退，去 iconv 会让 GBK 字幕乱码 | 这条对"直接去掉 iconv"成立（未实测，因为我没走这条路）；但**忽略了 win-iconv 这个替代**，用 win-iconv 实测 8 种编码零差异。也说明"去 iconv"不如"换 iconv" |
| `--icf=all` 对 nasm 对象无效且可能出运行时 bug，建议 `--icf=safe` | 无效这半句**对**（实测 all 与 safe 字节相同、总收益为负）；"运行时 bug"**无证据**，我没跑出问题 |
| ThinLTO 与 nasm 混链会丢寄存器保护/触发 lld bug | **未证实**。gcc LTO + nasm 对象在 Windows 上能链接通过（零收益）；clang ThinLTO 因缺 `llvm-ar` 没法测。"丢寄存器保护"没有任何证据 |
| clang `-Oz` 会"不计代价折叠"，ffmpeg 性能明显下降；gcc `-Oz` 较保守 | **证伪**：clang `-Oz` 对 ffmpeg 与 `-Os` 同字节；gcc `-Oz` 才小 0.4%；性能没测，无法评论 |
| mpv.rc 补丁：写成 `mpv_sources += compile_resources(..., 'etc/mpv-icon-8bit-16x16.png')` | **文件名/变量名错**：v0.41 实际是 `sources += compile_resources('osdep/mpv.rc', ..., depend_files: resources)`，条件是 `if win32`，依赖是 `etc/mpv-icon.ico` + manifest。**方向对**（按 cplayer 门控），我用修正后的补丁实测 −273,920B |
| HB_MINI 会同时去掉 AAT 和遗留表 | 部分对：实测 HB_MINI −146KB（相对基础 harfbuzz 源码构建），但我没做功能回归，所以不推荐；`HB_NO_AAT` 单项 −93KB 也已实测 |
| `.pdata` 去掉后 setjmp/longjmp 会受影响，DLL 崩溃无法抓栈 | **证据支持**：实测 X 档 `RtlLookupFunctionEntry` 查不到 unwind 项。但"宿主静默闪退"是推断，没实测 |
| 去 `.reloc` 致命，DLL 不可去 | **对**，且更彻底：ld 对 DLL 根本忽略 `--disable-reloc-section`，`.reloc` 仍在 |
| freetype/harfbuzz 选项名 `-Dbrotli -Dbzip2 -Dpng` / `-Dgraphite2` | 对，实测可用；另外 harfbuzz 需 `-Dfreetype=enabled` 与 freetype 的 `-Dharfbuzz=disabled`（破循环依赖）这一点它没提 |
| libass 去 fontconfig "完全可行" | 对，实测像素级一致 |

## 8. 下一步建议

1. 先把 S 档（§5 的 1–5 项）落到 `build-windows.sh`/CI：风险低、−24.6%。落地时盯住 §4 里 win-iconv 的链接判据（map 无 `/mingw64/lib/libiconv.a`）。
2. 你拍板 MPEG-2/VC-1、dav1d 位深/去留、unwind 表；其中 dav1d 是除 S 档外最大的一块（−0.66MB~−1.66MB）。
3. 若还要继续压：libswscale n9 ops 层约 210KB（要改源码）；libavcodec 的 vp9 10/12-bit 变体（vp9 的 10/12-bit 变体，数百 KB 量级，未精确量，ffmpeg 无开关，要改源码或精简 vp9 到 8-bit，会丢 10-bit VP9）。这两项都没实测。
4. 在 CI runner 上跑一次 S 档，确认 runner 的 MSYS2 快照下 map 判据成立、体积落在 ~10.9MB 附近。
5. 复核 mova 在 Windows 上实际用的渲染路径（见 §2.5 末尾关于 `HAVE_EGL_ANGLE=0` 的疑问）。
