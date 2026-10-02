#!/usr/bin/env bash
# Windows x86_64 libmpv-2.dll 回归检查。用法：check-symbols-windows.sh （Windows 本机请在 WSL 里跑，需 objdump）
# 环境变量：LIBMPV_DIR 产物根目录；FFCONF_LOG 可选
# 判据来自 windows job "Strip and verify"。注意：CI 的 dav1d/ass/hb 内部符号是 strip 之前检查的，
# 已发布产物 strip 后只剩导出表，所以这里只能查导出符号 + 导入表 + 内嵌字符串，内部符号项标"未验证"。
set -u
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DLL="$LIBMPV_DIR/windows-x86_64/libmpv-2.dll"
section "windows-x86_64"
OD="$(first_cmd objdump llvm-objdump)"
if [ -z "$OD" ]; then bad "找不到 objdump（Windows 请用 WSL）"; finish; exit 1; fi
[ -f "$DLL" ] || { bad "产物不存在: $DLL"; finish; exit 1; }
if is_lfs_pointer "$DLL"; then bad "是 LFS 指针，先 git lfs pull"; finish; exit 1; fi
ok "存在，$(size_of "$DLL") 字节"

# 导出表：PE 没有 nm -D，用 objdump -p 的 Export Table 段，整理成"每行一个符号"
syms="$(mktemp)"; _TMPS+=("$syms")
"$OD" -p "$DLL" | awk '/Export Table/{e=1} e && /\[ *[0-9]+\]/{print $NF}' > "$syms"
echo "  [INFO] 导出符号数: $(wc -l < "$syms")"
check_public_api "$syms"

# 自包含：导入表里不许出现 MinGW 运行时（CI 同款硬失败项）
imps="$("$OD" -p "$DLL" | grep -i 'DLL Name' | awk '{print $NF}' | sort -u)"
echo "  [INFO] 导入 DLL: $(echo $imps | tr '\n' ' ')"
for d in libstdc++ libgcc_s libwinpthread; do
  if echo "$imps" | grep -qi "$d"; then bad "导入了 $d，不再自包含"; else ok "导入表无 $d"; fi
done
if echo "$imps" | grep -qiE '^(libmpv|libdav1d|libass|libav)'; then bad "导入了外部 mpv/ffmpeg/dav1d DLL"; else ok "无外部 mpv/ffmpeg/dav1d/ass DLL 依赖"; fi

skip "dav1d_open / ass_* / hb_shape 等内部符号：strip 后不可见，CI 只在 strip 前查；已发布产物未验证（间接证据见下面 libdav1d 字符串）"

strs="$(strs_file "$DLL")"
if grep -axq libdav1d "$strs"; then ok "libdav1d 解码器名存在（字符串代理）"; else bad "libdav1d 解码器名缺失"; fi
# Windows 产物内嵌了 ffmpeg configure 串：可直接核对许可、协议、解码器白名单
if grep -aq -- '--disable-gpl --disable-nonfree' "$strs"; then ok "configure 串含 --disable-gpl --disable-nonfree"; else bad "configure 串缺 --disable-gpl/--disable-nonfree"; fi
conf="$(grep -a -- '--enable-protocol=' "$strs" | head -1 | grep -ao -- "--enable-protocol='[^']*'")"
for p in $REQUIRED_PROTOS; do
  if echo "$conf" | grep -qE "[=',]$p[',]"; then ok "configure 协议白名单含 $p"; else bad "configure 协议白名单缺 $p"; fi
done
if grep -aq -- '--enable-schannel' "$strs"; then ok "TLS 后端为 schannel"; else bad "configure 串未见 --enable-schannel"; fi
# mpv 那一步用 clang（见计划 §7.1）：构建工具链证据不在产物里，无法从产物验证
skip "mpv 是否用 clang 编译：产物无此信息，需看 CI 日志，未验证"
check_license "$strs" "${FFCONF_LOG:-}"
finish
