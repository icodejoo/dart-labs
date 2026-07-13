import { defineConfig } from 'tsdown';

export default defineConfig({
  entry: { ffuzzy: 'src/ffuzzy-corpus.ts' },
  format: 'esm',
  dts: true,
  minify: true,
  outDir: 'dist',
  clean: false,
});
