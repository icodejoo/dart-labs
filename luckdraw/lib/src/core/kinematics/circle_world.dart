import 'dart:math' as math;
import 'dart:typed_data';

/// 拨杆轮毂半径，单位为容器半径；绘制与物理世界共用。
const double kLuckyStirHubRadius = 0.15;

/// 拨杆长度，单位为容器半径；绘制与物理世界共用。
const double kLuckyStirArmLength = 0.92;

/// 拨杆完全啮合时的半宽，相对球半径；绘制与物理世界共用。
const double kLuckyStirArmHalfWidth = 0.35;

/// 子步目标时长，约一百二十赫兹。
const double _stepSeconds = 1 / 120;

/// 单帧最多子步数，封顶最坏开销。
const int _maxSubsteps = 8;

/// 每子步的速度求解迭代次数。
const int _iterations = 10;

/// 每子步的位置修正遍数，多遍让深堆叠的压缩向上传递。
const int _positionPasses = 4;

/// 拨杆尖端每子步位移上限，相对球半径。
const double _tipStep = 0.5;

/// 自转的额外阻尼（滚动阻力），单位每秒；啮合空转的球否则几乎不衰减。
const double _spinDamping = 2;

/// 低于该速度时启用低速阻尼，单位为容器半径每秒。
const double _slowSpeed = 0.3;

/// 低速阻尼，单位每秒；让压实中的堆更快静止。
const double _slowDamping = 6;

/// 邻近对列表的额外范围，相对球半径；覆盖位置修正造成的微小位移。
const double _contactSkin = 0.5;

/// 邻近对列表每球的容量上限；稠密堆里一个球最多同时接触约六个。
const int _pairsPerBall = 24;

/// 位置修正的穿透容忍，相对球半径。
const double _slop = 0.005;

/// 球与球位置修正比例。
const double _correction = 0.8;

/// 拨杆位置修正比例，较软以免推出时跳变。
const double _armCorrection = 0.2;

/// 拨杆单次位置修正上限，相对球半径。
const double _armCorrectionCap = 0.25;

/// 低于该法向速度的接触视为静止接触，不反弹。
const double _restThreshold = 0.3;

/// 拨杆恢复系数相对全局恢复系数的折减。
const double _armRestitution = 0.5;

/// 休眠速度阈值，单位为容器半径每秒。
const double _sleepSpeed = 0.05;

/// 持续低速多久后休眠，单位秒。
const double _sleepSeconds = 0.25;

/// 导引弹簧刚度。
const double _guideStiffness = 120;

/// 导引阻尼，约为临界阻尼的零点七倍。
const double _guideDamping = 15.3;

/// 导引强度达到该值后球变为幽灵：不再与其他球、拨杆碰撞，只受容器壁约束。
const double _ghostStrength = 0.5;

/// 落入阵列起始间距相对球直径的系数。
const double _dropSpacing = 1.04;

/// 落入阵列无法容纳时的间距收缩系数。
const double _dropShrink = 0.97;

/// 落入位置的抖动幅度，相对球半径。
const double _dropJitter = 0.03;

/// 零距离时的判定阈值。
const double _epsilon = 1e-12;

/// 静止堆积预演的最大子步数。
const int _settleSteps = 720;

/// 线性同余发生器的乘数。
const int _lcgMultiplier = 1664525;

/// 线性同余发生器的增量。
const int _lcgIncrement = 1013904223;

/// 线性同余发生器的取模掩码，三十二位。
const int _lcgMask = 0xFFFFFFFF;

/// 线性同余发生器值域大小，三十二位。
const double _lcgRange = 4294967296;

