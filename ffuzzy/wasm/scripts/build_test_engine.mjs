// 从当前源码构建独立测试引擎，不写入发布目录。
import { mkdirSync, readFileSync, readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';

if (!process.env.FFUZZY_TEST_ENGINE) {
  const output = '.test-engine/ffz.mjs';
  mkdirSync('.test-engine', { recursive: true });
  const ffi = readFileSync('../ffi/ffz_ffi.c', 'utf8');
  const symbols = [...ffi.matchAll(/^FFZ_API[^\n]*?\b(ffz_ffi_\w+)\(/gm)]
    .map(m => `_${m[1]}`).filter(s => s !== '_ffz_ffi_install_crash_handler');
  const sources = readdirSync('../src').filter(s => s.endsWith('.c')).map(s => `../src/${s}`);
  const args = ['-O2', '-std=c11', '-DFFZ_NO_THREADS', '-DFFZ_TRACK_ALLOC', '-I../include',
    '-sMODULARIZE=1', '-sEXPORT_ES6=1', '-sSINGLE_FILE=1', '-sENVIRONMENT=web,worker',
    '-sALLOW_MEMORY_GROWTH=1', '-sFILESYSTEM=0',
    `-sEXPORTED_FUNCTIONS=_malloc,_free,${symbols.join(',')}`,
    ...sources, '../ffi/ffz_ffi.c', '-o', output];
  // Windows 的编译器入口是批处理，参数仅由本脚本及仓库固定路径组成。
  const result = spawnSync('emcc', args, { stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.error) throw result.error;
  if (result.status !== 0) process.exit(result.status ?? 1);
}
