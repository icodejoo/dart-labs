#!/usr/bin/env bash
# 回归：WHEP 信令 answer 用 Transfer-Encoding: chunked 回包时不得报 EIO（补丁 0011），http 与 https 都测。
# 用法：whep_chunked_regress.sh <带 whep 的 ffprobe 路径> [更多 ffprobe（如不同 TLS 后端的构建）...]
# 判定：/bigcl（Content-Length）与 /big（chunked）都必须读到 answer（日志含 "Got answer"），
#       且不含 "Reading WHEP answer failed"。之后 ICE 阶段超时是预期的（mock 没有媒体面）。
# https 场景：用 openssl 临时生成自签证书，mock 以 --tls-cert/--tls-key 监听，客户端 -tls_verify 0。
set -u
[ $# -ge 1 ] || { echo "用法: whep_chunked_regress.sh <ffprobe> [ffprobe...]" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORT="${PORT:-18091}"; TPORT="${TPORT:-18092}"
TMP="$(mktemp -d)"
PIDS=""
trap 'kill $PIDS 2>/dev/null; rm -rf "$TMP"' EXIT
python3 "$HERE/mock_whep_signal.py" --port "$PORT" >/dev/null 2>&1 & PIDS="$!"
HTTPS=0
if command -v openssl >/dev/null && openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=127.0.0.1 \
     -keyout "$TMP/k.pem" -out "$TMP/c.pem" >/dev/null 2>&1; then
  python3 "$HERE/mock_whep_signal.py" --port "$TPORT" --tls-cert "$TMP/c.pem" --tls-key "$TMP/k.pem" >/dev/null 2>&1 &
  PIDS="$PIDS $!"; HTTPS=1
else
  echo "SKIP https: 没有 openssl"
fi
sleep 1
rc=0
# 参数：标签 ffprobe scheme 端口 场景
run_case() {
  local out
  out=$(timeout 25 "$2" -v verbose -handshake_timeout 1000000 -tls_verify 0 -f whep -i "whep+$3://127.0.0.1:$4/$5" 2>&1)
  if echo "$out" | grep -q "Got answer" && ! echo "$out" | grep -q "Reading WHEP answer failed"; then
    echo "PASS $1 $3 $5: $(echo "$out" | grep -m1 'Got answer')"
  else
    echo "FAIL $1 $3 $5: $(echo "$out" | grep -m1 -E 'Reading WHEP|failed|rror')"; rc=1
  fi
}
for ff in "$@"; do
  for m in bigcl big; do
    run_case "$(basename "$(dirname "$ff")")" "$ff" http "$PORT" "$m"
    [ "$HTTPS" = 1 ] && run_case "$(basename "$(dirname "$ff")")" "$ff" https "$TPORT" "$m"
  done
done
# 补丁 0012 负例：answer 为 setup:passive 必须立刻报清晰错误（而不是 ICE 超时后 no DTLS from peer）
for ff in "$@"; do
  out=$(timeout 25 "$ff" -v verbose -handshake_timeout 1000000 -f whep -i "whep+http://127.0.0.1:$PORT/passive" 2>&1)
  if echo "$out" | grep -q "is invalid for our setup:passive offer"; then
    echo "PASS $(basename "$(dirname "$ff")") http passive-answer rejected"
  else
    echo "FAIL $(basename "$(dirname "$ff")") passive-answer: $(echo "$out" | grep -m1 -E 'rror|failed')"; rc=1
  fi
done
exit $rc
