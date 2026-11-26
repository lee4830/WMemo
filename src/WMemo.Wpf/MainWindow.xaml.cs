using Microsoft.Win32;
using System;
using System.Linq;
using System.ComponentModel;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;
using WpfButton = System.Windows.Controls.Button;
using WpfComboBox = System.Windows.Controls.ComboBox;

namespace WMemo.Wpf;

public partial class MainWindow : Window
{
    private readonly MemoStore store = new();
    private MemoSettings settings = new();
    private MemoItem? currentMemo;
    private System.Windows.Forms.NotifyIcon? trayIcon;
    private bool allowExit;
    private bool loading;

    public MainWindow()
    {
        InitializeComponent();
        InitializeControls();
        LoadSettingsIntoUi();
        InitializeTrayIcon();
        RefreshCategories();
        NewMemo();
        RefreshList();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (settings.CloseToTray && !allowExit)
        {
            e.Cancel = true;
            if (trayIcon is not null)
            {
                trayIcon.Visible = true;
            }
            ShowInTaskbar = false;
            Hide();
            trayIcon?.ShowBalloonTip(1200, "WMemo", "트레이에서 계속 실행 중입니다.", System.Windows.Forms.ToolTipIcon.Info);
            return;
        }

        allowExit = true;
        base.OnClosing(e);
    }

    protected override void OnClosed(EventArgs e)
    {
        trayIcon?.Dispose();
        base.OnClosed(e);
        if (!System.Windows.Application.Current.Dispatcher.HasShutdownStarted)
        {
            System.Windows.Application.Current.Shutdown();
        }
    }

    private void InitializeControls()
    {
        SearchBox.TextChanged += (_, _) =>
        {
            UpdateSearchHint();
            RefreshList();
        };
        ClearSearchButton.Click += (_, _) => SearchBox.Clear();

        SortCombo.ItemsSource = new[] { "등록 최신순", "등록 오래된순", "수정 최신순", "수정 오래된순", "제목 가나다/ABC순" };
        SortCombo.SelectedIndex = 0;
        SortCombo.SelectionChanged += (_, _) => RefreshList();
        CategoryFilterCombo.SelectionChanged += (_, _) => RefreshList();
        MemoList.SelectionChanged += (_, _) => LoadSelectedMemo();

        NewButton.Click += (_, _) => NewMemo();
        SaveButton.Click += (_, _) => SaveMemo();
        DeleteButton.Click += (_, _) => DeleteMemo();
        InfoButton.Click += (_, _) => ShowInfoWindow();
        BackupButton.Click += (_, _) => ShowBackupWindow();
        SettingsButton.Click += (_, _) => ShowSettingsWindow();

        foreach (var family in Fonts.SystemFontFamilies.OrderBy(f => f.Source))
        {
            FontCombo.Items.Add(family.Source);
        }
        FontCombo.SelectedItem = ResolveFontFamily(settings.FontFamily);
        FontCombo.SelectionChanged += (_, _) => ApplyFontFamily();

        foreach (var size in new[] { 8, 9, 10, 11, 12, 14, 16, 18, 20, 22, 24, 28, 32, 36, 48, 72 })
        {
            SizeCombo.Items.Add(size);
        }
        SizeCombo.SelectedItem = settings.BodyFontSize;
        SizeCombo.SelectionChanged += (_, _) => ApplyFontSize();

        BoldButton.Click += (_, _) => EditingCommands.ToggleBold.Execute(null, BodyBox);
        ItalicButton.Click += (_, _) => EditingCommands.ToggleItalic.Execute(null, BodyBox);
        UnderlineButton.Click += (_, _) => EditingCommands.ToggleUnderline.Execute(null, BodyBox);
        TextColorButton.Click += (_, _) => PickTextColor(false);
        HighlightButton.Click += (_, _) => PickTextColor(true);
        UpdateSearchHint();
    }

