#!/bin/sh
# 为子项目创建 sparse worktree：每个 worktree 只检出自己的子目录，互不抢分支、体积很小。
#
# 用法：
#   ./setup-worktrees.sh                     列出可用子项目
#   ./setup-worktrees.sh <项目>              detached HEAD，从当前提交建
#   ./setup-worktrees.sh <项目> <分支>        检出已有分支；不存在则从起点新建
#   ./setup-worktrees.sh <项目> <分支> <起点>  新建分支时指定起点（默认 HEAD）
#   ./setup-worktrees.sh all                 为所有子项目各建一个 detached worktree
#
# worktree 目录：与仓库同级的 ../<仓库名>-<项目>
# 新建分支后不会自动 push，需自行 git push -u origin <分支>

set -e

# 仓库根目录与名称
ROOT=$(git rev-parse --show-toplevel)
REPO=$(basename "$ROOT")
cd "$ROOT"

# 子项目 = 含 pubspec.yaml 的一级目录
list_projects() {
  git ls-files '*/pubspec.yaml' | awk -F/ 'NF==2 {print $1}' | sort -u
}

# 创建单个 worktree：$1 项目 $2 分支(可空) $3 起点(可空)
add_one() {
  proj=$1
  branch=$2
  base=${3:-HEAD}
  dir="$ROOT/../$REPO-$proj"

  if ! list_projects | grep -qx "$proj"; then
    echo "未知子项目：$proj" >&2
    exit 1
  fi
  if [ -e "$dir" ]; then
    echo "跳过 $proj：目录已存在 $dir"
    return 0
  fi

  if [ -z "$branch" ]; then
    git worktree add --detach --no-checkout "$dir" HEAD
  elif git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add --no-checkout "$dir" "$branch"
  else
    git worktree add --no-checkout -b "$branch" "$dir" "$base"
    echo "提示：新分支未绑定上游，需要时执行 git -C \"$dir\" push -u origin $branch"
  fi

  git -C "$dir" sparse-checkout init --cone
  git -C "$dir" sparse-checkout set "$proj"
  git -C "$dir" checkout
  echo "已创建：$dir"
}

case "$1" in
  "")
    echo "可用子项目："
    list_projects | sed 's/^/  /'
    ;;
  all)
    for p in $(list_projects); do add_one "$p"; done
    ;;
  *)
    add_one "$1" "$2" "$3"
    ;;
esac
