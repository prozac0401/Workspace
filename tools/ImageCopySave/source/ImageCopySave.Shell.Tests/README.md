# Native Shell 경계 시험

이 디렉터리는 native `IExplorerCommand` 어댑터의 순수 정책과 등록 없는 COM 계약을 검사하는 C++17 x64 console harness다. 이 문서의 항목 수는 소스 목록이며 실행 결과가 아니다. Windows 11 실제 메뉴와 설치·제거의 G0/AT 수용시험은 별도 실기 증거가 필요하다.

## 빌드와 실행

저장소의 [build-shell.ps1](../../build/build-shell.ps1)이 Windows 11 SDK와 완전한 MSVC x64 도구 모음으로 DLL과 harness를 빌드하고 실행한다. 직접 컴파일할 때는 C++17, Unicode, UTF-8 source encoding을 사용하고 `ole32.lib`, `shell32.lib`, `uuid.lib`를 링크한다.

```text
ImageCopySave.Shell.Tests.exe --dll C:\evaluation\ImageCopySave.Shell.dll --report C:\evaluation\shell-results.json
```

두 경로는 서로 다른 일반 드라이브 절대 경로여야 한다. report의 상위 폴더는 미리 존재해야 하며, 기존 report를 덮어쓰지 않는다. DLL은 `LoadLibraryExW`의 명시적 절대 경로와 DLL 디렉터리·시스템 디렉터리 검색 플래그로 로드한다. 등록된 CLSID를 활성화하지 않고 DLL의 `DllGetClassObject`를 직접 호출한다.

종료 코드는 전체 성공 `0`, 하나 이상의 검증 실패 `1`, 인수 또는 report 기록 실패 `2`다. JSON 필드는 `schemaVersion`, `scope`, `total`, `passed`, `failed`, `tests[{name,passed,detail}]`다. 실패한 검증도 목록에 남긴다. 테스트가 충돌하거나 프로세스가 중단되어 report가 없으면 성공으로 간주하지 않는다.

## 검증 범위

총 66개의 이름 있는 검증 항목을 실행한다. 각 항목에는 여러 경계값을 포함할 수 있으며 경계값 수를 별도 시험 수로 합산하지 않는다.

| 그룹 | 항목 수 | 범위 |
|---|---:|---|
| 순수 정책·결과 경계 | 18 | 지원 형식의 16가지 합성 플래그 조합, 확장자, 경로 문법·길이·컴포넌트 수, 예약 장치명, 파일 속성, 물리 볼륨 이름, Windows 인수 quoting 왕복, 다른 폴더·중첩 폴더·개행/NUL 결과 거절 |
| 명령별 COM 계약 | 30 | 저장·복사 각각 15개: factory/QI/identity/reference, 메뉴 이름·flags·canonical name, site 수명, null output, 독립 명령 계약 |
| 상태 판정 경계 | 10 | 복사의 null/빈/다중/불확실/비지원 선택, 느린 판정 위임, site 없는 저장 명령 |
| 모듈·factory 수명 | 8 | DLL 로드·exports·unload, 알 수 없는 CLSID/IID, null output, server lock 균형 |

`GetState(FALSE)`는 선택 수만으로 숨길 수 있는 상황을 확인하고, 단일 선택에서는 `E_PENDING`과 초기 `ECS_HIDDEN`을 유지하면서 `GetItemAt` 등 깊은 조회를 하지 않는지 검사한다. 복사 명령의 비지원 항목은 `GetState(TRUE)`에서 가짜 `IShellItemArray`/`IShellItem`로 검사한다. 저장 명령의 상태 시험은 caller site를 한 번도 설정하지 않은 별도 객체만 사용하므로 문맥 확인에서 실패하고 클립보드 경로에 도달하지 않는다.

## 실행 경계와 해석

이 harness는 실제 클립보드 API를 호출하지 않는다. 지원 형식 검사는 `ClipboardFormats`의 합성 bool 값만 사용한다. `Invoke`, helper 실행, COM 등록, Explorer UI, 이미지 파일 생성, 패키지 설치·제거도 수행하지 않는다. 업무 폴더나 사용자 파일을 탐색하지 않으며 생성하는 파일은 호출자가 명시한 새 JSON report 하나다.

가짜 선택 항목의 경로는 파일시스템 조회 전 거절되는 문법 또는 실패 응답만 사용한다. 정상 실제 파일의 metadata 검증이나 양성 메뉴 표시·저장·복사 실행은 이 harness의 증거 범위가 아니다. `GetSite` 수명 시험은 fake `IUnknown`의 참조만 확인하며 caller-site 폴더·탭 해석을 실증하지 않는다.

JSON의 `scope`는 `native-policy-and-com-boundary-only`, `acceptanceTestStatus`는 `NOT RUN`이다. 66개 자동 검증이 실제 통과하더라도 G0 또는 AT-01~AT-44를 PASS로 바꾸지 않는다.
