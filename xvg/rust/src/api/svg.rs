// SVG parsing core: usvg → flat display list for Dart to replay into ui.Picture.
//
// SVG 解析核心：usvg → 扁平显示列表，交给 Dart 重放为 ui.Picture。

use usvg::tiny_skia_path::{Point, Transform};

/// A parsed SVG reduced to a flat list of paths with resolved paints.
///
/// 解析后的 SVG，规约为一组带已解析描边/填充的扁平路径。
pub struct SvgScene {
    /// Intrinsic width in px. / 固有宽（px）。
    pub width: f32,
    /// Intrinsic height in px. / 固有高（px）。
    pub height: f32,
    /// Draw commands in paint order. / 按绘制顺序排列的绘制命令。
    pub paths: Vec<SvgPath>,
    /// 含 opacity 时的有序重放命令；为空时沿用原有扁平绘制。
    pub commands: Vec<SvgCommand>,
    /// Embedded raster images, in document order (drawn before [paths] — a
    /// simplifying z-order assumption when [commands] is empty).
    ///
    /// 内嵌位图，按文档顺序排列（在 [paths] 之前绘制——简化的 z-order 假设，
    /// 有 [commands] 时按命令顺序绘制）。
    pub images: Vec<SvgImage>,
}

/// 静态显示列表命令：0 路径、1 图片、2 opacity 入层、3 出层。
#[derive(Clone)]
pub struct SvgCommand {
    /// 命令类型。
    pub kind: u8,
    /// 路径或图片下标；图层命令不用。
    pub index: u32,
    /// 入层不透明度；其他命令不用。
    pub opacity: f32,
}

/// 无 opacity 时不传重复的逐元素命令，保持普通图标载荷精简。
fn finish_commands(commands: &mut Vec<SvgCommand>) {
    if !commands.iter().any(|c| c.kind == 2) {
        commands.clear();
    }
}

/// 没有绘制内容时撤销入层，否则补齐出层。
fn close_opacity_layer(commands: &mut Vec<SvgCommand>, start: usize) {
    if commands.len() == start + 1 {
        commands.truncate(start);
    } else {
        commands.push(SvgCommand {
            kind: 3,
            index: 0,
            opacity: 1.0,
        });
    }
}

/// One embedded raster `<image>` node: absolute geometry + raw decoded bytes.
///
/// Only `usvg::ImageKind::Raster` (PNG/JPEG/GIF/WEBP) is represented here;
/// nested `<image>` referencing another SVG (`ImageKind::SVG`) is skipped
/// silently during collection — out of scope for this pass.
///
/// 单个内嵌位图 `<image>` 节点：绝对几何 + 原始解码字节。
///
/// 仅覆盖 `usvg::ImageKind::Raster`（PNG/JPEG/GIF/WEBP）；嵌套引用另一份 SVG 的
/// `<image>`（`ImageKind::SVG`）在收集阶段静默跳过——本轮不做。
pub struct SvgImage {
    /// Local (untransformed) object-bbox X. / 本地（未变换）物体包围盒 X。
    pub x: f32,
    /// Local (untransformed) object-bbox Y. / 本地（未变换）物体包围盒 Y。
    pub y: f32,
    /// Local (untransformed) object-bbox width. / 本地（未变换）物体包围盒宽度。
    pub width: f32,
    /// Local (untransformed) object-bbox height. / 本地（未变换）物体包围盒高度。
    pub height: f32,
    /// `[x, y, width, height]` mapped through this transform lands in
    /// absolute space; carries any rotation/skew from ancestor groups
    /// (`img.abs_transform()`), same 6-element convention as
    /// [SvgPattern.matrix]/[SvgGradient.matrix]. Two corners + width/height
    /// alone can't represent a rotated/skewed image, hence shipping the full
    /// matrix instead.
    ///
    /// 把 `[x, y, width, height]` 经此变换映射即落入绝对空间；携带祖先分组的
    /// 任意旋转/斜切（`img.abs_transform()`），与 [SvgPattern.matrix]/
    /// [SvgGradient.matrix] 同样的 6 元素约定。仅凭两角点 + 宽高无法表达
    /// 旋转/斜切后的图片，因此改为整体传出变换矩阵。
    pub matrix: Vec<f32>,
    /// Raw (still-encoded) image bytes, e.g. PNG file bytes.
    /// 原始（仍是编码态）图片字节，例如 PNG 文件字节。
    pub data: Vec<u8>,
    /// Encoding format of [data]. / [data] 的编码格式。
    pub format: SvgImageFormat,
    /// Clip regions inherited from ancestor groups, same semantics as
    /// [SvgEffects.clips]. / 从祖先分组继承的裁剪区域，语义同
    /// [SvgEffects.clips]。
    pub clips: Vec<SvgClip>,
    /// Mask inherited from the nearest ancestor group that declares one,
    /// same semantics as [SvgEffects.mask]. / 来自最近声明了遮罩的祖先分组的
    /// 遮罩，语义同 [SvgEffects.mask]。
    pub mask: Option<SvgMask>,
    /// Blur inherited from an ancestor group, same semantics as
    /// [SvgEffects.blur]. / 来自祖先分组的模糊，语义同 [SvgEffects.blur]。
    pub blur: Option<SvgBlur>,
}

/// Raster encodings usvg can hand back for `<image>`.
/// usvg 对 `<image>` 可返回的位图编码类型。
#[derive(Clone, Copy)]
pub enum SvgImageFormat {
    Png,
    Jpeg,
    Gif,
    Webp,
}

/// One clip region: the union of a `<clipPath>`'s shapes, already mapped into
/// absolute space.
///
/// A path carrying several [SvgClip]s must be clipped by *all* of them (set
/// intersection) — that is how nested `clip-path` on a `<clipPath>` and
/// clip-paths inherited from several ancestor groups compose.
///
/// 单个裁剪区域：一个 `<clipPath>` 内各形状的并集，已映射到绝对坐标空间。
///
/// 一条路径若带多个 [SvgClip]，必须被**全部**裁剪（求交集）——`<clipPath>` 自身
/// 的嵌套 `clip-path`、以及从多层祖先分组继承来的 clip-path 就是这样合成的。
#[derive(Clone)]
pub struct SvgClip {
    /// Verbs, same encoding as [SvgPath.verbs]. / 动词，编码同 [SvgPath.verbs]。
    pub verbs: Vec<u8>,
    /// Flattened x,y pairs, same encoding as [SvgPath.points].
    /// 扁平 x,y 坐标对，编码同 [SvgPath.points]。
    pub points: Vec<f32>,
    /// Even-odd fill rule for the clip region (else non-zero).
    /// 裁剪区域使用奇偶填充规则（否则非零环绕）。
    pub even_odd: bool,
}

/// A `<mask>` resolved into absolute-space content geometry plus its clipping
/// rect.
///
/// [paths] are the mask's own shapes (fully resolved paints included) — the
/// Dart side rasterizes them and uses either their luminance or their alpha
/// (per [kind]) as the coverage of the masked element.
///
/// 解析到绝对坐标空间的 `<mask>`：内容几何 + 遮罩矩形。
///
/// [paths] 是遮罩自身的形状（含已解析的 paint）——Dart 侧把它们光栅化，按
/// [kind] 取其亮度或 alpha 作为被遮罩元素的覆盖度。
#[derive(Clone)]
pub struct SvgMask {
    /// 0 = luminance (`mask-type="luminance"`, the default), 1 = alpha.
    /// 0 = 亮度（`mask-type="luminance"`，默认），1 = alpha。
    pub kind: u8,
    /// Mask rect in absolute space: left. / 绝对空间遮罩矩形左边界。
    pub x: f32,
    /// Mask rect in absolute space: top. / 绝对空间遮罩矩形上边界。
    pub y: f32,
    /// Mask rect width. / 遮罩矩形宽。
    pub width: f32,
    /// Mask rect height. / 遮罩矩形高。
    pub height: f32,
    /// Mask content shapes, in absolute space. / 遮罩内容形状，绝对坐标空间。
    pub paths: Vec<SvgPath>,
    /// 含 opacity 时的有序重放命令；为空时沿用原有扁平绘制。
    pub commands: Vec<SvgCommand>,
}

/// A `<pattern>` paint server resolved into a repeatable tile.
///
/// [paths] are the tile's contents in the pattern's own local space; [x]/[y]/
/// [width]/[height] is the tile rect in that same local space; [matrix]
/// (`[a, b, c, d, e, f]`) maps pattern-local space into the absolute space the
/// rest of the display list uses.
///
/// 已解析为可重复贴片的 `<pattern>` paint server。
///
/// [paths] 是贴片内容（图案自身局部空间）；[x]/[y]/[width]/[height] 是同一局部
/// 空间内的贴片矩形；[matrix]（`[a, b, c, d, e, f]`）把图案局部空间映射到显示
/// 列表其余部分所用的绝对空间。
#[derive(Clone)]
pub struct SvgPattern {
    /// The `<pattern>` element's own `id` — always present, since a pattern is
    /// only ever reachable via `url(#id)` and usvg drops any pattern def with
    /// no `id`. Lets the Dart side dedupe the (expensive) tile rasterization
    /// when the same pattern is referenced by many shapes.
    ///
    /// `<pattern>` 元素自身的 `id`——必然存在，因为图案只能通过 `url(#id)`
    /// 引用，usvg 会丢弃没有 `id` 的图案定义。供 Dart 侧在同一图案被多个形状
    /// 引用时，对（昂贵的）贴片光栅化做去重。
    pub id: String,
    /// Tile rect left, in pattern-local space. / 贴片矩形左边界（图案局部空间）。
    pub x: f32,
    /// Tile rect top, in pattern-local space. / 贴片矩形上边界（图案局部空间）。
    pub y: f32,
    /// Tile rect width. / 贴片矩形宽。
    pub width: f32,
    /// Tile rect height. / 贴片矩形高。
    pub height: f32,
    /// Pattern-local → absolute affine `[a, b, c, d, e, f]`.
    /// 图案局部 → 绝对空间的仿射矩阵 `[a, b, c, d, e, f]`。
    pub matrix: Vec<f32>,
    /// Tile contents, in pattern-local space. / 贴片内容，图案局部空间。
    pub paths: Vec<SvgPath>,
    /// 含 opacity 时的有序重放命令；为空时沿用原有扁平绘制。
    pub commands: Vec<SvgCommand>,
}

/// A resolved `feGaussianBlur`, in absolute-space sigma.
///
/// 已解析的 `feGaussianBlur`，sigma 已换算到绝对坐标空间。
#[derive(Clone)]
pub struct SvgBlur {
    /// Horizontal sigma. / 水平 sigma。
    pub std_dev_x: f32,
    /// Vertical sigma. / 垂直 sigma。
    pub std_dev_y: f32,
}

/// One path node: geometry (in absolute coords) plus fill/stroke.
///
/// 单个路径节点：几何（绝对坐标）+ 填充/描边。
#[derive(Clone)]
pub struct SvgPath {
    /// Verbs: 0=move 1=line 2=quad 3=cubic 4=close. / 动词：0 移动 1 直线 2 二次 3 三次 4 闭合。
    pub verbs: Vec<u8>,
    /// Flattened x,y coordinate pairs. / 扁平的 x,y 坐标对。
    pub points: Vec<f32>,
    /// Whether a fill is present. / 是否有填充。
    pub has_fill: bool,
    /// Fill color as 0xAARRGGBB. / 填充色 0xAARRGGBB。
    pub fill_argb: u32,
    /// Even-odd fill rule (else non-zero). / 奇偶填充规则（否则非零环绕）。
    pub even_odd: bool,
    /// Whether a stroke is present. / 是否有描边。
    pub has_stroke: bool,
    /// Stroke color as 0xAARRGGBB. / 描边色 0xAARRGGBB。
    pub stroke_argb: u32,
    /// Stroke width in px. / 描边宽度（px）。
    pub stroke_width: f32,
    /// Paint order: true paints stroke before fill (`paint-order="stroke fill"`),
    /// false (default) paints fill before stroke.
    ///
    /// 绘制顺序：true 表示先描边后填充（`paint-order="stroke fill"`），
    /// false（默认）表示先填充后描边。
    pub stroke_first: bool,
    /// Fill gradient, when the fill paint is a linear/radial gradient (in
    /// which case [fill_argb] is unused). / 填充渐变，填充为渐变时使用（此时
    /// [fill_argb] 不生效）。
    pub fill_gradient: Option<SvgGradient>,
    /// Stroke gradient, when the stroke paint is a linear/radial gradient (in
    /// which case [stroke_argb] is unused). / 描边渐变，描边为渐变时使用
    /// （此时 [stroke_argb] 不生效）。
    pub stroke_gradient: Option<SvgGradient>,
    /// Clip/mask/blur/pattern extras, when this path uses any of them.
    /// `None` for the common case (no clipPath/mask/filter/pattern), which
    /// SSE serializes as a single tag instead of one tag per sub-field — see
    /// [SvgEffects].
    ///
    /// 裁剪/遮罩/模糊/图案等附加特效，任一被用到时才有值。多数路径都不用这些
    /// 特效（`None`），SSE 序列化时只写一个 tag，而不是像拆分成 5 个独立字段
    /// 那样每个都写一个 tag——详见 [SvgEffects]。
    pub effects: Option<SvgEffects>,
}

/// Bundles the clip/mask/blur/pattern fields that only apply to a minority of
/// paths (those under a `<clipPath>`/`<mask>`/blur `<filter>`, or painted
/// with a `<pattern>`). Grouped into one struct — rather than left as five
/// separate `Option`/`Vec` fields on [SvgPath] — so the overwhelmingly common
/// "no such feature" case serializes as a single `None` tag over FFI instead
/// of five independent empty/`None` tags.
///
/// 打包裁剪/遮罩/模糊/图案这几个只有少数路径用得到的字段（位于
/// `<clipPath>`/`<mask>`/模糊 `<filter>` 之下，或用 `<pattern>` 上色的路径）。
/// 归并成一个结构体——而不是在 [SvgPath] 上留 5 个独立的 `Option`/`Vec`
/// 字段——这样绝大多数"没有用到这些特效"的情况，跨 FFI 时只序列化一个
/// `None` tag，而不是 5 个各自独立的空/`None` tag。
#[derive(Clone)]
pub struct SvgEffects {
    /// Fill pattern, when the fill paint is a `<pattern>` (in which case
    /// [SvgPath::fill_argb] is only a grey fallback). / 填充图案，填充为
    /// `<pattern>` 时使用（此时 [SvgPath::fill_argb] 只是灰色兜底）。
    pub fill_pattern: Option<SvgPattern>,
    /// Stroke pattern, when the stroke paint is a `<pattern>`.
    /// 描边图案，描边为 `<pattern>` 时使用。
    pub stroke_pattern: Option<SvgPattern>,
    /// Clip regions inherited from ancestor groups; the path must be clipped
    /// by all of them (intersection). Empty when unclipped.
    ///
    /// 从祖先分组继承来的裁剪区域；该路径必须被全部裁剪（求交集）。
    /// 无裁剪时为空。
    pub clips: Vec<SvgClip>,
    /// Mask inherited from the nearest ancestor group that declares one.
    /// 来自最近一个声明了遮罩的祖先分组的遮罩。
    pub mask: Option<SvgMask>,
    /// Gaussian blur inherited from the nearest ancestor group whose `filter`
    /// is a single `feGaussianBlur`. / 来自最近一个 `filter` 为单个
    /// `feGaussianBlur` 的祖先分组的高斯模糊。
    pub blur: Option<SvgBlur>,
}

impl SvgEffects {
    /// Builds `Some(SvgEffects)` when any sub-field is non-default, else
    /// `None` — keeping the "no effects" FFI payload minimal.
    ///
    /// 任一子字段非默认值时构建 `Some(SvgEffects)`，否则返回 `None`——让
    /// "无特效"场景下的 FFI 载荷保持最小。
    fn some_if_present(
        fill_pattern: Option<SvgPattern>,
        stroke_pattern: Option<SvgPattern>,
        clips: Vec<SvgClip>,
        mask: Option<SvgMask>,
        blur: Option<SvgBlur>,
    ) -> Option<Self> {
        if fill_pattern.is_none()
            && stroke_pattern.is_none()
            && clips.is_empty()
            && mask.is_none()
            && blur.is_none()
        {
            return None;
        }
        Some(SvgEffects {
            fill_pattern,
            stroke_pattern,
            clips,
            mask,
            blur,
        })
    }
}

/// One gradient color stop. / 单个渐变色标。
#[derive(Clone)]
pub struct SvgGradientStop {
    /// Position along the gradient in `[0, 1]`. / 沿渐变轴的位置，`[0, 1]`。
    pub offset: f32,
    /// Stop color as 0xAARRGGBB (alpha already combines `stop-opacity` and the
    /// paint's own fill/stroke opacity). / 色标颜色 0xAARRGGBB（alpha 已合并
    /// `stop-opacity` 与该 paint 自身的填充/描边透明度）。
    pub color_argb: u32,
}

/// A resolved linear/radial gradient paint.
///
/// Flattened into one struct (rather than an enum with per-variant fields) so
/// FRB can generate it as a plain Dart class without pulling in `freezed` —
/// see xvg CLAUDE.md's dependency-management rule (new deps need sign-off);
/// `kind` is the discriminant, and the unused half of the linear/radial
/// fields is simply left at its default.
///
/// For `kind == 0` (linear): [x1]/[y1]/[x2]/[y2] are the endpoints, already
/// resolved into the same absolute coordinate space as [SvgPath.points]
/// (bbox-relative `objectBoundingBox` gradients and any `gradientTransform`
/// pre-baked in) — an affine map is fully determined by where it sends two
/// points, so no extra matrix is needed.
///
/// For `kind == 1` (radial): [x1]/[y1] is the focal point, [x2]/[y2] is the
/// center, [radius] is the radius — all three in the gradient's own local
/// space (not absolute), plus [matrix] (local → absolute,
/// `[a, b, c, d, e, f]` per SVG's `matrix(a,b,c,d,e,f)`) that the Dart side
/// must apply (e.g. via `ui.Gradient.radial`'s `matrix4`) — unlike linear, a
/// non-uniform bbox scale turns the circle into an ellipse, which two points
/// alone can't express.
///
/// 已解析的线性/径向渐变 paint。
///
/// 压平为一个结构体（而非带各变体字段的枚举），使 FRB 能生成普通 Dart 类而
/// 无需引入 `freezed`——见 xvg CLAUDE.md 的依赖管理规则（新依赖需先征得同意）；
/// `kind` 是判别字段，线性/径向字段中用不到的那一半保持默认值即可。
///
/// `kind == 0`（线性）：[x1]/[y1]/[x2]/[y2] 是两个端点，已解析到与
/// [SvgPath.points] 相同的绝对坐标空间（bbox 相关的 `objectBoundingBox` 渐变
/// 及 `gradientTransform` 均已预烘焙）——仿射变换由其对两点的映射结果完全
/// 确定，无需额外矩阵。
///
/// `kind == 1`（径向）：[x1]/[y1] 是焦点，[x2]/[y2] 是圆心，[radius] 是半径——
/// 三者均在渐变自身的局部空间（非绝对空间），另加 [matrix]（局部→绝对，
/// `[a, b, c, d, e, f]`，对应 SVG `matrix(a,b,c,d,e,f)`）需由 Dart 侧应用
/// （例如通过 `ui.Gradient.radial` 的 `matrix4`）——与线性不同，非均匀 bbox
/// 缩放会把圆变成椭圆，仅凭两个点无法表达。
#[derive(Clone)]
pub struct SvgGradient {
    /// 0 = linear, 1 = radial. / 0 = 线性，1 = 径向。
    pub kind: u8,
    /// Linear: start X. Radial: focal point X (local space).
    /// 线性：起点 X。径向：焦点 X（局部空间）。
    pub x1: f32,
    /// Linear: start Y. Radial: focal point Y (local space).
    /// 线性：起点 Y。径向：焦点 Y（局部空间）。
    pub y1: f32,
    /// Linear: end X. Radial: center X (local space).
    /// 线性：终点 X。径向：圆心 X（局部空间）。
    pub x2: f32,
    /// Linear: end Y. Radial: center Y (local space).
    /// 线性：终点 Y。径向：圆心 Y（局部空间）。
    pub y2: f32,
    /// Radial only: radius (local space); unused for linear.
    /// 仅径向：半径（局部空间）；线性时不使用。
    pub radius: f32,
    /// Radial only: local-to-absolute affine `[a, b, c, d, e, f]`; empty for
    /// linear.
    /// 仅径向：局部到绝对空间的仿射变换 `[a, b, c, d, e, f]`；线性时为空。
    pub matrix: Vec<f32>,
    /// Color stops, in offset order. / 色标，按 offset 顺序排列。
    pub stops: Vec<SvgGradientStop>,
    /// Spread mode: 0=pad, 1=reflect, 2=repeat. / 延展模式：0=pad，1=reflect，2=repeat。
    pub spread: u8,
}

/// Parses [data] (SVG markup) into an [SvgScene]. Errors return a message.
///
/// [current_color] substitutes for the `currentColor` keyword in fill/stroke
/// paint values (0xAARRGGBB; alpha is ignored since SVG's `color` property
/// carries no alpha). `usvg::Options` (0.49) has no built-in hook for this
/// (`currentColor` resolves via `usvg`'s own `color`-attribute cascade,
/// defaulting to black), so when set, a `color="#RRGGBB"` attribute is
/// injected onto the root `<svg>` element before parsing — letting usvg's
/// existing cascade resolve it, while any explicit `color` already on the
/// root is left untouched.
///
/// 把 [data]（SVG 文本）解析为 [SvgScene]，出错返回错误信息。
///
/// [current_color] 用于替换 fill/stroke 中的 `currentColor` 关键字
/// （0xAARRGGBB；alpha 会被忽略，因为 SVG `color` 属性本身不带 alpha）。
/// `usvg::Options`（0.49）没有内置的注入钩子（`currentColor` 由 usvg 自身的
/// `color` 属性级联解析，缺省时回退黑色），所以设置该参数时会在解析前给根
/// `<svg>` 元素注入 `color="#RRGGBB"` 属性，借用 usvg 已有的级联机制解析；
/// 若根节点已显式声明 `color`，则保留不覆盖。
///
/// Example:
/// ```dart
/// final scene = parseSvg(data: '<svg .../>', currentColor: 0xFFFF7A00);
/// ```
#[flutter_rust_bridge::frb(sync)]
pub fn parse_svg(data: String, current_color: Option<u32>) -> Result<SvgScene, String> {
    const MAX_INPUT_BYTES: usize = 32 * 1024 * 1024;
    if data.len() > MAX_INPUT_BYTES {
        return Err("SVG input exceeds the 32 MiB limit".into());
    }
    check_xml_depth(&data)?;
    let doc = parse_xml(&data)?;
    let _stylesheet_needs_stack = limit_source_depth(&doc)?;
    // Only checked non-gradient CSS targets need the native stack fallback.
    // Gradient-only CSS stays inline even when declaration scanning is uncertain.
    #[cfg(not(any(target_family = "wasm", target_os = "none", target_os = "uefi")))]
    if _stylesheet_needs_stack {
        return std::thread::scope(|scope| {
            std::thread::Builder::new()
                .stack_size(STYLESHEET_STACK_BYTES)
                .spawn_scoped(scope, || {
                    let scene = parse_svg_document(&data, &doc, current_color)?;
                    limit_scene_reference_depth(&scene)?;
                    Ok(scene)
                })
                .map_err(|e| format!("Cannot start SVG stylesheet worker: {e}"))?
                .join()
                .map_err(|_| "SVG stylesheet worker panicked".to_owned())?
        });
    }
    // wasm and targets without native threads retain direct execution.
    parse_svg_document(&data, &doc, current_color)
}

// CSS references are resolved only by usvg. Check the resulting recursive
// wire paints on the worker too: otherwise a deep returned pattern can overflow
// during SSE encoding or Drop back on the caller's small stack. Rejected scenes
// are dropped here, while still on the large stack.
/// Check recursive wire paints in scene; return Err above the depth budget.
/// 检查 scene 的递归 wire 画笔；超过深度预算返回 Err；不涉及 simplecss 匹配。
fn limit_scene_reference_depth(scene: &SvgScene) -> Result<(), String> {
    let mut pending = vec![(scene.paths.as_slice(), 0usize)];
    for image in &scene.images {
        if let Some(mask) = &image.mask {
            pending.push((&mask.paths, 1));
        }
    }
    while let Some((paths, depth)) = pending.pop() {
        if depth > MAX_REFERENCE_DEPTH {
            return Err(REFERENCE_ERROR.into());
        }
        for path in paths {
            if let Some(effects) = &path.effects {
                for pattern in [&effects.fill_pattern, &effects.stroke_pattern]
                    .into_iter()
                    .flatten()
                {
                    pending.push((&pattern.paths, depth + 1));
                }
                if let Some(mask) = &effects.mask {
                    pending.push((&mask.paths, depth + 1));
                }
            }
        }
    }
    Ok(())
}

// A stack overflow or panic=abort cannot be recovered by join. CSS cycles and
// depth are bounded BEFORE spawning: this is only a finite fallback budget.
// Windows x86_64/usvg 0.44: pattern recursion costs ~16 KiB/layer debug,
// ~11.2 KiB release. The combined source/CSS graph bounds each chain to 32
// weighted edges; the worker adds headroom, not a proof for every upstream
// recursion. 32-bit 16 MiB and Android/iOS stacks remain unmeasured.
#[cfg(not(any(target_family = "wasm", target_os = "none", target_os = "uefi")))]
const STYLESHEET_STACK_BYTES: usize = if cfg!(target_pointer_width = "64") {
    64 * 1024 * 1024
} else {
    // Conserve the smaller virtual address space; not measured on 32-bit hosts.
    16 * 1024 * 1024
};

/// Convert data/doc with optional current_color through unchanged usvg; return scene or error.
/// 使用 data/doc 与可选 current_color 调用原始 usvg，返回场景或错误；CSS 仍由 simplecss 处理。
fn parse_svg_document(
    data: &str,
    doc: &usvg::roxmltree::Document<'_>,
    current_color: Option<u32>,
) -> Result<SvgScene, String> {
    #[cfg(test)]
    USVG_ENTRIES.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let injected = current_color.and_then(|argb| current_color_insertion(data, doc, argb));
    let tree = if let Some(injected) = injected {
        // 带 currentColor 需两遍,已知开销（额外 XML 文档分配）。
        // Keep roxmltree's validated root/attribute lookup: replacing it with
        // a partial scanner risks changing DTD, namespace and duplicate-color
        // handling. Reuse the validation document when no injection is needed.
        let colored_doc = parse_xml(&injected)?;
        usvg::Tree::from_xmltree(&colored_doc, usvg_options())
    } else {
        usvg::Tree::from_xmltree(doc, usvg_options())
    }
    .map_err(|e| e.to_string())?;
    try_scene_from_tree(&tree)
}

// Bound recursion BEFORE usvg constructs its recursive tree (including Drop).
// Scan iteratively first: roxmltree 0.20 overflowed at 5000 nested groups.
// Leave XML validation and reference lookup to roxmltree.
// Estimate against a 1 MiB thread stack: usvg release conversion overflows
// around 200–230 nested groups. 128 leaves headroom (debug uses larger frames).
const MAX_DEPTH: usize = 128;
const DEPTH_ERROR: &str = "SVG nesting exceeds the 128 layer limit";
// Reference expansion consumes more stack per level than source nesting;
// release 1 MiB measurements initially suggested 64 edges. Actual debug
// 1 MiB marker/pattern probes overflow at 64 and pass at 32 (2026-11-04).
// Use 32 in both profiles, including stylesheet reference edges.
const MAX_REFERENCE_DEPTH: usize = 32;
const REFERENCE_ERROR: &str = "SVG reference chain exceeds the 32 layer limit";
// Corpus max: 1105 rules (3.62x headroom), p99=672, median=11;
// 877 elements * 1105 rules = 969,085 pairs (8.26x headroom).
// r4/samples/s2.svg and corpus55/159.svg are the same source.
// Max estimated backtracking cost 128,528 (~249x headroom); max 1 combinator.
// Comma branches count separately because usvg matches each selector separately.
#[cfg(test)]
static GUARD_SCANS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);
#[cfg(test)]
static USVG_ENTRIES: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

const MAX_CSS_RULES: usize = 4000;
const MAX_CSS_MATCHES: usize = 8_000_000;
const MAX_CSS_SELECTOR_COST: usize = 32_000_000;
const CSS_COMPLEXITY_ERROR: &str = "SVG stylesheet too complex (rules, matches or graph edges)";
// Encoded image bytes beyond this cumulative output budget are silently
// skipped (Ok(None)), rather than making the entire SVG return Err.
const MAX_IMAGE_BYTES: usize = 64 * 1024 * 1024;

