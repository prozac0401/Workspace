# Excel 명단 비교 RC10 게시 기록

상태: 게시 완료 · 날짜: 2026-09-20 · 버전: 0.2.0-rc.10

[RC10 릴리즈](https://github.com/prozac0401/Workspace/releases/tag/excel-smart-list-compare-v0.2.0-rc.10)를 한국 시각 2026-09-20 07:38:12에 공개했다. [ADR-0017](ADR-0017-RC10-publication.md)의 사용자 요청에 따라 설치 안내와 검증 자료를 분리했다. 전체 인수 상태는 `NOT_MET`, `fullAcceptancePassed=false`를 유지한다.

## 배포 파일

소스·태그 커밋은 `ac0c08f7608fe5f928bc4336d4e4724fa3a4831e`다. XLAM은 기존 실제 기능·UI 검증 파일과 동일한 SHA-256 `2386375cbe0aec6e62fdfa2129cfbc18d358451666504be8bab2fab3c33f719b`이며, 진단용 XLAM을 배포하지 않았다. 설치 엔진과 두 CMD 실행기도 이전 후보의 정확한 바이트를 유지했다.

| 파일 | 바이트 | SHA-256 |
|---|---:|---|
| ExcelSmartListCompare-0.2.0-rc.10-Setup.exe | 2,230,652 | `d14334fc5c5ad5c4cdf9cc602e953defa70252ba00d09dad32313c55be4ef3a8` |
| ExcelSmartListCompare-0.2.0-rc.10-win-x64.zip | 139,280 | `7da6e663da56876de2e4cdf992d2bed8d01aa0a9c6f2bcc17b6d5b2ac7d52eaa` |
| ExcelSmartListCompare-0.2.0-rc.10-Verification.zip | 179,142 | `7179aad797ed1c4ebf0657ecab3a7720ea8ffb7f888bf0e2a8c9273566782c8c` |
| ExcelSmartListCompare-0.2.0-rc.10-Source.zip | 9,546,503 | `a4ce74f8d91b2e9f97a260515652d56df84aecceb81a2195a3beaa6e5761cf53` |

각 파일의 `.sha256`까지 8개 자산을 게시했다. 모두 다시 다운로드해 크기와 SHA-256이 제작본과 일치함을 확인했다. 전체 자산 값은 [게시 증거](../evidence/rc10/publication.json)에 기록했다.

## 확인 내용

- 새 읽기 전용 감사에서 직렬화 VBA 모듈 7개와 RibbonX가 현재 소스·고정 XLAM과 일치했다. 이전 실제 내장 시험 2개의 정확한 파일 해시·성공 결과·소유 Excel 정상 종료를 다시 대조했다.
- Python 회귀 152개, 문서 strict 빌드, 공개 15페이지·404·검색·사이트맵·정적 자산·생성 로컬 링크 검사를 통과했다.
- 설치 ZIP의 7개 파일, EXE에 넣은 5개 원본 payload 해시, 압축 무결성, 사용자 안내 문구와 비공개 자료 제외를 확인했다. 설치 패키지의 사용자 안내에는 시험 분류 문구나 실패 판정 목록을 넣지 않았다.
- 별도 Verification.zip에 실제 판정, 전체 흐름 요약, 게시 결정과 새 EXE의 OneFile-Build.json을 담았다. 원시 사용자 로그·계정 경로·레지스트리 덤프는 제외했다.
- [문서 배포 작업](https://github.com/prozac0401/Workspace/actions/runs/35473900503)의 build와 deploy가 모두 성공했다. [설치·사용 사이트](https://prozac0401.github.io/Workspace/tools/excel-list-compare/)에서 HTTP 200, RC10 표시와 새 EXE·ZIP 링크를 확인했다.

이번 게시에서는 Excel 실행·설치·보안 설정 변경을 하지 않았다. 새 EXE 컴파일과 게시 성공은 실제 설치 수명주기 검증을 대신하지 않는다. 앞선 실패·부분 검증·미실행 결과는 [검증 판정](../evidence/rc10/validation.json), [사용성 기록](USABILITY_RC10_REPORT.md), [전체 흐름 기록](RC10_END_TO_END_REPORT.md)에 보존한다.
