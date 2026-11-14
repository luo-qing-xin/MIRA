#!/bin/bash
# Remove the MIRA bridge from the DSH desktop profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/desktop"
python3 "$ROOT/scripts/dsh_bridge.py" uninstall "$PROFILE"
echo "已移除 DSH 连接。重启 DeepSeek Harness 后完全生效。"
