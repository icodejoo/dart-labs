/// Test doubles for apps that embed mova: run widget tests with real
/// `MovaEngine`s on a scriptable kernel, never touching media_kit.
///
/// 给嵌入 mova 的应用用的测试替身：在可编程内核上跑真实的 `MovaEngine`，完全不碰
/// media_kit。
library;

export 'src/testing/test_kernel.dart';
export 'src/testing/testing.dart';
