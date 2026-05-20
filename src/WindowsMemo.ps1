param([switch]$ValidateOnly)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:Root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot "MemoStore.psm1") -Force

$script:StorePath = Get-DefaultMemoStorePath
$script:SettingsPath = Get-DefaultMemoSettingsPath
Initialize-MemoStore -StorePath $script:StorePath -SettingsPath $script:SettingsPath

function ConvertFrom-HexColor {
    param([string]$Hex)
    if ([string]::IsNullOrWhiteSpace($Hex)) { return [System.Drawing.Color]::Black }
    return [System.Drawing.ColorTranslator]::FromHtml($Hex)
}

function ConvertTo-HexColor {
    param([System.Drawing.Color]$Color)
    return "#{0:X2}{1:X2}{2:X2}" -f $Color.R, $Color.G, $Color.B
}

function Show-AppError {
    param([string]$Message)
    [System.Windows.Forms.MessageBox]::Show($Message, "윈도우 메모", "OK", "Error") | Out-Null
}

function New-Button {
    param([string]$Text, [int]$Width = 76)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = $Width
    $button.Height = 30
    $button.FlatStyle = "System"
    return $button
}

function Format-MemoDateTime {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -eq "-") {
        return "-"
    }
    return ([datetime]$Value).ToLocalTime().ToString("yyyy년 MM월 dd일 HH시 mm분", [System.Globalization.CultureInfo]::GetCultureInfo("ko-KR"))
}

function Apply-SelectionFontStyle {
    param([System.Drawing.FontStyle]$Style)
    if ($bodyBox.SelectionFont) {
        $current = $bodyBox.SelectionFont
        $nextStyle = $current.Style
        if (($nextStyle -band $Style) -eq $Style) {
            $nextStyle = $nextStyle -bxor $Style
        }
        else {
            $nextStyle = $nextStyle -bor $Style
        }
        $bodyBox.SelectionFont = New-Object System.Drawing.Font($current.FontFamily, $current.Size, $nextStyle)
    }
}

function Apply-SelectedFontFamily {
    if (-not $bodyBox.SelectionFont) { return }
    $size = $bodyBox.SelectionFont.Size
    $style = $bodyBox.SelectionFont.Style
    $bodyBox.SelectionFont = New-Object System.Drawing.Font($fontCombo.Text, $size, $style)
}

function Apply-SelectedFontSize {
    if (-not $bodyBox.SelectionFont) { return }
    $size = [single]$sizeBox.Value
    $style = $bodyBox.SelectionFont.Style
    $family = $bodyBox.SelectionFont.FontFamily
    $bodyBox.SelectionFont = New-Object System.Drawing.Font($family, $size, $style)
}

function Get-CurrentSortBy {
    switch ($sortCombo.SelectedItem) {
        "등록 오래된순" { "CreatedAsc" }
        "수정 최신순" { "UpdatedDesc" }
        "수정 오래된순" { "UpdatedAsc" }
        "제목 가나다/ABC순" { "TitleAsc" }
        default { "CreatedDesc" }
    }
}

function Get-EffectiveSearchQuery {
    if ($script:SearchHintActive) { return "" }
    return $searchBox.Text
}

function Show-SearchHint {
    if ([string]::IsNullOrWhiteSpace($searchBox.Text)) {
        $script:SearchHintActive = $true
        $searchBox.ForeColor = [System.Drawing.Color]::Gray
        $searchBox.Text = "검색어를 입력하세요"
    }
}

function Hide-SearchHint {
    if ($script:SearchHintActive) {
        $script:SearchHintActive = $false
        $searchBox.Text = ""
        $searchBox.ForeColor = [System.Drawing.Color]::Black
    }
}

function Clear-SearchBox {
    $script:SearchHintActive = $false
    $searchBox.Text = ""
    Show-SearchHint
    Refresh-MemoList
}

function Get-SelectedCategoryFilter {
    if ($null -eq $categoryFilterCombo.SelectedItem) { return "전체" }
    return [string]$categoryFilterCombo.SelectedItem
}

function Get-SelectedMemoCategory {
    if ($null -eq $categoryCombo.SelectedItem -or [string]::IsNullOrWhiteSpace([string]$categoryCombo.SelectedItem)) {
        return "전체"
    }
    return [string]$categoryCombo.SelectedItem
}

function Get-SearchCreatedFrom {
    return $null
}

function Get-SearchCreatedTo {
    return $null
}

