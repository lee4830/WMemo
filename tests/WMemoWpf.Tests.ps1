$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$xamlPath = Join-Path $root "src/WMemo.Wpf/MainWindow.xaml"
$codePath = Join-Path $root "src/WMemo.Wpf/MainWindow.xaml.cs"
$storePath = Join-Path $root "src/WMemo.Wpf/MemoStore.cs"
$appPath = Join-Path $root "src/WMemo.Wpf/App.xaml.cs"
$projectPath = Join-Path $root "src/WMemo.Wpf/WMemo.Wpf.csproj"
$installPath = Join-Path $root "Install-WMemo.ps1"

$xaml = Get-Content -Raw -LiteralPath $xamlPath -Encoding UTF8
$code = Get-Content -Raw -LiteralPath $codePath -Encoding UTF8
$store = Get-Content -Raw -LiteralPath $storePath -Encoding UTF8
$app = Get-Content -Raw -LiteralPath $appPath -Encoding UTF8
$project = Get-Content -Raw -LiteralPath $projectPath -Encoding UTF8
$install = if (Test-Path $installPath) { Get-Content -Raw -LiteralPath $installPath -Encoding UTF8 } else { "" }

function Assert-Contains {
    param([string]$Text, [string]$Needle, [string]$Message)
    if (-not $Text.Contains($Needle)) {
        throw "Assertion failed: $Message"
    }
}

Assert-Contains $code "RefreshList(string? selectMemoId = null, bool keepListFocus = false)" "RefreshList should be able to preserve selection and focus"
Assert-Contains $code "MemoList.Focus()" "Saving should restore focus to the memo list when the saved memo is visible"
Assert-Contains $code "MemoList.SelectedItem = rows.FirstOrDefault" "RefreshList should reselect the saved memo by id"
Assert-Contains $store '(m.PlainText ?? "")' "WPF memo search should include memo body text"
Assert-Contains $xaml 'SearchHintText' "Search input should show a visible title/body search hint"
Assert-Contains $xaml 'Tag=' "Search input should carry a search hint marker"
Assert-Contains $xaml "HorizontalContentAlignment" "ListBoxItem should make the whole row clickable"
Assert-Contains $xaml 'Background="Transparent"' "List row template should receive clicks on blank space"
Assert-Contains $app "SetCurrentProcessExplicitAppUserModelID" "App should set an AppUserModelID for taskbar pinning/grouping"
Assert-Contains $project "<PublishSingleFile>true</PublishSingleFile>" "Release publish should be configured as a single-file app"
Assert-Contains $project "<IncludeNativeLibrariesForSelfExtract>true</IncludeNativeLibrariesForSelfExtract>" "Native WPF dependencies should be embedded for whole-exe publish"
Assert-Contains $install "CreateShortcut" "Installer should create a Start Menu shortcut so Windows exposes pin options"
Assert-Contains $install "Start Menu" "Installer should put WMemo where Windows can expose pin options"

Write-Host "WMemo WPF structure tests passed."
