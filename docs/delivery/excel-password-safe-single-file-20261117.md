# ExcelPasswordSafe · 작은 단일 파일 지연 후속 기록

기록 시작: 2026-11-17 · 버전: 4 · 상태: 단일 파일·혼합 배치 구현 및 관련 검증 완료, 릴리스 준비
관련: [사용자 원문](../tools/excel-password-safe/original-request.md), [현재 명세](../tools/excel-password-safe/specification.md), [직접 처리 결정](../design/0042-excel-password-safe-direct-ooxml.md), [버전 3 성능 기록](excel-password-safe-performance-20261117.md)

## 요구와 완료 기준

기존 피드백은 “암호화 복호화가 지나치게 오래걸립니다.”이며 사용자는 후속 질문에 “작은 파일 하나도 오래 걸림”이라고 답했다. 크기·소요 시간의 숫자는 제공하지 않았다. 이번 범위는 작은 단일 파일의 지연이다. 폴더 배치의 Excel 재사용 효과를 단일 파일의 개선으로 설명하지 않는다.

초기 조사는 `.xlsx`·`.xlsm`의 원시 OOXML 패키지를 Excel 시작 없이 처리할 수 있는지 검토했다. 이후 버전 4 후보에서 OfficeIMO의 고정 raw Agile/CFB 소스와 읽기 전용 PackageGuard를 채택했다. `.xls`·`.xlsb`와 명확한 미지원 조합은 기존 Excel 경로를 유지한다. 아래 기존 계약·초기 제안은 조사 이력이며 구현과 실제 시험은 마지막 대응표에서 확정한다. 기존 버전 3을 수정된 것으로 표시하지 않는다.

충분한 완료 근거는 동일한 작은 단일 파일·동일 작업의 기존/후속 전체 시간, 새 경로의 암호·바이트 보존과 거절 조건, 대표 실제 Excel 상호운용, 실패·취소 시 원본 불변 확인이다. 화면·설치가 바뀌지 않으면 무관한 수동 UI·설치 시험을 추가하지 않는다. 시간 개선은 실제 비교 결과가 나오기 전 주장하지 않는다.

## 기존 구현의 정확한 계약

조사 기준은 버전 3 소스 `a58164ba4d8bcc4938cc4606030140903d28b426`의 `runtime/Common.ps1`, `Engine.ps1`, `ExcelPassword.Worker.ps1`과 현재 명세다. 다음은 제안이 아닌 현재 코드 동작이다.

| 항목 | 현재 처리 |
|---|---|
| 파일·권한 | 고정 로컬 NTFS, 지원 확장자만 허용. 파일과 조상 재분석 지점, 읽기 전용·offline·Excel 잠금 파일, 사용자별 중복 작업 제외. 전체 기존 Excel 프로세스 확인도 유지 |
| 입력·암호 | 승인 SHA-256과 잠근 스트림 해시 확인. 현재 암호 필수, 새 암호 1~15자, 변경 전후 동일 암호 금지. DPAPI 전달이며 명령줄·로그에 암호 없음 |
| 열기 | 별도 Excel에서 읽기 전용, UpdateLinks=0, 이벤트·VBA 자동 실행 해제. 명시한 현재 암호로 열기 실패는 암호/손상을 단정하지 않는 오류 |
| 제외 순서 | 열기 후 문서 서명 또는 VBASigned → 공유(MultiUserEditing) → 쓰기 예약(WriteReserved) → 작업과 기존 암호 상태 판정. 앞 세 조건은 `Skipped` |
| 실제 형식 | 처리할 파일에서 `.xls`=56, `.xlsx`=51/Strict61, `.xlsm`=52, `.xlsb`=50을 확인. 불일치는 `UnsupportedOrMismatchedFormat`; 변환 없음 |
| 내용 검증 | 시트명·형식·표시 상태, UsedRange 범위·형식을 구분한 Formula 해시, 도형 이름/형식 목록, FileFormat·HasVBProject 비교. XLM 시트 형식 3/4는 거절. 모든 바이너리 내용·화면의 완전한 검증은 아님 |
| 결과 암호 | 저장 결과의 해시를 먼저 고정하고 Excel로 재열기. 설정/변경의 잘못된 암호, 변경의 이전 암호는 Excel의 정상 거절 오류로 검증. 끝의 결과 해시도 같아야 함 |
| 교체·정리 | 백업과 입력 복사본 해시, 원본/잠긴 스트림·결과 해시, 취소 및 배치 세션이 전달한 UI 소유 상태 재검사 후 File.Replace. 교체 후 결과와 recovery 해시 확인. 정상 임시 파일 삭제, 원본 백업 유지. 불확실한 상태는 중지·복구 보존 |
| 현재 한계 | 요청 JSON은 65,536바이트 이하, worker 기본 제한시간 180초. 통합문서 자체의 ZIP entry 수·압축 해제 크기 제한은 현재 COM 경로에 직접 구현되어 있지 않음 |

