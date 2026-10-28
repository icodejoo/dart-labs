# dioman B0 旧行为迁移总表

来源：`dart test test_legacy --reporter json` 的 testStart/testDone 事件（[原始事件](raw/legacy-tests.ndjson)），排除 loading、hidden、metadata.skip 与 testDone.skipped；每个参数化运行时标题单独一行。
归档前路径由 `test_legacy/` 一一还原成 `test/`；默认排除 real 标签，不把未运行的外部服务测试计入本地总数。旧 powerset 的 32767 个内部循环是一个运行时 test，不虚增用例。
总账源是未改动的 `test/accept/lib/matrix.json`，逐行以原 id 对账。预计位置按 `docs/guides/test-layers.md` 与 pipeline-test-plan §1 最低证明层安排；纯归一化进 unit，真实 IO 进 integration，多插件进 combo。
API id 是 B1–B5 的预定命名；删除能力的 new_api/location 是替代能力，绝非承诺恢复被删接口。`Options` 的机械换键仍可 keep；只有协议、判定或可观察行为变化才 change。
存疑为互斥分类上的附加标记，已计入 keep/change/drop，不能再加一次。B0 不替终审裁决。

## 计数

| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |
|---|---:|---:|---:|---:|---:|
| tests/unit | 91 | 36 | 9 | 46 | 0 |
| tests/rule | 238 | 118 | 76 | 44 | 0 |
| tests/boundary | 89 | 53 | 33 | 3 | 0 |
| tests/combo | 122 | 20 | 93 | 9 | 0 |
| tests/integration | 40 | 12 | 13 | 15 | 0 |
| tests/合计 | 580 | 239 | 224 | 117 | 0 |

`tests: 旧总数 580 = keep 239 + change 224 + drop 117`

| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |
|---|---:|---:|---:|---:|---:|
| matrix/unit | 107 | 7 | 40 | 60 | 0 |
| matrix/rule | 278 | 163 | 81 | 34 | 0 |
| matrix/boundary | 0 | 0 | 0 | 0 | 0 |
| matrix/combo | 19 | 4 | 13 | 2 | 0 |
| matrix/integration | 38 | 7 | 28 | 3 | 0 |
| matrix/合计 | 442 | 181 | 162 | 99 | 0 |

`matrix: 旧总数 442 = keep 181 + change 162 + drop 99`

## 终审裁决（2026-10-29）

54 条存疑按 [插件规格 §8.1](../../design/pipeline-plugin-spec.md) 裁决。请求级 `now` 覆盖、`cachePolicy.none`、`DiomanCacheOptions.maxEntries`、`DiomanSharePolicy.none` 相关行改为 drop（C13），其余维持 change；由 B1 工具生成并核对公式。所有原存疑标记已解除。

## 存疑行（逐项交终审）

| 来源 / 身份 | 旧位置或能力 | 暂定 | 理由 |
|---|---|---|---|

## 可复算

```powershell
python tool/pipeline_migration.py generate
python tool/pipeline_migration.py verify
```

verify 同时核对事件身份全集、matrix id 全集、唯一性、互斥分类、change 的 C1–C13、drop 理由、新位置与 Markdown 行数，输出见报告。
