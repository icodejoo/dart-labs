#!/bin/bash
# macOS 上的 libmpv 端到端冒烟：init 循环、WHEP 拉流（MediaMTX + ffmpeg 推流）、指纹被篡改/候选不可达的失败路径、
# https（mbedtls）三种校验场景。用于 macOS 切片（arm64 本机，x86_64 经 Rosetta）。
# 用法：whep-e2e.sh <libmpv 二进制> <arch: arm64|x86_64> [rpath 目录]
#   rpath 目录：二进制 install name 为 @rpath/... 时的查找目录，缺省取二进制所在目录
#               （framework 里的 Mpv 需传 Mpv.framework 的上一级目录）
# 环境变量：SIM_FRAMEWORK_DIR / SIM_OPTIONAL（iOS 模拟器冒烟，见 4b）；SKIP_HTTPS=1 跳过 https 场景；MEDIAMTX_VERSION 缺省 1.21.1（与 Linux 开发验证同版本）
# 退出码：0 全部通过；非 0 有失败（汇总在最后）。
set -uo pipefail
BIN="$(cd "$(dirname "${1:?binary}")" && pwd)/$(basename "$1")"; ARCH="${2:?arch}"
RPATH_DIR="${3:-$(dirname "$BIN")}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WHEP_TOOLS="$HERE/../whep-flavor"
W="${WORK:-$(mktemp -d)}"; mkdir -p "$W"; cd "$W"
MTX_VER="${MEDIAMTX_VERSION:-1.21.1}"
FAILS=()
pass() { echo "PASS  $*"; }
flunk() { echo "::error::FAIL  $*"; FAILS+=("$*"); }
PIDS=()
cleanup() { for p in "${PIDS[@]:-}"; do [ -n "$p" ] && kill "$p" 2>/dev/null; done; wait 2>/dev/null; }
trap cleanup EXIT