function Get-SearchUpdatedFrom {
    return $null
}

function Get-SearchUpdatedTo {
    return $null
}

function Refresh-MemoList {
    try {
        $listView.BeginUpdate()
        $listView.Items.Clear()
        $memos = @(Search-Memos `
            -StorePath $script:StorePath `
            -Query (Get-EffectiveSearchQuery) `
            -SortBy (Get-CurrentSortBy) `
            -CreatedFrom (Get-SearchCreatedFrom) `
            -CreatedTo (Get-SearchCreatedTo) `
            -UpdatedFrom (Get-SearchUpdatedFrom) `
            -UpdatedTo (Get-SearchUpdatedTo) `
            -Category (Get-SelectedCategoryFilter))

        foreach ($memo in $memos) {
            $item = New-Object System.Windows.Forms.ListViewItem($memo.Title)
            $item.Tag = $memo.Id
            $listView.Items.Add($item) | Out-Null
        }
        $countLabel.Text = "$($memos.Count)개 메모"
    }
    catch {
        Show-AppError $_.Exception.Message
    }
    finally {
        $listView.EndUpdate()
    }
}

function Load-MemoIntoEditor {
    param($Memo)
    $script:CurrentMemoId = $Memo.Id
    $titleBox.Text = $Memo.Title
    if ([string]::IsNullOrWhiteSpace($Memo.Rtf)) {
        $bodyBox.Text = $Memo.PlainText
    }
    else {
        try { $bodyBox.Rtf = $Memo.Rtf } catch { $bodyBox.Text = $Memo.PlainText }
    }
    $createdValue.Text = Format-MemoDateTime $Memo.CreatedAt
    $updatedValue.Text = Format-MemoDateTime $Memo.UpdatedAt
    $metaLabel.Text = "등록: $($createdValue.Text)    수정: $($updatedValue.Text)"
    $memoCategory = Get-MemoCategoryValue -Memo $Memo
    if ($categoryCombo.Items.Contains($memoCategory)) {
        $categoryCombo.SelectedItem = $memoCategory
    }
    else {
        $categoryCombo.SelectedItem = "전체"
    }
}

function Load-SelectedMemo {
    if ($listView.SelectedItems.Count -eq 0) { return }
    $id = [string]$listView.SelectedItems[0].Tag
    $memo = @(Get-Memos -StorePath $script:StorePath) | Where-Object { $_.Id -eq $id } | Select-Object -First 1
    if ($memo) { Load-MemoIntoEditor -Memo $memo }
}

function New-MemoInEditor {
    $script:CurrentMemoId = $null
    $titleBox.Text = "제목 없음"
    $bodyBox.Clear()
    $settings = Get-MemoSettings -SettingsPath $script:SettingsPath
    $bodyBox.Font = New-Object System.Drawing.Font($settings.FontFamily, [single]$settings.BodyFontSize)
    $bodyBox.ForeColor = ConvertFrom-HexColor $settings.BodyColor
    $bodyBox.BackColor = ConvertFrom-HexColor $settings.BackgroundColor
    $createdValue.Text = "-"
    $updatedValue.Text = "-"
    $metaLabel.Text = "등록: -    수정: -"
    $categoryCombo.SelectedItem = "전체"
    $null = $titleBox.Focus()
}

function Save-CurrentMemo {
    try {
        $title = $titleBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($title)) { $title = "제목 없음" }
        $category = Get-SelectedMemoCategory
        if ([string]::IsNullOrWhiteSpace($script:CurrentMemoId)) {
            $memo = New-Memo -StorePath $script:StorePath -Title $title -PlainText $bodyBox.Text -Rtf $bodyBox.Rtf -Category $category
        }
        else {
            $memo = Save-Memo -StorePath $script:StorePath -Id $script:CurrentMemoId -Title $title -PlainText $bodyBox.Text -Rtf $bodyBox.Rtf -Category $category
        }
        Load-MemoIntoEditor -Memo $memo
        Refresh-MemoList
        New-MemoInEditor
    }
    catch {
        Show-AppError $_.Exception.Message
    }
}

function Delete-CurrentMemo {
    if ([string]::IsNullOrWhiteSpace($script:CurrentMemoId)) { return }
    $answer = [System.Windows.Forms.MessageBox]::Show("이 메모를 삭제할까요?", "윈도우 메모", "YesNo", "Question")
    if ($answer -ne "Yes") { return }
    Remove-Memo -StorePath $script:StorePath -Id $script:CurrentMemoId
    New-MemoInEditor
    Refresh-MemoList
}

