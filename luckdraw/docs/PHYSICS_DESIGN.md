---
title: 扭蛋机 / 大乐透可选物理碰撞模式设计
status: active
updated: 2026-11-13
summary: 为 capsule、lotto 增加默认关闭的内置圆形碰撞模拟（落入、球球碰撞、容器与拨杆刚体），结果与状态机语义保持不变
---

# 扭蛋机 / 大乐透可选物理碰撞模式设计

> 进度：**P0–P4 已完成**（P4 的真机数据与未达标项见 §9）。**P0–P3 已落地**（求解器、驱动抽象、扭蛋机与大乐透接入、拨杆绘制、减弱动效、示例开关；验收编号见 `test/ACCEPTANCE.md` 的 PHYS-01…PHYS-76）。**参数默认值未做主观调参冻结，沿用初值，等你体验后再定（§13）**。§5–§8 已按实测与落地事实更新，与初稿不同之处标注“实测”或“落地”。

## TL;DR

- 新增**可选**物理模式：`CapsuleOptions.physics` / `LottoOptions.physics`，默认 `null`，等于今天的参数化轨迹，行为、golden、测试全部不变。
- 不引入第三方依赖。球和容器都是圆，写一个约 300 行的专用圆形碰撞求解器（`LuckyCircleWorld`），放在 `core/kinematics/`，两个玩法共用。
- 开机时球从容器顶部落下，与容器壁、球与球、旋转拨杆碰撞；拨杆由现有 `swirlDeg`/`mix` 驱动，所以加速、匀速、减速语义原样复用。
- **结果仍然预先决定**。物理只负责“看起来真”：目标球由导引力推向出口，末段硬收敛到出口，之后沿现有运动学轨迹飞出。时间轴、事件、结果与另一模式逐帧等价。
- 需要改动 core 两处：`LuckyMotion` 加“模拟中”钩子（让 Ticker 在 idle 落定前也跑），玩法 motion 的搅拌器换成可替换的驱动抽象。
- 推翻了 ARCHITECTURE §1、§21.1 的“不引入物理引擎”，改为“不引入第三方物理引擎；内置专用求解器且默认关闭”。ADR 草案见 §2，待拍板后写入 ARCHITECTURE §18。

## 1. 目标与非目标

目标：

1. 开局球从容器顶部下落，与容器刚体碰撞、球间互相碰撞，最终堆在底部。
2. 搅拌期间被拨杆推动，球翻滚、碰撞、弹跳，自转角随接触摩擦变化。
3. 出球时目标球被推向出口，其余球因空位继续下沉填补。
4. 可选：默认关闭，开启不影响结果、状态机、事件顺序、总时长。

非目标：

- 不做通用物理引擎：只有圆（球/胶囊）、圆形容器、旋转线段拨杆，没有多边形、关节、连续碰撞检测。
- 不做 3D、粒子、音效、触感。
- 不保证跨平台逐位一致，只保证同平台、同帧间隔序列下逐位一致（理由见 §5.6）。
- 不改变抽奖概率与选奖逻辑（`PrizePicker`、`LottoSampler` 不动）。

## 2. 与既有决定的关系

| 既有决定 | 位置 | 本设计的处置 |
| --- | --- | --- |
| 不引入物理引擎，翻滚是确定性参数化轨迹 | §1 非目标、§21.1 | **部分推翻**：默认仍是参数化轨迹；新增可选内置求解器 |
| 不引入任何第三方运行时依赖 | §1 非目标 | 保持：自研求解器，pubspec 不变 |
| 带第三方依赖的 3D/物理后端拆独立包 | §6、ADR-01 | 不触发：无第三方依赖，不拆包 |
| 玩法只依赖 core，玩法互不依赖 | IMP-R2 | 保持：求解器在 core，两玩法各自接入 |
| 动态物体位置写入复用的 `Float64List`，帧内不分配 | §21.1 性能 | 保持：求解器所有缓冲构造时分配 |
| 空闲停 Ticker | §21.1 性能 | 需要扩展：物理未休眠时 idle 阶段也要 tick（§6.2） |

ADR 草案（拍板后写入 ARCHITECTURE §18，编号接 ADR-35）：

> **ADR-36 可选物理碰撞模式**。方案：A 自研圆形求解器 / B forge2d / C 独立包 `luckdraw_physics`。选 A：场景只有圆与圆形容器，通用刚体引擎的能力用不上；A 保住零依赖和同平台可复现；B 破坏零依赖，C 的隔离收益在无第三方依赖时很小。**推翻**：§1“不引入物理引擎”改为“不引入第三方物理引擎”。默认关闭，参数化轨迹继续是默认与基线。

