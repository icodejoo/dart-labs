# 鸿蒙版 Flutter 开发环境（dot-source 使用：. E:\sdk\ohos-env.ps1）。只改当前会话，不动全局环境变量。
# 默认用 6.0.1.251（API 21，Flutter-OH 3.41.9 需要）；设 $env:OHOS_CLI='5' 可切回 5.0.5.200（API 13，编不过 flutter_ohos）
$ohosCli   = if ($env:OHOS_CLI -eq '5') { 'E:\sdk\ohos-cli\command-line-tools' } else { 'E:\sdk\ohos-cli6\command-line-tools' }
# Flutter-OH 版本：默认 3.41.9+ohos-1.0.2；设 $env:OHOS_FLUTTER='3.35.7' 用 3.35.7+ohos-1.0.5
$ohosFlut  = if ($env:OHOS_FLUTTER -eq '3.35.7') { 'E:\sdk\flutter-ohos-3.35.7' } else { 'E:\sdk\flutter-ohos-3.41.9' }
$jdk17     = 'E:\sdk\jdk\jdk-17.0.18+8'

$env:JAVA_HOME        = $jdk17
$env:HOS_SDK_HOME     = "$ohosCli\sdk"                 # 内含 default\{hms,openharmony}，API 13（HarmonyOS 5.0.1）
$env:DEVECO_SDK_HOME  = "$ohosCli\sdk"
$env:NODE_HOME        = "$ohosCli\tool\node"           # Flutter-OH 写入 local.properties 的 nodejs.dir
$env:DEVECO_NODE_HOME = "$ohosCli\tool\node"
$env:PUB_CACHE        = 'E:\sdk\pub-cache-ohos'         # 与现有 Flutter 的 pub 缓存隔离
$env:PUB_HOSTED_URL   = 'https://pub.flutter-io.cn'
# Flutter-OH 引擎/Dart SDK 默认源：https://flutter-ohos.obs.cn-south-1.myhuaweicloud.com（不必设置 FLUTTER_STORAGE_BASE_URL）
$env:FLUTTER_GIT_URL  = 'https://gitcode.com/CPF-Flutter/flutter_flutter.git'

$toolsPath = @(
  'C:\Program Files\Git\cmd',                          # Flutter 取版本/pub 需要 git
  "$jdk17\bin",
  "$ohosFlut\bin",
  "$ohosCli\bin",                                      # ohpm / hvigorw / codelinter
  "$ohosCli\tool\node",
  "$ohosCli\sdk\default\openharmony\toolchains"        # hdc.exe
) -join ';'
# 设 $env:OHOS_SDK='7' 改用 OpenHarmony 7.0 公开 SDK（API 26，官方镜像可匿名下载）；hvigor/ohpm/node 仍用 command-line-tools 6.0.1
if ($env:OHOS_SDK -eq '7') {
  $env:OHOS_SDK_HOME    = 'E:\sdk\ohos-sdk7\sdk'     # 内含 26\{ets,js,native,previewer,toolchains}
  $env:DEVECO_SDK_HOME  = 'E:\sdk\ohos-sdk7\sdk'
  $env:OHOS_BASE_SDK_HOME = 'E:\sdk\ohos-sdk7\sdk'   # hvigor 对 OpenHarmony 工程要这个变量
  Remove-Item Env:HOS_SDK_HOME -ErrorAction SilentlyContinue
  $toolsPath = "$toolsPath;E:\sdk\ohos-sdk7\sdk\26\toolchains"
}
$env:Path = "$toolsPath;$env:Path"
Write-Host "[ohos-env] flutter-ohos=$ohosFlut sdk=$env:HOS_SDK_HOME"