function Delete-AllMemos {
    $answer = [System.Windows.Forms.MessageBox]::Show("모든 메모를 삭제할까요? 이 작업은 되돌릴 수 없습니다.", "윈도우 메모", "YesNo", "Warning")
    if ($answer -ne "Yes") { return }
    Clear-Memos -StorePath $script:StorePath
    New-MemoInEditor
    Refresh-MemoList
}

function Load-SettingsIntoUI {
    $settings = Get-MemoSettings -SettingsPath $script:SettingsPath
    $defaultFontCombo.Text = $settings.FontFamily
    $titleSizeDefault.Value = [decimal]$settings.TitleFontSize
    $bodySizeDefault.Value = [decimal]$settings.BodyFontSize
    $titleColorButton.BackColor = ConvertFrom-HexColor $settings.TitleColor
    $bodyColorButton.BackColor = ConvertFrom-HexColor $settings.BodyColor
    $backgroundColorButton.BackColor = ConvertFrom-HexColor $settings.BackgroundColor
    $titleBox.Font = New-Object System.Drawing.Font($settings.FontFamily, [single]$settings.TitleFontSize, [System.Drawing.FontStyle]::Bold)
    $titleBox.ForeColor = ConvertFrom-HexColor $settings.TitleColor
    $bodyBox.Font = New-Object System.Drawing.Font($settings.FontFamily, [single]$settings.BodyFontSize)
    $bodyBox.ForeColor = ConvertFrom-HexColor $settings.BodyColor
    $bodyBox.BackColor = ConvertFrom-HexColor $settings.BackgroundColor
}

function Refresh-CategoryControls {
    $categories = @(Get-MemoCategories -SettingsPath $script:SettingsPath)
    $selectedFilter = if ($categoryFilterCombo.SelectedItem) { [string]$categoryFilterCombo.SelectedItem } else { "전체" }
    $selectedMemo = if ($categoryCombo.SelectedItem) { [string]$categoryCombo.SelectedItem } else { "전체" }

    $categoryFilterCombo.Items.Clear()
    $categoryCombo.Items.Clear()
    foreach ($category in $categories) {
        [void]$categoryFilterCombo.Items.Add($category)
        [void]$categoryCombo.Items.Add($category)
    }
    if ($categoryFilterCombo.Items.Contains($selectedFilter)) { $categoryFilterCombo.SelectedItem = $selectedFilter } else { $categoryFilterCombo.SelectedItem = "전체" }
    if ($categoryCombo.Items.Contains($selectedMemo)) { $categoryCombo.SelectedItem = $selectedMemo } else { $categoryCombo.SelectedItem = "전체" }
}

