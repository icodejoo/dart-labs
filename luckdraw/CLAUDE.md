# luckdraw 项目规则

## 分支

- `luckdraw` 分支是本项目的默认工作分支：日常开发、提交、推送都在它上面进行，新分支也从它拉。
- 推送 `luckdraw` 分支触发 CI，并由 `deploy-luckdraw.yml` 构建 example 部署到 Pages。
- 不再使用 `jelon/luckdraw-simplify` 这类一次性分支；确需临时分支，用完合回 `luckdraw` 后删除。
