#!/usr/bin/env bash
# Linux x86_64 产物回归检查。用法：check-symbols-linux.sh   （本机 Windows 请在 WSL 里跑：wsl bash <本脚本>）
# 环境变量：LIBMPV_DIR 产物根目录；FFCONF_LOG 可选 configure 日志（严格许可/协议校验）
# 判据来自 build-mova-libmpv.yml 的 linux job：公开 API、dav1d(定义或 NEEDED)、LGPL 2.1、协议。
set -u
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

SO="$LIBMPV_DIR/linux-x86_64/libmpv.so"
section "linux-x86_64"
NM="$(first_cmd nm)"; RE="$(first_cmd readelf)"
if [ -z "$NM" ]; then bad "找不到 nm（Windows 请用 WSL）"; finish; exit 1; fi
[ -f "$SO" ] || { bad "产物不存在: $SO"; finish; exit 1; }
if is_lfs_pointer "$SO"; then bad "是 LFS 指针，先 git lfs pull"; finish; exit 1; fi
ok "存在，$(size_of "$SO") 字节"

syms="$(mktemp)"; _TMPS+=("$syms")
"$NM" -D --defined-only "$SO" > "$syms"
check_public_api "$syms"

# v1 链接系统 libdav1d.so：dav1d_open 是 undefined + DT_NEEDED，两种形态任一即可
if has_sym "$syms" dav1d_open; then ok "dav1d_open 已定义（静态内嵌）"
elif [ -n "$RE" ] && "$RE" -d "$SO" | grep -q 'libdav1d'; then ok "libdav1d 在 NEEDED 里（动态链接）"
else bad "dav1d 未链入（既无 dav1d_open 也无 libdav1d NEEDED）"; fi
[ -n "$RE" ] && echo "  [INFO] NEEDED: $("$RE" -d "$SO" | grep -c NEEDED) 个（Linux v1 依赖系统库，非自包含）"

strs="$(strs_file "$SO")"
# Linux 产物里 tls/tcp/http 作独立串实测不存在（会被合并），故只断言 https/rtmps/rtmp
check_protocols_strs "$strs" https rtmps rtmp
check_license "$strs" "${FFCONF_LOG:-}"
if [ -n "${FFCONF_LOG:-}" ] && [ -f "$FFCONF_LOG" ]; then
  for p in https tls rtmps; do
    if grep -qw "$p" "$FFCONF_LOG"; then ok "ffconf.log 含协议 $p"; else bad "ffconf.log 缺协议 $p"; fi
  done
fi
finish
