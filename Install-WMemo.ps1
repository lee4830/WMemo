$ErrorActionPreference = "Stop"

$sourceDir = Join-Path $PSScriptRoot "dist\WMemo-Portable"
$sourceExe = Join-Path $sourceDir "WMemo.exe"
if (-not (Test-Path -LiteralPath $sourceExe)) {
    throw "WMemo.exe was not found. Build or publish the app first."
}

$installDir = Join-Path $env:LOCALAPPDATA "Programs\WMemo"
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item -LiteralPath $sourceExe -Destination $installDir -Force

$installedExe = Join-Path $installDir "WMemo.exe"
$startMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$shortcutPath = Join-Path $startMenuDir "WMemo.lnk"

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $installedExe
$shortcut.WorkingDirectory = $installDir
$shortcut.IconLocation = "$installedExe,0"
$shortcut.Description = "Windows memo utility"
$shortcut.Save()

Write-Host "Installed WMemo to $installedExe"
Write-Host "Created Start Menu shortcut at $shortcutPath"
