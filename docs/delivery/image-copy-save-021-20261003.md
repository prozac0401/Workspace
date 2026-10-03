# 그림 복사·저장 0.2.1 · 취소 안내 개선 출하 후보 기록

기록일: 2026-10-03 · 대상: ImageCopySave 0.2.1 · 상태: **출하 후보 검증 완료, PR·게시 대기**

이 문서는 게시 전 출하 후보의 동결 근거다. 이후 PR·태그·게시·원격 자산의 실제 결과는 [0.2.1 Release](https://github.com/prozac0401/Workspace/releases/tag/image-copy-save-v0.2.1) 페이지·본문에 기록한다.

제품 책임: 도구 개발·검증 담당
적용 정책: [추가 도구 개발 기준](../policies/tools.md), [정책 문서 작성 규칙](../policies/documentation.md)
관련 요구: [v1.0 원본](../tools/image-copy-save/ImageCopySave_Requirements_v1.0.md), [v1.1의 취소·완료 계약](../tools/image-copy-save/ImageCopySave_Requirements_v1.1.md), [현행 v1.2 변경 계약](../tools/image-copy-save/ImageCopySave_Requirements_v1.2.md)
관련 결정: [호출·결과 연결 ADR-0017](../design/0017-image-copy-save-invocation.md), [공통 클래식 메뉴 ADR-0023](../design/0023-image-copy-save-classic-menu.md), [보존 보호 ADR-0024](../design/0024-image-msi-preservation.md), [공개 안내 ADR-0025](../design/0025-image-public-guide.md)

## 변경과 데이터 경계

[Workspace PR #10](https://github.com/prozac0401/Workspace/pull/10)의 helper 문구 개선을 출하 버전에 포함한다. `ShellFeedback.ResultMessage`는 종료 코드 3이고 worker 진단이 정확히 `커밋 전에 작업을 취소했습니다.`인 경우 화면에 `그림 작업을 완료하기 전에 취소했습니다.`를 표시한다. 앞뒤 공백·개행을 정리하는 기존 진단 처리와 copy·save 모두에 적용한다.

다른 종료 코드·강제 중단·불확실한 supervision·이미 완료된 작업의 진단은 그대로 유지한다. worker의 취소 시점·커밋·이미지 처리·클립보드·원본·파일 생성·Explorer 메뉴·MSI 보호 알고리즘은 바꾸지 않는다. 새 기능이나 지원 범위는 추가하지 않는다. 관리 코드 버전과 패키지 기본값만 0.2.1에 맞춘다.

## 현재 확인 상태

| 항목 | 결과·범위 |
|---|---|
| 소스·문서·버전 | PASS: managed 입력 18개 원시 해시 일치·helper FileVersion 0.2.1.0·자체 포함 runtime 10.0.12. 원본 명세·과거 실패·완료 수동 시험 보존 |
| 현재 helper 집중 회귀 | **8 PASS / 0 FAIL / 0 SKIP**, 실제 출하 DLL SHA-256 C4B8A6BA…에 연결. 첫 프로젝트 참조의 8 PASS와 중복 합산하지 않음 |
| 실제 WPF 결과 문장 | **NOT RUN**. 기존 UI 표시 경로를 유지하는 순수 문장 분기여서 이번 버전에서 GUI 확인을 반복하지 않음 |
| 출하 payload·내용 해시 | **PASS**: stage 408파일·unpacked 409파일, 실제 MSI payload는 404파일. 중간 MSIX 평가 파일은 출하 자산이 아님 |
| 새 builder 보호 DLL 합성 시험 | **39 PASS / 0 FAIL**. 새 패키지 제작 검증이며 실제 MSI 설치·전체 보존 Suite가 아님 |
| 출하 MSI·소스 해시·서명·payload | **제작·읽기 전용 검사 PASS**: NotSigned 관리자 MSI·404파일·내장 CAB 1개·verb 5개·guard action 2개·Explorer 종료/자동 재시작 비활성. 설치 수명주기는 NOT RUN |
| native DLL 재사용 | **원시 입력·DLL 해시 일치**. 9/27 metadata의 native 소스 5개와 현재 파일·실제 DLL을 대조해 복사 재사용. 당시 66개 시험을 오늘 실행한 수치로 합산하지 않음 |
| 0.2.0에서의 업데이트 소유 목록 | **읽기 전용 감사 PASS**. 새 MSI에 0.1.1/공개 0.2.0 prior 2개·file 808행·등록 46행을 내장하고 식별 정보 일치 확인. 실제 업데이트 시험은 아님 |
| CI/checks | 현재 0.2.1에 대한 실행 근거 미확인. CI 없음이나 다른 도구의 CI 성공을 이 도구의 PASS로 사용하지 않음 |
| Release·태그·원격 자산·Pages | **PR·게시 대기**. 0.2.1 후보·안내를 준비했으며 최종 게시·원격 자산·배포 상태는 GitHub Release 페이지·본문을 따름 |

현재 판정은 출하 후보의 집중 회귀·빌드·정적 검증 완료다. PR·태그·원격 자산·공개 안내 확인은 다음 단계이며 최종 게시 상태는 GitHub Release 페이지·본문을 따른다. 집중 회귀와 읽기 전용 감사를 제품 GUI·설치 수명주기 확인이나 공개 배포로 확대하지 않는다.

## 이번 집중 실행과 재사용 식별

2026-10-03 11:06:09 UTC 실제 출하 payload의 helper DLL을 참조하는 ignored 실행기에서 원래 `HelperContractTests.cs` 8건을 **8 PASS / 0 FAIL / 0 SKIP**으로 확인했다. 출하 DLL SHA-256은 `C4B8A6BAA70D2ED851E53C4A2DDCF2C8F428A4633D6A3FB0821C508BB9EEAE44`이며 MSI에 들어간 DLL과 일치한다. worker 실행·클립보드 접근·Explorer·설치는 하지 않았다. 결과는 `artifacts/image-copy-save/release-validation/image021-shipping-focused-result.json`에 보존한다.

앞선 11:01:59 UTC 첫 프로젝트 참조 실행도 8건을 통과했다. 당시 DLL SHA-256 `8B059371A328CC0A27670B0FC866ED0C97BCFB13FE2241CE213445D6CDD66727`와 `artifacts/image-copy-save/release-validation/image021-focused-result.json`은 별도 이력으로 남긴다. 현재 표는 출하 DLL 실행을 사용하며 두 번의 동일 8건을 16건으로 합산하지 않는다.

첫 ignored 실행기 컴파일은 `System.IO` using 누락으로 CS0246에서 멈춰 시험을 하나도 실행하지 않았다. 실행기에 using만 추가한 뒤 8 PASS를 확인했으며 이 수정으로 제품 소스는 바뀌지 않았다. 실행기 실패를 제품 취소 동작의 회귀나 시험 FAIL로 바꾸어 집계하지 않는다.

native metadata의 원래 제작 시각은 2026-09-27 00:12:04 UTC다. x64 DLL SHA-256 `580BD98AD72F1F93BA4768DAC67131CB8CC9D621571275E380225E27D5DDAA86`와 소스 5개의 원시 해시가 현재 작업본과 모두 일치해 `artifacts/image-copy-save/native-shell/`로 복사 재사용했다. metadata·당시 66 PASS는 과거 근거이며 이번 native 재실행이나 실제 Explorer 확인이 아니다.

공개 0.2.0 MSI는 **50,569,176 bytes**, SHA-256 `82A72EB85F41D6DF29BC94EE57215991BA41BEF542717D81CCC0C850C5F5134B`다. 원격 자산 식별 정보와 빌드 메타데이터·실제 파일이 일치한 뒤 Windows Installer DB를 읽기 전용으로 연 소유 목록 exporter를 수행했다. 감사 목록은 404파일·23등록 값이며 SHA-256 `3999BCD79C2A5B30CDCC6881E2A7AE5FA5757C0E24EDE8ABD96AAC6BD8AF5323`다. `installed=false`, `registryModified=false`로 실제 설치·제품 등록 변경이 없었다. 로컬 목록은 `artifacts/image-copy-save/release-validation/prior-020/ownership-baseline.json`이며 새 MSI의 `-PriorBaseline` 입력과 내장 정적 검사에 사용했다.

## 출하 payload와 MSI 식별

자체 포함 payload의 입력 소스 18개 원시 해시가 빌드 전후 일치했고 pack/unpack 내용·해시 검사가 PASS다. 중간 stage 408파일·unpacked 409파일과 Appx 자료를 제외한 classic MSI 404파일을 구분한다. 중간 MSIX는 배포하지 않는다. 출하 helper FileVersion은 `0.2.1.0`이며 포함된 `Microsoft.NETCore.App`·`Microsoft.WindowsDesktop.App`은 모두 `10.0.12`다.

helper informational version에는 빌드 당시 HEAD `bc68705cb7815e2052f1ca3e4465429f81f53933`가 포함돼 있다. 최종 릴리스 소스 식별은 그 문자열만으로 판단하지 않고 기록한 입력 18개 해시와 최종 태그의 실제 파일 내용을 대조해야 한다. 빌드 이후 제품 입력은 동결했으며 문서 변경은 해당 컴파일 입력과 분리한다.

| 출하 후보 | 식별·결과 |
|---|---|
| 제품 MSI | `ImageCopySave-0.2.1-x64.msi`, **50,593,964 bytes** |
| MSI SHA-256 | `EFF7115A469FBE760741B03D2A2F2C8288F59E6BDBB7AE805586A595E1058FC0` |
| 서명·설치 형식 | NotSigned, Windows 11 x64 자체 포함 관리자 MSI. Explorer 자동 종료·자동 재시작 비활성 |
| 제품·보호 경계 | rollbackTest=false·recoveryUpdate=false. 실패 주입·로컬 복구 후보가 아닌 제품 MSI |
| MSI 정적 확인 | 읽기 전용 PASS: 404파일·내장 CAB 1개·verb 5개·guard action 2개·prior 2개 |
| guard DLL SHA-256 | `F06BED80A290766821260E3C4AE757945538E71FA5E6E867175638443C460CC2`, MSI 내장 바이너리와 일치 |
| guard 합성 단위 시험 | **39 PASS / 0 FAIL**. 새 builder 실행 범위이며 실제 MSI 설치·보존 Suite가 아님 |
| 이전 버전 감사 내장 | 0.1.1과 공개 0.2.0 두 식별자, file 808행·등록 46행의 목록·식별 정보 일치 |
| 실제 MSI 설치 수명주기·WPF·Explorer | **NOT RUN**. 기존 완료 수동 시험과 변경에 무관한 전체 suite를 반복하지 않음 |

제품 builder와 읽기 전용 verifier는 PASS다. 로컬 패키지 결과는 `artifacts/image-copy-save/package-evaluation/package-result.json`, 새 MSI·guard 메타데이터와 로그는 `artifacts/image-copy-save/msi/20261003T110611632Z-d4cebe2e97594284bd29b1bfe9a9ac97/`에 보존한다. 원시 메타데이터의 개인 경로를 공개 자산에 그대로 포함하지 않는다.

## 남은 최소 확인

1. 게시 전 MkDocs strict와 생성 사이트·변경 문서 링크 검사를 수행하고 현재 변경의 PR·check 상태를 확인한다. 기록한 컴파일 입력 18개와 최종 태그의 파일 내용이 일치하는지 대조한다.
2. 공개 MSI·체크섬의 크기·SHA-256이 위 후보와 일치하는지 확인하고 공개 안내 버전·링크·Pages 결과를 확인한다. 원시 설치 로그·개인 경로·사용자 SID는 공개 자산과 Pages에서 제외한다. 최종 게시 상태는 GitHub Release 페이지·본문에 실제 결과로 남긴다.

helper 집중 시험은 `HelperContractTests.Register`의 8건만 기존 코드에 연결하는 로컬 실행기로 제한한다. 기존 전체 실행기에는 helper-contract 전용 명령 옵션이 없으므로 전체 `build.ps1`이나 `--mode-contract-tests`를 이 범위의 실행 명령으로 설명하지 않는다. 실제 WPF·Explorer·worker 취소 버튼과 새 MSI 설치는 이번 실행 범위에서 제외한다.

이미 완료된 메뉴 모드 전환·MSI 전체 수명주기·전체 GUI·외부 앱·전체 suite를 이번 작은 문구 패치의 반복 관문으로 만들지 않는다. 패키지 구조나 보호 입력 감사가 실패하면 해당 차이만 해소한 뒤 다시 판단한다.

## 재사용하는 근거와 한계

[0.2.0 실제 릴리스 기록](image-020-release-20260927.md)의 같은 공개 MSI에 대한 외부 보존 시험 **32 PASS / 0 FAIL / 0 NOT RUN**, 기본 위치 설치와 대표 Explorer 복사·저장은 당시 버전·호스트·범위로 재사용한다. 앞선 HKCU 차단 FAIL·복구 실패·UAC 취소는 같은 문서의 당시 이력으로 그대로 남긴다. 기존 기본 Windows 11 메뉴 두 기능은 사용자 직접 확인이며 새 자동화 확인이 아니다.

저장 후 최종 행 선택 NOT_CONFIRMED, 전체 조건별 숨김·복수 창/탭·외부 앱 미확인, 과거 Explorer 무응답의 원인 미확정, Windows 10·ARM64·네트워크/가상 위치 제외와 무서명 조직 정책은 유지한다. 과거 helper 집중 수치와 다른 도구의 CI는 native·Office·MSI 설치 성공을 뜻하지 않는다. 정식 GitHub 릴리스와 회사의 상용 도입 승인은 별개다.

## 후보와 게시 기록

0.2.1 출하 후보의 제작·집중 회귀·정적 검증은 위 식별 정보로 완료했으며 PR·공개 게시는 대기다. 최종 소스 커밋·공개 태그·Release URL과 원격 자산 검증은 게시 단계에서 확인한다. 기존 공개 0.2.0과 별도 실패 주입 `ROLLBACK-TEST.msi`를 새 0.2.1 제품 자산으로 게시하지 않는다. 상세 로컬 증거는 `artifacts/image-copy-save/release-validation/` 아래에 남기고 공개 요약에는 필요한 수치·해시·지원 한계만 기록한다. 최종 게시 상태는 GitHub Release 페이지·본문을 따른다.