function Open-CategoryManager {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = "카테고리 관리"
    $dialog.Width = 360
    $dialog.Height = 420
    $dialog.StartPosition = "CenterParent"
    $dialog.Font = $form.Font

    $layout = New-Object System.Windows.Forms.TableLayoutPanel
    $layout.Dock = "Fill"
    $layout.Padding = New-Object System.Windows.Forms.Padding(12)
    $layout.RowCount = 3
    $layout.ColumnCount = 1
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100))) | Out-Null
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 36))) | Out-Null
    $layout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 70))) | Out-Null
    $dialog.Controls.Add($layout)

    $list = New-Object System.Windows.Forms.ListBox
    $list.Dock = "Fill"
    $list.SelectionMode = "One"
    $layout.Controls.Add($list, 0, 0)

    $categoryNameBox = New-Object System.Windows.Forms.TextBox
    $categoryNameBox.Dock = "Fill"
    $layout.Controls.Add($categoryNameBox, 0, 1)

    $buttons = New-Object System.Windows.Forms.FlowLayoutPanel
    $buttons.Dock = "Fill"
    $buttons.FlowDirection = "LeftToRight"
    $addButton = New-Button "추가" 70
    $removeButton = New-Button "삭제" 70
    $statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.AutoSize = $true
    $statusLabel.TextAlign = "MiddleLeft"
    $statusLabel.ForeColor = [System.Drawing.Color]::DimGray
    $statusLabel.Margin = New-Object System.Windows.Forms.Padding(8, 8, 0, 0)
    $buttons.Controls.AddRange(@($addButton, $removeButton, $statusLabel))
    $layout.Controls.Add($buttons, 0, 2)

    $reload = {
        param([string]$SelectName = "")
        $list.Items.Clear()
        foreach ($category in @(Get-MemoCategories -SettingsPath $script:SettingsPath)) {
            [void]$list.Items.Add($category)
        }
        if (-not [string]::IsNullOrWhiteSpace($SelectName) -and $list.Items.Contains($SelectName)) {
            $list.SelectedItem = $SelectName
        }
    }

    $addCategory = {
        try {
            $name = $categoryNameBox.Text.Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                Show-AppError "추가할 카테고리 이름을 입력하세요."
                return
            }
            Add-MemoCategory -SettingsPath $script:SettingsPath -Name $name | Out-Null
            $savedCategories = @(Get-MemoCategories -SettingsPath $script:SettingsPath)
            if ($savedCategories -notcontains $name) {
                throw "카테고리를 저장하지 못했습니다."
            }
            $categoryNameBox.Text = ""
            & $reload $name
            Refresh-CategoryControls
            Refresh-MemoList
            $statusLabel.Text = "'$name' 추가됨"
        }
        catch { Show-AppError $_.Exception.Message }
    }

    $addButton.Add_Click($addCategory)
    $categoryNameBox.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [System.Windows.Forms.Keys]::Enter) {
            $eventArgs.SuppressKeyPress = $true
            & $addCategory
        }
    })

    $removeButton.Add_Click({
        try {
            if ($null -eq $list.SelectedItem) { return }
            $name = [string]$list.SelectedItem
            if ($name -eq (Get-AllCategoryName)) {
                Show-AppError "전체 카테고리는 삭제할 수 없습니다."
                return
            }
            $answer = [System.Windows.Forms.MessageBox]::Show("'$name' 카테고리를 삭제할까요? 해당 메모는 전체로 이동합니다.", "윈도우 메모", "YesNo", "Warning")
            if ($answer -ne "Yes") { return }
            Remove-MemoCategory -StorePath $script:StorePath -SettingsPath $script:SettingsPath -Name $name | Out-Null
            & $reload
            Refresh-CategoryControls
            Refresh-MemoList
            New-MemoInEditor
            $statusLabel.Text = "'$name' 삭제됨"
        }
        catch { Show-AppError $_.Exception.Message }
    })

    & $reload
    $dialog.AcceptButton = $addButton
    $owner = if ($sideDialog.Visible) { $sideDialog } else { $form }
    $dialog.ShowDialog($owner) | Out-Null
}

function Save-SettingsFromUI {
    try {
        Save-MemoSettings -SettingsPath $script:SettingsPath -Settings @{
            FontFamily = $defaultFontCombo.Text
            TitleFontSize = [int]$titleSizeDefault.Value
            BodyFontSize = [int]$bodySizeDefault.Value
            TitleColor = ConvertTo-HexColor $titleColorButton.BackColor
            BodyColor = ConvertTo-HexColor $bodyColorButton.BackColor
            BackgroundColor = ConvertTo-HexColor $backgroundColorButton.BackColor
        } | Out-Null
        Load-SettingsIntoUI
    }
    catch {
        Show-AppError $_.Exception.Message
    }
}

function Choose-ButtonColor {
    param([System.Windows.Forms.Button]$Button)
    $dialog = New-Object System.Windows.Forms.ColorDialog
    $dialog.Color = $Button.BackColor
    if ($dialog.ShowDialog() -eq "OK") {
        $Button.BackColor = $dialog.Color
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "윈도우 메모"
$form.Width = 1440
$form.Height = 820
$form.MinimumSize = New-Object System.Drawing.Size(1200, 680)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$script:CurrentMemoId = $null
$script:SearchHintActive = $false

$main = New-Object System.Windows.Forms.TableLayoutPanel
$main.Dock = "Fill"
$main.ColumnCount = 2
$main.RowCount = 1
$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 460))) | Out-Null
$main.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100))) | Out-Null
$form.Controls.Add($main)

$leftPanel = New-Object System.Windows.Forms.TableLayoutPanel
$leftPanel.Dock = "Fill"
$leftPanel.RowCount = 5
$leftPanel.ColumnCount = 1
$leftPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$leftPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 34))) | Out-Null
$leftPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 38))) | Out-Null
$leftPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 38))) | Out-Null
$leftPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100))) | Out-Null
$leftPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 28))) | Out-Null
$main.Controls.Add($leftPanel, 0, 0)