## 3. 总体方案

```
CapsuleOptions.physics ─┐                 ┌─ LuckySwirlMixer      （现状，physics == null）
                        ├─ motion.configure ─┤
LottoOptions.physics ───┘                 └─ LuckyPhysicsDriver ── LuckyCircleWorld
                                                (core/kinematics，两玩法共用)
```

### 3.1 文件与依赖方向

| 文件（新增） | 内容 | 允许 import |
| --- | --- | --- |
| `core/kinematics/physics_options.dart` | `LuckyPhysics` 不可变参数（公共 API） | `dart:*`、`package:flutter/foundation.dart` |
| `core/kinematics/circle_world.dart` | `LuckyCircleWorld`：纯数值求解器，无 Flutter 依赖 | 仅 `dart:math`、`dart:typed_data` |
| `core/kinematics/body_driver.dart` | `LuckyBodyDriver` 抽象与两个实现（`LuckySwirlDriver` 包装现有 mixer、`LuckyPhysicsDriver` 包装 world） | core 内部 |

改动（既有文件）：`core/motion/motion.dart`（加 `isSimulating`）、`core/control/controller.dart`（`_syncClock`）、`capsule_motion.dart`、`lotto_motion.dart`（换驱动）、两个 painter（画拨杆、置顶被导引球）、两个 options（加 `physics` 字段）。`LuckySwirlMixer` 本身不改，现有测试与 `extend.dart` 导出不受影响。

`LuckyPhysics` 在 `luckdraw.dart` 导出（两个玩法共用的 core 类型）。`LuckyCircleWorld` v1 不导出，需要时再进 `extend.dart`。因为玩法 motion 会引用求解器，capsule/lotto 的产物里会带上这几百行代码；wheel/grid/slot 单玩法入口不受影响，用摇树探针验证（§10）。

## 4. 公共 API

```dart
/// 物理碰撞模式参数；传给 `CapsuleOptions.physics` / `LottoOptions.physics` 即开启。
@immutable
final class LuckyPhysics {
  const LuckyPhysics({
    this.gravity = 9,            // 容器半径/秒²，屏幕向下
    this.restitution = 0.3,      // 球-球、球-壁恢复系数 0..1
    this.friction = 0.25,        // 库仑摩擦，驱动自转
    this.linearDamping = 0.2,    // 1/秒，防永动
    this.stirArms = 2,           // 拨杆数量，0 表示无拨杆（只有落入与堆叠）
    this.stirRatio = 0.3,        // 拨杆角 = swirlDeg × stirRatio
    this.dropIn = true,          // 首次布局与 reset 后球从顶部落入
    this.guideLead = const Duration(milliseconds: 350),
    this.seed = 1,               // 初始落入位置的确定性抖动种子
    this.maxBodies = 128,        // 超出则整体回退参数化轨迹
    this.reduceMotion = LuckyPhysicsReduceMotion.system,
  });
  // copyWith / == / hashCode 与 LottoOptions 同款
}
```

用法：

```dart
LuckyLotto(config: LottoConfig.superLotto().copyWith(
    options: const LottoOptions(physics: LuckyPhysics())));

LuckyCapsuleMachine(config: CapsuleConfig(prizes: prizes,
    options: const CapsuleOptions(physics: LuckyPhysics(stirArms: 3))));
```

所有数值是初值，需真机调参后冻结。`reduceMotion` 沿用 grid 的 `system / always / never` 语义：系统要求减弱动效时整体回退参数化轨迹（落地时看是抽到 core 共用还是各玩法一份，实现细节）。

## 5. 求解器 `LuckyCircleWorld`

### 5.1 坐标与单位

- 内部用**归一化坐标**：容器半径 = 1，时间单位秒。布局缩放（旋转屏、窗口变化）只改写出时的乘数，不需要重建世界。
- 球半径比 `r = ballRadius / containerRadius` 由布局传入。同一玩法内半径相同（现有布局也是统一半径）。
- 重力 `(0, +g)`，屏幕向下。

### 5.2 数据布局

构造时一次性分配，帧内零分配：`px, py, vx, vy, angle, omega`（`Float64List`）、`active`（`Uint8List`，被导引出场或已移出为 0）、`guideX/guideY/guideT0/guideT1`（导引目标与窗口）。写出缓冲 `x, y, angle` 是对外缓冲，沿用现有 frame 复用约定（motion 把 `frame.x/y/angle` 指向它们）。

