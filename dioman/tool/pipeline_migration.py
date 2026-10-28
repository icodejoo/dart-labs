"""B0 运行时清单生成与独立核对；仅使用 Python 标准库。"""
import collections
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reference/pipeline-migration'
LAYERS = ('unit', 'rule', 'boundary', 'combo', 'integration')
DECISIONS = ('keep', 'change', 'drop')
MANIFEST = DEST / 'manifest.json'
MATRIX = ROOT / 'test/accept/lib/matrix.json'
EVENTS = DEST / 'raw/legacy-tests.ndjson'


def runtime_tests():
    """从最终 JSON reporter 事件取得实际用例，排除加载和跳过事件。"""
    events = [json.loads(line) for line in EVENTS.read_text(encoding='utf-8-sig').splitlines() if line.strip()]
    assert events[-1]['type'] == 'done' and events[-1]['success'], '必须等待旧测试最终成功'
    suites = {e['suite']['id']: e['suite']['path'] for e in events if e['type'] == 'suite'}
    done = {e['testID']: e for e in events if e['type'] == 'testDone'}
    result = []
    for event in events:
        if event['type'] != 'testStart':
            continue
        test = event['test']
        outcome = done[test['id']]
        if test['name'].startswith('loading ') or test['metadata'].get('skip') or outcome['skipped'] or outcome['hidden']:
            continue
        assert outcome['result'] == 'success'
        path = Path(suites[test['suiteID']]).resolve().relative_to(ROOT).as_posix()
        assert path.startswith('test_legacy/')
        result.append({'file': path.replace('test_legacy/', 'test/', 1), 'title': test['name']})
    return sorted(result, key=lambda t: (t['file'], t['title']))


