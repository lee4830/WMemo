Set-StrictMode -Version Latest

function Get-DefaultMemoStorePath {
    $dir = Join-Path $env:LOCALAPPDATA "WindowsMemoUtility"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Join-Path $dir "memos.json")
}

function Get-DefaultMemoSettingsPath {
    $dir = Join-Path $env:LOCALAPPDATA "WindowsMemoUtility"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    return (Join-Path $dir "settings.json")
}

function Get-AllCategoryName {
    return [string]::Concat(@([char]0xC804, [char]0xCCB4))
}

function Test-BrokenAllCategoryName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $true }
    if ($Name -eq (Get-AllCategoryName)) { return $false }
    return $Name.Contains("?") -or $Name.Contains([char]0xFFFD) -or $Name.Contains([char]0x00EC) -or $Name.Contains([char]0x00B2) -or $Name.Contains([char]0x00B4)
}

function Initialize-MemoStore {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath)
    )

    $storeDir = Split-Path -Parent $StorePath
    $settingsDir = Split-Path -Parent $SettingsPath
    if ($storeDir -and -not (Test-Path $storeDir)) { New-Item -ItemType Directory -Force -Path $storeDir | Out-Null }
    if ($settingsDir -and -not (Test-Path $settingsDir)) { New-Item -ItemType Directory -Force -Path $settingsDir | Out-Null }
    if (-not (Test-Path $StorePath)) { "[]" | Set-Content -LiteralPath $StorePath -Encoding UTF8 }
    if (-not (Test-Path $SettingsPath)) {
        Get-DefaultMemoSettings | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    }
}

function Get-DefaultMemoSettings {
    [ordered]@{
        FontFamily = "Malgun Gothic"
        TitleFontSize = 22
        BodyFontSize = 12
        TitleColor = "#111827"
        BodyColor = "#1f2937"
        BackgroundColor = "#ffffff"
        Categories = @((Get-AllCategoryName))
        LastRestoredAt = ""
        CloseToTray = $false
        StartWithWindows = $false
    }
}

function Get-MemoCategoryValue {
    param($Memo)
    if ($null -eq $Memo) { return (Get-AllCategoryName) }
    $property = $Memo.PSObject.Properties["Category"]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return (Get-AllCategoryName)
    }
    if (Test-BrokenAllCategoryName -Name ([string]$property.Value)) {
        return (Get-AllCategoryName)
    }
    return [string]$property.Value
}

function Get-Memos {
    param([string]$StorePath = (Get-DefaultMemoStorePath))

    if (-not (Test-Path $StorePath)) { return @() }
    $raw = Get-Content -Raw -LiteralPath $StorePath
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $parsed = $raw | ConvertFrom-Json
    return @($parsed)
}

function Write-Memos {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [array]$Memos
    )

    $dir = Split-Path -Parent $StorePath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($null -eq $Memos -or @($Memos).Count -eq 0) {
        "[]" | Set-Content -LiteralPath $StorePath -Encoding UTF8
        return
    }
    @($Memos) | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StorePath -Encoding UTF8
}

function New-Memo {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$Title,
        [string]$PlainText,
        [string]$Rtf,
        [string]$Category = ""
    )

    $now = (Get-Date).ToUniversalTime().ToString("o")
    $memo = [pscustomobject][ordered]@{
        Id = [guid]::NewGuid().ToString("N")
        Title = $Title
        PlainText = $PlainText
        Rtf = $Rtf
        Category = if ([string]::IsNullOrWhiteSpace($Category)) { Get-AllCategoryName } else { $Category }
        CreatedAt = $now
        UpdatedAt = $now
    }
    $memos = @(Get-Memos -StorePath $StorePath)
    Write-Memos -StorePath $StorePath -Memos @($memos + $memo)
    return $memo
}

