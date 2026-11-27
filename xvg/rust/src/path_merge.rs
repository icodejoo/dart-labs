use crate::api::svg::SvgPath;

/// Defines collection-time path merging for the chosen scene. / 为当前场景指定收集阶段的路径合并行为。
pub(crate) trait MergePaths {
    /// Ends the current run at a draw boundary. / 在绘制边界结束当前合并段。
    fn end_run(&mut self);

    /// Returns whether the incoming draw was appended to a previous path. / 返回当前绘制是否已追加到前序路径。
    fn append(&mut self, out: &mut [SvgPath], path: &mut SvgPath) -> bool;
}

impl MergePaths for () {
    #[inline(always)]
    fn end_run(&mut self) {}

    #[inline(always)]
    fn append(&mut self, _out: &mut [SvgPath], _path: &mut SvgPath) -> bool {
        false
    }
}
