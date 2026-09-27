# G0 메뉴 구현성 검증

현재 기준은 [요구명세 v1.2 변경 계약](../../docs/tools/image-copy-save/ImageCopySave_Requirements_v1.2.md)입니다. Windows 11 클래식 직접 표시 모드의 독립 저장·비이미지 및 실제 파일 클립보드 완전 숨김·실제 PNG 복사/저장, 무서명 MSI 설치·Repair·업데이트·제거·설치 실패 롤백·재설치는 확인한 시나리오에서 PASS입니다. 실제 0.1.0 helper 비상승 실행을 관찰했으며 현재 0.1.1을 설치해 메뉴 검증을 이어갑니다. 클래식 메뉴 PASS와 반복 8회는 0.1.0에서 확인했습니다. 0.1.1 재설치 후 9회차 재개 때 UI 도구 창 활성화 오류로 추가 관찰은 0건이며 반복 시험은 미완료입니다. 메뉴 설정은 읽기만 했으며 실제 전환은 하지 않았습니다. 기본 새 메뉴 경로·모드 복구는 NOT RUN이고 전체 G0는 **미완료**입니다.

Windows 11 기본 메뉴에서는 ‘더 많은 옵션 표시’ 뒤에, 클래식 직접 표시 모드에서는 바로 두 명령을 제공합니다. HKLM native IExplorerCommand·ExplorerCommandHandler 등록과 무서명 관리자 MSI를 검증하며 평소 Explorer/helper는 일반 사용자 권한으로 실행합니다. 이미지 없음의 완전 숨김·무상주·원본 보존은 유지합니다.

현재 판정과 모드별 확인 항목은 Markdown 원본인 [전체 G0 매트릭스](../../docs/tools/image-copy-save/G0_Menu_Feasibility.md)와 [ADR-0023](../../docs/design/0023-image-copy-save-classic-menu.md)를 따릅니다. 이전 첫 메뉴·MSIX·진단 MSI 기록은 당시 증거로 보존합니다. Windows 11의 클래식 직접 표시 시험은 실제 Windows 10 OS 지원 인증이 아닙니다.