### 5.3 一个子步

半隐式欧拉 + 顺序冲量，迭代 4 次：

1. 积分：`v += g·dt`，施加线性阻尼与导引力（§7），`p += v·dt`。P0 实测补两项阻尼：自转额外阻尼 2/s（啮合的球否则会长期空转），速度低于 0.3 R/s 时额外阻尼 6/s（让压实中的堆更快静止）。
2. 球-球：圆心距 `< 2r` 时沿法线施加冲量（恢复系数 e），再施加切向摩擦冲量（同时改变 `omega`，圆惯量 ½mr²）。
3. 球-容器壁：`|p| > 1 − r` 时沿径向向内反弹，同样带摩擦。
4. 球-拨杆：拨杆是绕圆心旋转的线段（半宽 0.35r 的胶囊）。取球心到线段最近点，相对速度要加上拨杆表面速度 `ω_arm × 径向矩`，只用较低的恢复系数。
5. 位置修正：对残余穿透做 80% 投影、容忍 0.5% r，避免堆叠抖动。

P0 实测：4 次迭代时 35 球堆叠压缩到 31% 球半径且不休眠，所以速度迭代取 10、位置修正 4 遍，稳态重叠降到 3.3% 球半径（12 球为 0.95%）。球-球检测 v1 用朴素 O(n²)，带平方距离提前剔除。n ≤ 128 时每子步 ≤ 约 8k 次配对，可接受；超出 `maxBodies` 整体回退参数化轨迹，不做半吊子。均匀网格是将来 n 变大时的备选，不在 v1。

### 5.4 子步数与防穿透

每帧 `dt` 先被 `maxFrameDelta` 钳制（现有机制）。子步数 `n = clamp(ceil(dt / (1/120 s)), 1, 8)`，等分，不做累加器和插值：渲染位置就是最后一个子步的状态，没有插值延迟。

拨杆尖端每子步位移必须小于 `0.5r`，否则会穿过球。因此 `n` 同时满足 `n ≥ ceil(tipTravel / (0.5r))`；达到上限 8 仍超过时，钳制拨杆角速度。以 lotto 默认 `motion.speed=12°/帧`、`stirRatio=0.3` 估算：拨杆角每帧 3.6°，尖端（臂长约 0.9 容器半径）每帧约 0.057 容器半径，与 `0.5r`（`ballRadiusFactor=0.11` 时约 0.055）相当，默认值约需 1–2 子步；调大 `stirRatio` 或 `motion.speed` 时靠这条规则自动加子步。

### 5.5 休眠

没有外力驱动（拨杆在转或有导引球）且**整帧实际位移**低于 0.05 R/s、转角位移同样很小，持续 0.25 秒，进入休眠：停止积分、速度清零、`awake=false`，不再消耗 CPU。外部事件（`place`、拨杆转动、导引、移出、`reset`）重新唤醒。

P0 实测：判据不能用瞬时速度。深堆叠里每个子步重力加速度被接触抵消，球不动但速度恒不为零，会永远不休眠，所以改按位移判定。

- 容量边界：`radius ≤ 0.5`。35 球一池（`superLotto` 前区）约 4.8 秒休眠；填充率过高（例如 60 球、r=0.11）会长期不休眠且重叠达 13% 球半径，超出设计场景，由 `maxBodies` 与布局的球半径比例共同约束。

### 5.6 确定性边界

- 初始落入位置由 `seed` 生成的确定性抖动网格得到，求解过程不再用随机数。
- 相同平台、相同初始状态、相同 `dt` 序列（例如 `ManualLuckyClock`）下，每帧缓冲逐位一致。
- 不承诺跨平台逐位一致：`sin/cos` 在 VM 与 JS 的末位可能不同，混沌系统会放大。因此物理轨迹**不做 golden 像素对比**，用性质断言（§10）；仅在 VM 上保留少量位级快照。
- 运行时的 `dt` 来自真实帧间隔，两次运行不会逐位相同，这是预期，不影响结果（结果与物理无关）。

## 6. 与 motion 的集成

### 6.1 驱动抽象

```dart
abstract interface class LuckyBodyDriver {
  Float64List get x; Float64List get y; Float64List get angle; // 相对容器圆心
  /// 推进到当前帧；kinematic 实现忽略 dtMs
  void advance(double dtMs, double swirlDeg, double mix, List<bool> excluded);
  bool get isAwake;
  void reset();
}
```

