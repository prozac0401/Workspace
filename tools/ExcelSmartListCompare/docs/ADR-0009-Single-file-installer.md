# ADR-0009 · 기존 설치 엔진을 내장한 단일 EXE

상태: 채택 · 날짜: 2026-09-15 · 결정 담당: 사용자 요청에 따른 배포 변경

관련 요구사항·정책: 동일 로직의 단일 설치 프로그램 제작과 EXE 배포 요청, [추가 도구 개발 기준](../../../docs/policies/tools.md), [I26~I30](ACCEPTANCE_TESTS.md).
대체 관계: [ADR-0005](ADR-0005-Process-scoped-launchers.md)의 CMD 실행기와 [ADR-0007](ADR-0007-Replace-previous-installation.md)의 설치 거래를 유지하고 EXE 진입점을 추가한다.

## 맥락

ZIP을 풀고 Install.cmd를 찾는 단계를 없애면서 이미 검증한 RC7의 비교 기능, 설치 준비, 업데이트와 복구 동작을 유지해야 한다.

## 결정

Inno Setup으로 일반 사용자용 단일 EXE를 만든다. 공개 RC7 패키지의 XLAM, Install.cmd, Uninstall.cmd, Setup.ps1, README.md를 바이트 단위로 그대로 내장한다. 빌드 도구는 고정 SHA-256과 일치하지 않는 입력을 거절하고 EXE 실행 시에도 추출 파일의 해시를 확인한다. 버전은 엔진 `0.2.0-rc.7`, 포장 `1`로 분리한다.

설치 준비 화면에서 제품 폴더의 신뢰 위치 등록 범위를 안내한다. 설치 버튼은 기존 ConfirmProduct의 확인을 대신한다. EXE는 경로를 셸 코드에 삽입하지 않고 작업 디렉터리와 고정 CMD 이름으로 실행하며 SLC_SETUP_NO_PAUSE를 자식 프로세스 범위에만 설정한다. 한글 로그를 위해 자식 콘솔의 코드 페이지를 UTF-8로 설정한다. 기존 CMD가 정책·다운로드 표시·STA 실행을 처리한다. 콘솔 출력은 로컬 설치 로그로 수집하고 제품 실패 코드를 화면에 설명한다.

Excel 파일과 등록은 기존 엔진만 소유한다. Inno는 별도 `%LOCALAPPDATA%\ExcelSmartListCompare.Setup` 폴더의 제거 프로그램·엔진 복구본·제품 표식과 HKCU 설치된 앱 항목만 소유한다. 이 관리 폴더는 Excel 신뢰 위치에 포함하지 않는다. 고정 폴더를 변경하는 인자를 거절하고 알 수 없는 기존 관리 폴더를 덮어쓰지 않는다. EXE 설치와 제거의 별도 프로세스 잠금은 원래 엔진 잠금과 함께 유지한다.

설치 엔진이 성공한 뒤 관리 파일과 앱 항목을 기록한다. Windows의 제거 확인 후, 현재 설치된 Setup.ps1과 Uninstall.cmd를 전용 임시 폴더에 그대로 복사해 실행한다. 실행 중인 CMD 자체의 삭제와 현재 작업 폴더 잠금을 피하기 위한 실행 위치 분리이며 엔진 내용은 변경하지 않는다. 파일이 누락된 중단 상태나 기존 CMD로 이미 제거한 경우에는 내장한 엔진 복구본을 같은 방법으로 사용한다. 엔진 제거가 실패하면 예외로 Inno 제거를 중단하므로 관리 파일과 앱 항목이 남는다. Inno에 제품 XLAM이나 Excel 레지스트리 삭제를 중복 등록하지 않는다. 디렉터리 전체를 재귀 삭제하지 않는다.

## 검토한 대안

직접 만든 C# 설치기나 네이티브 엔진 이식은 기존 설치 로직의 재구현과 재검증이 필요하다. 단순 자동 압축 해제기는 Windows 앱 제거와 실패 화면을 별도로 구현해야 한다. 이번 범위에는 Inno의 설치 화면과 제거 수명주기를 사용한다.

## 영향과 이행

사용자는 EXE 하나를 다운로드하고 설치 버튼을 누른다. 기존 RC1~RC6에서 업데이트하거나 RC7을 재설치하는 판단은 원래 엔진이 수행한다. 원래 ZIP과 소스 자산은 보존한다. PowerShell 의존과 조직 정책의 영향은 남으며 전체 매크로 설정이나 영구 실행 정책을 변경하지 않는다. EXE는 Windows x64용이고 코드 서명이 없는 평가용 배포다.

## 실패와 복구

엔진이 실패하면 관리 파일 설치를 시작하지 않는다. 엔진 성공 직후 전원 단절·디스크 오류로 관리 파일 기록만 실패하는 두 단계의 경계는 존재한다. 이 경우 기존 install.json과 Uninstall.cmd가 남는다. 제품 소유 표식이 있는 관리 폴더는 같은 EXE로 다시 설치할 수 있다. 관리 폴더 표식 기록 전 강제 중단으로 알 수 없는 폴더가 남으면 이를 보존하고 중단하므로 폴더 확인이 필요하다. EXE 포장이 기존 엔진보다 강한 전원 단절 롤백을 제공한다고 주장하지 않는다. 사용자 추가 파일은 원래 엔진과 Inno의 개별 소유 파일 제거 규칙에 따라 남는다.

## 검증

[단일 EXE 검증 기록](ONEFILE_REPORT.md)에 실제 EXE, 격리 실패 시험, 설치 수명주기, 원래 엔진 회귀 검사와 미검증 범위를 기록한다. 빌드 메타데이터와 공개 검증 요약만 배포하며 로컬 사용자 경로·원시 설치 로그는 artifacts에 보관한다.

근거: Inno Setup의 [이벤트 수명주기](https://jrsoftware.org/ishelp/topic_scriptevents.htm), [임시 파일 추출](https://jrsoftware.org/ishelp/topic_isxfunc_extracttemporaryfile.htm), [콘솔 출력 수집](https://jrsoftware.org/ishelp/topic_isxfunc_execandlogoutput.htm), [일반 사용자 설치](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm).
