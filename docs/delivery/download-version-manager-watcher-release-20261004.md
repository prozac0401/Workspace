# DownloadVersionManager 0.2.0 · 폴더 감시 릴리즈 기록

날짜: 2026-10-04 KST · 제품: 0.2.0 x64 · 상태: **무서명 기능 평가 prerelease 준비 완료, 게시 전**

이 기록은 실제 실행한 범위만 남긴다. 기존 0.1.0의 설치 실패·미검증·미게시 결과를 보존하며 상용 승인으로 분류하지 않는다.

## 사용자 결정과 구현

사용자는 브라우저 확장 없이 지정 폴더를 감시하고 프로세스를 유지하는 방향을 채택했다. 이후 최초 기존 번호 그룹의 미리보기·사용자 동의·최신 파일 선택, 신규 번호 파일 연결, 3초 안정·잠금 조건, 동시 후보 보존을 확인했다. 로그인 자동 실행 기본과 설치 위자드 해제, 현재 Windows 다운로드 위치 기본 제시·위치 변경 추종·다른 폴더 선택도 확인했다.

[0.2.0 명세](../tools/download-version-manager/next-version-specification.md)와 [ADR-0028](../design/0028-download-version-manager-folder-input.md)을 기준으로 네이티브 C++ /MT 프로그램을 구현한다. 기존 경로·핸들·크기 우선 비교·streaming SHA-256·History·rollback은 재사용하며 폴더 입력은 기존 브라우저 CompletionOrder를 읽거나 변경하지 않는다.

처음 그룹은 사용자가 선택한 최신 번호 파일을 마지막에 처리한다. 원래 파일 선택은 그룹 보존이다. 후속 신규 단일 후보만 처리 가능 시점에 받아들이며 동시 후보의 최신을 추측하지 않는다. 3초 안정은 앱의 다운로드 완료 증명이 아니다.

## 설치 후보와 구버전 보존

후보 파일: `DownloadVersionManager-Watcher-0.2.0-x64.msi`.

새 MSI product code는 `{6CF9F782-F53F-5964-AEEA-BC1CC63A20C5}`, upgrade code는 `{CBC7F202-BD84-4D52-9438-F01164572918}`이다. 구버전 0.1.0과 설치 폴더·식별자를 분리해 자동 upgrade·등록 변환·삭제를 하지 않는다. 사용자 LocalAppData·HKCU 설치이며 기존 브라우저 확장·Native Messaging 등록을 요구하지 않는다.

최종 MSI SHA-256: `5fba25fe5c07f7813341ca524a9d1807b36357c1a5412bbd47ea63a68ab42e47`, 크기 294,912 bytes. 최종 executable SHA-256: `f14d7ead2eb3c566d9ffd0851e0e085b36c1fca207d3496635a55c052e3354f1`. 실제 파일·build manifest·SHA256SUMS·패키지 확인 결과를 맞췄다.

실제 설치·실행·repair·제거 5개를 통과한 수정 후보는 `6a12b33cd21b3d15cf53dca9fbce899b677bada219bca094e396cc67824db86e`다. 하단 화면 높이 수정 이후 `18f22f04a9fe8478a4ab28dc9c8385aefe0c5ece6eef1b192aa7dd17c0378a32`의 설치·실제 GUI 감시 시작·제거·보존 4개도 성공했다. 마지막 최종 재제작은 잠금·cleanup·metadata 안내 문구만 고쳤다. 처리·배치·MSI·시작 항목은 같아 위 관련 설치·repair 증거를 재사용했으며 최종 hash의 파일 자체를 다시 실제 설치했다고 기록하지 않는다. 초기 제작 후보 `63b2a664…`는 최종 릴리즈 파일로 안내하지 않는다.

위자드는 현재 Windows Known Folder 다운로드 위치와 위치 변경 추종을 기본으로 제시하고 사용자 폴더 선택을 제공한다. 로그인 자동 실행은 기본이며 해제 가능하다. User Shell Folders registry 변경 알림에서 기본 위치를 다시 해석한다. 제거 시 감시 폴더 파일·History와 사용자 실행 설정을 보존한다.

## 실제 검증

