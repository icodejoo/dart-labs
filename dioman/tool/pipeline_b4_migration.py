"""B4 按原行号核对 source keep/change，并独立关闭 B3 的 39 条组合承接。"""
from pathlib import Path
from collections import Counter
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b4-evidence'
CATALOG = []
for path in (ROOT / 'test').rglob('*test.dart'):
    source = path.read_text(encoding='utf-8')
    for match in re.finditer(r"test\(\s*'([^']+)'", source):
        CATALOG.append((path.relative_to(ROOT).as_posix(), source[:match.start()].count('\n') + 1, match.group(1)))


def target(needle):
    """定位唯一存在的测试，拒绝不存在、歧义或泛指文件。"""
    rows = [r for r in CATALOG if needle in r[2]]
    assert len(rows) == 1, (needle, rows)
    return rows[0]


def choose(file, number, row):
    """根据来源行的具体语义选择已有规则、边界或组合断言。"""
    if file == 'combo.md' and number in B3:
        return target(B3_TITLES[number])
    if file == 'integration.md':
        return target('四 source 安装禁用与固定位置')
    if any(w in row for w in ['namespace', 'sorted queryParameters', 'Map body']):
        return target('账号隔离和 prepare 后请求体区分')
    if 'cache_normalize' in row or 'INV-16' in row:
        return target('归一化判定表与请求级覆盖优先级' if any(w in row for w in ['shouldStore 优先级', '请求级覆盖插件级', '显式 shouldStore']) else '信封开关自定义成功和单层解包')
    if 'loading' in row.lower() and 'DiomanMock' not in row:
        return target('缓存命中和跟随者均计逻辑请求')
    if 'FormData' in row and 'DiomanShare' in row:
        return target('FormData 首发取消跟随者沿用传输')
    if 'normalize_share' in row:
        return target('FormData 首发取消跟随者沿用传输' if '只解一层' in row or '解一层' in row else '每次尝试重新进入，失败不缓存')
    if 'cache_offline' in row or 'INV-20' in row:
        return target('离线缓存命中照常返回')
    if 'cache_share' in row:
        return target('并发一次发送缓存一次')
    if any(w in row for w in ['share → auth', 'mock_adapter_combo']):
        if 'retry' in row.lower():
            return target('每次尝试探测回落且 I7')
        return target('探测不缓存不共享' if '回落' in row else '内联优先于 share 每个逻辑调用')
    if 'DiomanOffline' in row or 'offline_' in row:
        if any(w in row for w in ['queueFull', 'QueueSize', '队列满']):
            return target('队满挤出最早')
        if any(w in row for w in ['dispose', 'timeout', 'maxWait', '取消']):
            return target('timeout cancel flush dispose')
        if any(w in row for w in ['.name', '.ordering', '.pluginName', '.enabled']):
            return target('四 source 安装禁用与固定位置')
        return target('离线排队恢复和手动 flush')
    if 'DiomanMock' in row or 'mock_adapter' in row or 'defaultFallback' in row:
        if any(w in row for w in ['inline errors', '内联处理器抛']):
            return target('内联处理器异常原样抛出')
        if any(w in row for w in ['body', 'POST', 'transport error']):
            return target('每次尝试探测回落且 I7')
        if any(w in row for w in ['cancel', '取消', 'interrupted', 'close', '关闭']):
            return target('探测取消不回落不调用判定')
        if any(w in row for w in ['401', 'refresh']):
            return target(B3_TITLES[29])
        if '500 retries' in row:
            return target(B3_TITLES[102])
        if any(w in row for w in ['query', 'queryParameters']):
            return target('自审：path 内嵌')
        if any(w in row for w in ['抛', 'errors', 'error decisions', 'fallbackWhen', 'mockUrl', 'URL override', 'routes merge', 'Options.routes']):
            return target('请求级路由地址覆盖')
        if 'concurrent' in row:
            return target('内联优先于 share 每个逻辑调用')
        if any(w in row for w in ['memo', 'persist', 'both']):
            return target('探测不缓存不共享')
        if any(w in row for w in ['enabled', 'extraKey']):
            return target('四 source 安装禁用与固定位置')
        return target('默认生效，内联数据经工厂识别')
    if 'DiomanCache' in row or 'DiomanClone' in row or 'cache_' in row:
        if any(w in row for w in ['snapshot', 'first response', '深拷贝保留', 'deep clone isolates']):
            return target('写入快照隔离来源')
        if any(w in row for w in ['clone', 'Clone']):
            return target('deep 保留非字符串键隔离嵌套')
        if any(w in row for w in ['write failure', 'write and erases', 'write and erase', 'pending write', 'write failure', 'failure rejects', '.erase', '.write', '删除操作串行']):
            return target('clear 等待在途持久化写入后 erase')
        if 'expired entry cannot delete' in row:
            return target('旧过期慢读取不得删除较新写入')
        if 'maxEntries' in row or 'LRU' in row:
            return target('新结果淘汰后旧在途不得回写')
        if any(w in row for w in ['old read', 'pending reads', '旧读取', 'dispose', '.remove']):
            return target('慢读取被 clear remove dispose 作废')
        if '.clear' in row:
            return target('clear 作废在途写入')
        if any(w in row for w in ['.name', '.ordering', '.pluginName', '.enabled']):
            return target('四 source 安装禁用与固定位置')
        if any(w in row for w in ['.now', '(now)', '.expires', 'TTL']):
            return target('插件级 DiomanClock 控制 TTL')
        if 'canceled-response' in row:
            return target('取消的在途响应不缓存')
        if any(w in row for w in ['shouldCache', 'shouldStore']):
            return target('key false 方法否决与自定义方法' if 'shouldCache' in row else '归一化判定表与请求级覆盖优先级')
        return target('memo persist both 分层')
    if 'DiomanShare' in row or 'share_' in row or 'INV-15' in row:
        if any(w in row for w in ['dispose', '释放', 'cancelAll', '取消类错误']):
            return target('retry 间隔取消与耗尽释放条目')
        if any(w in row for w in ['首发取消', 'leader', '接手', 'cancelled', 'cancelling']):
            return target('首发取消不连累跟随者')
        if any(w in row for w in ['enabled', '.name', '.pluginName']):
            return target('四 source 安装禁用与固定位置')
        if 'retries' in row and '默认 3' in row:
            return target('默认内部重试三次')
        if any(w in row for w in ['retry', 'retries', 'interval']):
            return target('内部重放独立保护 I7 嵌套请求体')
        if any(w in row for w in ['end', 'race', 'LAST', 'LATEST', 'last', 'SUCCEED', 'settle()']):
            return target('end 最新失败归所有')
        return target('start 只发一次，跟随者为相同只读 R')
    raise AssertionError((file, number, row))


