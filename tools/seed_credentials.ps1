param(
  [string]$DataDir = "build\windows\x64\runner\Release\data",
  [string]$AccountFile = ".tools\account.txt",
  [string]$Username = "",
  [string]$DisplayName = "杨逸伦"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$lines = Get-Content -LiteralPath $AccountFile
$username = if ($Username) { $Username } else { $lines[0].Trim() }
$password = $lines[1].Trim()
$payload = @{ username = $username; password = $password; displayName = $DisplayName } | ConvertTo-Json -Compress
$bytes = [Text.Encoding]::UTF8.GetBytes($payload)
$enc = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
[IO.File]::WriteAllBytes((Join-Path $DataDir 'credentials.dat'), $enc)
Write-Output "seeded credentials.dat in $DataDir (user=$username)"