$searchPanel = New-Object System.Windows.Forms.TableLayoutPanel
$searchPanel.Dock = "Fill"
$searchPanel.ColumnCount = 2
$searchPanel.RowCount = 1
$searchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100))) | Out-Null
$searchPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 44))) | Out-Null
$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Dock = "Fill"
$clearSearchButton = New-Button "X" 40
$clearSearchButton.Dock = "Fill"
$clearSearchButton.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$searchPanel.Controls.Add($searchBox, 0, 0)
$searchPanel.Controls.Add($clearSearchButton, 1, 0)
$leftPanel.Controls.Add($searchPanel, 0, 0)

$sortCombo = New-Object System.Windows.Forms.ComboBox
$sortCombo.Dock = "Fill"
$sortCombo.DropDownStyle = "DropDownList"
$sortCombo.Items.AddRange(@("등록 최신순", "등록 오래된순", "수정 최신순", "수정 오래된순", "제목 가나다/ABC순"))
$sortCombo.SelectedIndex = 0
$leftPanel.Controls.Add($sortCombo, 0, 1)

$categoryFilterCombo = New-Object System.Windows.Forms.ComboBox
$categoryFilterCombo.Dock = "Fill"
$categoryFilterCombo.DropDownStyle = "DropDownList"
$leftPanel.Controls.Add($categoryFilterCombo, 0, 2)

$listView = New-Object System.Windows.Forms.ListView
$listView.Dock = "Fill"
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.HideSelection = $false
$listView.Columns.Add("제목", 420) | Out-Null
$leftPanel.Controls.Add($listView, 0, 3)

$countLabel = New-Object System.Windows.Forms.Label
$countLabel.Dock = "Fill"
$countLabel.TextAlign = "MiddleLeft"
$leftPanel.Controls.Add($countLabel, 0, 4)

$centerPanel = New-Object System.Windows.Forms.TableLayoutPanel
$centerPanel.Dock = "Fill"
$centerPanel.RowCount = 5
$centerPanel.ColumnCount = 1
$centerPanel.Padding = New-Object System.Windows.Forms.Padding(8, 10, 8, 10)
$centerPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 38))) | Out-Null
$centerPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 26))) | Out-Null
$centerPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 44))) | Out-Null
$centerPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 48))) | Out-Null
$centerPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100))) | Out-Null
$main.Controls.Add($centerPanel, 1, 0)

$commandBar = New-Object System.Windows.Forms.FlowLayoutPanel
$commandBar.Dock = "Fill"
$commandBar.FlowDirection = "LeftToRight"
$commandBar.WrapContents = $false
$newButton = New-Button "새 메모" 84
$saveButton = New-Button "저장" 70
$deleteButton = New-Button "삭제" 70
$infoButton = New-Button "정보" 70
$backupButton = New-Button "백업" 70
$settingsButton = New-Button "설정" 70
$commandBar.Controls.AddRange(@($newButton, $saveButton, $deleteButton, $infoButton, $backupButton, $settingsButton))
$centerPanel.Controls.Add($commandBar, 0, 0)

$titleBox = New-Object System.Windows.Forms.TextBox
$titleBox.Dock = "Fill"
$metaPanel = New-Object System.Windows.Forms.TableLayoutPanel
$metaPanel.Dock = "Fill"
$metaPanel.ColumnCount = 4
$metaPanel.RowCount = 1
$metaPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100))) | Out-Null
$metaPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 70))) | Out-Null
$metaPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 180))) | Out-Null
$metaPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 8))) | Out-Null
$metaLabel = New-Object System.Windows.Forms.Label
$metaLabel.Dock = "Fill"
$metaLabel.TextAlign = "MiddleLeft"
$metaLabel.ForeColor = [System.Drawing.Color]::DimGray
$metaLabel.Text = "등록: -    수정: -"
$categoryLabel = New-Object System.Windows.Forms.Label
$categoryLabel.Dock = "Fill"
$categoryLabel.TextAlign = "MiddleRight"
$categoryLabel.Text = "카테고리"
$categoryCombo = New-Object System.Windows.Forms.ComboBox
$categoryCombo.Dock = "Fill"
$categoryCombo.DropDownStyle = "DropDownList"
$metaPanel.Controls.Add($metaLabel, 0, 0)
$metaPanel.Controls.Add($categoryLabel, 1, 0)
$metaPanel.Controls.Add($categoryCombo, 2, 0)
$centerPanel.Controls.Add($metaPanel, 0, 1)
$centerPanel.Controls.Add($titleBox, 0, 2)

