# WMemo

Windows 11용 메모 유틸리티입니다.

권장 버전은 WPF 기반 `WMemo.exe`입니다. PowerShell WinForms 버전에서 일부 한글 입력기가 글자를 한 칸씩 띄우거나 스페이스를 탭처럼 처리하는 문제가 있어, 일반적인 Windows 데스크톱 앱 방식의 WPF 버전을 추가했습니다.

## 실행

권장 실행 파일:

`dist\WMemo-Portable\WMemo.exe`

작업표시줄 고정 메뉴가 보이지 않으면 아래 설치 스크립트를 한 번 실행한 뒤 시작 메뉴의 `WMemo` 바로가기를 우클릭해서 고정하세요.

```powershell
powershell -ExecutionPolicy Bypass -File Install-WMemo.ps1
```

기존 PowerShell WinForms 버전:

`Run-WindowsMemo.vbs`

## 주요 기능

- 제목과 본문 메모 작성
- WPF RichTextBox 기반 본문 꾸미기
- 제목/본문 검색
- 등록일/수정일 기록
- 등록/수정/제목 순 정렬
- 카테고리 추가, 삭제, 필터링
- 전체 백업 및 복구
- 사람이 읽을 수 있는 TXT 백업
- 설정에 따라 종료 시 트레이에 남기기
- 설정에 따라 Windows 시작 시 자동 실행

## 테스트

```powershell
dotnet build src\WMemo.Wpf\WMemo.Wpf.csproj -c Release
powershell -ExecutionPolicy Bypass -File tests/MemoStore.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tests/WindowsMemoUi.Tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File src/WindowsMemo.ps1 -ValidateOnly
```