| 확인 | 결과 | 범위 |
|---|---|---|
| 폴더 엔진 | **8 PASS / 0 FAIL** | 동일/다른 내용, 신규 객체와 시간, target 부재·잠금, source/target 변경, rollback, 강제 중단 보존 |
| OS 알림 watcher | **15 PASS / 0 FAIL** | 합성 파일 대표 세션, 안정·writer/잠금·동시 후보·임시 최종 rename·범위·중지/재시작. Windows invariant 대소문자 매핑 수정 후 Ä/ä 동시 후보를 포함해 관련 세션만 재확인 |
| 최초 그룹 처리 | **4 PASS / 0 FAIL** | 무동의·보존·선택 최신·미리보기 후 변경 보존. 앞선 slash 형식 harness 호출 실패와 구분 |
| executable 제작·runtime | **PASS** | x64 C++ /MT, 외부 C/C++ runtime import 없음 |
| MSI 구조·payload·checksum | **PASS** | executable 한 개, per-user, 확장/NMI/서비스 없음, 사용자 선택 시작 항목 |
| 새 late-failure recovery | **FAIL** | InstallExecute 뒤 실패에서 제품 등록 rollback access denied(5), 시작 항목 security restore 1307. 공식 시험 제품 제거 exit 0, 합성 파일 보존 |
| 수정 후보 정상 설치·실제 실행·repair·제거·보존 | **5 PASS / 0 FAIL** | fresh/repair/remove exit 0, 설치된 GUI의 격리 폴더 감시 시작·정상 종료, 파일·History·실행 설정 보존, 프로그램/시작 등록 제거, cleaned true |
| 화면 높이 수정 후 설치 자산 | **4 PASS / 0 FAIL** | `18f22f04…` 설치·실제 GUI 감시 시작/정상 종료·제거·사용자 파일/History/실행 설정 보존, cleaned true. 완료한 repair·late-failure 반복 없음 |
| 실제 위자드 기본 위치·선택 표시·취소 | **PASS** | 이동된 현재 Windows 다운로드 위치 표시, 기본 위치 추종·로그인 자동 실행 체크 확인. 취소 exit 1602·설치 없음 |
| 다음 로그인·실행 중 OS 다운로드 위치 변경 | **NOT RUN** | 현재 위치 해석과 소스 구현으로 해당 실기 성공을 대신하지 않음 |
| 문서 strict·공개 링크 | **PASS** | MkDocs strict, 공개 19개·기존 이동 2개·404·검색/사이트맵·생성 로컬 링크. 내부 명세·배포 기록·진단 제외 |
| tag·Release·공개 자산 | **NOT RUN** | 게시 전 |

합계 27개 집중 결과와 수정 후보의 5개·화면 높이 수정 후보의 4개 설치 결과를 구분하며 전체 Host/확장·대용량·브라우저별 시험을 반복하지 않았다. 초기 후보의 INSTALLFOLDER 전달 오류와 제거 후 잔류 검사 FAIL은 보존하고 수정 후보의 성공과 구분한다. GUI 하단 설명 잘림도 보존하고 창 높이 수정 후 실제 표시를 확인했다. 설치 실패 복구는 새 제품에도 남는 실제 제한이다. 정상 설치 성공이나 다른 MSI identity를 근거로 과거 0.1.0 실패를 해결됐다고 바꾸지 않는다.

원시 로그·상태 JSON·로컬 절대 경로는 `artifacts/download-version-manager-watcher/`에 비공개로 보관한다. 이 문서에는 필요한 판정과 후보 지문만 남기며 공개 사이트에서 제외한다.

## 릴리즈 경계

의도한 태그는 `download-version-manager-v0.2.0`이고 사용자 핵심 자산은 MSI와 `SHA256SUMS.txt`다. 정상 설치·실행·제거 근거와 알려진 installer 실패 복구 제한을 포함한 **무서명 기능 평가 prerelease**를 준비했다. 아직 공개 링크를 활성화하거나 Release 게시 완료를 선언하지 않는다.

게시 후 실제 태그·자산 다운로드·checksum·설치 안내 링크를 확인해 이 기록을 마무리한다. 조직 도입·서명 주체·상용 승인은 미결정이다.