def api_target(api):
    """按架构与插件规格命名预计新 API；未确定的公开面由存疑列说明。"""
    api = api.split('#')[0]
    api = re.sub(r'\.new\(([^)]+)\)', r'.\1', api)
    direct = {
        'Dioman.install': 'Dioman', 'Dioman.installPlugins': 'Dioman',
        'Dioman.sort': 'Dioman.inspect', 'Dioman.validate': 'Dioman.inspect',
        'DiomanHandle.plugin': 'Dioman.plugin', 'DiomanHandle.remove': 'Dioman.eject',
        'DiomanHandle.dispose': 'Dioman.dispose', 'DiomanHandle.plugins': 'Dioman.inspect',
        'DiomanHandle.append': 'Dioman.use', 'DiomanHandle.prepend': 'Dioman.use',
        'DiomanHandle.insertAfter': 'Dioman.use', 'DiomanHandle.insertBefore': 'Dioman.use',
        'cancelAll': 'Dioman.cancelAll', 'kKey': 'DiomanContext.key',
        'defaultAuthFailure': 'DiomanAuth.onFailure', 'defaultFallback': 'DiomanMock.fallbackWhen',
        'DiomanCache.clear': 'DiomanCacheApi.clear', 'DiomanCache.remove': 'DiomanCacheApi.remove',
        'DiomanTokenManager.canRefresh': 'DiomanAuth.setup',
        'DiomanHandle.diagnoseSharedStateKeys': 'DiomanPlugin.setup; StateKey',
        'DiomanEnvs.apply': 'DiomanEnvs.setup',
        'DiomanEnvs.config': 'DiomanEnvs.setup',
        'DiomanEnvs.dio': 'DiomanEnvs.setup',
        'DiomanSharePolicy.none': 'DiomanShareOptions.enabled',
        'cancellableDelay': 'DiomanContext.wait',
        'prepareForReplay': 'DiomanContext.markReplayable',
    }
    if api in direct:
        return direct[api]
    if api.startswith('INV-'):
        return {'INV-01': 'Dioman.inspect', 'INV-02': 'Dioman.use', 'INV-03': 'Dioman.eject',
                'INV-04': 'StateKey', 'INV-05': 'Dioman.pending', 'INV-06': 'DiomanPlugin.setup',
                'INV-12': 'DiomanResponse', 'INV-13': 'DiomanResponseFactory',
                'INV-14': 'DiomanContext.wait', 'INV-15': 'DiomanShare.policy',
                'INV-16': 'DiomanCache.shouldStore', 'INV-17': 'DiomanNext',
                'INV-18': 'Dioman.dio', 'INV-20': 'DiomanCache',
                'INV-21': 'DiomanContext.markReplayable', 'INV-22': 'Dioman.dispose',
                'INV-23': 'Dioman.request', 'INV-24': 'DiomanResponse.kind',
                'INV-25': 'Dioman.send', 'INV-26': 'DiomanCall'}.get(api, 'Dioman')
    if api.startswith('DiomanPluginOrder') or api.endswith('.ordering'):
        return 'DiomanPlugin.stage; DiomanPlugin.enforce; Dioman.inspect'
    if api.startswith(('DiomanExtra', 'DiomanSharedStateKey')):
        return 'StateKey; DiomanContext.get; DiomanContext.set'
    if api.startswith('DiomanLog'):
        return 'LogInterceptor (Dio); Dioman.debug'
    if api.startswith('DiomanNormalize'):
        field = api.split('.')[-1]
        return {'codeKey': 'Envelope.code', 'dataKey': 'Envelope.data', 'messageKey': 'Envelope.message',
                'isSuccess': 'DiomanResponseFactory.isSuccess',
                'shouldNormalize': 'DiomanResponseFactory.envelope'}.get(field, 'DiomanResponseFactory')
    if api.startswith('DiomanException'):
        return 'DiomanResponse.' + api.split('.')[-1]
    if api.startswith('DiomanBreakerOpenException'):
        return 'DiomanResponse.kind; DiomanResponse.reason'
    if api.startswith(('DiomanOfflineException', 'DiomanOfflineReason')):
        return 'DiomanResponse.kind; DiomanResponse.reason'
    if api.startswith('DiomanCancel'):
        return 'Dioman.cancelAll; Dioman.pending; DiomanCall.cancelToken'
    if api.startswith('DiomanKey'):
        field = api.split('.')[-1]
        return 'DiomanCall.key' if field in ('key', 'enabled') else 'DiomanKeyOptions.' + field if field in ('ignores', 'namespace') else 'DiomanContext.key'
    if api.startswith('DiomanMockAdapter'):
        field = api.split('.')[-1]
        return 'DiomanMock.' + field if field in ('enabled', 'fallbackWhen', 'mockUrl', 'routes') else 'DiomanMock'
    if re.match(r'Dioman(?:Auth|Retry|Share)\.(cancel|share|dio|breaker|hasMultipleDownstreamSettlers|registerDownstreamSettler|settle)$', api):
        return 'DiomanPluginInstance.handle; DiomanNext'
    if api.endswith('.dispose') and re.match(r'Dioman(?:Auth|Retry|Share|Breaker|Cache|Loading|Offline)\.', api):
        return 'DiomanPluginInstance.dispose'
    if re.match(r'DiomanBreaker\.(admit|recordResponse|recordError)$', api):
        return 'DiomanBreaker.setup; DiomanPluginInstance.handle'
    if api.endswith('.now'):
        return api[:-4] + '.clock' if 'Options' not in api else 'DiomanClock'
    if api.startswith(('ReplayClient', 'RequestClaims')) or api in ('claimRequest', 'releaseClaim'):
        return 'DiomanNext; DiomanContext.wait'
    if api == 'DiomanPlugin.dispose':
        return 'DiomanPluginInstance.dispose'
    if re.search(r'\.(onRequest|onResponse|onError)$', api):
        return api.split('.')[0] + '.setup; DiomanPluginInstance.handle'
    return api


