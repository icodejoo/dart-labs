import { defineConfig } from 'tsdown';
import { resolve } from 'node:path';

const testEngine = process.env.FFUZZY_TEST_ENGINE ??
  (process.env.npm_lifecycle_event === 'test' ? resolve('.test-engine/ffz.mjs') : undefined);

export default defineConfig({
  // Chrome 集成测试使用此路径替换引擎，避免覆盖已发布产物。
  alias: testEngine ? { './ffz.mjs': testEngine } : {},
  entry: { ffuzzy: 'src/ffuzzy-corpus.ts' },
  format: 'esm',
  dts: true,
  minify: true,
  outDir: 'dist',
  clean: true,
});
