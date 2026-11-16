param(
  [string]$Flutter = 'C:\Users\user\development\flutter\bin\flutter.bat',
  [string]$JavaHome = 'C:\Program Files\Android\Android Studio\jbr',
  [string]$AndroidSdk = "$env:LOCALAPPDATA\Android\sdk"
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$store = Join-Path $PSScriptRoot 'local\fenru-release.jks'
$protectedPassword = Join-Path $PSScriptRoot 'local\signing-password.dpapi'
if (!(Test-Path -LiteralPath $store) -or !(Test-Path -LiteralPath $protectedPassword)) {
  throw 'The existing project signing key and DPAPI password are required. Do not generate a replacement key.'
}
$buildTools = Get-ChildItem -LiteralPath (Join-Path $AndroidSdk 'build-tools') -Directory |
  Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'apksigner.bat') } |
  Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
if ($null -eq $buildTools) { throw 'Android SDK apksigner is required.' }
$expectedCertificate = 'b2f9b21cb92f4c424d942a722986ec5b9c76c981154a7355b713b155025c629a'
$variables = @('JAVA_HOME', 'FENRU_KEYSTORE_PATH', 'FENRU_STORE_PASSWORD', 'FENRU_KEY_ALIAS', 'FENRU_KEY_PASSWORD')
$previous = @{}
foreach ($name in $variables) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$plainBytes = $null
Push-Location $projectRoot
try {
  $plainBytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
    [IO.File]::ReadAllBytes($protectedPassword), $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser
  )
  $env:JAVA_HOME = $JavaHome
  $env:FENRU_KEYSTORE_PATH = $store
  $env:FENRU_STORE_PASSWORD = [Text.Encoding]::UTF8.GetString($plainBytes)
  $env:FENRU_KEY_ALIAS = 'fenru'
  $env:FENRU_KEY_PASSWORD = $env:FENRU_STORE_PASSWORD
  # Single ABI, unsplit APK: keep the normal increasing versionCode for future updates.
  & $Flutter build apk --release --target-platform android-arm64
  if ($LASTEXITCODE -ne 0) { throw 'Project-signed Android build failed.' }
  $apk = Join-Path $projectRoot 'build\app\outputs\flutter-apk\app-release.apk'
  $signature = & (Join-Path $buildTools.FullName 'apksigner.bat') verify --verbose --print-certs $apk
  if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
  if (($signature -join "`n") -notmatch [regex]::Escape("certificate SHA-256 digest: $expectedCertificate")) {
    throw 'APK does not match the existing distribution certificate. Update artifact was not exported.'
  }
  $destination = Join-Path $projectRoot 'dist\android-update'
  New-Item -ItemType Directory -Force -Path $destination | Out-Null
  Copy-Item -LiteralPath $apk -Destination (Join-Path $destination 'Fenru-Android-release.apk') -Force
  $signature | Set-Content -LiteralPath (Join-Path $destination 'Android-signature.txt') -Encoding utf8
  $hash = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLowerInvariant()
  "$hash  Fenru-Android-release.apk" | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS-Android.txt') -Encoding utf8
  Write-Output "Existing distribution certificate verified. Update APK: $destination\Fenru-Android-release.apk"
} finally {
  if ($null -ne $plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
  foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name, $previous[$name], 'Process') }
  Pop-Location
}
