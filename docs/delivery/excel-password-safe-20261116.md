# ExcelPasswordSafe · 탐색기·MSI 로컬 검증

기록일: 2026-11-16 · 대상 버전: 1.2.0 · 로컬 평가 후보  
책임: 도구 개발·검증 담당  
관련 문서: [최초 요청](../tools/excel-password-safe/original-request.md), [명세](../tools/excel-password-safe/specification.md), [ADR-0018](../design/0018-excel-password-safe-explorer.md), [사용 안내](../tools/excel-password-safe/index.md)

## 변경 범위와 증거의 경계

첨부 1.1.0을 보존하고 파일 하나를 대상으로 하는 WPF 암호 관리 창, 설정·해제·변경 엔진, 탐색기 정적 메뉴와 현재 사용자 MSI를 별도 소스로 구현했다. Windows 11 메뉴는 `더 많은 옵션 표시`가 대상이다. 기존 FolderState·Office 설치나 다른 도구 코드는 이번 변경 범위가 아니다.

실제 업무 문서는 시험 대상으로 사용하지 않는다. 자동 시험은 새로 만든 합성 파일과 전용 실행 폴더에 한정한다. 빌드 성공·MSI 테이블 검사·설치 성공·실제 Explorer 클릭·실제 Excel 저장은 서로 다른 증거다. 서명 없는 평가 패키지를 상용 승인 제품으로 표시하지 않는다.

실제 Excel 시험 환경은 Windows 11 Pro 23H2 x64, 빌드22631.6199, Windows PowerShell 5.1.22621.6133 STA, Excel x64 16.0.20527.20196이다. 다른 Windows·Office 버전의 결과로 일반화하지 않는다. 환경 원본은 `artifacts/excel-password-safe/excel-full-001/environment.json`에 보관한다.

## 실행 결과

실행 증거가 있는 범위만 통과로 기록한다. `NOT RUN`은 해당 동작을 검증했다는 뜻이 아니다. 아래의 짧은 증거 경로는 `artifacts/excel-password-safe/`를 기준으로 한다.