`LuckySwirlDriver` 把现有 `LuckySwirlMixer.update` 包一层（`isAwake` 恒为 false）；`LuckyPhysicsDriver` 持有 world，`swirlDeg × stirRatio` 作为拨杆角，`mix` 作为拨杆转速占比。两个 motion 里 `_mixer`/`_mixers` 换成驱动，`_update()`/`_mix()` 改调 `advance`。布局变化时 physics 驱动按半径比例改写出缓冲，球半径比变化则触发一次重叠消解。

### 6.2 时钟：idle 阶段也要 tick

`_syncClock` 现在只有 `motion.phase.isMoving` 为真才开 Ticker；`tick()` 也在 `!isMoving` 时直接返回。物理模式有两种“相位是 idle 但球还在动”的情况：开机落入、`reset` 后重新落入。

- `LuckyMotion` 新增 `bool get isSimulating => false;`，physics 驱动存在且 `isAwake` 时返回 true。
- `_syncClock` 条件改为 `motion.phase.isMoving || motion.isSimulating`（仍受 `_timeline.isPaused` 约束）。
- 两个 motion 的 `tick` 守卫改为 `!phase.isMoving && !isSimulating` 才提前返回；idle 下的 tick 只推进物理，不触发相位事件。
- 落地：`LuckyController.configure` 在应用配置后调用 `_syncClock`（挂接时 motion 还没配置，不能只靠 `attach`），让落入动画能在没有用户操作时自启动；`tick` 末尾本来就会调用，所以休眠时自动停表。
- 休眠后 `isSimulating` 变 false，Ticker 停止，空闲零开销。

### 6.3 `reset`、`play()` 与重配

- `reset()`：物理模式下把所有球放回顶部落入初始位置并唤醒（`dropIn: false` 则直接放静止堆积位置并休眠）。
- **落地：`cancel()` 与 `reset()` 分开**。两个玩法原先 `cancel()` 直接调用 `reset()`；物理模式下作废时球应保持当前位置，所以拆成 `_resetState()`（只清状态）和 `reset()`（先让驱动重置再清状态），`cancel()` 走前者。
- **落地：结算后再次 `start()`**：大乐透已抽出的球在槽里，`start()` 只在 `settled` 阶段让驱动重置（球重新装填落入）；从 `idle` 开始不重置，避免静止的球被传送到顶部。扭蛋机的掉落胶囊只是取消移出标记，回到出口处。
- 落入过程中调用 `play()`：允许，拨杆直接开始转，不用等球落定。
- 配置变化：球数、球半径比或物理参数变了则重建世界；否则沿用世界并只改换算比例（`rescale`），缩放窗口不会让球重新落入。搅拌角回退（重置造成）时驱动调用 `resetStir`，拨杆不会倒转。

## 7. 结果不变量与“接管”

**硬性约束：物理只改变“球在容器里的位置与自转”，不改变相位序列、事件、结果、时长、`drawnCount`、落槽顺序。** 实现上靠两点：现有时间轴公式不改；物理只接管“球还在容器内”的那一段位置。

### 7.1 大乐透

现有流程：`stopWith(draw)` 后球 i 在 `decelerationMs + i × drawInterval` 起飞，前半程（progress < 0.5，默认 250ms）从当前位置直线到出口，后半程出口到结果槽。

物理模式：

1. **导引**：球 i 在起飞前 `min(guideLead, 0.5 × drawInterval)` 开始受弹簧阻尼导引加速度（刚度 120，约 0.7 倍临界阻尼），强度随窗口斜坡增强。**强度过半后该球变成幽灵**：不再与其他球、拨杆碰撞，只受容器壁约束，所以不会被挤偏或卡住；强度低于一半时仍是普通碰撞体，轻轻拉动。
   - P0 实测（35 球、随机目标）：初稿“导引球保持碰撞、真实挤开别的球”几乎到不了——静止堆里 0/60，搅拌中最多 8/40，球被邻球和扫过的拨杆挤到一边；加质量倍数、出口让位排斥力也没解决（竖直堆叠推不动）。幽灵方案两种场景都是 40/40，最慢 0.5 秒到位，终点误差 ≤ 0.004 容器半径。
   - 视觉上与旧版直线飞行“穿过其他球”等价（目标球本就是最上层绘制），取舍是放弃“真实挤开邻球”。