/// 圆形刚体世界：同半径的球在单位圆容器内下落、碰撞，可选旋转拨杆。
///
/// 长度单位为容器半径、时间单位为秒；重力向下（y 轴正向）。球之间、球与容器壁
/// 带恢复系数与库仑摩擦，摩擦驱动自转；拨杆是绕圆心旋转的线段，只在 `engaged`
/// 大于零时参与碰撞。所有缓冲在构造时分配，推进过程不分配。
///
/// 只依赖 `dart:math` 与 `dart:typed_data`，同平台、同初始状态、同帧间隔序列下逐位可复现。
///
/// ```dart
/// final world = LuckyCircleWorld(count: 20, radius: 0.1);
/// while (world.isAwake) {
///   world.advance(1 / 60, stirAngle: 0);
/// }
/// ```
final class LuckyCircleWorld {
  /// 创建世界并按 [dropIn] 摆放：真为顶部落入，假为直接堆积静止。
  ///
  /// [count] 须非负，[radius]（球半径与容器半径之比）须在零到零点五之间，
  /// 否则单个容器放不下球阵；[armCount] 为零表示没有拨杆。
  LuckyCircleWorld(
      {required this.count,
      required this.radius,
      this.gravity = 9,
      this.restitution = 0.3,
      this.friction = 0.25,
      this.linearDamping = 0.2,
      this.armCount = 2,
      this.seed = 1,
      bool dropIn = true})
      : assert(count >= 0),
        assert(radius > 0 && radius <= 0.5),
        x = Float64List(count),
        y = Float64List(count),
        angle = Float64List(count),
        _vx = Float64List(count),
        _vy = Float64List(count),
        _omega = Float64List(count),
        _active = Uint8List(count),
        _guideX = Float64List(count),
        _guideY = Float64List(count),
        _guideStrength = Float64List(count),
        _pairA = Int32List(
            math.min(count * (count - 1) ~/ 2, count * _pairsPerBall)),
        _pairB = Int32List(
            math.min(count * (count - 1) ~/ 2, count * _pairsPerBall)),
        _hitBall = Int32List(armCount * count),
        _hitArm = Int32List(armCount * count),
        _prevX = Float64List(count),
        _prevY = Float64List(count),
        _prevAngle = Float64List(count),
        _armCos = Float64List(armCount),
        _armSin = Float64List(armCount) {
    reset(dropIn: dropIn);
  }

  /// 球的数量。
  final int count;

  /// 球半径，单位为容器半径。
  final double radius;

  /// 重力加速度，单位为容器半径每二次方秒。
  final double gravity;

  /// 球与球、球与容器壁的恢复系数。
  final double restitution;

  /// 库仑摩擦系数。
  final double friction;

  /// 线性阻尼，单位每秒。
  final double linearDamping;

  /// 拨杆数量。
  final int armCount;

  /// 初始落入位置的抖动种子。
  final int seed;

  /// 球心横坐标，单位为容器半径，原点为容器圆心；与外部共享的复用缓冲。
  final Float64List x;

  /// 球心纵坐标，向下为正；与外部共享的复用缓冲。
  final Float64List y;

  /// 球自转角，单位弧度；与外部共享的复用缓冲。
  final Float64List angle;

  /// 横向速度。
  final Float64List _vx;

  /// 纵向速度。
  final Float64List _vy;

  /// 自转角速度。
  final Float64List _omega;

  /// 球是否参与模拟，一为参与。
  final Uint8List _active;

  /// 导引目标横坐标。
  final Float64List _guideX;

  /// 导引目标纵坐标。
  final Float64List _guideY;

  /// 导引强度，零表示不导引。
  final Float64List _guideStrength;

  /// 本帧开始时的横坐标，用于按实际位移判定休眠。
  final Float64List _prevX;

  /// 本帧开始时的纵坐标。
  final Float64List _prevY;

  /// 本帧开始时的自转角。
  final Float64List _prevAngle;

  /// 各拨杆方向的余弦。
  final Float64List _armCos;

  /// 各拨杆方向的正弦。
  final Float64List _armSin;

  /// 邻近球对的第一个球下标，每个子步重建。
  final Int32List _pairA;

  /// 邻近球对的第二个球下标。
  final Int32List _pairB;

  /// 邻近球对数量。
  int _pairCount = 0;

  /// 靠近拨杆的球下标，每个子步重建。
  final Int32List _hitBall;

  /// 靠近拨杆的拨杆下标，与 [_hitBall] 一一对应。
  final Int32List _hitArm;

  /// 靠近拨杆的球数。
  int _hitCount = 0;

  /// 拨杆当前角度，弧度。
  double _armAngle = 0;

  /// 拨杆当前角速度，弧度每秒。
  double _armOmega = 0;

  /// 上一次的拨杆指令角。
  double _lastCommand = 0;

  /// 是否已收到过拨杆指令。
  bool _hasCommand = false;

  /// 当前拨杆半宽，随啮合度缩放。
  double _halfWidth = 0;

  /// 是否有拨杆参与碰撞。
  bool _armsOn = false;

  /// 是否仍需推进。
  bool _awake = false;

  /// 已持续低速的时间。
  double _calm = 0;

  /// 随机数状态。
  int _rng = 0;

