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
run_smoke() { arch -"$ARCH" ./smoke "$@"; }   # arch -x86_64 在 Apple Silicon 上走 Rosetta

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
kill -0 "${PIDS[-1]}" 2>/dev/null || { echo "::error::推流进程退出"; cat pub.log; exit 1; }

# ---- 4. WHEP 正常拉流 ----
echo "=== WHEP 正常拉流 15s ==="
run_smoke play whep+http://127.0.0.1:8889/test/whep 15 > whep-ok.log 2>&1; RC=$?
grep -E 'RESULT|EVENT|PROP|DTLS|ICE|fingerprint' whep-ok.log | head -40
[ $RC -eq 0 ] && pass "WHEP 起播且 time-pos 推进" || { flunk "WHEP 正常拉流 (rc=$RC)"; tail -40 whep-ok.log; }
grep -q 'PROP width = 640' whep-ok.log && grep -q 'PROP height = 360' whep-ok.log && pass "视频 640x360" || flunk "没有拿到 640x360 视频参数"
grep -q 'PROP video-codec = .*H.264\|PROP video-codec = .*h264' whep-ok.log && pass "视频编码 H.264" || flunk "视频编码不是 H.264"
grep -q 'PROP audio-codec-name = opus' whep-ok.log && pass "音频编码 opus" || flunk "音频编码不是 opus"
FR=$(grep -E '^t=' whep-ok.log | tail -1 | sed -E 's/.*frames=([0-9-]+).*/\1/')
[ "${FR:-0}" -gt 100 ] 2>/dev/null && pass "出帧数 $FR (>100)" || flunk "出帧数过少: ${FR:-?}"

# ---- 4b. iOS 模拟器：init + WHEP 拉流（模拟器与宿主共用网络，直接连宿主上的 MediaMTX） ----
# 需要 SIM_FRAMEWORK_DIR=<模拟器切片里 Mpv.framework 的上一级目录>；SIM_OPTIONAL=1 时失败只告警（模拟器环境偶发起不来）
if [ -n "${SIM_FRAMEWORK_DIR:-}" ]; then
  echo "=== iOS 模拟器冒烟 ==="
  sim_fail() { if [ "${SIM_OPTIONAL:-0}" = 1 ]; then echo "::warning::模拟器: $*"; else flunk "模拟器: $*"; fi; }
  RUNTIME=$(xcrun simctl list runtimes available -j | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['runtimes'] if x['platform']=='iOS' and x.get('isAvailable',True)]; print(r[-1]['identifier'] if r else '')")
  DEVTYPE=$(xcrun simctl list devicetypes -j | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['devicetypes'] if 'iPhone' in x['name']]; print(r[-1]['identifier'] if r else '')")
  echo "runtime=$RUNTIME devtype=$DEVTYPE"
  if [ -z "$RUNTIME" ] || [ -z "$DEVTYPE" ]; then sim_fail "没有可用的 iOS 运行时/设备类型"; else
    UDID=$(xcrun simctl create mova-smoke "$DEVTYPE" "$RUNTIME")
    if xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1; then
      xcrun --sdk iphonesimulator clang -arch arm64 -target arm64-apple-ios13.0-simulator -I inc "$HERE/apple-smoke.c"         -F "$SIM_FRAMEWORK_DIR" -framework Mpv -Wl,-rpath,"$SIM_FRAMEWORK_DIR" -o smoke-sim && codesign -f -s - smoke-sim
      if [ $? -ne 0 ]; then sim_fail "编译模拟器冒烟程序失败"; else
        xcrun simctl spawn "$UDID" "$PWD/smoke-sim" init > sim-init.log 2>&1 && pass "模拟器 init 循环" || { sim_fail "init 循环"; tail -20 sim-init.log; }
        grep -E 'PROP' sim-init.log
        xcrun simctl spawn "$UDID" "$PWD/smoke-sim" play whep+http://127.0.0.1:8889/test/whep 15 > sim-whep.log 2>&1           && pass "模拟器 WHEP 起播且 time-pos 推进" || { sim_fail "WHEP 拉流"; tail -30 sim-whep.log; }
        grep -E 'RESULT|EVENT|PROP' sim-whep.log | head -20
      fi
    else sim_fail "模拟器起不来"; fi
    xcrun simctl shutdown "$UDID" 2>/dev/null; xcrun simctl delete "$UDID" 2>/dev/null
  fi
