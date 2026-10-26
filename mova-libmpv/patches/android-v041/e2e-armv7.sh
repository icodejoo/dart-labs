#!/bin/bash -e
# 从零端到端构建 Android armeabi-v7a libmpv：e2e-arm64.sh 的 ARCH=armv7l 薄包装，参数相同。
# 用法：WHEP=1 e2e-armv7.sh <新建的空工作目录> [NDK r25c 目录]
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH=armv7l exec "$HERE/e2e-arm64.sh" "$@"
