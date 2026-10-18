#!/bin/sh
# 打包成 .love（ZIP 仅存储、不压缩），可在任意目录调用。
#
#   ./pack.sh                 # 输出 <目录名>.love 到项目根目录
#   ./pack.sh MyGame          # 输出 MyGame.love
#   sh /path/to/pack.sh       # 从别处调用也行（会先切到脚本所在目录）
#
# 纯 POSIX sh：Termux（/bin/sh = mksh）与桌面 Linux/macOS 都能直接执行。
# 不依赖 zip 命令：优先用 python3 的 zipfile，缺 python3 时才退回 zip。
# 不生成临时目录，产物直接写到项目根目录。

set -u

RED=$(printf '\033[0;31m')
GREEN=$(printf '\033[0;32m')
YELLOW=$(printf '\033[0;33m')
NC=$(printf '\033[0m')

die() {
    printf '%s错误: %s%s\n' "$RED" "$*" "$NC" >&2
    exit 1
}

# ---------- 1. 定位项目根目录（不依赖调用者的 cwd）----------
SCRIPT_PATH=$0
SCRIPT_DIR=$(cd "$(dirname "$SCRIPT_PATH")" 2>/dev/null && pwd) ||
    die "无法定位脚本所在目录，路径可能已不存在: $SCRIPT_PATH"

cd "$SCRIPT_DIR" || die "无法进入 $SCRIPT_DIR"

[ -f main.lua ] || die "$SCRIPT_DIR 下没有 main.lua，这里可能不是项目根目录"

# ---------- 2. 目标文件名 ----------
TARGET_NAME=${1:-$(basename "$PWD")}
case "$TARGET_NAME" in
    *.love) ;;
    *) TARGET_NAME="$TARGET_NAME.love" ;;
esac
TARGET="$SCRIPT_DIR/$TARGET_NAME"

printf '%s开始打包 %s ...%s\n' "$GREEN" "$TARGET_NAME" "$NC"
printf '%s源目录: %s%s\n' "$YELLOW" "$SCRIPT_DIR" "$NC"

# ---------- 3. 打包 ----------
STATUS=1

if command -v python3 >/dev/null 2>&1; then
    python3 - "$TARGET" <<'PY'
import os
import sys
import zipfile

target = sys.argv[1]
root = os.getcwd()

# 排除规则与旧脚本保持一致；新增产物类型时两边都要改
skip_dirs = {'.git', '.vscode', '.idea', '__pycache__', 'temp_package', 'node_modules', 'docs'}
skip_suffix = ('.love', '.zip', '.bash', '.tmp', '.log', '.md')
skip_names = {'pack.sh', 'AGENTS.md', '.gitignore'}

def skipped(name):
    if name in skip_names:
        return True
    if name.startswith('test_') and name.endswith('.lua'):
        return True
    return name.endswith(skip_suffix)

entries = []
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in skip_dirs)
    for name in sorted(filenames):
        if skipped(name):
            continue
        full = os.path.join(dirpath, name)
        # 不要把正在写的包本身打进去
        if os.path.abspath(full) == os.path.abspath(target):
            continue
        entries.append((full, os.path.relpath(full, root).replace(os.sep, '/')))

with zipfile.ZipFile(target, 'w', zipfile.ZIP_STORED) as archive:
    for full, rel in entries:
        archive.write(full, rel)

print('包含文件: %d 个' % len(entries))
for _, rel in entries[:10]:
    print('  ' + rel)
if len(entries) > 10:
    print('  ... 另外 %d 个' % (len(entries) - 10))
PY
    STATUS=$?
else
    command -v zip >/dev/null 2>&1 ||
        die "既没有 python3 也没有 zip，无法打包；先 pkg install python 或 pkg install zip"

    rm -f "$TARGET"
    zip -r -0 -X "$TARGET" . \
        -x '*.love' '*.zip' '*.bash' '*.tmp' '*.log' '*.md' \
        -x 'pack.sh' 'AGENTS.md' '.gitignore' 'test_*.lua' \
        -x '.git/*' '.vscode/*' '.idea/*' '__pycache__/*' 'temp_package/*' 'docs/*' \
        > /dev/null 2>&1
    STATUS=$?
fi

# ---------- 4. 结果 ----------
[ "$STATUS" -eq 0 ] || die "打包失败（退出码 $STATUS）"
[ -f "$TARGET" ] || die "没有生成 $TARGET"

printf '%s✅ 打包成功: %s%s\n' "$GREEN" "$TARGET" "$NC"
ls -lh "$TARGET" | awk '{print "大小: " $5}'