| 시험 | 상태 | 결과·제한 |
|---|---|---|
| 첨부 ZIP 식별·원본 보존 | PASS | SHA-256 `57A8970B8F1269A8E1E143D8CC2480BC0F813201E6F68EF53FA0B7F56F926D9A`; ZIP의 파일21개와 `upstream/1.1.0`의 SHA-256 개별 일치 확인 |
| PowerShell 구문·코어 계약 | PASS | 최종 빌드의 코어58개 통과. 실제 NTFS 교체, 원본·백업·복구본 보존, 수동 복구, 저널 교체 실패·잠금·원본 변경·뮤텍스·사전 취소·요청 비밀 정리 포함 |
| 컨트롤러 장애·트랜잭션 | PASS | 별도 런타임 사본+모의 worker의6사례 통과. worker 중단·출력 변조·입력 복사본 변조·외부 원본 교체·검증 후 취소·정상 교체. 실제 Excel 장애 재현과 구분 |
| 합성 Excel 설정·변경·해제 | PASS | `excel-full-001/excel-summary.json`의31사례 통과. XLS56·XLSX51·XLSM52·XLSB50·Strict XLSX61의 각6사례와 실제 worker 실행 중 취소1사례. 설정·잘못된 현재 암호 변경 거절·변경·이전 암호 거절·해제·평문 변경 건너뜀 확인 |
| 한글 암호 | PASS | `excel-unicode-001/excel-summary.json`의 XLSX 설정·변경·해제3사례 통과. 최종 실제 Excel 합계34사례이며 앞선 quick6사례는 중복 합산하지 않음 |
| 합성 XLSM VBA 정적 보존 | PASS | `vba-review-20261116/vba-source-review.json`. 전체 컨테이너 해시는 다르지만 내부 스트림13개와 추출 모듈5개 소스 동일. 매크로 실행은 하지 않음 |
| 앱 입력·암호 전달 계약 | PASS | 31개 검사. 암호 조건·인수 인용·파일 사전검사와 Windows PowerShell DPAPI 전달 호환성 포함 |
| WPF 빌드·렌더 | PASS | 6상태×출력DPI96/144/192의18장과 520×520 소형창6장, 합계24장. 기본 암호 변경·오류 및 소형 오류 화면을 시각 검토. 실제 모니터 배율 변경 시험과 구분 |
| MSI 제작·정적 검사 | PASS | 최종 MSI의 파일6개, HKCU 메뉴4개, 인수 인용·단일 선택, x64·현재 사용자 설치 검사. 내장 파일을 추출한 SHA-256이 staging6개와 모두 일치. 실행형 사용자 지정 설치 동작 없음 |
| MSI 정상 설치·복구·제거·재설치 | PASS | `installer-20261116-164945-94a3bbed/installer-results.json`의63개 검사, RollbackMode=None. 복구 안내를 포함한 최종 MSI SHA 일치. 일반 사용자·전용 설치 위치, 누락 EXE 복구, 메뉴·기본 연결·합성 파일·백업 보존, 최종 제거·관련 제품0개 확인 |
| MSI 업그레이드·다운그레이드 차단 | PASS (중간 후보) | `installer-20261116-162723-f1bc5254/installer-results.json`의88개 검사 중 업그레이드 포함. 시험 전용1.2.1로 올리고1.2.0 다운그레이드 거절 확인. 최종 MSI 정상 수명주기의63개와 합산하지 않음 |
| MSI 제품 등록 이전의 실제 쓰기 실패 롤백 | PASS (보충) | `installer-20261116-164708-3af966c2/installer-results.json`, DeferredBeforePublish 방식의75개 검사 통과. 안내 추가 전 후보의 시험 사본에 파일·메뉴 쓰기 뒤 제품 등록 전에 실패를 주입. 아래 늦은 실패와 구분 |
| MSI 제품 등록 이후 강제 실패 롤백 | FAIL | 안내 추가 전 후보의 시험 전용 clone MSI에서 파일·메뉴·제품 등록 실행 후 오류1603 주입. 파일·메뉴는 제거됐지만 등록이 남아 다음 설치가 maintenance로 처리됨. 미해결 제한으로 유지하며 아래 후보 설치 실패 기록 참조 |
| 실제 Explorer 메뉴 클릭 | NOT RUN | Windows 잠금 상태여서 클릭 시험을 진행하지 못함. 전용 위치의 후보 설치는 제거 종료0, 메뉴4개 제거·합성 원본 해시 보존 확인. `explorer-ui-20261116/explorer-ui-results.json`에 기록. 레지스트리 검사·WPF 렌더와 구분 |
| 문서 strict 빌드·생성 로컬 링크 | PASS | `.tools/docs-venv/Scripts/python.exe -m mkdocs build --strict` 및 `scripts/check-site.py site` 종료0. 공개20페이지+404·검색·사이트맵·로컬 링크·비공개 제외 확인. 새 문서6개의 상대링크27개 오류0 |
| Windows/Office 다른 조합·긴 경로·새 사용자·물리 고DPI 모니터 | NOT RUN | 확인한 조합만 지원 근거로 사용 |
| 전원 손실·실제 Excel 프로세스 강제 중단 | NOT RUN | 저널 교체 실패 주입과 모의 worker 중단은 실제 전원 손실 시험이 아님 |
| 코드 서명·신뢰·조직 승인 | NOT RUN | 서명 주체와 조직 승인 미결정 |
| 공개 사이트·Release 게시 | NOT RUN | 요청 범위에 포함하지 않음 |

## 요구사항 대응

REQ-EPS-001은 MSI 등록·실제 메뉴, 002~004는 실제 Excel 결과, 005는 화면·사용성, 006~008은 엔진·장애·암호 전달, 009는 설치 수명주기, 010은 이 기록의 증거 구분으로 판정한다. 최종 구현 소스는 `tools/ExcelPasswordSafe/`이며 시험·설치 진단은 `artifacts/excel-password-safe/`에 로컬 자료로 보관한다.

REQ-EPS-001의 등록과 REQ-EPS-005의 렌더는 자동 검증 대상이지만 실제 탐색기 클릭과 처음 쓰는 사람의 사용성은 미검증이다. REQ-EPS-002~004는 위 한 Excel 빌드에서 검증했으며 다른 Office 버전 전체에 대한 통과 판정은 하지 않는다.

## 최종 로컬 패키지

