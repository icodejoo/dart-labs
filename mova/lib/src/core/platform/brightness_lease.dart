/// 包内使用的亮度还原权；换指时把最初的还原动作交给接班引擎。
///
/// 不从 barrel 导出，不要求宿主实现额外接口。
class MovaBrightnessLease {
  /// 为 [owner] 登记 [restore]，返回该还原权对象。
  ///
  /// 示例：`MovaBrightnessLease(engine, restoreInitialBrightness)`。
  MovaBrightnessLease(Object owner, this._restore) {
    _owners[owner] = this;
  }

  /// 仅随拥有者存活的还原权映射，避免全局强引用引擎。
  static final Expando<MovaBrightnessLease> _owners = Expando();

  /// 最初进入播放器时的还原动作。
  final Future<void> Function() _restore;

  /// 整段播放期间是否发生过亮度修改。
  bool _changed = false;

  /// 记录 [owner] 的亮度修改；示例：`MovaBrightnessLease.markChanged(engine)`。
  static void markChanged(Object owner) => _owners[owner]?._changed = true;

  /// 返回 [owner] 及其前任是否修改过亮度，无登记时返回 false。
  ///
  /// 示例：`if (MovaBrightnessLease.needsRestore(engine)) ...`。
  static bool needsRestore(Object owner) => _owners[owner]?._changed ?? false;

  /// 将 [previous] 的还原权交给 [successor]，无登记的宿主保持原行为。
  ///
  /// 示例：`MovaBrightnessLease.transfer(old, shadow)`。
  static void transfer(Object previous, Object successor) {
    final lease = _owners[previous];
    if (lease == null) return;
    lease._changed = lease._changed || needsRestore(successor);
    _owners[successor] = lease;
    _owners[previous] = null;
  }

  /// 释放 [owner] 的还原权，返回原始亮度还原完成通知，重复释放无操作。
  ///
  /// 示例：`await MovaBrightnessLease.release(engine)`。
  static Future<void> release(Object owner) async {
    final lease = _owners[owner];
    _owners[owner] = null;
    await lease?._restore();
  }
}
