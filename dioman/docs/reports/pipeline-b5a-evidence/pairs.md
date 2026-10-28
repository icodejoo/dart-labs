| 插件对 | 覆盖用例 | 范围 / 无时序交互理由 |
|---|---|---|
| loading + notify | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=3` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + retry | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=5` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=9` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=17` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=33` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=65` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=129` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=257` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| loading + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| loading + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] loading+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + retry | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=6` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=10` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=18` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=34` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=66` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=130` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=258` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| notify + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| notify + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] notify+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + breaker | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=12` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=20` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=36` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=68` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=132` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=260` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| retry + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| retry + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] retry+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + auth | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=24` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=40` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=72` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=136` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=264` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| breaker + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| breaker + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] breaker+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + mock | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=48` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=80` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=144` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=272` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| auth + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| auth + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] auth+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + share | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=96` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=160` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=288` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| mock + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| mock + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] mock+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + cache | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=192` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| share + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=320` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| share + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| share + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+timeout 补丁穿透发送` | 遵从 B4：共享底层三超时清零；本用例核对底层值，订阅者独立超时另由 B4 回归覆盖 |
| share + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] share+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + offline | `powerset_combo_test.dart` — `[DiomanPlugin powerset] mask=384` × 全部九流程 | 存在时序交互；独立二元子集及所有包含该对的更大子集均检查 I1–I7 |
| cache + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| cache + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] cache+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + repath | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+repath 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| offline + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] offline+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + filter | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+filter 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| repath + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] repath+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| filter + timeout | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] filter+timeout 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| filter + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] filter+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
| timeout + envs | `prepare_pairs_combo_test.dart` — `[DiomanPlugin pairs] timeout+envs 补丁穿透发送` | 无额外时序策略；核对 path/query/body/三超时及 envs 配置实际到达 adapter |