function Save-Memo {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$Id,
        [string]$Title,
        [string]$PlainText,
        [string]$Rtf,
        [string]$Category = ""
    )

    $memos = @(Get-Memos -StorePath $StorePath)
    $existing = $memos | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $existing) {
        throw "Memo '$Id' was not found."
    }

    $updated = [pscustomobject][ordered]@{
        Id = $existing.Id
        Title = $Title
        PlainText = $PlainText
        Rtf = $Rtf
        Category = if ([string]::IsNullOrWhiteSpace($Category)) { Get-AllCategoryName } else { $Category }
        CreatedAt = $existing.CreatedAt
        UpdatedAt = (Get-Date).ToUniversalTime().ToString("o")
    }
    $next = @($memos | ForEach-Object {
        if ($_.Id -eq $Id) { $updated } else { $_ }
    })
    Write-Memos -StorePath $StorePath -Memos $next
    return $updated
}

function Remove-Memo {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$Id
    )

    $memos = @(Get-Memos -StorePath $StorePath)
    Write-Memos -StorePath $StorePath -Memos @($memos | Where-Object { $_.Id -ne $Id })
}

function Clear-Memos {
    param([string]$StorePath = (Get-DefaultMemoStorePath))

    Write-Memos -StorePath $StorePath -Memos @()
}

function Search-Memos {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$Query = "",
        [string]$SortBy = "CreatedDesc",
        [Nullable[datetime]]$CreatedFrom = $null,
        [Nullable[datetime]]$CreatedTo = $null,
        [Nullable[datetime]]$UpdatedFrom = $null,
        [Nullable[datetime]]$UpdatedTo = $null,
        [string]$Category = ""
    )

    $safeQuery = if ($null -eq $Query) { "" } else { $Query }
    $queryText = $safeQuery.Trim().ToLowerInvariant()
    $memos = @(Get-Memos -StorePath $StorePath)

    $filtered = @($memos | Where-Object {
        $created = [datetime]$_.CreatedAt
        $updated = [datetime]$_.UpdatedAt
        $textMatch = $true
        if ($queryText.Length -gt 0) {
            $titleText = if ($null -eq $_.Title) { "" } else { $_.Title }
            $bodyText = if ($null -eq $_.PlainText) { "" } else { $_.PlainText }
            $haystack = ($titleText + "`n" + $bodyText).ToLowerInvariant()
            $textMatch = $haystack.Contains($queryText)
        }
        $createdOk = (($null -eq $CreatedFrom) -or $created -ge $CreatedFrom) -and (($null -eq $CreatedTo) -or $created -le $CreatedTo)
        $updatedOk = (($null -eq $UpdatedFrom) -or $updated -ge $UpdatedFrom) -and (($null -eq $UpdatedTo) -or $updated -le $UpdatedTo)
        $memoCategory = Get-MemoCategoryValue -Memo $_
        $allCategory = Get-AllCategoryName
        $categoryOk = [string]::IsNullOrWhiteSpace($Category) -or $Category -eq $allCategory -or $memoCategory -eq $Category
        $textMatch -and $createdOk -and $updatedOk -and $categoryOk
    })

    switch ($SortBy) {
        "CreatedAsc" { return @($filtered | Sort-Object { [datetime]$_.CreatedAt }) }
        "UpdatedAsc" { return @($filtered | Sort-Object { [datetime]$_.UpdatedAt }) }
        "UpdatedDesc" { return @($filtered | Sort-Object { [datetime]$_.UpdatedAt } -Descending) }
        "TitleAsc" { return @($filtered | Sort-Object { $_.Title }) }
        default { return @($filtered | Sort-Object { [datetime]$_.CreatedAt } -Descending) }
    }
}

function Export-MemoFullBackup {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath),
        [string]$DestinationFile
    )

    $dir = Split-Path -Parent $DestinationFile
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $payload = [ordered]@{
        App = "WindowsMemoUtility"
        Version = 1
        ExportedAt = (Get-Date).ToUniversalTime().ToString("o")
        Memos = @(Get-Memos -StorePath $StorePath)
        Settings = Get-MemoSettings -SettingsPath $SettingsPath
    }
    $payload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $DestinationFile -Encoding UTF8
}

