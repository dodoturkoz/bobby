#!/bin/bash
set -euo pipefail
BOBBY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$BOBBY_ROOT/scripts/build-app.sh" "${1:-debug}"
open "$BOBBY_ROOT/build/Bobby.app"
