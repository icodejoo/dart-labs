/// 洋葱管线从外到内的固定阶段。
enum DiomanStage { outer, prepare, attempt, credential, source }

/// 自定义插件在同阶段内置插件之前或之后运行。
enum DiomanEnforce { pre, post }

/// 内置名称的位置表；位置只由名称决定。
const diomanBuiltinStages = <DiomanStage, List<String>>{
  DiomanStage.outer: ['dioman:loading', 'dioman:notify'],
  DiomanStage.prepare: ['dioman:repath', 'dioman:filter', 'dioman:timeout'],
  DiomanStage.attempt: ['dioman:retry', 'dioman:breaker'],
  DiomanStage.credential: ['dioman:auth'],
  DiomanStage.source: [
    'dioman:mock',
    'dioman:share',
    'dioman:cache',
    'dioman:offline'
  ],
};
