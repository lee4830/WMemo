# Windows 11 Memo Utility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows 11 memo utility with rich text editing, search, sorting, settings, backup, TXT export, and restore.

**Architecture:** Split the project into a testable PowerShell core module and a Windows Forms UI script. The core handles memo storage, search, sorting, backup, restore, and settings persistence; the UI only coordinates controls and calls the core.

**Tech Stack:** PowerShell 5+/7, .NET Windows Forms, JSON files, RichTextBox RTF.

---

### Task 1: Core Storage Tests

**Files:**
- Create: `tests/MemoStore.Tests.ps1`
- Create: `src/MemoStore.psm1`

- [ ] **Step 1: Write failing tests** for save, update, search, sort, TXT export, and restore.
- [ ] **Step 2: Run tests** with `powershell -ExecutionPolicy Bypass -File tests/MemoStore.Tests.ps1` and confirm they fail because `src/MemoStore.psm1` is missing.
- [ ] **Step 3: Implement core module** with JSON-backed memo and settings functions.
- [ ] **Step 4: Run tests** and confirm all assertions pass.

### Task 2: Windows Forms App

**Files:**
- Create: `src/WindowsMemo.ps1`
- Create: `Run-WindowsMemo.bat`

- [ ] **Step 1: Build the three-column WinForms layout** with memo list, editor, and tabbed side panel.
- [ ] **Step 2: Wire memo commands** for new, save, delete, search, sort, and date filters.
- [ ] **Step 3: Add rich text controls** for bold, italic, underline, font family, size, text color, highlight, and defaults.
- [ ] **Step 4: Add backup/restore controls** for full JSON backup, readable TXT backup, and restore.

### Task 3: Verification

**Files:**
- Modify as needed: `src/MemoStore.psm1`
- Modify as needed: `src/WindowsMemo.ps1`

- [ ] **Step 1: Run tests** with `powershell -ExecutionPolicy Bypass -File tests/MemoStore.Tests.ps1`.
- [ ] **Step 2: Parse scripts** with PowerShell AST parser to catch syntax errors.
- [ ] **Step 3: Launch command is documented** through `Run-WindowsMemo.bat`.
