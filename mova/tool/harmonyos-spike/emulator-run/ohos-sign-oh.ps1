# 用 OpenHarmony SDK 自带调试材料给 HAP 签名（已跑通，取代上级目录里未跑通的同名脚本）。
# 关键点：p12 里的 "openharmony application release" 是自签证书，不能直接拼链；
# 正确的应用证书链 = 模板 JSON 内嵌的 development-certificate（CA 签发，公钥与 p12 release 私钥一致）+ Application CA + Root CA。
# debug profile 必须写入设备 UDID（BMS 报 9568423 device is unauthorized）；设备取不到 UDID 时用 -ProfileType release（不绑设备，app-distribution-type=os_integration）。
# 用法：.\ohos-sign-oh.ps1 -Hap in.hap -Out out.hap [-ProfileType debug|release] [-Udid <设备UDID>] [-Work <中间目录>]
param(
  [Parameter(Mandatory)] [string] $Hap,
  [Parameter(Mandatory)] [string] $Out,
  [string] $Bundle = 'com.example.mova.hello_ohos',
  [string] $Udid = '',
  [ValidateSet('debug','release')] [string] $ProfileType = 'debug',
  [string] $Work = (Join-Path (Split-Path $Out) 'sign-work')
)
$ErrorActionPreference = 'Stop'
$jdk = 'E:\sdk\jdk\jdk-17.0.18+8\bin'; $lib = 'E:\sdk\ohos-sdk7\sdk\26\toolchains\lib'
$ks = "$lib\OpenHarmony.p12"; $pw = '123456'; $jar = "$lib\hap-sign-tool.jar"
New-Item -ItemType Directory -Force $Work | Out-Null

# 1) Profile：换包名、刷新有效期；debug 写入 device-ids
$isRel = $ProfileType -eq 'release'
$tpl = if ($isRel) { 'UnsgnedReleasedProfileTemplate.json' } else { 'UnsgnedDebugProfileTemplate.json' }
$ppem = if ($isRel) { 'OpenHarmonyProfileRelease.pem' } else { 'OpenHarmonyProfileDebug.pem' }
$palias = if ($isRel) { 'openharmony application profile release' } else { 'openharmony application profile debug' }
$p = Get-Content "$lib\$tpl" -Raw | ConvertFrom-Json
$p.'bundle-info'.'bundle-name' = $Bundle
$p.validity.'not-before' = [int][DateTimeOffset]::UtcNow.AddDays(-1).ToUnixTimeSeconds()
$p.validity.'not-after'  = [int][DateTimeOffset]::UtcNow.AddDays(365).ToUnixTimeSeconds()
if (-not $isRel) { $p.'debug-info'.'device-ids' = if ($Udid) { @($Udid) } else { @() } }
$p | ConvertTo-Json -Depth 10 | Set-Content "$Work\profile.json" -Encoding utf8

# 2) 应用证书链：模板内嵌的 CA 签发 release 证书 + CA + Root（后两张取自 profile pem 的前两段）
$pem = Get-Content "$lib\$ppem" -Raw
$certs = [regex]::Matches($pem, '-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----', 'Singleline') | % Value  # [0]=root [1]=CA [2]=profile leaf
$leaf = $(if ($isRel) { $p.'bundle-info'.'distribution-certificate' } else { $p.'bundle-info'.'development-certificate' }).Trim()
Set-Content "$Work\app-chain.pem" ($leaf + "`n" + $certs[1] + "`n" + $certs[0] + "`n") -Encoding ascii

# 3) 签 Profile → p7b
& "$jdk\java.exe" -jar $jar sign-profile -keyAlias $palias -signAlg SHA256withECDSA -mode localSign `
  -profileCertFile "$lib\$ppem" -inFile "$Work\profile.json" -keystoreFile $ks -outFile "$Work\profile.p7b" -keyPwd $pw -keystorePwd $pw
# 4) 签 HAP
& "$jdk\java.exe" -jar $jar sign-app -keyAlias 'openharmony application release' -signAlg SHA256withECDSA -mode localSign `
  -appCertFile "$Work\app-chain.pem" -profileFile "$Work\profile.p7b" -inFile $Hap -keystoreFile $ks -outFile $Out -keyPwd $pw -keystorePwd $pw
# 5) 验签
& "$jdk\java.exe" -jar $jar verify-app -inFile $Out -outCertChain "$Work\verify-chain.cer" -outProfile "$Work\verify-profile.p7b"
Write-Host "signed: $Out"
