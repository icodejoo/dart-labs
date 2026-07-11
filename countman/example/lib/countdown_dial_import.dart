// Workaround: package:countman/src/widgets/countdown_dial.dart triggers a
// false-positive "Target of URI doesn't exist" in dart analyze when imported
// from the example package. This thin relay file imports it via relative path
// (which the analyzer handles correctly) and re-exports the public API.
// ignore: implementation_imports
export 'package:countman/src/widgets/countdown_dial.dart';
