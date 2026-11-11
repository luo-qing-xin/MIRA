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

if [ -f "$PATCH" ] && grep -q "id: mira-bridge" "$PATCH"; then
  cp "$PATCH" "$PATCH.mira-backup-$(date +%s)"
  python3 - "$PATCH" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
block = (
    "\n# MIRA bridge (added by scripts/install-dsh-bridge.sh)\n"
    "- insert:\n"
    "    - id: mira-bridge\n"
    "      name: './plugins/mira-bridge/index.js'\n"
)
if block not in text:
    sys.exit("补丁里的 MIRA 行不是本脚本写入的格式，未修改：" + str(path))
path.write_text(text.replace(block, ""))
PY
  echo "已从补丁层移除 mira-bridge。"
else
  echo "补丁层里没有 mira-bridge，跳过。"
fi

rm -rf "$DEST"
echo "已删除 $DEST。重启 DeepSeek Harness 后完全生效。"