최종 빌드는 `artifacts/excel-password-safe/build-1.2.0-20261116-164839-52dbe01c/`다. 설치 실패 복구 제한과 같은 MSI의 제거·재설치 안내를 README에 반영하여 다시 제작했다. `build-result.json`, `source-sha256.txt`, 코어·컨트롤러·앱 시험 기록, `ui-smoke/smoke-result.json`, `msi-verification.json`과 추출 파일 해시가 증거다. 코어58개·컨트롤러6사례·앱31개는 총95개 검사이며 실제 Excel34사례와 구분한다. 최종 빌드에서95개와 WPF24장을 다시 확인했다.

| 항목 | 값 |
|---|---|
| 파일명 | `ExcelPasswordSafe-1.2.0-win-x64-evaluation.msi` |
| 사용자 전달 위치 | `artifacts/excel-password-safe/release/ExcelPasswordSafe-1.2.0-win-x64-evaluation.msi` |
| 크기 | 81,920 bytes |
| SHA-256 | `3BDE89785133C5B27F103EAF6EA8D4C1DA529D42FFCD30C4FDE6CD995C564C98` |
| 서명·출시 판정 | 서명 없음, `productionRelease=false`, 로컬 평가용 |

제작 결과 파일의 `installerLifecycle=NotRun`은 제작 단계 자체가 설치하지 않았다는 뜻이다. 이후 설치 수명주기 결과는 별도 `installer-results.json`과 위 표를 따른다. 실제 Explorer 클릭은 잠금 화면 때문에 미검증으로 유지한다.

## 재현 명령과 소스

