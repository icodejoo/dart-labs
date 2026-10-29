---
title: dioman 架构概览
status: active
updated: 2026-10-29
summary: 现行客户端、固定阶段、结果模型与维护入口
---

# dioman 架构概览

Dioman 是以 Dio 为引擎的请求包装器。客户端编译插件链，每次逻辑调用捕获链快照；Dio 拦截器在真正传输时运行。使用入口是 lib/dioman.dart 的 show 白名单。

## 请求流

outer（loading、notify）→ prepare（repath、filter、timeout）→ attempt（retry、breaker）→ credential（auth）→ source（mock、share、cache、offline）→ Dio → 归一化结果沿链返回。

envs 只执行 setup。自定义插件在指定阶段按 pre/post 排序；同组稳定排序。配置属于工厂，状态属于每客户端 setup 实例。请求补丁从当前基准派生，兄弟尝试互不污染。

## 内核边界

key 在整形后惰性计算；取消覆盖整个逻辑请求；等待统一清理计时器和订阅。响应工厂只拆一层信封，kind、逻辑状态与 HTTP 状态分开。链内返回结果，公共边界将程序错误原栈抛出；动词方法对可预期失败抛结果，send 返回结果。

## 模块与贡献入口

lib/src 中 client、pipeline、context、request、response、transport、options、key、clock 组成内核；plugins 中有 12 个插件与 envs，token_manager 和 cache_store 定义宿主接口。内部 part 文件与服务不从公开入口导出。

- [核心架构细节](pipeline-architecture.md)：接口与边界。
- [插件规格](pipeline-plugin-spec.md)：选项、行为及终审补充，C1–C13。
- [测试方案](pipeline-test-plan.md)：I1–I7、六层、性能门槛。
- [实施计划](pipeline-implementation-plan.md)：批次范围与终审。
- [迁移指南](../guides/migrating-to-pipeline.md)：0.7.2 的逐项替代。

改 lib/src 前先读 .claude/skills/dioman/SKILL.md，并按其中命令验证。历史安装顺序只供追溯，不作为当前约束。
