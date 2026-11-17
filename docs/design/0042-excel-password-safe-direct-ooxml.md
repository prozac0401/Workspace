# ADR-0042 · ExcelPasswordSafe의 OOXML 직접 암호 처리

날짜: 2026-11-17 · 상태: 채택·버전 4 직접 처리와 버전 5 파생 계산 개선 구현·전체 시간 검증 완료
관련: [원문](../tools/excel-password-safe/original-request.md), [명세](../tools/excel-password-safe/specification.md)의 REQ-EPS-002~004·024~026, [버전 4 검증 기록](../delivery/excel-password-safe-single-file-20261117.md), [버전 5 검증 기록](../delivery/excel-password-safe-latency-20261117.md)

## 맥락과 결정

사용자는 “작은 파일 하나도 오래 걸림”이라고 지연 조건을 구체화했다. 버전 3의 배치 Excel 재사용은 첫 단일 파일의 Excel 시작·저장·재열기·종료를 제거하지 않는다. 지원 OOXML에 직접 암호 경로를 추가하고 현재 화면·파일별 백업·교체 계약을 재사용한다.

`.xlsx`·`.xlsm`의 지원 조합은 원시 ZIP bytes 전체를 다시 저장하지 않고 OfficeIMO의 고정 raw Agile/CFB 코드로 처리한다. 원본 소스 commit은 `45ce514916aabe4eb65c0190e6df75f827acdf21`이며 vendor bytes·SHA 목록과 MIT 고지를 보존한다. DLL은 net48 BCL만 참조하고 별도 런타임 설치를 추가하지 않는다. 새 암호·무작위 salt/key와 KDF를 속도 때문에 약화하지 않는다.

입력 64MiB 초과, `.xls`·`.xlsb`, 지원 밖 암호 알고리즘/매개변수·컨테이너는 기존 Excel 경로를 사용한다. 잘못된 암호·HMAC 불일치·발견한 패키지 손상은 원본을 유지한 실패이며 fallback으로 우회하지 않는다. 기존 Excel이 열려 있으면 처리를 막는 조건도 유지한다.

추가 수신자나 컨테이너 정보를 잃지 않도록 직접 경로는 정확히 하나의 password 수신자·encryptedKey와 예상한 descriptor만 받는다. 알 수 없는 CFB 스트림/저장소와 인증서 수신자가 있는 컨테이너는 기존 경로로 넘긴다. 실제 Office 합성 자료에서 확인한 표준 DataSpaces 4개만 EncryptionInfo·EncryptedPackage와 함께 허용한다. 이 경계의 합성 시험은 인증서 기능을 구현하거나 실제 인증서 호환성을 검증한 것이 아니다.

## 검증과 보존

직접 경로의 설정·변경은 새 암호 재복호화 후 전체 평문 bytes 동일성, 잘못된 암호와 변경 전 암호 거절을 확인한다. 해제는 현재 암호·HMAC을 확인한 원시 bytes를 그대로 출력한다. DataIntegrity는 길이 필드까지 포함한 암호화 스트림을 검증한다. 출력 bytes의 해시를 저장 전에 고정하고 독점 핸들로 쓴 파일의 해시와 대조한다. 엔진의 승인 해시·원본 잠금·백업·취소·교체 전후 확인·원자 교체·정리 계약은 유지한다.

읽기 전용 PackageGuard는 ZIP 중앙/로컬 구조·CRC, 중복 part·탈출 경로, workbook 관계·content type·Strict/Transitional namespace, 기존 서명·공유·쓰기 예약·XLM 제외를 확인한다. 외부 관계는 접근하지 않고 unknown XML/바이너리는 그대로 보존한다. 제한은 10,000 ZIP entries, 비압축 합계 256MiB, 메타데이터 XML 16MiB·깊이 64다. XML DTD·외부 resolver는 금지한다. 이 검사에 실패한 구조를 Excel로 다시 시도하여 승인하지 않는다.

