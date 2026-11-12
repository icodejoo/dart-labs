# mova_example

Demonstrates how to use the mova plugin.

## Entrypoints

Each entrypoint is a standalone `main()`, selected with `-t`. Only the main
ones are listed here; the many other `lib/main_*_verify.dart` files are
one-off device verification pages (their helpers live in `lib/verify_auto/`)
and are not demos.

| Entrypoint | Purpose |
|---|---|
| `lib/main.dart` | The general demo: VOD, live, time-shift, feed and preview |
| `lib/main_seamless_test.dart` | Automated acceptance for the seamless ad -> content cutover |
| `lib/main_ad_orchestration_verify.dart` | No-click acceptance run for ad orchestration |
| `lib/main_keep_alive_verify.dart` | Hidden-card keep-alive (standby) verification |
| `lib/main_coverage_api.dart` | API coverage run, including the in-app mini window (`MovaMini`) |
| `lib/main_qoe_verify.dart` | QoE reporting verification (TTFF, stalls, session end reasons) |
| `lib/main_host_ergonomics_verify.dart` | Host ergonomics (first frame, poster, recovery, auto-pause) verification |
| `lib/main_cp0_suite_verify.dart` ... `lib/main_cp3_suite_verify.dart` | Device acceptance suites CP0 to CP3 |
| `lib/main_coverage_suite.dart` | Combined device coverage run |
| `lib/spike_*.dart` | One-off technical spikes, not demos |

Run one of them:

```bash
flutter run -t lib/main.dart -d windows
flutter run -t lib/main_seamless_test.dart
```

> A repo path deep enough to exceed Windows' 260-char limit breaks the media_kit
> plugin build (MSB3491); `subst X: <repo root>` and run from `X:\mova\example`.

## Getting Started

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)