fi

# ---- 5. 失败路径：指纹被篡改必须被拒绝；候选不可达必须在握手超时内干净返回 ----
python3 "$WHEP_TOOLS/whep_tamper_proxy.py" 18100 > proxy.log 2>&1 & PIDS+=($!)
sleep 1
echo "=== 指纹被篡改（fp 模式）==="
run_smoke play whep+http://127.0.0.1:18100/fp/test/whep 10 > whep-fp.log 2>&1; RC=$?
grep -E 'RESULT|EVENT end-file|fingerprint|EACCES|Permission' whep-fp.log | head
[ $RC -ne 0 ] && grep -q 'advanced=-1\|advanced=0' whep-fp.log && pass "指纹被篡改 -> 拒绝，没有出画面" || flunk "指纹被篡改仍然起播了 (rc=$RC)"
echo "=== 候选不可达（dead 模式，握手超时 10s）==="
T0=$(date +%s); run_smoke play whep+http://127.0.0.1:18100/dead/test/whep 20 > whep-dead.log 2>&1; RC=$?; T1=$(date +%s)
grep -E 'RESULT|EVENT end-file' whep-dead.log | head -5
[ $RC -ne 0 ] && [ $((T1-T0)) -lt 19 ] && pass "候选不可达 -> $((T1-T0))s 内干净返回" || flunk "候选不可达场景异常 (rc=$RC, ${T1}-${T0}s)"

# ---- 6. https（mbedtls）：tls-verify=no 能播；=yes 配 ca 文件能播；换无关 CA 必须失败 ----
if [ "${SKIP_HTTPS:-0}" != 1 ]; then
  echo "=== https / mbedtls ==="
  ffmpeg -nostdin -loglevel error -f lavfi -i testsrc2=size=320x180:rate=25 -t 20 -c:v libx264 -pix_fmt yuv420p -g 25 -movflags +faststart media.mp4
  for n in good evil; do
    openssl req -x509 -newkey rsa:2048 -nodes -keyout $n.key -out $n.pem -days 2 -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1" >/dev/null 2>&1
  done
  cat > httpsd.py <<'PY'
import http.server, ssl, sys
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); ctx.load_cert_chain('good.pem', 'good.key')
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8443), http.server.SimpleHTTPRequestHandler)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True); srv.serve_forever()
PY
  python3 httpsd.py > httpsd.log 2>&1 & PIDS+=($!)
  sleep 2
  SMOKE_OPTS="tls-verify=no" run_smoke play https://127.0.0.1:8443/media.mp4 6 > https-noverify.log 2>&1 \
    && pass "https tls-verify=no 能播" || { flunk "https tls-verify=no"; tail -20 https-noverify.log; }
  SMOKE_OPTS="tls-verify=yes;tls-ca-file=$W/good.pem" run_smoke play https://127.0.0.1:8443/media.mp4 6 > https-ca.log 2>&1 \
    && pass "https tls-verify=yes + tls-ca-file 能播" || { flunk "https tls-verify=yes + ca"; tail -20 https-ca.log; }
  SMOKE_OPTS="tls-verify=yes;tls-ca-file=$W/evil.pem" run_smoke play https://127.0.0.1:8443/media.mp4 6 > https-badca.log 2>&1 \
    && flunk "换无关 CA 仍然起播（校验没生效）" || pass "https 换无关 CA -> 拒绝"
fi

echo; echo "================ 汇总 ================"
if [ ${#FAILS[@]} -eq 0 ]; then echo "全部通过"; exit 0; fi
printf 'FAIL: %s\n' "${FAILS[@]}"; exit 1