암호가 걸린 파일에 설정을 요청해도 현재 코드가 암호 없이 상태를 항상 판별하는 것은 아니다. 먼저 Excel 열기를 시도하므로 열기에 실패하면 `AlreadyEncrypted`가 아닌 열기 오류가 될 수 있다. 직접 경로에서 상태를 더 일찍 판별한다면 분류 변경을 기록하되 기존 암호를 임의 교체하지 않는 계약을 유지한다.

## 검증 방식이 바뀌는 지점

MS-OFFCRYPTO의 EncryptedPackage는 압축된 ECMA-376 원본 전체를 암호화하는 스트림이다. 따라서 ZIP을 다시 저장하거나 개별 XML을 수정하지 않고 원시 바이트를 암복호화하면 수식·서식·그림·VBA·외부 연결·알 수 없는 파트도 동일 바이트로 보존할 수 있다는 설계 근거가 있다. 실제 채택 시 입력과 재복호화 결과의 전체 길이·SHA-256을 비교해야 한다. [EncryptedPackage 구조](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/b60c8b35-2db2-4409-8710-59d88a793f83)

이는 **Excel이 문서를 복구 없이 정상적으로 연다는 검증과 다르다**. 제한된 ZIP/메타데이터 검사는 모든 셀·수식·확장 기능의 의미적 유효성을 증명하지 않는다. 직접 경로를 채택할 때 REQ-EPS-002~004의 결과 재열기를 경로별로 명시해야 한다. 직접 경로는 암호 확인·무결성·원시 패키지 바이트 동일성 및 대표 Excel 상호운용 근거, 기존 경로는 실제 Excel 재열기라는 차이를 숨기지 않는다.

원본 잠금·승인 해시·백업·결과 고정 해시·원자 교체·교체 후 검증·취소·정리 계약은 경로에 관계없이 유지할 수 있다. 상태/로그는 실제 사용한 경로를 구분하되 암호와 업무 내용을 기록하지 않는다.

## 초기 패키지 판정 검토

아래 표는 조사에 따른 구현 제안이며 현재 지원을 확대하는 선언이 아니다. 판정은 파일 이름의 관습만으로 하지 않고 content type, 관계, XML namespace와 실제 존재하는 part를 대조한다. 범위를 확신할 수 없는 지원 기능은 기존 경로로 넘길 수 있지만, 발견한 손상·암호 오류·무결성 실패를 fallback으로 우회하지 않는다.