def classify(text, file='', ledger=False):
    """逐类审计旧契约；返回判定、C 编号、迁移理由及待终审的问题。"""
    action, codes, reason, doubt = 'keep', [], '行为保持；按新 API 重写，并用新响应/请求夹具验证。', ''

    def change(cs, why):
        """累计同一行涉及的明确变化。"""
        nonlocal action, reason
        action = 'change'
        codes.extend(cs.split(','))
        reason = why

    def drop(cs, why):
        """只删除已明确移除的能力或旧机制本身。"""
        nonlocal action, reason
        action = 'drop'
        codes.extend(cs.split(','))
        reason = why

    if 'DiomanMockAdapter' in text or 'defaultFallback' in text or 'mock_adapter' in file:
        change('C7', '改测 source 阶段 DiomanMock：命中短路，不进入 share/cache/offline；探测回落用 next。')
        if any(s in text for s in ('markerHeader', '标记头', 'mock marker', 'delegates force')) or (ledger and text.startswith(('DiomanMockAdapter.close ', 'DiomanMockAdapter.new(inner) '))):
            drop('C7', '删除 adapter 包装、关闭委托或标记头协议；由客户端管理 Dio，mock 短路天然不入 cache。')
    if 'DiomanNormalize' in text or 'normalize_' in file:
        change('C3,C8', '归一化移到传输边界，由客户端工厂配置；插件读取逻辑状态，成功数据只解包一次。')
        if 'DiomanNormalizeOptions.' in text:
            drop('C3', '删除请求级 normalize 配置；不同信封/成功码改用独立客户端的 DiomanResponseFactory。')
        if any(s in text for s in ('关闭：业务失败照常缓存', '没装 normalize：2xx', '动态 append / remove normalize', '动态 insert normalize', 'dispose 撤销接线')):
            drop('C3,C8', '删除可插拔 normalize 与自动接线能力；工厂始终归一化，cache 默认按 r.ok 判定。')
    if any(s in text for s in ('DiomanException', 'DiomanBreakerOpenException', 'DiomanOfflineException', 'DiomanOfflineReason')):
        change('C2,C6', '可预期失败改断言 DiomanResponse.kind/reason；保留业务字段，去掉旧异常类型断言。')
        if 'toString' in text and (ledger or 'exception_test' in file):
            drop('C6', '删除旧异常专属字符串格式；替代为 DiomanResponse 字段断言。')
    if 'DiomanKey' in text or re.search(r'(^|\W)kKey(\W|$)', text):
        change('C3,C5', 'key 算法迁入 DiomanContext.key，客户端配置 DiomanKeyOptions；显式 key/false 用 DiomanCall.key。')
    if 'DiomanCancel' in text or (ledger and text.startswith('cancelAll ')):
        change('C3', '取消由内核覆盖每个逻辑请求，改测 Dioman.cancelAll/pending 和调用级 cancelToken。')
        if any(s in text for s in ('config]', '.track ', '.untrack ', '多个取消插件', '移除插件以 plugin ejected', '不自动登记')):
            drop('C3', '删除可禁用/多实例取消插件及手工 track/untrack；内核统一登记，dispose 取消全部请求。')
    if any(s in text for s in ('DioException', '转成错误', '以取消错误', '抛出 500', 'LAST attempt as-is')):
        change('C2', '落定时可预期失败抛 DiomanResponse；send 返回失败结果，bug 保留原异常和 stack。')
    if any(s in text for s in ('callback', '回调', 'namespace failures')) and any(s in text for s in ('抛', '异常', '吞', 'failures', 'throws')):
        change('C2,C12', '判定类回调抛错按 internal 流经外层清理后原样抛出；通知类隔离；onRefresh 仍按刷新失败处理。')
    if any(s in text for s in ('DiomanAuthFailureAction', 'defaultAuthFailure', 'business', '业务')) and any(s in text for s in ('DiomanAuth', 'DiomanRetry', 'DiomanBreaker', 'DiomanCache')):
        change('C8', 'auth/retry/breaker/cache 统一消费归一化后的逻辑状态和 ok，增加 business 风格断言。')
    if any(s in text for s in ('NaN', 'default predicate', 'DiomanFilter.predicate ')):
        change('C9', '保留 null/空白过滤规则，并新增 NaN 默认剔除断言。')
    if any(s in text for s in ('DiomanLoading', 'loading', '加载括号')) and any(s in text for s in ('cache hit', '缓存命中', 'follower is invisible', 'batch edge', 'shared counter', 'includes waiting')):
        change('C1,C10', 'loading 位于 outer：缓存命中、share 跟随者和刷新等待都属于逻辑请求；不同回调按身份独立计数。')
    if 'cache hit bypasses DiomanAuth' in text:
        change('C1,C4', 'auth 位于 cache 外层；清掉 token 的受保护请求先被 auth 拒绝，不能用旧缓存绕过认证。')
    if any(s in text for s in ('NOT cached', 'ORIGINAL failed attempt poisoned', 'bare-dio', 'SAME auth header', '绕过原请求链', 'internal throwaway Dio')):
        change('C1,C8', '重试重新进入内层 breaker/auth/source；每次尝试归一化，恢复成功按 cache 新鲜度屏障写入。')
    if ('DiomanShare' in text or 'share' in file) and any(s in text for s in ('独立', '不同实例', 'distinct', '副本', 'without DiomanKey', 'takeover', '接手', '首发取消', 'while the retry is in flight', 'THIRD caller', 'NEW caller')):
        change('C1,C3', 'share 按一次尝试共享同一个只读 R；首发离场保留共享传输，最后订阅者离开才取消；不再要求安装 key。')
    if 'Stream 请求体' in text or 'Stream body' in text or '流请求体不自动重放' in text:
        change('C1', 'markReplayable 对不可克隆 Stream 回退原引用并 debug 告警；不再保留旧版拒绝重放断言。')
    if 'DiomanTokenManager.canRefresh' in text:
        drop('C11', '删除 canRefresh 契约；刷新是否失效由 auth 实例管理，保留 accessToken/refreshToken/clear 用例。')
    if 'EnvelopeTransformer' in text:
        drop('C3,C8', '删除执行器补库的信封转换器；由内核工厂统一判定，D21 透传能力按缺 raw-business-code 跳过。')
    if '能力集合' in text:
        change('C3,C7', '按新能力集合重建断言，声明 mock-in-chain，移除旧插件数量和传输层 mock 假设。')
    if 'DiomanLog' in text or '/log_' in file:
        drop('C3', '删除自带报文日志插件及请求级格式开关；使用 Dio LogInterceptor，debug 只负责调用点和告警。')
    if any(s in text for s in ('DiomanExtra', 'DiomanSharedStateKey')) or '/extra_' in file:
        drop('C5', '删除字符串 extra 注册表、描述表和重复状态键诊断；替代为 StateKey<T> 及每客户端 setup 隔离状态。')
    if '/request_claims_test' in file or '/replay_support_test' in file or re.search(r'^(ReplayClient|RequestClaims|claimRequest|releaseClaim)\b', text):
        drop('C1,C5', '删除认领/重放交接实现用例；对应取消与落定行为由 DiomanContext.wait/next 及 I1/I3/I6 重写。')
        if 'cancellableDelay' in text:
            change('C3', '可取消等待迁到 DiomanContext.wait，断言完成/超时/取消都摘掉订阅和计时器。')
    if 'DiomanPluginOrder' in text or '/plugin_order_test' in file:
        drop('C4', '删除拓扑排序、before/after/requires 与环/缺依赖诊断；阶段排序与重复名改在新 pipeline 单测。')
        if 'duplicateName' in text or '重复名' in text:
            change('C4', '保留重复名拒绝行为，改由构造/use 抛 ArgumentError，并验证客户端链不变。')
    if (ledger and re.search(r'^Dioman(?:Auth|Retry|Share)\.(cancel|share|dio|breaker|hasMultipleDownstreamSettlers|registerDownstreamSettler|settle)(?:\s|$)', text)) or any(s in text for s in ('兼容 setter', '旧 setter', 'registerDownstreamSettler():', '兼容计数', '手动接的外部 breaker', 'dispose 解除 retry', '被移除的 retry 也被解除', '认领登记被外部移除')):
        drop('C1,C4', '删除宿主/settler/兼容 setter/手工结算接线能力；重发由 next 及固定阶段天然组合。')
    if ledger and re.search(r'^DiomanBreaker\.(admit|recordResponse|recordError)\b', text):
        drop('C1,C4', '删除为 retry 接线公开的放行/记账方法；改从 DiomanBreaker.setup 后的中间件验证每次尝试。')
    if any(s in text for s in ('reject(callFollowing=', 'handOff', 'runDownstream')):
        drop('C1', '删除 handler 传播标志和重放下游交接协议；Dio 用户拦截器只在 transport 内每次尝试运行。')
    if ledger and text.startswith('DiomanPlugin.ordering '):
        drop('C4', '删除 ordering 声明，改用 stage/enforce。')
    elif ledger and re.search(r'\.ordering\b', text):
        change('C4', '固定阶段和内置位置取代 before/after，改测 inspect 及 prepare 后惰性 key。')
    if '/install_' in file or (ledger and text.startswith(('Dioman.install', 'DiomanHandle.'))):
        if action != 'drop':
            change('C1,C4', '用 Dioman 构造/use/eject/inspect/plugin/dispose 重写装配；在途保留链快照，禁止按锚点插拦截器。')
        if any(s in text for s in ('anchor 不在', 'requires 的插件不能移除', '位置违反约束', '缺失必需依赖')):
            drop('C4', '删除锚点、拓扑依赖与位置违规能力；自定义插件用 stage/enforce，移除按名字执行。')
    if ledger and text.startswith(('Dioman.sort ', 'Dioman.validate ')):
        drop('C4', '删除公开拓扑排序与校验；改用固定阶段，inspect 只查询已编译顺序。')
    if ledger and text.startswith(('DiomanEnvs.apply ', 'DiomanEnvs.new(dio) ', 'DiomanEnvs.onRequest ')):
        change('C1', 'envs 只在 setup 自动应用克隆后的规则配置，不再手工 apply，也不进入请求链。')
    if ledger and text.startswith(('DiomanAuth.dispose ', 'DiomanRetry.dispose ')):
        change('C1', '生命周期改由客户端实例管理，不再释放旧版兜底重放 Dio；客户端 dispose 后拒绝新请求。')
    if ledger and text.startswith(('DiomanNotify.notify ', 'DiomanNotify.stringify ')):
        change('C1,C2', '通知位于 outer，notify(message, R) 与 stringify(R, ctx) 读取最终响应，每个逻辑请求最多通知一次。')
    if ledger and text.startswith(('DiomanCacheOptions.shouldStore ', 'DiomanRetry.shouldRetry ', 'DiomanRetry.statusCodes ', 'DiomanBreaker.shouldTrip ')):
        change('C8', '判定回调改读归一化 R；默认状态码是逻辑状态，cache 默认按 r.ok，不再依赖 normalize 接线。')
    if action != 'drop' and ('同时是' in text and ('extra 键' in text or '配置键' in text) or (ledger and text.split(' | ')[0].endswith('.pluginName'))):
        change('C5', '保留稳定插件名用于查找；请求级开关改用类型化选项键，不再将名称作为 extra 协议。')

    # 文档未完整承诺的公开面不能靠默认规则视为已拍板。
    uncertain = []
    if any(s in text for s in ('Options.now', 'fastMode', 'Options.builder', 'Key.builder', 'KeyOptions.ignores')):
        uncertain.append('新规格未列此旧请求级时钟/构键模式或 builder 覆盖；暂迁客户端 clock/key 服务，是否保留细粒度选项需终审。')
    if any(s in text for s in ('queue full evicts', '最早的请求被挤出', '满则挤出', 'shouldQueue: only writes', 'reads pass through', 'maxQueueSize |')):
        uncertain.append('新规格是拒绝新请求还是挤出旧请求、shouldQueue=false 是否放行，与旧契约有差异但未列独立 C；按 source/offline fail 模型暂改，需终审确认 reason 和零容量语义。')
    if 'shouldNormalize' in text:
        uncertain.append('新工厂要求 code+data，旧识别允许 code+message；迁客户端 envelope/create 后需终审确认自定义识别能力的替代范围。')
    if any(s in text for s in ('TTL=-1', 'TTL=0', '非正数不设上限', 'cachePolicy | 默认 none', 'CacheOptions.maxEntries', 'CachePolicy.none', 'SharePolicy.none')):
        uncertain.append('新选项表未完整规定 none/零负值/旧占位字段兼容；暂按新 optIn/false 迁移，边界默认值交终审。')
    if 'onRetry' in text and ('抛异常' in text or '回调异常' in text):
        uncertain.append('架构通知类枚举未列 onRetry；暂按 bug 原样抛出，是否属于通知隔离需终审。')
    if 'DiomanLoadingOptions.onChanged' in text and any(s in text for s in ('同周期', 'shared counter', 'batch edge', 'cycle')):
        change('C1,C10', '按回调身份独立计数，每个回调自行配对 true/false；不再共享一个显示周期吞掉另一回调。')
    if 'DiomanEnvs' in text and any(s in text for s in ('shallow-merged', '空地址和默认 json')):
        uncertain.append('新 envs 要求克隆容器，旧版按支持字段浅合并；空地址/default json 的合并优先级新文未展开，交终审。')
    if any(s in text for s in ('shouldRetry 抛异常', 'onFailure 抛异常', 'keyBuilder 抛异常', 'expiresAt 抛异常', 'isProtected 抛异常', '普通异常')) and action != 'drop':
        change('C2,C12', '判定/转换器 bug 经 internal 收尾后原异常原栈抛出；不能再包装成 DioException 或被 share 胜出结果掩盖。')
    if 'DiomanBreaker.onStateChange' in text and any(s in text for s in ('异常原样抛出', '不隔离回调异常')):
        change('C2,C12', '架构 §7 将 onStateChange 列为通知类：隔离通知异常并记录日志，不能抛给请求调用者；状态迁移仍生效。')
    if '释放后' in text and any(s in text for s in ('后续请求能启动', '走兜底', '退回独立传输层', '改走独立传输层')):
        change('C1', '不再复活已释放插件或使用独立兜底 Dio；客户端 dispose 后拒绝新调用，重发始终走客户端 transport。')
    if 'cache hit resolves before DiomanShare' in text:
        change('C1,C4', 'source 顺序改为 share→cache；命中仍可能先进入共享登记，cache 本身不触网。')
    if 'powerset_combo_test' in file:
        change('C1,C4', '旧全子集成功/恢复覆盖迁为 9 插件×512 子集×9 流程，统一检查 I1–I7；不搬旧拦截器内部循环。')
    if ledger and text.startswith('DiomanAuth.dio#transport-reuse '):
        action = 'keep'
        codes = []
        reason = '保留重放复用客户端 Dio adapter/连接且不关闭宿主的行为；删除 setter 不删除复用能力。'
    if ledger and text.startswith(('DiomanNormalize.enabled ', 'DiomanNormalize.name ', 'DiomanNormalize.pluginName ')):
        drop('C3', '删除可安装/禁用的 normalize 插件身份；替代为客户端 DiomanResponseFactory.envelope 配置。')
    if any(s in text for s in ('bucketCount', '.isOpen', '.stateOf', 'Offline.pending', 'Offline.flush', 'Loading.activeCount', 'defaultIdleTtl', 'defaultMaxBuckets')):
        uncertain.append('新规格未命名这些插件状态/管理公开 API；暂保留行为并建议通过 plugin<A>() 暴露，确切 API id 交 B3/B4 终审。')
    if uncertain and action != 'drop':
        change('C1,C5', reason if action == 'change' else '暂保留行为并迁入新客户端选项/实例；公开面命名以终审为准。')
        doubt = ' '.join(uncertain)
    if ledger and action == 'keep' and re.search(r'\.(onRequest|onResponse|onError)\b', text):
        change('C1', '旧拦截器入口改为 setup/handle；通过新客户端验证同一行为，结果读取 R。')
    return action, sorted(set(codes), key=lambda c: int(c[1:])), reason, doubt


