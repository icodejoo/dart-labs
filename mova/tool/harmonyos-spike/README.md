# 鸿蒙（HarmonyOS / OpenHarmony）Flutter 最小工程归档

2026-10-28 的一次可行性探路：在 Windows 上用 Flutter-OH 构建一个最小 Flutter 工程，产出 HAP。
**结论与坑位见 [../../doc/notes/2026-10-28-harmonyos-hello-spike.md](../../doc/notes/2026-10-28-harmonyos-hello-spike.md)**，
可行性评估见 [../../doc/notes/2026-10-28-harmonyos-next-feasibility.md](../../doc/notes/2026-10-28-harmonyos-next-feasibility.md)。

一句话结论：HAP 已构建但**未签名**；`@ohos/flutter_ohos` 要求 `compatibleSdkVersion >= 12`（HarmonyOS 5.0），
HarmonyOS 4.2（API 9–11）大概率装不上。运行时是 OpenHarmony，能否装到纯血 HarmonyOS 机型未验证。

## 目录

| 路径 | 说明 |
|---|---|
| `hello_ohos/` | 主工程，Flutter-OH 3.41.9+ohos-1.0.2 + OpenHarmony 7.0 SDK（API 26），产出 HAP 的那个 |
| `hello35/` | 对照工程，Flutter-OH 3.35.7 线，只存源码 |
| `ohos-env.ps1` | 构建环境脚本（dot-source，只改当前会话 PATH）：`$env:OHOS_SDK='7'; . .\ohos-env.ps1` |
| `ohos-sign-oh.ps1` | 用 OpenHarmony SDK 自带调试证书签名的尝试，**未跑通**（证书链校验失败），不建议再投入 |
| `obs_proxy.py` | 本地回源代理：华为云 OBS 对本机极不稳，分块并行 + 无限重试 + 落盘缓存，用 `FLUTTER_OHOS_STORAGE_BASE_URL=http://127.0.0.1:8099` 指过去 |
| `SHA256SUMS.txt` | 两个未签名 HAP 的哈希（HAP 本体不入库：debug 96MB、release 19.5MB，可按文档重新构建） |

## 没有归档的东西

- **HAP 本体**：见上，体积大且可复现；哈希在 `SHA256SUMS.txt`。
- **构建产物与缓存**：`build/`、`.hvigor/`、`oh_modules/`、`node_modules/`、`ohos/entry/libs/`、`flutter_assets/` 等已排除。
- **工具链**：Flutter-OH 源码、OpenHarmony SDK、命令行工具等在 `E:\sdk\`（`ohos-cli6`、`ohos-sdk7`、`flutter-ohos-3.41.9` 等）与 `E:\sdk\_dl`（安装包与 OBS 缓存，约 12GB，可清理）。工具链是第三方镜像取得的，官方包下载需登录。
- **签名材料**：未生成可用的设备签名，`sign-work/` 的中间文件不入库。

## 构建

```powershell
$env:OHOS_SDK='7'; . .\ohos-env.ps1
cd hello_ohos
flutter build hap --debug   --no-codesign   # → build\ohos\hap\entry-default-unsigned.hap
flutter build hap --release --no-codesign
```

bundleName `com.example.mova.hello_ohos`，HAP 的 `minAPIVersion=12`，只含 arm64。

代码里路径写死了 `E:\sdk`、`E:\w`，换机器要改 `ohos-env.ps1`。
