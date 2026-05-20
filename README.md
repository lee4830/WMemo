# WMemo

Windows 11용 PowerShell WinForms 메모 유틸리티입니다.

## 실행

`Run-WindowsMemo.bat`를 더블클릭하면 실행됩니다.

## 주요 기능

- 제목과 본문 메모 작성
- RichTextBox 기반 본문 꾸미기
- 제목/본문 검색
- 등록일/수정일 기록
- 등록/수정/제목 순 정렬
- 카테고리 추가, 삭제, 필터링
- 전체 백업 및 복구
- 사람이 읽을 수 있는 TXT 백업

## 테스트

```powershell
powershell -ExecutionPolicy Bypass -File tests/MemoStore.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/WindowsMemoUi.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File src/WindowsMemo.ps1 -ValidateOnly
```
