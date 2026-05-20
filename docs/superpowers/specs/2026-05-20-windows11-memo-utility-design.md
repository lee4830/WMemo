# Windows 11 Memo Utility Design

## Goal
Build a Windows 11 desktop memo utility with a three-column UI, title/body memos, rich text editing, searchable metadata, backup, restore, and readable TXT export.

## Platform
Use PowerShell with Windows Forms so the app can run on Windows without external package installation. The UI uses `System.Windows.Forms`, including `RichTextBox` for formatted memo content.

## UI
The app uses the approved A layout:

- Left column: memo list, search box, date filters, and created/modified sort selector.
- Center column: title field, rich body editor, and formatting toolbar.
- Right column: tab panel with Info, Backup, and Settings tabs.

The editor supports body formatting through RichTextBox features: bold, italic, underline, font family, font size, text color, and highlight color. Settings provide defaults for title size, body size, font family, title color, body color, and editor background.

## Data
Memos are stored as JSON in the user's local app data folder by default. Each memo contains:

- `Id`
- `Title`
- `PlainText`
- `Rtf`
- `CreatedAt`
- `UpdatedAt`

Settings are stored separately in JSON.

## Search And Sort
Search checks title and plain body text. Date filters can match created and modified ranges. Sorting supports created newest/oldest and modified newest/oldest.

## Backup And Restore
The backup tab supports:

- Full backup to a `.memo-backup.json` file, preserving metadata and rich text.
- Human-readable TXT export, one `.txt` file per memo plus an index file.
- Restore from a full backup file.

Restore replaces the current memo store after confirmation in the UI.

## Error Handling
Storage and backup operations fail with readable messages. The UI shows message boxes for save, backup, restore, and validation errors.

## Testing
Core behavior is tested outside the GUI:

- Creating and saving memos preserves timestamps.
- Updating memos changes `UpdatedAt` without changing `CreatedAt`.
- Searching checks title and body.
- Sorting by created time works.
- TXT backup writes readable memo files.
- Full backup and restore preserve memo data.