    private void UpdateSearchHint()
    {
        SearchHintText.Visibility = string.IsNullOrWhiteSpace(SearchBox.Text)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshList(string? selectMemoId = null, bool keepListFocus = false)
    {
        if (loading) return;
        var category = CategoryFilterCombo.SelectedItem as string ?? MemoStore.AllCategory;
        var sort = SortCombo.SelectedItem as string ?? "등록 최신순";
        var items = store.Search(SearchBox.Text, sort, category);
        var rows = items.Select(m => new MemoListRow(m)).ToList();
        selectMemoId ??= currentMemo?.Id;
        loading = true;
        try
        {
            MemoList.ItemsSource = rows;
            MemoList.SelectedItem = rows.FirstOrDefault(row => row.Memo.Id == selectMemoId);
            if (MemoList.SelectedItem is not null) MemoList.ScrollIntoView(MemoList.SelectedItem);
        }
        finally
        {
            loading = false;
        }
        if (keepListFocus && MemoList.SelectedItem is not null)
        {
            MemoList.Focus();
        }
        CountText.Text = $"{items.Count}개 메모";
    }

    private void LoadSelectedMemo()
    {
        if (loading) return;
        if (MemoList.SelectedItem is MemoListRow row)
        {
            LoadMemo(row.Memo);
        }
    }

    private void LoadMemo(MemoItem memo)
    {
        currentMemo = memo;
        TitleBox.Text = memo.Title;
        SelectComboValue(CategoryCombo, MemoStore.GetCategory(memo));
        LoadRtf(memo.Rtf, memo.PlainText);
        MetaText.Text = $"등록: {MemoStore.FormatDate(memo.CreatedAt)}    수정: {MemoStore.FormatDate(memo.UpdatedAt)}";
    }

    private void NewMemo()
    {
        currentMemo = null;
        MemoList.UnselectAll();
        TitleBox.Clear();
        SelectComboValue(CategoryCombo, MemoStore.AllCategory);
        BodyBox.Document.Blocks.Clear();
        BodyBox.Document.Blocks.Add(new Paragraph { Margin = new Thickness(0) });
        BodyBox.FontFamily = new FontFamily(ResolveFontFamily(settings.FontFamily));
        BodyBox.FontSize = PointsToPixels(settings.BodyFontSize);
        BodyBox.Foreground = BrushFromHex(settings.BodyColor);
        BodyBox.Background = BrushFromHex(settings.BackgroundColor);
        MetaText.Text = $"작성 시작: {MemoStore.FormatDate(DateTime.UtcNow.ToString("o"))}";
        TitleBox.Focus();
    }

    private void SaveMemo()
    {
        var isNew = currentMemo is null;
        var memo = currentMemo ?? new MemoItem();
        memo.Title = TitleBox.Text;
        memo.Category = CategoryCombo.SelectedItem as string ?? MemoStore.AllCategory;
        memo.PlainText = GetDocumentText();
        memo.Rtf = GetDocumentRtf();
        currentMemo = store.SaveMemo(memo, isNew);
        LoadMemo(currentMemo);
        RefreshList(currentMemo.Id, keepListFocus: true);
        MessageBox.Show(this, "저장했습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Information);
        if (MemoList.SelectedItem is not null)
        {
            MemoList.Focus();
        }
    }

    private void DeleteMemo()
    {
        if (currentMemo is null) return;
        if (MessageBox.Show(this, "이 메모를 삭제할까요?", "윈도우 메모", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        store.DeleteMemo(currentMemo.Id);
        NewMemo();
        RefreshList();
    }

    private void LoadSettingsIntoUi()
    {
        settings = store.LoadSettings();
        settings.StartWithWindows = StartupManager.IsStartWithWindowsEnabled();
        settings.FontFamily = ResolveFontFamily(settings.FontFamily);
        TitleBox.FontFamily = new FontFamily(settings.FontFamily);
        TitleBox.FontSize = PointsToPixels(settings.TitleFontSize);
        TitleBox.Foreground = BrushFromHex(settings.TitleColor);
        BodyBox.FontFamily = new FontFamily(settings.FontFamily);
        BodyBox.FontSize = PointsToPixels(settings.BodyFontSize);
        BodyBox.Foreground = BrushFromHex(settings.BodyColor);
        BodyBox.Background = BrushFromHex(settings.BackgroundColor);
        UpdateTrayIconVisibility();
    }

    private void InitializeTrayIcon()
    {
        trayIcon = new System.Windows.Forms.NotifyIcon
        {
            Icon = LoadAppIcon(),
            Text = "WMemo",
            Visible = settings.CloseToTray,
            ContextMenuStrip = new System.Windows.Forms.ContextMenuStrip()
        };
        trayIcon.ContextMenuStrip.Items.Add("열기", null, (_, _) => ShowFromTray());
        trayIcon.ContextMenuStrip.Items.Add("종료", null, (_, _) => ExitApplication());
        trayIcon.DoubleClick += (_, _) => ShowFromTray();
    }

    private void UpdateTrayIconVisibility()
    {
        if (trayIcon is not null)
        {
            trayIcon.Visible = settings.CloseToTray;
        }
    }

    public void ShowFromTray()
    {
        Show();
        ShowInTaskbar = true;
        WindowState = WindowState.Normal;
        Activate();
    }

    private void ExitApplication()
    {
        allowExit = true;
        trayIcon?.Dispose();
        System.Windows.Application.Current.Shutdown();
    }

    private static System.Drawing.Icon LoadAppIcon()
    {
        try
        {
            var resource = System.Windows.Application.GetResourceStream(new Uri("pack://application:,,,/Assets/note.ico"));
            if (resource?.Stream is not null)
            {
                return new System.Drawing.Icon(resource.Stream);
            }
        }
        catch
        {
        }

        return System.Drawing.SystemIcons.Application;
    }

    private void RefreshCategories()
    {
        loading = true;
        var filter = CategoryFilterCombo.SelectedItem as string ?? MemoStore.AllCategory;
        var memoCategory = CategoryCombo.SelectedItem as string ?? MemoStore.AllCategory;
        var categories = store.LoadSettings().Categories;
        CategoryFilterCombo.ItemsSource = categories;
        CategoryCombo.ItemsSource = categories;
        SelectComboValue(CategoryFilterCombo, categories.Contains(filter) ? filter : MemoStore.AllCategory);
        SelectComboValue(CategoryCombo, categories.Contains(memoCategory) ? memoCategory : MemoStore.AllCategory);
        loading = false;
    }

    private void ShowInfoWindow()
    {
        var win = CreateToolWindow("정보", 420, 220);
        var panel = new Grid { Margin = new Thickness(14) };
        panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
        panel.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
        panel.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
        panel.ColumnDefinitions.Add(new ColumnDefinition());
        AddInfoRow(panel, 0, "등록 시간", currentMemo is null ? "-" : MemoStore.FormatDate(currentMemo.CreatedAt));
        AddInfoRow(panel, 1, "수정 시간", currentMemo is null ? "-" : MemoStore.FormatDate(currentMemo.UpdatedAt));
        win.Content = panel;
        win.ShowDialog();
    }

    private void ShowBackupWindow()
    {
        var win = CreateToolWindow("백업", 440, 300);
        var panel = new StackPanel { Margin = new Thickness(14) };
        var lastRestore = MemoStore.FormatDate(store.LoadSettings().LastRestoredAt);
        panel.Children.Add(new TextBlock { Text = $"마지막 복구: {lastRestore}", Margin = new Thickness(0, 0, 0, 12) });
        panel.Children.Add(MakeButton("전체 백업 (.json)", () =>
        {
            var dialog = new SaveFileDialog
            {
                Filter = "메모 백업 (*.json)|*.json",
                FileName = $"backup_wmemo_{DateTime.Now:yyyyMMdd_HHmmss}.json"
            };
            if (dialog.ShowDialog(this) == true)
            {
                store.ExportBackup(dialog.FileName);
                MessageBox.Show(win, "전체 백업을 저장했습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }));
        panel.Children.Add(MakeButton("읽을 수 있는 TXT 백업", () =>
        {
            var dialog = new OpenFolderDialog { Title = "TXT 백업을 저장할 폴더를 선택하세요" };
            if (dialog.ShowDialog(this) == true)
            {
                store.ExportTxtBackup(dialog.FolderName);
                MessageBox.Show(win, "TXT 백업을 저장했습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }));
        panel.Children.Add(MakeButton("백업에서 복구", () =>
        {
            var dialog = new OpenFileDialog { Filter = "Memo backup (*.memo-backup.json;*.json)|*.memo-backup.json;*.json" };
            if (dialog.ShowDialog(this) == true &&
                MessageBox.Show(win, "복구하면 현재 메모가 백업 내용으로 바뀝니다. 계속할까요?", "윈도우 메모", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            {
                store.RestoreBackup(dialog.FileName);
                LoadSettingsIntoUi();
                RefreshCategories();
                NewMemo();
                RefreshList();
                win.Close();
                MessageBox.Show(this, "백업을 복구했습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Information);
            }
        }));
        win.Content = panel;
        win.ShowDialog();
    }

    private void ShowSettingsWindow()
    {
        var win = CreateToolWindow("설정", 520, 480);
        var grid = new Grid { Margin = new Thickness(14) };
        for (var i = 0; i < 9; i++) grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(40) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());

        var font = new ComboBox { ItemsSource = Fonts.SystemFontFamilies.Select(f => f.Source).OrderBy(x => x).ToList(), SelectedItem = settings.FontFamily };
        var titleSize = new ComboBox { ItemsSource = new[] { 14, 16, 18, 20, 22, 24, 28, 32, 36, 48 }, SelectedItem = settings.TitleFontSize };
        var bodySize = new ComboBox { ItemsSource = new[] { 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36 }, SelectedItem = settings.BodyFontSize };
        var closeToTray = new CheckBox { Content = "종료 버튼을 누르면 트레이에 남기기", IsChecked = settings.CloseToTray, VerticalAlignment = VerticalAlignment.Center };
        var startWithWindows = new CheckBox { Content = "Windows 시작 시 자동 실행", IsChecked = settings.StartWithWindows, VerticalAlignment = VerticalAlignment.Center };
        AddSettingRow(grid, 0, "글꼴", font);
        AddSettingRow(grid, 1, "제목 크기", titleSize);
        AddSettingRow(grid, 2, "본문 크기", bodySize);
        AddSettingRow(grid, 3, "카테고리", MakeButton("카테고리 관리", ShowCategoryManager));
        AddSettingRow(grid, 4, "전체 삭제", MakeButton("전체 메모 삭제", () =>
        {
            if (MessageBox.Show(win, "모든 메모를 삭제할까요? 이 작업은 되돌릴 수 없습니다.", "윈도우 메모", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            {
                store.ClearMemos();
                NewMemo();
                RefreshList();
            }
        }));
        AddSettingRow(grid, 5, "종료 동작", closeToTray);
        AddSettingRow(grid, 6, "시작 실행", startWithWindows);

        var save = MakeButton("설정 저장", () =>
        {
            settings.FontFamily = font.SelectedItem as string ?? settings.FontFamily;
            settings.TitleFontSize = (int)(titleSize.SelectedItem ?? settings.TitleFontSize);
            settings.BodyFontSize = (int)(bodySize.SelectedItem ?? settings.BodyFontSize);
            settings.CloseToTray = closeToTray.IsChecked == true;
            settings.StartWithWindows = startWithWindows.IsChecked == true;
            StartupManager.SetStartWithWindows(settings.StartWithWindows);
            store.SaveSettings(settings);
            LoadSettingsIntoUi();
            UpdateTrayIconVisibility();
            MessageBox.Show(win, "설정을 저장했습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Information);
        });
        Grid.SetRow(save, 8);
        Grid.SetColumn(save, 1);
        grid.Children.Add(save);

        win.Content = grid;
        win.ShowDialog();
    }

    private void ShowCategoryManager()
    {
        var win = CreateToolWindow("카테고리 관리", 360, 420);
        var panel = new DockPanel { Margin = new Thickness(14) };
        var list = new ListBox { ItemsSource = settings.Categories };
        DockPanel.SetDock(list, Dock.Top);
        panel.Children.Add(list);
        var input = new TextBox { Margin = new Thickness(0, 8, 0, 8) };
        DockPanel.SetDock(input, Dock.Bottom);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal };
        buttons.Children.Add(MakeButton("추가", () =>
        {
            var name = input.Text.Trim();
            if (name.Length == 0) return;
            if (!settings.Categories.Contains(name)) settings.Categories.Add(name);
            store.SaveSettings(settings);
            input.Clear();
            list.ItemsSource = null;
            list.ItemsSource = settings.Categories;
            RefreshCategories();
            RefreshList();
        }));
        buttons.Children.Add(MakeButton("삭제", () =>
        {
            if (list.SelectedItem is not string name) return;
            if (name == MemoStore.AllCategory)
            {
                MessageBox.Show(win, "전체 카테고리는 삭제할 수 없습니다.", "윈도우 메모", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            settings.Categories.Remove(name);
            var memos = store.LoadMemos();
            foreach (var memo in memos)
            {
                if (MemoStore.GetCategory(memo) == name) memo.Category = MemoStore.AllCategory;
            }
            store.SaveMemos(memos);
            store.SaveSettings(settings);
            list.ItemsSource = null;
            list.ItemsSource = settings.Categories;
            RefreshCategories();
            RefreshList();
        }));
        DockPanel.SetDock(buttons, Dock.Bottom);
        panel.Children.Add(buttons);
        panel.Children.Add(input);
        win.Content = panel;
        win.ShowDialog();
    }

    private string GetDocumentText()
    {
        return new TextRange(BodyBox.Document.ContentStart, BodyBox.Document.ContentEnd).Text.TrimEnd('\r', '\n');
    }

    private string GetDocumentRtf()
    {
        var range = new TextRange(BodyBox.Document.ContentStart, BodyBox.Document.ContentEnd);
        using var stream = new MemoryStream();
        range.Save(stream, DataFormats.Rtf);
        return Encoding.ASCII.GetString(stream.ToArray());
    }

    private void LoadRtf(string? rtf, string? fallbackText)
    {
        BodyBox.Document.Blocks.Clear();
        if (!string.IsNullOrWhiteSpace(rtf))
        {
            try
            {
                using var stream = new MemoryStream(Encoding.ASCII.GetBytes(rtf));
                new TextRange(BodyBox.Document.ContentStart, BodyBox.Document.ContentEnd).Load(stream, DataFormats.Rtf);
                return;
            }
            catch
            {
            }
        }

        BodyBox.Document.Blocks.Add(new Paragraph(new Run(fallbackText ?? "")));
    }

    private void ApplyFontFamily()
    {
        if (FontCombo.SelectedItem is string family)
            BodyBox.Selection.ApplyPropertyValue(TextElement.FontFamilyProperty, new FontFamily(family));
    }

    private void ApplyFontSize()
    {
        if (SizeCombo.SelectedItem is int size)
            BodyBox.Selection.ApplyPropertyValue(TextElement.FontSizeProperty, PointsToPixels(size));
    }

    private void PickTextColor(bool background)
    {
        var brush = ShowColorPicker(background ? "강조 색" : "글자색");
        if (brush is null) return;
        BodyBox.Selection.ApplyPropertyValue(background ? TextElement.BackgroundProperty : TextElement.ForegroundProperty, brush);
    }

    private SolidColorBrush? ShowColorPicker(string title)
    {
        SolidColorBrush? selected = null;
        var win = CreateToolWindow(title, 320, 210);
        var wrap = new WrapPanel { Margin = new Thickness(14) };
        var colors = new (string Name, Color Color)[]
        {
            ("검정", Colors.Black),
            ("회색", Colors.DimGray),
            ("빨강", Colors.Firebrick),
            ("주황", Colors.DarkOrange),
            ("초록", Colors.SeaGreen),
            ("파랑", Colors.RoyalBlue),
            ("보라", Colors.DarkViolet),
            ("노랑", Colors.Gold),
            ("하늘", Colors.LightSkyBlue),
            ("연두", Colors.LightGreen),
            ("분홍", Colors.LightPink),
            ("흰색", Colors.White)
        };
        foreach (var item in colors)
        {
            var button = new WpfButton
            {
                Content = item.Name,
                Width = 68,
                Height = 30,
                Margin = new Thickness(0, 0, 6, 8),
                Background = new SolidColorBrush(item.Color)
            };
            button.Click += (_, _) =>
            {
                selected = new SolidColorBrush(item.Color);
                win.Close();
            };
            wrap.Children.Add(button);
        }
        win.Content = wrap;
        win.ShowDialog();
        return selected;
    }

    private Window CreateToolWindow(string title, int width, int height)
    {
        return new Window
        {
            Owner = this,
            Title = title,
            Width = width,
            Height = height,
            MinWidth = Math.Min(width, 360),
            MinHeight = Math.Min(height, 220),
            FontFamily = new FontFamily("Malgun Gothic"),
            FontSize = 13,
            WindowStartupLocation = WindowStartupLocation.CenterOwner
        };
    }

    private WpfButton MakeButton(string text, Action action)
    {
        var button = new WpfButton { Content = text, MinWidth = 90, Height = 30, Margin = new Thickness(0, 0, 6, 8) };
        button.Click += (_, _) => action();
        return button;
    }

    private static void AddInfoRow(Grid grid, int row, string label, string value)
    {
        var left = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        var right = new TextBlock { Text = value, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis };
        Grid.SetRow(left, row);
        Grid.SetColumn(left, 0);
        Grid.SetRow(right, row);
        Grid.SetColumn(right, 1);
        grid.Children.Add(left);
        grid.Children.Add(right);
    }

    private static void AddSettingRow(Grid grid, int row, string label, UIElement control)
    {
        var left = new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetRow(left, row);
        Grid.SetColumn(left, 0);
        Grid.SetRow(control, row);
        Grid.SetColumn(control, 1);
        grid.Children.Add(left);
        grid.Children.Add(control);
    }

    private static void SelectComboValue(WpfComboBox combo, string value)
    {
        combo.SelectedItem = combo.Items.Contains(value) ? value : MemoStore.AllCategory;
    }

    private static WpfBrush BrushFromHex(string hex)
    {
        try
        {
            return (WpfBrush)new BrushConverter().ConvertFromString(hex)!;
        }
        catch
        {
            return Brushes.Black;
        }
    }

    private static string ResolveFontFamily(string? preferred)
    {
        var names = Fonts.SystemFontFamilies.Select(f => f.Source).ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!string.IsNullOrWhiteSpace(preferred) && names.Contains(preferred)) return preferred;
        return names.Contains("Malgun Gothic") ? "Malgun Gothic" : "Microsoft Sans Serif";
    }

    private static double PointsToPixels(int points) => points * 96.0 / 72.0;

    private sealed class MemoListRow(MemoItem memo)
    {
        public MemoItem Memo { get; } = memo;
        public string Title => Memo.Title;
        public string Category => MemoStore.GetCategory(Memo);
        public override string ToString() => $"{MemoStore.GetCategory(Memo)} | {Memo.Title}";
    }
}
