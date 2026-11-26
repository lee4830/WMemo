using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace WMemo.Wpf;

public sealed class MemoStore
{
    public const string AllCategory = "전체";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    public string DataDirectory { get; }
    public string StorePath { get; }
    public string SettingsPath { get; }

    public MemoStore()
    {
        DataDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WindowsMemoUtility");
        StorePath = Path.Combine(DataDirectory, "memos.json");
        SettingsPath = Path.Combine(DataDirectory, "settings.json");
        Directory.CreateDirectory(DataDirectory);
        if (!File.Exists(StorePath)) File.WriteAllText(StorePath, "[]", Encoding.UTF8);
        if (!File.Exists(SettingsPath)) SaveSettings(new MemoSettings());
    }

    public List<MemoItem> LoadMemos()
    {
        var raw = File.ReadAllText(StorePath, Encoding.UTF8);
        if (string.IsNullOrWhiteSpace(raw)) return [];
        return JsonSerializer.Deserialize<List<MemoItem>>(raw, JsonOptions) ?? [];
    }

    public void SaveMemos(IEnumerable<MemoItem> memos)
    {
        File.WriteAllText(StorePath, JsonSerializer.Serialize(memos, JsonOptions), Encoding.UTF8);
    }

    public MemoSettings LoadSettings()
    {
        var defaults = new MemoSettings();
        if (!File.Exists(SettingsPath)) return defaults;
        var loaded = JsonSerializer.Deserialize<MemoSettings>(File.ReadAllText(SettingsPath, Encoding.UTF8), JsonOptions);
        if (loaded is null) return defaults;

        loaded.FontFamily = string.IsNullOrWhiteSpace(loaded.FontFamily) ? defaults.FontFamily : loaded.FontFamily;
        loaded.TitleFontSize = loaded.TitleFontSize <= 0 ? defaults.TitleFontSize : loaded.TitleFontSize;
        loaded.BodyFontSize = loaded.BodyFontSize <= 0 ? defaults.BodyFontSize : loaded.BodyFontSize;
        loaded.TitleColor = string.IsNullOrWhiteSpace(loaded.TitleColor) ? defaults.TitleColor : loaded.TitleColor;
        loaded.BodyColor = string.IsNullOrWhiteSpace(loaded.BodyColor) ? defaults.BodyColor : loaded.BodyColor;
        loaded.BackgroundColor = string.IsNullOrWhiteSpace(loaded.BackgroundColor) ? defaults.BackgroundColor : loaded.BackgroundColor;
        loaded.Categories = NormalizeCategories(loaded.Categories);
        loaded.LastRestoredAt ??= "";
        return loaded;
    }

