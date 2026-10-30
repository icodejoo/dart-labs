"""B2 迁移逐行对账；保留清单不改分类，验证每个目标用例实际存在。"""
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
NAMES = ['DiomanLoading', 'DiomanNotify', 'DiomanRepath', 'DiomanFilter', 'DiomanTimeout', 'DiomanEnvs', 'EnvRule', 'NetworkQuality']
CATALOG = []
for p in (ROOT / 'test').glob('**/*test.dart'):
    content = p.read_text(encoding='utf-8')
    for m in re.finditer(r"test\(\s*'([^']+)'", content):
        CATALOG.append((p.relative_to(ROOT).as_posix(), content[:m.start()].count('\n')+1, m.group(1)))

def target(needle):
    matches = [x for x in CATALOG if needle in x[2]]
    assert len(matches) == 1, (needle, matches)
    return matches[0]

def choose(file, number, row):
    identity = row.split('|')[1].strip()
    note = ''
    if file == 'combo.md':
        rules = {17:'credential 等待期间',46:'credential 等待期间',47:'取消与 source 短路',
            75:'取消与 source 短路',93:'多次 next 仅一个',94:'并发成功失败',95:'共享同一响应',
            96:'并发成功失败',97:'并发成功失败',107:'默认忽略成功'}
        needle = rules[number]
        note = '仅验证本批外层契约；auth/retry/cache/share 的真实装配由 B3/B4 接续。' if number != 107 else '改读最终归一化结果。'
    elif file == 'integration.md':
        if number == 90:
            needle = '档位补丁送达 adapter'
            note = '配置/归类已测；真实 SYN 黑洞计时留 B7 netem，不声称回环验证了连接超时。'
        elif number == 91: needle = '$mode 停顿'
        elif number == 92: needle = '发送缓冲阻塞'
        else: needle = {14:'$mode 停顿',15:'分块间隔小于',16:'$mode 停顿',17:'请求级收紧接收',18:'请求级放宽接收',19:'正常读取小',20:'发送缓冲阻塞'}[number]
    elif file == 'unit.md':
        needle = 'dispose 取消显示' if number == 173 else '六插件名称'
    elif file == 'boundary.md':
        needle = {57:'FormData、Stream',65:'显示前结束',66:'dispose 取消显示',67:'dispose 取消显示',68:'同回调并发聚合',77:'URL 只处理路径',78:'三语法',79:'URL 只处理路径',98:'缺档无补丁'}[number]
    else:
        if number == 245:
            needle = '六插件名称'
            note = '旧 keep 文字中“true 可点亮插件级 false”与规格 §0.2 冲突：按新规格总开关不允许请求重启。'
        elif any(x in row for x in ['.pluginName', '.name |', '.ordering', '.enabled |']) or number in [96,99,119,126,244]: needle = '六插件名称'
        elif 'DiomanEnvs' in row or 'EnvRule' in row:
            needle = '空地址、默认 json' if number in [93,97,98,373] else '首个命中、全部旧字段'
        elif 'DiomanFilter' in row:
            needle = '豁免并集' if any(x in row for x in ['ignoreKeys', 'ignoreValues','Options.predicate','Options.enabled']) else 'C9 剔除'
        elif 'DiomanLoading' in row:
            if 'activeCount' in identity or number in [123,124,402]: needle = '同回调并发聚合'
            elif 'delayClose' in identity or number == 121: needle = '新请求取消隐藏'
            elif 'delay' in identity or number == 122: needle = '显示前结束'
            elif number == 125: needle = '独占回调替代'
            elif any(x in identity for x in ['onError','onResponse']) or number == 120: needle = 'credential 等待期间'
            elif 'Options.enabled' in row: needle = '四种写法、字段继承与请求开关'
            else: needle = '同回调并发聚合'
        elif 'DiomanNotify' in row:
            needle = 'true 开启、自定义 stringify' if any(x in row for x in ['onRequest','onResponse']) else '默认忽略成功'
        elif 'DiomanRepath' in row:
            needle = '开关、字段继承、自定义模式' if 'Options.' in row else '三语法'
        elif 'DiomanTimeout' in row or 'NetworkQuality' in row:
            needle = '默认四档' if 'NetworkQuality' in row or number in [518,521] else '按档并集'
            if number == 242: needle = '请求级放宽接收'
        else: raise AssertionError((file,number,row))
    return target(needle), note

def run():
    output = ['| 迁移来源行 | 原 ID | 分类 | 新用例（文件:行 / 完整标题） | 范围说明 |', '|---|---|---|---|---|']
    counts = {}
    for p in sorted((ROOT/'docs/reference/pipeline-migration').glob('*.md')):
        for number, row in enumerate(p.read_text(encoding='utf-8').splitlines(),1):
            if not (any(x in row for x in NAMES) and ('| keep |' in row or '| change |' in row)): continue
            fields = row.split('|')
            destination, note = choose(p.name,number,row)
            path, line, title = destination
            counts[p.name] = counts.get(p.name,0)+1
            output.append(f'| [{p.name}:{number}](../reference/pipeline-migration/{p.name}#L{number}) | {fields[1].strip()} | {fields[3].strip()} | `{path}:{line}` — {title} | {note} |')
    print('\n'.join(output))
    print('\n逐行验证：'+str(counts)+f'；共 {sum(counts.values())} 行，每行目标测试唯一存在。')

if __name__ == '__main__': run()
