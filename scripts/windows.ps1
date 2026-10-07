# ChemDraw one-line installer for Windows
# Open PowerShell and run:
#   powershell -c "iwr https://raw.githubusercontent.com/buildn-dev/chemdraw-installer/main/scripts/windows.ps1 -OutFile $env:TEMP\cdinstall.ps1; & $env:TEMP\cdinstall.ps1 '<S3_PACK_URL>'"
param(
  [Parameter(Mandatory=$true)][string]$PackUrl
)
$ErrorActionPreference = 'Stop'
$pack = "$env:TEMP\chemdraw-pack"
if (Test-Path $pack) { Remove-Item $pack -Recurse -Force }
New-Item -ItemType Directory -Force $pack | Out-Null

Write-Host "==> Downloading pack from S3"
Invoke-WebRequest $PackUrl -OutFile "$pack\pack.zip"

Write-Host "==> Unpacking"
Expand-Archive "$pack\pack.zip" $pack\packdir -Force
Set-Location $pack\packdir

$msi = Get-ChildItem -Recurse -Filter *.msi | Sort-Object Name | Select-Object -First 1
if (-not $msi) { throw "No .msi found in the pack" }

Write-Host "==> Installing ChemDraw Suite (native Windows) from $($msi.Name)"
Start-Process msiexec -ArgumentList "/i", "`"$($msi.FullName)`"", "/qn" -Wait

Write-Host "==> Applying pack reg entries"
Get-ChildItem -Recurse -Filter *.reg | ForEach-Object {
  Start-Process regedit -ArgumentList "/s", "`"$($_.FullName)`"" -Wait
}

Write-Host "==> Applying pack DLLs / OCXs"
$appDir = Get-ChildItem "C:\Program Files\RevvitySignalsSoftware" -Recurse -Filter ChemDraw.exe -ErrorAction SilentlyContinue |
          Select-Object -First 1 -ExpandProperty FullName
if (-not $appDir) { $appDir = Get-ChildItem "$env:APPDATA\RevvitySignalsSoftware" -Recurse -Filter ChemDraw.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
if (-not $appDir) { throw "ChemDraw.exe install location not found" }
$appPath = Split-Path $appDir

Get-ChildItem -Directory | Where-Object { $_.Name -match 'ChemDraw|Chem3D|ChemFinder|ChemScript' } |
  Copy-Item -Destination $appPath -Recurse -Force -ErrorAction SilentlyContinue
foreach ($f in 'FlxComm64.dll','FlxCore64.dll') {
  $p = Join-Path $appPath $f
  if (Test-Path $p) { Move-Item $p "$p.bak" -Force -ErrorAction SilentlyContinue }
}
Get-ChildItem -Recurse -Filter *.ocx | ForEach-Object {
  Start-Process regsvr32 -ArgumentList "/s", "`"$($_.FullName)`"" -Wait
}

Write-Host "==> Launching ChemDraw"
Start-Process $appDir -WorkingDirectory $appPath
Write-Host "Done. Choose 'Activation code' if asked (keys from the pack are already in the registry)."
