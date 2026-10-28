#!/usr/bin/env python3
"""水合 Git LFS 二进制并检查是否仍是指针文件（仅标准库）。

用法：
  python tool/libmpv_hydrate.py            拉取（codeup 失败自动换 GitHub）后检查
  python tool/libmpv_hydrate.py --check    只检查，不拉取
  python tool/libmpv_hydrate.py --selftest 离线自测指针判定逻辑

退出码：0 全部为真实文件；1 仍有指针或拉取失败；2 自测失败。
"""
import argparse
import os
import subprocess
import sys
import tempfile

# GitHub 镜像地址：codeup 常缺 CI 新推的 LFS 对象，兜底从这里拉。
GITHUB_URL = "https://github.com/icodejoo/dart-labs.git"
# 指针文件头部特征。
POINTER_HEAD = b"version https://git-lfs.github.com/spec"
# 小于该字节数一律视为指针（真实二进制远大于此）。
MIN_REAL_SIZE = 1024


def is_pointer(path):
    """判断文件是否为 LFS 指针：过小或内容以指针头开头。"""
    try:
        if os.path.getsize(path) < MIN_REAL_SIZE:
            return True
        with open(path, "rb") as f:
            return f.read(len(POINTER_HEAD)) == POINTER_HEAD
    except OSError:
        return True


def run(args, cwd):
    """运行命令并回显输出，返回退出码。"""
    print("$ " + " ".join(args))
    return subprocess.call(args, cwd=cwd)


def repo_root():
    """返回 git 仓库根目录。"""
    out = subprocess.check_output(["git", "rev-parse", "--show-toplevel"])
    return out.decode().strip()


def lfs_files(root):
    """列出 LFS 跟踪的文件（相对仓库根的路径）。"""
    out = subprocess.check_output(["git", "lfs", "ls-files", "-n"], cwd=root)
    names = [p for p in out.decode("utf-8").splitlines() if p.strip()]
    links = symlink_paths(root)
    # 与索引取交集：已暂存的改名会让 lfs ls-files 带出 HEAD 里的旧路径。
    idx = subprocess.check_output(["git", "ls-files"], cwd=root).decode("utf-8").splitlines()
    live = set(idx)
    return [p for p in names if p not in links and p in live]


def symlink_paths(root):
    """返回 git 里模式为 120000 的符号链接路径集合（Windows 上会落成小文本，不是指针）。"""
    out = subprocess.check_output(["git", "ls-files", "-s"], cwd=root)
    res = set()
    for line in out.decode("utf-8").splitlines():
        meta, _, path = line.partition("	")
        if meta.startswith("120000"):
            res.add(path)
    return res


def hydrate(root):
    """先从 origin 拉，失败再从 GitHub 拉，最后 checkout 到工作区。"""
    if run(["git", "lfs", "pull"], root) != 0:
        print("origin 拉取不完整，改从 GitHub 拉取")
        run(["git", "lfs", "fetch", GITHUB_URL], root)
        run(["git", "lfs", "checkout"], root)


def check(root):
    """检查所有 LFS 文件，返回仍是指针的相对路径列表。"""
    return [p for p in lfs_files(root) if is_pointer(os.path.join(root, p))]


def selftest():
    """离线自测指针判定：小文件、指针头、真实大文件、缺失文件。"""
    with tempfile.TemporaryDirectory() as d:
        ptr = os.path.join(d, "ptr")
        with open(ptr, "wb") as f:
            f.write(POINTER_HEAD + b"\noid sha256:0\nsize 1\n")
        small = os.path.join(d, "small")
        with open(small, "wb") as f:
            f.write(b"x" * 10)
        bigptr = os.path.join(d, "bigptr")
        with open(bigptr, "wb") as f:
            f.write(POINTER_HEAD + b"\n" + b" " * 2000)
        real = os.path.join(d, "real")
        with open(real, "wb") as f:
            f.write(b"MZ" + b"\0" * 4096)
        cases = [(ptr, True), (small, True), (bigptr, True), (real, False),
                 (os.path.join(d, "none"), True)]
        for p, want in cases:
            got = is_pointer(p)
            if got != want:
                print("selftest FAIL: %s want=%s got=%s" % (p, want, got))
                return 2
    print("selftest OK")
    return 0


def main():
    """入口：解析参数，水合（可选）并检查。"""
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="只检查不拉取")
    ap.add_argument("--selftest", action="store_true", help="离线自测")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    root = repo_root()
    if not a.check:
        hydrate(root)
    bad = check(root)
    if bad:
        print("\n[FAIL] 以下 LFS 文件仍是指针（共 %d 个）：" % len(bad))
        for p in bad:
            print("  - " + p)
        print("请检查网络/远端 LFS 对象后重跑：python tool/libmpv_hydrate.py")
        return 1
    print("[OK] 所有 LFS 文件均为真实内容")
    return 0


if __name__ == "__main__":
    sys.exit(main())