2. **硬收敛**：progress 落在 `[0.35, 0.5]` 时，位置按平滑步进混合到出口坐标，保证 progress = 0.5 时恰好在出口。幽灵方案下它是兜底而不是常态。
3. **移出**：progress ≥ 0.5 后该球从世界移除（`active = 0`），按现有运动学路径飞向槽位；其余球在重力下填补空位。
4. 现有 `_fromX/_fromY`（起飞瞬间位置）继续使用，因此“硬收敛”只是把前半程起点换成物理位置。

时间轴不受影响：硬收敛保证 progress = 0.5 时目标球在出口；§10 的随机种子测试证明“导引到位 + 其余球不越界”。

### 7.2 扭蛋机

现有流程：`stop()` 时在目标奖品色的胶囊里选“静止位置离出口最近”的一个，搅拌减速，再沿折线掉落。

物理模式：

- 落地参数：减速时长过半时锁定当前离出口最近的目标色胶囊，导引强度在减速时长的 35% 内升到一；进入 `dropping` 时记录物理位置与折线起点的偏差，在掉落前 15% 进度内线性消除，位置不跳变。
- 目标奖品色已知，但**具体哪个胶囊**推迟到搅拌减速结束时选，取目标色里当前活动位置离出口最近者。`droppedCapsule` 只在 `dropping` 之后才被 painter 使用（已核对 `capsule_painter.dart:320-335`），所以推迟不影响绘制。
- 为避免“选中时离出口太远”，减速窗口后 60% 对该奖品色中最近的候选施加导引（同样是强度过半变幽灵），窗口结束时选择仍按最近者，保证总能到位。
- 进入 `dropping` 时该胶囊移出世界，从当前物理位置起沿 `dropPath` 掉落；位置与 `dropPath[0]`（出口）的偏差在掉落前 10% 进度内线性混合消除，其余胶囊因重力下沉。
- **等价性**：结果奖品由 `PrizePicker` 先定，与物理无关；两模式的 `droppedCapsule` 下标可以不同，但被取出的胶囊必是目标奖品色。

## 8. 渲染改动

- 落地的帧字段：`CapsuleFrame` 新增 `stirDeg`（拨杆角，度）、`physical`（是否真在物理模拟，超过 `maxBodies` 回退时为假）、`guided`（被导引、将要出球的胶囊下标）；`LottoFrame` 新增 `stirDeg`（各池拨杆角）、`physical`（各池标志）。painter 只在 `physical` 为真时画拨杆。
- 球本体绘制不变（Picture 缓存的球/胶囊 sprite，按 `x/y/angle` 变换回放，帧内不 `saveLayer`）。
- 拨杆：由 `LuckyStirArms`（`core/render/stir_arms.dart`）绘制，几何常量与物理世界共用（`kLuckyStir*`）。实测修正：拨杆角取驱动给出的真实角度 `stirDeg`（碰撞用的角度），而不是 `swirlDeg × stirRatio`，二者在角速度被钳制时会不一致；半宽随啮合度缩放、透明度随之淡入淡出，用复用的 `Paint` 改颜色而不是 `saveLayer`。绘制在球层下方。
- 被导引球置顶：大乐透 painter 本来就先画 `slotOf < 0` 的球再画 `slotOf >= 0` 的球，所以不需要新增缓冲——物理模式让被导引的球在起飞前就被标记 `slotOf`，自然排到上层（参数化模式的标记时机不变）。扭蛋机用 `frame.guided` 让该胶囊在其他胶囊之后绘制。
- `capsule`/`lotto` 的 `LuckyLayer` 等扩展点不变。

## 9. 性能

- 桌面 AOT 粗测（`Stopwatch`、60Hz、拨杆全啮合）：35 球一池 89 µs/帧，邻近对列表优化后 24 µs/帧。**这个数字对手机没有预测力**：手机上慢了一到两个数量级，见下。

### 真机 A/B 实测（P4，vivo V2417 / Android 16，profile，`LUCKDRAW_TIMELINE`）

同包对照参数化（`capsule_mixing` / `lotto_draw`）与物理（`capsule_physics` / `lotto_physics`）。`luckdraw.physics.step` 是驱动里单次推进的耗时。原始汇总：`docs/device/physics_ab/`；复现：`tool/bench/run_perf.ps1`（每次一个变体）+ `tool/bench/summarize_physics_ab.py`。

