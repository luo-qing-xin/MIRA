#!/bin/bash
# Mount the MIRA bridge into the DSH desktop profile.
# The bridge observes events; while MIRA is alive it may also answer an
# approval from the MIRA panel (one-shot token), otherwise DSH handles it.
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
# The app treats a missing patch as an empty layer; so does this script.
# An existing but unreadable file must stop the install before anything changes.
if [ -e "$PATCH" ] && [ ! -r "$PATCH" ]; then
  echo "无法读取 profile 补丁文件：$PATCH" >&2
  echo "为保护现有配置，本次未做修改。" >&2
  exit 1
fi

mkdir -p "$DEST"
cp "$SRC/index.js" "$SRC/entry.js" "$DEST/"
chmod 700 "$DEST"
chmod 600 "$DEST"/*.js

ROW_RE='id:[[:space:]]*["'"'"']?mira-bridge["'"'"']?([[:space:]#]|$)'
if [ -f "$PATCH" ] && grep -qE "$ROW_RE" "$PATCH"; then
  echo "已连接：profile 的补丁层里已经有 mira-bridge。"
  exit 0
fi

if [ ! -f "$PATCH" ]; then
  : > "$PATCH"
else
  BACKUP="$PATCH.mira-backup-$(date +%s)"
  suffix=2
  while [ -e "$BACKUP" ]; do
    BACKUP="$PATCH.mira-backup-$(date +%s)-$suffix"
    suffix=$((suffix + 1))
  done
  cp "$PATCH" "$BACKUP"

  # `[]` is the documented disabled layer; appending a list item after it is invalid YAML.
  if ! grep -vE '^[[:space:]]*(#|$|---[[:space:]]*$)' "$PATCH" | grep -qvE '^[[:space:]]*\[\][[:space:]]*$'; then
    : > "$PATCH"
  fi
fi
cat >> "$PATCH" <<'EOF'

# MIRA bridge (added by scripts/install-dsh-bridge.sh)
- insert:
    - id: mira-bridge
      name: './plugins/mira-bridge/index.js'
EOF
echo "已写入 $PATCH"
echo "如果 DeepSeek Harness 正在运行，热重载会自动挂载；否则退出并重新打开一次。"
echo "验收：在 DSH 里跑完一轮，MIRA 应出现「本轮结束」；点击会切到 DSH 窗口。"