def target_file(old_file, text, api, layer=None):
    """按最低可证明层安排新文件，真实回环超时迁 integration。"""
    if old_file:
        layer = old_file.split('/')[1]
        name = Path(old_file).name
        if 'timeout_effective' in name or 'auth_transport' in name or 'keep_alive' in name:
            layer = 'integration'
        if 'normalize' in name and layer in ('unit', 'rule', 'boundary'):
            layer, name = 'unit', 'response_test.dart'
        if name.startswith(('extra_', 'plugin_order', 'plugin_contract')):
            name = 'pipeline_test.dart' if 'extra_' not in name else 'context_test.dart'
        if name == 'exception_test.dart':
            name = 'response_test.dart'
        if name == 'replay_support_test.dart':
            name = 'context_test.dart'
        if name == 'request_claims_test.dart':
            name = 'pipeline_test.dart'
        name = name.replace('mock_adapter', 'mock')
    else:
        topic = re.sub(r'^Dioman', '', api.split('.')[0]).lower()
        if api.startswith(('Envelope', 'DiomanResponse')):
            layer, topic = 'unit', 'response'
        elif api.startswith(('StateKey', 'DiomanContext', 'DiomanKeyOptions')):
            layer, topic = 'unit', 'context'
        elif api.startswith(('DiomanStage', 'DiomanPlugin', 'Dioman.inspect')):
            layer, topic = 'unit', 'pipeline'
        elif api.startswith('Dioman.') or api == 'Dioman':
            layer, topic = 'integration', 'client'
        else:
            layer = layer or 'rule'
        topic = re.sub(r'[^a-z_]', '', topic) or 'client'
        name = topic + ('_test.dart' if layer == 'unit' else f'_{layer}_test.dart')
    return layer, f'test/{layer}/{name}'