[제작 안내](../../tools/ExcelPasswordSafe/build/README.md), [빌드 스크립트](../../tools/ExcelPasswordSafe/build/build.ps1), [MSI 검사](../../tools/ExcelPasswordSafe/installer/verify-msi.ps1), [설치 수명주기 시험](../../tools/ExcelPasswordSafe/installer/test-installer.ps1)을 사용한다. 제작 단계는 실제 Excel 시험과 별도다.

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/build/build.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File tools/ExcelPasswordSafe/tests/Test-ExcelSynthetic.ps1 -EvidenceDirectory 'artifacts/excel-password-safe/excel-new-run'
```

Excel 시험은 다른 Excel이 실행 중이지 않고 지정한 증거 폴더가 새 경로일 때만 시작한다. [코어 시험](../../tools/ExcelPasswordSafe/tests/Test-Core.ps1)은 잠금·해시·저널·뮤텍스·수동 복구를 검사한다. [컨트롤러 장애 시험](../../tools/ExcelPasswordSafe/tests/Test-ControllerFailures.ps1)은 실제 엔진의 별도 사본과 모의 worker를 사용하며 제품 런타임에 오류 주입 기능을 넣지 않는다.

## 한계와 배포 상태

원본 1.1.0의 Linux 코어 45개 통과는 출처 기록이며 이번 Windows 시험 수에 합산하지 않는다. 실제 Excel 재저장은 그림·삽입 개체의 모든 내부 데이터나 매크로 동작 동일성까지 입증하지 않는다. Excel 4.0 매크로 보안 확인은 자동화 설정으로 모두 억제되지 않는다.

문서와 소스는 로컬 개발 결과이며 인터넷 게시와 조직 배포 승인으로 간주하지 않는다. 이 도구 문서는 공개 사이트 허용 목록에 추가하지 않는다. 사용자 로그·비밀·업무 자료·로컬 설치 진단은 공개 출력에 포함하지 않는다.

## 후보 시험에서 확인한 문제

첫 Excel 후보는 암호 설정 첫 사례에서 `OpenFailedPossiblePasswordOrCorruption`·`0x800A03EC`로 실패했다. 해당 합성 원본의 실행 전후 SHA-256은 일치했다. 이 실패는 `artifacts/excel-password-safe/excel-quick-001/excel-summary.json`에 보존하며 최종 통과 결과로 덮어쓰지 않는다. Windows PowerShell 5.1의 UTF-8 JSON 읽기를 명시하여 한글 경로 전달을 보완했다.

별도 새 Excel 인스턴스의 인수 비교에서 `Workbooks.Open`의 마지막 `CorruptLoad=0`을 명시한 호출은 1004 오류가 발생하고 이 선택 인수를 생략한 호출은 열렸다. 최종 런타임은 이 선택 인수를 생략하도록 조정했다. 문서상 생략 기본값은 `xlNormalLoad`이고 개체 모델은 복구 열기를 시도하지 않으므로 데이터 복구·추출로 안전 조건을 완화한 것이 아니다. 이후 실제 설정·변경·해제 결과는 위 실행 결과에 따로 기록했다. [Microsoft Workbooks.Open](https://learn.microsoft.com/en-us/office/vba/api/excel.workbooks.open)

### 제품 등록 뒤의 설치 실패 복구

이 절의 실패·보충 롤백 시험 대상은 안내 추가 전 후보 `build-1.2.0-20261116-164005-70c0182a`의 MSI, SHA-256 `5BA8009C9B887CFD1B5779228EAC92794311DC0860F2E8083819B61E6E7D5EFE`다. 최종 전달 MSI의 해시와 구분한다. 최종 재제작은 알려진 제한과 복구 안내를 반영한 것이며 이 실패를 해결했다고 판정하지 않는다.

`installer-20261116-164106-e4ed9eb8`에서는 배포 MSI의 시험 전용 사본에 `InstallExecute`6500과 오류 동작6501을 넣었다. 실제 파일·메뉴·제품 등록을 실행한 뒤 오류1603으로 실패시켰다. 이 주입 동작은 배포 MSI에 포함하지 않았다.

로그에서 파일 복사와 레지스트리 기록이 실행된 것을 확인했다. 롤백 뒤 메뉴4개와 EXE는 없어졌고 합성 업무 파일·백업도 유지됐다. 그러나 롤백 중 레지스트리 접근 거부 오류1401·1403·5가 남았으며 제품 등록은 남았다. 다음 정상 MSI 설치가 `ProductState=5`·`Installed=00:00:00`으로 maintenance 경로를 탔고, 종료0이어도 메뉴가 없어 시험이 실패했다.

시험의 정리 제거는 종료0이었다. 근거는 같은 폴더의 `installer-results.json`, `forced-rollback.log`, `install.log`, `cleanup-uninstall.log`다. 뒤에 성공한 다른 설치·제거 시험이나 제품 등록 이전에 주입한 오류 시험으로 이 실패를 통과 처리하지 않는다. 따라서 설치 중 모든 실패의 자동 복구를 검증 완료로 표시하지 않는다.

제품 코드·패키지 코드를 새로 부여한 시험 사본에서도 같은 조건을 반복했다. `installer-20261116-164611-87fbf576/installer-results.json`에서 파일·메뉴 제거는 통과했지만 등록이 `ProductState=5`로 남는 실패가 재현됐다. 정리 제거는 종료0이었다. 단순히 같은 MSI 식별자를 재사용해서 생긴 결과로 치부하지 않는다. 정상 수명주기63개 통과와 이 늦은 실패는 독립된 결과다.

사용자 안내에는 설치 실패 뒤 같은 MSI를 다시 열어 **프로그램 제거**를 실행하고 완료 후 재설치하는 복구 절차를 적는다. 시험에서는 제거 명령의 종료0을 확인했으며 잠긴 화면에서 사용자가 직접 제거 버튼을 클릭한 시험은 하지 않았다. 운영체제 권한이나 Windows Installer 보안 설정을 바꿔 시험 결과를 우회하지 않았다.

## 합성 XLSM의 VBA 별도 확인

`picture_vba.xlsm`의 `vbaProject.bin` 전체 SHA-256은 처리 전후 서로 달랐다. 원본 합성 fixture와 `excel-full-001`의 암호 해제 결과만 별도로 읽어 검사했다. VBA 실행이나 Office 보안 설정 변경은 하지 않았다.

`oletools`로 추출한 VBA 모듈5개의 소스가 모두 정확히 같았다. `olefile`로 이름별 비교한 내부 OLE 스트림13개도 모두 바이트·SHA-256이 같았으며 `_VBA_PROJECT`, `dir`와 캐시 스트림을 포함한다. 컨테이너의 디렉터리 순서·스트림 배치·저장소 시각 변화가 관찰됐다. 따라서 이 표본의 전체 컨테이너 해시 차이를 VBA 소스·스트림 손실로 판정하지 않는다.

근거는 `artifacts/excel-password-safe/vba-review-20261116/vba-source-review.json`과 양쪽 추출 소스다. 이는 이 합성 표본의 정적 보존 확인이며 매크로 실행 동작이나 다른 VBA 문서의 완전한 보존을 보증하지 않는다.