# ---- 1. 编译冒烟程序，链接到被测二进制 ----
mkdir -p inc/mpv && cp "$HERE"/Headers/*.h inc/mpv/
clang -arch "$ARCH" -mmacosx-version-min=10.15 -I inc "$HERE/apple-smoke.c" "$BIN" -Wl,-rpath,"$RPATH_DIR" -o smoke || { echo "::error::编译冒烟程序失败"; exit 1; }
# 带超时的冒烟运行：超时（默认 120s）就用 sample 抓一份线程栈再杀掉，避免 CI 无声挂死
run_smoke() {
  local limit="${SMOKE_TIMEOUT:-120}"
  arch -"$ARCH" ./smoke "$@" &
  local pid=$!
  ( sleep "$limit"; echo "::error::冒烟超过 ${limit}s 仍未退出，抓栈后强杀: ./smoke $*"; sample "$pid" 3 -file "$W/hang-$pid.txt" >/dev/null 2>&1; head -120 "$W/hang-$pid.txt" 2>/dev/null; kill -9 "$pid" 2>/dev/null ) &
  local guard=$!
  wait "$pid"; local rc=$?
  kill "$guard" 2>/dev/null; wait "$guard" 2>/dev/null
  return $rc
}   # arch -x86_64 在 Apple Silicon 上走 Rosetta

# ---- 2. init 循环 + 版本取证 ----
if run_smoke init > init.log 2>&1; then pass "init 循环 5 次"; else flunk "init 循环"; fi
cat init.log
grep -q 'PROP ffmpeg-version = .*9\.0\.2' init.log && pass "运行时 ffmpeg-version = n9.0.2" || flunk "运行时 ffmpeg-version 不是 n9.0.2"
grep -Eq 'PROP mpv-version = .*0\.41\.0' init.log && pass "运行时 mpv-version = 0.41.0" || flunk "运行时 mpv-version 不是 0.41.0"

# ---- 3. MediaMTX + ffmpeg 推流 ----
MTX_ARCH=$(uname -m); [ "$MTX_ARCH" = arm64 ] || MTX_ARCH=amd64
curl -fsSL "https://github.com/bluenviron/mediamtx/releases/download/v${MTX_VER}/mediamtx_v${MTX_VER}_darwin_${MTX_ARCH}.tar.gz" | tar xz mediamtx || { echo "::error::下载 MediaMTX 失败"; exit 1; }
cat > mtx.yml <<'YML'
logLevel: info
rtsp: yes
webrtc: yes
webrtcAddress: :8889
webrtcLocalUDPAddress: :8189
webrtcAdditionalHosts: [127.0.0.1]
rtmp: no
hls: no
srt: no
api: no
paths:
  all_others:
YML
./mediamtx mtx.yml > mtx.log 2>&1 & PIDS+=($!)
for i in $(seq 1 30); do nc -z 127.0.0.1 8889 2>/dev/null && break; sleep 0.5; done
nc -z 127.0.0.1 8889 || { echo "::error::MediaMTX 没起来"; cat mtx.log; exit 1; }

command -v ffmpeg >/dev/null || { echo "brew install ffmpeg ..."; HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1 brew install ffmpeg >/dev/null 2>&1; }
command -v ffmpeg >/dev/null || { echo "::error::没有 ffmpeg，无法推流"; exit 1; }
ffmpeg -nostdin -loglevel warning -re \
  -f lavfi -i testsrc2=size=640x360:rate=25 -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -c:v libx264 -profile:v baseline -pix_fmt yuv420p -g 50 -preset ultrafast -tune zerolatency \
  -c:a libopus -b:a 64k -ac 2 -f rtsp -rtsp_transport tcp rtsp://127.0.0.1:8554/test > pub.log 2>&1 & PIDS+=($!)
sleep 4
kill -0 "${PIDS[${#PIDS[@]}-1]}" 2>/dev/null || { echo "::error::推流进程退出"; cat pub.log; exit 1; }

# ---- 4. WHEP 正常拉流 ----
echo "=== WHEP 正常拉流 15s ==="
run_smoke play whep+http://127.0.0.1:8889/test/whep 15 > whep-ok.log 2>&1; RC=$?
grep -E 'RESULT|EVENT|PROP|DTLS|ICE|fingerprint' whep-ok.log | head -40
[ $RC -eq 0 ] && pass "WHEP 起播且 time-pos 推进" || { flunk "WHEP 正常拉流 (rc=$RC)"; tail -40 whep-ok.log; }
grep -q 'PROP width = 640' whep-ok.log && grep -q 'PROP height = 360' whep-ok.log && pass "视频 640x360" || flunk "没有拿到 640x360 视频参数"
grep -q 'PROP video-format = h264' whep-ok.log && pass "视频编码 H.264" || flunk "视频编码不是 H.264"
grep -q 'PROP audio-codec-name = opus' whep-ok.log && pass "音频编码 opus" || flunk "音频编码不是 opus"
FR=$(grep -E '^t=' whep-ok.log | tail -1 | sed -E 's/.*frames=([0-9-]+).*/\1/')
[ "${FR:-0}" -gt 100 ] 2>/dev/null && pass "出帧数 $FR (>100)" || flunk "出帧数过少: ${FR:-?}"

# ---- 4b. iOS 模拟器：init + WHEP 拉流（模拟器与宿主共用网络，直接连宿主上的 MediaMTX） ----
# 需要 SIM_FRAMEWORK_DIR=<模拟器切片里 Mpv.framework 的上一级目录>；SIM_OPTIONAL=1 时失败只告警（模拟器环境偶发起不来）
if [ -n "${SIM_FRAMEWORK_DIR:-}" ]; then
  echo "=== iOS 模拟器冒烟 ==="
  sim_fail() { if [ "${SIM_OPTIONAL:-0}" = 1 ]; then echo "::warning::模拟器: $*"; else flunk "模拟器: $*"; fi; }
  # 用 runner 上已有的设备（自己 create 容易撞 "Incompatible device"：设备类型和运行时版本不配）
  UDID=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
d = json.load(sys.stdin)['devices']
rts = sorted(k for k in d if 'iOS' in k)
pick = ''
for rt in reversed(rts):
    cands = [x for x in d[rt] if x['name'].startswith('iPhone') and x.get('isAvailable', True)]
    pro = [x for x in cands if 'Pro' in x['name'] and 'Max' not in x['name']]
    if cands:
        pick = (pro or cands)[0]['udid']; break
