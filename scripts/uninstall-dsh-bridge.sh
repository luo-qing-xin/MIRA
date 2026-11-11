#!/bin/bash
# Remove the MIRA bridge from the DSH desktop profile. Keeps everything else.
set -euo pipefail

DSH_HOME_DIR="${DSH_HOME:-$HOME/.dsh}"
PROFILE="$DSH_HOME_DIR/profiles/desktop"
PATCH="$PROFILE/cordis.patch.yml"
DEST="$PROFILE/plugins/mira-bridge"

case "$DEST" in
  "$PROFILE"/plugins/mira-bridge) ;;
  *) echo "拒绝删除异常路径：$DEST" >&2; exit 1 ;;
esac

ROW_RE='id:[[:space:]]*["'"'"']?mira-bridge["'"'"']?([[:space:]#]|$)'
if [ -f "$PATCH" ] && grep -qE "$ROW_RE" "$PATCH"; then
  BACKUP="$PATCH.mira-backup-$(date +%s)"
  suffix=2
  while [ -e "$BACKUP" ]; do
    BACKUP="$PATCH.mira-backup-$(date +%s)-$suffix"
    suffix=$((suffix + 1))
  done
  cp "$PATCH" "$BACKUP"
  python3 - "$PATCH" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
rows = (
    "- insert:\n"
    "    - id: mira-bridge\n"
    "      name: './plugins/mira-bridge/index.js'\n"
)
# Both installers write the same rows; accept either comment so the app and
# this script can undo each other's install.
blocks = [
    "# MIRA bridge (added by MIRA)\n" + rows,
    "# MIRA bridge (added by scripts/install-dsh-bridge.sh)\n" + rows,
]
block = next((candidate for candidate in blocks if candidate in text), None)
if block is None:
    sys.exit("补丁里的 MIRA 行不是已知格式，未修改：" + str(path))
cleaned = text.replace(block, "")
for line in cleaned.splitlines():
    if line.strip() in ("- id: mira-bridge", "id: mira-bridge"):
        sys.exit("移除后仍残留 mira-bridge 行，未修改：" + str(path))
path.write_text(cleaned)
PY
  echo "已从补丁层移除 mira-bridge。"
else
  echo "补丁层里没有 mira-bridge，跳过。"
fi

rm -rf "$DEST"
echo "已删除 ${DEST}。重启 DeepSeek Harness 后完全生效。"