| 조건 | 필요한 판정·보존 | 제안 분기 |
|---|---|---|
| OOXML 파일 종류 | `[Content_Types].xml`, 패키지 관계의 유일한 내부 officeDocument 대상, workbook root를 확인. `.xlsx`의 일반 workbook과 `.xlsm`의 macroEnabled content type을 구분하고 `.xlsx`에 VBA/매크로 파트가 숨겨진 모순도 확인 | 확실한 지원 조합만 직접 처리. 확장자/내용 모순은 실패 |
| Strict `.xlsx` | Strict/Transitional의 workbook·관계 namespace를 각각 이해하고 원본 bytes 유지. SDK로 열고 재저장하여 namespace를 변환하지 않음 | Strict를 판별·시험하지 못한 구현은 Excel fallback. 지원 시 별도 Strict 상호운용 근거 |
| 문서 서명 | 모든 관계·content type에서 OPC digital-signature origin/signature/certificate를 식별. `_xmlsignatures/` 같은 관습 이름은 보조 신호일 뿐 | 기존 `SignedWorkbookUnsupported` 유지. 의미가 불명확한 서명 흔적은 직접 처리하지 않음 |
| VBA 서명 | VBA project 관계와 legacy/Agile/V3 signature 관련 관계·content type·파트를 확인. 단순히 `xl/vbaProjectSignature.bin`만 검사하지 않음 | 서명된 VBA 제외. `.xlsm`의 서명 없는 VBA는 원시 바이트 보존 가능하나 대표 시험 필요 |
| 공유·변경 기록 | revisionHeaders/revisionLog/userNames 관계·content type와 header 공유 상태 검사. sharedStrings는 공유 통합문서의 증거가 아님 | 확실한 공유는 기존 제외. 잔존 기록처럼 의미가 모호하면 Excel fallback으로 현재 판정 유지 |
| 쓰기 예약 | workbook/fileSharing의 reservationPassword 및 ISO hashValue/algorithmName/saltValue/spinCount 검사 | 쓰기 예약은 기존 제외. readOnlyRecommended 또는 userName만으로 쓰기 암호라고 단정하지 않음 |
| XLM | macrosheet와 international macrosheet 관계·content type, 관계 대상 존재 대조 | 발견하면 기존 `Excel4MacroSheetUnsupported`. 매크로 실행 없이 종료 |
| 외부 링크·연결 | 외부 관계를 로컬 파일로 해석하거나 다운로드하지 않음. 링크·연결·캐시를 원시 바이트로 유지 | v3의 일괄 거절 항목이 아님. 기능 미지원이면 fallback 사유를 명시하며 임의 삭제·값 갱신 금지 |
| ZIP·XML 손상 | 중복/모호한 part 이름, 탈출 경로, 불일치하는 관계 대상, 잘린/읽을 수 없는 entry, 필요한 XML 오류는 성공으로 인정하지 않음. XML은 DTD·외부 resolver 차단 | 발견한 손상은 실패. 모든 내용의 완전한 Excel 유효성 검사라고 표현하지 않음 |
| 자원 한계 | 압축 파일/entry 개수, 메타데이터 XML 크기·깊이, 읽을 비압축 바이트, 선언된 암호화 길이·KDF 반복 수, CFB 체인 순환을 제한. 숫자는 구현의 실제 메모리·취소 시험으로 정하고 기록 | 정상 형식이지만 범위 밖이면 명시적 fallback/미지원. 손상·순환·불가능한 길이는 실패. 전체 ZIP을 무제한 메모리에 펼치지 않음 |
| `.xls`·`.xlsb`, 지원 밖 암호 방식 | 현재 Excel 형식·보존 검증을 재사용. IRM/인증서/확장 암호화를 암호 한 개의 일반 Agile로 오인하지 않음 | 식별 가능한 미지원 조합만 Excel fallback. 알 수 없는 컨테이너를 일반 ZIP으로 처리하지 않음 |

