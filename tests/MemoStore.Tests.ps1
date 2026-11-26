$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root "src/MemoStore.psm1"
Import-Module $modulePath -Force

$allCategory = [string]::Concat(@([char]0xC804, [char]0xCCB4))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) {
        throw "Assertion failed: $Message. Expected '$Expected', got '$Actual'"
    }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsMemoTests-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null

try {
    $storePath = Join-Path $tempRoot "memos.json"
    $settingsPath = Join-Path $tempRoot "settings.json"
    $backupPath = Join-Path $tempRoot "backup.memo-backup.json"
    $txtDir = Join-Path $tempRoot "txt"

    Initialize-MemoStore -StorePath $storePath -SettingsPath $settingsPath

    $first = New-Memo -StorePath $storePath -Title "Windows utility idea" -PlainText "Backup tabs and rich text editor" -Rtf "{\rtf1 Backup tabs}"
    Start-Sleep -Milliseconds 20
    $second = New-Memo -StorePath $storePath -Title "Meeting memo" -PlainText "Search should include body text" -Rtf "{\rtf1 Search body}"

    Assert-True ($first.Id.Length -gt 0) "new memo has an id"
    Assert-Equal "Windows utility idea" $first.Title "new memo title is saved"
    Assert-True ($first.CreatedAt -eq $first.UpdatedAt) "created memo starts with matching created and updated timestamps"

    Start-Sleep -Milliseconds 20
    $updated = Save-Memo -StorePath $storePath -Id $first.Id -Title "Windows utility idea updated" -PlainText "Readable TXT backup" -Rtf "{\rtf1 Updated}"
    Assert-Equal $first.CreatedAt $updated.CreatedAt "updating preserves created time"
    Assert-True ([datetime]$updated.UpdatedAt -gt [datetime]$first.UpdatedAt) "updating advances modified time"

    $titleResults = @(Search-Memos -StorePath $storePath -Query "meeting" -SortBy "CreatedDesc")
    Assert-Equal 1 $titleResults.Count "search finds title matches"
    Assert-Equal "Meeting memo" $titleResults[0].Title "title search returns expected memo"

    $bodyResults = @(Search-Memos -StorePath $storePath -Query "readable" -SortBy "CreatedDesc")
    Assert-Equal 1 $bodyResults.Count "search finds body matches"
    Assert-Equal "Windows utility idea updated" $bodyResults[0].Title "body search returns expected memo"

    $createdAsc = @(Search-Memos -StorePath $storePath -Query "" -SortBy "CreatedAsc")
    Assert-Equal $first.Id $createdAsc[0].Id "created ascending returns oldest memo first"

    $titleStorePath = Join-Path $tempRoot "title-sort.json"
    Initialize-MemoStore -StorePath $titleStorePath -SettingsPath $settingsPath
    New-Memo -StorePath $titleStorePath -Title "banana" -PlainText "b" -Rtf "{\rtf1 b}" | Out-Null
    New-Memo -StorePath $titleStorePath -Title "apple" -PlainText "a" -Rtf "{\rtf1 a}" | Out-Null
    New-Memo -StorePath $titleStorePath -Title "cherry" -PlainText "c" -Rtf "{\rtf1 c}" | Out-Null
    $titleAsc = @(Search-Memos -StorePath $titleStorePath -Query "" -SortBy "TitleAsc")
    Assert-Equal "apple" $titleAsc[0].Title "title ascending sorts abc titles first"
    Assert-Equal "banana" $titleAsc[1].Title "title ascending sorts abc titles second"

    Export-MemoTxtBackup -StorePath $storePath -DestinationDirectory $txtDir
    Assert-True (Test-Path (Join-Path $txtDir "index.txt")) "TXT backup writes index"
    $txtFiles = Get-ChildItem -Path $txtDir -Filter "*.txt"
    Assert-True ($txtFiles.Count -ge 3) "TXT backup writes readable memo files"
    $indexText = Get-Content -Raw (Join-Path $txtDir "index.txt")
    Assert-True ($indexText.Contains("Windows utility idea updated")) "TXT backup index contains memo title"

    Export-MemoFullBackup -StorePath $storePath -DestinationFile $backupPath
    Assert-True (Test-Path $backupPath) "full backup file is written"

    $restoreStorePath = Join-Path $tempRoot "restored.json"
    Initialize-MemoStore -StorePath $restoreStorePath -SettingsPath $settingsPath
    Restore-MemoFullBackup -StorePath $restoreStorePath -BackupFile $backupPath
    $restored = @(Get-Memos -StorePath $restoreStorePath)
    Assert-Equal 2 $restored.Count "restore preserves memo count"
    Assert-True (@($restored | Where-Object { $_.Title -eq "Windows utility idea updated" }).Count -eq 1) "restore preserves updated memo"

    $settings = Save-MemoSettings -SettingsPath $settingsPath -Settings @{
        FontFamily = "Segoe UI"
        TitleFontSize = 22
        BodyFontSize = 14
        TitleColor = "#111827"
        BodyColor = "#1f2937"
        BackgroundColor = "#ffffff"
    }
    Assert-Equal "Segoe UI" $settings.FontFamily "settings save font family"
    Assert-Equal 22 $settings.TitleFontSize "settings save title size"
    Assert-True ($null -ne $settings.PSObject.Properties["LastRestoredAt"]) "settings include restore timestamp field"
    Assert-True ($null -ne $settings.PSObject.Properties["CloseToTray"]) "settings include close to tray field"
    Assert-True ($null -ne $settings.PSObject.Properties["StartWithWindows"]) "settings include startup field"

    $singleStorePath = Join-Path $tempRoot "single.json"
    Initialize-MemoStore -StorePath $singleStorePath -SettingsPath $settingsPath
    $single = New-Memo -StorePath $singleStorePath -Title "Only memo" -PlainText "Delete me" -Rtf "{\rtf1 Delete me}"
    Remove-Memo -StorePath $singleStorePath -Id $single.Id
    $afterSingleDelete = @(Get-Memos -StorePath $singleStorePath)
    Assert-Equal 0 $afterSingleDelete.Count "deleting the last memo leaves an empty list"

    $clearStorePath = Join-Path $tempRoot "clear-all.json"
    Initialize-MemoStore -StorePath $clearStorePath -SettingsPath $settingsPath
    New-Memo -StorePath $clearStorePath -Title "First" -PlainText "One" -Rtf "{\rtf1 One}" | Out-Null
    New-Memo -StorePath $clearStorePath -Title "Second" -PlainText "Two" -Rtf "{\rtf1 Two}" | Out-Null
    Clear-Memos -StorePath $clearStorePath
    $afterClear = @(Get-Memos -StorePath $clearStorePath)
    Assert-Equal 0 $afterClear.Count "clear all removes every memo"

    $categoryStorePath = Join-Path $tempRoot "categories.json"
    $categorySettingsPath = Join-Path $tempRoot "category-settings.json"
    Initialize-MemoStore -StorePath $categoryStorePath -SettingsPath $categorySettingsPath
    $categories = @(Get-MemoCategories -SettingsPath $categorySettingsPath)
    Assert-Equal $allCategory $categories[0] "default category is all"

    Add-MemoCategory -SettingsPath $categorySettingsPath -Name "Work" | Out-Null
    $koreanCategory = [string]::Concat(@([char]0xC77C, [char]0xC0C1))
    Add-MemoCategory -SettingsPath $categorySettingsPath -Name $koreanCategory | Out-Null
    Save-MemoSettings -SettingsPath $categorySettingsPath -Settings @{
        FontFamily = "Malgun Gothic"
        BodyFontSize = 15
    } | Out-Null
    $categories = @(Get-MemoCategories -SettingsPath $categorySettingsPath)
    Assert-True ($categories -contains "Work") "added category is saved"
    Assert-True ($categories -contains $koreanCategory) "added Korean category is saved"
    $nullCategoryRejected = $false
    try {
        Add-MemoCategory -SettingsPath $categorySettingsPath -Name $null | Out-Null
    }
    catch {
        $nullCategoryRejected = $true
    }
    Assert-True $nullCategoryRejected "null category name is rejected with a readable error"

    New-Memo -StorePath $categoryStorePath -Title "Work memo" -PlainText "Project" -Rtf "{\rtf1 Project}" -Category "Work" | Out-Null
    New-Memo -StorePath $categoryStorePath -Title "Default memo" -PlainText "Personal" -Rtf "{\rtf1 Personal}" | Out-Null
    $workResults = @(Search-Memos -StorePath $categoryStorePath -Query "" -SortBy "CreatedDesc" -Category "Work")
    Assert-Equal 1 $workResults.Count "category filter returns matching memo"
    Assert-Equal "Work" $workResults[0].Category "memo stores selected category"

    Remove-MemoCategory -StorePath $categoryStorePath -SettingsPath $categorySettingsPath -Name "Work" | Out-Null
    $afterCategoryDelete = @(Search-Memos -StorePath $categoryStorePath -Query "" -SortBy "CreatedDesc" -Category $allCategory)
    Assert-Equal 2 $afterCategoryDelete.Count "deleting a category moves its memos to all"
    Assert-True (@($afterCategoryDelete | Where-Object { $_.Title -eq "Work memo" -and $_.Category -eq $allCategory }).Count -eq 1) "category delete resets affected memo category"
    Remove-MemoCategory -StorePath $categoryStorePath -SettingsPath $categorySettingsPath -Name $allCategory | Out-Null
    $afterAllDeleteAttempt = @(Get-MemoCategories -SettingsPath $categorySettingsPath)
    Assert-True ($afterAllDeleteAttempt -contains $allCategory) "all category cannot be deleted"

    $categoryBackupPath = Join-Path $tempRoot "category-backup.memo-backup.json"
    Export-MemoFullBackup -StorePath $categoryStorePath -SettingsPath $categorySettingsPath -DestinationFile $categoryBackupPath
    $categoryBackup = Get-Content -Raw -LiteralPath $categoryBackupPath | ConvertFrom-Json
    Assert-True ($categoryBackup.PSObject.Properties["Settings"] -ne $null) "full backup includes settings"
    Assert-True (@($categoryBackup.Settings.Categories) -contains $koreanCategory) "full backup includes saved categories"

    $restoredCategorySettingsPath = Join-Path $tempRoot "restored-category-settings.json"
    $restoredCategoryStorePath = Join-Path $tempRoot "restored-category-store.json"
    Initialize-MemoStore -StorePath $restoredCategoryStorePath -SettingsPath $restoredCategorySettingsPath
    Restore-MemoFullBackup -StorePath $restoredCategoryStorePath -SettingsPath $restoredCategorySettingsPath -BackupFile $categoryBackupPath
    $restoredCategories = @(Get-MemoCategories -SettingsPath $restoredCategorySettingsPath)
    Assert-True ($restoredCategories -contains $koreanCategory) "restore preserves backed up categories"

    Write-Host "All MemoStore tests passed."
}
finally {
    try {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction Stop
    }
    catch {
        Write-Warning "Could not remove temporary test directory: $tempRoot"
    }
}