  /// 是否仍在运动；休眠后 [advance] 不再消耗计算。
  bool get isAwake => _awake;

  /// 拨杆当前角度，单位弧度。
  double get armAngle => _armAngle;

  /// 参与模拟的球的总动能（含自转），用于诊断与测试。
  double get energy {
    var sum = 0.0;
    for (var i = 0; i < count; i++) {
      if (_active[i] == 0) continue;
      sum += 0.5 * (_vx[i] * _vx[i] + _vy[i] * _vy[i]) +
          0.25 * radius * radius * _omega[i] * _omega[i];
    }
    return sum;
  }

  /// 球 [i] 是否参与模拟。
  bool isActive(int i) => _active[i] != 0;

  /// 重新摆放所有球并清空速度、导引与拨杆状态；[dropIn] 为假时预演到静止。
  void reset({required bool dropIn}) {
    _active.fillRange(0, count, 1);
    _layoutTop();
    _vx.fillRange(0, count, 0);
    _vy.fillRange(0, count, 0);
    _omega.fillRange(0, count, 0);
    angle.fillRange(0, count, 0);
    _guideStrength.fillRange(0, count, 0);
    _armAngle = 0;
    _armOmega = 0;
    _hasCommand = false;
    _halfWidth = 0;
    _armsOn = false;
    _calm = 0;
    _awake = count > 0;
    if (!dropIn) {
      for (var s = 0; s < _settleSteps && _awake; s++) {
        _snapshot();
        _step(_stepSeconds);
        _updateSleep(_stepSeconds, driven: false);
      }
    }
  }

  /// 把球 [i] 放到 ([px], [py])，可带初速度与自转，并唤醒世界。
  void place(int i, double px, double py,
      {double vx = 0, double vy = 0, double spin = 0}) {
    x[i] = px;
    y[i] = py;
    _vx[i] = vx;
    _vy[i] = vy;
    _omega[i] = spin;
    wake();
  }

  /// 忘记上一次拨杆指令角，下次 [advance] 把新指令当作起点而不是增量；拨杆当前角度保持。
  void resetStir() {
    _hasCommand = false;
    _armOmega = 0;
  }

  /// 唤醒世界，重新开始积分。
  void wake() {
    if (count == 0) return;
    _awake = true;
    _calm = 0;
  }

  /// 设置球 [i] 是否参与模拟；移出的球速度清零，位置由外部接管。
  void setActive(int i, {required bool active}) {
    _active[i] = active ? 1 : 0;
    _vx[i] = 0;
    _vy[i] = 0;
    _omega[i] = 0;
    wake();
  }

  /// 让球 [i] 受弹簧阻尼导引力趋向 ([tx], [ty])，[strength] 在零到一，零表示取消。
  void setGuide(int i, double tx, double ty, double strength) {
    _guideX[i] = tx;
    _guideY[i] = ty;
    _guideStrength[i] = strength;
    if (strength > 0) wake();
  }

  /// 推进 [dtSeconds] 秒。
  ///
  /// [stirAngle] 是拨杆指令角（弧度，累计值），[engaged] 在零到一，大于零时拨杆参与碰撞，
  /// 其半宽随 [engaged] 增长。拨杆角速度会被限制到尖端每子步位移不超过半个球半径。
  void advance(double dtSeconds,
      {required double stirAngle, double engaged = 0}) {
    if (dtSeconds <= 0) return;
    final maxDelta = _maxSubsteps * _tipStep * radius / kLuckyStirArmLength;
    final raw = _hasCommand ? stirAngle - _lastCommand : 0.0;
    final delta = raw.clamp(-maxDelta, maxDelta).toDouble();
    _lastCommand = stirAngle;
    _hasCommand = true;
    _armsOn = engaged > 0 && armCount > 0;
    _halfWidth =
        _armsOn ? kLuckyStirArmHalfWidth * radius * engaged.clamp(0, 1) : 0;
    final stirring = _armsOn && delta != 0;
    if (stirring) wake();
    if (!_awake) return;
    final byTime = (dtSeconds / _stepSeconds).ceil();
    final byTip =
        (delta.abs() * kLuckyStirArmLength / (_tipStep * radius)).ceil();
    final n = math.max(byTime, byTip).clamp(1, _maxSubsteps);
    final h = dtSeconds / n;
    _armOmega = delta / dtSeconds;
    _snapshot();
    for (var s = 0; s < n; s++) {
      _armAngle += delta / n;
      _step(h);
    }
    var guided = false;
    for (var i = 0; i < count && !guided; i++) {
      guided = _active[i] != 0 && _guideStrength[i] > 0;
    }
    _updateSleep(dtSeconds, driven: stirring || guided);
  }

