#!/bin/bash
# Mount the MIRA bridge into the DSH desktop profile.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="${DSH_HOME:-$HOME/.dsh}/profiles/desktop"
python3 "$ROOT/scripts/dsh_bridge.py" install "$PROFILE" \
  "$ROOT/integrations/dsh/index.js" "$ROOT/integrations/dsh/entry.js" "$ROOT/integrations/emit/emit.js"
echo "已配置 DSH 连接。重启 DeepSeek Harness 后生效。"
