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

# Without reading the patch we cannot prove the plugin is unreferenced.
if [ -e "$PATCH" ] && [ ! -r "$PATCH" ]; then
  echo "无法读取 profile 补丁文件：$PATCH" >&2
  echo "为避免删除仍被引用的插件，本次未做修改。" >&2
  exit 1
fi

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
import os
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1]).resolve()
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
# Any equivalent leftover row means the patch still references the plugin
# directory that is deleted below, so stop instead of breaking DSH.
leftover = re.compile(
    r"""^[ \t]*(?:-[ \t]+)?id:[ \t]*["']?mira-bridge["']?[ \t]*(?:#.*)?$""",
    re.MULTILINE,
)
if leftover.search(cleaned):
    sys.exit("移除后仍残留 mira-bridge 行，未修改：" + str(path))
# Replace atomically and keep the original permissions: a half-written patch
# would keep DSH from starting.
temporary = path.with_name("." + path.name + ".mira-remove")
temporary.write_text(cleaned)
os.chmod(temporary, path.stat().st_mode)
temporary.replace(path)
PY
  echo "已从补丁层移除 mira-bridge。"
else
  echo "补丁层里没有 mira-bridge，跳过。"
fi

rm -rf "$DEST"
echo "已删除 ${DEST}。重启 DeepSeek Harness 后完全生效。"
