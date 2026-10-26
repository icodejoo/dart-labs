import assert from 'node:assert/strict';
import { test } from 'node:test';
import { FuzzyCorpus, FuzzyKey, ffuzzyInitialize, autoMaxDistance } from '../.test-dist/ffuzzy.mjs';

const ITEMS = ['alpha', 'beta', 'gamma'];
const QUERY = 'hello';
const PRIMARY = '原始';
const ALIAS = '别名';
const INDICES = Array.from(QUERY, (_, i) => i);
const HIGHLIGHT = { highlight: true };
const FAILURE = new Error('回调失败');

// 初始化完成后不得复活已销毁的延迟语料库。
const disposed = FuzzyCorpus.strings(ITEMS);
disposed.dispose();
await ffuzzyInitialize();

test('延迟初始化不复活已销毁的语料库', () => {
  assert.equal(disposed.isReady, false);
  assert.throws(() => disposed.fuzzy(QUERY));
});

test('删除回调失败时保留原索引', () => {
  const c = FuzzyCorpus.strings(ITEMS);
  try {
    assert.throws(() => c.removeWhere(s => { if (s === ITEMS[1]) throw FAILURE; return true; }));
    assert.equal(c.length, ITEMS.length);
    for (const s of ITEMS) assert.equal(c.exact(s)[0]?.raw, s);
  } finally { c.dispose(); }
});

test('非整数索引被拒绝且不修改语料库', () => {
  const c = FuzzyCorpus.strings(ITEMS);
  try {
    for (const index of [NaN, 0.5, Infinity, -1]) {
      assert.throws(() => c.removeAt(index), RangeError);
      assert.throws(() => c.update(index, QUERY), RangeError);
    }
    assert.equal(c.length, ITEMS.length);
  } finally { c.dispose(); }
});

test('全部搜索模式使用别名键与归一化并支持高亮', () => {
  const c = FuzzyCorpus.strings([]);
  const display = 'display';
  c.addKey(display, [new FuzzyKey('café')]);
  try {
    for (const method of ['substring', 'prefix', 'postfix', 'exact']) {
      const hit = c[method]('cafe', HIGHLIGHT)[0];
      assert.equal(hit?.raw, display);
      assert.equal(hit.matchedKey, 1);
      assert.deepEqual(hit.indices, [0, 1, 2, 3]);
      assert.deepEqual(c[`${method}Raws`]('cafe', HIGHLIGHT), [display]);
    }
  } finally { c.dispose(); }
});

test('组合策略和编辑距离读取高亮', () => {
  const c = FuzzyCorpus.strings([QUERY]);
  try {
    for (const strategy of ['fuzzy', 'approx', 'merge', 'fallback']) {
      assert.deepEqual(c.search(QUERY, { strategy, ...HIGHLIGHT })[0].indices, INDICES);
      assert.deepEqual(c.search(QUERY, { strategy })[0].indices, []);
    }
    for (const hits of Object.values(c.dual(QUERY, HIGHLIGHT))) assert.deepEqual(hits[0].indices, INDICES);
  } finally { c.dispose(); }
});

test('自动距离按码点计数', () => {
  assert.equal(autoMaxDistance('😀😀'), 0);
  assert.equal(autoMaxDistance('😀😀😀'), 1);
  assert.equal(autoMaxDistance('😀😀😀😀😀'), 1);
});

test('临时缓冲区分配失败保留旧缓冲且释放新分配', () => {
  const c = FuzzyCorpus.strings(ITEMS);
  const M = c._M;
  const allocate = M._malloc;
  const free = M._free;
  const scratch = c._scratch;
  const scratch4 = c._scratch4;
  const allocated = new Set();
  let calls = 0;
  M._malloc = n => { if (++calls === 2) return 0; const p = allocate(n); allocated.add(p); return p; };
  M._free = p => { allocated.delete(p); free(p); };
  try {
    assert.throws(() => c._allocScratch(c._scratchCap * 2), /OOM/);
    assert.equal(allocated.size, 0);
    assert.equal(c._scratch, scratch);
    assert.equal(c._scratch4, scratch4);
    assert.equal(c.fuzzy(ITEMS[0])[0]?.raw, ITEMS[0]);
  } finally { M._malloc = allocate; M._free = free; c.dispose(); }
});

test('stringOf 中销毁后拒绝继续写入原生对象', () => {
  let dispose = false;
  let c;
  c = new FuzzyCorpus(ITEMS, { stringOf: s => { if (dispose) c.dispose(); return s; } });
  dispose = true;
  assert.throws(() => c.add(QUERY), /dispose/);
});


test('新增失败不提交半条目或错位索引', () => {
  for (const keyed of [false, true]) {
    for (let budget = 0; budget < 8; budget++) {
      const c = FuzzyCorpus.strings([]);
      const M = c._M;
      let committed = false;
      M._ffz_ffi_dbg_fail_after(budget);
      try {
        if (keyed) c.addKey(PRIMARY, [new FuzzyKey(ALIAS)]);
        else c.add(PRIMARY);
        committed = true;
      } catch (e) { assert.match(e.message, /OOM/); }
      finally { M._ffz_ffi_dbg_fail_after(-1); }
      try {
        if (budget === 0) assert.equal(committed, false);
        assert.equal(c.length, committed ? 1 : 0);
        c.add(QUERY);
        assert.equal(c.exact(QUERY)[0].index, committed ? 1 : 0);
        if (committed && keyed) assert.equal(c.exact(ALIAS)[0].raw, PRIMARY);
      } finally { c.dispose(); }
    }
  }
});

test('公共搜索统一拒绝非法距离及超限近似查询', () => {
  const c = FuzzyCorpus.strings([QUERY]);
  try {
    for (const distance of [-1, 11, 0.5, NaN, Infinity]) {
      for (const strategy of ['fuzzy', 'approx', 'merge', 'fallback']) {
        assert.throws(() => c.search(QUERY, { strategy, maxDistance: distance }), RangeError);
      }
      assert.throws(() => c.approx(QUERY, distance), RangeError);
      assert.throws(() => c.dual(QUERY, { maxDistance: distance }), RangeError);
    }
    const boundary = '😀'.repeat(64);
    c.add(boundary);
    assert.equal(c.approx(boundary, 0)[0].raw, boundary);
    const long = boundary + '😀';
    for (const strategy of ['approx', 'merge', 'fallback']) {
      assert.throws(() => c.search(long, { strategy }), RangeError);
    }
    assert.throws(() => c.approx(long), RangeError);
    assert.throws(() => c.dual(long), RangeError);
    c.add(long);
    assert.equal(c.exact(long)[0].raw, long);
  } finally { c.dispose(); }
});
