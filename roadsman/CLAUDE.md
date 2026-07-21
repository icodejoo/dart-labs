# roadsman — 项目规则

**先读 `/roadsman` 技能**(`.claude/skills/roadsman/SKILL.md`)再改代码——架构、
移植对照、验收流程都在那里,此处只记项目级规则。

## 1. README 只维护英文版

不再维护 `README.zh-CN.md` 或任何中文版 README。README 只有一份 `README.md`,
用英文撰写。

## 2. 代码注释一律用英文,禁止出现中文

`lib/`、`test/`、`example/` 下所有代码注释(`//`、`/* */`、文档注释 `///`)一律用
英文书写,不允许出现中文。此规则只约束**注释**,不影响面向用户的数据/文案字段
(如 `OutcomeDef.label`、`MarkerDef.label` 这类展示文案本就是中文,不受此规则
约束——它们是数据,不是注释)。

## 3. 包发布不带 GitHub 链接

`pubspec.yaml` 不写 `homepage`/`repository`/`issue_tracker` 字段。