// This only bounds nesting; roxmltree remains responsible for XML validity.
/// Scan data iteratively; return an error for excessive XML depth or markup entities.
/// 迭代检查 data 的 XML 深度和标记实体，返回成功或错误；先于 simplecss 执行。
fn check_xml_depth(data: &str) -> Result<(), String> {
    let bytes = data.as_bytes();
    let (mut i, mut depth) = (0, 0usize);
    while i < bytes.len() {
        if bytes[i] != b'<' {
            i += 1;
            continue;
        }
        let tail = &data[i..];
        let special = if tail.starts_with("<!--") {
            Some((4, "-->"))
        } else if tail.starts_with("<![CDATA[") {
            Some((9, "]]>"))
        } else if tail.starts_with("<?") {
            Some((2, "?>"))
        } else {
            None
        };
        if let Some((prefix, end)) = special {
            i += prefix
                + tail[prefix..]
                    .find(end)
                    .ok_or("Unterminated XML declaration/comment/CDATA")?
                + end.len();
            continue;
        }
        let declaration = tail.starts_with("<!");
        let mut entity = tail.starts_with("<!ENTITY");
        let closing = tail.starts_with("</");
        let (mut quote, mut subset) = (0u8, 0usize);
        let mut j = i + 1;
        while j < bytes.len() {
            let c = bytes[j];
            if quote != 0 {
                // roxmltree recursively parses entity replacement markup and
                // overflows at 5000 groups before usvg is reached. Text-only
                // entities remain supported; reject markup before XML parsing.
                if entity && c == b'<' {
                    return Err("SVG entities containing markup are unsupported".into());
                }
                if c == quote {
                    quote = 0;
                }
            } else if c == b'\'' || c == b'"' {
                quote = c;
            } else if declaration && bytes[j..].starts_with(b"<!--") {
                j += 4
                    + data[j + 4..]
                        .find("-->")
                        .ok_or("Unterminated DTD comment")?
                    + 3;
                continue;
            } else if declaration && bytes[j..].starts_with(b"<?") {
                j += 2 + data[j + 2..].find("?>").ok_or("Unterminated DTD PI")? + 2;
                continue;
            } else if declaration && bytes[j..].starts_with(b"<!ENTITY") {
                entity = true;
            } else if declaration && c == b'>' && subset != 0 {
                entity = false;
            } else if declaration && c == b'[' {
                subset += 1;
            } else if declaration && c == b']' {
                subset = subset.saturating_sub(1);
            } else if c == b'>' && subset == 0 {
                break;
            }
            j += 1;
        }
        if j == bytes.len() {
            return Err("Unterminated XML tag".into());
        }
        if !declaration {
            if closing {
                depth = depth.saturating_sub(1);
            } else if bytes[j - 1] != b'/' {
                depth += 1;
                if depth > MAX_DEPTH {
                    return Err(DEPTH_ERROR.into());
                }
            }
        }
        i = j + 1;
    }
    Ok(())
}

/// Parse data with roxmltree and DTD support; return the document or its error.
/// 解析 data 为支持 DTD 的 XML 文档或返回错误；为 simplecss 提供原始样式文本。
fn parse_xml(data: &str) -> Result<usvg::roxmltree::Document<'_>, String> {
    usvg::roxmltree::Document::parse_with_options(
        data,
        usvg::roxmltree::ParsingOptions {
            allow_dtd: true,
            ..Default::default()
        },
    )
    .map_err(|e| e.to_string())
}

// Extract every URL token, including paint fallbacks, filter lists and inline
// declaration hacks accepted by simplecss. Token scanning stops at ')' rather than
// demanding the entire value be a FuncIRI. No declaration splitting is needed.
/// Yield local URL IDs in value using the same FuncIRI grammar as usvg.
/// 从 value 迭代本地 URL 标识；沿用 usvg FuncIRI 语法，覆盖 simplecss 声明中的 URL。
fn local_urls(value: &str) -> impl Iterator<Item = &str> {
    let mut tokens = value.match_indices("url(").peekable();
    std::iter::from_fn(move || loop {
        let (i, _) = tokens.next()?;
        // Do not rescan an unclosed token for every following url(. Besides
        // bounding malformed input, this still sees each later valid token.
        let end = tokens.peek().map_or(value.len(), |(next, _)| *next);
        let token = &value[i..end];
        // svgtypes 0.16 keeps Stream private. Isolate one token (respecting
        // quoted IDs), then use its public FuncIRI parser for the same grammar.
        let mut quote = 0u8;
        for (end, c) in token.bytes().enumerate().skip(4) {
            if quote != 0 {
                if c == quote {
                    quote = 0;
                }
            } else if c == b'\'' || c == b'"' {
                quote = c;
            } else if c == b')' {
                if let Ok(id) = svgtypes::FuncIRI::from_str(&token[..=end]) {
                    return Some(id.0);
                }
                break;
            }
        }
    })
}

// Independent guard scanner based on simplecss 0.2.2's lib.rs
// (consume_term/consume_at_rule/consume_declaration) and selector.rs/stream.rs.
// This is deliberately NOT a general CSS lexer: functions end at the FIRST ')'
// without interpreting quotes/comments, strings close unless the preceding byte
// is '\\', at-rule blocks count raw braces. Comments are skipped only between
// tokens. The original stylesheet is always passed unchanged to usvg.
// Grammar/recovery outside this audited subset sets uncertain for the WHOLE
// document: expanding resource interiors then reference non-gradient candidates. In particular
// malformed strings/comments/functions, escapes and illegal tokens never hide
// a later rule from the graph. No direct simplecss dependency is needed.
#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct GuardCss<'a> {
    rules: Vec<(String, &'a str)>,
    uncertain: bool,
}

/// Return whether byte c is whitespace in simplecss 0.2.2.
/// 返回字节 c 是否为 simplecss 0.2.2 定义的空白。
fn css_space(c: u8) -> bool {
    matches!(c, b' ' | b'\t' | b'\r' | b'\n' | b'\x0C') // CSS form feed / CSS 换页空白
}

/// Return the end offset of the string at start in bytes, or None if unclosed.
/// 返回 bytes 中 start 字符串的结束位置；未闭合返回 None，与 simplecss 前一字节转义规则一致。
fn css_string_end(bytes: &[u8], start: usize) -> Option<usize> {
    (start + 1..bytes.len())
        .find(|&i| bytes[i] == bytes[start] && bytes[i - 1] != b'\\')
        .map(|i| i + 1)
}

// Validate the declaration subset whose block boundaries we can prove agree
// with upstream. Failed validation is not a syntax error returned to the caller;
// it selects the global graph fallback instead of emulating error recovery.
/// Return whether text has provably aligned simplecss declaration/recovery boundaries.
/// 判断 text 的声明及错误恢复边界是否可确切对齐 simplecss；不能证明时返回 false。
fn css_declarations_certain(text: &str) -> bool {
    /// Skip text trivia at i; None means an unclosed simplecss comment.
    /// 跳过 text 在 i 处的空白和注释；simplecss 注释未闭合时返回 None。
    fn trivia(text: &str, i: &mut usize) -> Option<()> {
        let b = text.as_bytes();
        loop {
            while *i < b.len() && css_space(b[*i]) {
                *i += 1;
            }
            if !b[*i..].starts_with(b"/*") {
                return Some(());
            }
            *i += text[*i + 2..].find("*/")? + 4;
        }
    }
    // After consume_term/consume_ident fails, upstream counts RAW braces to
    // the block end. Certify only tails where our token-aware scan cannot
    // disagree with that boundary; collected URLs remain an overapproximation.
    // 失败后上游按原始花括号恢复；只认可两种扫描边界必然一致的尾部。
    /// Return whether text has identical raw/tokenized recovery block boundaries.
    /// 判断 text 按 simplecss 原始花括号恢复时是否与词元扫描的块边界一致。
    fn recovery_tail(text: &str) -> bool {
        !text.contains(['{', '}', '\'', '"', '\\']) && !text.contains("/*")
    }
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if trivia(text, &mut i).is_none() {
            return false;
        }
        if i == b.len() {
            break;
        }
        if b[i] == b'*' {
            i += 1;
        }
        if !css_ident(text, &mut i) || trivia(text, &mut i).is_none() || b.get(i) != Some(&b':') {
            return !matches!(b.get(i), Some(b'!')) && recovery_tail(&text[i..]);
        }
        i += 1;
        let mut terms = 0;
        loop {
            if trivia(text, &mut i).is_none() {
                return false;
            }
            if i == b.len() || matches!(b[i], b';' | b'!') {
                break;
            }
            match b[i] {
                b'\'' | b'"' => {
                    let Some(end) = css_string_end(b, i) else {
                        return false;
                    };
                    i = end;
                }
                b',' => i += 1,
                b'+' | b'-' | b'.' | b'0'..=b'9' => {
                    i += 1;
                    while b.get(i).is_some_and(u8::is_ascii_digit) {
                        i += 1;
                    }
                    if b.get(i) == Some(&b'.') {
                        i += 1;
                        while b.get(i).is_some_and(u8::is_ascii_digit) {
                            i += 1;
                        }
                    }
                    if b.get(i) == Some(&b'%') {
                        i += 1;
                    } else {
                        let end = i;
                        if !css_ident(text, &mut i) {
                            i = end;
                        }
                    }
                }
                b'#' => {
                    i += 1;
                    let end = i;
                    if !css_ident(text, &mut i) {
                        i = end;
                        while b.get(i).is_some_and(u8::is_ascii_hexdigit) {
                            i += 1;
                        }
                    }
                }
                _ => {
                    if !css_ident(text, &mut i) {
                        return !matches!(b.get(i), Some(b'!')) && recovery_tail(&text[i..]);
                    }
                    if b.get(i) == Some(&b'(') {
                        let Some(end) = text[i + 1..].find(')') else {
                            return false;
                        };
                        i += end + 2;
                    }
                }
            }
            terms += 1;
        }
        if terms == 0 {
            return false;
        }
        if b.get(i) == Some(&b'!') {
            i += 1;
            if trivia(text, &mut i).is_none() || !text[i..].starts_with("important") {
                return false;
            }
            i += 9;
            if trivia(text, &mut i).is_none() {
                return false;
            }
            if i < b.len() && b[i] != b';' {
                return false;
            }
        }
        while b.get(i) == Some(&b';') {
            i += 1;
            if trivia(text, &mut i).is_none() {
                return false;
            }
        }
    }
    true
}

/// Scan text into unchanged rule bodies and normalized headers, marking uncertain recovery.
/// 将 text 扫描为原始规则体及去注释规则头；按 simplecss 首个右括号等规则标记不确定恢复。
fn scan_css(text: &str) -> GuardCss<'_> {
    #[cfg(test)]
    GUARD_SCANS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let mut result = GuardCss::default();
    let b = text.as_bytes();
    let mut i = 0;
    while i < b.len() {
        if css_space(b[i]) {
            i += 1;
            continue;
        }
        if b[i..].starts_with(b"/*") {
            if let Some(end) = text[i + 2..].find("*/") {
                i += end + 4;
                continue;
            }
            result.uncertain = true;
            break;
        }
        if b[i] == b'@' {
            // Upstream ignores at-rules, using raw ';'/'{' and raw brace depth.
            i += 1;
            let name = i;
            while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'-') {
                i += 1;
            }
            if i == name || !css_compound_certain(&text[name..i]) {
                result.uncertain = true;
                break;
            }
            while i < b.len() && !matches!(b[i], b';' | b'{') {
                i += 1;
            }
            if i == b.len() {
                result.uncertain = true;
                break;
            }
            if b[i] == b';' {
                i += 1;
                continue;
            }
            i += 1;
            let mut depth = 1usize;
            while i < b.len() && depth != 0 {
                match b[i] {
                    b'{' => depth += 1,
                    b'}' => depth -= 1,
                    _ => {}
                }
                i += 1;
            }
            if depth != 0 {
                result.uncertain = true;
            }
            continue;
        }
        let mut header = String::new();
        while i < b.len() && b[i] != b'{' {
            if b[i..].starts_with(b"/*") {
                if let Some(end) = text[i + 2..].find("*/") {
                    i += end + 4;
                    continue;
                }
                result.uncertain = true;
                return result;
            }
            if matches!(b[i], b'\'' | b'"') {
                if let Some(end) = css_string_end(b, i) {
                    header.push_str(&text[i..end]);
                    i = end;
                    continue;
                }
                result.uncertain = true;
                return result;
            }
            let c = text[i..].chars().next().unwrap();
            header.push(c);
            i += c.len_utf8();
        }
        if i == b.len() {
            result.uncertain = true;
            break;
        }
        i += 1;
        let body = i;
        while i < b.len() && b[i] != b'}' {
            if b[i..].starts_with(b"/*") {
                if let Some(end) = text[i + 2..].find("*/") {
                    i += end + 4;
                    continue;
                }
                result.uncertain = true;
                return result;
            }
            match b[i] {
                b'\'' | b'"' => {
                    if let Some(end) = css_string_end(b, i) {
                        i = end;
                        continue;
                    }
                    result.uncertain = true;
                    return result;
                }
                b'(' if i > body && (b[i - 1].is_ascii_alphanumeric() || b[i - 1] == b'-') => {
                    if let Some(end) = text[i + 1..].find(')') {
                        i += end + 2;
                        continue;
                    }
                    result.uncertain = true;
                    return result;
                }
                // Recovery in consume_declarations counts raw braces. Rather
                // than attempting to predict partial declarations, go global.
                b'{' | b'(' | b'\\' => result.uncertain = true,
                c if c.is_ascii_control() && !css_space(c) => result.uncertain = true,
                _ => {}
            }
            i += 1;
        }
        result.uncertain |= !css_declarations_certain(&text[body..i]);
        result.rules.push((header, &text[body..i]));
        if i == b.len() {
            result.uncertain = true;
            break;
        }
        i += 1;
    }
    result
}

/// Consume an identifier in `text` at `i`; return success and advance the offset.
/// 按 simplecss 0.2.2 的 >237 字符规则扫描 text 标识符，更新 i，返回是否成功。
/// Escapes stay uncertain; iterate only consumed UTF-8 characters, not the whole tail.
fn css_ident(text: &str, i: &mut usize) -> bool {
    let start = *i;
    if text.as_bytes().get(*i) == Some(&b'-') {
        *i += 1;
    }
    let mut chars = text[*i..].chars();
    let Some(first) = chars.next() else {
        return *i != start;
    };
    if !(first.is_ascii_alphabetic() || first == '_' || first as u32 > 237) {
        return false;
    }
    *i += first.len_utf8();
    for c in chars {
        if c.is_ascii_alphanumeric() || matches!(c, '_' | '-') || c as u32 > 237 {
            *i += c.len_utf8();
        } else {
            break;
        }
    }
    true
}

// Retain every known tag/id/class constraint, including ancestor constraints.
// Attribute/pseudo constraints can only narrow matching; ignore just those
// constraints, not the rest of the selector. Unknown grammar goes global.
/// Validate compound constraints; return whether matching can safely overapproximate simplecss.
/// 校验 compound 约束，返回是否能安全放宽 simplecss 匹配；未知伪类仅放宽自身约束。
fn css_compound_certain(compound: &str) -> bool {
    let b = compound.as_bytes();
    let mut i = 0;
    if b.first() == Some(&b'*') {
        i += 1;
    } else if b
        .first()
        .is_some_and(|c| !matches!(c, b'#' | b'.' | b'[' | b':'))
        && !css_ident(compound, &mut i)
    {
        return false;
    }
    while i < b.len() {
        match b[i] {
            b'#' | b'.' => {
                i += 1;
                if !css_ident(compound, &mut i) {
                    return false;
                }
            }
            b'[' => {
                i += 1;
                if !css_ident(compound, &mut i) {
                    return false;
                }
                if matches!(b.get(i), Some(b'~' | b'|')) {
                    i += 1;
                    if b.get(i) != Some(&b'=') {
                        return false;
                    }
                }
                if b.get(i) == Some(&b'=') {
                    i += 1;
                    if matches!(b.get(i), Some(b'\'' | b'"')) {
                        let Some(end) = css_string_end(b, i) else {
                            return false;
                        };
                        i = end;
                    } else if !css_ident(compound, &mut i) {
                        return false;
                    }
                }
                if b.get(i) != Some(&b']') {
                    return false;
                }
                i += 1;
            }
            b':' => {
                i += 1;
                // Unknown pseudo names/elements are discarded by simplecss;
                // relax only this constraint, keeping tag/class/id relations.
                if b.get(i) == Some(&b':') {
                    i += 1;
                }
                if !css_ident(compound, &mut i) {
                    return false;
                }
                if b.get(i) == Some(&b'(') {
                    let Some(end) = compound[i + 1..].find(')') else {
                        return false;
                    };
                    let arg = &compound[i + 1..i + 1 + end];
                    if arg.contains(['{', '}', '\'', '"', '\\', '(']) || arg.contains("/*") {
                        return false;
                    }
                    i += end + 2;
                }
            }
            _ => return false,
        }
    }
    !b.is_empty()
}

/// Split selector into compounds and relations, or None for unaligned grammar.
/// 将 selector 按 simplecss 组合子拆为约束与关系；无法对齐的语法返回 None。
fn css_selector_parts(selector: &str) -> Option<Vec<(&str, u8)>> {
    let b = selector.as_bytes();
    let (mut parts, mut start, mut i, mut relation) = (Vec::new(), 0, 0, b' ');
    while i < b.len() {
        match b[i] {
            b'[' | b'(' => {
                let end = if b[i] == b'[' { b']' } else { b')' };
                i += 1;
                while i < b.len() && b[i] != end {
                    if matches!(b[i], b'\'' | b'"') {
                        i = css_string_end(b, i)?;
                    } else {
                        i += 1;
                    }
                }
                if i == b.len() {
                    return None;
                }
                i += 1;
            }
            c if css_space(c) || matches!(c, b'>' | b'+') => {
                if start < i {
                    parts.push((&selector[start..i], relation));
                    relation = b' ';
                }
                if !css_space(c) {
                    relation = c;
                }
                i += 1;
                start = i;
            }
            b'\\' | b'~' | b'/' | b'}' | b';' | b'@' | b'!' => return None,
            _ => i += 1,
        }
    }
    if start < i {
        parts.push((&selector[start..i], relation));
    }
    (!parts.is_empty() && parts.iter().all(|(c, _)| css_compound_certain(c))).then_some(parts)
}

/// Return whether node may match compound, retaining known tag/id/class constraints.
/// 判断 node 是否可能命中 compound；保留 simplecss 标签/id/class 约束，放宽属性和伪类。
fn css_compound_matches(compound: &str, node: usvg::roxmltree::Node<'_, '_>) -> bool {
    let b = compound.as_bytes();
    let mut i = 0;
    while i < b.len() {
        let prefix = b[i];
        if prefix == b'*' {
            i += 1;
            continue;
        }
        if prefix == b'[' {
            // Certain compounds have validated delimiters; quotes may contain ']'.
            i += 1;
            while i < b.len() && b[i] != b']' {
                if matches!(b[i], b'\'' | b'"') {
                    i = css_string_end(b, i).unwrap_or(b.len());
                } else {
                    i += 1;
                }
            }
            i += 1;
            continue;
        }
        if prefix == b':' {
            i += 1;
            if b.get(i) == Some(&b':') {
                i += 1;
            }
            while i < b.len()
                && (b[i].is_ascii_alphanumeric() || matches!(b[i], b'-' | b'_') || b[i] >= 128)
            {
                i += 1;
            }
            if b.get(i) == Some(&b'(') {
                i += compound[i + 1..]
                    .find(')')
                    .map_or(b.len() - i, |end| end + 2);
            }
            continue;
        }
        let start = i + usize::from(matches!(prefix, b'.' | b'#'));
        i = start;
        while i < b.len()
            && (b[i].is_ascii_alphanumeric() || matches!(b[i], b'_' | b'-') || b[i] >= 128)
        {
            i += 1;
        }
        if start == i {
            return true;
        }
        let word = &compound[start..i];
        let matches = match prefix {
            b'#' => node.attribute("id") == Some(word),
            b'.' => node
                .attribute("class")
                .is_some_and(|s| s.split_ascii_whitespace().any(|c| c == word)),
            _ => node.tag_name().name() == word,
        };
        if !matches {
            return false;
        }
    }
    true
}

/// Return whether node may match parsed parts, following simplecss ancestor/sibling traversal.
/// 按 simplecss 的祖先/兄弟遍历判断 node 是否可能命中 parts，返回布尔值。
fn css_parts_match(parts: &[(&str, u8)], node: usvg::roxmltree::Node<'_, '_>) -> bool {
    let Some((compound, relation)) = parts.last() else {
        return true;
    };
    if !css_compound_matches(compound, node) {
        return false;
    }
    if parts.len() == 1 {
        return true;
    }
    let rest = &parts[..parts.len() - 1];
    match relation {
        b'>' => node
            .parent_element()
            .is_some_and(|n| css_parts_match(rest, n)),
        b'+' => node
            .prev_siblings()
            .skip(1)
            .find(|n| n.is_element())
            .is_some_and(|n| css_parts_match(rest, n)),
        _ => node
            .ancestors()
            .skip(1)
            .filter(|n| n.is_element())
            .any(|n| css_parts_match(rest, n)),
    }
}

/// Scan styles in doc; return rules or Err when cumulative matching budgets are exceeded.
/// 扫描 doc 样式并累计 simplecss 匹配工作量；返回规则或预算超限错误。
fn checked_styles<'a>(
    doc: &'a usvg::roxmltree::Document<'_>,
) -> Result<Vec<(&'a str, GuardCss<'a>)>, String> {
    let elements = doc.descendants().filter(|n| n.is_element()).count();
    let depth = doc
        .descendants()
        .filter(|n| n.is_element())
        .map(|n| n.ancestors().filter(|n| n.is_element()).count())
        .max()
        .unwrap_or(1);
    let (mut styles, mut rules, mut cost) = (Vec::new(), 0usize, 0usize);
    for n in doc.descendants().filter(|n| n.has_tag_name("style")) {
        for text in n.children().filter_map(|n| n.text()) {
            // Raw braces are also an upper bound for malformed recovery and
            // skipped at-rules; do not let unclosed tokens hide rule budgets.
            let raw = text.bytes().filter(|&c| c == b'{').count();
            if raw > MAX_CSS_RULES {
                return Err(CSS_COMPLEXITY_ERROR.into());
            }
            let mut scan = scan_css(text);
            let mut selectors = 0usize;
            for (header, _) in &scan.rules {
                for selector in header.split(',') {
                    selectors += 1;
                    let parts = css_selector_parts(selector.trim());
                    if parts.is_none() {
                        scan.uncertain = true;
                    }
                    let count = parts.as_ref().map_or_else(
                        || selector.split_ascii_whitespace().count().saturating_sub(1),
                        |p| p.len() - 1,
                    );
                    // This is a pessimistic bound, NOT a match-count prediction.
                    // Actual simplecss 0.2.2 Element probes at depths 8/12/16:
                    // `* * * * *` short-circuits in 4 ancestor requests; missing
                    // `.a` in `.a .b .c .d .e` costs 255/1092/3213 (O(depth^4));
                    // `nonexist * * * * * rect` costs 465/4095/21777 (O(depth^6)).
                    // depth^k bounds the latter powers but overestimates successful
                    // universal chains and does not model factorial constants or
                    // rightmost filtering. No independent combinator cap is needed.
                    // 饱和估算是最坏回溯上界；通配链成功时短路，不能视作实际匹配次数。
                    cost = cost.saturating_add(
                        depth.saturating_pow(count as u32).saturating_mul(elements),
                    );
                }
            }
            if scan.uncertain {
                // Error recovery counts raw braces. Also inspect possible raw
                // rule heads, but NEVER count whitespace in declaration values
                // (animation/font lists etc.) as selector combinators.
                for fragment in text.split_inclusive('{').filter(|s| s.ends_with('{')) {
                    let head = fragment[..fragment.len() - 1]
                        .rsplit(['}', ';'])
                        .next()
                        .unwrap_or("");
                    let head = head.rsplit("*/").next().unwrap_or(head);
                    for selector in head.split(',') {
                        let Some(parts) = css_selector_parts(selector.trim()) else {
                            continue;
                        };
                        let count = parts.len() - 1;
                        cost = cost.saturating_add(
                            depth.saturating_pow(count as u32).saturating_mul(elements),
                        );
                    }
                }
            }
            rules = rules.saturating_add(raw.max(selectors));
            if cost > MAX_CSS_SELECTOR_COST {
                return Err("SVG stylesheet selector cost exceeds the 32M limit".into());
            }
            if rules > MAX_CSS_RULES || elements.saturating_mul(rules) > MAX_CSS_MATCHES {
                return Err(CSS_COMPLEXITY_ERROR.into());
            }
            styles.push((text, scan));
        }
    }
    Ok(styles)
}

/// Bound XML and reference expansion in doc before usvg; return whether a CSS worker is needed.
/// 在 usvg 前界定 doc 的 XML 与引用展开；返回是否需要 CSS 工作线程，无法对齐 simplecss 时使用保守图。
fn limit_source_depth(doc: &usvg::roxmltree::Document<'_>) -> Result<bool, String> {
    let mut references = false;
    // roxmltree descendants/ancestors iterators do not recurse or allocate.
    // Check the expanded tree too, including entity replacements.
    for n in doc.descendants().filter(|n| n.is_element()) {
        if n.ancestors().skip(1).filter(|n| n.is_element()).count() > MAX_DEPTH {
            return Err(DEPTH_ERROR.into());
        }
        references |= n.attributes().any(|a| a.value().contains("url("))
            || matches!(
                n.tag_name().name(),
                "use" | "feImage" | "pattern" | "filter"
            ) && n
                .attributes()
                .any(|a| a.name() == "href" && svgtypes::IRI::from_str(a.value()).is_ok());
    }
    let styles = if doc.input_text().contains("style") {
        checked_styles(doc)?
    } else {
        Vec::new()
    };
    references |= styles.iter().any(|(css, _)| css.contains("url("));
    if !references {
        return Ok(false);
    }

    let nodes: Vec<_> = doc.descendants().filter(|n| n.is_element()).collect();
    let (edges, css_references) = source_reference_graph(&nodes, &styles)?;
    let mut reverse = vec![Vec::new(); nodes.len()];
    for (i, outgoing) in edges.iter().enumerate() {
        for &(target, weight) in outgoing {
            reverse[target].push((i, weight));
        }
    }

    // Iterative Kosaraju: visited sets terminate cycles without removing any
    // attributes. Preserve usvg's one/two-resource cycle semantics, but reject
    // larger cycles: usvg 0.44 infinitely recurses on three-resource cycles.
    // Bound acyclic expansion between the remaining collapsed components.
    let mut visited = vec![false; nodes.len()];
    let mut order = Vec::with_capacity(nodes.len());
    let mut stack = Vec::new();
    for start in 0..nodes.len() {
        if visited[start] {
            continue;
        }
        visited[start] = true;
        stack.push((start, 0));
        while let Some((node, next)) = stack.last_mut() {
            if *next == edges[*node].len() {
                order.push(*node);
                stack.pop();
            } else {
                let target = edges[*node][*next].0;
                *next += 1;
                if !visited[target] {
                    visited[target] = true;
                    stack.push((target, 0));
                }
            }
        }
    }
    let mut component = vec![usize::MAX; nodes.len()];
    let mut pending = Vec::new();
    let mut count = 0;
    for &start in order.iter().rev() {
        if component[start] != usize::MAX {
            continue;
        }
        component[start] = count;
        pending.push(start);
        while let Some(node) = pending.pop() {
            for &(parent, _) in &reverse[node] {
                if component[parent] == usize::MAX {
                    component[parent] = count;
                    pending.push(parent);
                }
            }
        }
        count += 1;
    }
    // Kosaraju numbers components in topological order. Dynamic programming
    // backwards computes the longest reference chain in linear time.
    let mut longest = vec![0usize; count];
    let mut members = vec![Vec::new(); count];
    for (node, &c) in component.iter().enumerate() {
        members[c].push(node);
    }
    for source in (0..count).rev() {
        // Structural descendants belong to the SCC too. Count only distinct
        // targets of internal URL edges, i.e. resources rather than children.
        let resources = members[source]
            .iter()
            .filter(|&&node| {
                reverse[node]
                    .iter()
                    .any(|&(parent, weight)| weight == 1 && component[parent] == source)
            })
            .count();
        if resources >= 3 {
            return Err("SVG has a reference cycle involving at least 3 resources".into());
        }
        for &node in &members[source] {
            for &(target, weight) in &edges[node] {
                let target = component[target];
                if source != target {
                    longest[source] = longest[source].max(longest[target] + weight);
                }
            }
        }
        if longest[source] > MAX_REFERENCE_DEPTH {
            return Err(REFERENCE_ERROR.into());
        }
    }
    Ok(css_references)
}

