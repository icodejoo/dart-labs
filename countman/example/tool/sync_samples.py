"""从实际演示源码生成可复制代码，保持 CRLF，与 widget 测试共同防止漂移。"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1] / 'lib'
source = (root / 'demo_samples.dart').read_text(encoding='utf-8')
prelude = source[:source.index('// sample:')].strip()
samples = re.findall(r'// sample:([^\n]+)\n(.*?)// end-sample', source, re.S)
codes = {name.strip(): prelude + '\n\n' + body.strip() for name, body in samples}
codes['pomodoro'] = (root / 'pomodoro_plugin.dart').read_text(encoding='utf-8')
output = "/// 从实际运行源码生成；通过 python tool/sync_samples.py 更新。\n"
output += "const samplePrelude = r'''" + prelude + "''';\n\n"
output += "/// 完整且与实际组件一致的代码示例。\nconst sampleCode = <String, String>{\n"
for name, code in codes.items():
    output += "  '" + name + "': r'''" + code + "''',\n"
output += "};\n\n"
output += "/// 合并同一分区的示例，导入与共用常量只保留一份。\n"
output += "String combineSampleCode(List<String> ids) => '$samplePrelude\\n\\n${ids.map((id) => sampleCode[id]!.replaceFirst(samplePrelude, \"\").trim()).join(\"\\n\\n\")}';\n"
(root / 'sample_code.dart').write_bytes(output.replace('\n', '\r\n').encode('utf-8'))