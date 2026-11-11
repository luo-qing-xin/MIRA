#!/bin/bash
# Mount the MIRA bridge into the DSH desktop profile.
# The bridge only observes: it never approves, denies, or answers anything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/integrations/dsh"
DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE="$DSH_HOME_DIR/profiles/desktop"
PATCH="$PROFILE/cordis.patch.yml"
DEST="$PROFILE/plugins/mira-bridge"

if [ ! -f "$PROFILE/package.json" ]; then
  echo "找不到 DSH 桌面 profile：$PROFILE" >&2
  echo "请先启动一次 DeepSeek Harness，再运行本脚本。" >&2
  exit 1
fi
if [ ! -f "$PATCH" ]; then
  echo "找不到 profile 补丁文件：$PATCH" >&2
  exit 1
fi

mkdir -p "$DEST"
cp "$SRC/index.js" "$SRC/entry.js" "$DEST/"
chmod 700 "$DEST"
chmod 600 "$DEST"/*.js

if grep -q "id: mira-bridge" "$PATCH"; then
  echo "已连接：profile 的补丁层里已经有 mira-bridge。"
  exit 0
fi

cp "$PATCH" "$PATCH.mira-backup-$(date +%s)"
cat >> "$PATCH" <<'EOF'

# MIRA bridge (added by scripts/install-dsh-bridge.sh)
- insert:
    - id: mira-bridge
      name: './plugins/mira-bridge/index.js'
EOF
echo "已写入 $PATCH"
echo "如果 DeepSeek Harness 正在运行，热重载会自动挂载；否则退出并重新打开一次。"
echo "验收：在 DSH 里跑完一轮，MIRA 应出现「本轮结束」；点击会切到 DSH 窗口。"
