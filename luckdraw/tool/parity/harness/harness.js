'use strict';

/// 串行推进伪时钟，输出未修改 npm 产物的观测结果或明确错误。
(async function generateBaseline() {
  const FRAME_MS = 16;
  const out = document.getElementById('out');
  try {
    const spec = JSON.parse(document.getElementById('case').textContent);
    await document.fonts.load('400 14px Roboto');
    await document.fonts.ready;
    if (!document.fonts.check('400 14px Roboto')) throw Error('Roboto unavailable');

    let now = 0;
    let frame = 0;
    let randomCursor = 0;
    const queue = new Map();
    let requestId = 0;
    Date.now = () => now;
    window.requestAnimationFrame = callback => {
      queue.set(++requestId, callback);
      return requestId;
    };
    window.cancelAnimationFrame = id => queue.delete(id);
    // 序列耗尽必须报错，不能悄悄循环或退回不确定的原生随机数。
    Math.random = () => {
      if (randomCursor === spec.random.length) throw Error('Random sequence exhausted');
      return spec.random[randomCursor++];
    };

    const Constructor = {
      wheel: LuckyCanvas.LuckyWheel,
      grid: LuckyCanvas.LuckyGrid,
      slot: LuckyCanvas.SlotMachine,
    }[spec.game];
    const pendingImages = [];
    const originalLoad = Constructor.prototype.loadImg;
    Constructor.prototype.loadImg = function (...args) {
      const promise = originalLoad.apply(this, args);
      pendingImages.push(promise);
      return promise;
    };
    const events = [];
    const config = structuredClone(spec.config);
    config.width = spec.size.width;
    config.height = spec.size.height;
    let game;
    config.end = result => events.push({
      frame, timeMs: now, result: result === undefined ? null : result,
      resultIndex: result === undefined ? null : game.prizes.indexOf(result),
    });
    game = new Constructor({ el: '#game', dpr: spec.dpr }, config);
    // 上游 afterInit 可能早于全部图片；直接等待每一个真实 loadImg promise。
    await Promise.all(pendingImages);
    await Promise.resolve();
    await Promise.resolve();
    Constructor.prototype.loadImg = originalLoad;
    if (queue.size) throw Error('Unexpected rAF during initialization');
    game.draw();
    game.draw();

    /// 返回运动快照；上游 run(0) 的 0/0 FPS 显式记为 null。
    function snapshot() {
      const state = { frame, timeMs: now, step: game.step,
        fps: Number.isFinite(game.FPS) ? game.FPS : null,
        prizeFlag: game.prizeFlag === undefined ? null : game.prizeFlag };
      if (spec.game === 'wheel') Object.assign(state, {
        rotateDeg: game.rotateDeg, stopDeg: game.stopDeg, endDeg: game.endDeg,
      });
      if (spec.game === 'grid') Object.assign(state, {
        currIndex: game.currIndex, stopIndex: game.stopIndex, endIndex: game.endIndex,
      });
      if (spec.game === 'slot') Object.assign(state, {
        scroll: [...game.scroll], stopScroll: [...game.stopScroll], endScroll: [...game.endScroll],
      });
      return structuredClone(state);
    }
    const initial = snapshot();
    const keyframes = {};
    /// 保存指定标签对应的 Canvas 像素与原始帧号。
    function capture(label) {
      keyframes[String(label)] = {
        frame, timeMs: now, png: game.config.canvasElement.toDataURL('image/png'),
      };
    }
    // 关键帧 0 专门表示开始前，数值帧 0 则表示 play() 同步 run(0) 后。
    if (spec.keyframes.includes(0)) capture(0);
    const frames = [];
    let settledFrame = null;
    let previous;
    for (frame = 0; frame < spec.frames; frame++) {
      now = frame * FRAME_MS;
      for (const action of spec.script.filter(action => action.frame === frame)) {
        if (action.action === 'play') game.play();
        else if (Object.hasOwn(action, 'index')) game.stop(action.index);
        else game.stop();
      }
      // play 在第 0 帧已经同步 run(0)，此处不能再消费它刚排入的 rAF。
      if (frame > 0 && queue.size) {
        const [id, callback] = queue.entries().next().value;
        queue.delete(id);
        callback(now);
      }
      const state = snapshot();
      const value = spec.game === 'wheel' ? state.rotateDeg : state.currIndex;
      if (spec.game !== 'slot') {
        if (!Number.isFinite(value) || (previous !== undefined && value < previous)) {
          throw Error(`Non-monotonic upstream sequence at frame ${frame}`);
        }
        previous = value;
      } else if (!state.scroll.every(Number.isFinite)) {
        throw Error(`Non-finite upstream scroll at frame ${frame}`);
      }
      frames.push(state);
      if (frame > 0 && spec.keyframes.includes(frame)) capture(frame);
      if (settledFrame === null && game.step === 0) {
        settledFrame = frame;
        if (spec.keyframes.includes('settled')) capture('settled');
      }
    }
    if (settledFrame === null || queue.size) throw Error('Frame budget exhausted before completion');
    const cancelled = spec.script.some(action => action.index === -1);
    const expectedEnds = cancelled && spec.game === 'slot' ? 0 : 1;
    if (events.length !== expectedEnds) throw Error('Unexpected end callback count');
    out.textContent = JSON.stringify({
      id: spec.id, game: spec.game, frameMs: FRAME_MS, initial, frames,
      settledFrame, events, randomConsumed: randomCursor, keyframes,
    });
  } catch (error) {
    out.textContent = JSON.stringify({ error: String(error), stack: error.stack });
  }
})();
