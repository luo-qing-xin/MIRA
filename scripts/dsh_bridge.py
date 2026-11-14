"""Install or remove MIRA's bridge in a local DSH desktop profile."""

import argparse
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile
import time

PATCH_NAME = "cordis.patch.yml"
BRIDGE_ROW = re.compile(
    r"""^[ \t]*(?:-[ \t]+)?id:[ \t]+(?:mira-bridge|"mira-bridge"|'mira-bridge')(?:[ \t]+#[^\r\n]*)?[ \t]*\r?$""",
    re.MULTILINE,
)
DISABLED_ROW = re.compile(r"^[ \t]*\[\](?:[ \t]+(#[^\r\n]*(?:\r?\n|$))|[ \t]*(?:\r?\n|$))", re.MULTILINE)
ROWS = "- insert:\n    - id: mira-bridge\n      name: './plugins/mira-bridge/index.js'\n"
SCRIPT_BLOCK = "# MIRA bridge (added by scripts/install-dsh-bridge.sh)\n" + ROWS
APP_BLOCK = "# MIRA bridge (added by MIRA)\n" + ROWS


def read_patch(path):
    try:
        return path.read_bytes().decode("utf-8")
    except FileNotFoundError:
        return None
    except (OSError, UnicodeError) as exc:
        raise ValueError(f"无法读取补丁文件 {path}：{exc}") from exc


def backup_patch(path, original):
    stem = path.name + ".mira-backup-" + str(int(time.time()))
    mode = stat.S_IMODE(path.stat().st_mode)
    for suffix in range(1, 1000):
        target = path.with_name(stem if suffix == 1 else f"{stem}-{suffix}")
        try:
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        except FileExistsError:
            continue
        with os.fdopen(fd, "wb") as backup:
            backup.write(original.encode("utf-8"))
        return
    raise ValueError(f"无法创建补丁备份：{path}")


def replace_patch(path, updated, original):
    if read_patch(path) != original:
        raise ValueError(f"补丁文件已被其他进程修改：{path}")
    path = path.resolve()
    mode = stat.S_IMODE(path.stat().st_mode) if original is not None else 0o644
    with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".mira-patch-", delete=False) as handle:
        temporary = Path(handle.name)
    try:
        temporary.write_bytes(updated.encode("utf-8"))
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def install(profile, sources):
    if not (profile / "package.json").is_file():
        raise ValueError(f"找不到 DSH 桌面 profile：{profile}。请先启动一次 DeepSeek Harness。")
    patch = profile / PATCH_NAME
    original = read_patch(patch)
    text = original or ""
    updated = None
    if not BRIDGE_ROW.search(text):
        newline = "\r\n" if "\r\n" in text else "\n"
        rows = [row for row in map(str.strip, text.splitlines()) if row and row != "---" and not row.startswith("#")]
        if rows and all(DISABLED_ROW.fullmatch(row) for row in rows):
            text = DISABLED_ROW.sub(r"\1", text)
        if text and not text.endswith("\n"):
            text += newline
        updated = text + SCRIPT_BLOCK.replace("\n", newline)

    plugins = profile / "plugins"
    plugins.mkdir(exist_ok=True)
    destination = plugins / "mira-bridge"
    staging = Path(tempfile.mkdtemp(prefix=".mira-install-", dir=plugins))
    replacement, previous = staging / "replacement", staging / "previous"
    clean_staging = True
    try:
        if destination.is_symlink() or (destination.exists() and not destination.is_dir()):
            raise ValueError(f"MIRA 插件路径不是文件夹：{destination}")
        had_plugin = destination.is_dir()
        if had_plugin:
            shutil.copytree(destination, replacement, symlinks=True)
        else:
            replacement.mkdir()
        replacement.chmod(0o700)
        for source in sources:
            target = replacement / source.name
            # Replace a staged symlink itself, without writing through it.
            if target.is_symlink():
                target.unlink()
            if target.exists() and not target.is_file():
                raise ValueError(f"插件文件路径不可替换：{target.name}")
            shutil.copyfile(source, target)
            target.chmod(0o600)
        if updated is not None and original:
            backup_patch(patch, original)
        if had_plugin:
            os.replace(destination, previous)
        published = False
        try:
            os.replace(replacement, destination)
            published = True
            if updated is not None:
                replace_patch(patch, updated, original)
        except (OSError, ValueError):
            try:
                if published:
                    os.replace(destination, replacement)
                if had_plugin:
                    os.replace(previous, destination)
            except OSError as exc:
                clean_staging = False
                raise ValueError(f"安装失败且无法恢复插件，备份保留在 {staging}：{exc}") from exc
            raise
    finally:
        if clean_staging:
            shutil.rmtree(staging, ignore_errors=True)


def uninstall(profile):
    patch = profile / PATCH_NAME
    original = read_patch(patch)
    if original and BRIDGE_ROW.search(original):
        blocks = (SCRIPT_BLOCK, APP_BLOCK)
        variants = blocks + tuple(block.replace("\n", "\r\n") for block in blocks)
        block = next((candidate for candidate in variants if candidate in original), None)
        if block is None:
            raise ValueError(f"补丁里的 MIRA 行不是已知格式，未修改：{patch}")
        updated = original.replace(block, "")
        if BRIDGE_ROW.search(updated):
            raise ValueError(f"移除后仍残留 mira-bridge 行，未修改：{patch}")
        backup_patch(patch, original)
        replace_patch(patch, updated, original)
    destination = profile / "plugins/mira-bridge"
    if destination.is_symlink():
        destination.unlink()
    elif destination.exists():
        shutil.rmtree(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("profile", type=Path)
    parser.add_argument("sources", nargs="*", type=Path)
    args = parser.parse_args()
    try:
        if args.action == "install":
            install(args.profile, args.sources)
        else:
            uninstall(args.profile)
    except (OSError, ValueError) as exc:
        parser.exit(1, str(exc) + "\n")


if __name__ == "__main__":
    main()
