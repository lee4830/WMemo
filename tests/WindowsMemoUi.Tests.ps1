$ErrorActionPreference = "Stop"

$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) "src/WindowsMemo.ps1"
$raw = Get-Content -Raw -LiteralPath $scriptPath -Encoding UTF8
$launcherPath = Join-Path (Split-Path -Parent $PSScriptRoot) "Run-WindowsMemo.vbs"
$launcherRaw = Get-Content -Raw -LiteralPath $launcherPath -Encoding UTF8

function K {
    param([int[]]$CodePoints)
    return [string]::Concat(($CodePoints | ForEach-Object { [char]$_ }))
}

function Assert-ContainsText {
    param([string]$Needle)
    if (-not $raw.Contains($Needle)) {
        throw "Assertion failed: WindowsMemo.ps1 should contain expected Korean UI text."
    }
}

function Assert-DoesNotContainText {
    param([string]$Needle)
    if ($raw.Contains($Needle)) {
        throw "Assertion failed: WindowsMemo.ps1 should not contain '$Needle'."
    }
}

function Assert-LauncherContainsText {
    param([string]$Needle)
    if (-not $launcherRaw.Contains($Needle)) {
        throw "Assertion failed: Run-WindowsMemo.vbs should contain '$Needle'."
    }
}

Assert-ContainsText (K @(0xC708, 0xB3C4, 0xC6B0, 0x20, 0xBA54, 0xBAA8))
Assert-ContainsText (K @(0xC0C8, 0x20, 0xBA54, 0xBAA8))
Assert-ContainsText (K @(0xC800, 0xC7A5))
Assert-ContainsText (K @(0xC0AD, 0xC81C))
Assert-ContainsText (K @(0xC815, 0xBCF4))
Assert-ContainsText (K @(0xBC31, 0xC5C5))
Assert-ContainsText (K @(0xC124, 0xC815))
Assert-ContainsText ("yyyy" + (K @(0xB144)) + " MM" + (K @(0xC6D4)) + " dd" + (K @(0xC77C)) + " HH" + (K @(0xC2DC)) + " mm" + (K @(0xBD84)))
Assert-ContainsText (K @(0xC804, 0xCCB4, 0x20, 0xBC31, 0xC5C5))
Assert-ContainsText ((K @(0xC77D, 0xC744, 0x20, 0xC218, 0x20, 0xC788, 0xB294)) + " TXT " + (K @(0xBC31, 0xC5C5)))
Assert-ContainsText "CloseReason"
Assert-ContainsText "UserClosing"
Assert-ContainsText "Open-InfoWindow"
Assert-ContainsText "Open-BackupWindow"
Assert-ContainsText "Open-SettingsWindow"
Assert-ContainsText '$restoreValue'
Assert-ContainsText 'LastRestoredAt'
Assert-ContainsText (K @(0xC804, 0xCCB4, 0x20, 0xBA54, 0xBAA8, 0x20, 0xC0AD, 0xC81C))
Assert-ContainsText "Clear-Memos"
Assert-ContainsText (K @(0xC81C, 0xBAA9, 0x20, 0xAC00, 0xB098, 0xB2E4, 0x2F, 0x41, 0x42, 0x43, 0xC21C))
Assert-ContainsText (K @(0xAC80, 0xC0C9, 0xC5B4, 0xB97C, 0x20, 0xC785, 0xB825, 0xD558, 0xC138, 0xC694))
Assert-ContainsText '$metaLabel'
Assert-ContainsText '$script:SearchHintActive'
Assert-ContainsText '$clearSearchButton'
Assert-ContainsText 'Clear-SearchBox'
Assert-ContainsText '$categoryCombo'
Assert-ContainsText '$categoryFilterCombo'
Assert-ContainsText 'Open-CategoryManager'
Assert-ContainsText (K @(0xCE74, 0xD14C, 0xACE0, 0xB9AC, 0x20, 0xAD00, 0xB9AC))
Assert-ContainsText (K @(0xCD94, 0xAC00, 0xD560, 0x20, 0xCE74, 0xD14C, 0xACE0, 0xB9AC, 0x20, 0xC774, 0xB984, 0xC744, 0x20, 0xC785, 0xB825, 0xD558, 0xC138, 0xC694))
Assert-ContainsText (K @(0xC804, 0xCCB4, 0x20, 0xCE74, 0xD14C, 0xACE0, 0xB9AC, 0xB294, 0x20, 0xC0AD, 0xC81C, 0xD560, 0x20, 0xC218, 0x20, 0xC5C6, 0xC2B5, 0xB2C8, 0xB2E4))
Assert-ContainsText 'AcceptButton'
Assert-ContainsText '$statusLabel'
Assert-ContainsText '$deleteAllPanel'
Assert-ContainsText 'SetColumnSpan'
Assert-ContainsText '$categoryNameBox'
Assert-ContainsText '$titlePanel'
Assert-ContainsText '$titleDividerLabel'
Assert-LauncherContainsText 'WindowStyle Hidden'
Assert-LauncherContainsText 'shell.Run command, 0, False'
Assert-DoesNotContainText '$input.Text'
Assert-DoesNotContainText '$tabControl'
Assert-DoesNotContainText 'TabPage'
Assert-DoesNotContainText "DateTimePicker"

Write-Host "WindowsMemo Korean UI text tests passed."