OPC는 파일별 content type과 관계로 구성된다. Strict는 별도 namespace를 사용하며 SDK는 이를 매핑하므로 byte 보존 경로는 SDK 재저장을 피해야 한다. [OPC 관계 종류](https://learn.microsoft.com/en-us/dotnet/api/system.io.packaging.package.getrelationshipsbytype?view=windowsdesktop-8.0), [Open XML SDK의 패키지·Strict 설명](https://learn.microsoft.com/en-us/office/open-xml/about-the-open-xml-sdk), [ECMA-376 원문](https://ecma-international.org/publications-and-standards/standards/ecma-376/)

서명 종류와 파일 공유 속성은 아래 공식 정의를 기준으로 분류해야 한다. 이 링크의 XLSB 파트 설명을 그대로 OOXML 전체 유효성 검사로 간주하지 않으며 실제 XML 관계/형식과 대조한다. [VBA 서명](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/8fbb98c8-bf03-429e-b6e8-ae024539b5b9), [VBA Agile 서명](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-xlsb/301bfe6b-5acc-4223-81e6-4ee2cc3fc09b), [V3를 포함한 VBA 서명 파일](https://learn.microsoft.com/en-us/javascript/api/office/office.filetype?view=excel-js-1.15), [수정 기록의 shared 속성](https://learn.microsoft.com/en-us/dotnet/api/documentformat.openxml.spreadsheet.headers?view=openxml-3.0.1), [fileSharing ISO 해시 확장](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-oi29500/2faf54e7-9805-4ca5-a4e7-e74f85d96201), [XLM 파트](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-offmacro2/1de8055f-535b-4ebc-ba18-8d25e2986c89)

## 암호 처리와 충분한 시험

Agile 경로에서는 password verifier 통과만으로 성공하면 안 된다. DataIntegrity HMAC은 StreamSize 8바이트를 포함한 EncryptedPackage 전체에 적용된다. 길이·지원 알고리즘/매개변수·암호 확인·HMAC 검증 후 원본 패키지를 판정한다. HMAC 실패와 잘못된 암호는 원본을 유지하는 실패이며 다른 경로로 우회하지 않는다. [Agile EncryptionInfo](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/87020a34-e73f-4139-99bc-bbdf6cf6fa55), [DataIntegrity 계산 범위](https://learn.microsoft.com/en-us/openspecs/office_file_formats/ms-offcrypto/63d9c262-82b9-4fa3-a06d-d087b93e3b00)

설정 결과는 새 암호로 재복호화한 전체 bytes가 원본과 같아야 하고, 잘못된 암호는 거절해야 한다. 해제는 현재 암호와 무결성을 확인한 평문 bytes를 그대로 출력한다. 변경은 새 암호 재복호화 후 기존 평문과 동일하고 이전 암호가 거절되어야 한다. 새 암호·salt·키 생성과 KDF 비용을 성능만을 위해 약화하지 않는다. 새 구현의 encrypt/decrypt가 같은 오류를 공유할 수 있으므로 자체 왕복만으로 Excel 호환을 선언하지 않는다.

필요한 검증은 지원한 `.xlsx`·Strict·`.xlsm`의 독립 생성 자료/실제 Excel 상호운용, 암호/바이트/무결성 변조 거절, 위 제외·fallback 조건, 취소·원본 변경·임시 파일 정리, 작은 단일 파일의 기존/후속 전체 시간이다. 아직 생성하지 않은 fixture·미실행 시험을 PASS로 표시하지 않는다.

## 채택한 구현과 현재 증거

OfficeIMO 원본 commit `45ce514916aabe4eb65c0190e6df75f827acdf21`의 raw Agile/CFB 부분을 원본 bytes·해시 manifest와 MIT 고지로 포함한다. PackageGuard와 facade는 제품 코드이며 vendor 원본을 재작성하지 않는다. Roslyn은 빌드용으로 고정하고 설치 DLL은 .NET Framework 4.8 BCL만 참조한다. MSI에는 직접 처리 DLL과 `THIRD-PARTY-NOTICES.txt`를 더해 payload 9개를 포함한다. 설치된 앱은 SDK·Python·NuGet runtime을 요구하지 않는다.

엔진은 worker를 시작하기 전 직접 경로를 호출한다. 원본 백업·해시·File.Replace·취소·기존 Excel 실행 차단은 유지하며 처리 결과의 `backend=DirectOoxml`로 경로를 구분한다. unsupported 확장자·컨테이너·알고리즘/매개변수·사전 크기 한계만 기존 Excel로 전달한다. 암호·HMAC·발견한 구조 손상 실패는 직접 종료한다. ZIP guard의 실제 한계는 입력 64MiB, entries 10,000개, 비압축 합계 256MiB, 메타데이터 XML 합계 16MiB·깊이 64다. parser 내부 한계 실패는 Excel로 우회하지 않는다.

`package-guard-001`의 최초 시험 컴파일은 시험 코드의 상수 `Main`과 진입점 이름 충돌로 실패했으며 수정 후 실행했다. 별도 최초 DLL 컴파일은 nullable 경고를 오류로 취급해 실패했고, C#5 방식의 독립 guard 파일에 국소 `#nullable disable`을 적용했다. 실제 검사는 고정 Roslyn과 net48 참조로 컴파일한다. 이후 코드 검토에서 호환성 XML 래퍼 안의 fileSharing 예약 속성을 놓칠 수 있음을 발견해 하위 전체 검사를 추가했다. 아래 이전/후속 결과를 구분하며 초기 실패를 지우지 않는다.

| 대응 요구·검사 | 현재 결과·근거 |
|---|---|
| REQ-EPS-025 요구 | 정확한 단일 파일 답변 확인, 구체 크기/시간 없음 |
| REQ-EPS-002~004·025 패키지 분기 | `package-guard-002/guard-results.json` 47조건 PASS · 래퍼 보완 전 후보 |
| 최종 guard 거절·보존 | `package-guard-003/guard-results.json` 48조건 PASS · 일반/Strict/XLSM/다른 workbook 경로, upstream XLSX/VBA, 서명 3종·공유·쓰기 예약·XLM·CRC/ZIP/XML/경로/한계 검사. 모든 입력 bytes 불변, 실제 Excel 미실행 |
| guard 바이너리 근거 | `PackageGuard.cs` SHA-256 `7064EEEBD49B964166DE4DA4F2D3E4F3446D7A1917036D34025BF15839FEBC3E`; 소스는 고정 Roslyn `/warnaserror+` 컴파일 PASS |
| REQ-EPS-002~004 codec | `direct-crypto-001/direct-crypto-results.json` 97개 PASS · guard 보완 전 후보. 1,362/4,080/4,081/4,096바이트 합성 패키지, Unicode·이전/잘못된 암호·HMAC/암호문 변조 거절·무출력·고정 출력 해시·VBA ZIP bytes. Standard 분기는 실제 암호화 Standard 파일이 아닌 버전 헤더 합성 라우팅 시험 |
| guard 보완 후 codec | `direct-crypto-final-001/direct-crypto-results.json` 97개 PASS · DLL SHA-256 `216E5725B3AD380D0F8ACEB62C8B57BAD8E2EBC6B677E49A97C0AB1D64EA4EF0`. 별도 diagnostic-review는 시험 암호값의 진단 JSON 미포함과 C#의 Console/Debug/Trace 로그 부재 확인. 아래 수신자/컨테이너 보완 전 후보이며 파일명의 final을 최종 배포 판정으로 읽지 않음 |
| REQ-EPS-006·008·016 엔진 연결 | `direct-controller-001` 9개 PASS · 초기 후보. `controller-checks-001`에서 최종 PS 소스의 DirectController 12개 PASS로 후속 확인 |
| 최종 제어기 회귀 | `controller-checks-001`: Core 63·Controller 6·DirectController 12·Session 19조건/180확인·Batch 45 PASS. 시험 PS와 최종 staging의 4개 runtime bytes 동일 확인 |
| 변경하지 않은 v3 시험 승계 | WorkerSession 35·Signature 34의 이전 PASS를 재사용. worker의 v3/v4 파일 SHA는 CRLF/LF 차이로 달랐으나 줄바꿈 정규화 후 소스 동일, BOM 없음과 git blob/소스 불변을 확인했다. 새 버전에서 다시 실행했다고 표시하지 않음 |
| 실제 Excel 상호운용 | `direct-excel-002/direct-excel-results.json` 225개 확인 PASS · 일반 XLSX·VBA XLSM·Strict·1,347바이트 tiny XLSX. 직접 결과를 Excel에서 열기 및 Excel 생성 암호문을 직접 해제하는 양방향, Unicode/변경/잘못된·이전 암호 거절, 전체 원시 ZIP 복원·백업·정리 확인. DLL `C90FEE668BCF86847516AB7ED58204DD331C9BDC60BEC6C876D41BB9AF53DBFD`로 실행한 래퍼/수신자 보완 전 후보이며 정상 자료 결과만 해당 근거로 보존 |
| 단일 파일 전후 시간 | `performance-small1-final-001/performance-results.json` PASS · 최종 패키지와 같은 runtime/crypto, 전체 34확인 통과. 아래 같은 입력 비교에 수치·한계를 기록 |
| 실제 혼합 배치 | `batch-mixed-final-001/batch-excel-results.json` 81개 확인 PASS · 직접→`.xls` Excel→직접 3파일의 설정/변경/해제 성공, 각 실행 소유 Excel 1개·정리 확인. 잘못된 암호의 직접 경로 3회 실패·XLSX 보고서 실제 Excel 열기·수식 없음, 해당 실패 배치에서 Excel 시작 없음 확인 |
| 최종 codec | `direct-crypto-final-002/direct-crypto-results.json` 124개 PASS · 최종 DLL `E5629EDF…C6301`, 추가 수신자/외부 CFB 8종과 변경 작업의 혼합 수신자 무출력 fallback 포함. 실제 인증서 상호운용 시험은 아님. 진단 JSON에 시험 암호값 없음 확인 |
| 최종 EXE 별도 시험 | `app-checks-final-001/app-checks.json`: 최종 EXE `C71E9954…CE32D`에서 App 43·Wizard 44·WPF 60렌더 PASS. 암호 설정 144 DPI 렌더의 버전 4 표기·레이아웃 직접 확인. 종료 후 앱/Excel 프로세스 없음. 물리 화면·실제 메뉴 클릭을 대신하지 않음 |
| MSI·서명·게시 | 아래 `210736-5995acbb` 패키지 제작·정적 검사 완료. 실제 게시 여부·커밋·자산은 별도 게시 기록으로 확인. 버전 3 기록 보존 |
| 문서 검사 | `docs-single-file-001/docs-results.json` PASS · mkdocs strict·공개 사이트 생성 링크/경계·diff, 문서 7개의 상대 링크 38개. 마지막 혼합 배치 결과 추가 뒤 상대 링크·diff를 다시 확인 |

위 근거는 현재 작업 폴더의 `artifacts/excel-password-safe/`에 보관하는 로컬 시험이다. 원본 업무 자료·암호·사용자 로그·설치 진단은 릴리스 자산에 포함하지 않는다. 과거 늦은 MSI 실패에서 제품 등록이 남는 제한, 이전 GUI/설치 미실행 범위와 서명 상태는 이번 변경으로 해결됐다고 표시하지 않는다.

최초 실제 Excel 시험 `direct-excel-001`은 시험 준비의 System.IO.Compression 참조 누락으로 중단됐다. Strict 자료 생성 이후 직접 암호 작업 전의 하네스 오류였고 수정 후 002의 225개 확인을 수행했다. 이 초기 실패를 제품 성공으로 바꾸거나 삭제하지 않는다.

추가 검토에서 암호 descriptor의 추가 인증서 수신자를 무시하거나 알 수 없는 CFB 스트림 정보를 새 암호문에서 잃을 가능성을 확인했다. 정확히 하나의 password 수신자·encryptedKey와 예상한 descriptor만 직접 처리하도록 보완했다. 추가 수신자·알 수 없는 요소/컨테이너 정보는 기존 경로로 보내며 표준 DataSpaces 4개 외의 CFB 스트림·저장소를 허용하지 않는다. 이름 조사 근거는 `cfb-boundary-001/office-streams.json`이다. 추가 합성 변형 8종과 변경 작업의 혼합 수신자 분기는 최종 codec 124개 시험에서 통과했으며 실제 인증서 기능 호환성으로 확대하지 않는다. 보완 후 통제 비교에서 같은 정상 Office 암호문 해제도 성공했다.

## 작은 단일 파일의 통제 비교

`performance-small1-final-001/performance-results.json`은 버전 3과 최종 버전 4 패키지의 runtime을 같은 작은 파일 하나로 순차 비교했다. 설정 입력은 6,184바이트이며 SHA-256 `CB3B4920A17BA8835FDA128EC3815D92B7A60D6EA0FD239D267F089AC4FD38FA`다. 해제는 두 경로 모두 같은 Excel 생성 암호문 16,896바이트, SHA-256 `CBE4A3C8996A3093E39BE5EDDD5114D5460D7366E53BB45C3823AD6DE54033C3`를 사용했다.

| 작업 | 버전 3 | 버전 4 | 관측된 시간 감소 |
|---|---:|---:|---:|
| 암호 설정 | 21,471.34ms | 4,326.32ms | 79.85% |
| 암호 해제 | 19,276.66ms | 4,954.65ms | 74.30% |

엔진 프로세스 시작부터 종료까지 측정해 백업·암호/내용 확인·원본 교체를 포함하며 UI 암호 입력 시간은 제외했다. 순서는 기존 설정→기존 해제→현재 설정→현재 해제이고 경로/작업별 관측은 각각 1회다. 반복 평균·무작위 실행 순서·캐시 영향 분포를 측정한 것은 아니다. crypto/App 시험 프로세스를 끝낸 뒤 비교했으며 무거운 병렬 시험을 함께 돌리지 않았다.

네 실행 모두 `Success`이고 동일 시작 bytes·원본 백업·커밋 결과 해시·작업 파일 및 암호 전달 자료 정리·Excel 종료를 포함한 34개 확인이 통과했다. 현재 runtime과 crypto는 위 최종 MSI 내장 bytes와 같다. 직접 경로의 전체 bytes/HMAC 확인과 기존 Excel 재열기는 서로 다른 검증 방식이며 단순히 검사를 없앤 결과로 설명하지 않는다. 이 수치는 해당 합성 자료와 환경의 단일 관측이며 사용자 파일의 보장 시간이나 모든 Excel 형식의 개선율이 아니다.

실제 혼합 배치의 설정/변경/해제 시간은 각각 약 23.906/26.203/19.460초였다. 이는 서로 다른 형식 3개를 처리한 기능 시험이며 기존 버전과의 전후 성능 비교 수치로 사용하지 않는다.

## 패키지와 게시 확인

최종 stage를 포함한 `git diff --cached --check`에서는 새 `DirectCrypto.cs`, `Test-DirectCrypto.ps1`, `CryptoFixtureTools.cs`의 파일 끝 빈 줄 경고 3건이 있었다. 앞선 tracked 문서/변경 검사 PASS와 구분한다. 동작과 무관한 서식 경고이며 검증한 패키지의 소스 바이트를 보존했다.

`build-4.0.0-20261117-205848-324b0e28`의 MSI는 보완 전 후보이며 최종 게시 자산에서 제외한다. 253,952바이트, SHA-256 `46AD544CA319A7CA8D9C996B7F11CB448C5E9B6303EA4C9643882C0C0683DF54`이고 DLL `216E5725…EA4EF0`를 포함했다. 9개 내장 파일의 해시와 HKCU 6메뉴 루트·18명령·설치 경로 정적 검사는 PASS였다. 빌드의 `-SkipTests`/`tests=NotRun`, `installerLifecycle=NotRun`, `explorerClick=NotRun`, `Unsigned`, `productionRelease=false`는 그대로 보존한다. 별도 시험을 이 빌드 내부에서 모두 실행한 것으로 표시하지 않는다.

보완 후 현재 패키지는 `build-4.0.0-20261117-210736-5995acbb`다. `ExcelPasswordSafe-4-win-x64.msi`는 253,952바이트, SHA-256 `C71A5F8A989E3CF6A5182BA5C418BF0CFC4104453C123F48B13C035C56B4C267`이다. DLL SHA-256은 `E5629EDF466C6A4D972CB37226CACC54989092C0B74BB9AC91AF76E3EBAC6301`, EXE는 `C71E9954FCE41781FFC9B0E64B751D0B07B7EDF836EC63869FF04B758FCCE32D`다. 내장 파일 9개의 추출 해시와 6메뉴 루트·18명령 정적 검사가 PASS다. `-SkipTests`로 제작하여 빌드 자체 `tests=NotRun`을 유지하고 위 별도 시험과 연결한다. 새 MSI의 실제 수명주기·Explorer 클릭은 `NotRun`, 서명은 `Unsigned`, `productionRelease=false`다.

이 기록은 소스·ZIP 동결 시점의 구현·검증 근거다. 버전 4의 실제 게시 여부·대상 커밋·자산은 [GitHub 릴리스](https://github.com/prozac0401/Workspace/releases/tag/excel-password-safe-v4)와 별도 게시 기록에서 확인한다. 게시 완료를 이 문서에 선기입하지 않으며 소스 ZIP의 자기 참조 해시는 넣지 않는다.