/// Build the guard graph without invoking upstream recursive conversion.
fn source_reference_graph(
    nodes: &[usvg::roxmltree::Node<'_, '_>],
    styles: &[(&str, GuardCss<'_>)],
) -> Result<(Vec<Vec<(usize, usize)>>, bool), String> {
    // The linear token scanner stops at another url(. Reject this unusual ID
    // spelling rather than missing a quoted target containing nested URL text.
    if nodes
        .iter()
        .any(|n| n.attribute("id").is_some_and(|id| id.contains("url(")))
    {
        return Err("SVG resource ID contains nested URL syntax".into());
    }
    let indices: std::collections::HashMap<_, _> =
        nodes.iter().enumerate().map(|(i, n)| (n.id(), i)).collect();
    // usvg URL lookup keeps the last recognized element; use keeps the first.
    // Preserve ALL candidates, including unknown decoys. Duplicate IDs alone
    // are legal: only a resulting cycle/long chain is rejected.
    let mut ids: std::collections::HashMap<&str, Vec<usize>> = std::collections::HashMap::new();
    for (i, node) in nodes.iter().enumerate() {
        if let Some(id) = node.attribute("id") {
            ids.entry(id).or_default().push(i);
        }
    }
    let mut edges = vec![Vec::new(); nodes.len()];
    for (i, n) in nodes.iter().enumerate() {
        // Structural edges cost zero; they connect references declared on
        // resource children to that resource's expansion chain.
        for child in n.children().filter(|n| n.is_element()) {
            edges[i].push((indices[&child.id()], 0usize));
        }
        const RESOURCE_PROPERTIES: [&str; 9] = [
            "clip-path",
            "mask",
            "fill",
            "stroke",
            "filter",
            "marker",
            "marker-start",
            "marker-mid",
            "marker-end",
        ];
        for value in RESOURCE_PROPERTIES
            .iter()
            .filter_map(|name| n.attribute(*name))
            .chain(n.attribute("style"))
        {
            for id in local_urls(value) {
                for &target in ids.get(id).into_iter().flatten() {
                    edges[i].push((target, 1));
                }
            }
        }
        if matches!(
            n.tag_name().name(),
            "use" | "feImage" | "pattern" | "filter"
        ) {
            // Use the same IRI parser as usvg (including surrounding spaces).
            // roxmltree exposes both href and xlink:href by local name. These
            // weighted edges plus zero-cost child edges count expansion chains
            // through symbol/g, never the number of sibling use instances.
            // usvg separately enforces its 1,000,000 expanded XML node limit.
            for attr in n.attributes().filter(|a| a.name() == "href") {
                if let Some(targets) = svgtypes::IRI::from_str(attr.value())
                    .ok()
                    .and_then(|id| ids.get(id.0))
                {
                    for &target in targets {
                        edges[i].push((target, 1));
                    }
                }
            }
        }
    }
    let uncertain = styles.iter().any(|(_, scan)| scan.uncertain);
    let mut css_targets = std::collections::HashSet::new();
    for (css, _) in styles {
        for target in local_urls(css)
            .flat_map(|id| ids.get(id).into_iter().flatten())
            .copied()
        {
            if !matches!(
                nodes[target].tag_name().name(),
                "linearGradient" | "radialGradient"
            ) {
                css_targets.insert(target);
            }
        }
    }
    if !css_targets.is_empty() {
        let mut added = 0usize;
        if uncertain {
            // Global fallback, even if uncertainty occurred in a different style.
            if nodes.len().saturating_mul(css_targets.len()) > MAX_CSS_MATCHES {
                return Err(CSS_COMPLEXITY_ERROR.into());
            }
            // Any referenced subtree can be expanded, including ordinary g/rect
            // targets reached through use/feImage or pattern/filter inheritance.
            // Snapshot incoming references before adding fallback CSS edges.
            let mut referenced = vec![false; nodes.len()];
            for outgoing in &edges {
                for &(target, weight) in outgoing {
                    if weight >= 1 {
                        referenced[target] = true;
                    }
                }
            }
            for (i, outgoing) in edges.iter_mut().enumerate() {
                // Include all descendants of expanding targets/resources, but
                // never gradients or their stops: those cannot recurse via CSS.
                if !nodes[i].ancestors().any(|n| {
                    n.is_element()
                        && !matches!(n.tag_name().name(), "linearGradient" | "radialGradient")
                        && (indices
                            .get(&n.id())
                            .is_some_and(|&j| css_targets.contains(&j) || referenced[j])
                            || matches!(
                                n.tag_name().name(),
                                "pattern" | "mask" | "clipPath" | "filter" | "marker" | "symbol"
                            ))
                }) {
                    continue;
                }
                if nodes[i]
                    .ancestors()
                    .any(|n| matches!(n.tag_name().name(), "linearGradient" | "radialGradient"))
                {
                    continue;
                }
                outgoing.extend(css_targets.iter().map(|&target| (target, 1)));
            }
        } else {
            for (_, scan) in styles {
                for (header, body) in &scan.rules {
                    let targets: std::collections::HashSet<_> = local_urls(body)
                        .flat_map(|id| ids.get(id).into_iter().flatten())
                        .copied()
                        .filter(|t| css_targets.contains(t))
                        .collect();
                    if targets.is_empty() {
                        continue;
                    }
                    let selectors: Vec<_> = header
                        .split(',')
                        .map(|selector| css_selector_parts(selector.trim()))
                        .collect();
                    for (i, node) in nodes.iter().enumerate() {
                        if selectors
                            .iter()
                            .any(|parts| parts.as_ref().is_none_or(|p| css_parts_match(p, *node)))
                        {
                            for &target in &targets {
                                added += 1;
                                if added > MAX_CSS_MATCHES {
                                    return Err(CSS_COMPLEXITY_ERROR.into());
                                }
                                edges[i].push((target, 1));
                            }
                        }
                    }
                }
            }
        }
    }
    Ok((edges, !css_targets.is_empty()))
}

/// The process-wide `usvg::Options`, built once.
///
/// `Options::default()` heap-allocates on every call (the default `font_family`
/// String, the `languages` Vec plus its one String, and the two boxed
/// `image_href_resolver` closures) and this crate never varies any of them per
/// call, so building it per `parse_svg` was pure waste. Sharing one instance is
/// sound because usvg declares both resolver closures `Send + Sync + 'static`
/// and `Tree::from_str` only ever reads `Options`.
///
/// No `fontdb`/`font_resolver` field is set: usvg's `system-fonts`/`text`
/// features are disabled (see rust/Cargo.toml), so those fields do not exist.
/// `<text>` sources still parse fine — they just yield no glyph geometry (see
/// the `usvg::Node::Text` arm in [collect]).
///
/// 进程级共享的 `usvg::Options`，只构建一次。
///
/// `Options::default()` 每次调用都会在堆上分配（默认 `font_family` String、
/// `languages` Vec 及其中的一个 String、两个装箱的 `image_href_resolver`
/// 闭包），而本 crate 从不按调用改动其中任何一项，所以每次 `parse_svg` 都重建
/// 纯属浪费。共享一份是安全的：usvg 把两个 resolver 闭包声明为
/// `Send + Sync + 'static`，且 `Tree::from_str` 只读 `Options`。
///
/// 不设置 `fontdb`/`font_resolver` 字段：usvg 的 `system-fonts`/`text` feature
/// 已关闭（见 rust/Cargo.toml），这两个字段并不存在。含 `<text>` 的源依然能
/// 正常解析——只是不产生字形几何（见 [collect] 里的 `usvg::Node::Text` 分支）。
#[flutter_rust_bridge::frb(ignore)]
fn usvg_options() -> &'static usvg::Options<'static> {
    static OPTIONS: std::sync::OnceLock<usvg::Options<'static>> = std::sync::OnceLock::new();
    OPTIONS.get_or_init(|| usvg::Options {
        // Keep embedded data URIs; reject paths before any filesystem/UNC access.
        // 保留内嵌 data URI；拒绝所有路径，避免文件系统读取或 UNC 网络访问。
        image_href_resolver: usvg::ImageHrefResolver {
            resolve_data: {
                let default = usvg::ImageHrefResolver::default_data_resolver();
                Box::new(move |mime, data, options| {
                    // SVG images are already omitted by convert_image. Reject
                    // before usvg recursively parses an unsupported sub-SVG.
                    if mime == "image/svg+xml" {
                        return None;
                    }
                    // Upstream also tries SVG for unknown text/plain data.
                    // Only pass raster signatures to that fallback resolver;
                    // the default still validates/detects the actual format.
                    if mime == "text/plain"
                        && !(data.starts_with(b"\x89PNG\r\n\x1a\n")
                            || data.starts_with(b"\xff\xd8")
                            || data.starts_with(b"GIF87a")
                            || data.starts_with(b"GIF89a")
                            || (data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP")))
                    {
                        return None;
                    }
                    default(mime, data, options)
                })
            },
            resolve_string: Box::new(|_, _| None),
        },
        ..usvg::Options::default()
    })
}

/// Flattens an already-parsed usvg tree into the wire [SvgScene].
///
/// Split out of [parse_svg] so the benchmark harness can time this conversion
/// on its own, separately from usvg's XML parse — the two have very different
/// cost profiles and only this half is ours to optimize.
///
/// 把已解析的 usvg 树展平为跨 FFI 的 [SvgScene]。
///
/// 从 [parse_svg] 拆出来，便于基准 harness 单独给这段转换计时，与 usvg 的 XML
/// 解析分开——两者成本画像差别很大，而只有这一半是我们能优化的。
#[flutter_rust_bridge::frb(ignore)]
#[cfg(test)]
pub(crate) fn scene_from_tree(tree: &usvg::Tree) -> SvgScene {
    try_scene_from_tree(tree).expect("benchmark fixture exceeds SVG complexity budget")
}

fn try_scene_from_tree(tree: &usvg::Tree) -> Result<SvgScene, String> {
    let size = tree.size();
    let mut paths = Vec::new();
    let mut images = Vec::new();
    let mut commands = Vec::new();
    // The root `<svg>` can itself carry clip-path/mask/filter, so seed the
    // inherited context from it rather than starting empty.
    // 根 `<svg>` 自身也可能带 clip-path/mask/filter，因此继承上下文从它起算，
    // 而不是从空开始。
    let mut image_budget = MAX_IMAGE_BYTES;
    let mut expansion_budget = ExpansionBudget::default();
    let root_ctx = if tree.root().opacity().get() == 0.0 {
        Inherited::default()
    } else {
        extend_inherited(&Inherited::default(), tree.root(), &mut expansion_budget)?
            .unwrap_or_default()
    };
    collect(
        tree.root(),
        &root_ctx,
        &mut paths,
        &mut images,
        &mut commands,
        0,
        &mut image_budget,
        &mut expansion_budget,
    )?;
    finish_commands(&mut commands);
    Ok(SvgScene {
        width: size.width(),
        height: size.height(),
        paths,
        commands,
        images,
    })
}

/// Injects a `color="#RRGGBB"` attribute into the root `<svg>` tag, unless it
/// already declares one. Gives usvg's own `currentColor` cascade (which reads
/// the `color` attribute, walking up ancestors) a caller-provided value to
/// resolve against, without usvg exposing a dedicated option for it.
///
/// Takes [data] by value and hands it back untouched on every path that needs
/// no injection, so the three early exits cost nothing; only the injecting path
/// allocates, and it allocates exactly once.
///
/// 给根 `<svg>` 标签注入 `color="#RRGGBB"` 属性（若尚未声明）。让 usvg 自身的
/// `currentColor` 级联解析（读取 `color` 属性并向上查找祖先）能用上调用方
/// 提供的颜色——usvg 本身并未为此暴露专门的 Option。
///
/// 按值接收 [data]，不需要注入的分支原样返回，三个提前返回路径零成本；只有
/// 真正注入的分支分配，且只分配一次。
#[cfg(test)]
fn inject_current_color(data: String, argb: u32) -> String {
    let Ok(doc) = parse_xml(&data) else {
        return data;
    };
    current_color_insertion(&data, &doc, argb).unwrap_or(data)
}

fn current_color_insertion(
    data: &str,
    doc: &usvg::roxmltree::Document<'_>,
    argb: u32,
) -> Option<String> {
    let root = doc.root_element();
    if root.tag_name().name() != "svg" || root.attribute("color").is_some() {
        return None;
    }
    let start = root.range().start + 1;
    let Some(len) = data[start..].find(|c: char| c.is_ascii_whitespace() || c == '/' || c == '>')
    else {
        return None;
    };
    let insert_at = start + len;
    const ATTR: &str = " color=\"#RRGGBB\"";
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut out = String::with_capacity(data.len() + ATTR.len());
    out.push_str(&data[..insert_at]);
    out.push_str(" color=\"#");
    let rgb = argb & 0x00FF_FFFF;
    for shift in [20, 16, 12, 8, 4, 0] {
        out.push(HEX[((rgb >> shift) & 0xF) as usize] as char);
    }
    out.push('"');
    out.push_str(&data[insert_at..]);
    Some(out)
}

/// Group-level state a path inherits from its ancestors: clip regions, the
/// nearest mask, and the nearest single-`feGaussianBlur` filter.
///
/// Kept private (not FRB-exported): it is a walk-time accumulator, and what
/// crosses the FFI boundary is the per-path snapshot baked into [SvgPath].
///
/// 路径从祖先继承的分组级状态：裁剪区域、最近的遮罩、最近的单
/// `feGaussianBlur` 滤镜。
///
/// 保持私有（不导出给 FRB）：它只是遍历期的累加器，真正跨 FFI 的是烘焙进
/// [SvgPath] 的每路径快照。
#[flutter_rust_bridge::frb(ignore)]
#[derive(Clone, Default)]
struct Inherited {
    clips: Vec<SvgClip>,
    mask: Option<SvgMask>,
    blur: Option<SvgBlur>,
}

// Charge the fully expanded wire geometry before cloning it onto each output.
// Bound both points (x,y pairs) and paths: tiny paths still have owned buffers.
const MAX_EXPANSION_POINTS: usize = 4_000_000;
const MAX_EXPANSION_PATHS: usize = 100_000;
const MAX_EXPANSION_COMMANDS: usize = 100_000;
const EXPANSION_ERROR: &str = "SVG too complex: clip/mask expansion budget exceeded";

/// Running totals charged against the clip/mask expansion limits. Internal only:
/// ignored by FRB so no Dart binding is generated for it.
///
/// 已消耗的裁剪/遮罩展开配额累计值。仅内部使用：对 FRB 标记 ignore，
/// 不生成 Dart 绑定。
#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct ExpansionBudget {
    points: usize,
    paths: usize,
    commands: usize,
}

impl ExpansionBudget {
    fn charge(&mut self, ctx: &Inherited) -> Result<(), String> {
        self.charge_clips(&ctx.clips);
        if let Some(mask) = &ctx.mask {
            self.charge_subtree(&mask.paths, &mask.commands)?;
        }
        self.check()
    }

    /// 遮罩与图案的嵌套载荷都计入预算，克隆前检查。
    fn charge_subtree(&mut self, paths: &[SvgPath], commands: &[SvgCommand]) -> Result<(), String> {
        let mut pending = vec![(paths, commands)];
        while let Some((paths, commands)) = pending.pop() {
            self.paths = self.paths.saturating_add(paths.len());
            self.commands = self.commands.saturating_add(commands.len());
            self.check()?;
            for path in paths {
                self.points = self.points.saturating_add(path.points.len() / 2);
                if let Some(e) = &path.effects {
                    self.charge_clips(&e.clips);
                    if let Some(m) = &e.mask {
                        pending.push((&m.paths, &m.commands));
                    }
                    for pattern in [&e.fill_pattern, &e.stroke_pattern].into_iter().flatten() {
                        pending.push((&pattern.paths, &pattern.commands));
                    }
                }
                self.check()?;
            }
        }
        Ok(())
    }

    fn charge_clips(&mut self, clips: &[SvgClip]) {
        self.paths = self.paths.saturating_add(clips.len());
        for clip in clips {
            self.points = self.points.saturating_add(clip.points.len() / 2);
        }
    }

    fn check(&self) -> Result<(), String> {
        if self.points > MAX_EXPANSION_POINTS
            || self.paths > MAX_EXPANSION_PATHS
            || self.commands > MAX_EXPANSION_COMMANDS
        {
            return Err(EXPANSION_ERROR.into());
        }
        Ok(())
    }
}

/// Recursively walks a group, flattening path nodes into [out] while carrying
/// [ctx] (clip/mask/blur inherited from ancestor groups) down the tree.
/// In the main tree, normal Path/Image children have their parent's absolute
/// transform (usvg 0.49 converter.rs:1006, image.rs:236-251).
/// usvg 0.49's root background Path is inconsistent:
/// `background_path` uses `Path::new_simple` and leaves its absolute transform
/// at identity before the root group's viewBox transform is set. Using the
/// parent fixes that background while preserving normal Path/Image output.
///
/// 递归遍历分组，把路径节点扁平化收集进 [out]，同时把 [ctx]（从祖先分组继承的
/// 裁剪/遮罩/模糊）沿树向下传递。
/// 主树中普通 Path/Image 与父组的绝对变换相同（usvg 0.49 的
/// converter.rs:1006、image.rs:236-251）。usvg 0.49
/// 的根背景 Path 存在不一致：`background_path` 用 `Path::new_simple` 创建路径，
/// 随后设置根组的 viewBox 变换，却把路径的绝对变换留在单位矩阵。改用父组
/// 变换修复背景，同时保持普通 Path/Image 的输出不变。
fn collect(
    group: &usvg::Group,
    ctx: &Inherited,
    out: &mut Vec<SvgPath>,
    images: &mut Vec<SvgImage>,
    commands: &mut Vec<SvgCommand>,
    depth: usize,
    image_budget: &mut usize,
    expansion_budget: &mut ExpansionBudget,
) -> Result<(), String> {
    if depth >= MAX_DEPTH {
        return Ok(());
    }
    let opacity = group.opacity().get();
    if opacity == 0.0 {
        return Ok(());
    }
    let layer_start = commands.len();
    if opacity != 1.0 {
        commands.push(SvgCommand {
            kind: 2,
            index: 0,
            opacity,
        });
    }
    for node in group.children() {
        match node {
            usvg::Node::Group(g) if g.opacity().get() == 0.0 => continue,
            usvg::Node::Group(g) => match extend_inherited(ctx, g, expansion_budget)? {
                Some(child_ctx) => collect(
                    g,
                    &child_ctx,
                    out,
                    images,
                    commands,
                    depth + 1,
                    image_budget,
                    expansion_budget,
                )?,
                None => collect(
                    g,
                    ctx,
                    out,
                    images,
                    commands,
                    depth + 1,
                    image_budget,
                    expansion_budget,
                )?,
            },
            usvg::Node::Path(p) => {
                if let Some(mut sp) = convert_path(p, &Transform::default(), &group.abs_transform())
                {
                    // Fold the inherited clip/mask/blur into whatever pattern
                    // fields `convert_path` already produced.
                    // 把继承来的裁剪/遮罩/模糊，并入 `convert_path` 已经产出的
                    // 图案字段。
                    let (fill_pattern, stroke_pattern) = match sp.effects.take() {
                        Some(e) => (e.fill_pattern, e.stroke_pattern),
                        None => (None, None),
                    };
                    expansion_budget.charge(ctx)?;
                    for pattern in [&fill_pattern, &stroke_pattern].into_iter().flatten() {
                        expansion_budget.charge_subtree(&pattern.paths, &pattern.commands)?;
                    }
                    sp.effects = SvgEffects::some_if_present(
                        fill_pattern,
                        stroke_pattern,
                        ctx.clips.clone(),
                        ctx.mask.clone(),
                        ctx.blur.clone(),
                    );
                    commands.push(SvgCommand {
                        kind: 0,
                        index: out.len() as u32,
                        opacity: 1.0,
                    });
                    out.push(sp);
                }
            }
            usvg::Node::Image(img) => {
                if let Some(si) = convert_image(
                    img,
                    &group.abs_transform(),
                    ctx,
                    image_budget,
                    expansion_budget,
                )? {
                    commands.push(SvgCommand {
                        kind: 1,
                        index: images.len() as u32,
                        opacity: 1.0,
                    });
                    images.push(si);
                }
            }
            // `<text>` is silently skipped: usvg's `text` feature (needed to
            // flatten glyphs to outlines) is disabled to shrink the release
            // binary (see rust/Cargo.toml), so there is no glyph geometry to
            // collect here. No panic, no error — the shape is just absent
            // from the display list. The animation path's `<text>` support
            // (Flutter `TextPainter`-based) is unaffected.
            //
            // `<text>` 静默跳过：为缩小 release 体积（见 rust/Cargo.toml），
            // usvg 展平字形所需的 `text` feature 已关闭，这里没有字形几何可
            // 收集。不 panic、不报错——对应形状只是不出现在显示列表里。动画
            // 路径的 `<text>` 支持（基于 Flutter `TextPainter`）不受影响。
            usvg::Node::Text(_) => {}
        }
    }
    if opacity != 1.0 {
        close_opacity_layer(commands, layer_start);
    }
    Ok(())
}

/// Returns an [Inherited] extended by [g]'s own clip-path/mask/filter, or
/// `None` when [g] declares none of them (so the caller can keep passing the
/// parent context without cloning).
///
/// 返回被 [g] 自身的 clip-path/mask/filter 扩展过的 [Inherited]；若 [g] 三者
/// 皆无则返回 `None`（调用方可直接沿用父上下文，避免克隆）。
fn extend_inherited(
    ctx: &Inherited,
    g: &usvg::Group,
    expansion_budget: &mut ExpansionBudget,
) -> Result<Option<Inherited>, String> {
    let clip = g.clip_path();
    let mask = g.mask();
    let blur = gaussian_blur_of(g);
    if clip.is_none() && mask.is_none() && blur.is_none() {
        return Ok(None);
    }
    let base = g.abs_transform();
    let mut next = ctx.clone();
    if let Some(c) = clip {
        build_clips(c, &base, &mut next.clips);
    }
    // Nearest-ancestor-wins for mask and blur: nesting either of them would
    // need a real layer tree, which the flat display list deliberately does
    // not have. Documented as a limitation.
    //
    // 遮罩与模糊按"最近祖先优先"处理：真要嵌套需要完整的图层树，而扁平显示
    // 列表刻意不做这层结构。作为限制如实记录。
    if let Some(m) = mask {
        next.mask = build_mask(m, &base, expansion_budget)?;
    }
    if let Some(b) = blur {
        next.blur = Some(b);
    }
    Ok(Some(next))
}

/// Extracts the `feGaussianBlur` sigma of [g]'s filter, in absolute-space
/// units, when its filter list is exactly one filter holding exactly one
/// Gaussian-blur primitive. Any other filter shape yields `None` (MVP scope —
/// other primitives are future work).
///
/// 当 [g] 的滤镜列表恰好是一个滤镜、且其中恰好只有一个高斯模糊图元时，取出其
/// sigma（已换算到绝对坐标空间）。其他形态一律返回 `None`（MVP 范围——其他
/// 图元列为后续工作）。
fn gaussian_blur_of(g: &usvg::Group) -> Option<SvgBlur> {
    let filters = g.filters();
    if filters.len() != 1 {
        return None;
    }
    let primitives = filters[0].primitives();
    if primitives.len() != 1 {
        return None;
    }
    let usvg::filter::Kind::GaussianBlur(blur) = primitives[0].kind() else {
        return None;
    };
    // stdDeviation is in the filtered element's user space; the display list
    // is in absolute space, so scale by the transform's per-axis magnitude.
    //
    // stdDeviation 处于被滤元素的用户空间；显示列表是绝对空间，因此按变换在
    // 各轴上的缩放量换算。
    let t = g.abs_transform();
    let sx = (t.sx * t.sx + t.ky * t.ky).sqrt();
    let sy = (t.kx * t.kx + t.sy * t.sy).sqrt();
    let x = blur.std_dev_x().get() * sx;
    let y = blur.std_dev_y().get() * sy;
    (x.is_finite() && y.is_finite()).then_some(SvgBlur {
        std_dev_x: x,
        std_dev_y: y,
    })
}

/// Appends [clip] (and any `clip-path` chained onto it) to [out] as
/// absolute-space regions, given the referencing element's [base] transform.
///
/// 给定引用元素的 [base] 变换，把 [clip]（以及链在其上的 `clip-path`）作为
/// 绝对空间区域追加进 [out]。
fn build_clips(clip: &usvg::ClipPath, base: &Transform, out: &mut Vec<SvgClip>) {
    build_clips_at_depth(clip, base, out, 0);
}

fn build_clips_at_depth(
    clip: &usvg::ClipPath,
    base: &Transform,
    out: &mut Vec<SvgClip>,
    depth: usize,
) {
    if depth >= MAX_DEPTH {
        return;
    }
    if let Some(nested) = clip.clip_path() {
        build_clips_at_depth(nested, base, out, depth + 1);
    }
    let t = base.pre_concat(clip.transform());
    let mut region = SvgClip {
        verbs: Vec::new(),
        points: Vec::new(),
        even_odd: false,
    };
    // A clipPath's children are all flattened into one verbs/points buffer
    // with a single fill-rule flag — [SvgClip] has no per-subpath fill rule.
    // `saw_evenodd`/`saw_nonzero` track whether that single flag can be
    // trusted: only when EVERY child agrees on even-odd is `even_odd = true`
    // correct. A mix (e.g. one evenodd child overlapping one nonzero child)
    // falls back to nonzero, which behaves as a plain union for the common
    // case of same-wound, non-self-intersecting children — wrong only for a
    // self-intersecting *nonzero* child mixed with an evenodd sibling, a
    // narrower miss than XOR-cancelling genuinely disjoint children's overlap.
    //
    // 一个 clipPath 的所有子形状被压平进同一份 verbs/points 缓冲，配一个单一
    // 的填充规则标志——[SvgClip] 没有逐子路径的填充规则。`saw_evenodd`/
    // `saw_nonzero` 用来判断这单一标志是否可信：只有*所有*子元素都用
    // even-odd 时，`even_odd = true` 才是对的。混用（例如一个 evenodd 子形状
    // 与一个 nonzero 子形状重叠）回退为 nonzero——对同向缠绕、自身不相交的
    // 子形状而言表现等同于普通并集，仅在"自相交的 nonzero 子形状与 evenodd
    // 兄弟混用"这种更窄的场景下仍不准确，比把本应不相交子形状的重叠区域
    // XOR 抵消掉的原错误范围更小。
    let mut saw_evenodd = false;
    let mut saw_nonzero = false;
    append_clip_geometry(
        clip.root(),
        &t,
        &mut region,
        &mut saw_evenodd,
        &mut saw_nonzero,
        0,
    );
    region.even_odd = saw_evenodd && !saw_nonzero;
    if !region.verbs.is_empty() && region.points.iter().all(|v| v.is_finite()) {
        out.push(region);
    }
}

/// Flattens every shape under [group] into [region] as one union path,
/// tracking each child's fill rule into [saw_evenodd]/[saw_nonzero] — see
/// [build_clips] for how those settle [region]'s single `even_odd` flag.
///
/// 把 [group] 下的每个形状展平进 [region]，合成一条并集路径，并把每个子元素的
/// 填充规则记录进 [saw_evenodd]/[saw_nonzero]——[region] 单一 `even_odd`
/// 标志如何由二者敲定见 [build_clips]。
fn append_clip_geometry(
    group: &usvg::Group,
    base: &Transform,
    region: &mut SvgClip,
    saw_evenodd: &mut bool,
    saw_nonzero: &mut bool,
    depth: usize,
) {
    if depth >= MAX_DEPTH {
        return;
    }
    for node in group.children() {
        match node {
            usvg::Node::Group(g) => {
                append_clip_geometry(g, base, region, saw_evenodd, saw_nonzero, depth + 1)
            }
            usvg::Node::Path(p) => {
                let t = base.pre_concat(p.abs_transform());
                append_segments(p, &t, &mut region.verbs, &mut region.points);
                if let Some(f) = p.fill() {
                    if matches!(f.rule(), usvg::FillRule::EvenOdd) {
                        *saw_evenodd = true;
                    } else {
                        *saw_nonzero = true;
                    }
                }
            }
            _ => {}
        }
    }
}

/// Resolves [mask] into absolute-space content, given the referencing
/// element's [base] transform.
///
/// 给定引用元素的 [base] 变换，把 [mask] 解析为绝对空间的内容。
fn build_mask(
    mask: &usvg::Mask,
    base: &Transform,
    expansion_budget: &mut ExpansionBudget,
) -> Result<Option<SvgMask>, String> {
    build_mask_at_depth(mask, base, 0, expansion_budget)
}

fn build_mask_at_depth(
    mask: &usvg::Mask,
    base: &Transform,
    depth: usize,
    expansion_budget: &mut ExpansionBudget,
) -> Result<Option<SvgMask>, String> {
    if depth >= MAX_DEPTH {
        return Ok(None);
    }
    let r = mask.rect();
    let corners = [
        map(base, Point::from_xy(r.x(), r.y())),
        map(base, Point::from_xy(r.right(), r.y())),
        map(base, Point::from_xy(r.x(), r.bottom())),
        map(base, Point::from_xy(r.right(), r.bottom())),
    ];
    if !corners.iter().all(|(x, y)| x.is_finite() && y.is_finite()) {
        return Ok(None);
    }
    let left = corners.iter().map(|c| c.0).fold(f32::INFINITY, f32::min);
    let top = corners.iter().map(|c| c.1).fold(f32::INFINITY, f32::min);
    let right = corners
        .iter()
        .map(|c| c.0)
        .fold(f32::NEG_INFINITY, f32::max);
    let bottom = corners
        .iter()
        .map(|c| c.1)
        .fold(f32::NEG_INFINITY, f32::max);
    if !(right - left).is_finite() || !(bottom - top).is_finite() {
        return Ok(None);
    }
    let mut paths = Vec::new();
    let mut commands = Vec::new();
    append_subtree_commands(mask.root(), base, &mut paths, &mut commands, 0);
    finish_commands(&mut commands);
    // usvg exposes a mask linked on the <mask> itself via Mask::mask().
    // Preserve that chain through the existing per-path effects field; no
    // new wire fields. Dart's current `nested: true` replay remains naive
    // (doc/animation-engine-features.md); this is Rust-side preservation.
    if let Some(nested_mask) = mask.mask() {
        if let Some(nested) = build_mask_at_depth(nested_mask, base, depth + 1, expansion_budget)? {
            for path in &mut paths {
                expansion_budget.charge_subtree(&nested.paths, &nested.commands)?;
                let effects = path.effects.get_or_insert_with(|| SvgEffects {
                    fill_pattern: None,
                    stroke_pattern: None,
                    clips: Vec::new(),
                    mask: None,
                    blur: None,
                });
                effects.mask = Some(nested.clone());
            }
        }
    }
    Ok(Some(SvgMask {
        kind: match mask.kind() {
            usvg::MaskType::Alpha => 1,
            _ => 0,
        },
        x: left,
        y: top,
        width: right - left,
        height: bottom - top,
        paths,
        commands,
    }))
}

/// Keeps subroot composition as base × leaf abs_transform. Unlike the main
/// tree, usvg's push_pattern_transform only updates the wrapper group, leaving
/// descendants unchanged (paint_server.rs TODO). Existing tile replay relies
/// on those leaf values; objectBoundingBox content rendering remains a separate,
/// pre-existing limitation.
/// 子根保持 base × 叶子 abs_transform。与主树不同，usvg 的
/// push_pattern_transform 只更新包裹组，未更新后代（paint_server.rs 的 TODO）。
/// 现有贴片重放依赖这些叶子值；objectBoundingBox 内容渲染不正确是另一个既有问题。
#[cfg(test)]
fn append_subtree_paths_at_depth(
    group: &usvg::Group,
    base: &Transform,
    out: &mut Vec<SvgPath>,
    depth: usize,
) {
    append_subtree_commands(group, base, out, &mut Vec::new(), depth);
}

/// 收集子根的路径及 opacity 边界，保持叶子的原有坐标变换。
fn append_subtree_commands(
    group: &usvg::Group,
    base: &Transform,
    out: &mut Vec<SvgPath>,
    commands: &mut Vec<SvgCommand>,
    depth: usize,
) {
    if depth >= MAX_DEPTH {
        return;
    }
    let opacity = group.opacity().get();
    if opacity == 0.0 {
        return;
    }
    let layer_start = commands.len();
    if opacity != 1.0 {
        commands.push(SvgCommand {
            kind: 2,
            index: 0,
            opacity,
        });
    }
    for node in group.children() {
        match node {
            usvg::Node::Group(g) => append_subtree_commands(g, base, out, commands, depth + 1),
            usvg::Node::Path(p) => {
                if let Some(sp) = convert_path(p, base, &p.abs_transform()) {
                    commands.push(SvgCommand {
                        kind: 0,
                        index: out.len() as u32,
                        opacity: 1.0,
                    });
                    out.push(sp);
                }
            }
            // usvg does retain images in mask/pattern subtrees. Intentionally
            // omit them: mask images and naive pattern/mask subroot replay
            // are documented limitations (animation-engine-features.md).
            usvg::Node::Image(_) | usvg::Node::Text(_) => {}
        }
    }
    if opacity != 1.0 {
        close_opacity_layer(commands, layer_start);
    }
}

/// Converts a usvg `<image>` node into an [SvgImage]. Nested-SVG images
/// (`ImageKind::SVG`) are skipped (returns `None`) — out of scope for this
/// pass, no nested display-list flattening. [parent_abs] is the direct parent
/// group's absolute transform, equal to a normal image's absolute transform.
///
/// 把 usvg `<image>` 节点转成 [SvgImage]。嵌套 SVG 的 image
/// （`ImageKind::SVG`）跳过（返回 `None`）——本轮不做嵌套显示列表展平。
/// [parent_abs] 是直接父组的绝对变换，与普通图片自身的绝对变换相同。
fn convert_image(
    img: &usvg::Image,
    parent_abs: &Transform,
    ctx: &Inherited,
    image_budget: &mut usize,
    expansion_budget: &mut ExpansionBudget,
) -> Result<Option<SvgImage>, String> {
    let (data, format) = match img.kind() {
        usvg::ImageKind::PNG(d) => (d.as_ref(), SvgImageFormat::Png),
        usvg::ImageKind::JPEG(d) => (d.as_ref(), SvgImageFormat::Jpeg),
        usvg::ImageKind::GIF(d) => (d.as_ref(), SvgImageFormat::Gif),
        usvg::ImageKind::WEBP(d) => (d.as_ref(), SvgImageFormat::Webp),
        usvg::ImageKind::SVG(_) => return Ok(None),
    };
    // Ship the local object bbox plus the full `abs_transform` matrix rather
    // than pre-mapping two corners into an axis-aligned absolute rect: the
    // latter can't represent a rotated/skewed ancestor transform (see
    // [SvgImage.matrix] doc comment) — `convert_path` avoids the same trap by
    // mapping every point individually instead of just a bbox's corners.
    //
    // 传出本地物体包围盒加完整的 `abs_transform` 矩阵，而非预先把两角点映射成
    // 轴对齐的绝对矩形：后者无法表达旋转/斜切的祖先变换（见 [SvgImage.matrix]
    // 文档注释）——`convert_path` 靠逐点映射而非只取包围盒两角点，避开了同样
    // 的陷阱。
    let t = *parent_abs;
    if !transform_to_vec6(&t).iter().all(|v| v.is_finite()) {
        return Ok(None);
    }
    // usvg already shares these encoded bytes in Arc<Vec<u8>>. The existing
    // wire protocol requires a byte list per image, so charge BEFORE cloning.
    // Count each occurrence (including <use> of the same Arc) against 64 MiB.
    // Exceeding this output budget silently skips that image: Ok(None), not Err.
    if data.len() > *image_budget {
        return Ok(None);
    }
    expansion_budget.charge(ctx)?;
    *image_budget -= data.len();
    let data = data.clone();
    let bbox = img.bounding_box();
    Ok(Some(SvgImage {
        x: bbox.left(),
        y: bbox.top(),
        width: bbox.width(),
        height: bbox.height(),
        matrix: transform_to_vec6(&t),
        data,
        format,
        clips: ctx.clips.clone(),
        mask: ctx.mask.clone(),
        blur: ctx.blur.clone(),
    }))
}

/// Maps a point through [t] into absolute space. / 用 [t] 把点映射到绝对坐标。
fn map(t: &Transform, p: Point) -> (f32, f32) {
    let mut a = [p];
    t.map_points(&mut a);
    (a[0].x, a[0].y)
}

/// Flattens [t] into the 6-element `[sx, ky, kx, sy, tx, ty]` vector the
/// Dart side expects for pattern/radial-gradient matrices.
///
/// 把 [t] 展平为 Dart 侧期望的图案/径向渐变矩阵的 6 元素
/// `[sx, ky, kx, sy, tx, ty]` 向量。
fn transform_to_vec6(t: &Transform) -> Vec<f32> {
    vec![t.sx, t.ky, t.kx, t.sy, t.tx, t.ty]
}

/// Appends [p]'s segments, mapped through [t], onto [verbs]/[points].
///
/// Reads tiny-skia's two parallel arrays (`verbs()`/`points()`) directly instead
/// of driving the `segments()` iterator. tiny-skia documents `Path` as "compact
/// storage, where segment types and numbers are stored separately", and the
/// points array is already in exactly the order this wire format wants (move 1,
/// line 1, quad 2, cubic 3, close 0 points) — so the iterator's per-segment
/// last-point/last-move bookkeeping was pure overhead, and the raw slices give
/// exact lengths to reserve up front instead of growing both Vecs by doubling.
///
/// The verb translation is fed to `Vec::extend` rather than a `reserve` + `push`
/// loop: `Map<slice::Iter<_>, _>` is `TrustedLen`, so `extend` takes std's
/// `extend_trusted` path — one exact `reserve`, then raw pointer writes with no
/// per-element capacity check or length update.
///
/// 直接读 tiny-skia 的两个平行数组（`verbs()`/`points()`），不再驱动
/// `segments()` 迭代器。tiny-skia 文档写明 `Path` 是"紧凑存储，段类型与数值
/// 分开存放"，而点数组的顺序恰好就是本 wire 格式要的顺序（move 1 点、line 1
/// 点、quad 2 点、cubic 3 点、close 0 点）——因此迭代器那套 last-point/
/// last-move 记账纯属额外开销，且拿到裸切片就能提前按精确长度 reserve，
/// 不必让两个 Vec 靠翻倍扩容长大。
///
/// 动词转换交给 `Vec::extend` 而不是 `reserve` + `push` 循环：
/// `Map<slice::Iter<_>, _>` 实现了 `TrustedLen`，`extend` 因此走 std 的
/// `extend_trusted` 分支——只做一次精确 `reserve`，随后用裸指针写入，
/// 每个元素都不再有容量检查与长度自增。
fn append_segments(p: &usvg::Path, t: &Transform, verbs: &mut Vec<u8>, points: &mut Vec<f32>) {
    use usvg::tiny_skia_path::PathVerb;

    let data = p.data();
    verbs.extend(data.verbs().iter().map(|v| match v {
        PathVerb::Move => 0u8,
        PathVerb::Line => 1,
        PathVerb::Quad => 2,
        PathVerb::Cubic => 3,
        PathVerb::Close => 4,
    }));
    append_mapped_points(t, data.points(), points);
}

/// Appends [src] mapped through [t] as flattened x,y pairs onto [out].
///
/// Dispatches on the transform's shape *once for the whole slice* — the same
/// four cases `Transform::map_points` picks between, in the same order and with
/// the same arithmetic, so the output is bit-identical to the previous
/// point-at-a-time `map_points(&mut [pt])` calls, which redid that dispatch per
/// point (and, at `opt-level = "z"`, paid a real call per point too).
///
/// Each branch emits its two coordinates as a `[f32; 2]` through `flat_map` and
/// hands the result to `Vec::extend`. That iterator is `TrustedLen` — std has
/// `unsafe impl TrustedLen for FlattenCompat<I, array::IntoIter<T, N>> where
/// I: TrustedLen<Item = [T; N]>` — so `extend` reserves once for the exact final
/// length and then writes through a raw pointer, instead of the `push`-per-
/// coordinate form which re-checked capacity and bumped the length 2× per point.
/// The arithmetic per coordinate is unchanged, so output stays bit-identical.
///
/// 把 [src] 经 [t] 映射后作为扁平 x,y 对追加到 [out]。
///
/// **对整个切片只做一次**变换形态分派——与 `Transform::map_points` 内部相同的
/// 四个分支、相同顺序、相同算式，因此输出与此前逐点调用
/// `map_points(&mut [pt])` 的结果逐位一致；而那种写法每个点都要重做一次分派
/// （在 `opt-level = "z"` 下还要真的付一次函数调用）。
///
/// 每个分支都用 `flat_map` 把两个坐标产出为 `[f32; 2]`，再交给 `Vec::extend`。
/// 该迭代器是 `TrustedLen`——std 有
/// `unsafe impl TrustedLen for FlattenCompat<I, array::IntoIter<T, N>> where
/// I: TrustedLen<Item = [T; N]>`——因此 `extend` 按最终精确长度只 reserve 一次，
/// 之后通过裸指针写入；而原先逐坐标 `push` 的写法，每个点都要做两次容量检查与
/// 两次长度自增。每个坐标的算式没有改变，输出仍然逐位一致。
fn append_mapped_points(t: &Transform, src: &[Point], out: &mut Vec<f32>) {
    if t.is_identity() {
        out.extend(src.iter().flat_map(|p| [p.x, p.y]));
    } else if t.is_translate() {
        out.extend(src.iter().flat_map(|p| [p.x + t.tx, p.y + t.ty]));
    } else if t.is_scale_translate() {
        out.extend(
            src.iter()
                .flat_map(|p| [p.x * t.sx + t.tx, p.y * t.sy + t.ty]),
        );
    } else {
        out.extend(src.iter().flat_map(|p| {
            [
                p.x * t.sx + p.y * t.kx + t.tx,
                p.x * t.ky + p.y * t.sy + t.ty,
            ]
        }));
    }
}

/// Converts a usvg path into an [SvgPath] with baked-in transform.
///
/// [base] is pre-multiplied onto the caller-selected [node_abs]: the direct
/// parent's absolute transform in the main tree (see [collect] for usvg's
/// background Path inconsistency), or the leaf's own value in subroots (see
/// [append_subtree_paths_at_depth] for usvg's pattern wrapper inconsistency).
/// Pass identity as [base] for the main tree, the referencing element's absolute
/// transform for masks, and identity for pattern-local tile content.
///
/// The returned path's [SvgPath::effects] carries only its own fill/stroke
/// pattern (if any) — [collect] folds in the inherited clip/mask/blur from
/// the group context.
///
/// 把 usvg 路径转成已烘焙 transform 的 [SvgPath]。
///
/// [base] 会预乘到调用方选择的 [node_abs] 上：主树传直接父组的绝对变换
/// （usvg 背景 Path 的不一致见 [collect]），子根传叶子自身的值（usvg 图案
/// 包裹组的不一致见 [append_subtree_paths_at_depth]）。主树的 [base] 传单位矩阵，
/// 遮罩传引用元素的绝对变换，图案贴片的局部内容传单位矩阵。
///
/// 返回值的 [SvgPath::effects] 只带自身的填充/描边图案（如果有）——继承的
/// 裁剪/遮罩/模糊由 [collect] 按分组上下文并入。
fn convert_path(p: &usvg::Path, base: &Transform, node_abs: &Transform) -> Option<SvgPath> {
    let t = base.pre_concat(*node_abs);
    let mut verbs = Vec::new();
    let mut points = Vec::new();
    append_segments(p, &t, &mut verbs, &mut points);
    if !points.iter().all(|v| v.is_finite()) {
        return None;
    }

    let (has_fill, fill_argb, even_odd, fill_gradient, fill_pattern) = match p.fill() {
        Some(f) => {
            let (argb, gradient, pattern) = resolve_paint(f.paint(), &t, f.opacity().get());
            (
                true,
                argb,
                matches!(f.rule(), usvg::FillRule::EvenOdd),
                gradient,
                pattern,
            )
        }
        None => (false, 0, false, None, None),
    };
    let (has_stroke, stroke_argb, stroke_width, stroke_gradient, stroke_pattern) = match p.stroke()
    {
        Some(s) => {
            let (argb, gradient, pattern) = resolve_paint(s.paint(), &t, s.opacity().get());
            (true, argb, s.width().get(), gradient, pattern)
        }
        None => (false, 0, 0.0, None, None),
    };

    let stroke_first = matches!(p.paint_order(), usvg::PaintOrder::StrokeAndFill);

    Some(SvgPath {
        verbs,
        points,
        has_fill,
        fill_argb,
        even_odd,
        has_stroke,
        stroke_argb,
        stroke_width,
        stroke_first,
        fill_gradient,
        stroke_gradient,
        effects: SvgEffects::some_if_present(fill_pattern, stroke_pattern, Vec::new(), None, None),
    })
}

/// Builds an [SvgPattern] when [paint] is a `<pattern>` paint server.
///
/// usvg has already normalized `patternUnits`/`patternContentUnits` to user
/// space by the time the tree is public, so `rect()` and the tile contents
/// share the pattern's local space; [abs] (the referencing path's absolute
/// transform) composed with the pattern's own `transform()` maps that space
/// into the display list's absolute space.
/// Tile replay preserves leaf transforms (see [append_subtree_paths_at_depth]);
/// objectBoundingBox content units still have a pre-existing rendering defect.
///
/// 当 [paint] 是 `<pattern>` paint server 时构建 [SvgPattern]。
///
/// 树公开时 usvg 已把 `patternUnits`/`patternContentUnits` 归一到用户空间，因此
/// `rect()` 与贴片内容共享图案的局部空间；[abs]（引用路径的绝对变换）与图案
/// 自身的 `transform()` 组合后，即可把该空间映射到显示列表的绝对空间。
/// 贴片重放保留叶子变换（见 [append_subtree_paths_at_depth]）；objectBoundingBox
/// 内容单位仍有既有的渲染缺陷。
fn build_pattern(paint: &usvg::Paint, abs: &Transform) -> Option<SvgPattern> {
    let usvg::Paint::Pattern(pattern) = paint else {
        return None;
    };
    let combined = abs.pre_concat(pattern.transform());
    if !transform_to_vec6(&combined).iter().all(|v| v.is_finite()) {
        return None;
    }
    let rect = pattern.rect();
    let mut paths = Vec::new();
    let mut commands = Vec::new();
    append_subtree_commands(
        pattern.root(),
        &Transform::default(),
        &mut paths,
        &mut commands,
        0,
    );
    finish_commands(&mut commands);
    Some(SvgPattern {
        id: pattern.id().to_string(),
        x: rect.x(),
        y: rect.y(),
        width: rect.width(),
        height: rect.height(),
        matrix: transform_to_vec6(&combined),
        paths,
        commands,
    })
}

/// Builds an [SvgGradient] when [paint] is a linear/radial gradient, resolving
/// its geometry into the same absolute space as the path's own points.
///
/// [abs] is the path's `abs_transform()`. The gradient's own `transform()`
/// (which usvg has already pre-multiplied with the `objectBoundingBox`→bbox
/// scale, verified empirically against `resvg`'s rasterized output — see
/// xvg CLAUDE.md for the investigation) is combined via
/// `abs.pre_concat(gradient.transform())`, matching `abs.map(gradient
/// .transform().map(point))` — i.e. gradient-local point → gradient's resolved
/// user space → this path's absolute space, the same chain [convert_path]
/// uses for its own geometry.
///
/// `Linear` bakes this combined transform directly into its two endpoints
/// (an affine map is fully determined by where it sends two points). `Radial`
/// cannot do the same for `r` (a scalar can't capture an anisotropic bbox
/// scale turning the circle into an ellipse), so it ships the combined
/// transform as a matrix instead, for the Dart side to apply via
/// `ui.Gradient.radial`'s `matrix4`.
///
/// 当 [paint] 是线性/径向渐变时构建 [SvgGradient]，把其几何解析到与路径自身
/// 点集相同的绝对空间。
///
/// [abs] 是路径的 `abs_transform()`。渐变自身的 `transform()`（usvg 已把
/// `objectBoundingBox`→bbox 缩放预乘在内，已通过对照 `resvg` 光栅化输出做过
/// 实测验证——调查过程见 xvg CLAUDE.md）通过
/// `abs.pre_concat(gradient.transform())` 组合，等价于
/// `abs.map(gradient.transform().map(point))`——即渐变局部坐标点 → 渐变已解析
/// 的用户空间 → 该路径的绝对空间，与 [convert_path] 处理自身几何的链路一致。
///
/// `Linear` 把该组合变换直接烘焙进两个端点（仿射变换由其对两点的映射结果
/// 完全确定）。`Radial` 无法对 `r` 做同样处理（标量无法表达把圆变成椭圆的
/// 非均匀 bbox 缩放），因此改为把组合变换以矩阵形式传出，供 Dart 侧通过
/// `ui.Gradient.radial` 的 `matrix4` 应用。
fn build_gradient(paint: &usvg::Paint, abs: &Transform, opacity: f32) -> Option<SvgGradient> {
    match paint {
        usvg::Paint::LinearGradient(lg) => {
            let combined = abs.pre_concat(lg.transform());
            let (x1, y1) = map(&combined, Point::from_xy(lg.x1(), lg.y1()));
            let (x2, y2) = map(&combined, Point::from_xy(lg.x2(), lg.y2()));
            if ![x1, y1, x2, y2].iter().all(|v| v.is_finite()) {
                return None;
            }
            Some(SvgGradient {
                kind: 0,
                x1,
                y1,
                x2,
                y2,
                radius: 0.0,
                matrix: Vec::new(),
                stops: convert_gradient_stops(lg.stops(), opacity),
                spread: spread_to_u8(lg.spread_method()),
            })
        }
        usvg::Paint::RadialGradient(rg) => {
            let combined = abs.pre_concat(rg.transform());
            if !transform_to_vec6(&combined).iter().all(|v| v.is_finite()) {
                return None;
            }
            Some(SvgGradient {
                kind: 1,
                x1: rg.fx(),
                y1: rg.fy(),
                x2: rg.cx(),
                y2: rg.cy(),
                radius: rg.r().get(),
                matrix: transform_to_vec6(&combined),
                stops: convert_gradient_stops(rg.stops(), opacity),
                spread: spread_to_u8(rg.spread_method()),
            })
        }
        _ => None,
    }
}

/// Converts usvg gradient stops, baking each stop's own `stop-opacity` and the
/// paint's overall [opacity] into its alpha channel.
///
/// 转换 usvg 渐变色标，把每个色标自身的 `stop-opacity` 与 paint 整体
/// [opacity] 一并烘焙进 alpha 通道。
fn convert_gradient_stops(stops: &[usvg::Stop], opacity: f32) -> Vec<SvgGradientStop> {
    stops
        .iter()
        .map(|s| {
            let c = s.color();
            let a = ((s.opacity().get() * opacity).clamp(0.0, 1.0) * 255.0).round() as u32;
            SvgGradientStop {
                offset: s.offset().get(),
                color_argb: argb(a, c.red, c.green, c.blue),
            }
        })
        .collect()
}

/// Packs 8-bit channels into a 0xAARRGGBB word.
///
/// 把 8 位通道打包为 0xAARRGGBB 字。
fn argb(a: u32, r: u8, g: u8, b: u8) -> u32 {
    (a << 24) | ((r as u32) << 16) | ((g as u32) << 8) | (b as u32)
}

/// Maps usvg's `SpreadMethod` to the wire encoding (0=pad, 1=reflect, 2=repeat).
///
/// 把 usvg 的 `SpreadMethod` 映射为线路编码（0=pad，1=reflect，2=repeat）。
fn spread_to_u8(s: usvg::SpreadMethod) -> u8 {
    match s {
        usvg::SpreadMethod::Pad => 0,
        usvg::SpreadMethod::Reflect => 1,
        usvg::SpreadMethod::Repeat => 2,
    }
}

/// Resolves a paint to a solid 0xAARRGGBB; gradients use their first stop
/// (spike limitation), patterns fall back to grey.
///
/// 把 paint 解析为实色 0xAARRGGBB；渐变取首个色标（spike 限制），
/// 图案回退灰色。
/// Resolves one `usvg::Paint` (a fill or a stroke) into the flat ARGB fallback
/// color plus its gradient/pattern shader, if any — the three calls that
/// `convert_path` needs for either its fill or its stroke.
///
/// 把一个 `usvg::Paint`（填充或描边）解析为纯色 ARGB 兜底值，加上它的渐变/图案
/// shader（如果有）——`convert_path` 无论处理填充还是描边都需要这三次调用。
fn resolve_paint(
    paint: &usvg::Paint,
    t: &Transform,
    opacity: f32,
) -> (u32, Option<SvgGradient>, Option<SvgPattern>) {
    (
        paint_argb(paint, opacity),
        build_gradient(paint, t, opacity),
        build_pattern(paint, t),
    )
}

fn paint_argb(paint: &usvg::Paint, opacity: f32) -> u32 {
    let (r, g, b) = match paint {
        usvg::Paint::Color(c) => (c.red, c.green, c.blue),
        usvg::Paint::LinearGradient(lg) => stop_rgb(lg.stops()),
        usvg::Paint::RadialGradient(rg) => stop_rgb(rg.stops()),
        usvg::Paint::Pattern(_) => (128, 128, 128),
    };
    let a = (opacity.clamp(0.0, 1.0) * 255.0).round() as u32;
    argb(a, r, g, b)
}

/// First gradient stop color, or black. / 渐变首个色标颜色，否则黑。
fn stop_rgb(stops: &[usvg::Stop]) -> (u8, u8, u8) {
    match stops.first() {
        Some(s) => {
            let c = s.color();
            (c.red, c.green, c.blue)
        }
        None => (0, 0, 0),
    }
}

/// Parses any CSS3/SVG colour string (`red`, `cornflowerblue`, `#RGB`,
/// `#RRGGBB`, `rgb()`, `rgba()`, `hsl()`, ...) into RGBA bytes, or returns
/// `None` when the string isn't a colour.
///
/// Exists so the Dart animation engine doesn't have to carry its own CSS
/// named-colour table: `svgtypes` (the crate usvg parses with) already has
/// the complete one. Called once per attribute at document-parse time, never
/// per animation frame.
///
/// 把任意 CSS3/SVG 颜色字符串（`red`、`cornflowerblue`、`#RGB`、`#RRGGBB`、
/// `rgb()`、`rgba()`、`hsl()` 等）解析为 RGBA 字节；不是颜色时返回 `None`。
///
/// 存在的意义是让 Dart 动画引擎不必自带一张 CSS 具名颜色表——`svgtypes`
/// （usvg 自身解析用的 crate）已经有完整的一张。只在文档解析阶段按属性调用
/// 一次，绝不在每一动画帧调用。
///
/// Example:
/// ```dart
/// final rgba = parseColor(s: 'cornflowerblue'); // [100, 149, 237, 255]
/// ```
///
/// Returns a 4-element `Vec<u8>` rather than `[u8; 4]` on purpose: FRB maps a
/// fixed-size array to its `U8Array4` wrapper, which drags
/// `package:collection` into the generated Dart and trips
/// `depend_on_referenced_packages` unless it's declared in `pubspec.yaml`.
/// A plain `Vec<u8>` maps to `Uint8List` with no new dependency.
///
/// 刻意返回 4 元素的 `Vec<u8>` 而非 `[u8; 4]`：FRB 会把定长数组映射成其
/// `U8Array4` 包装类型，从而给生成的 Dart 代码引入 `package:collection`，除非
/// 在 `pubspec.yaml` 里声明它，否则触发 `depend_on_referenced_packages` 告警。
/// 普通 `Vec<u8>` 映射为 `Uint8List`，不引入新依赖。
#[flutter_rust_bridge::frb(sync)]
pub fn parse_color(s: String) -> Option<Vec<u8>> {
    let c: svgtypes::Color = s.trim().parse().ok()?;
    Some(vec![c.red, c.green, c.blue, c.alpha])
}

/// Parses a full SVG `transform` list (`translate(10,20) rotate(45) scale(2)`,
/// `matrix(...)`, `skewX(...)`, ...) into the composed affine matrix
/// `[a, b, c, d, e, f]`, or `None` when the string is malformed.
///
/// Components compose left-to-right exactly as SVG specifies, and
/// `rotate(a cx cy)` is expanded to translate/rotate/translate by the
/// underlying grammar. Called once per `transform` attribute at
/// document-parse time, never per animation frame.
///
/// 把完整的 SVG `transform` 列表（`translate(10,20) rotate(45) scale(2)`、
/// `matrix(...)`、`skewX(...)` 等）解析为合成后的仿射矩阵 `[a, b, c, d, e, f]`；
/// 字符串非法时返回 `None`。
///
/// 各分量按 SVG 规范从左到右合成，`rotate(a cx cy)` 由底层语法自动展开为
/// translate/rotate/translate。只在文档解析阶段按 `transform` 属性调用一次，
/// 绝不在每一动画帧调用。
///
/// Example:
/// ```dart
/// final m = parseTransform(s: 'translate(10,20)'); // [1, 0, 0, 1, 10, 20]
/// ```
#[flutter_rust_bridge::frb(sync)]
pub fn parse_transform(s: String) -> Option<Vec<f32>> {
    let mut m = svgtypes::Transform::default();
    let mut seen = false;
    for token in svgtypes::TransformListParser::from(s.trim()) {
        let token = token.ok()?;
        m = concat(m, token_matrix(token));
        seen = true;
    }
    if !seen {
        return None;
    }
    let result = vec![
        m.a as f32, m.b as f32, m.c as f32, m.d as f32, m.e as f32, m.f as f32,
    ];
    result.iter().all(|v| v.is_finite()).then_some(result)
}

/// One `<transform-list>` token as a bare affine matrix.
///
/// 单个 `<transform-list>` 词法单元对应的裸仿射矩阵。
fn token_matrix(token: svgtypes::TransformListToken) -> svgtypes::Transform {
    use svgtypes::Transform as T;
    use svgtypes::TransformListToken as Tok;
    match token {
        Tok::Matrix { a, b, c, d, e, f } => T::new(a, b, c, d, e, f),
        Tok::Translate { tx, ty } => T::new(1.0, 0.0, 0.0, 1.0, tx, ty),
        Tok::Scale { sx, sy } => T::new(sx, 0.0, 0.0, sy, 0.0, 0.0),
        Tok::Rotate { angle } => {
            let (sin, cos) = angle.to_radians().sin_cos();
            T::new(cos, sin, -sin, cos, 0.0, 0.0)
        }
        Tok::SkewX { angle } => T::new(1.0, 0.0, angle.to_radians().tan(), 1.0, 0.0, 0.0),
        Tok::SkewY { angle } => T::new(1.0, angle.to_radians().tan(), 0.0, 1.0, 0.0, 0.0),
    }
}

/// Post-multiplies [b] onto [a] (`a * b`), i.e. [b] applies in [a]'s
/// coordinate system — the composition order an SVG transform list uses.
///
/// 把 [b] 右乘到 [a] 上（`a * b`），即 [b] 作用在 [a] 的坐标系里——SVG
/// transform 列表所用的合成顺序。
fn concat(a: svgtypes::Transform, b: svgtypes::Transform) -> svgtypes::Transform {
    svgtypes::Transform::new(
        a.a * b.a + a.c * b.b,
        a.b * b.a + a.d * b.b,
        a.a * b.c + a.c * b.d,
        a.b * b.c + a.d * b.d,
        a.a * b.e + a.c * b.f + a.e,
        a.b * b.e + a.d * b.f + a.f,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 解析静态测试内容，统一 viewport。
    fn opacity_scene(content: &str) -> SvgScene {
        parse_svg(
            format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'>{content}</svg>"
            ),
            None,
        )
        .unwrap()
    }

    #[test]
    fn opacity_commands_preserve_group_and_element_boundaries() {
        let scene = opacity_scene("<g opacity='.5'><rect width='30' height='30'/><rect x='10' width='30' height='30' opacity='.5' fill-opacity='.5'/></g><rect y='35' width='40' height='5'/>");
        let commands = &scene.commands;
        assert_eq!(
            commands.iter().map(|c| c.kind).collect::<Vec<_>>(),
            [2, 0, 2, 0, 3, 3, 0]
        );
        assert_eq!(
            commands
                .iter()
                .filter(|c| c.kind == 2)
                .map(|c| c.opacity)
                .collect::<Vec<_>>(),
            [0.5, 0.5]
        );
        assert_eq!(
            commands
                .iter()
                .filter(|c| c.kind == 0)
                .map(|c| c.index)
                .collect::<Vec<_>>(),
            [0, 1, 2]
        );
        assert_eq!(scene.paths[0].fill_argb >> 24, 255);
        assert_eq!(scene.paths[1].fill_argb >> 24, 128);
    }

    #[test]
    fn finish_commands_omits_ordinary_draws_but_keeps_layers() {
        let mut commands = vec![SvgCommand {
            kind: 0,
            index: 0,
            opacity: 1.0,
        }];
        finish_commands(&mut commands);
        assert!(commands.is_empty());
        assert!(
            opacity_scene("<g opacity='1'><rect width='10' height='10'/></g>")
                .commands
                .is_empty()
        );
        let scene = opacity_scene("<rect width='10' height='10' opacity='.5'/>");
        assert_eq!(scene.commands.len(), 3);
    }

    #[test]
    fn opacity_subroots_preserve_compositing_boundaries() {
        let scene = opacity_scene("<defs><mask id='m' mask-type='alpha'><g opacity='.5'><rect width='40' height='40' fill='white'/><rect width='20' height='40' fill='white'/></g></mask><pattern id='p' patternUnits='userSpaceOnUse' width='40' height='40'><g opacity='.5'><rect width='40' height='40'/><rect width='20' height='40'/></g></pattern></defs><rect width='40' height='40' fill='url(#p)' mask='url(#m)'/>");
        let effects = scene.paths[0].effects.as_ref().unwrap();
        for commands in [
            &effects.mask.as_ref().unwrap().commands,
            &effects.fill_pattern.as_ref().unwrap().commands,
        ] {
            assert_eq!(
                commands.iter().map(|c| c.kind).collect::<Vec<_>>(),
                [2, 0, 0, 3]
            );
            assert_eq!(commands[0].opacity, 0.5);
        }
    }

    #[test]
    fn opacity_commands_include_images_and_root() {
        let source = IMAGE_SVG.replace("<svg ", "<svg opacity='.5' ");
        let scene = parse_svg(source, None).unwrap();
        assert_eq!(
            scene.commands.iter().map(|c| c.kind).collect::<Vec<_>>(),
            [2, 1, 3]
        );
        assert_eq!(scene.commands[0].opacity, 0.5);
        assert_eq!(scene.commands[1].index, 0);
    }

    /// 空 opacity 组不能随遮罩或图案引用放大命令数。
    #[test]
    fn empty_opacity_groups_do_not_expand_commands() {
        let empty = "<g opacity='.5'/>".repeat(1000);
        let shape = "<rect width='40' height='40' fill='white'/>";
        for effect in ["mask", "nested-mask", "pattern"] {
            let content = match effect {
                "mask" => format!("<defs><mask id='m'>{empty}{shape}</mask></defs><g mask='url(#m)'>{}</g>", shape.repeat(250)),
                "nested-mask" => format!("<defs><mask id='n'>{empty}{shape}</mask><mask id='m' mask='url(#n)'>{}</mask></defs><rect width='40' height='40' mask='url(#m)'/>", shape.repeat(250)),
                _ => format!("<defs><pattern id='p' patternUnits='userSpaceOnUse' width='40' height='40'>{empty}{shape}</pattern></defs><g fill='url(#p)'>{}</g>", "<rect width='40' height='40'/>".repeat(250)),
            };
            let source = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'>{content}</svg>"
            );
            match parse_svg(source, None) {
                Ok(scene) => {
                    fn count(paths: &[SvgPath]) -> usize {
                        paths
                            .iter()
                            .filter_map(|p| p.effects.as_ref())
                            .map(|e| {
                                let mask = e
                                    .mask
                                    .as_ref()
                                    .map_or(0, |m| m.commands.len() + count(&m.paths));
                                mask + [&e.fill_pattern, &e.stroke_pattern]
                                    .into_iter()
                                    .flatten()
                                    .map(|p| p.commands.len() + count(&p.paths))
                                    .sum::<usize>()
                            })
                            .sum()
                    }
                    assert_eq!(scene.commands.len() + count(&scene.paths), 0, "{effect}");
                }
                Err(error) => assert_eq!(error, EXPANSION_ERROR, "{effect}"),
            }
        }
    }

    /// 有绘制的深层 opacity 命令也必须扣除预算。
    #[test]
    fn opacity_command_expansion_is_budgeted() {
        let shape = "<rect width='40' height='40' fill='white'/>";
        let layers = format!(
            "{}{}{}",
            "<g opacity='.5'>".repeat(32),
            shape,
            "</g>".repeat(32)
        );
        for effect in ["mask", "nested-mask", "pattern", "mask-pattern"] {
            let content = match effect {
                "mask" => format!("<defs><mask id='m'>{layers}</mask></defs><g mask='url(#m)'>{}</g>", shape.repeat(1600)),
                "nested-mask" => format!("<defs><mask id='n'>{layers}</mask><mask id='m' mask='url(#n)'>{}</mask></defs><rect width='40' height='40' mask='url(#m)'/>", shape.repeat(1600)),
                "pattern" => format!("<defs><pattern id='p' patternUnits='userSpaceOnUse' width='40' height='40'>{layers}</pattern></defs><g fill='url(#p)'>{}</g>", "<rect width='40' height='40'/>".repeat(1600)),
                _ => format!("<defs><pattern id='p' patternUnits='userSpaceOnUse' width='40' height='40'>{layers}</pattern><mask id='m'><rect width='40' height='40' fill='url(#p)'/></mask></defs><g mask='url(#m)'>{}</g>", shape.repeat(1600)),
            };
            let source = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40'>{content}</svg>"
            );
            assert_eq!(
                parse_svg(source, None).err().as_deref(),
                Some(EXPANSION_ERROR),
                "{effect}"
            );
        }
    }

    /// 零 opacity 不生成主树、遮罩和图案的路径及命令。
    #[test]
    fn zero_opacity_skips_subtrees() {
        let scene =
            opacity_scene("<g opacity='0'><g opacity='.5'><rect width='40' height='40'/></g></g>");
        assert!(scene.paths.is_empty());
        assert!(scene.commands.is_empty());
        let scene = opacity_scene("<defs><mask id='m'><g opacity='0'><rect width='40' height='40'/></g><rect width='40' height='40' fill='white'/></mask><pattern id='p' patternUnits='userSpaceOnUse' width='40' height='40'><g opacity='0'><rect width='40' height='40'/></g><rect width='40' height='40'/></pattern></defs><rect width='40' height='40' fill='url(#p)' mask='url(#m)'/>");
        let effects = scene.paths[0].effects.as_ref().unwrap();
        let mask = effects.mask.as_ref().unwrap();
        let pattern = effects.fill_pattern.as_ref().unwrap();
        assert_eq!(mask.paths.len(), 1);
        assert!(mask.commands.is_empty());
        assert_eq!(pattern.paths.len(), 1);
        assert!(pattern.commands.is_empty());
    }

    /// 被深度限制截断的绘制不能留下空图层。
    #[test]
    fn truncated_subtrees_do_not_leave_empty_layers() {
        let tree = usvg::Tree::from_str("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='40' opacity='.5'><g opacity='.5'><rect width='40' height='40'/></g></svg>", usvg_options()).unwrap();
        let mut paths = Vec::new();
        let mut commands = Vec::new();
        append_subtree_commands(
            tree.root(),
            &Transform::default(),
            &mut paths,
            &mut commands,
            MAX_DEPTH - 1,
        );
        assert!(paths.is_empty());
        assert!(commands.is_empty());
        collect(
            tree.root(),
            &Inherited::default(),
            &mut paths,
            &mut Vec::new(),
            &mut commands,
            MAX_DEPTH - 1,
            &mut 0,
            &mut ExpansionBudget::default(),
        )
        .unwrap();
        assert!(paths.is_empty());
        assert!(commands.is_empty());
    }

    /// 检查根背景两种声明写法的绝对坐标包围盒。
    fn assert_root_background_bounds(size: u32, view_box: &str, expected: [f32; 4]) {
        for declaration in ["background-color='#f00'", "style='background-color:#f00'"] {
            let source = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='{size}' height='{size}' viewBox='{view_box}' {declaration}/>"
            );
            let scene = parse_svg(source, None).unwrap();
            assert_eq!(scene.paths.len(), 1, "{declaration}");
            let path = &scene.paths[0];
            assert!(path.has_fill);
            assert_eq!(path.fill_argb, 0xffff0000);
            assert!(!path.points.is_empty());
            let mut bounds = [
                f32::INFINITY,
                f32::INFINITY,
                f32::NEG_INFINITY,
                f32::NEG_INFINITY,
            ];
            for point in path.points.chunks_exact(2) {
                bounds[0] = bounds[0].min(point[0]);
                bounds[1] = bounds[1].min(point[1]);
                bounds[2] = bounds[2].max(point[0]);
                bounds[3] = bounds[3].max(point[1]);
            }
            for (actual, expected) in bounds.into_iter().zip(expected) {
                assert!(
                    (actual - expected).abs() < 1e-3,
                    "{declaration}: {bounds:?}"
                );
            }
        }
    }

    /// Identity viewBox mapping preserves the root background bounds.
    /// 恒等 viewBox 映射保持根背景的包围盒。
    #[test]
    fn root_background_identity() {
        assert_root_background_bounds(24, "0 0 24 24", [0., 0., 24., 24.]);
    }

    /// The root background scales from viewBox units to viewport pixels.
    /// 根背景从 viewBox 单位缩放到视口像素。
    #[test]
    fn root_background_scaled_viewbox() {
        assert_root_background_bounds(200, "0 0 24 24", [0., 0., 200., 200.]);
    }

    /// A nonzero viewBox origin translates the root background to the viewport.
    /// 非零 viewBox 原点将根背景平移到视口。
    #[test]
    fn root_background_translated_viewbox() {
        assert_root_background_bounds(24, "10 10 24 24", [0., 0., 24., 24.]);
    }

    /// Nested ordinary paths keep every coordinate under a nonidentity viewBox.
    /// 非恒等 viewBox 下的普通嵌套路径保持每个坐标不变。
    #[test]
    fn nested_path_nonidentity_viewbox() {
        let source = r#"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="10 10 100 100">
            <g transform="translate(12 14)"><g transform="scale(2 3)"><g transform="rotate(90)">
                <path d="M1 2 L3 4 Q5 6 7 8 C9 10 11 12 13 14 Z"/>
            </g></g></g>
        </svg>"#;
        let scene = parse_svg(source.into(), None).unwrap();
        assert_eq!(scene.paths.len(), 1);
        let path = &scene.paths[0];
        assert_eq!(path.verbs, vec![0, 1, 2, 3, 4]);
        let expected = [
            -4., 14., -12., 26., -20., 38., -28., 50., -36., 62., -44., 74., -52., 86.,
        ];
        assert_eq!(path.points.len(), expected.len());
        for (actual, expected) in path.points.iter().zip(expected) {
            assert!((actual - expected).abs() < 1e-3, "{actual} != {expected}");
        }
    }

    fn final_review_child(kind: &str, seconds: u64) {
        let mut child = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "api::svg::tests::final_review_small_stack_subprocess",
                "--nocapture",
            ])
            .env("XVG_FINAL_CHILD", kind)
            .spawn()
            .unwrap();
        let start = std::time::Instant::now();
        loop {
            if let Some(status) = child.try_wait().unwrap() {
                assert!(status.success(), "{kind}: {status}");
                break;
            }
            if start.elapsed() > std::time::Duration::from_secs(seconds) {
                child.kill().unwrap();
                child.wait().unwrap();
                panic!("{kind} exceeded {seconds}s");
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
    }

    #[test]
    fn final_review_small_stack_subprocess() {
        let Ok(kind) = std::env::var("XVG_FINAL_CHILD") else {
            for kind in ["function", "duplicates", "hidden-rules", "selector", "fuzz"] {
                final_review_child(kind, if kind == "fuzz" { 1200 } else { 5 });
            }
            return;
        };
        std::thread::Builder::new()
            .stack_size(1 << 20)
            .spawn(move || {
                match kind.as_str() {
                    "function" => {
                        for token in ["/*", "'"] {
                            for source in [
                                revision_chain("css-cycle-pattern", 3),
                                remaining_chain("css", 100),
                            ] {
                                let source = source
                                    .replace("<style>", &format!("<style>.x{{a:x({token})}}"));
                                assert!(parse_svg(source, None).is_err());
                            }
                        }
                    }
                    "duplicates" => {
                        let cycle = revision_chain("css-cycle-pattern", 3)
                            .replace("<style>", "<style>.x{a:x(/*)}")
                            .replace(
                                "</svg>",
                                "<decoy id='p0'/><decoy id='p1'/><decoy id='p2'/></svg>",
                            );
                        assert!(parse_svg(cycle, None).is_err());
                        let cycle = third_round_cycle_source("pattern", 3).replace(
                            "</svg>",
                            "<decoy id='r0'/><decoy id='r1'/><decoy id='r2'/></svg>",
                        );
                        assert!(parse_svg(cycle, None).is_err());
                        for (kind, length, tag) in [("red", 5000, "decoy"), ("use", 200, "rect")] {
                            let source = if kind == "red" {
                                revision_chain(kind, length)
                            } else {
                                remaining_chain(kind, length)
                            };
                            let decoys = (0..length)
                                .map(|i| format!("<{tag} id='r{i}'/>"))
                                .collect::<String>();
                            assert!(parse_svg(
                                source.replace("</svg>", &format!("{decoys}</svg>")),
                                None
                            )
                            .is_err());
                        }
                    }
                    "hidden-rules" => {
                        let source = format!(
                            "<svg><style>.x{{a:x(/*)}}{}</style></svg>",
                            "rect{fill:red}".repeat(20000)
                        );
                        let start = std::time::Instant::now();
                        assert!(parse_svg(source, None).is_err());
                        assert!(start.elapsed() < std::time::Duration::from_secs(5));
                        eprintln!("hidden 20000 rules: {:?}", start.elapsed());
                    }
                    "selector" => final_review_selector_cost(),
                    "fuzz" => {
                        GUARD_SCANS.store(0, std::sync::atomic::Ordering::Relaxed);
                        USVG_ENTRIES.store(0, std::sync::atomic::Ordering::Relaxed);
                        let tokens = [
                            "/*", "*/", "'", "\"", "(", ")", "{", "}", ";", ":", ",", "\\",
                            "@media", "url(#p0)", "url(#p1)", "url(#p2)", " ", "\n", "rect", "#r0",
                            ".x", " > ", "*", "a:x(", "fill:",
                        ];
                        let chain = remaining_chain("css", 100);
                        let direct_chain =
                            revision_chain("red", 5000).replace("<defs>", "<style></style><defs>");
                        let cycles = ["pattern", "mask", "clipPath"]
                            .map(|tag| revision_chain(&format!("css-cycle-{tag}"), 3));
                        let mut seed = 0x3a41_9c27_012d_678bu64;
                        // Keep both profiles exercising the scanner and reference graph.
                        // 两种构建均进入扫描器与引用图；CSS 底稿低于 4000 规则上限。
                        let cases = if cfg!(debug_assertions) { 500 } else { 3000 };
                        for case in 0..cases {
                            let mut css = String::new();
                            for _ in 0..(8 + case % 57) {
                                seed ^= seed << 13;
                                seed ^= seed >> 7;
                                seed ^= seed << 17;
                                css.push_str(tokens[seed as usize % tokens.len()]);
                            }
                            let selected_chain = if case % 2 == 0 { &chain } else { &direct_chain };
                            for source in cycles.iter().chain(std::iter::once(selected_chain)) {
                                let source = source.replace("<style>", &format!("<style>{css}"));
                                // Ok or Err is acceptable. Overflow aborts this child.
                                let _ = parse_svg(source, None);
                            }
                            if case % 500 == 499 {
                                eprintln!(
                                    "fuzz: {} CSS fragments / {} parses",
                                    case + 1,
                                    (case + 1) * 4
                                );
                            }
                        }
                        let scans = GUARD_SCANS.load(std::sync::atomic::Ordering::Relaxed);
                        let entries = USVG_ENTRIES.load(std::sync::atomic::Ordering::Relaxed);
                        eprintln!(
                            "fuzz coverage: {scans} scans, {entries} usvg entries / {} parses",
                            cases * 4
                        );
                        assert!(scans >= cases * 4, "all cases must reach the scanner");
                        assert!(
                            entries > cases / 100,
                            "attack-heavy cases must send at least 0.25% of parses into usvg"
                        );
                    }
                    _ => unreachable!(),
                }
            })
            .unwrap()
            .join()
            .unwrap();
    }

    #[test]
    fn final_review_css_workload_calibration() {
        for (rules, elements) in [
            (400, 5000),
            (200, 10000),
            (500, 8000),
            (4000, 400),
            (4000, 1998),
        ] {
            let css = (0..rules)
                .map(|i| format!(".s{i}{{fill:red}}"))
                .collect::<String>();
            let paths = (0..elements)
                .map(|i| format!("<path class='s{}' d='M0 0L1 1'/>", i % rules))
                .collect::<String>();
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style>{paths}</svg>");
            let start = std::time::Instant::now();
            assert!(parse_svg(source, None).is_ok(), "{rules}x{elements}");
            eprintln!("CSS {rules}x{elements}: {:?}", start.elapsed());
        }
        // Include application/cascade cost when every rule matches every path.
        for elements in [400, 1998] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{}</style>{}</svg>",
                ".s{fill:red}".repeat(4000), "<path class='s' d='M0 0L1 1'/>".repeat(elements));
            let start = std::time::Instant::now();
            assert!(parse_svg(source, None).is_ok());
            eprintln!("CSS all-matching 4000x{elements}: {:?}", start.elapsed());
        }
        let source = format!(
            "<svg><style>{}</style>{}</svg>",
            ".s{fill:red}".repeat(4000),
            "<path/>".repeat(2000)
        );
        assert!(limit_source_depth(&parse_xml(&source).unwrap()).is_err());
        let selectors = "g g g rect{fill:red}".repeat(100);
        let source = format!(
            "<svg><style>{selectors}</style>{}<rect/>{}</svg>",
            "<g>".repeat(100),
            "</g>".repeat(100)
        );
        assert!(limit_source_depth(&parse_xml(&source).unwrap()).is_err());
    }

    #[test]
    fn final_review_function_and_duplicate_guards() {
        for token in ["/*", "'"] {
            let source = revision_chain("css-cycle-pattern", 3)
                .replace("<style>", &format!("<style>.x{{a:x({token})}}"));
            assert!(
                limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                "{token}"
            );
        }
        for (kind, length) in [("css", 5000), ("use", 200)] {
            let source = if kind == "css" {
                revision_chain("red", length)
            } else {
                remaining_chain(kind, length)
            };
            let decoys = (0..length)
                .map(|i| format!("<decoy id='r{i}'/>"))
                .collect::<String>();
            let source = source.replace("</svg>", &format!("{decoys}</svg>"));
            assert!(
                limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                "{kind}"
            );
        }
    }

    #[test]
    fn final_review_independent_resources_and_selectors() {
        use crate::frb_generated::SseEncode;
        for (tag, prop, count) in [
            ("clipPath", "clip-path", 100),
            ("mask", "mask", 100),
            ("linearGradient", "fill", 200),
        ] {
            let css = (0..count)
                .map(|i| format!(".st{i}{{{prop}:url(#SVGID_{i}_)}}"))
                .collect::<String>();
            let defs = (0..count).map(|i| format!("<{tag} id='SVGID_{i}_'><rect width='1' height='1'/><stop stop-color='red'/></{tag}>" )).collect::<String>();
            let shapes = (0..count)
                .map(|i| format!("<g class='st{i}'><rect width='1' height='1'/></g>"))
                .collect::<String>();
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style><defs>{defs}</defs>{shapes}</svg>");
            let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
            let mut expected = flutter_rust_bridge::for_generated::SseSerializer::new();
            scene_from_tree(&tree).sse_encode(&mut expected);
            assert_eq!(wire_bytes(&source), expected.cursor.into_inner(), "{tag}");
        }
        for suffix in [" rect", " > rect", " rect[data-x]", " rect:first-child"] {
            for (tag, prop) in [("clipPath", "clip-path"), ("mask", "mask")] {
                let css = (0..3)
                    .map(|i| format!("#layer{i}{suffix}{{{prop}:url(#c{i})}}"))
                    .collect::<String>();
                let defs = (0..3)
                    .map(|i| format!("<{tag} id='c{i}'><rect width='1' height='1'/></{tag}>"))
                    .collect::<String>();
                let shapes = (0..3)
                    .map(|i| {
                        format!("<g id='layer{i}'><rect data-x='1' width='1' height='1'/></g>")
                    })
                    .collect::<String>();
                let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style>{defs}{shapes}</svg>");
                let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
                let mut expected = flutter_rust_bridge::for_generated::SseSerializer::new();
                scene_from_tree(&tree).sse_encode(&mut expected);
                assert_eq!(
                    wire_bytes(&source),
                    expected.cursor.into_inner(),
                    "{tag}: {suffix}"
                );
            }
        }
        assert!(parse_svg("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><rect id='same'/><rect id='same'/></svg>".into(), None).is_ok());
        assert!(parse_svg(remaining_chain("css", 11), None).is_ok());
    }

    #[test]
    fn opus_common_css_and_gradient_fallback() {
        let css = (0..3)
            .map(|i| format!(".st{i}{{fill:url(#SVGID_{i}_)}}"))
            .collect::<String>();
        let defs = (0..3)
            .map(|i| {
                format!("<linearGradient id='SVGID_{i}_'><stop stop-color='red'/></linearGradient>")
            })
            .collect::<String>();
        let shapes = (0..3)
            .map(|i| format!("<rect class='st{i}' x='{i}' width='1' height='1'/>"))
            .collect::<String>();
        let base = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style><defs>{defs}</defs>{shapes}</svg>");
        for extra in [
            ".st3{filter:drop-shadow(0 1px 2px rgba(0,0,0,.3))}",
            ".st3{font:12px/1.5 Arial}",
            ":root{color-scheme:light dark}",
            "rect:nth-child(2){opacity:.9}",
            ".st3{font-family:微软雅黑}",
            ":root{--fg:#333}",
            "rect::before{opacity:.9}",
        ] {
            let source = base.replace("</style>", &format!("{extra}</style>"));
            let doc = parse_xml(&source).unwrap();
            assert!(!checked_styles(&doc).unwrap()[0].1.uncertain, "{extra}");
            assert_eq!(wire_bytes(&source), wire_bytes(&base), "{extra}");
        }
        // Unaligned recovery must still exclude gradients and their stop children.
        let source = base.replace("</style>", ".unused{a:!bad}</style>");
        assert!(
            checked_styles(&parse_xml(&source).unwrap()).unwrap()[0]
                .1
                .uncertain
        );
        assert!(!limit_source_depth(&parse_xml(&source).unwrap()).unwrap());
        assert_eq!(wire_bytes(&source), wire_bytes(&base));
        let markers = base
            .replace("linearGradient", "marker")
            .replace("<stop stop-color='red'/>", "<path d='M0 0L1 1'/>")
            .replace("fill:url", "marker-start:url");
        assert_eq!(
            wire_bytes(&markers.replace("</style>", ":root{--fg:#333}</style>")),
            wire_bytes(&markers)
        );
    }

    #[test]
    fn opus_conservative_referenced_subtree_edges() {
        // Legal static structures only: inspect the graph, never convert a cycle.
        for (resource, property, content) in [
            ("pattern", "fill", "<use href='#x'/>"),
            ("filter", "filter", "<feImage href='#x'/>"),
        ] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>.a{{{property}:url(#p0)}}.b{{{property}:url(#p1)}}.c{{{property}:url(#p2)}}.unused{{a:!bad}}</style><defs><{resource} id='p0' width='2' height='2'>{content}</{resource}><{resource} id='p1'/><{resource} id='p2'/><g id='x'><rect id='leaf' class='b' width='1' height='1'/></g><linearGradient id='gradient'><stop id='stop'/></linearGradient></defs><rect class='a' width='10' height='10'/></svg>");
            let doc = parse_xml(&source).unwrap();
            let styles = checked_styles(&doc).unwrap();
            assert!(styles[0].1.uncertain);
            let nodes: Vec<_> = doc.descendants().filter(|n| n.is_element()).collect();
            let index = |id| {
                nodes
                    .iter()
                    .position(|n| n.attribute("id") == Some(id))
                    .unwrap()
            };
            let (edges, worker) = source_reference_graph(&nodes, &styles).unwrap();
            assert!(worker);
            let p0 = index("p0");
            let x = index("x");
            let leaf = index("leaf");
            assert!(edges[p0]
                .iter()
                .any(|&(child, weight)| weight == 0 && edges[child].contains(&(x, 1))));
            assert!(edges[x].contains(&(leaf, 0)));
            for target in ["p0", "p1", "p2"] {
                assert!(
                    edges[leaf].contains(&(index(target), 1)),
                    "{resource}: missing leaf -> {target}"
                );
            }
            for id in ["gradient", "stop"] {
                assert!(!edges[index(id)].iter().any(|&(_, weight)| weight >= 1));
            }
            // Acyclic counterpart: root paint selects p0 directly, so the two
            // CSS targets cannot lead back into the expanded ordinary subtree.
            let acyclic = source
                .replace(&format!(".a{{{property}:url(#p0)}}"), "")
                .replace("<rect class='a'", &format!("<rect {property}='url(#p0)'"));
            assert!(limit_source_depth(&parse_xml(&acyclic).unwrap()).is_ok());
            assert_eq!(
                wire_bytes(&acyclic),
                wire_bytes(&acyclic.replace(".unused{a:!bad}", "")),
                "{resource}: fallback changed acyclic wire",
            );
        }
    }

    #[test]
    fn opus_long_legal_selectors() {
        let mut cases = Vec::new();
        for count in [4, 5, 6] {
            let body = format!(
                "{}<rect/><rect id='target' width='1' height='1'/>{}",
                "<g>".repeat(count),
                "</g>".repeat(count)
            );
            cases.push((format!("{}rect", "g ".repeat(count)), body.clone()));
            cases.push((format!("{}rect:nth-child(2)", "g > ".repeat(count)), body));
        }
        cases.push((
            ".chart > .axis .tick g text".to_owned(),
            "<g class='chart'><g class='axis'><g class='tick'><g><text id='target'>tick</text><rect width='1' height='1'/></g></g></g></g>".to_owned(),
        ));
        for (selector, body) in cases {
            let base = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>{body}</svg>"
            );
            // font-family is parsed CSS, but does not affect xvg's wire output
            // (static text is disabled, and rect geometry/paint is unchanged).
            let source = base.replace(
                &body,
                &format!("<style>{selector}{{font-family:serif}}</style>{body}"),
            );
            let doc = parse_xml(&source).unwrap();
            let target = doc
                .descendants()
                .find(|n| n.attribute("id") == Some("target"))
                .unwrap();
            assert!(
                css_parts_match(&css_selector_parts(&selector).unwrap(), target),
                "selector must match: {selector}"
            );
            assert_eq!(wire_bytes(&source), wire_bytes(&base), "{selector}");
        }
    }

    #[test]
    fn final_review_selector_cost() {
        let source = format!(
            "<svg><style>nonexist * * * * * rect{{fill:red}}</style>{}<rect/>{}</svg>",
            "<g>".repeat(100),
            "</g>".repeat(100)
        );
        // Check before upstream matching, so the red test itself does not hang.
        let now = std::time::Instant::now();
        assert!(limit_source_depth(&parse_xml(&source).unwrap())
            .unwrap_err()
            .contains("selector"));
        assert!(parse_svg(source, None).is_err());
        assert!(now.elapsed() < std::time::Duration::from_secs(2));
    }

    #[test]
    fn final_review_unicode_selector_combinators() {
        let source = "<svg><style>层>g>g>g>rect{fill:red}</style><rect/></svg>";
        assert!(limit_source_depth(&parse_xml(source).unwrap()).is_ok());
    }

    #[test]
    fn final_review_ambiguous_values_are_not_selectors() {
        for css in [
            ".beat:nth-child(4){animation:beat-scale 1s linear infinite alternate}",
            ".s{filter:drop-shadow(0 12px 28px rgba(0, 0, 0, .08))}",
            "*,*::before,*::after{animation:spin 1s linear infinite normal forwards}",
        ] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style><rect width='1' height='1'/></svg>");
            assert!(parse_svg(source, None).is_ok(), "{css}");
        }
    }

    fn revision_chain(kind: &str, length: usize) -> String {
        if let Some(tag) = kind.strip_prefix("css-cycle-") {
            let prop = match tag {
                "pattern" => "fill",
                "mask" => "mask",
                _ => "clip-path",
            };
            let mut css = String::new();
            let mut defs = String::new();
            for i in 0..3 {
                let selector = if tag == "clipPath" {
                    format!("p{i}")
                } else {
                    format!("r{i}")
                };
                css.push_str(&format!("#{selector}{{{prop}:url(#p{})}}", (i + 1) % 3));
                defs.push_str(&format!("<{tag} id='p{i}' width='1' height='1'><rect id='r{i}' width='1' height='1'/></{tag}>"));
            }
            return format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style><defs>{defs}</defs><rect width='10' height='10' {prop}='url(#p0)'/></svg>");
        }
        if kind == "marker" {
            return remaining_chain("marker-start", length)
                .replace("marker-start=", "style=")
                .replace("style='url", "style='marker:url");
        }
        if kind == "gradient" || kind.ends_with("href") {
            let tag = match kind {
                "gradient" => "linearGradient",
                "pattern-href" | "pattern-xlink-href" => "pattern",
                _ => "filter",
            };
            let defs = (0..length).map(|i| if i + 1 == length {
                format!("<{tag} id='p{i}' width='2' height='2'><rect width='1' height='1'/><stop stop-color='red'/></{tag}>")
            } else { format!("<{tag} id='p{i}' href='#p{}' width='2' height='2'/>", i+1) }).collect::<String>();
            let prop = if tag == "filter" { "filter" } else { "fill" };
            let defs = if kind.contains("xlink") {
                defs.replace("href=", "xlink:href=")
            } else {
                defs
            };
            return format!("<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='10' height='10'><defs>{defs}</defs><rect width='10' height='10' {prop}='url(#p0)'/></svg>");
        }
        if kind == "filters" {
            return remaining_chain("filter", length)
                .replace("filter='url(#", "filter='url(#missing) url(#");
        }
        let mut source = remaining_chain("css", length);
        if kind == "css" {
            return source;
        }
        // Turn the same pattern chain into every bypass spelling.
        let css_end = source.find("</style>").unwrap() + 8;
        let css_start = source.find("<style>").unwrap();
        source.replace_range(css_start..css_end, "");
        let mut output = String::with_capacity(source.len());
        let mut tail = source.as_str();
        while let Some(start) = tail.find("class='c") {
            output.push_str(&tail[..start]);
            tail = &tail[start + 8..];
            let end = tail.find('\'').unwrap();
            let i = &tail[..end];
            let value = match kind {
                "comment" => format!("style='/**/fill:url(#r{i})'"),
                "star" => format!("style='*fill:url(#r{i})'"),
                "red" => format!("fill='url(#r{i}) red'"),
                "none" => format!("fill='url(#r{i}) none'"),
                "filters" => format!("filter='url(#missing) url(#r{i})'"),
                _ => unreachable!(),
            };
            output.push_str(&value);
            tail = &tail[end + 1..];
        }
        output.push_str(tail);
        output
    }

    #[test]
    fn revision_bypasses_subprocess() {
        if let Ok(kind) = std::env::var("XVG_REVISION_CHILD") {
            std::thread::Builder::new()
                .stack_size(1 << 20)
                .spawn(move || {
                    let source = match kind.as_str() {
                        "pattern32" => revision_chain("red", 32),
                        "marker32" => remaining_chain("marker-start", 32),
                        _ => revision_chain(&kind, 5000),
                    };
                    let result = parse_svg(source, None);
                    if matches!(kind.as_str(), "gradient" | "pattern32" | "marker32") {
                        assert!(result.is_ok());
                    } else {
                        assert!(result.is_err(), "{kind}");
                    }
                })
                .unwrap()
                .join()
                .unwrap();
            return;
        }
        let mut failures = Vec::new();
        for kind in [
            "marker",
            "comment",
            "star",
            "red",
            "none",
            "filters",
            "pattern-href",
            "filter-href",
            "pattern-xlink-href",
            "filter-xlink-href",
            "gradient",
            "css",
            "css-cycle-pattern",
            "css-cycle-mask",
            "css-cycle-clipPath",
            "pattern32",
            "marker32",
        ] {
            let out = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "api::svg::tests::revision_bypasses_subprocess",
                    "--nocapture",
                ])
                .env("XVG_REVISION_CHILD", kind)
                .output()
                .unwrap();
            eprintln!("{kind} subprocess: {}", out.status);
            if !out.status.success() {
                failures.push(format!("{kind}: {}", String::from_utf8_lossy(&out.stderr)));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[test]
    fn revision_guard_edges() {
        let mut missing = Vec::new();
        for kind in [
            "marker",
            "comment",
            "star",
            "red",
            "none",
            "filters",
            "pattern-href",
            "filter-href",
            "pattern-xlink-href",
            "filter-xlink-href",
        ] {
            let source = revision_chain(kind, 5000);
            if limit_source_depth(&parse_xml(&source).unwrap()).is_ok() {
                missing.push(kind);
            }
        }
        assert!(missing.is_empty(), "unprotected graph edges: {missing:?}");
        for n in [10, 11] {
            let source = remaining_chain("css", n);
            assert!(limit_source_depth(&parse_xml(&source).unwrap()).is_ok());
        }
    }

    #[test]
    fn revision_css_limits() {
        for (rules, elements) in [(20000, 1), (1000, 9000)] {
            let css = "rect{fill:red}".repeat(rules);
            let source = format!(
                "<svg width='10' height='10'><style>{css}</style>{}</svg>",
                "<rect width='1' height='1'/>".repeat(elements)
            );
            let now = std::time::Instant::now();
            let doc = parse_xml(&source).unwrap();
            assert!(
                limit_source_depth(&doc).is_err(),
                "{rules} rules x {elements} elements"
            );
            assert!(parse_svg(source.clone(), None)
                .err()
                .unwrap()
                .starts_with("SVG stylesheet too complex"));
            assert!(now.elapsed() < std::time::Duration::from_secs(2));
            eprintln!("{rules} rules x {elements}: {:?}", now.elapsed());
        }
    }

    #[test]
    fn revision_css_cycles_and_independent_targets() {
        for selector in [
            "#c",
            ".c",
            "rect",
            "*",
            "clipPath > rect.c",
            "[id=c]",
            "rect:is(.c)",
        ] {
            let source = format!("<svg><style>{selector}{{fill:url(#a)}} #a {{mask:url(#b)}} #b {{clip-path:url(#c)}}</style><pattern id='a'/><mask id='b'/><clipPath id='c' class='c'/></svg>");
            // rect selectors need an actual matching descendant of c.
            let source = source.replace(
                "<clipPath id='c' class='c'/>",
                "<clipPath id='c' class='c'><rect id='c2' class='c'/></clipPath>",
            );
            assert!(
                limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                "{selector}"
            );
        }
        for n in [64, 65] {
            let defs = (0..n)
                .map(|i| format!("<pattern id='p{i}'/>"))
                .collect::<String>();
            let css = (0..n)
                .map(|i| format!(".s{i}{{fill:url(#p{i})}}"))
                .collect::<String>();
            let source = format!("<svg><style>{css}</style>{defs}</svg>");
            assert!(limit_source_depth(&parse_xml(&source).unwrap()).is_ok());
        }
    }

    #[test]
    fn revision_gradient_stylesheet_inline_and_timing() {
        let source="<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>.st0{fill:url(#SVGID_1_)}</style><linearGradient id='SVGID_1_'><stop stop-color='red'/></linearGradient><rect class='st0' width='10' height='10'/></svg>";
        let doc = parse_xml(source).unwrap();
        if std::env::var_os("XVG_TIMING").is_none() {
            assert!(!stylesheet_needs_stack(&doc));
        }
        let start = std::time::Instant::now();
        for _ in 0..1000 {
            std::hint::black_box(parse_svg(source.into(), None).unwrap());
        }
        eprintln!("gradient stylesheet 1000 parses: {:?}", start.elapsed());
    }

    fn stylesheet_needs_stack(doc: &usvg::roxmltree::Document<'_>) -> bool {
        limit_source_depth(doc).unwrap()
    }

    #[test]
    fn revision_common_urls_and_illustration_wire() {
        use crate::frb_generated::SseEncode;
        for url in [
            "url(#p)",
            "url(#p) red",
            "url(#p) none",
            "url(&quot;#p&quot;)",
            "url('#p')",
            "url(  '#p'  )",
        ] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs><pattern id='p' width='2' height='2' patternUnits='userSpaceOnUse'><rect width='1' height='1'/></pattern></defs><rect width='10' height='10' fill=\"{url}\"/></svg>");
            let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
            let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
            scene_from_tree(&tree).sse_encode(&mut ser);
            assert_eq!(wire_bytes(&source), ser.cursor.into_inner(), "{url}");
        }
        // Hundreds of Illustrator-style gradient classes must remain inline.
        let css = (0..400)
            .map(|i| format!(".st{i}{{fill:url(#SVGID_{i}_)}}"))
            .collect::<String>();
        let defs = (0..400)
            .map(|i| {
                format!("<linearGradient id='SVGID_{i}_'><stop stop-color='red'/></linearGradient>")
            })
            .collect::<String>();
        let paths = (0..400)
            .map(|i| format!("<rect class='st{i}' x='{i}' width='1' height='1'/>"))
            .collect::<String>();
        let source=format!("<svg xmlns='http://www.w3.org/2000/svg' width='400' height='10'><style>{css}</style><defs>{defs}</defs>{paths}</svg>");
        assert!(!stylesheet_needs_stack(&parse_xml(&source).unwrap()));
        let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
        let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
        scene_from_tree(&tree).sse_encode(&mut ser);
        assert_eq!(wire_bytes(&source), ser.cursor.into_inner());
    }

    // Normal runs compare the repository's 1000 MDI icons against the unchanged
    // upstream conversion, with/without currentColor. A length-prefixed corpus
    // can be supplied for the 2880-sample audit and real exporter samples:
    // XVG_PROBE_CORPUS=<file> XVG_PROBE_OUTPUT=<optional SSE dump file>
    #[test]
    fn revision_full_wire_corpus() {
        use crate::frb_generated::SseEncode;
        let sources = if let Ok(path) = std::env::var("XVG_PROBE_CORPUS") {
            let bytes = std::fs::read(path).unwrap();
            let mut tail = bytes.as_slice();
            let mut sources = Vec::new();
            while !tail.is_empty() {
                let end = tail.iter().position(|&b| b == b'\n').unwrap();
                let len = std::str::from_utf8(&tail[..end])
                    .unwrap()
                    .parse::<usize>()
                    .unwrap();
                tail = &tail[end + 1..];
                sources.push(std::str::from_utf8(&tail[..len]).unwrap().to_owned());
                tail = &tail[len..];
            }
            sources
        } else {
            let text = std::fs::read_to_string(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../benchmark/bench_app/lib/mdi_icons_1000.dart"
            ))
            .unwrap();
            let sources: Vec<_> = text
                .lines()
                .filter_map(|s| s.trim().strip_prefix('\'')?.strip_suffix("',"))
                .filter(|s| s.starts_with("<svg"))
                .map(str::to_owned)
                .collect();
            assert_eq!(sources.len(), 1000);
            sources
        };
        let mut dump = Vec::new();
        for source in &sources {
            for cc in [None, Some(0xffff7a00)] {
                let colored = cc
                    .map(|c| inject_current_color(source.clone(), c))
                    .unwrap_or_else(|| source.clone());
                let tree = usvg::Tree::from_str(&colored, usvg_options()).unwrap();
                let mut expected = flutter_rust_bridge::for_generated::SseSerializer::new();
                scene_from_tree(&tree).sse_encode(&mut expected);
                let mut actual = flutter_rust_bridge::for_generated::SseSerializer::new();
                parse_svg(source.clone(), cc)
                    .unwrap()
                    .sse_encode(&mut actual);
                let bytes = actual.cursor.into_inner();
                assert_eq!(bytes, expected.cursor.into_inner());
                dump.extend_from_slice(&(bytes.len() as u64).to_le_bytes());
                dump.extend(bytes);
            }
        }
        if let Ok(path) = std::env::var("XVG_PROBE_OUTPUT") {
            std::fs::write(path, &dump).unwrap();
        }
        eprintln!(
            "full SSE: {} samples, {} bytes",
            sources.len() * 2,
            dump.len()
        );
    }

    #[test]
    fn revision_nested_url_id_is_conservatively_rejected() {
        let source = "<svg><style>#a{fill:url('#purl(1')}</style><pattern id='purl(1'><rect id='a'/></pattern></svg>";
        assert!(limit_source_depth(&parse_xml(source).unwrap()).is_err());
    }

    #[test]
    fn revision_css_quoted_delimiters() {
        for prefix in ["font-family:'}';", "font-family:'/*';", "font-family:'{';"] {
            let source=format!("<svg><style>#a{{{prefix}mask:url(#b)}} #b{{clip-path:url(#c)}} #c{{fill:url(#a)}}</style><pattern id='a'/><mask id='b'/><clipPath id='c'/></svg>");
            assert!(
                limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                "{prefix}"
            );
        }
    }
    #[test]
    fn revision_css_independent_depths() {
        for chains in [3, 4] {
            let mut defs = String::new();
            let mut css = String::new();
            for k in 0..chains {
                for i in 0..19 {
                    let body = if i == 18 {
                        String::new()
                    } else {
                        format!("<rect fill='url(#p{k}_{})'/>", i + 1)
                    };
                    defs.push_str(&format!("<pattern id='p{k}_{i}'>{body}</pattern>"));
                }
                css.push_str(&format!(".unused{k}{{fill:url(#p{k}_0)}}"));
            }
            let source = format!("<svg><style>{css}</style>{defs}</svg>");
            assert!(limit_source_depth(&parse_xml(&source).unwrap()).is_ok());
        }
    }
    fn remaining_chain(kind: &str, length: usize) -> String {
        let mut defs = String::new();
        let shape = "<rect width='8' height='8'/>";
        for i in 0..length {
            let next = i + 1;
            let body = if next == length {
                shape.to_owned()
            } else {
                match kind {
                    "use" | "xlink-use" | "symbol" => format!("<use xlink:href='#r{next}'/>"),
                    "feImage" => format!("<rect width='8' height='8' filter='url(#f{next})'/>"),
                    "filter" => format!("<rect width='8' height='8' filter='url(#r{next})'/>"),
                    "css" => format!("<rect class='c{next}' width='8' height='8'/>"),
                    prop => format!("<path d='M0 0L8 8L0 8' {prop}='url(#r{next})'/>"),
                }
            };
            match kind {
                "use" => defs.push_str(&format!("<g id='r{i}'>{}</g>", body.replace("xlink:href", "href"))),
                "xlink-use" => defs.push_str(&format!("<g id='r{i}'>{body}</g>")),
                "symbol" => defs.push_str(&format!("<symbol id='r{i}'>{body}</symbol>")),
                "feImage" => defs.push_str(&format!("<g id='r{i}'>{body}</g><filter id='f{i}'><feImage href='#r{i}'/></filter>")),
                "filter" => defs.push_str(&format!("<filter id='r{i}'><feImage href='#g{i}'/></filter><g id='g{i}'>{body}</g>")),
                "css" => defs.push_str(&format!("<pattern id='r{i}' width='10' height='10' patternUnits='userSpaceOnUse'>{body}</pattern>")),
                _ => defs.push_str(&format!("<marker id='r{i}' markerWidth='10' markerHeight='10'>{body}</marker>")),
            }
        }
        let output = match kind {
            "use" | "xlink-use" | "symbol" => "<use href='#r0'/>".to_owned(),
            "feImage" => "<rect width='10' height='10' filter='url(#f0)'/>".to_owned(),
            "filter" => "<rect width='10' height='10' filter='url(#r0)'/>".to_owned(),
            "css" => "<rect class='c0' width='10' height='10'/>".to_owned(),
            prop => format!("<path d='M0 0L8 8L0 8' {prop}='url(#r0)'/>"),
        };
        let css = if kind == "css" {
            format!(
                "<style>{}</style>",
                (0..length)
                    .map(|i| format!(".c{i} {{fill:url(#r{i})}} "))
                    .collect::<String>()
            )
        } else {
            String::new()
        };
        format!("<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='10' height='10'>{css}<defs>{defs}</defs>{output}</svg>")
    }

    #[test]
    fn remaining_chains_subprocess() {
        if let Ok(kind) = std::env::var("XVG_REMAINING_CHILD") {
            std::thread::Builder::new()
                .stack_size(1 << 20)
                .spawn(move || {
                    let length = if kind == "css100" {
                        100
                    } else if kind == "css2000" {
                        2000
                    } else {
                        5000
                    };
                    let source = remaining_chain(
                        if kind.starts_with("css") {
                            "css"
                        } else {
                            &kind
                        },
                        length,
                    );
                    let result = parse_svg(source, None);
                    assert!(result.is_err(), "{kind} must return Err");
                })
                .unwrap()
                .join()
                .unwrap();
            return;
        }
        let mut failures = Vec::new();
        for kind in [
            "use",
            "xlink-use",
            "symbol",
            "marker-start",
            "marker-mid",
            "marker-end",
            "feImage",
            "filter",
            "css100",
            "css2000",
        ] {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "api::svg::tests::remaining_chains_subprocess",
                    "--nocapture",
                ])
                .env("XVG_REMAINING_CHILD", kind)
                .output()
                .unwrap();
            if !output.status.success() {
                failures.push(format!(
                    "{kind}: {}",
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[test]
    fn remaining_href_whitespace() {
        for kind in ["use", "xlink-use", "symbol", "feImage"] {
            let source = remaining_chain(kind, 5000)
                .replace("href='#", "href=' #")
                .replace("'/>", " '/>");
            assert!(
                limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                "{kind}"
            );
        }
    }

    #[test]
    fn remaining_reference_cycles_and_boundaries() {
        for kind in [
            "use",
            "xlink-use",
            "symbol",
            "feImage",
            "filter",
            "marker-start",
            "marker-mid",
            "marker-end",
        ] {
            for length in [1, 2, 3] {
                let defs = (0..length)
                    .map(|i| {
                        let next = (i + 1) % length;
                        let body = match kind {
                            "use" | "symbol" => format!("<use href='#r{next}'/>"),
                            "xlink-use" => format!("<use xlink:href='#r{next}'/>"),
                            "feImage" => format!("<feImage href='#r{next}'/>"),
                            "filter" => format!("<g filter='url(#r{next})'/>"),
                            prop => format!("<path d='M0 0L8 8' {prop}='url(#r{next})'/>"),
                        };
                        format!("<g id='r{i}'>{body}</g>")
                    })
                    .collect::<String>();
                let source =
                    format!("<svg xmlns:xlink='http://www.w3.org/1999/xlink'>{defs}</svg>");
                assert_eq!(
                    limit_source_depth(&parse_xml(&source).unwrap()).is_err(),
                    length >= 3,
                    "{kind}, cycle {length}"
                );
            }
        }
        // Exact boundaries count reference edges; feImage and filter alternate
        // two resources per source layer, so their layer count is half the cap.
        for kind in ["use", "symbol", "marker-start", "feImage", "filter"] {
            let limit = if matches!(kind, "feImage" | "filter") {
                MAX_REFERENCE_DEPTH / 2
            } else {
                MAX_REFERENCE_DEPTH
            };
            for length in [limit, limit + 1] {
                assert_eq!(
                    limit_source_depth(&parse_xml(&remaining_chain(kind, length)).unwrap()).is_ok(),
                    length == limit,
                    "{kind}, chain {length}"
                );
            }
        }
    }

    #[test]
    fn remaining_legal_wire_bytes() {
        use crate::frb_generated::SseEncode;
        for kind in [
            "use",
            "xlink-use",
            "symbol",
            "marker-start",
            "marker-mid",
            "marker-end",
            "feImage",
            "filter",
            "css",
        ] {
            let source = remaining_chain(kind, if kind == "css" { 8 } else { 12 });
            let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
            let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
            scene_from_tree(&tree).sse_encode(&mut ser);
            assert_eq!(wire_bytes(&source), ser.cursor.into_inner(), "{kind}");
        }
        // 5000 independent instances still have a chain depth of one.
        for tag in ["symbol", "g"] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs><{tag} id='s'><rect width='1' height='1'/></{tag}></defs>{}</svg>", "<use href='#s'/>".repeat(5000));
            assert_eq!(parse_svg(source, None).unwrap().paths.len(), 5000);
        }
    }

    #[test]
    fn remaining_stylesheet_routing_and_wire() {
        use crate::frb_generated::SseEncode;
        for css in [
            "rect {fill:red}",
            "rect {fill:url(#p)}",
            "@import 'unused.css'; rect {fill:red}",
            "<![CDATA[rect {fill:url(#p)}]]>",
        ] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><style>{css}</style><defs><pattern id='p' width='2' height='2' patternUnits='userSpaceOnUse'><rect width='1' height='1' fill='currentColor'/></pattern></defs><rect width='10' height='10'/></svg>");
            let doc = parse_xml(&source).unwrap();
            assert_eq!(stylesheet_needs_stack(&doc), css.contains("url("));
            for cc in [None, Some(0xffff7a00)] {
                let colored = cc
                    .map(|c| inject_current_color(source.clone(), c))
                    .unwrap_or_else(|| source.clone());
                let tree = usvg::Tree::from_str(&colored, usvg_options()).unwrap();
                let mut expected = flutter_rust_bridge::for_generated::SseSerializer::new();
                scene_from_tree(&tree).sse_encode(&mut expected);
                let mut actual = flutter_rust_bridge::for_generated::SseSerializer::new();
                parse_svg(source.clone(), cc)
                    .unwrap()
                    .sse_encode(&mut actual);
                assert_eq!(actual.cursor.into_inner(), expected.cursor.into_inner());
            }
        }
    }

    // Manual subprocess probe: binary search the minimum successful stack;
    // uses unguarded upstream parsing to measure actual usvg recursion cost.
    // XVG_STACK_KIND=css|marker-start XVG_STACK_LENGTH=32 XVG_STACK_BYTES=1048576
    // cargo test remaining_stack_probe -- --ignored --exact api::svg::tests::remaining_stack_probe
    #[test]
    #[ignore = "manual stack probe; requires XVG_STACK_KIND/LENGTH/BYTES"]
    fn remaining_stack_probe() {
        let Ok(kind) = std::env::var("XVG_STACK_KIND") else {
            return;
        };
        let length = std::env::var("XVG_STACK_LENGTH").unwrap().parse().unwrap();
        let bytes = std::env::var("XVG_STACK_BYTES").unwrap().parse().unwrap();
        std::thread::Builder::new()
            .stack_size(bytes)
            .spawn(move || {
                let source = remaining_chain(&kind, length);
                let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
                let _ = scene_from_tree(&tree);
            })
            .unwrap()
            .join()
            .unwrap();
    }

    fn wire_bytes(source: &str) -> Vec<u8> {
        use crate::frb_generated::SseEncode;
        let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
        parse_svg(source.into(), None).unwrap().sse_encode(&mut ser);
        ser.cursor.into_inner()
    }

    #[test]
    fn audit_rework_cycles_match_upstream_wire_bytes() {
        use crate::frb_generated::SseEncode;
        for (tag, attr, self_ref) in [
            ("clipPath", "clip-path", false),
            ("clipPath", "clip-path", true),
            ("mask", "mask", false),
        ] {
            let next = if self_ref { "a" } else { "b" };
            let shape = "<rect width='5' height='10' fill='white'/>";
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs><{tag} id='a' {attr}='url(#{next})'>{shape}</{tag}><{tag} id='b' {attr}='url(#a)'>{shape}</{tag}></defs><rect width='10' height='10' {attr}='url(#a)'/></svg>");
            // HEAD delegates cycles to usvg. Preserve the complete SSE bytes,
            // including the surviving clip/mask, rather than stripping attributes.
            let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
            let expected = scene_from_tree(&tree);
            let effects = expected.paths[0].effects.as_ref().unwrap();
            assert!(if attr == "mask" {
                effects.mask.is_some()
            } else {
                !effects.clips.is_empty()
            });
            let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
            expected.sse_encode(&mut ser);
            assert_eq!(
                wire_bytes(&source),
                ser.cursor.into_inner(),
                "{tag}, self={self_ref}"
            );
        }
    }

    fn third_round_cycle_source(kind: &str, length: usize) -> String {
        let (tag, attr) = match kind {
            "clip-chain" | "clip-child" => ("clipPath", "clip-path"),
            "mask-child" => ("mask", "mask"),
            "pattern" => ("pattern", "fill"),
            _ => panic!("unknown cycle kind"),
        };
        let mut defs = String::new();
        for i in 0..length {
            let next = (i + 1) % length;
            let reference = format!("{attr}='url(#r{next})'");
            let (outer, inner) = if kind == "clip-chain" {
                (reference.as_str(), "")
            } else {
                ("", reference.as_str())
            };
            defs.push_str(&format!("<{tag} id='r{i}' width='10' height='10' {outer}><rect width='5' height='10' {inner}/></{tag}>"));
        }
        format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs>{defs}</defs><rect width='10' height='10' {attr}='url(#r0)'/></svg>")
    }

    fn third_round_children(test: &str, kinds: &[&str]) {
        let mut failures = Vec::new();
        for kind in kinds {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args(["--exact", test, "--nocapture"])
                .env("XVG_THIRD_ROUND_CHILD", kind)
                .output()
                .unwrap();
            if !output.status.success() {
                failures.push(format!(
                    "{kind}: {} {}",
                    String::from_utf8_lossy(&output.stdout),
                    String::from_utf8_lossy(&output.stderr)
                ));
            }
        }
        assert!(failures.is_empty(), "{}", failures.join("\n"));
    }

    #[test]
    fn third_round_three_resource_cycles_subprocess() {
        if let Ok(kind) = std::env::var("XVG_THIRD_ROUND_CHILD") {
            std::thread::Builder::new()
                .stack_size(1 << 20)
                .spawn(move || {
                    let error = parse_svg(third_round_cycle_source(&kind, 3), None)
                        .err()
                        .expect("three-resource cycle must return Err");
                    assert!(error.starts_with("SVG has a reference cycle"), "{error}");
                })
                .unwrap()
                .join()
                .unwrap();
            return;
        }
        third_round_children(
            "api::svg::tests::third_round_three_resource_cycles_subprocess",
            &["clip-chain", "clip-child", "mask-child", "pattern"],
        );
    }

    #[test]
    fn third_round_small_cycles_preserve_wire_bytes() {
        use crate::frb_generated::SseEncode;
        for kind in ["clip-chain", "clip-child", "mask-child", "pattern"] {
            for length in [1, 2] {
                let source = third_round_cycle_source(kind, length);
                let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
                let mut ser = flutter_rust_bridge::for_generated::SseSerializer::new();
                scene_from_tree(&tree).sse_encode(&mut ser);
                assert_eq!(
                    wire_bytes(&source),
                    ser.cursor.into_inner(),
                    "{kind}, n={length}"
                );
            }
        }
    }

    #[test]
    fn third_round_inline_style_chains_subprocess() {
        if let Ok(kind) = std::env::var("XVG_THIRD_ROUND_CHILD") {
            let (tag, attr, length) = if kind == "clip" {
                ("clipPath", "clip-path", 300)
            } else {
                ("mask", "mask", 5000)
            };
            let mut defs = String::new();
            for i in 0..length {
                defs.push_str(&format!("<{tag} id='r{i}'><rect width='10' height='10' style='fill: white; {attr}: url(#r{}); stroke: none'/></{tag}>", i + 1));
            }
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs>{defs}</defs><rect width='10' height='10' style='{attr}: url(#r0)'/></svg>");
            std::thread::Builder::new()
                .stack_size(1 << 20)
                .spawn(move || {
                    let error = parse_svg(source, None)
                        .err()
                        .expect("inline style chain must return Err");
                    assert!(error.contains("reference chain"), "{error}");
                })
                .unwrap()
                .join()
                .unwrap();
            return;
        }
        third_round_children(
            "api::svg::tests::third_round_inline_style_chains_subprocess",
            &["clip", "mask"],
        );
    }

    #[test]
    fn audit_rework_svg_data_resolver() {
        let bytes = std::sync::Arc::new(b"<svg xmlns='http://www.w3.org/2000/svg'/>".to_vec());
        assert!((usvg_options().image_href_resolver.resolve_data)(
            "image/svg+xml",
            bytes,
            usvg_options()
        )
        .is_none());
        assert_eq!(parse_svg(IMAGE_SVG.into(), None).unwrap().images.len(), 1);
    }

    #[test]
    fn audit_rework_plain_data_resolver() {
        let bytes = std::sync::Arc::new(b"<svg xmlns='http://www.w3.org/2000/svg'/>".to_vec());
        assert!((usvg_options().image_href_resolver.resolve_data)(
            "text/plain",
            bytes,
            usvg_options()
        )
        .is_none());
        let png = IMAGE_SVG.replace("data:image/png", "data:text/plain");
        assert_eq!(parse_svg(png, None).unwrap().images.len(), 1);
    }

    #[test]
    fn audit_rework_reference_boundaries_and_cycles() {
        for (length, cycle, expected) in
            [(32, false, true), (33, false, false), (5000, true, false)]
        {
            let mut source = String::from("<svg xmlns='http://www.w3.org/2000/svg'><defs>");
            for i in 0..length {
                source.push_str(&format!(
                    "<clipPath id='c{i}'><rect clip-path='url(#c{})'/></clipPath>",
                    i + 1
                ));
            }
            if cycle {
                source.push_str(&format!("<clipPath id='c{length}' clip-path='url(#c0)'/>"));
            } else {
                source.push_str(&format!("<clipPath id='c{length}'/>"));
            }
            source.push_str("</defs></svg>");
            let doc = parse_xml(&source).unwrap();
            assert_eq!(
                limit_source_depth(&doc).is_ok(),
                expected,
                "length={length}, cycle={cycle}"
            );
        }
        // A modest entity expansion is safe for roxmltree itself. Verify the
        // second guard inspects expanded elements rather than source tokens.
        let source = format!(
            "<!DOCTYPE svg [<!ENTITY e \"{}{}\">]><svg>&e;</svg>",
            "<g>".repeat(129),
            "</g>".repeat(129)
        );
        let doc = parse_xml(&source).unwrap();
        assert_eq!(limit_source_depth(&doc).err().as_deref(), Some(DEPTH_ERROR));
    }

    fn rework_nested_groups(depth: usize) -> String {
        format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>{}<rect width='1' height='1'/>{}</svg>", "<g opacity='.9'>".repeat(depth), "</g>".repeat(depth))
    }

    fn rework_base64(bytes: &[u8]) -> String {
        const DIGITS: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let n = ((chunk[0] as u32) << 16)
                | ((chunk.get(1).copied().unwrap_or(0) as u32) << 8)
                | chunk.get(2).copied().unwrap_or(0) as u32;
            for i in 0..4 {
                out.push(if i > chunk.len() {
                    '='
                } else {
                    DIGITS[((n >> (18 - i * 6)) & 63) as usize] as char
                });
            }
        }
        out
    }

    #[test]
    fn audit_rework_depth_limit() {
        assert_eq!(MAX_DEPTH, 128);
        assert!(check_xml_depth(&rework_nested_groups(128)).is_err());
    }

    #[test]
    fn audit_rework_subprocess() {
        if let Ok(kind) = std::env::var("XVG_REWORK_CHILD") {
            let nested = rework_nested_groups(5000);
            match kind.as_str() {
                "raw-entity" | "entity" => {
                    let value = format!(
                        "{}<rect width='1' height='1'/>{}",
                        "<g>".repeat(5000),
                        "</g>".repeat(5000)
                    );
                    let source = format!("<!DOCTYPE svg [<!ENTITY e \"{value}\">]><svg xmlns='http://www.w3.org/2000/svg'>&e;</svg>");
                    if kind == "raw-entity" {
                        eprintln!("enter roxmltree entity parse");
                        let doc = usvg::roxmltree::Document::parse_with_options(
                            &source,
                            usvg::roxmltree::ParsingOptions {
                                allow_dtd: true,
                                ..Default::default()
                            },
                        )
                        .unwrap();
                        eprintln!(
                            "roxmltree completed: {} nodes; enter usvg",
                            doc.descendants().count()
                        );
                        let _ = usvg::Tree::from_xmltree(&doc, usvg_options());
                    } else {
                        assert!(parse_svg(source, None).is_err());
                    }
                }
                "image" | "plain-image" => {
                    let encoded = rework_base64(nested.as_bytes());
                    let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><image width='10' height='10' href='data:image/svg+xml;base64,{encoded}'/></svg>");
                    let source = if kind == "plain-image" {
                        source.replace("image/svg+xml", "text/plain")
                    } else {
                        source
                    };
                    assert!(parse_svg(source, None).unwrap().images.is_empty());
                }
                "stack" => {
                    // Both release and debug have been exercised at 1 MiB;
                    // 127 groups parse, while 128 are rejected before usvg.
                    std::thread::Builder::new()
                        .stack_size(1 << 20)
                        .spawn(|| {
                            assert!(parse_svg(rework_nested_groups(127), None).is_ok());
                            assert!(parse_svg(rework_nested_groups(128), None).is_err());
                        })
                        .unwrap()
                        .join()
                        .unwrap();
                }
                "clipPath" | "mask" | "pattern" => {
                    let attr = match kind.as_str() {
                        "clipPath" => "clip-path",
                        "mask" => "mask",
                        _ => "fill",
                    };
                    let mut defs = String::new();
                    for i in 0..5000 {
                        defs.push_str(&format!("<{kind} id='r{i}' width='10' height='10'><rect width='10' height='10' {attr}='url(#r{})'/></{kind}>", i + 1));
                    }
                    let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs>{defs}</defs><rect width='10' height='10' {attr}='url(#r0)'/></svg>");
                    assert!(parse_svg(source, None).is_err(), "{kind} chain must fail");
                }
                _ => panic!("unknown child mode"),
            }
            return;
        }
        for kind in [
            "entity",
            "image",
            "plain-image",
            "stack",
            "clipPath",
            "mask",
            "pattern",
        ] {
            let output = std::process::Command::new(std::env::current_exe().unwrap())
                .args([
                    "--exact",
                    "api::svg::tests::audit_rework_subprocess",
                    "--nocapture",
                ])
                .env("XVG_REWORK_CHILD", kind)
                .output()
                .unwrap();
            assert!(
                output.status.success(),
                "{kind}: {} {}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }
    }

    #[test]
    fn audit_nonfinite_clip_geometry() {
        let tree = usvg::Tree::from_str(CLIP_SVG, usvg_options()).unwrap();
        let mut clips = Vec::new();
        build_clips(
            &tree.clip_paths()[0],
            &Transform::from_scale(f32::MAX, f32::MAX),
            &mut clips,
        );
        assert!(clips.iter().flat_map(|c| &c.points).all(|v| v.is_finite()));
    }

    #[test]
    fn audit_mask_images_remain_unsupported() {
        let image =
            &IMAGE_SVG[IMAGE_SVG.find("<image").unwrap()..IMAGE_SVG.find("</svg>").unwrap()];
        let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'><defs><mask id='m'>{image}<rect width='24' height='24' fill='white'/></mask></defs><rect width='24' height='24' mask='url(#m)'/></svg>");
        let tree = usvg::Tree::from_str(&source, usvg_options()).unwrap();
        fn has_image(g: &usvg::Group) -> bool {
            g.children().iter().any(|n| match n {
                usvg::Node::Image(_) => true,
                usvg::Node::Group(g) => has_image(g),
                _ => false,
            })
        }
        assert!(tree.masks().iter().any(|m| has_image(m.root())));
        let scene = parse_svg(source, None).unwrap();
        assert!(scene.images.is_empty());
        let mask = scene.paths[0]
            .effects
            .as_ref()
            .unwrap()
            .mask
            .as_ref()
            .unwrap();
        assert_eq!(mask.paths.len(), 1, "only the white shape is collected");
    }

    #[test]
    fn audit_full_wire_snapshot() {
        let mut hash = 0xcbf29ce484222325u64;
        for source in [
            MASK_SVG,
            CLIP_SVG,
            PATTERN_SVG,
            BLUR_SVG,
            IMAGE_SVG,
            PAINT_ORDER_SVG,
        ] {
            for b in wire_bytes(source) {
                hash = (hash ^ b as u64).wrapping_mul(0x100000001b3);
            }
        }
        // 新增的空 commands 长度也属于 SSE 载荷。
        assert_eq!(hash, 0x9e3ca7e4b26bf30b, "full SSE wire bytes changed");
    }

    fn expansion_source(shapes: usize, outputs: usize, effect: &str) -> String {
        let shape = "<rect width='10' height='10' fill='white'/>";
        let tag = if effect == "mask" { "mask" } else { "clipPath" };
        format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs><{tag} id='e'>{}</{tag}></defs><g {effect}='url(#e)'>{}</g></svg>", shape.repeat(shapes), shape.repeat(outputs))
    }

    #[test]
    fn audit_expansion_budget_2000_by_2000() {
        for effect in ["mask", "clip-path"] {
            let source = expansion_source(2000, 2000, effect);
            let start = std::time::Instant::now();
            let error = parse_svg(source, None)
                .err()
                .expect("must reject excessive expansion");
            assert_eq!(error, EXPANSION_ERROR);
            assert!(
                start.elapsed() < std::time::Duration::from_secs(2),
                "{effect}: {:?}",
                start.elapsed()
            );
            eprintln!("{effect} 2000x2000 rejected in {:?}", start.elapsed());
        }
    }

    /// Parent transforms must preserve charging before inherited geometry is cloned.
    /// 使用父组变换后，仍须在克隆继承几何之前扣除配额。
    #[test]
    fn audit_image_expansion_is_charged_before_clone() {
        let start = IMAGE_SVG.find("<image").unwrap();
        let end = start + IMAGE_SVG[start..].find("/>").unwrap() + 2;
        let image = &IMAGE_SVG[start..end];
        let source =
            expansion_source(2000, 0, "mask").replace("</g>", &format!("{}</g>", image.repeat(60)));
        assert_eq!(
            parse_svg(source, None).err().as_deref(),
            Some(EXPANSION_ERROR)
        );

        // Even the first image cannot clone inherited geometry if the
        // remaining budget is exhausted; image bytes remain uncharged too.
        let tree = usvg::Tree::from_str(IMAGE_SVG, usvg_options()).unwrap();
        // Return the image with its direct parent for conversion.
        // 同时返回图片及其直接父组以供转换。
        fn find_image(g: &usvg::Group) -> (&usvg::Image, &usvg::Group) {
            for n in g.children() {
                match n {
                    usvg::Node::Image(i) => return (i, g),
                    usvg::Node::Group(g) => return find_image(g),
                    _ => {}
                }
            }
            panic!("fixture image missing")
        }
        let mask_scene = parse_svg(MASK_SVG.into(), None).unwrap();
        let ctx = Inherited {
            mask: mask_scene.paths[0].effects.as_ref().unwrap().mask.clone(),
            ..Default::default()
        };
        let mut budget = ExpansionBudget {
            points: MAX_EXPANSION_POINTS,
            paths: 0,
            commands: 0,
        };
        let mut image_bytes = 64 * 1024 * 1024;
        let (image, parent) = find_image(tree.root());
        assert_eq!(
            convert_image(
                image,
                &parent.abs_transform(),
                &ctx,
                &mut image_bytes,
                &mut budget
            )
            .err()
            .as_deref(),
            Some(EXPANSION_ERROR)
        );
        assert_eq!(image_bytes, 64 * 1024 * 1024);
    }

    #[test]
    fn audit_expansion_near_budget() {
        for (effect, shapes, outputs) in [("mask", 100, 999), ("clip-path", 2000, 499)] {
            let scene = parse_svg(expansion_source(shapes, outputs, effect), None).unwrap();
            assert_eq!(scene.paths.len(), outputs);
            for path in &scene.paths {
                assert_eq!(path.points, vec![0., 0., 10., 0., 10., 10., 0., 10.]);
                let e = path.effects.as_ref().unwrap();
                if effect == "mask" {
                    let mask = e.mask.as_ref().unwrap();
                    assert_eq!(mask.paths.len(), shapes);
                    assert!(mask.paths.iter().all(|p| p.points == path.points));
                } else {
                    assert_eq!(e.clips.len(), 1);
                    assert_eq!(e.clips[0].points.len(), shapes * 8);
                    assert!(e.clips[0].points.chunks_exact(8).all(|p| p == path.points));
                }
            }
        }
    }

    #[test]
    fn audit_nested_mask_chain() {
        let source = r##"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
            <defs><mask id="inner"><rect width="5" height="5" fill="white"/></mask>
            <mask id="outer" mask="url(#inner)"><rect width="10" height="10" fill="white"/></mask></defs>
            <rect width="10" height="10" mask="url(#outer)"/></svg>"##;
        let tree = usvg::Tree::from_str(source, usvg_options()).unwrap();
        assert!(
            tree.masks().iter().any(|m| m.mask().is_some()),
            "upstream exposes linked masks"
        );
        let scene = parse_svg(source.into(), None).unwrap();
        let outer = scene.paths[0]
            .effects
            .as_ref()
            .unwrap()
            .mask
            .as_ref()
            .unwrap();
        assert!(
            outer.paths[0]
                .effects
                .as_ref()
                .and_then(|e| e.mask.as_ref())
                .is_some(),
            "preserve linked mask in existing effects fields"
        );
    }

    #[test]
    fn audit_image_output_budget() {
        let padded = IMAGE_SVG.replace("==\"", &format!("{}==\"", "AAAA".repeat(90_000)));
        let start = padded.find("<image").unwrap();
        let end = padded[start..].find("/>").unwrap() + start + 2;
        let image = padded[start..end].replace("<image ", "<image id='pixel' ");
        let uses = "<use href='#pixel'/>".repeat(300);
        let source = format!("<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'><defs>{image}</defs>{uses}</svg>");
        let scene = parse_svg(source, None).unwrap();
        assert!(!scene.images.is_empty());
        let bytes: usize = scene.images.iter().map(|i| i.data.len()).sum();
        assert!(bytes <= 64 * 1024 * 1024, "image output: {bytes}");
        assert!(scene.images.len() < 300);
    }

    #[test]
    fn audit_nonfinite_mask_bbox() {
        let tree = usvg::Tree::from_str(MASK_SVG, usvg_options()).unwrap();
        fn find(g: &usvg::Group) -> Option<&usvg::Mask> {
            g.mask().or_else(|| {
                g.children().iter().find_map(|n| match n {
                    usvg::Node::Group(g) => find(g),
                    _ => None,
                })
            })
        }
        let mask = find(tree.root()).unwrap();
        // A finite transform may still overflow when mapping a finite rect.
        let result = build_mask(
            mask,
            &Transform::from_scale(f32::MAX, f32::MAX),
            &mut ExpansionBudget::default(),
        )
        .unwrap();
        assert!(result.is_none(), "overflowing mask must be discarded");
    }

    #[test]
    fn audit_nonfinite_blur() {
        let svg = BLUR_SVG.replace("<rect x=", "<rect transform='scale(1e20)' x=");
        let scene = parse_svg(svg, None).unwrap();
        for p in &scene.paths {
            assert!(p
                .effects
                .as_ref()
                .and_then(|e| e.blur.as_ref())
                .is_none_or(|b| b.std_dev_x.is_finite() && b.std_dev_y.is_finite()));
        }
    }

    #[test]
    fn audit_input_limit() {
        let err = parse_svg(" ".repeat(32 * 1024 * 1024 + 1), None)
            .err()
            .unwrap();
        assert!(err.contains("32 MiB"), "{err}");
    }

    #[test]
    fn audit_root_color_location() {
        for source in [
            r#"<!-- <svg color='blue'> --><svg xmlns="http://www.w3.org/2000/svg"/>"#,
            r#"<!DOCTYPE svg [<!ENTITY fake '<svg color="blue">'>]><svg xmlns="http://www.w3.org/2000/svg"/>"#,
            r#"<x:svg xmlns:x="http://www.w3.org/2000/svg"/>"#,
        ] {
            let injected = inject_current_color(source.into(), 0xffff0000);
            let doc = usvg::roxmltree::Document::parse_with_options(
                &injected,
                usvg::roxmltree::ParsingOptions {
                    allow_dtd: true,
                    ..Default::default()
                },
            )
            .unwrap();
            assert_eq!(doc.root_element().attribute("color"), Some("#FF0000"));
            // Root insertion still finds the real SVG. The public parser now
            // rejects markup entities before roxmltree can expand them.
            if source.contains("<!ENTITY") {
                assert!(parse_svg(source.into(), Some(0xffff0000)).is_err());
            } else {
                assert!(parse_svg(source.into(), Some(0xffff0000)).is_ok());
            }
        }
        for source in ["<svgfoo/>", "<![CDATA[<svg/>]]>", "<root><svg/></root>"] {
            assert_eq!(inject_current_color(source.into(), 0xffff0000), source);
        }
    }

    #[test]
    fn audit_color_attribute_spacing_and_quotes() {
        for attrs in [
            "color = 'red'",
            "color\t=\n\"red\"",
            "data-note=\"color='blue'\"",
        ] {
            let source = format!("<svg xmlns='http://www.w3.org/2000/svg' {attrs}/>");
            let injected = inject_current_color(source, 0xff00ff00);
            let doc = usvg::roxmltree::Document::parse(&injected).unwrap();
            let expected = if attrs.starts_with("color") {
                "red"
            } else {
                "#00FF00"
            };
            assert_eq!(doc.root_element().attribute("color"), Some(expected));
        }
    }

    #[test]
    fn audit_nonfinite_transform() {
        for value in [
            "scale(1e308)",
            "matrix(1,0,0,1,1e308,0)",
            "scale(1e200) scale(1e200)",
        ] {
            assert_eq!(parse_transform(value.into()), None, "{value}");
        }
    }

    #[test]
    fn audit_xml_depth_scan_boundaries() {
        let noise = "<g>".repeat(300);
        let source = format!("<?xml version='1.0'?><!--{noise}--><?test {noise}?><!DOCTYPE svg [<!-- ] > {noise} --><?test ] >?><!ENTITY fake '{noise}'>]><svg xmlns='http://www.w3.org/2000/svg' data-note='quoted > delimiter'><![CDATA[{noise}]]>{}</svg>", "<g/>".repeat(1000));
        assert!(
            check_xml_depth(&source).is_err(),
            "markup entities are rejected even when unused"
        );
        let source = source.replace(
            &format!("<!ENTITY fake '{noise}'>"),
            "<!ENTITY fake 'text only'>",
        );
        assert!(check_xml_depth(&source).is_ok());
        parse_svg(source, None).unwrap();
        let at_limit = format!(
            "<svg xmlns='http://www.w3.org/2000/svg'>{}<rect width='1' height='1'/>{}</svg>",
            "<g>".repeat(MAX_DEPTH - 1),
            "</g>".repeat(MAX_DEPTH - 1)
        );
        assert!(check_xml_depth(&at_limit).is_ok());
        let over_limit = at_limit.replace(
            "<rect width='1' height='1'/>",
            "<g/><!-- ignored --><g></g>",
        );
        assert_eq!(
            check_xml_depth(&over_limit).err().as_deref(),
            Some(DEPTH_ERROR)
        );
        for broken in [
            "<!--",
            "<![CDATA[",
            "<?pi",
            "<!DOCTYPE svg [",
            "<svg a='>",
            "<svg",
        ] {
            assert!(check_xml_depth(broken).is_err(), "{broken}");
        }
    }

    #[test]
    fn audit_collector_depth_cutoff_preserves_subtree_behavior() {
        let tree = usvg::Tree::from_str(
            "<svg xmlns='http://www.w3.org/2000/svg'><rect width='1' height='1'/></svg>",
            usvg_options(),
        )
        .unwrap();
        let (mut paths, mut images) = (Vec::new(), Vec::new());
        for depth in [MAX_DEPTH, MAX_DEPTH - 1] {
            collect(
                tree.root(),
                &Inherited::default(),
                &mut paths,
                &mut images,
                &mut Vec::new(),
                depth,
                &mut (64 * 1024 * 1024),
                &mut ExpansionBudget::default(),
            )
            .unwrap();
            assert_eq!(paths.len(), usize::from(depth < MAX_DEPTH));
        }
        let mut subtree = Vec::new();
        append_subtree_paths_at_depth(tree.root(), &Transform::default(), &mut subtree, MAX_DEPTH);
        assert!(subtree.is_empty());
        append_subtree_paths_at_depth(
            tree.root(),
            &Transform::default(),
            &mut subtree,
            MAX_DEPTH - 1,
        );
        assert_eq!(subtree.len(), 1);
    }

    #[test]
    fn audit_extreme_depth_subprocess() {
        if let Some(kind) = std::env::var_os("XVG_EXTREME_CHILD") {
            let kind = kind.to_str().unwrap();
            let depth: usize = std::env::var("XVG_EXTREME_DEPTH")
                .unwrap()
                .parse()
                .unwrap();
            let shape = "<rect width='1' height='1'/>";
            let body = if kind == "groups" {
                format!(
                    "{}{}{}",
                    "<g opacity='.9'>".repeat(depth),
                    shape,
                    "</g>".repeat(depth)
                )
            } else {
                let mut defs = String::new();
                for i in 0..depth {
                    defs.push_str(&format!(
                        "<clipPath id='c{i}' clip-path='url(#c{})'>{shape}</clipPath>",
                        i + 1
                    ));
                }
                format!("<defs>{defs}<clipPath id='c{depth}'>{shape}</clipPath></defs><g clip-path='url(#c0)'>{shape}</g>")
            };
            let result = parse_svg(
                format!(
                    "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>{body}</svg>"
                ),
                None,
            );
            assert!(result.is_err(), "{kind} depth {depth} must be rejected");
            eprintln!(
                "{kind} depth {depth}: {}",
                if result.is_ok() { "Ok" } else { "Err" }
            );
            return;
        }
        for depth in [5000, 20000] {
            for kind in ["groups", "clips"] {
                let status = std::process::Command::new(std::env::current_exe().unwrap())
                    .args([
                        "--exact",
                        "api::svg::tests::audit_extreme_depth_subprocess",
                        "--nocapture",
                    ])
                    .env("XVG_EXTREME_CHILD", kind)
                    .env("XVG_EXTREME_DEPTH", depth.to_string())
                    .status()
                    .unwrap();
                assert!(
                    status.success(),
                    "{kind} depth {depth}: child crashed: {status}"
                );
            }
        }
    }

    #[test]
    fn audit_deep_input_subprocess() {
        if std::env::var_os("XVG_AUDIT_DEPTH_CHILD").is_some() {
            let shape = "<rect width='1' height='1'/>";
            let nested = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>{}{}{}</svg>",
                "<g opacity='.9'>".repeat(1000),
                shape,
                "</g>".repeat(1000)
            );
            // The entry scan now rejects over-depth XML before roxmltree.
            // The collector's subtree cutoff is tested separately.
            assert_eq!(parse_svg(nested, None).err().as_deref(), Some(DEPTH_ERROR));
            let siblings = format!(
                "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>{}{}{}</svg>",
                format!("<g opacity='.9'>{shape}").repeat(MAX_DEPTH - 1),
                shape,
                "</g>".repeat(MAX_DEPTH - 1)
            );
            let scene = parse_svg(siblings, None).unwrap();
            assert_eq!(
                scene.paths.len(),
                MAX_DEPTH,
                "all permitted-depth siblings survive"
            );
            let mut clips = String::new();
            for i in 0..1000 {
                clips.push_str(&format!(
                    "<clipPath id='c{i}' clip-path='url(#c{})'>{shape}</clipPath>",
                    i + 1
                ));
            }
            clips.push_str(&format!("<clipPath id='c1000'>{shape}</clipPath>"));
            assert!(parse_svg(format!("<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'><defs>{clips}</defs><g clip-path='url(#c0)'>{shape}</g></svg>"), None).is_err());
            return;
        }
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "api::svg::tests::audit_deep_input_subprocess",
                "--nocapture",
            ])
            .env("XVG_AUDIT_DEPTH_CHILD", "1")
            .status()
            .unwrap();
        assert!(
            status.success(),
            "depth test child crashed or failed: {status}"
        );
    }

    #[test]
    fn parse_color_resolves_css_named_colors() {
        assert_eq!(parse_color("red".to_string()), Some(vec![255, 0, 0, 255]));
        assert_eq!(parse_color("blue".to_string()), Some(vec![0, 0, 255, 255]));
        // A name no hand-rolled Dart table would plausibly carry.
        // 一个手写 Dart 颜色表基本不会收录的名字。
        assert_eq!(
            parse_color("cornflowerblue".to_string()),
            Some(vec![100, 149, 237, 255])
        );
        assert_eq!(
            parse_color("  red  ".to_string()),
            Some(vec![255, 0, 0, 255])
        );
    }

    #[test]
    fn parse_color_handles_hex_and_functional_forms() {
        assert_eq!(parse_color("#f00".to_string()), Some(vec![255, 0, 0, 255]));
        assert_eq!(
            parse_color("#00ff00".to_string()),
            Some(vec![0, 255, 0, 255])
        );
        assert_eq!(
            parse_color("rgb(1, 2, 3)".to_string()),
            Some(vec![1, 2, 3, 255])
        );
    }

    #[test]
    fn parse_color_rejects_non_colors() {
        assert_eq!(parse_color("none".to_string()), None);
        assert_eq!(parse_color("url(#grad)".to_string()), None);
        assert_eq!(parse_color("".to_string()), None);
    }

    fn assert_matrix(actual: Option<Vec<f32>>, expected: [f32; 6]) {
        let actual = actual.expect("expected a parsed matrix");
        for (i, e) in expected.iter().enumerate() {
            assert!(
                (actual[i] - e).abs() < 1e-4,
                "component {i}: got {}, want {e} (full: {actual:?})",
                actual[i]
            );
        }
    }

    #[test]
    fn parse_transform_handles_single_primitives() {
        assert_matrix(
            parse_transform("translate(10,20)".to_string()),
            [1.0, 0.0, 0.0, 1.0, 10.0, 20.0],
        );
        assert_matrix(
            parse_transform("scale(2)".to_string()),
            [2.0, 0.0, 0.0, 2.0, 0.0, 0.0],
        );
        assert_matrix(
            parse_transform("rotate(90)".to_string()),
            [0.0, 1.0, -1.0, 0.0, 0.0, 0.0],
        );
        assert_matrix(
            parse_transform("matrix(1 2 3 4 5 6)".to_string()),
            [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
        );
    }

    #[test]
    fn parse_transform_composes_a_full_list_left_to_right() {
        // translate(10,20) rotate(90) scale(2): a point at (1,0) must land at
        // (10, 22) — rotate then scale apply inside the translated frame.
        //
        // translate(10,20) rotate(90) scale(2)：点 (1,0) 应落在 (10, 22)——
        // rotate/scale 作用在已平移的坐标系内。
        let m = parse_transform("translate(10,20) rotate(90) scale(2)".to_string())
            .expect("valid transform list");
        let (x, y) = (1.0f32, 0.0f32);
        let px = m[0] * x + m[2] * y + m[4];
        let py = m[1] * x + m[3] * y + m[5];
        assert!((px - 10.0).abs() < 1e-4, "x = {px}");
        assert!((py - 22.0).abs() < 1e-4, "y = {py}");
    }

    #[test]
    fn parse_transform_expands_rotate_about_a_pivot() {
        // rotate(90 12 12) must fix the pivot (12,12).
        // rotate(90 12 12) 必须使支点 (12,12) 不动。
        let m = parse_transform("rotate(90 12 12)".to_string()).expect("valid transform");
        let px = m[0] * 12.0 + m[2] * 12.0 + m[4];
        let py = m[1] * 12.0 + m[3] * 12.0 + m[5];
        assert!((px - 12.0).abs() < 1e-4, "x = {px}");
        assert!((py - 12.0).abs() < 1e-4, "y = {py}");
    }

    #[test]
    fn parse_transform_rejects_garbage_and_empty_input() {
        assert_eq!(parse_transform("not-a-transform".to_string()), None);
        assert_eq!(parse_transform("".to_string()), None);
    }

    // A filled + stroked circle: exercises both fill and stroke conversion
    // paths, and MoveTo/CubicTo/Close verbs (usvg flattens arcs to cubics).
    //
    // 一个既有填充又有描边的圆：同时覆盖填充/描边转换路径，
    // 以及 MoveTo/CubicTo/Close 动词（usvg 会把圆弧展平为三次贝塞尔）。
    const CIRCLE_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" fill="#FF7A00" stroke="#000000" stroke-width="2"/>
    </svg>"##;

    #[test]
    fn parses_static_circle_into_flat_display_list() {
        let scene = parse_svg(CIRCLE_SVG.to_string(), None).expect("valid svg should parse");

        assert_eq!(scene.width, 24.0);
        assert_eq!(scene.height, 24.0);
        assert!(!scene.paths.is_empty(), "expected at least one path");

        let path = &scene.paths[0];
        assert!(!path.verbs.is_empty(), "expected flattened verbs");
        assert!(path.verbs.contains(&0), "expected a MoveTo verb");
        assert!(path.verbs.contains(&4), "expected a Close verb");
        assert_eq!(
            path.points.len(),
            path.verbs
                .iter()
                .map(|&v| match v {
                    0 | 1 => 2, // move/line: 1 point
                    2 => 4,     // quad: 2 points
                    3 => 6,     // cubic: 3 points
                    _ => 0,     // close: 0 points
                })
                .sum::<usize>(),
            "point count must match verb arity"
        );

        assert!(path.has_fill, "expected a resolved fill");
        assert_eq!(
            path.fill_argb, 0xFFFF7A00,
            "fill should resolve to opaque orange"
        );
        assert!(!path.even_odd, "default fill-rule should be nonzero");

        assert!(path.has_stroke, "expected a resolved stroke");
        assert_eq!(
            path.stroke_argb, 0xFF000000,
            "stroke should resolve to opaque black"
        );
        assert_eq!(path.stroke_width, 2.0);
        assert!(
            !path.stroke_first,
            "default paint-order should paint fill before stroke"
        );
    }

    #[test]
    fn rejects_malformed_svg() {
        let result = parse_svg("<svg><not-closed></svg>".to_string(), None);
        assert!(result.is_err());
    }

    // A `currentColor` fill with no caller-provided override should fall back
    // to usvg's own default (black), confirming baseline behavior is
    // unchanged when `current_color` is not passed.
    //
    // 未提供调用方覆盖颜色时，`currentColor` 填充应回退到 usvg 自身的默认值
    // （黑色），确认不传 `current_color` 时行为保持不变。
    const CURRENT_COLOR_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
        <path d="M2 2 L22 2 L22 22 Z" fill="currentColor"/>
    </svg>"##;

    #[test]
    fn current_color_defaults_to_black_without_override() {
        let scene = parse_svg(CURRENT_COLOR_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths[0].fill_argb, 0xFF000000);
    }

    #[test]
    fn current_color_resolves_to_caller_provided_override() {
        let scene = parse_svg(CURRENT_COLOR_SVG.to_string(), Some(0xFFFF7A00))
            .expect("valid svg should parse");
        assert_eq!(
            scene.paths[0].fill_argb, 0xFFFF7A00,
            "currentColor should resolve to the caller-provided override color"
        );
    }

    #[test]
    fn current_color_override_does_not_clobber_explicit_root_color() {
        // Root `<svg>` already declares an explicit `color`; the caller-provided
        // override must not clobber it (mirrors CSS: explicit beats inherited).
        //
        // 根 `<svg>` 已显式声明 `color`；调用方传入的覆盖色不应覆盖它
        // （对应 CSS 语义：显式声明优先于继承默认值）。
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" color="#00FF00">
            <path d="M2 2 L22 2 L22 22 Z" fill="currentColor"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), Some(0xFFFF7A00)).expect("valid svg should parse");
        assert_eq!(scene.paths[0].fill_argb, 0xFF00FF00);
    }

    #[test]
    fn current_color_injection_is_quote_aware_around_literal_gt_in_attributes() {
        // A literal unescaped `>` inside a quoted attribute value is legal,
        // unremarkable XML — a naive `find('>')` would stop there instead of
        // at the tag's real closing `>`.
        //
        // 带引号的属性值内出现字面未转义的 `>` 是合法、常见的 XML——朴素的
        // `find('>')` 会在这里而非标签真正的结束 `>` 处停下。
        let svg = r##"<svg data-note="a>b" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
            <path d="M2 2 L22 2 L22 22 Z" fill="currentColor"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), Some(0xFFFF7A00)).expect("valid svg should parse");
        assert_eq!(scene.paths[0].fill_argb, 0xFFFF7A00);
    }

    #[test]
    fn current_color_injection_is_not_fooled_by_a_decoy_color_suffixed_attribute() {
        // `data-color="..."` must not be mistaken for a real `color` attribute
        // (a plain substring search on `"color="` would false-positive here).
        //
        // `data-color="..."` 不应被误判为真正的 `color` 属性（对 `"color="` 做
        // 纯子串搜索会在这里误判）。
        let svg = r##"<svg data-color="foo" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
            <path d="M2 2 L22 2 L22 22 Z" fill="currentColor"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), Some(0xFFFF7A00)).expect("valid svg should parse");
        assert_eq!(scene.paths[0].fill_argb, 0xFFFF7A00);
    }

    #[test]
    fn mixed_fill_rule_clip_children_do_not_xor_cancel_their_overlap() {
        // Two overlapping, non-self-intersecting rects with different
        // fill-rules: the combined clip region must still cover the overlap
        // (union), not exclude it (which a naive single evenodd flag would).
        //
        // 两个重叠、自身不相交的矩形，各自不同的 fill-rule：合并后的裁剪区域
        // 仍应覆盖重叠部分（并集），而非把它排除掉（朴素的单一 evenodd 标志
        // 会导致排除）。
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
            <clipPath id="c">
                <rect x="0" y="0" width="10" height="10" fill-rule="nonzero"/>
                <rect x="5" y="5" width="10" height="10" fill-rule="evenodd"/>
            </clipPath>
            <path d="M0 0 L24 0 L24 24 L0 24 Z" fill="#000000" clip-path="url(#c)"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), None).expect("valid svg should parse");
        let clips = &scene.paths[0]
            .effects
            .as_ref()
            .expect("path should carry a clip effect")
            .clips;
        assert_eq!(clips.len(), 1);
        assert!(
            !clips[0].even_odd,
            "mixed fill rules among clip children must not fall back to a \
             single even-odd flag that XORs their overlap away"
        );
    }

    // paint-order="stroke fill" reverses the default fill-then-stroke order;
    // `stroke_first` must reflect that.
    //
    // `paint-order="stroke fill"` 反转默认的先填充后描边顺序；
    // `stroke_first` 必须如实反映。
    const PAINT_ORDER_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
        <circle cx="12" cy="12" r="10" fill="#FF7A00" stroke="#000000" stroke-width="4" paint-order="stroke fill"/>
    </svg>"##;

    // 1x1 opaque red PNG, base64-encoded — smallest fixture that exercises the
    // real `data:` URI + `usvg::ImageKind::PNG` decode path, not a mock.
    //
    // 1x1 不透明红色 PNG，base64 编码——用真实 `data:` URI +
    // `usvg::ImageKind::PNG` 解码路径的最小 fixture，非 mock。
    const IMAGE_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
        <image x="2" y="3" width="10" height="12" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="/>
    </svg>"##;

    struct ImageFixtureDir(std::path::PathBuf);

    impl ImageFixtureDir {
        fn new() -> Self {
            let path = std::env::temp_dir().join(format!(
                "xvg-image-fixture-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ));
            std::fs::create_dir(&path).expect("temporary fixture directory should be created");
            Self(path)
        }
    }

    impl Drop for ImageFixtureDir {
        fn drop(&mut self) {
            // Best effort: cleanup must not panic again while unwinding.
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn image_fixture_directory_is_removed_on_panic() {
        let mut path = None;
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let fixture = ImageFixtureDir::new();
            path = Some(fixture.0.clone());
            std::fs::write(fixture.0.join("partial.png"), b"partial").unwrap();
            panic!("simulate a fixture assertion failure");
        }));
        assert!(result.is_err());
        let path = path.unwrap();
        let removed = !path.exists();
        if !removed {
            // Keep the regression's failing run clean as well.
            std::fs::remove_dir_all(&path).unwrap();
        }
        assert!(
            removed,
            "fixture directory must be removed during unwinding"
        );
    }

    #[test]
    fn image_href_resolver_rejects_file_paths_but_preserves_data_uris() {
        const PNG_1X1: &[u8] = &[
            137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1,
            8, 6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 120, 218, 99, 252, 207,
            192, 80, 15, 0, 4, 133, 1, 128, 132, 169, 140, 33, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66,
            96, 130,
        ];
        let fixture = ImageFixtureDir::new();
        let png_path = fixture.0.join("pixel.png");
        std::fs::write(&png_path, PNG_1X1).expect("PNG fixture should be written");

        // Default usvg must load the real PNG through both path forms, proving
        // the fixture is valid; our resolver must skip it. Embedded PNGs still work.
        // 默认 usvg 须能通过两种路径加载真实 PNG，以证明夹具有效；
        // 我们的 resolver 则须跳过它。内嵌 PNG 仍能正常解析。
        let native_path = png_path.to_str().expect("fixture path should be UTF-8");
        for href in [native_path.to_string(), native_path.replace('\\', "/")] {
            let escaped_href = href
                .replace('&', "&amp;")
                .replace('"', "&quot;")
                .replace('<', "&lt;");
            let svg = format!(
                r#"<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
                    <image width="10" height="10" href="{escaped_href}"/>
                </svg>"#
            );
            let tree = usvg::Tree::from_str(&svg, &usvg::Options::default())
                .expect("default usvg should parse the external PNG fixture");
            assert_eq!(
                scene_from_tree(&tree).images.len(),
                1,
                "default usvg must load the PNG fixture: {href}"
            );
            let scene = parse_svg(svg, None).expect("external image must not fail SVG parsing");
            assert_eq!(
                scene.images.len(),
                0,
                "external image must be skipped: {href}"
            );
        }

        let scene = parse_svg(IMAGE_SVG.to_string(), None).expect("data URI PNG should parse");
        assert_eq!(scene.images.len(), 1, "embedded PNG must remain supported");
        assert!(matches!(scene.images[0].format, SvgImageFormat::Png));
    }

    #[test]
    fn parses_embedded_base64_png_into_svg_image() {
        let scene = parse_svg(IMAGE_SVG.to_string(), None).expect("valid svg should parse");
        assert!(scene.paths.is_empty(), "no path nodes in this fixture");
        assert_eq!(scene.images.len(), 1, "expected one decoded image node");

        let img = &scene.images[0];
        // The fixture's 1x1 intrinsic PNG size is fit into the specified
        // 10x12 box under the default `preserveAspectRatio="xMidYMid meet"`,
        // so the actual rendered rect is a 10x10 square centered vertically
        // within it (not a naive readout of the `<image>` tag's own
        // x/y/width/height attributes). `x`/`y`/`width`/`height` are in the
        // image's own LOCAL space (pre-`matrix`) — mapping the local
        // top-left corner through `matrix` (a plain translate here, no
        // rotation in this fixture) is what recovers the absolute (2, 4)
        // placement.
        //
        // fixture 的 1x1 固有 PNG 尺寸在默认 `preserveAspectRatio="xMidYMid
        // meet"` 下适配进指定的 10x12 盒子，实际渲染矩形是一个在盒内垂直居中
        // 的 10x10 正方形（并非 `<image>` 标签自身 x/y/width/height 属性的
        // 直接读数）。`x`/`y`/`width`/`height` 处于图片自身的本地空间
        // （`matrix` 变换之前）——把本地左上角经 `matrix`（此 fixture 中只是
        // 平移，不含旋转）映射，才能得到绝对空间里的 (2, 4) 位置。
        assert_eq!(img.matrix.len(), 6, "expected a 6-element affine matrix");
        let m = &img.matrix;
        let abs_x = m[0] * img.x + m[2] * img.y + m[4];
        let abs_y = m[1] * img.x + m[3] * img.y + m[5];
        let abs_w = (m[0] * m[0] + m[1] * m[1]).sqrt() * img.width;
        let abs_h = (m[2] * m[2] + m[3] * m[3]).sqrt() * img.height;
        assert_eq!(abs_x, 2.0);
        assert_eq!(abs_y, 4.0);
        assert_eq!(abs_w, 10.0);
        assert_eq!(abs_h, 10.0);
        assert!(!img.data.is_empty(), "expected raw decoded PNG bytes");
        assert!(matches!(img.format, SvgImageFormat::Png));
    }

    #[test]
    fn paint_order_stroke_fill_sets_stroke_first() {
        let scene = parse_svg(PAINT_ORDER_SVG.to_string(), None).expect("valid svg should parse");
        assert!(
            scene.paths[0].stroke_first,
            "paint-order=\"stroke fill\" should set stroke_first"
        );
    }

    // ---- <marker> / <switch>: expansion check ----
    // ---- <marker> / <switch>：展开验证 ----

    // A line with `marker-end`: usvg expands the marker definition into plain
    // elements at parse time, so the display list must contain the line *plus*
    // the marker's own shape — no dedicated node type is involved.
    //
    // 带 `marker-end` 的直线：usvg 在解析期把 marker 定义展开为普通元素，
    // 因此显示列表里应同时有直线和 marker 自身的形状——不涉及专门的节点类型。
    const MARKER_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="0" refY="3" orient="auto">
                <path d="M0,0 L0,6 L9,3 z" fill="#FF0000"/>
            </marker>
        </defs>
        <line x1="10" y1="50" x2="80" y2="50" stroke="#000000" stroke-width="2" marker-end="url(#arrow)"/>
    </svg>"##;

    #[test]
    fn marker_end_is_expanded_into_plain_paths() {
        let scene = parse_svg(MARKER_SVG.to_string(), None).expect("valid svg should parse");
        assert!(
            scene.paths.len() >= 2,
            "expected the line plus the expanded marker shape, got {} path(s)",
            scene.paths.len()
        );
        assert!(
            scene
                .paths
                .iter()
                .any(|p| p.has_fill && p.fill_argb == 0xFFFF0000),
            "the marker's own red-filled arrow head must appear in the display list"
        );
    }

    // `<switch>` picks the first child whose conditional attributes evaluate to
    // true; usvg resolves this at parse time, so only the selected branch may
    // reach the display list.
    //
    // `<switch>` 选取第一个条件属性求值为真的子元素；usvg 在解析期完成该选择，
    // 因此只有被选中的分支能进入显示列表。
    const SWITCH_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <switch>
            <rect requiredExtensions="http://example.com/nope" x="0" y="0" width="10" height="10" fill="#FF0000"/>
            <rect x="0" y="0" width="10" height="10" fill="#00FF00"/>
        </switch>
    </svg>"##;

    #[test]
    fn switch_keeps_only_the_first_satisfied_branch() {
        let scene = parse_svg(SWITCH_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 1, "only one <switch> branch may render");
        assert_eq!(
            scene.paths[0].fill_argb, 0xFF00FF00,
            "the branch with an unsatisfiable requiredExtensions must be skipped"
        );
    }

    // ---- <clipPath> ----

    const CLIP_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <clipPath id="c"><rect x="0" y="0" width="50" height="100"/></clipPath>
        </defs>
        <rect x="0" y="0" width="100" height="100" fill="#0000FF" clip-path="url(#c)"/>
    </svg>"##;

    #[test]
    fn clip_path_is_carried_on_the_clipped_path() {
        let scene = parse_svg(CLIP_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 1);
        let path = &scene.paths[0];
        let clips = &path.effects.as_ref().expect("expected effects").clips;
        assert_eq!(clips.len(), 1, "expected exactly one inherited clip region");
        let clip = &clips[0];
        assert!(!clip.verbs.is_empty(), "clip geometry must not be empty");
        // The clip rect spans x in [0, 50]; its points are already absolute.
        // 裁剪矩形 x 范围为 [0, 50]；其坐标已是绝对空间。
        let max_x = clip
            .points
            .iter()
            .step_by(2)
            .copied()
            .fold(f32::NEG_INFINITY, f32::max);
        assert!(max_x <= 50.0 + 1e-3, "clip max x = {max_x}");
    }

    #[test]
    fn clip_path_on_an_ancestor_group_reaches_descendant_paths() {
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
            <defs><clipPath id="c"><circle cx="50" cy="50" r="20"/></clipPath></defs>
            <g clip-path="url(#c)">
                <rect x="0" y="0" width="100" height="100" fill="#0000FF"/>
                <rect x="0" y="0" width="10" height="10" fill="#00FF00"/>
            </g>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 2);
        for path in &scene.paths {
            assert_eq!(
                path.effects.as_ref().expect("expected effects").clips.len(),
                1,
                "every descendant inherits the group clip"
            );
        }
    }

    #[test]
    fn paths_without_a_clip_path_carry_no_clip_regions() {
        let scene = parse_svg(CIRCLE_SVG.to_string(), None).expect("valid svg should parse");
        assert!(
            scene.paths[0].effects.is_none(),
            "no clip/mask/blur/pattern in use should leave effects unset"
        );
    }

    // ---- <mask> ----

    const MASK_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <mask id="m" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100">
                <rect x="0" y="0" width="50" height="100" fill="#FFFFFF"/>
            </mask>
        </defs>
        <rect x="0" y="0" width="100" height="100" fill="#0000FF" mask="url(#m)"/>
    </svg>"##;

    #[test]
    fn mask_content_is_resolved_into_absolute_paths() {
        let scene = parse_svg(MASK_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 1);
        let mask = scene.paths[0]
            .effects
            .as_ref()
            .and_then(|e| e.mask.as_ref())
            .expect("expected an inherited mask");
        assert_eq!(mask.kind, 0, "default mask-type is luminance");
        assert_eq!(mask.paths.len(), 1, "mask content is one white rect");
        assert_eq!(mask.paths[0].fill_argb, 0xFFFFFFFF);
        assert!(
            (mask.width - 100.0).abs() < 1e-3,
            "mask rect width = {}",
            mask.width
        );
        assert!((mask.height - 100.0).abs() < 1e-3);
    }

    // ---- <pattern> ----

    const PATTERN_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <pattern id="p" patternUnits="userSpaceOnUse" x="0" y="0" width="10" height="10">
                <rect x="0" y="0" width="5" height="5" fill="#FF0000"/>
            </pattern>
        </defs>
        <rect x="0" y="0" width="100" height="100" fill="url(#p)"/>
    </svg>"##;

    #[test]
    fn pattern_fill_is_resolved_into_a_repeatable_tile() {
        let scene = parse_svg(PATTERN_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 1);
        let pattern = scene.paths[0]
            .effects
            .as_ref()
            .and_then(|e| e.fill_pattern.as_ref())
            .expect("a url(#p) pattern fill must resolve to a pattern");
        assert!(
            (pattern.width - 10.0).abs() < 1e-3,
            "tile width = {}",
            pattern.width
        );
        assert!((pattern.height - 10.0).abs() < 1e-3);
        assert_eq!(pattern.matrix.len(), 6);
        assert_eq!(pattern.paths.len(), 1, "tile content is one red rect");
        assert_eq!(pattern.paths[0].fill_argb, 0xFFFF0000);
    }

    /// Pins leaf-based subroot replay, not correct objectBoundingBox rendering.
    /// 钉住基于叶子的子根重放行为，不代表 objectBoundingBox 图案渲染正确。
    #[test]
    fn pattern_object_bounding_box_content_preserves_leaf_transform() {
        let source = r##"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="90">
            <defs><pattern id="p" width=".5" height=".5" patternContentUnits="objectBoundingBox">
                <path d="M.05 .1 L.2 .1 L.2 .3 Z" fill="#ff0000"/>
            </pattern></defs>
            <g transform="translate(3 7)"><rect x="10" y="15" width="80" height="60" fill="url(#p)"/></g>
        </svg>"##;
        // Find the leaf and its direct parent without assuming wrapper depth.
        // 不假定包裹层数，查找叶子及其直接父组。
        fn first_path(group: &usvg::Group) -> Option<(&usvg::Path, &usvg::Group)> {
            for node in group.children() {
                match node {
                    usvg::Node::Path(p) => return Some((p, group)),
                    usvg::Node::Group(g) => {
                        if let Some(found) = first_path(g) {
                            return Some(found);
                        }
                    }
                    _ => {}
                }
            }
            None
        }
        let tree = usvg::Tree::from_str(source, usvg_options()).unwrap();
        let (reference, _) = first_path(tree.root()).unwrap();
        let usvg::Paint::Pattern(pattern) = reference.fill().unwrap().paint() else {
            panic!("fixture pattern missing");
        };
        let (leaf, parent) = first_path(pattern.root()).unwrap();
        assert_ne!(leaf.abs_transform(), parent.abs_transform());
        let t = Transform::default().pre_concat(leaf.abs_transform());
        let mut expected_verbs = Vec::new();
        let mut expected_points = Vec::new();
        append_segments(leaf, &t, &mut expected_verbs, &mut expected_points);
        let mut parent_verbs = Vec::new();
        let mut parent_points = Vec::new();
        append_segments(
            leaf,
            &parent.abs_transform(),
            &mut parent_verbs,
            &mut parent_points,
        );
        assert_ne!(expected_points, parent_points);

        let scene = parse_svg(source.into(), None).unwrap();
        assert_eq!(scene.paths.len(), 1);
        let tile = scene.paths[0]
            .effects
            .as_ref()
            .unwrap()
            .fill_pattern
            .as_ref()
            .unwrap();
        assert_eq!(tile.paths.len(), 1);
        let actual = &tile.paths[0];
        assert_eq!(actual.verbs, expected_verbs);
        assert_eq!(
            actual
                .points
                .iter()
                .map(|v| v.to_bits())
                .collect::<Vec<_>>(),
            expected_points
                .iter()
                .map(|v| v.to_bits())
                .collect::<Vec<_>>()
        );
        assert!(actual.has_fill);
        assert_eq!(actual.fill_argb, 0xffff0000);
        assert!(!actual.even_odd);
        assert!(!actual.has_stroke);
        assert_eq!(actual.stroke_argb, 0);
        assert_eq!(actual.stroke_width.to_bits(), 0.0f32.to_bits());
        assert!(!actual.stroke_first);
        assert!(actual.fill_gradient.is_none());
        assert!(actual.stroke_gradient.is_none());
        assert!(actual.effects.is_none());
    }

    // ---- feGaussianBlur ----

    const BLUR_SVG: &str = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
        <defs>
            <filter id="b" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="3"/>
            </filter>
        </defs>
        <rect x="20" y="20" width="60" height="60" fill="#0000FF" filter="url(#b)"/>
    </svg>"##;

    #[test]
    fn gaussian_blur_filter_is_carried_as_sigma() {
        let scene = parse_svg(BLUR_SVG.to_string(), None).expect("valid svg should parse");
        assert_eq!(scene.paths.len(), 1);
        let blur = scene.paths[0]
            .effects
            .as_ref()
            .and_then(|e| e.blur.as_ref())
            .expect("expected a resolved blur");
        assert!(
            (blur.std_dev_x - 3.0).abs() < 1e-3,
            "sigma x = {}",
            blur.std_dev_x
        );
        assert!((blur.std_dev_y - 3.0).abs() < 1e-3);
    }

    // ---- <text> ----

    #[test]
    fn text_is_silently_skipped_now_that_the_text_feature_is_off() {
        // usvg's `text` feature is disabled to shrink the release binary
        // (see rust/Cargo.toml), so `<text>` no longer flattens to glyph
        // outlines. Assert the source still parses without panic/error, that
        // the sibling shapes survive intact, and that no path was emitted
        // for the text element itself.
        //
        // usvg 的 `text` feature 已关闭以缩小 release 体积（见
        // rust/Cargo.toml），`<text>` 不再展平为字形轮廓。断言含 `<text>`
        // 的源依然能正常解析（不 panic、不报错）、同级形状完整保留，且
        // 文本元素本身没有产生任何路径。
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100">
            <rect x="0" y="0" width="20" height="20" fill="#00FF00"/>
            <text x="10" y="50" font-family="Arial, sans-serif" font-size="40" fill="#FF0000">Hi</text>
            <circle cx="150" cy="50" r="10" fill="#0000FF"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), None).expect("valid svg should parse");
        assert_eq!(
            scene.paths.len(),
            2,
            "expected only the rect and circle, <text> should contribute no paths"
        );
        assert!(scene.paths.iter().any(|p| p.fill_argb == 0xFF00FF00));
        assert!(scene.paths.iter().any(|p| p.fill_argb == 0xFF0000FF));
        assert!(
            !scene.paths.iter().any(|p| p.fill_argb == 0xFFFF0000),
            "no red glyph geometry should have been emitted for the skipped <text>"
        );
    }

    #[test]
    fn non_gaussian_filter_primitives_are_ignored_not_guessed() {
        // MVP scope: only a lone feGaussianBlur is honored. A feColorMatrix
        // must yield no blur rather than a wrong approximation.
        //
        // MVP 范围：只认单独的 feGaussianBlur。feColorMatrix 应不产生模糊，
        // 而不是给出错误的近似。
        let svg = r##"<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">
            <defs><filter id="f"><feColorMatrix type="saturate" values="0"/></filter></defs>
            <rect x="20" y="20" width="60" height="60" fill="#0000FF" filter="url(#f)"/>
        </svg>"##;
        let scene = parse_svg(svg.to_string(), None).expect("valid svg should parse");
        assert!(scene.paths[0].effects.is_none());
    }
}

