#!/usr/bin/env bash
# 回归检查脚本的公共函数，被 check-symbols-*.sh 用 source 引入。
# 只读检查：不修改任何产物。判据复用 build-mova-libmpv.yml 各 job 的 "Strip and verify" 步骤。

# 仓库里产物的默认目录（mova/libmpv），可用环境变量 LIBMPV_DIR 覆盖
REGRESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBMPV_DIR="${LIBMPV_DIR:-$REGRESS_DIR/../../../mova/libmpv}"

# mova 实际会用到的 mpv 公开 API：CI 的 6 个 + FFI 弱客户端/事件订阅用到的几个
PUBLIC_API_SYMS="mpv_create mpv_initialize mpv_command mpv_set_option_string \
mpv_render_context_create mpv_terminate_destroy \
mpv_create_weak_client mpv_wait_event mpv_set_wakeup_callback mpv_observe_property"

# 必须在 --enable-protocol 里的协议（与 workflow 的 https/tls/rtmps 校验同口径，外加 tcp/http）
REQUIRED_PROTOS="https tls rtmps tcp http"

PASS_N=0; FAIL_N=0; SKIP_N=0
_TMPS=()

# 打印一条通过
ok()   { echo "  [PASS] $*"; PASS_N=$((PASS_N+1)); }
# 打印一条失败
bad()  { echo "  [FAIL] $*"; FAIL_N=$((FAIL_N+1)); }
# 打印一条跳过（环境缺工具或产物无此信息），不算失败，但汇报里要写明"未验证"
skip() { echo "  [SKIP] $*"; SKIP_N=$((SKIP_N+1)); }
# 打印分节标题
section() { echo; echo "== $*"; }

# 退出前清理临时文件
_cleanup() { [ ${#_TMPS[@]} -gt 0 ] && rm -f "${_TMPS[@]}"; return 0; }
trap _cleanup EXIT

# 汇总并以 0/1 退出
finish() {
  echo
  echo "汇总：PASS=$PASS_N FAIL=$FAIL_N SKIP=$SKIP_N"
  [ "$FAIL_N" -eq 0 ]
}

# 取文件字节数
size_of() { stat -c%s "$1" 2>/dev/null || wc -c < "$1"; }

# 判断文件是 Git LFS 指针而非真实产物（指针只有百来字节）
is_lfs_pointer() { head -c 40 "$1" 2>/dev/null | grep -q '^version https://git-lfs'; }

# 在 PATH 里按顺序找第一个存在的命令，找不到返回空
first_cmd() { local c; for c in "$@"; do command -v "$c" >/dev/null 2>&1 && { echo "$c"; return; }; done; }

# 把二进制里的 NUL 分隔字符串拆成行，缓存到临时文件，输出临时文件路径
strs_file() {
  local t; t="$(mktemp)"; _TMPS+=("$t")
  tr '\0' '\n' < "$1" > "$t"; echo "$t"
}

# 检查符号：$1=符号列表文件(nm 输出)  $2=符号名 -> 全词匹配
has_sym() { grep -qw -- "$2" "$1"; }

# 检查公开 API 符号是否都在导出表里；$1=导出符号列表文件
check_public_api() {
  local f="$1" s miss=""
  for s in $PUBLIC_API_SYMS; do has_sym "$f" "$s" || miss="$miss $s"; done
  if [ -z "$miss" ]; then ok "公开 API 符号齐全（$(echo $PUBLIC_API_SYMS | wc -w) 个）"; else bad "公开 API 缺失:$miss"; fi
}

# 许可检查：$1=产物字符串文件  $2=可选 ffconf.log 路径
# 有 ffconf.log 时严格按 CI 口径 grep；没有则看产物内嵌的 "license:" 串，都没有就跳过
check_license() {
  local strs="$1" conf="${2:-}"
  if [ -n "$conf" ]; then
    if [ -f "$conf" ]; then
      if grep -q 'License: LGPL version 2.1' "$conf"; then ok "ffconf.log: License: LGPL version 2.1"; else bad "ffconf.log 不是 LGPL v2.1"; fi
    else bad "ffconf.log 不存在: $conf"; fi
    return
  fi
  if grep -aq 'license: LGPL version 2.1 or later' "$strs"; then
    ok "产物内嵌 'license: LGPL version 2.1 or later'"
  elif grep -aqE 'license: (L?GPL version 3|GPL)' "$strs"; then
    bad "产物内嵌了 GPL/LGPLv3 许可串"
  else
    skip "产物未内嵌 ffmpeg 许可串（strip/enable-small 已去除），需传 FFCONF_LOG=<ffconf.log> 才能验证"
  fi
}

# 协议检查（产物字符串文件）：$1=字符串文件  其余=协议名；
# 协议名以独立 C 字符串存放，整行匹配。注意：只是字符串存在性代理，不等于协议已注册
check_protocols_strs() {
  local strs="$1" p miss=""; shift
  for p in "$@"; do grep -axq -- "$p" "$strs" || miss="$miss $p"; done
  if [ -z "$miss" ]; then ok "协议名字符串齐全: $*"; else bad "协议名字符串缺失:$miss"; fi
}