    public void SaveSettings(MemoSettings settings)
    {
        settings.Categories = NormalizeCategories(settings.Categories);
        File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, JsonOptions), Encoding.UTF8);
    }

    public List<string> NormalizeCategories(IEnumerable<string>? categories)
    {
        var result = new List<string> { AllCategory };
        foreach (var category in categories ?? [])
        {
            var name = (category ?? "").Trim();
            if (name.Length == 0 || name.Contains('?') || name.Contains('\uFFFD')) continue;
            if (!result.Contains(name)) result.Add(name);
        }
        return result;
    }

    public List<MemoItem> Search(string query, string sortBy, string category)
    {
        query = (query ?? "").Trim().ToLowerInvariant();
        var items = LoadMemos()
            .Where(m => category == AllCategory || GetCategory(m) == category)
            .Where(m => query.Length == 0 ||
                        ((m.Title ?? "") + "\n" + (m.PlainText ?? "")).ToLowerInvariant().Contains(query))
            .ToList();

        return sortBy switch
        {
            "등록 오래된순" => items.OrderBy(m => ParseDate(m.CreatedAt)).ToList(),
            "수정 최신순" => items.OrderByDescending(m => ParseDate(m.UpdatedAt)).ToList(),
            "수정 오래된순" => items.OrderBy(m => ParseDate(m.UpdatedAt)).ToList(),
            "제목 가나다/ABC순" => items.OrderBy(m => m.Title, StringComparer.CurrentCultureIgnoreCase).ToList(),
            _ => items.OrderByDescending(m => ParseDate(m.CreatedAt)).ToList()
        };
    }

    public MemoItem SaveMemo(MemoItem memo, bool isNew)
    {
        var now = DateTime.UtcNow.ToString("o");
        var memos = LoadMemos();
        memo.Title = string.IsNullOrWhiteSpace(memo.Title) ? "제목 없음" : memo.Title.Trim();
        memo.Category = string.IsNullOrWhiteSpace(memo.Category) ? AllCategory : memo.Category.Trim();
        memo.UpdatedAt = now;

        if (isNew)
        {
            memo.Id = Guid.NewGuid().ToString("N");
            memo.CreatedAt = now;
            memos.Add(memo);
        }
        else
        {
            var index = memos.FindIndex(m => m.Id == memo.Id);
            if (index >= 0)
            {
                memo.CreatedAt = memos[index].CreatedAt;
                memos[index] = memo;
            }
            else
            {
                memo.CreatedAt = now;
                memos.Add(memo);
            }
        }

        SaveMemos(memos);
        return memo;
    }

    public void DeleteMemo(string id)
    {
        SaveMemos(LoadMemos().Where(m => m.Id != id));
    }

    public void ClearMemos() => SaveMemos([]);

    public void ExportBackup(string path)
    {
        var backup = new MemoBackup
        {
            ExportedAt = DateTime.UtcNow.ToString("o"),
            Memos = LoadMemos(),
            Settings = LoadSettings()
        };
        File.WriteAllText(path, JsonSerializer.Serialize(backup, JsonOptions), Encoding.UTF8);
    }

    public void RestoreBackup(string path)
    {
        var backup = JsonSerializer.Deserialize<MemoBackup>(File.ReadAllText(path, Encoding.UTF8), JsonOptions)
                     ?? throw new InvalidOperationException("백업 파일을 읽을 수 없습니다.");
        if (backup.App != "WindowsMemoUtility" || backup.Version < 1)
            throw new InvalidOperationException("지원하지 않는 백업 파일입니다.");
        SaveMemos(backup.Memos);
        if (backup.Settings is not null)
        {
            backup.Settings.LastRestoredAt = DateTime.UtcNow.ToString("o");
            SaveSettings(backup.Settings);
        }
        else
        {
            var settings = LoadSettings();
            settings.LastRestoredAt = DateTime.UtcNow.ToString("o");
            SaveSettings(settings);
        }
    }

    public void ExportTxtBackup(string directory)
    {
        Directory.CreateDirectory(directory);
        var memos = LoadMemos();
        var lines = new List<string>
        {
            "Windows Memo Utility TXT Backup",
            $"ExportedAt: {DateTime.Now:yyyy-MM-dd HH:mm:ss}",
            $"Count: {memos.Count}",
            ""
        };

        var index = 1;
        foreach (var memo in memos)
        {
            var fileName = $"{index:000}-{SafeFileName(memo.Title)}.txt";
            File.WriteAllLines(Path.Combine(directory, fileName),
            [
                $"Category: {GetCategory(memo)}",
                $"Title: {memo.Title}",
                $"CreatedAt: {memo.CreatedAt}",
                $"UpdatedAt: {memo.UpdatedAt}",
                "",
                memo.PlainText ?? ""
            ], Encoding.UTF8);
            lines.Add($"{GetCategory(memo)} | {memo.Title} | Created: {memo.CreatedAt} | Modified: {memo.UpdatedAt} | File: {fileName}");
            index++;
        }

        File.WriteAllLines(Path.Combine(directory, "index.txt"), lines, Encoding.UTF8);
    }

    public static string GetCategory(MemoItem memo)
    {
        return string.IsNullOrWhiteSpace(memo.Category) ? AllCategory : memo.Category.Trim();
    }

    public static string FormatDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value == "-") return "-";
        return ParseDate(value).ToLocalTime().ToString("yyyy년 MM월 dd일 HH시 mm분", CultureInfo.GetCultureInfo("ko-KR"));
    }

    private static DateTime ParseDate(string? value)
    {
        return DateTime.TryParse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var parsed)
            ? parsed
            : DateTime.MinValue;
    }

    private static string SafeFileName(string? value)
    {
        var safe = string.IsNullOrWhiteSpace(value) ? "Untitled" : value.Trim();
        foreach (var c in Path.GetInvalidFileNameChars()) safe = safe.Replace(c, '_');
        return safe.Length > 70 ? safe[..70] : safe;
    }
}
