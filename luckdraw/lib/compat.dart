/// lucky-canvas JSON 迁移入口；仅显式引入时加载 CSS 解析器。
library;

export 'src/compat/compat_options.dart'
    show
        LuckyCanvasCompatOptions,
        LuckyCanvasCompatResult,
        LuckyCanvasCompatWarning;
export 'src/compat/css_color.dart' show parseCssColor;
export 'src/compat/css_fill.dart' show parseCssFill;
export 'src/compat/css_length.dart' show parseCssLength;
export 'src/compat/css_misc.dart' show parseCssFontWeight, parseCssPadding;
export 'src/compat/css_shadow.dart' show parseCssShadow;
export 'src/compat/easing_names.dart' show kLuckyCanvasEasingNames;
export 'src/compat/grid_compat.dart' show gridFromLuckyCanvasConfig;
export 'src/compat/slot_compat.dart' show slotFromLuckyCanvasConfig;
export 'src/compat/wheel_compat.dart' show wheelFromLuckyCanvasConfig;