| 场景 | 轮数 | UI 均值 / P99 ms | Raster 均值 / P99 ms | 物理步均值 / P99 / 最大 ms |
| --- | --- | --- | --- | --- |
| capsule 参数化（30 胶囊） | 3 | 1.80 / 3.33 | 3.97 / 5.09 | — |
| capsule 物理，优化前 | 3 | 4.40 / 8.39 | 5.86 / 17.63 | 2.40 / 5.56 / 6.58 |
| capsule 物理，优化后 | 3 | 2.83 / 5.25 | 4.72 / 8.90 | 0.85 / 1.78 / 2.21 |
| lotto 参数化（47 球） | 3 | 2.23 / 3.93 | 9.67 / 19.24 | — |
| lotto 物理，优化前 | 3 | 5.22 / 10.44 | 4.73 / 8.56 | 1.29 / 4.92 / 5.70 |
| lotto 物理，优化后 | 3 | 3.50 / 6.51 | 5.17 / 10.60 | 0.48 / 1.55 / 1.91 |

- 优化：每个子步只建一次邻近球对与靠近拨杆的球列表，速度与位置迭代只遍历列表，原先每次迭代都做 O(n²) 全对检测。物理步约快 3 倍。
- **结论（如实）**：优化后（每变体 3 个有效轮，中位数）物理模式相对参数化的 UI 均值增量约 +1.0ms（扭蛋机）和 +1.5ms（大乐透）；帧数未丢（301/301，580/579）。但 **UI P99 为 5.25 / 6.51ms，超过项目 4ms 的 UI 硬门禁**（参数化的 lotto 本来就是 3.93，贴着线）。物理是可选模式、默认关闭，所以不影响默认路径的既有结论，但**不能说物理模式通过了帧余量门禁**。
- 优化后样本已补满 3 轮；途中有几次设备侧超时或驱动连不上的无效轮，均保留在 runs.json，未替换。
- 试过把子步降到 60Hz，以及把迭代降到 6/2、8/3：堆叠残余重叠（≤5% 球半径）与机械能单调不增等质量测试都不再通过，已恢复为 120Hz、10 次速度迭代、4 遍位置修正。要继续压 P99 只能换思路（例如更细的候选过滤、减少球数、降低拨杆啮合时的子步），不能再靠砍迭代。
- 子步上限 8 与 `maxBodies = 128` 是最坏开销封顶。
- 休眠后零 CPU；idle 无 Ticker。
- 新增 trace 段 `luckdraw.physics.step`，沿用现有 `luckyTraceStart/End` 机制，真机时间线里能单独读到物理耗时。
- 现状提醒：lotto_draw 在 V2417 上帧余量门禁尚未通过（见 docs/README 与 METRIC_FIX_REPORT）。物理模式的验收看**同包 A/B 增量**（参数化 vs 物理，沿用 `tool/bench` 变体机制），不与既有硬门禁混为一谈，也不借此改写既有结论。

## 10. 测试与验收

按 TEST_STRATEGY 约定：新文件 `lib/` 行覆盖 100%（豁免须登记）、验收编号与真实测试名双向校验、`tool/check_imports.dart` 通过。