  /// 下一个 [0,1) 的确定性随机数。
  double _random() {
    _rng = (_rng * _lcgMultiplier + _lcgIncrement) & _lcgMask;
    return _rng / _lcgRange;
  }

  /// 按六边形阵列从顶部向下摆放，再用种子洗牌与抖动，保证不依赖外部随机源。
  void _layoutTop() {
    _rng = seed & _lcgMask;
    final limit = 1 - radius;
    var spacing = 2 * radius * _dropSpacing;
    while (!_fillLattice(limit, spacing)) {
      spacing *= _dropShrink;
    }
    for (var i = count - 1; i > 0; i--) {
      final j = (_random() * (i + 1)).floor();
      final tx = x[i], ty = y[i];
      x[i] = x[j];
      y[i] = y[j];
      x[j] = tx;
      y[j] = ty;
    }
    for (var i = 0; i < count; i++) {
      x[i] += (_random() - 0.5) * _dropJitter * radius;
      y[i] += (_random() - 0.5) * _dropJitter * radius;
    }
    _wallPositions();
  }

  /// 以 [spacing] 为间距从顶部逐行填充圆内阵列；放不下返回假。
  bool _fillLattice(double limit, double spacing) {
    final rowHeight = spacing * math.sqrt(3) / 2;
    var placed = 0;
    var row = 0;
    for (var py = -limit; py <= limit && placed < count; py += rowHeight) {
      final half = math.sqrt(math.max(0, limit * limit - py * py));
      final shift = row.isOdd ? spacing / 2 : 0.0;
      for (var c = ((-half - shift) / spacing).ceil();
          c * spacing + shift <= half && placed < count;
          c++) {
        x[placed] = c * spacing + shift;
        y[placed] = py;
        placed++;
      }
      row++;
    }
    return placed == count;
  }

  /// 记录帧起点，供休眠判定按实际位移计算。
  void _snapshot() {
    _prevX.setAll(0, x);
    _prevY.setAll(0, y);
    _prevAngle.setAll(0, angle);
  }

  /// 休眠判定：整帧实际位移与转角都很小且没有外力驱动，则停止积分并清零速度。
  ///
  /// 深堆叠里每子步重力与接触会互相抵消，瞬时速度不为零但位置不动，
  /// 所以按位移而不是瞬时速度判断。
  void _updateSleep(double dt, {required bool driven}) {
    var fast = driven;
    final limit = _sleepSpeed * dt;
    for (var i = 0; i < count && !fast; i++) {
      if (_active[i] == 0) continue;
      final dx = x[i] - _prevX[i], dy = y[i] - _prevY[i];
      final spin = (angle[i] - _prevAngle[i]) * radius;
      fast = dx * dx + dy * dy > limit * limit || spin.abs() > limit;
    }
    _calm = fast ? 0 : _calm + dt;
    if (_calm >= _sleepSeconds) {
      _awake = false;
      _vx.fillRange(0, count, 0);
      _vy.fillRange(0, count, 0);
      _omega.fillRange(0, count, 0);
    }
  }

  /// 单个子步：积分、速度迭代、位置修正。
  void _step(double h) {
    final damp = math.max(0.0, 1 - linearDamping * h);
    final slowDamp = math.max(0.0, 1 - (linearDamping + _slowDamping) * h);
    final spinDamp = math.max(0.0, 1 - (linearDamping + _spinDamping) * h);
    for (var i = 0; i < count; i++) {
      if (_active[i] == 0) continue;
      var ax = 0.0, ay = gravity;
      final s = _guideStrength[i];
      if (s > 0) {
        ax += s *
            (_guideStiffness * (_guideX[i] - x[i]) - _guideDamping * _vx[i]);
        ay += s *
            (_guideStiffness * (_guideY[i] - y[i]) -
                _guideDamping * _vy[i] -
                gravity);
      }
      var vx = _vx[i] + ax * h, vy = _vy[i] + ay * h;
      final slow = vx * vx + vy * vy < _slowSpeed * _slowSpeed;
      final k = slow ? slowDamp : damp;
      vx *= k;
      vy *= k;
      _vx[i] = vx;
      _vy[i] = vy;
      _omega[i] *= spinDamp;
      x[i] += _vx[i] * h;
      y[i] += _vy[i] * h;
      angle[i] += _omega[i] * h;
    }
    for (var k = 0; k < armCount; k++) {
      final a = _armAngle + k * 2 * math.pi / armCount;
      _armCos[k] = math.cos(a);
      _armSin[k] = math.sin(a);
    }
    _buildContacts();
    for (var it = 0; it < _iterations; it++) {
      if (_armsOn) _armVelocities();
      _pairVelocities();
      _wallVelocities();
    }
    for (var pass = 0; pass < _positionPasses; pass++) {
      if (_armsOn) _armPositions();
      _pairPositions();
      _wallPositions();
    }
  }

