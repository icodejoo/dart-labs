import { defineConfig } from 'tsdown';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC = 'src/ffuzzy-corpus.ts';
const DEFAULT_ENGINE = resolve(__dirname, 'src/ffz-fzf.mjs');

const variants = [
  { name: 'fzf',    engine: 'ffz-fzf.mjs' },
  { name: 'approx', engine: 'ffz-approx.mjs' },
  { name: 'full',   engine: 'ffz-full.mjs' },
] as const;

export default variants.map(({ name, engine }) =>
  defineConfig({
    entry: { [`ffuzzy-${name}`]: SRC },
    format: 'esm',
    dts: name === 'fzf',
    minify: true,
    outDir: 'dist',
    clean: false,
    alias: {
      [DEFAULT_ENGINE]: resolve(__dirname, 'src', engine),
    },
  }),
);