| 编号 | 断言 |
| --- | --- |
| PH-01 | 世界构造/复位后无 NaN/Inf，球全在容器内（`|p| ≤ 1 − r + ε`） |
| PH-02 | 无拨杆时自由落体：重力方向正确、最终休眠、稳态残余重叠 ≤ 1% r |
| PH-03 | 球-球碰撞：能量单调不增（有阻尼无拨杆）、动量方向合理（对称碰撞） |
| PH-04 | 摩擦产生自转：斜向接触后 `omega ≠ 0`，滚动方向与接触切向一致 |
| PH-05 | 拨杆推球：转速范围内无穿透（尖端位移 < 0.5r 的子步规则），球不进入拨杆内部 |
| PH-06 | 休眠与唤醒：低速持续后 `isAwake=false`；`reset`/导引/`mix>0` 唤醒 |
| PH-07 | 确定性：同种子、同 `dt` 序列，两次运行缓冲逐位相同 |
| PH-08 | 帧长鲁棒：`dt` = 8/16/33/100ms 序列均稳定，无爆炸（钳制生效） |
| PH-09 | 导引：搅拌中与静止堆两种场景、多个随机种子，导引球到达出口邻域，且全部球未越出容器（P0 为 12 个种子 × 2 场景；探索期曾跑 40 个种子 × 2 场景全部到位） |
| PH-10 | 容器缩放：缩放写出缓冲，球半径比变化触发重叠消解，无跳变 |
| PH-11 | 超出 `maxBodies` 整体回退参数化轨迹，且标志可读 |
| PH-12 | 模式等价（核心不变量）：同一脚本在 `ManualLuckyClock` 下，两模式的相位序列、事件、`drawnCount`、结果、总 tick 数完全相同；capsule 只比较奖品，不比较胶囊下标 |
| PH-13 | idle 落入：`dropIn` 下无用户操作也会 tick 到休眠后停表；休眠后 `isSimulating=false` |
| PH-14 | `physics: null` 时全部现有测试与 golden 不变（回归基线，以落地时的全量用例数为准） |
| PH-15 | widget：开启物理的 `LuckyLotto`/`LuckyCapsuleMachine` 跑完整一局，结果与 `stopWith` 的号码一致，`onEnd` 只触发一次 |
| PH-16 | 摇树：wheel/grid/slot 单入口产物不含求解器符号；capsule/lotto 含之；导入规则通过。**落地**：`check_treeshake.dart` 的受检符号加入 `LuckyCircleWorld`、`LuckyPhysicsDriver`、`LuckyStirArms`，仅 capsule/lotto/all_games 探针允许。Web 十探针物理模式首测：其余探针均无这些符号；capsule_only 增量 +4.55KB gzip（8.85→13.40KB），lotto_only +4.51KB，all_games +1.75KB，无关探针各 +37…+62B（`resolveConfig` 钩子）。**2026-11-13 用户决定**：依据 CI run `43264055196`，按实测×1.1 校准（向上取整）；实测低于现预算则保持原预算，不下调。Web 与 APK 分开处理，数值及范围见下表；`lots_only` 等源码、符号与体积关系检查不变。历史首测失败不改写，当前 CI 复验仍待执行。 |
| PH-17 | 真机（V2417，release/profile）：同包 A/B，参数化 vs 物理，读 `luckdraw.physics.step` 与帧时间增量；结果如实记录，不达标不改口径。**已执行，UI P99 未达 4ms 门禁，数据见 §9** |

物理轨迹不用 golden 像素，用性质断言；位级快照只在 VM 上少量保留（PH-07）。

### PH-16 预算校准（2026-11-13）

