$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$local = Join-Path $PSScriptRoot 'local'
New-Item -ItemType Directory -Force $local | Out-Null
$store = Join-Path $local 'fenru-release.jks'
if (Test-Path -LiteralPath $store) { throw 'Existing signing key must not be replaced.' }
$keytool = 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
$randomBytes = [byte[]]::new(36)
[System.Security.Cryptography.RandomNumberGenerator]::Fill($randomBytes)
$password = [Convert]::ToBase64String($randomBytes)
& $keytool -genkeypair -keystore $store -storetype JKS -storepass $password -keypass $password -alias fenru -keyalg RSA -keysize 4096 -validity 10000 -dname 'CN=Fenru, OU=Fenru Project, O=vividhyeok, C=KR' -noprompt
if ($LASTEXITCODE -ne 0) { throw 'Signing key generation failed.' }
$protected = [System.Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($password), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
[IO.File]::WriteAllBytes((Join-Path $local 'signing-password.dpapi'), $protected)
function Set-RepoSecret([string]$name, [string]$value) {
  $start = [Diagnostics.ProcessStartInfo]::new('gh.exe')
  $start.ArgumentList.Add('secret'); $start.ArgumentList.Add('set'); $start.ArgumentList.Add($name)
  $start.ArgumentList.Add('--repo'); $start.ArgumentList.Add('vividhyeok/fenru')
  $start.UseShellExecute = $false
  $start.RedirectStandardInput = $true
  $start.CreateNoWindow = $true
  $process = [Diagnostics.Process]::Start($start)
  $process.StandardInput.Write($value)
  $process.StandardInput.Close()
  $process.WaitForExit()
  if ($process.ExitCode -ne 0) { throw "GitHub secret save failed: $name. Local protected files are retained." }
}
Set-RepoSecret 'FENRU_KEYSTORE_B64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($store)))
Set-RepoSecret 'FENRU_STORE_PASSWORD' $password
Set-RepoSecret 'FENRU_KEY_ALIAS' 'fenru'
Set-RepoSecret 'FENRU_KEY_PASSWORD' $password
Write-Output 'Project signing key generated. Password protected by Windows DPAPI; GitHub Secrets configured.'
