# [未跑通] 本机实测 sign-app 报 "verify certificate chain failed"，证书链导出方式有误；零售华为机也不认 OpenHarmony 调试证书。仅留作参考。
# 用 OpenHarmony SDK 自带的调试证书给 HAP 签名（仅「OpenHarmony 设备/开发板」可信；华为零售机一般不认，需 AGC 调试证书+Profile）。
# 用法：.\ohos-sign-oh.ps1 -Hap E:\w\hello_ohos-release-unsigned.hap -Out E:\w\hello_ohos-release-ohsigned.hap [-Udid <设备UDID>]
param(
  [Parameter(Mandatory)] [string] $Hap,
  [Parameter(Mandatory)] [string] $Out,
  [string] $Bundle = 'com.example.mova.hello_ohos',
  [string] $Udid = ''
)
$ErrorActionPreference = 'Stop'
$jdk  = 'E:\sdk\jdk\jdk-17.0.18+8\bin'
$lib  = 'E:\sdk\ohos-sdk7\sdk\26\toolchains\lib'
$work = Join-Path (Split-Path $Out) 'sign-work'
New-Item -ItemType Directory -Force $work | Out-Null
$ks = "$lib\OpenHarmony.p12"; $pw = '123456'

# 1) 调试 Profile：换包名；有 UDID 就写入 device-ids
$p = Get-Content "$lib\UnsgnedDebugProfileTemplate.json" -Raw | ConvertFrom-Json
$p.'bundle-info'.'bundle-name' = $Bundle
$p.validity.'not-before' = [int][DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeSeconds()
$p.validity.'not-after'  = [int][DateTimeOffset]::UtcNow.AddDays(365).ToUnixTimeSeconds()
if ($Udid) { $p.'debug-info'.'device-ids' = @($Udid) } else { $p.'debug-info'.'device-ids' = @() }
$p | ConvertTo-Json -Depth 10 | Set-Content "$work\profile.json" -Encoding utf8

# 2) 导出应用证书链（release 证书 + application CA + root CA）
$chain = ''
foreach ($a in 'openharmony application release','openharmony application ca','openharmony application root ca') {
  $chain += (& "$jdk\keytool.exe" -exportcert -rfc -alias $a -keystore $ks -storepass $pw 2>$null) -join "`n"; $chain += "`n"
}
Set-Content "$work\app-chain.pem" $chain -Encoding ascii

# 3) 签 Profile
& "$jdk\java.exe" -jar "$lib\hap-sign-tool.jar" sign-profile -keyAlias 'openharmony application profile debug' -signAlg SHA256withECDSA -mode localSign `
  -profileCertFile "$lib\OpenHarmonyProfileDebug.pem" -inFile "$work\profile.json" -keystoreFile $ks -outFile "$work\profile.p7b" -keyPwd $pw -keystorePwd $pw
# 4) 签 HAP
& "$jdk\java.exe" -jar "$lib\hap-sign-tool.jar" sign-app -keyAlias 'openharmony application release' -signAlg SHA256withECDSA -mode localSign `
  -appCertFile "$work\app-chain.pem" -profileFile "$work\profile.p7b" -inFile $Hap -keystoreFile $ks -outFile $Out -keyPwd $pw -keystorePwd $pw
# 5) 验签
& "$jdk\java.exe" -jar "$lib\hap-sign-tool.jar" verify-app -inFile $Out -outCertChain "$work\verify-chain.cer" -outProfile "$work\verify-profile.p7b"
Write-Host "signed: $Out"