function Restore-MemoFullBackup {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$SettingsPath = "",
        [string]$BackupFile
    )

    if (-not (Test-Path $BackupFile)) { throw "Backup file was not found: $BackupFile" }
    $payload = Get-Content -Raw -LiteralPath $BackupFile | ConvertFrom-Json
    if ($payload.App -ne "WindowsMemoUtility" -or $payload.Version -lt 1) {
        throw "This is not a supported memo backup file."
    }
    Write-Memos -StorePath $StorePath -Memos @($payload.Memos)
    if (-not [string]::IsNullOrWhiteSpace($SettingsPath) -and $payload.PSObject.Properties["Settings"] -and $payload.Settings) {
        $settingsTable = @{}
        foreach ($property in $payload.Settings.PSObject.Properties) {
            $settingsTable[$property.Name] = $property.Value
        }
        Save-MemoSettings -SettingsPath $SettingsPath -Settings $settingsTable | Out-Null
    }
}

function ConvertTo-SafeFileName {
    param([string]$Name)
    $safe = $Name
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace([string]$char, "_")
    }
    $safe = $safe.Trim()
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = "Untitled" }
    if ($safe.Length -gt 70) { $safe = $safe.Substring(0, 70) }
    return $safe
}

function Export-MemoTxtBackup {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$DestinationDirectory
    )

    if (-not (Test-Path $DestinationDirectory)) {
        New-Item -ItemType Directory -Force -Path $DestinationDirectory | Out-Null
    }

    $memos = @(Get-Memos -StorePath $StorePath)
    $indexLines = @(
        "Windows Memo Utility TXT Backup"
        "ExportedAt: $((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))"
        "Count: $($memos.Count)"
        ""
    )

    $counter = 1
    foreach ($memo in $memos) {
        $name = "{0:D3}-{1}.txt" -f $counter, (ConvertTo-SafeFileName -Name $memo.Title)
        $file = Join-Path $DestinationDirectory $name
        $content = @(
            "Title: $($memo.Title)"
            "CreatedAt: $($memo.CreatedAt)"
            "UpdatedAt: $($memo.UpdatedAt)"
            ""
            $memo.PlainText
        )
        $content | Set-Content -LiteralPath $file -Encoding UTF8
        $indexLines += "$($memo.Title) | Created: $($memo.CreatedAt) | Modified: $($memo.UpdatedAt) | File: $name"
        $counter++
    }

    $indexLines | Set-Content -LiteralPath (Join-Path $DestinationDirectory "index.txt") -Encoding UTF8
}

function Get-MemoSettings {
    param([string]$SettingsPath = (Get-DefaultMemoSettingsPath))

    if (-not (Test-Path $SettingsPath)) {
        $defaults = Get-DefaultMemoSettings
        Save-MemoSettings -SettingsPath $SettingsPath -Settings $defaults | Out-Null
    }
    $merged = Get-DefaultMemoSettings
    $settings = Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json
    if ($settings) {
        foreach ($property in $settings.PSObject.Properties) {
            if ($null -ne $property.Value) {
                $merged[$property.Name] = $property.Value
            }
        }
    }
    return ($merged | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
}

function Get-MemoCategories {
    param([string]$SettingsPath = (Get-DefaultMemoSettingsPath))

    $settings = Get-MemoSettings -SettingsPath $SettingsPath
    $categories = @()
    if ($settings.PSObject.Properties["Categories"] -and $settings.Categories) {
        $categories = @($settings.Categories)
    }
    $normalized = @((Get-AllCategoryName))
    foreach ($category in $categories) {
        $name = ([string]$category).Trim()
        if ((Test-BrokenAllCategoryName -Name $name)) { continue }
        if (-not [string]::IsNullOrWhiteSpace($name) -and $normalized -notcontains $name) {
            $normalized += $name
        }
    }
    return $normalized
}

function Save-MemoCategories {
    param(
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath),
        [array]$Categories
    )

    $settings = Get-MemoSettings -SettingsPath $SettingsPath
    $table = @{}
    foreach ($property in $settings.PSObject.Properties) {
        $table[$property.Name] = $property.Value
    }
    $normalized = @((Get-AllCategoryName))
    foreach ($category in @($Categories)) {
        $name = ([string]$category).Trim()
        if ((Test-BrokenAllCategoryName -Name $name)) { continue }
        if (-not [string]::IsNullOrWhiteSpace($name) -and $normalized -notcontains $name) {
            $normalized += $name
        }
    }
    $table["Categories"] = $normalized
    Save-MemoSettings -SettingsPath $SettingsPath -Settings $table | Out-Null
    return $normalized
}

