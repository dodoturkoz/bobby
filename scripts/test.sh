#!/bin/bash
set -euo pipefail
BOBBY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BOBBY_ROOT"
export CLANG_MODULE_CACHE_PATH="$BOBBY_ROOT/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$BOBBY_ROOT/.build/module-cache"
swift test --disable-sandbox --cache-path "$BOBBY_ROOT/.build/swiftpm-cache" --config-path "$BOBBY_ROOT/.build/swiftpm-config" --security-path "$BOBBY_ROOT/.build/swiftpm-security" --manifest-cache local "$@"