def note(row):
    """保留原分类，并记录新规格相对旧断言的适配，供终审逐行查阅。"""
    if 'DiomanCacheOptions.maxEntries' in row:
        return '§8.1 删除请求级占位；插件级容量与 LRU 仍保留。'
    if 'DiomanShare.settle' in row:
        return '删除手工结算，按 next 自然落定及随后同 key 重发验证；原 keep 的 setter 部分不再适用。'
    if 'now 抛异常' in row:
        return '请求级 now 删除；改用客户端时钟，回调 bug 原样落定与 source 状态清理仍验证。'
    if 'before' in row or 'ordering' in row or 'order' in row:
        return '固定 source 顺序 mock → share → cache → offline；不保留旧拦截器相对顺序。'
    if 'DiomanMockAdapter' in row:
        return 'C7：由 source mock/客户端生命周期承接；内联每逻辑请求运行，探测不共享不缓存。'
    if 'loading' in row.lower() or 'INV-20' in row:
        return 'C10：outer loading 覆盖缓存命中与所有跟随者；仅 offline 队列被缓存命中绕过。'
    if '认领' in row or 'settler' in row or 'registry' in row:
        return '删除认领登记簿，验证外层逻辑请求与共享活动表归零。'
    return '按归一化 R、类型化选项和固定阶段验证；原始描述见迁移清单。'


B3 = {r['line'] for r in json.loads((ROOT / 'docs/reports/pipeline-b3-evidence/migration.json').read_text(encoding='utf-8')) if r['b4_assembly_pending']}
assert len(B3) == 39
# 行号到行为标题的对应仅由证据账本维护。
B3_TITLES = {r['line']: r['title'] for r in json.loads(
    (DEST / 'migration.json').read_text(encoding='utf-8'))
    if r['b3_assembly']}
assert set(B3_TITLES) == B3
assert len(set(B3_TITLES.values())) == 39
for title in B3_TITLES.values():
    assert len([r for r in CATALOG if r[2] == title]) == 1, title



def run():
    """生成完整原行号账本与 39 行单独附录，无 pending 状态。"""
    records = []
    for path in sorted((ROOT / 'docs/reference/pipeline-migration').glob('*.md')):
        for number, row in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
            if not ('| keep |' in row or '| change |' in row):
                continue
            relevant = re.search(r'Dioman(Mock|Share|Cache|Offline|Clone)|defaultFallback|(?:mock_adapter|cache_|share_|offline_)', row)
            pending = path.name == 'combo.md' and number in B3
            if not (relevant or pending or (path.name == 'integration.md' and number == 84)):
                continue
            dest = choose(path.name, number, row)
            fields = row.split('|')
            records.append(dict(source=path.name, line=number, identity=fields[1].strip(), classification=fields[3].strip(), original_description=fields[2].strip(),
                                test=dest[0], test_line=dest[1], title=dest[2], note=note(row), b3_assembly=pending, status='closed'))
    assert sum(r['b3_assembly'] for r in records) == 39
    assert len(records) == 267
    DEST.mkdir(parents=True, exist_ok=True)
    (DEST / 'migration.json').write_text(json.dumps(records, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for name, data in [('migration', records), ('b3-39', [r for r in records if r['b3_assembly']])]:
        table = ['| 原来源行 | ID | 原分类 | 新用例 | 说明 |', '|---|---|---|---|---|']
        for r in data:
            table.append(f"| {r['source']}:{r['line']} | {r['identity']} | {r['classification']} | `{r['test']}:{r['test_line']}` — {r['title']} | {r['note']} |")
        (DEST / f'{name}.md').write_text('\n'.join(table) + '\n', encoding='utf-8')
    print(dict(Counter(r['source'] for r in records)))
    print(f'{len(records)} keep/change rows individually mapped; B3 39/39 closed')


if __name__ == '__main__':
    run()