  /// 摩擦冲量，限制在库仑锥内。
  double _clampFriction(double jt, double normalImpulse) {
    final limit = friction * normalImpulse;
    return math.min(math.max(jt, -limit), limit);
  }

  /// 球与容器壁的速度冲量。
  void _wallVelocities() {
    final limit = 1 - radius;
    for (var i = 0; i < count; i++) {
      if (_active[i] == 0) continue;
      final d2 = x[i] * x[i] + y[i] * y[i];
      if (d2 <= limit * limit) continue;
      final d = math.sqrt(d2);
      final nx = x[i] / d, ny = y[i] / d;
      final vn = _vx[i] * nx + _vy[i] * ny;
      if (vn <= 0) continue;
      final e = vn > _restThreshold ? restitution : 0.0;
      final jn = -(1 + e) * vn;
      _vx[i] += jn * nx;
      _vy[i] += jn * ny;
      final tx = -ny, ty = nx;
      final vt = _vx[i] * tx + _vy[i] * ty + _omega[i] * radius;
      final jt = _clampFriction(-vt / 3, -jn);
      _vx[i] += jt * tx;
      _vy[i] += jt * ty;
      _omega[i] += 2 * jt / radius;
    }
  }

  /// 建立本子步的邻近球对与靠近拨杆的球，迭代只遍历这两张表而不是全对检测。
  ///
  /// 速度迭代不移动球、位置修正位移很小，所以按积分后的位置建一次即可。
  void _buildContacts() {
    _pairCount = 0;
    final capacity = _pairA.length;
    final near = (2 + _contactSkin) * radius;
    for (var i = 0; i < count; i++) {
      if (_active[i] == 0 || _guideStrength[i] >= _ghostStrength) continue;
      for (var j = i + 1; j < count; j++) {
        if (_active[j] == 0 || _guideStrength[j] >= _ghostStrength) continue;
        final dx = x[j] - x[i], dy = y[j] - y[i];
        if (dx * dx + dy * dy >= near * near) continue;
        if (_pairCount >= capacity) break;
        _pairA[_pairCount] = i;
        _pairB[_pairCount++] = j;
      }
    }
    _hitCount = 0;
    if (!_armsOn) return;
    final armNear = radius + _halfWidth + _contactSkin * radius;
    for (var k = 0; k < armCount; k++) {
      final ux = _armCos[k], uy = _armSin[k];
      for (var i = 0; i < count; i++) {
        if (_active[i] == 0 || _guideStrength[i] >= _ghostStrength) continue;
        final s = math.min(math.max(x[i] * ux + y[i] * uy, kLuckyStirHubRadius),
            kLuckyStirArmLength);
        final dx = x[i] - ux * s, dy = y[i] - uy * s;
        if (dx * dx + dy * dy >= armNear * armNear) continue;
        _hitBall[_hitCount] = i;
        _hitArm[_hitCount++] = k;
      }
    }
  }

  /// 球与球的速度冲量（含摩擦与自转）。
  void _pairVelocities() {
    final reach = 2 * radius;
    for (var p = 0; p < _pairCount; p++) {
      final i = _pairA[p], j = _pairB[p];
      final dx = x[j] - x[i], dy = y[j] - y[i];
      final d2 = dx * dx + dy * dy;
      if (d2 >= reach * reach) continue;
      final d = math.sqrt(d2);
      final nx = d > _epsilon ? dx / d : 1.0;
      final ny = d > _epsilon ? dy / d : 0.0;
      final dvx = _vx[j] - _vx[i], dvy = _vy[j] - _vy[i];
      final vn = dvx * nx + dvy * ny;
      if (vn >= 0) continue;
      final e = -vn > _restThreshold ? restitution : 0.0;
      final jn = -(1 + e) * vn / 2;
      _vx[i] -= jn * nx;
      _vy[i] -= jn * ny;
      _vx[j] += jn * nx;
      _vy[j] += jn * ny;
      final tx = -ny, ty = nx;
      final vt = dvx * tx + dvy * ty - radius * (_omega[i] + _omega[j]);
      final jt = _clampFriction(-vt / 6, jn);
      _vx[i] -= jt * tx;
      _vy[i] -= jt * ty;
      _vx[j] += jt * tx;
      _vy[j] += jt * ty;
      _omega[i] -= 2 * jt / radius;
      _omega[j] -= 2 * jt / radius;
    }
  }