$formatBar = New-Object System.Windows.Forms.FlowLayoutPanel
$formatBar.Dock = "Fill"
$formatBar.FlowDirection = "LeftToRight"
$formatBar.WrapContents = $false
$boldButton = New-Button "B" 34
$italicButton = New-Button "I" 34
$underlineButton = New-Button "U" 34
$fontCombo = New-Object System.Windows.Forms.ComboBox
$fontCombo.Width = 160
$fontCombo.DropDownStyle = "DropDownList"
foreach ($family in [System.Drawing.FontFamily]::Families) { [void]$fontCombo.Items.Add($family.Name) }
$fontCombo.Text = "Segoe UI"
$sizeBox = New-Object System.Windows.Forms.NumericUpDown
$sizeBox.Width = 58
$sizeBox.Minimum = 8
$sizeBox.Maximum = 72
$sizeBox.Value = 12
$textColorButton = New-Button "글자색" 70
$highlightButton = New-Button "강조" 58
$formatBar.Controls.AddRange(@($boldButton, $italicButton, $underlineButton, $fontCombo, $sizeBox, $textColorButton, $highlightButton))
$centerPanel.Controls.Add($formatBar, 0, 3)

$bodyBox = New-Object System.Windows.Forms.RichTextBox
$bodyBox.Dock = "Fill"
$bodyBox.BorderStyle = "FixedSingle"
$bodyBox.AcceptsTab = $true
$bodyBox.DetectUrls = $true
$centerPanel.Controls.Add($bodyBox, 0, 4)

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = "Fill"

$infoTab = New-Object System.Windows.Forms.TabPage
$infoTab.Text = "정보"
$backupTab = New-Object System.Windows.Forms.TabPage
$backupTab.Text = "백업"
$settingsTab = New-Object System.Windows.Forms.TabPage
$settingsTab.Text = "설정"
$tabControl.TabPages.AddRange(@($infoTab, $backupTab, $settingsTab))

$sideDialog = New-Object System.Windows.Forms.Form
$sideDialog.Text = "정보 / 백업 / 설정"
$sideDialog.Width = 520
$sideDialog.Height = 520
$sideDialog.MinimumSize = New-Object System.Drawing.Size(460, 420)
$sideDialog.StartPosition = "CenterParent"
$sideDialog.Font = $form.Font
$sideDialog.Controls.Add($tabControl)
$sideDialog.Add_FormClosing({
    param($sender, $eventArgs)
    if ($eventArgs.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {
        $eventArgs.Cancel = $true
        $sideDialog.Hide()
    }
})

$infoPanel = New-Object System.Windows.Forms.TableLayoutPanel
$infoPanel.Dock = "Top"
$infoPanel.Height = 170
$infoPanel.Padding = New-Object System.Windows.Forms.Padding(12)
$infoPanel.RowCount = 2
$infoPanel.ColumnCount = 2
$infoPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 86))) | Out-Null
$infoPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100))) | Out-Null
$infoPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 52))) | Out-Null
$infoPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 52))) | Out-Null
$infoTab.Controls.Add($infoPanel)
$createdLabel = New-Object System.Windows.Forms.Label
$createdLabel.Text = "등록 시간"
$createdLabel.Dock = "Fill"
$createdLabel.TextAlign = "MiddleLeft"
$createdValue = New-Object System.Windows.Forms.Label
$createdValue.Text = "-"
$createdValue.Dock = "Fill"
$createdValue.TextAlign = "MiddleLeft"
$createdValue.AutoEllipsis = $true
$updatedLabel = New-Object System.Windows.Forms.Label
$updatedLabel.Text = "수정 시간"
$updatedLabel.Dock = "Fill"
$updatedLabel.TextAlign = "MiddleLeft"
$updatedValue = New-Object System.Windows.Forms.Label
$updatedValue.Text = "-"
$updatedValue.Dock = "Fill"
$updatedValue.TextAlign = "MiddleLeft"
$updatedValue.AutoEllipsis = $true
$infoPanel.Controls.Add($createdLabel, 0, 0)
$infoPanel.Controls.Add($createdValue, 1, 0)
$infoPanel.Controls.Add($updatedLabel, 0, 1)
$infoPanel.Controls.Add($updatedValue, 1, 1)

$backupPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$backupPanel.Dock = "Fill"
$backupPanel.Padding = New-Object System.Windows.Forms.Padding(12)
$backupPanel.FlowDirection = "TopDown"
$backupPanel.WrapContents = $false
$backupTab.Controls.Add($backupPanel)
$fullBackupButton = New-Button "전체 백업 (.memo-backup.json)" 320
$txtBackupButton = New-Button "읽을 수 있는 TXT 백업" 320
$restoreButton = New-Button "백업에서 복구" 320
$backupHint = New-Object System.Windows.Forms.Label
$backupHint.Width = 330
$backupHint.Height = 110
$backupHint.Text = "전체 백업은 서식과 날짜를 보존합니다.`r`nTXT 백업은 사람이 읽을 수 있는 텍스트 파일을 만듭니다."
$backupPanel.Controls.AddRange(@($fullBackupButton, $txtBackupButton, $restoreButton, $backupHint))

$settingsPanel = New-Object System.Windows.Forms.TableLayoutPanel
$settingsPanel.Dock = "Top"
$settingsPanel.Padding = New-Object System.Windows.Forms.Padding(12)
$settingsPanel.ColumnCount = 2
$settingsPanel.RowCount = 9
$settingsPanel.Height = 390
$settingsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 120))) | Out-Null
$settingsPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100))) | Out-Null
for ($row = 0; $row -lt 9; $row++) {
    $settingsPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", 38))) | Out-Null
}
$settingsTab.Controls.Add($settingsPanel)

$defaultFontCombo = New-Object System.Windows.Forms.ComboBox
$defaultFontCombo.DropDownStyle = "DropDownList"
foreach ($family in [System.Drawing.FontFamily]::Families) { [void]$defaultFontCombo.Items.Add($family.Name) }
$titleSizeDefault = New-Object System.Windows.Forms.NumericUpDown
$titleSizeDefault.Minimum = 12
$titleSizeDefault.Maximum = 48
$bodySizeDefault = New-Object System.Windows.Forms.NumericUpDown
$bodySizeDefault.Minimum = 8
$bodySizeDefault.Maximum = 36
$titleColorButton = New-Button "제목 색" 110
$bodyColorButton = New-Button "본문 색" 110
$backgroundColorButton = New-Button "배경색" 110
$saveSettingsButton = New-Button "설정 저장" 130
$categoryManageButton = New-Button "카테고리 관리" 150
$deleteAllButton = New-Button "삭제" 70
$deleteAllPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$deleteAllPanel.Dock = "Fill"
$deleteAllPanel.FlowDirection = "LeftToRight"
$deleteAllPanel.WrapContents = $false
$deleteAllPanel.Margin = New-Object System.Windows.Forms.Padding(0)
$deleteAllLabel = New-Object System.Windows.Forms.Label
$deleteAllLabel.Text = "전체 메모 삭제"
$deleteAllLabel.AutoSize = $true
$deleteAllLabel.TextAlign = "MiddleLeft"
$deleteAllLabel.Margin = New-Object System.Windows.Forms.Padding(0, 8, 12, 0)
$deleteAllPanel.Controls.AddRange(@($deleteAllLabel, $deleteAllButton))

$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "글꼴"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 0)
$settingsPanel.Controls.Add($defaultFontCombo, 1, 0)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "제목 크기"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 1)
$settingsPanel.Controls.Add($titleSizeDefault, 1, 1)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "본문 크기"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 2)
$settingsPanel.Controls.Add($bodySizeDefault, 1, 2)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "제목"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 3)
$settingsPanel.Controls.Add($titleColorButton, 1, 3)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "본문"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 4)
$settingsPanel.Controls.Add($bodyColorButton, 1, 4)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "편집 배경"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 5)
$settingsPanel.Controls.Add($backgroundColorButton, 1, 5)
$settingsPanel.Controls.Add($saveSettingsButton, 1, 6)
$settingsPanel.Controls.Add((New-Object System.Windows.Forms.Label -Property @{ Text = "카테고리"; Dock = "Fill"; TextAlign = "MiddleLeft" }), 0, 7)
$settingsPanel.Controls.Add($categoryManageButton, 1, 7)
$settingsPanel.Controls.Add($deleteAllPanel, 0, 8)
$settingsPanel.SetColumnSpan($deleteAllPanel, 2)