def build():
    """生成完整的机器清单，随后渲染逐层 Markdown。"""
    tests = runtime_tests()
    rows = json.loads(MATRIX.read_text(encoding='utf-8'))
    output = {'tests': [], 'matrix': []}
    for index, test in enumerate(tests, 1):
        title, file = test['title'], test['file']
        ids = [x.strip() for chunk in re.findall(r'\[([^\]]+)\]', title) for x in chunk.split('×')]
        new_ids = list(dict.fromkeys(api_target(x) for x in ids)) or ['accept.executor']
        action, codes, reason, doubt = classify(title, file)
        layer, location = target_file(file, title, new_ids[0])
        output['tests'].append(dict(test, key=f'T{index:04}', layer=layer, action=action,
                                    codes=codes, reason=reason, doubt=doubt, new_api=new_ids, location=location))
    for row in rows:
        text = row['id'] + ' | ' + row['capability']
        action, codes, reason, doubt = classify(text, ledger=True)
        new_api = api_target(row['id'])
        if row['id'].startswith('INV-'):
            inv = int(row['id'][4:])
            if inv in (4, 6):
                action, codes, reason = 'drop', ['C5'], '删除 extra 注册表/重复键机制；由 StateKey 和 setup 隔离替代。'
            elif inv in (1, 2, 3, 22):
                action, codes, reason = 'change', ['C1', 'C4'], '按固定阶段与客户端 use/eject/dispose 重建装配不变量。'
            elif inv in (12, 13, 14, 15, 16, 17, 20, 21, 24):
                action, codes, reason = 'change', ['C1', 'C2', 'C8'], '按新逻辑请求/尝试边界重建不变量；缓存命中也经 outer，失败由 R 落定。'
            elif inv in (5, 7, 8, 10, 11):
                action, codes, reason = 'change', ['C1', 'C3', 'C7'], '按新客户端、内核服务与 source mock 重建插件集合/在途记账断言；旧插件计数和 extra 残留不再适用。'
        layer, location = target_file('', text, new_api, 'combo' if row['id'].startswith('INV-') else None)
        if row['id'].startswith('INV-'):
            layer = 'integration' if row['id'] in ('INV-01', 'INV-02', 'INV-03', 'INV-22', 'INV-23', 'INV-24', 'INV-26') else 'combo'
            location = f'test/{layer}/invariants_{layer}_test.dart'
        if '#effective' in row['id'] or '#transport' in row['id'] or '#real-' in row['id']:
            layer, location = 'integration', 'test/integration/transport_integration_test.dart'
        output['matrix'].append({'key': row['id'], 'capability': row['capability'], 'layer': layer,
                                 'action': action, 'codes': codes, 'reason': reason, 'doubt': doubt,
                                 'new_api': [new_api], 'location': location})
    MANIFEST.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    render(output)


