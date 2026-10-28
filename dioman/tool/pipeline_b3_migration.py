"""B3 迁移逐行定位；B4 真实装配依赖单列，不把局部边界算作整体通过。"""
from collections import Counter
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'docs/reports/pipeline-b3-evidence'
NAMES = ['DiomanAuth', 'DiomanRetry', 'DiomanBreaker', 'DiomanTokenManager', 'defaultAuthFailure']
CATALOG = []
for path in (ROOT / 'test').glob('**/*test.dart'):
    source = path.read_text(encoding='utf-8')
    for match in re.finditer(r"test\(\s*'([^']+)'", source):
        CATALOG.append((path.relative_to(ROOT).as_posix(), source[:match.start()].count('\n')+1, match.group(1)))


def target(needle):
    """每行必须对应唯一、确实存在的新测试标题。"""
    matches = [row for row in CATALOG if needle in row[2]]
    assert len(matches) == 1, (needle, matches)
    return matches[0]


def choose(file, number, row):
    """按来源行的具体 API 或行为选择承接用例，保留跨批范围说明。"""
    fields = row.split('|')
    identity, description = fields[1].strip(), fields[2]
    note = ''
    pending = file == 'combo.md' and any(x in description.lower() for x in ['diomanshare', 'diomancache', 'diomanmock', 'share +', 'share →', 'share+'])
    if pending:
        note = '已验证对应 B3 边界；share/cache/mock 真实组合依赖 B4，不宣称整体迁移通过。'
    if file == 'integration.md':
        needle = {10: '插入移除替换熔断器', 11: '同配置不同客户端刷新窗口隔离',
                  12: 'JSON FormData Stream', 13: 'JSON FormData Stream',
                  39: '插入移除替换熔断器', 40: '插入移除替换熔断器', 41: '插入移除替换熔断器',
                  55: 'JSON FormData Stream', 89: '真实 429 503'}[number]
    elif file == 'unit.md':
        needle = {108: '同配置不同客户端刷新窗口隔离', 110: '连续失败、冷却、半开成功',
                  111: '每次尝试计数，打开返回', 112: '默认键与请求覆盖只计算桶键',
                  113: '保存开启时请求冷却', 206: '插入移除替换熔断器'}[number]
        if number in (112, 113):
            note = '终审已裁决：旧 bucketKey 由 DiomanBreakerApi.keyOf(request) 承接；旧 retryableAt 由 retryableAt(key) 承接，保留开启时冷却快照且查询只读。'
    elif file == 'boundary.md':
        needle = {
            1:'并发主动刷新各轮一次', 2:'刷新窗口关闭后旧请求', 3:'刷新窗口关闭后旧请求',
            4:'并发主动刷新各轮一次', 5:'刷新后仍为 401 的并发请求', 6:'同步与异步抛错释放窗口',
            7:'internal cancel 不路由', 8:'自定义五动作', 9:'默认判定覆盖无 token',
            10:'buildHeader expiresAt 在首发和重放', 11:'旧请求的 expired',
            12:'JSON FormData Stream', 13:'JSON FormData Stream', 14:'旧请求的 expired',
            15:'同步与异步抛错释放窗口', 16:'同步与异步抛错释放窗口', 17:'旧请求的 expired',
            18:'同步与异步抛错释放窗口', 19:'同步与异步抛错释放窗口',
            24:'cancel 只归还名额', 25:'TTL 与软上限', 26:'TTL 与软上限',
            27:'真实取消探测释放槽位', 28:'open halfOpen 与 closed',
            29:'TTL 与软上限', 30:'TTL 与软上限', 31:'open halfOpen 与 closed', 32:'open halfOpen 与 closed',
            33:'真实取消探测释放槽位', 34:'真实取消探测释放槽位',
            35:'Dio 连接与三种超时', 36:'Dio 连接与三种超时', 37:'Dio 连接与三种超时', 38:'Dio 连接与三种超时',
            39:'真实取消探测释放槽位', 40:'通知异常隔离，判定与 keyBuilder',
            76:'类别硬否决先于回调', 77:'退避取消含订阅前', 78:'退避取消含订阅前',
            79:'通知抛错隔离并记日志', 80:'shouldRetry delay jitter 程序错误',
            81:'JSON FormData Stream', 82:'JSON FormData Stream',
        }[int(identity[1:])]
    elif file == 'combo.md':
        if 'T0104' in row:
            needle = '本地无凭证拒绝也释放'
        elif any(x in row for x in ['T0106', 'T0107']):
            needle = '重放等待时 cancelAll'
        elif 'T0186' in row:
            needle = '重试全过程 loading 一对'
        elif 'DiomanBreaker' in row:
            needle = '每次尝试计数，打开返回'
        elif any(x in row for x in ['DiomanAuth', 'defaultAuthFailure']):
            if any(x in description for x in ['回调抛', 'callback', 'buildHeader 抛', 'expiresAt 抛', 'isProtected 抛']):
                needle = 'buildHeader expiresAt 在首发和重放' if any(x in description for x in ['buildHeader', 'expiresAt']) else '通知同步异步抛错隔离'
            elif any(x in description for x in ['取消', 'cancelAll', 'cancel + auth']): needle = '发起者等待者取消和 cancelAll'
            elif 'DiomanRetry' in row: needle = '刷新不占重试预算'
            elif any(x in description for x in ['公开', '不受保护']): needle = '四种写法、请求覆盖、公开路径'
            elif '清掉 token' in description: needle = '本地无 token 每请求通知一次'
            else: needle = '两刷新轮各一次'
        elif 'DiomanRetry.onRetry' in row and '抛' in description: needle = '通知抛错隔离并记日志'
        elif 'shouldRetry' in row and '抛' in description: needle = 'shouldRetry delay jitter 程序错误'
        elif '取消' in description or 'cancel' in description: needle = '退避取消含订阅前'
        elif 'normalize' in description.lower(): needle = 'HTTP 与 business 逻辑状态全表'
        else: needle = '请求级关闭不恢复'
    elif 'DiomanBreaker' in row:
        if 'cancel' in row.lower() or '取消' in row: needle = 'cancel 只归还名额'
        elif 'onStateChange' in row: needle = '通知异常隔离，判定与 keyBuilder'
        elif any(x in row for x in ['generation', 'stale', '旧窗口', '在途']): needle = '真实取消探测释放槽位'
        elif any(x in row for x in ['idleTtl', 'maxBuckets']): needle = 'TTL 与软上限'
        elif any(x in row for x in ['defaultIdleTtl', 'defaultMaxBuckets']): needle = '默认回收一小时'
        elif 'reset' in identity and 'resetDuration' not in identity: needle = 'reset 之后旧请求'
        elif 'Options.' in row or any(x in row for x in ['.enabled', '.keyBuilder']): needle = '四种写法、继承覆盖、非法类型'
        elif any(x in row for x in ['.shouldTrip', 'network-classification']): needle = '默认类别与逻辑状态'
        else: needle = '连续失败、冷却、半开成功'
    elif 'DiomanAuth' in row or 'DiomanTokenManager' in row or 'defaultAuthFailure' in row:
        if 'defaultAuthFailure' in identity: needle = '默认判定覆盖无 token'
        elif any(x in row for x in ['FormData','Stream','multipart','transport','adapter','transformer','结构化请求体']): needle = 'JSON FormData Stream'
        elif identity == 'DiomanTokenManager.refreshToken': needle = 'auth 不直接读取刷新凭证'
        elif 'TokenManager' in identity and 'tokenManager' not in identity: needle = 'setTokens 与 clear'
        elif any(x in row for x in ['expiresAt','refreshLeeway','.new(now)']): needle = '主动刷新只一次'
        elif any(x in row for x in ['.headerKey','.buildHeader','new(headerKey)','new(buildHeader)']): needle = '自定义头和格式'
        elif identity == 'DiomanAuth.new(ready)': needle = '通知同步异步抛错隔离'
        elif 'Options.enabled' in identity: needle = 'true 强制保护优先'
        elif 'Options.onAccessExpired' in row: needle = '自定义头和格式'
        elif 'Options.' in row or any(x in row for x in ['.enabled','.isProtected','.ready']): needle = '四种写法、请求覆盖、公开路径'
        elif 'onRefresh' in identity: needle = '两刷新轮各一次'
        elif 'onAccessDenied' in identity or 'new(tokenManager)' in identity: needle = '本地无 token 每请求通知一次'
        elif 'cancel' in identity: needle = '发起者等待者取消和 cancelAll'
        elif 'onFailure' in identity or 'AuthFailureAction' in identity: needle = '自定义五动作'
        else: needle = '默认 Bearer 刷新重放一次'
    else:
        assert 'DiomanRetry' in row, (file,number,row)
        if any(x in row for x in ['FormData','Stream','adapter','transformer','绑定宿主','释放后']): needle = 'JSON FormData Stream'
        elif 'onRetry' in row: needle = '通知抛错隔离并记日志'
        elif 'Options.shouldRetry' in row or 'T0464' in row: needle = '请求判定覆盖插件判定'
        elif 'Options.' in row and any(x in row for x in ['delay','jitter','respectRetryAfter','retryAfterMax','afterStatusCodes']): needle = '逐字段生效'
        elif any(x in row for x in ['Retry-After','retryAfterMax','afterStatusCodes','respectRetryAfter']): needle = '秒数、空白、HTTP 日期'
        elif any(x in row for x in ['delayMax','jitter']): needle = '抖动正负、随机'
        elif 'network-type' in row or '网络失败' in row: needle = '类别硬否决先于回调'
        elif 'shouldRetry' in row or '.methods' in row: needle = '成功也交判定'
        elif any(x in row for x in ['.enabled','Options.','max']): needle = '四种写法、整数简写'
        else: needle = 'HTTP 与 business 逻辑状态全表'
    return target(needle), note, pending