이 경로는 매번 실제 Excel을 여는 검증을 하지 않는다. 전체 package bytes 보존은 Excel의 모든 의미·복구 여부를 검증하는 것과 다르므로 명세에 경로별 차이를 기록한다. 대표 자료의 양방향 실제 Excel 상호운용을 별도로 확인한다. `.xls`·`.xlsb` 등 Excel 경로는 기존 의미 비교·재열기 검증을 유지한다.

## 영향과 완료 근거

사용자는 동일한 입력→진행→결과 흐름을 사용한다. `backend=DirectOoxml`은 로컬 결과 진단에만 기록한다. 폴더 내 직접 파일에는 Excel을 시작하지 않으며 Excel이 필요한 파일은 버전 3의 소유 세션을 재사용한다. 최대 3회 안전한 재시도·실패 XLSX·원본 백업·중간 파일 정리와 불확실한 경우의 중지는 동일하다.

필요한 증거는 guard/codec의 손상·거절·byte 보존, 기존 교체 경계와 연결한 제어기 회귀, 대표 실제 Excel 상호운용, 작은 단일 파일의 같은 입력 전후 전체 시간이다. 새 DLL과 제3자 고지가 포함된 MSI의 내장 파일·의존성·메뉴 연결도 확인한다. 검증하지 않은 GUI·설치 수명주기·서명 상태는 이전 결과로 대체하지 않는다. 실제 결과는 검증 기록에만 확정한다.

## 2026-11-17 후속 결정 · 같은 검증을 유지한 파생 계산 개선

사용자가 작은 파일의 4~5초도 줄이되 백업과 검증을 유지하도록 요청했다. 구간 조사에서 비용을 확인한 legacy KDF만 Windows의 재사용 SHA 객체로 연결한다. PowerShell host·assembly 로더 변경은 전체 처리에서 이득을 확인하지 못해 채택하지 않았다. 기존 Engine·프로세스·화면·원본 교체 경계는 유지한다.

같은 salt와 UTF-16LE 암호를 처음 해시한 뒤 little-endian 순번과 앞선 digest를 기존 횟수만큼 해시한다. 새 암호의 100,000회 반복을 낮추지 않으며 입력 암호문의 지원 매개변수도 바꾸지 않는다. AES·HMAC·전체 bytes·잘못된/이전 암호 검증을 모두 수행한다. 객체는 파생 계산 안에서만 재사용하며 작업 간 비밀 캐시는 없다.

vendor 원본은 byte 단위로 보존한다. `kdf-patch.json`이 고정한 원본·2행 dispatch 교체·결과 SHA를 대조해 빌드 출력 사본에만 적용하고 실제 컴파일 목록을 기록한다. net48 BCL 외에 Windows 시스템 `bcrypt.dll`을 호출하며 별도 런타임 배포는 추가하지 않는다. [Microsoft의 재사용 해시 절차](https://learn.microsoft.com/en-us/windows/win32/seccng/creating-a-hash-with-cng)에 따라 객체를 reset하며, [해시 객체 버퍼](https://learn.microsoft.com/en-us/windows/win32/api/bcrypt/nf-bcrypt-bcryptcreatehash)는 네이티브 객체가 참조하는 동안 이동·해제하지 않는다. 실패·취소 경로도 임시 비밀을 지우고 정리 실패에는 결과를 반환하지 않는다.

변경된 파생 함수의 원본 결과 동일성, 포인터 수명·실패·취소 시험과 기존 codec의 거절·보존 시험을 확인한다. 변하지 않은 ZIP/컨테이너·화면·설치 범위는 정확한 소스 근거로 구분하고 무관한 전체 시험을 반복하지 않는다. 같은 작은 입력의 작업별 3쌍 비교에서 세 작업의 중앙값이 줄었고 버전 5에 채택했다. KDF 단독 수치를 파일 처리 시간으로 쓰지 않는다. preview의 버전 메타데이터·최종 패키지·실제 결과·미실행 범위는 [추가 지연 개선 기록](../delivery/excel-password-safe-latency-20261117.md)에 기록한다.