  /// 球与拨杆的速度冲量；拨杆视为无穷质量，表面速度随角速度。
  void _armVelocities() {
    final reach = radius + _halfWidth;
    for (var h = 0; h < _hitCount; h++) {
      final i = _hitBall[h], k = _hitArm[h];
      final ux = _armCos[k], uy = _armSin[k];
      final s = math.min(math.max(x[i] * ux + y[i] * uy, kLuckyStirHubRadius),
          kLuckyStirArmLength);
      final qx = ux * s, qy = uy * s;
      final dx = x[i] - qx, dy = y[i] - qy;
      final d2 = dx * dx + dy * dy;
      if (d2 >= reach * reach) continue;
      final d = math.sqrt(d2);
      final nx = d > _epsilon ? dx / d : -uy;
      final ny = d > _epsilon ? dy / d : ux;
      final rvx = _vx[i] + _armOmega * qy;
      final rvy = _vy[i] - _armOmega * qx;
      final vn = rvx * nx + rvy * ny;
      if (vn >= 0) continue;
      final e = -vn > _restThreshold ? restitution * _armRestitution : 0.0;
      final jn = -(1 + e) * vn;
      _vx[i] += jn * nx;
      _vy[i] += jn * ny;
      final tx = -ny, ty = nx;
      final vt = rvx * tx + rvy * ty - _omega[i] * radius;
      final jt = _clampFriction(-vt / 3, jn);
      _vx[i] += jt * tx;
      _vy[i] += jt * ty;
      _omega[i] -= 2 * jt / radius;
    }
  }

  /// 球与球的位置修正，平分穿透。
  void _pairPositions() {
    final reach = 2 * radius;
    final slop = _slop * radius;
    for (var p = 0; p < _pairCount; p++) {
      final i = _pairA[p], j = _pairB[p];
      final dx = x[j] - x[i], dy = y[j] - y[i];
      final d2 = dx * dx + dy * dy;
      if (d2 >= reach * reach) continue;
      final d = math.sqrt(d2);
      final nx = d > _epsilon ? dx / d : 1.0;
      final ny = d > _epsilon ? dy / d : 0.0;
      final push = math.max(reach - d - slop, 0) * _correction / 2;
      x[i] -= push * nx;
      y[i] -= push * ny;
      x[j] += push * nx;
      y[j] += push * ny;
    }
  }

  /// 球与拨杆的软位置修正，单次上限避免推出时跳变。
  void _armPositions() {
    final reach = radius + _halfWidth;
    final slop = _slop * radius;
    for (var h = 0; h < _hitCount; h++) {
      final i = _hitBall[h], k = _hitArm[h];
      final ux = _armCos[k], uy = _armSin[k];
      final s = math.min(math.max(x[i] * ux + y[i] * uy, kLuckyStirHubRadius),
          kLuckyStirArmLength);
      final dx = x[i] - ux * s, dy = y[i] - uy * s;
      final d2 = dx * dx + dy * dy;
      if (d2 >= reach * reach) continue;
      final d = math.sqrt(d2);
      final nx = d > _epsilon ? dx / d : -uy;
      final ny = d > _epsilon ? dy / d : ux;
      final push = math.min(math.max(reach - d - slop, 0) * _armCorrection,
          _armCorrectionCap * radius);
      x[i] += push * nx;
      y[i] += push * ny;
    }
  }

  /// 容器壁硬约束：越界的球投影回壁内。
  void _wallPositions() {
    final limit = 1 - radius;
    for (var i = 0; i < count; i++) {
      if (_active[i] == 0) continue;
      final d2 = x[i] * x[i] + y[i] * y[i];
      if (d2 <= limit * limit) continue;
      final scale = limit / math.sqrt(d2);
      x[i] *= scale;
      y[i] *= scale;
    }
  }
}