#[cfg(test)]
mod final_corpus_audit {
    use super::*;
    use crate::frb_generated::SseEncode;

    // Optional read-only external corpus. Records full wire bytes AND errors so
    // the same harness can be run against HEAD without hiding rejected inputs.
    #[test]
    fn external_wire_export() {
        let Ok(list) = std::env::var("XVG_AUDIT_LIST") else {
            return;
        };
        let output = std::env::var("XVG_AUDIT_OUTPUT").unwrap();
        std::thread::Builder::new()
            .stack_size(64 << 20)
            .spawn(move || {
                use std::io::Write;
                let mut dump = std::io::BufWriter::new(std::fs::File::create(output).unwrap());
                let mut count = 0;
                let mut errors = 0;
                let (mut styled, mut uncertain, mut with_targets, mut max_targets) = (0usize, 0usize, 0usize, 0usize);
                for path in std::fs::read_to_string(list).unwrap().lines() {
                    let source =
                        String::from_utf8_lossy(&std::fs::read(path).unwrap()).into_owned();
                    if let Ok(doc) = parse_xml(&source) {
                        if doc.descendants().any(|n| n.has_tag_name("style") && n.children().filter_map(|c| c.text()).any(|s| !s.trim().is_empty())) {
                            styled += 1;
                            if checked_styles(&doc).is_ok_and(|styles| styles.iter().any(|(_, scan)| scan.uncertain)) {
                                uncertain += 1;
                                let ids: std::collections::HashSet<_> = doc.descendants()
                                    .filter(|n| n.has_tag_name("style"))
                                    .flat_map(|n| n.children().filter_map(|c| c.text()).flat_map(local_urls))
                                    .collect();
                                let targets = doc.descendants().filter(|n| n.is_element() && !matches!(n.tag_name().name(), "linearGradient" | "radialGradient") && n.attribute("id").is_some_and(|id| ids.contains(id))).count();
                                with_targets += usize::from(targets > 0);
                                max_targets = max_targets.max(targets);
                                eprintln!("conservative: {path}, non-gradient targets={targets}");
                            }
                        }
                    }
                    for cc in [None, Some(0xffff7a00)] {
                        let (status, bytes) = match parse_svg(source.clone(), cc) {
                            Ok(scene) => {
                                let mut ser =
                                    flutter_rust_bridge::for_generated::SseSerializer::new();
                                scene.sse_encode(&mut ser);
                                (1u8, ser.cursor.into_inner())
                            }
                            Err(error) => {
                                errors += 1;
                                (0u8, error.into_bytes())
                            }
                        };
                        dump.write_all(&[status]).unwrap();
                        dump.write_all(&(bytes.len() as u64).to_le_bytes()).unwrap();
                        dump.write_all(&bytes).unwrap();
                        count += 1;
                    }
                }
                dump.flush().unwrap();
                eprintln!("external corpus: {count} parses, {errors} errors; styled={styled}, uncertain={uncertain}, with non-gradient targets={with_targets}, max targets={max_targets}");
            })
            .unwrap()
            .join()
            .unwrap();
    }
}