def counts(rows):
    """按三种互斥判定计数，存疑是其中的附加标记。"""
    counter = collections.Counter(row['action'] for row in rows)
    return [len(rows), *(counter[a] for a in DECISIONS), sum(bool(row['doubt']) for row in rows)]


def escape(value):
    """保持标题原文并转义 Markdown 表格分隔符。"""
    return str(value).replace('|', '&#124;').replace('\n', '<br>').replace('\r', '')


def render(data):
    """输出五层明细及包含完整存疑行的总表。"""
    for layer in LAYERS:
        lines = [f'# dioman 洋葱管线迁移：{layer}', '',
                 'keep 保留行为并按新 API 重写；change 有意变化；drop 删除旧机制，替代位置仍保留供追踪。',
                 '按**预计新层**分组；旧路径和完整运行时标题逐条保存。存疑项的判定是暂定值，不等于已获终审批准。', '']
        for kind, caption in [('tests', '旧用例'), ('matrix', '旧总账')]:
            rows = [r for r in data[kind] if r['layer'] == layer]
            lines += [f'## {caption}（{len(rows)}）', '', '| 身份 | 旧文件＋完整标题 / 能力 | 判定 | C 编号 | 新 API id | 预计新位置 | 理由 / 存疑 |', '|---|---|---|---|---|---|---|']
            for row in rows:
                identity = f"{row['file']} :: {row['title']}" if kind == 'tests' else row['capability']
                cells = [row['key'], identity, row['action'], ', '.join(row['codes']) or '—', '; '.join(row['new_api']), row['location'], row['reason'] + (' 【存疑】' + row['doubt'] if row['doubt'] else '')]
                lines.append('| ' + ' | '.join(map(escape, cells)) + ' |')
            lines += ['']
        (DEST / f'{layer}.md').write_text('\n'.join(lines), encoding='utf-8')
    lines = ['# dioman B0 旧行为迁移总表', '',
             '来源：`dart test test_legacy --reporter json` 的 testStart/testDone 事件（[原始事件](raw/legacy-tests.ndjson)），排除 loading、hidden、metadata.skip 与 testDone.skipped；每个参数化运行时标题单独一行。',
             '归档前路径由 `test_legacy/` 一一还原成 `test/`；默认排除 real 标签，不把未运行的外部服务测试计入本地总数。旧 powerset 的 32767 个内部循环是一个运行时 test，不虚增用例。',
             '总账源是未改动的 `test/accept/lib/matrix.json`，逐行以原 id 对账。预计位置按 `docs/guides/test-layers.md` 与 pipeline-test-plan §1 最低证明层安排；纯归一化进 unit，真实 IO 进 integration，多插件进 combo。',
             'API id 是 B1–B5 的预定命名；删除能力的 new_api/location 是替代能力，绝非承诺恢复被删接口。`Options` 的机械换键仍可 keep；只有协议、判定或可观察行为变化才 change。',
             '存疑为互斥分类上的附加标记，已计入 keep/change/drop，不能再加一次。B0 不替终审裁决。', '',
             '## 计数', '', '| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |', '|---|---:|---:|---:|---:|---:|']
    for kind in ('tests', 'matrix'):
        if kind == 'matrix':
            lines += ['| 来源 / 新层 | 旧总数 | keep | change | drop | 存疑（已含） |',
                      '|---|---:|---:|---:|---:|---:|']
        for layer in LAYERS:
            rows = [r for r in data[kind] if r['layer'] == layer]
            lines.append('| ' + f'{kind}/{layer} | ' + ' | '.join(map(str, counts(rows))) + ' |')
        total, keep, change, drop, doubt = counts(data[kind])
        lines += [f'| {kind}/合计 | {total} | {keep} | {change} | {drop} | {doubt} |', '',
                  f'`{kind}: 旧总数 {total} = keep {keep} + change {change} + drop {drop}`', '']
    lines += ['## 存疑行（逐项交终审）', '', '| 来源 / 身份 | 旧位置或能力 | 暂定 | 理由 |', '|---|---|---|---|']
    for kind in ('tests', 'matrix'):
        for row in data[kind]:
            if row['doubt']:
                old = row.get('file', '') + ' :: ' + row.get('title', row.get('capability', ''))
                lines.append('| ' + ' | '.join(map(escape, [kind + '/' + row['key'], old, row['action'], row['doubt']])) + ' |')
    lines += ['', '## 可复算', '', '```powershell', 'python tool/pipeline_migration.py generate', 'python tool/pipeline_migration.py verify', '```', '',
              'verify 同时核对事件身份全集、matrix id 全集、唯一性、互斥分类、change 的 C1–C12、drop 理由、新位置与 Markdown 行数，输出见报告。', '']
    (DEST / 'README.md').write_text('\n'.join(lines), encoding='utf-8')