print(pick)")
  echo "simulator udid=$UDID"
  if [ -z "$UDID" ]; then sim_fail "没有可用的 iPhone 模拟器设备"; else
    if xcrun simctl boot "$UDID" 2>&1 | tail -2; xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1; then
      xcrun --sdk iphonesimulator clang -arch arm64 -target arm64-apple-ios14.0-simulator -I inc "$HERE/apple-smoke.c" -F "$SIM_FRAMEWORK_DIR" -framework Mpv -Wl,-rpath,"$SIM_FRAMEWORK_DIR" -o smoke-sim && codesign -f -s - smoke-sim
      if [ $? -ne 0 ]; then sim_fail "编译模拟器冒烟程序失败"; else
        xcrun simctl spawn "$UDID" "$PWD/smoke-sim" init > sim-init.log 2>&1 && pass "模拟器 init 循环" || { sim_fail "init 循环"; tail -20 sim-init.log; }
        grep -E 'PROP' sim-init.log
        xcrun simctl spawn "$UDID" "$PWD/smoke-sim" play whep+http://127.0.0.1:8889/test/whep 15 > sim-whep.log 2>&1           && pass "模拟器 WHEP 起播且 time-pos 推进" || { sim_fail "WHEP 拉流"; tail -30 sim-whep.log; }
        grep -E 'RESULT|EVENT|PROP' sim-whep.log | head -20
      fi
    else sim_fail "模拟器起不来"; fi
    xcrun simctl shutdown "$UDID" 2>/dev/null
  fi
fi

# ---- 5. 失败路径：指纹被篡改必须因指纹校验被拒绝；候选不可达必须在握手超时内干净返回 ----
PROXY_DEBUG=1 python3 "$WHEP_TOOLS/whep_tamper_proxy.py" 18100 > proxy.log 2>&1 & PIDS+=($!)
# 等端口真正可连：Python 的 HTTPServer 在 server_bind 里做 getfqdn 反查，runner 上可能卡几十秒
wait_port() { for i in $(seq 1 90); do nc -z 127.0.0.1 "$1" 2>/dev/null && return 0; sleep 1; done; echo "::warning::端口 $1 等了 90s 仍不可连"; return 1; }
wait_port 18100
echo "--- proxy.log (启动后) ---"; cat proxy.log
echo "=== 对照：经代理原样转发（ok 模式）必须能播 ==="
SMOKE_LOG_ALL=1 run_smoke play whep+http://127.0.0.1:18100/ok/test/whep 10 > whep-proxy-ok.log 2>&1; RC=$?
grep -aE 'RESULT|EVENT|whep:|WHEP' whep-proxy-ok.log | head -12
if [ $RC -eq 0 ]; then pass "经代理（ok）起播"; else flunk "经代理（ok）起播失败 (rc=$RC)"; tail -40 whep-proxy-ok.log; echo "--- proxy.log ---"; cat proxy.log; fi

echo "=== 指纹被篡改（fp 模式）：必须因指纹校验被拒绝 ==="
SMOKE_LOG_ALL=1 run_smoke play whep+http://127.0.0.1:18100/fp/test/whep 12 > whep-fp.log 2>&1; RC=$?
grep -aEi 'RESULT|EVENT|ingerprint|EACCES|Permission denied' whep-fp.log | head -12
if [ $RC -ne 0 ] && grep -aqiE 'fingerprint|EACCES|Permission denied' whep-fp.log; then
  pass "指纹被篡改 -> 因指纹校验被拒绝"
else
  flunk "指纹被篡改没有被指纹校验拒绝 (rc=$RC)"; tail -40 whep-fp.log; echo "--- proxy.log ---"; cat proxy.log
fi

echo "=== 候选不可达（dead 模式，handshake_timeout=3s）==="
T0=$(date +%s)
SMOKE_LOG_ALL=1 SMOKE_OPTS="demuxer-lavf-o=handshake_timeout=3000000" run_smoke play whep+http://127.0.0.1:18100/dead/test/whep 20 > whep-dead.log 2>&1; RC=$?
T1=$(date +%s); DT=$((T1-T0))
grep -aEi 'RESULT|EVENT|whep:|timeout|Connection' whep-dead.log | head -12
if [ $RC -ne 0 ] && [ $DT -lt 18 ]; then
  pass "候选不可达 -> ${DT}s 内干净返回"