依据 [luckdraw CI run 43264055196](https://github.com/icodejoo/dart-labs/actions/runs/43264055196) 的两个 Probes 步骤；head `ee74a54f45675270da966293592b57006db37ed0`，Flutter 3.50.0。Web 使用 Dart `GZipCodec(level: 9)` 相对 baseline 的增量；APK 使用 arm64 analyze-size 的 luckdraw 包子树字节数，不能互换。

按实测×1.1 校准，使用整数算式 `(实测 × 11 + 9) ~/ 10` 精确向上取整；实测未超过现预算时保留原值。下表单位均为 bytes。

| 后端 | 探针 | CI 实测 | 旧预算 | 新预算 |
| --- | --- | ---: | ---: | ---: |
| WEB | baseline | 0 | 0 | 0 |
| WEB | wheel_only | 45711 | 48528 | 48528 |
| WEB | grid_only | 7479 | 6005 | 8227 |
| WEB | slot_only | 7854 | 7572 | 8640 |
| WEB | capsule_only | 13279 | 7408 | 14607 |
| WEB | number_wheel_only | 2939 | 2935 | 3233 |
| WEB | lots_only | 4652 | 4873 | 4873 |
| WEB | lotto_only | 10365 | 4859 | 11402 |
| WEB | compat_wheel | 26493 | 29653 | 29653 |
| WEB | all_games | 85984 | 83831 | 94583 |
| APK | baseline | 0 | 0 | 0 |
| APK | wheel_only | 68461 | 65181 | 75308 |
| APK | grid_only | 56957 | 53944 | 62653 |
| APK | slot_only | 65937 | 67401 | 67401 |
| APK | all_games | 275708 | 268143 | 303279 |

APK 其余五项未在本轮 CI 构建，预算不变。Web 的 GNU gzip 独立预算未在本轮 CI 测量，保持原值；历史实测报告和 `measured*` 字段保留，最新 CI 实测另存 `budgets.json` 的 `_ciCalibration`。`lots_only` 的预算及所有探针的源码、符号、体积关系规则不变。本地采用与 CI 相同修订的 Flutter 3.50.0（Windows）；APK 五探针命令在 baseline 的 Gradle 下载阶段因 Java 证书链错误（PKIX）失败，尚未进入预算检查，完整 CI 复验仍需后续运行。

本地验证（2026-11-13）：`dart run tool/treeshake/check_treeshake.dart --backend=web` 十探针全部通过，实测与本轮 CI 逐字节一致。`flutter test --no-pub --concurrency=4 --coverage --coverage-path=coverage/PH16-final.lcov --reporter json` 全量 1283 项通过；`dart run tool/coverage.dart --min=100 --lcov=coverage/PH16-final.lcov` 为 7768/7768（100%）；`flutter analyze --no-pub --no-fatal-infos` 通过（2 条既有 info）；`dart run tool/check_acceptance.dart --from-json build/PH16-final-test-run.json` 为 1735 引用、1308 登记测试全部映射。测试输出保存在 `build/PH16-final-test-run.json`，本次未新增覆盖率豁免。

## 11. 落地批次

当前状态：**P0–P3 已完成，P4 待做**。P1–P3 另外落地了设计初稿里没有的两件事：`LuckyGame.resolveConfig` 钩子（让宿主按 `MediaQuery.disableAnimations` 实现 `reduceMotion`，系统设置运行时变化也会重新配置）、示例页“物理碰撞（实验）”开关。

| 批 | 内容 | 产出 |
| --- | --- | --- |
| P0 | `LuckyCircleWorld` + `LuckyPhysics` + 全套单测（PH-01..11） | 纯数值、可独立评审，不接入任何玩法 |
| P1 | 驱动抽象 + `isSimulating` + capsule 接入 + PH-12/13/14 | 扭蛋机可开关，旧行为不变 |
| P2 | lotto 接入（导引、硬收敛、置顶）+ PH-09/15 | 大乐透可开关 |
| P3 | painter 拨杆、示例页切换开关、README/ARCHITECTURE/CHANGELOG 同步 | 可演示 |
| P4 | 真机 A/B 与调参冻结、摇树探针、验收矩阵登记（PH-16/17） | 数据与结论 |

每批合并前跑相关测试；P1 起必须保证 `physics: null` 的全量测试仍通过。

## 12. 风险

| 风险 | 缓解 |
| --- | --- |
| 手感不真（弹性、摩擦、拨杆速度） | 所有参数暴露在 `LuckyPhysics`；P4 真机调参后冻结默认值 |
| 目标球被卡住 | 导引加硬收敛，末段有界退化；PH-09 随机验证 |
| 性能超预算 | 球数上限与子步上限封顶；休眠；A/B 真机；超限回退 |
| 拨杆穿透 | 子步数由尖端位移推导，超限钳制角速度（PH-05） |
| Ticker 不停或不启动 | `isSimulating` 唯一入口，PH-13 覆盖休眠与自启动 |
| 与既有 `LottoFrame` 共享缓冲约定冲突 | 驱动对外仍是同一组 `Float64List`，frame 指向驱动缓冲，约定不变 |
| 混沌放大造成测试脆弱 | 不做物理 golden，只做性质断言与同平台位级快照 |

## 13. 已定默认与待拍板

以下按推荐默认推进，不反对即照此执行：

1. v1 搅拌器只做**旋转拨杆**；lotto 经典的“气流喷射”作为后续扩展，不在 v1。
2. `dropIn` 默认开启：首次布局与 `reset` 后落入。
3. `maxBodies = 128`，超出整体回退。
4. 物理模式下 `drawMix` 解释为拨杆转速占比，语义与现有一致。
5. `LuckyCircleWorld` v1 不对外导出。
6. 声音与触感不做。

需要你定的只有一项：

- **默认值调参由谁拍板**：P4 我用真机录像和 A/B 数据给出一组推荐默认值，你体验后确认；还是你想先指定“偏稳重”（弹性低、转速慢）或“偏热闹”（弹性高、转速快）的方向？

## 14. 被否决的方案

| 方案 | 否决原因 |
| --- | --- |
| forge2d（Box2D 移植） | 破坏零依赖；通用刚体能力用不上；跨平台浮点同样不保证一致 |
| 独立包 `luckdraw_physics` + forge2d | 隔离收益在无第三方依赖时很小，增加版本矩阵与发布成本；若将来要做真 3D 才值得拆（沿用 `luckdraw_3d` 设想） |
| 直接替换现有翻滚 | 破坏 golden、回放与既有测试的基线；默认关闭才安全 |
| 纯物理决定结果 | 与预先选奖冲突，破坏概率与 `stopWith(服务端号码)` 语义 |
| 累加器 + 渲染插值 | 增加状态与一帧延迟；本场景子步等分足够，且时间轴由 `ManualLuckyClock` 可控 |
| 均匀网格 broadphase | n ≤ 128 时朴素配对更简单更快；留作后续 |
