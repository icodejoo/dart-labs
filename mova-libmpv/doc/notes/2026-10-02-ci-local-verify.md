# 2026-10-02 CI 新增 dispatch 输入的本地复现验证

对象：提交 b6d7e69（`ffmpeg_ref` / `mpv_ref` / `commit_artifact`）。工作目录 WSL `/root/w/cilocal`。
方式：WSL 无 `act`（未装，且 act 跑 ubuntu-22.04 镜像与 actions/cache 不划算），改为**手工把 yaml 的 run 脚本原样抽出来跑**，用 env 模拟 inputs。以下均为实测，推断处单独标注。

## 结论

| # | 项 | 结果 |
|---|----|------|
| 2 | 默认输入（空）Linux | 实测通过：FFMPEG_TAG=n6.0.1，MPV_COMMIT=78d43740…（该 commit 可 fetch，2023-09-30），configure 含 `--disable-bsfs --disable-swscale-alpha` 退出 0，LGPL2.1 与 https/tls/rtmps 检查通过，bsf 列表 11 项符合白名单，`CONFIG_SWSCALE_ALPHA` 为禁用 |
| 2 | 默认输入 Android | 静态推演：`if: inputs.ffmpeg_ref \|\| inputs.mpv_ref` 两者空串 -> falsy，覆盖步骤跳过；缓存 key 的 `a && format() ` 为空串，key 与改动前相同 |
| 3 | ffmpeg_ref=9.0.2 Linux | **按 workflow 原样 configure 失败**：`Unknown option "--disable-postproc"`（n9 已移除 postproc，即计划 T0.4）。临时去掉该选项后 configure 退出 0，LGPL2.1、https/tls/rtmps、bsf 白名单均 OK，说明 `--disable-bsfs --disable-swscale-alpha` 在 n9.0.2 下被接受（未扩大改动，仅诊断） |
| 4 | Android 覆盖 sed | 实测：depinfo.sh:16 `v_ffmpeg=6.0` 被换成 `9.0.2`；mpv hash 在 depinfo.sh:17 与 download-deps.sh:53 各出现一次，用假 hash 验证 sed 全部替换成功；download-deps.sh:31 用 `--branch n$v_ffmpeg`，即 n9.0.2 |
| 4 | mova 补丁 | 实测：1ecf510 上 `git apply --check` 与实际 apply `libmpv-android-video-build.patch` 通过，`flavors-mova-slim.sh` cp 到 scripts/ffmpeg.sh 正常。补丁只改 build.sh 与 scripts/*.sh，不碰 depinfo/patches，故与 9.0.2 覆盖步骤无冲突（顺序：先 apply 补丁、后覆盖，OK） |
| 5 | commit_artifact 表达式 | 见下表 |

## Bug（workflow 需改，我没动）

### Bug 1：Linux + ffmpeg_ref=9.x 必挂在 `--disable-postproc`
- 证据：`/root/w/cilocal/cfg_902.out`，`Unknown option "--disable-postproc"`。
- 最小修复：configure 里对 n9 条件去掉该选项，例如 `PP_OPT=$([[ "$FFMPEG_TAG" == n9* ]] || echo --disable-postproc)`，configure 行里引用 `$PP_OPT`；这正是计划 T0.4 要做的事。

### Bug 2（实测复现，Android 两个 job 都有）：`rm -f` 两个补丁后 patch.sh 会失败
- `buildscripts/patch.sh` 对 `patches/*` 里每个目录执行 `patches=($dep_path/*)`，无 nullglob。`patches/ffmpeg/` 只有这两个文件，删完变空目录，数组变成字面量 `patches/ffmpeg/*`，`git apply` 报 `can't open patch '.../patches/ffmpeg/*'`，`bash -e` 退出码 128，直接让 "Patch" 步骤（workflow 175/356 行 `./patch.sh`）失败。已用 patch.sh 同款循环在 a_902 副本上复现。
- 最小修复：把 `rm -f patches/ffmpeg/hls_mp4_seek.patch patches/ffmpeg/dash_base_url_escape.patch` 改成 `rm -rf patches/ffmpeg`（目录整个删，循环只剩 `patches/mpv`，推断可行；未跑完整 patch.sh 因需要 deps 源码）。注意：该删除目前放在 `if: ffmpeg_ref || mpv_ref` 里，若只传 mpv_ref（ffmpeg 仍 6.0）也会删掉 ffmpeg 补丁，应只在 `[ -n "$FFMPEG_REF" ]` 分支内删。

### 小问题 3：仅传 ffmpeg_ref 时 `grep -n "$MPV_REF" download-deps.sh` 空模式
- `MPV_REF` 为空时 `grep -n ""` 匹配所有行，日志刷满整个文件（有 `|| true`，不致命）。修复：包进 `if [ -n "$MPV_REF" ]`。

### 备注（非 bug）
- 传 mpv_ref 后，`patches/mpv/mpv_lavc_set_java_vm.patch` 对新 mpv 是否仍可 apply 未验证（需 deps 源码，属 T0.x 范围）。
- Linux job 无 commit 步骤；5 个 commit 步骤（android-arm64、android-other-abi、darwin、ios、windows）均已加 if 守卫，Linux 无需。
- 缓存 key 用 ffmpeg_ref 原文拼接，含 `/` 等字符时可能非法，9.0.2 这类版本号无问题。

## commit_artifact 的 if 取值（静态推演）

表达式：`github.event_name != 'workflow_dispatch' || inputs.commit_artifact`

| 触发 | event_name != dispatch | inputs.commit_artifact | 结果 |
|------|-----|-----|------|
| push（路径过滤命中） | true | 空（无 inputs） | true，提交（行为同改动前） |
| dispatch, commit_artifact=true（默认） | false | true | true，提交 |
| dispatch, commit_artifact=false | false | false | false，跳过 |

## 命令（可复现）

```bash
# Android 部分
git clone https://github.com/media-kit/libmpv-android-video-build base && git -C base checkout 1ecf510
cp -r base a_def && cd a_def && git apply --check $D/libmpv-android-video-build.patch && git apply $D/libmpv-android-video-build.patch
cp $D/flavors-mova-slim.sh buildscripts/scripts/ffmpeg.sh
# 覆盖步骤 sed 原样：见 workflow 144-163 行；patch.sh 空目录复现：mkdir deps/ffmpeg; git init; 跑其循环
# Linux 部分：workflow 901-927 行 configure 原样（FFMPEG_TAG=n6.0.1 / n9.0.2，--shared 克隆 /root/w/ffmpeg 与 /root/w/ff902）
```