else
  flunk "候选不可达场景异常 (rc=$RC, ${DT}s)"; tail -40 whep-dead.log; echo "--- proxy.log ---"; cat proxy.log
fi

# ---- 6. https（mbedtls）：tls-verify=no 能播；=yes 配 ca 文件能播；换无关 CA 必须因证书校验失败 ----
if [ "${SKIP_HTTPS:-0}" != 1 ]; then
  echo "=== https / mbedtls ==="
  ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=size=320x180:rate=25 -t 20 -c:v libx264 -pix_fmt yuv420p -g 25 -movflags +faststart media.mp4
  # macOS 自带的 openssl 是 LibreSSL，不一定支持 -addext，用配置文件更稳
  cat > san.cnf <<'CNF'
[req]
distinguished_name=dn
x509_extensions=v3
prompt=no
[dn]
CN=127.0.0.1
[v3]
subjectAltName=IP:127.0.0.1
basicConstraints=CA:TRUE
CNF
  for n in good evil; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout $n.key -out $n.pem -days 2 -config san.cnf 2>&1 | tail -2
  done
  cat > httpsd.py <<'PY'
import http.server, ssl
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain('good.pem', 'good.key')

class S(http.server.ThreadingHTTPServer):
    # 握手放到每个连接自己的线程里做：在 accept 线程里握手，一个卡住的客户端会堵死后面所有连接
    def get_request(self):
        sock, addr = self.socket.accept()
        return ctx.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), addr

S(('127.0.0.1', 8443), http.server.SimpleHTTPRequestHandler).serve_forever()
PY
  python3 httpsd.py > httpsd.log 2>&1 & PIDS+=($!)
  wait_port 8443
  ls -l media.mp4 good.pem good.key
  echo "curl 直连自检: $(curl -sk -m 5 -o /dev/null -w '%{http_code} %{size_download}B' https://127.0.0.1:8443/media.mp4)"
  echo "--- httpsd.log ---"; cat httpsd.log

  SMOKE_LOG_ALL=1 SMOKE_OPTS="tls-verify=no" run_smoke play https://127.0.0.1:8443/media.mp4 8 > https-noverify.log 2>&1; RC=$?
  grep -aEi 'RESULT|EVENT|tls|ssl|certificate' https-noverify.log | head -12
  if [ $RC -eq 0 ]; then pass "https tls-verify=no 能播"; else flunk "https tls-verify=no (rc=$RC)"; tail -50 https-noverify.log; echo "--- httpsd.log ---"; cat httpsd.log; fi

  SMOKE_LOG_ALL=1 SMOKE_OPTS="tls-verify=yes;tls-ca-file=$W/good.pem" run_smoke play https://127.0.0.1:8443/media.mp4 8 > https-ca.log 2>&1; RC=$?
  grep -aEi 'RESULT|EVENT|tls|ssl|certificate' https-ca.log | head -12
  if [ $RC -eq 0 ]; then pass "https tls-verify=yes + tls-ca-file 能播"; else flunk "https tls-verify=yes + ca (rc=$RC)"; tail -50 https-ca.log; fi

  SMOKE_LOG_ALL=1 SMOKE_OPTS="tls-verify=yes;tls-ca-file=$W/evil.pem" run_smoke play https://127.0.0.1:8443/media.mp4 8 > https-badca.log 2>&1; RC=$?
  grep -aEi 'RESULT|EVENT|tls|ssl|certificate|verif' https-badca.log | head -12
  if [ $RC -eq 0 ]; then
    flunk "换无关 CA 仍然起播（校验没生效）"
  elif grep -aqiE 'certificate|verif|x509' https-badca.log; then
    pass "https 换无关 CA -> 因证书校验被拒绝"
  else
    flunk "换无关 CA 失败，但日志里没有证书校验相关信息"; tail -50 https-badca.log
  fi
fi

echo; echo "================ 汇总 ================"
if [ ${#FAILS[@]} -eq 0 ]; then echo "全部通过"; exit 0; fi
printf 'FAIL: %s\n' "${FAILS[@]}"; exit 1