def run():
    """输出完整 Markdown 与 JSON 账本，保留每条原行号。"""
    records = []
    for path in sorted((ROOT / 'docs/reference/pipeline-migration').glob('*.md')):
        for number, row in enumerate(path.read_text(encoding='utf-8').splitlines(),1):
            if not (any(name in row for name in NAMES) and ('| keep |' in row or '| change |' in row)):
                continue
            destination, note, pending = choose(path.name, number, row)
            records.append(dict(source=path.name,line=number,identity=row.split('|')[1].strip(),
                                classification=row.split('|')[3].strip(),test=destination[0],
                                test_line=destination[1],title=destination[2],note=note,b4_assembly_pending=pending))
    DEST.mkdir(parents=True,exist_ok=True)
    (DEST / 'migration.json').write_text(json.dumps(records,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    table = ['| 迁移来源行 | 原 ID | 分类 | 承接用例 | 范围说明 |','|---|---|---|---|---|']
    for r in records:
        table.append(f"| {r['source']}:{r['line']} | {r['identity']} | {r['classification']} | `{r['test']}:{r['test_line']}` — {r['title']} | {r['note']} |")
    (DEST / 'migration.md').write_text('\n'.join(table)+'\n',encoding='utf-8')
    print('逐行定位:',dict(Counter(r['source'] for r in records)))
    print('总行数:',len(records),'本批边界均有承接用例；其中 B4 真实装配待续:',sum(r['b4_assembly_pending'] for r in records))


if __name__ == '__main__':
    run()