$searchBox.Add_GotFocus({ Hide-SearchHint })
$searchBox.Add_LostFocus({ Show-SearchHint })
$searchBox.Add_TextChanged({ if (-not $script:SearchHintActive) { Refresh-MemoList } })
$clearSearchButton.Add_Click({ Clear-SearchBox })
$sortCombo.Add_SelectedIndexChanged({ Refresh-MemoList })
$categoryFilterCombo.Add_SelectedIndexChanged({ Refresh-MemoList })
$listView.Add_SelectedIndexChanged({ Load-SelectedMemo })
$newButton.Add_Click({ New-MemoInEditor })
$saveButton.Add_Click({ Save-CurrentMemo })
$deleteButton.Add_Click({ Delete-CurrentMemo })
$infoButton.Add_Click({
    $tabControl.SelectedTab = $infoTab
    $sideDialog.Show($form)
    $sideDialog.BringToFront()
})
$backupButton.Add_Click({
    $tabControl.SelectedTab = $backupTab
    $sideDialog.Show($form)
    $sideDialog.BringToFront()
})
$settingsButton.Add_Click({
    $tabControl.SelectedTab = $settingsTab
    $sideDialog.Show($form)
    $sideDialog.BringToFront()
})

$boldButton.Add_Click({ Apply-SelectionFontStyle ([System.Drawing.FontStyle]::Bold) })
$italicButton.Add_Click({ Apply-SelectionFontStyle ([System.Drawing.FontStyle]::Italic) })
$underlineButton.Add_Click({ Apply-SelectionFontStyle ([System.Drawing.FontStyle]::Underline) })
$fontCombo.Add_SelectedIndexChanged({ Apply-SelectedFontFamily })
$sizeBox.Add_ValueChanged({ Apply-SelectedFontSize })
$textColorButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.ColorDialog
    if ($dialog.ShowDialog() -eq "OK") { $bodyBox.SelectionColor = $dialog.Color }
})
$highlightButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.ColorDialog
    if ($dialog.ShowDialog() -eq "OK") { $bodyBox.SelectionBackColor = $dialog.Color }
})

$fullBackupButton.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.SaveFileDialog
        $dialog.Filter = "Memo backup (*.memo-backup.json)|*.memo-backup.json|JSON files (*.json)|*.json"
        $dialog.FileName = "windows-memo-backup.memo-backup.json"
        if ($dialog.ShowDialog() -eq "OK") {
            Export-MemoFullBackup -StorePath $script:StorePath -DestinationFile $dialog.FileName
            [System.Windows.Forms.MessageBox]::Show("전체 백업을 저장했습니다.", "윈도우 메모", "OK", "Information") | Out-Null
        }
    }
    catch { Show-AppError $_.Exception.Message }
})

$txtBackupButton.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "읽을 수 있는 TXT 백업을 저장할 폴더를 선택하세요"
        if ($dialog.ShowDialog() -eq "OK") {
            Export-MemoTxtBackup -StorePath $script:StorePath -DestinationDirectory $dialog.SelectedPath
            [System.Windows.Forms.MessageBox]::Show("TXT 백업을 저장했습니다.", "윈도우 메모", "OK", "Information") | Out-Null
        }
    }
    catch { Show-AppError $_.Exception.Message }
})

$restoreButton.Add_Click({
    try {
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Filter = "Memo backup (*.memo-backup.json;*.json)|*.memo-backup.json;*.json"
        if ($dialog.ShowDialog() -eq "OK") {
            $answer = [System.Windows.Forms.MessageBox]::Show("복구하면 현재 메모가 백업 내용으로 바뀝니다. 계속할까요?", "윈도우 메모", "YesNo", "Warning")
            if ($answer -eq "Yes") {
                Restore-MemoFullBackup -StorePath $script:StorePath -BackupFile $dialog.FileName
                New-MemoInEditor
                Refresh-MemoList
            }
        }
    }
    catch { Show-AppError $_.Exception.Message }
})

$titleColorButton.Add_Click({ Choose-ButtonColor $titleColorButton })
$bodyColorButton.Add_Click({ Choose-ButtonColor $bodyColorButton })
$backgroundColorButton.Add_Click({ Choose-ButtonColor $backgroundColorButton })
$saveSettingsButton.Add_Click({ Save-SettingsFromUI })
$categoryManageButton.Add_Click({ Open-CategoryManager })
$deleteAllButton.Add_Click({ Delete-AllMemos })

Load-SettingsIntoUI
Refresh-CategoryControls
New-MemoInEditor
Show-SearchHint
Refresh-MemoList

if ($ValidateOnly) {
    Write-Host "WindowsMemo.ps1 UI initialization OK"
    return
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::Run($form)











