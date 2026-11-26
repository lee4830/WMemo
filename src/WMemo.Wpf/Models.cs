using System;
using System.Collections.Generic;

namespace WMemo.Wpf;

public sealed class MemoItem
{
    public string Id { get; set; } = Guid.NewGuid().ToString("N");
    public string Title { get; set; } = "제목 없음";
    public string PlainText { get; set; } = "";
    public string Rtf { get; set; } = "";
    public string Category { get; set; } = MemoStore.AllCategory;
    public string CreatedAt { get; set; } = DateTime.UtcNow.ToString("o");
    public string UpdatedAt { get; set; } = DateTime.UtcNow.ToString("o");
}

public sealed class MemoSettings
{
    public string FontFamily { get; set; } = "Malgun Gothic";
    public int TitleFontSize { get; set; } = 22;
    public int BodyFontSize { get; set; } = 12;
    public string TitleColor { get; set; } = "#111827";
    public string BodyColor { get; set; } = "#1f2937";
    public string BackgroundColor { get; set; } = "#ffffff";
    public List<string> Categories { get; set; } = [MemoStore.AllCategory];
    public string LastRestoredAt { get; set; } = "";
    public bool CloseToTray { get; set; } = false;
    public bool StartWithWindows { get; set; } = false;
}

public sealed class MemoBackup
{
    public string App { get; set; } = "WindowsMemoUtility";
    public int Version { get; set; } = 1;
    public string ExportedAt { get; set; } = DateTime.UtcNow.ToString("o");
    public List<MemoItem> Memos { get; set; } = [];
    public MemoSettings Settings { get; set; } = new();
}