def verify():
    """独立重新读取事件与总账，校验清单和渲染表格没有漏行。"""
    data = json.loads(MANIFEST.read_text(encoding='utf-8'))
    source_tests = collections.Counter((r['file'], r['title']) for r in runtime_tests())
    actual_tests = collections.Counter((r['file'], r['title']) for r in data['tests'])
    assert source_tests == actual_tests
    source_matrix = [r['id'] for r in json.loads(MATRIX.read_text(encoding='utf-8'))]
    assert collections.Counter(source_matrix) == collections.Counter(r['key'] for r in data['matrix'])
    for kind in ('tests', 'matrix'):
        rows = data[kind]
        assert len({r['key'] for r in rows}) == len(rows)
        for row in rows:
            assert row['action'] in DECISIONS
            assert row['layer'] in LAYERS
            assert row['location'].startswith('test/' + row['layer'] + '/')
            assert row['new_api'] and row['reason']
            if row['action'] == 'change':
                assert row['codes'] and all(re.fullmatch(r'C(?:[1-9]|1[0-2])', c) for c in row['codes'])
            markdown = (DEST / (row['layer'] + '.md')).read_text(encoding='utf-8')
            assert sum(line.startswith('| ' + escape(row['key']) + ' |')
                       for line in markdown.splitlines()) == 1
        total, keep, change, drop, doubt = counts(rows)
        assert total == keep + change + drop
        print(f'{kind}: {total} = {keep} keep + {change} change + {drop} drop; doubtful={doubt}; PASS')
    print('runtime identities / matrix ids / unique keys / C1-C12 / locations / Markdown rows: PASS')


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == 'generate':
        build()
    verify()