function Add-MemoCategory {
    param(
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath),
        [string]$Name
    )

    $nameValue = if ($null -eq $Name) { "" } else { $Name.Trim() }
    if ([string]::IsNullOrWhiteSpace($nameValue)) { throw "Category name is required." }
    $categories = @(Get-MemoCategories -SettingsPath $SettingsPath)
    if ($categories -notcontains $nameValue) {
        $categories += $nameValue
    }
    Save-MemoCategories -SettingsPath $SettingsPath -Categories $categories
}

function Remove-MemoCategory {
    param(
        [string]$StorePath = (Get-DefaultMemoStorePath),
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath),
        [string]$Name
    )

    $nameValue = if ($null -eq $Name) { "" } else { $Name.Trim() }
    if ($nameValue -eq (Get-AllCategoryName) -or (Test-BrokenAllCategoryName -Name $nameValue)) { return @(Get-MemoCategories -SettingsPath $SettingsPath) }

    $categories = @(Get-MemoCategories -SettingsPath $SettingsPath) | Where-Object { $_ -ne $nameValue }
    Save-MemoCategories -SettingsPath $SettingsPath -Categories $categories | Out-Null

    $memos = @(Get-Memos -StorePath $StorePath)
    $updated = @($memos | ForEach-Object {
        $memo = $_
        $categoryValue = Get-MemoCategoryValue -Memo $memo
        [pscustomobject][ordered]@{
            Id = $memo.Id
            Title = $memo.Title
            PlainText = $memo.PlainText
            Rtf = $memo.Rtf
            Category = if ($categoryValue -eq $nameValue -or (Test-BrokenAllCategoryName -Name $categoryValue)) { Get-AllCategoryName } else { $categoryValue }
            CreatedAt = $memo.CreatedAt
            UpdatedAt = $memo.UpdatedAt
        }
    })
    Write-Memos -StorePath $StorePath -Memos $updated
    return @(Get-MemoCategories -SettingsPath $SettingsPath)
}

function Save-MemoSettings {
    param(
        [string]$SettingsPath = (Get-DefaultMemoSettingsPath),
        [hashtable]$Settings
    )

    $merged = Get-DefaultMemoSettings
    if (Test-Path $SettingsPath) {
        $existing = Get-Content -Raw -LiteralPath $SettingsPath | ConvertFrom-Json
        if ($existing) {
            foreach ($property in $existing.PSObject.Properties) {
                $merged[$property.Name] = $property.Value
            }
        }
    }
    if ($Settings) {
        foreach ($key in @($Settings.Keys)) {
            $merged[$key] = $Settings[$key]
        }
    }
    $dir = Split-Path -Parent $SettingsPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $merged | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SettingsPath -Encoding UTF8
    return ($merged | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
}

Export-ModuleMember -Function @(
    "Get-DefaultMemoStorePath",
    "Get-DefaultMemoSettingsPath",
    "Initialize-MemoStore",
    "Get-Memos",
    "New-Memo",
    "Save-Memo",
    "Remove-Memo",
    "Clear-Memos",
    "Search-Memos",
    "Export-MemoFullBackup",
    "Restore-MemoFullBackup",
    "Export-MemoTxtBackup",
    "Get-MemoSettings",
    "Save-MemoSettings",
    "Get-AllCategoryName",
    "Get-MemoCategoryValue",
    "Get-MemoCategories",
    "Save-MemoCategories",
    "Add-MemoCategory",
    "Remove-MemoCategory"
)

