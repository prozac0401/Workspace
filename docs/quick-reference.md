# 빠른 판단 기준

**정리가 일이 되지 않도록, 지금 필요한 판단부터 찾으세요.** 이 페이지는 기존 운영 정책을 상황별로 찾아보는 안내입니다. 실제 저장 위치·보존·권한은 조직에서 정한 기준을 따릅니다.

## 어디에 두나요? {#where}

| 고민 | 지금 할 일 | 자세한 기준 |
|---|---|---|
| 새 파일을 받았는데 용도가 모호하다 | 파일용 `00_Inbox`에 둡니다. 용도를 알게 되거나 실제 사용할 때 옮깁니다. | [기본 구조와 원본](policies/workspace.md) |
| 지금 하는 업무의 자료다 | `10_Active`의 해당 회차에 둡니다. 이미 회차가 있으면 그곳을 사용합니다. | [업무 키트](policies/kits.md) |
| 새 업무 폴더를 만들어야 하나? | 독립적인 목적·일정·결과물이 있는 새 업무나 새 회차일 때 만듭니다. 같은 회차의 자료는 기존 컨테이너에 둡니다. | [컨테이너를 나누는 기준](policies/workspace.md#container) |
| 반복해서 쓸 업무 틀이다 | `20_Operations`의 MASTER로 관리합니다. 실업무는 복사본에서 합니다. | [MASTER의 수명주기](policies/kits.md#master) |
| Reference인가 Archive인가? | 여러 업무에서 참고할 매뉴얼은 `40_Reference`, 끝난 특정 회차의 결과물·증거는 `80_Archive`입니다. 참고할 과거 결과물은 Archive 원본 링크로 연결합니다. | [기본 구조와 원본](policies/workspace.md) |
| 업무가 끝났다 | 미완료·이슈와 보관 조건을 확인하고 컨테이너째 `80_Archive`로 옮깁니다. 내부를 다시 분류하지 않습니다. | [종료와 보관](policies/archive-security.md) |
| 잠깐 쓰고 없어져도 되는 파일이다 | 없어져도 업무기록이 사라지지 않는 자료만 `90_Temp`에 둡니다. 유일한 결과물·증거는 해당 업무에 둡니다. | [보관 기준](policies/archive-security.md) |

## 어떻게 시작하고 이어가나요? {#work}

| 고민 | 지금 할 일 | 자세한 기준 |
|---|---|---|
| 새 반복 업무를 시작한다 | 미착수 상태로 유지한 MASTER를 Active에 복사하고 회차명·기본정보·기준일을 입력합니다. MASTER 자체에서 진행하지 않습니다. | [업무 키트와 일정](policies/kits.md#master) |
| 어디까지 했는지 알고 싶다 | 단계 폴더의 FolderState를 확인합니다. 상태 변경은 담당자가 판단해 실행합니다. | [상태 사용 안내](tools/folderstate/index.md) |
| 언제, 누가 해야 하나? | 공식 일정 원본인 Schedule 또는 사내 일정 시스템을 봅니다. 담당 역할·연락수단은 Contacts에서 확인합니다. | [운영현황 역할](policies/kits.md#overview) |
| 무엇을 확인해야 하나? | Checklist의 단계 내부 확인사항을 봅니다. 폴더 완료와 같은 체크를 다시 만들지 않습니다. | [운영현황 역할](policies/kits.md#overview) |
| 완료로 바꿔도 되나? | 그 단계의 필요한 결과물과, 해당 업무에 필요한 승인·전달까지 확인한 뒤 완료로 표시합니다. 파일이 있다는 이유만으로 자동 완료하지 않습니다. | [업무 사건과 상태](policies/kits.md#events) |
| 왜 그렇게 결정했는지 남겨야 한다 | 기존 Issues / Decision Log에 결정·이유·근거 위치를 짧게 남깁니다. | [업무 키트와 일정](policies/kits.md#overview) |
| 회신을 기다린다 | 메일은 Action 또는 필요 시 Waiting에 둡니다. 필요한 재확인 일정은 기존 Schedule에 둡니다. 기한 내 통상 대기는 진행 중, 진행을 막는 문제는 이슈로 판단합니다. | [메일함](policies/files-email.md), [상태 판단](tools/folderstate/index.md) |
| 같은 파일이 여러 곳에 있다 | 공식 원본 한 곳을 정해 수정하고 다른 곳에는 그 위치를 연결합니다. | [원본 시스템](policies/workspace.md#source-of-truth) |

## 메일·과거자료·정리 부담은 어떻게 다루나요? {#less-work}

| 고민 | 지금 할 일 | 자세한 기준 |
|---|---|---|
| 메일 첨부파일을 모두 저장해야 하나? | 실제 작업할 첨부만 업무폴더에 저장합니다. 별도 보존이 필요한 승인·비용 근거는 조직의 기록 기준에 따릅니다. | [파일과 이메일](policies/files-email.md) |
| 과거자료가 엉망이다 | 기존 위치를 유지하고, 다시 쓰거나 인수인계에 필요한 자료부터 새 구조에 편입합니다. | [Legacy와 보관](policies/archive-security.md) |
| Inbox를 매일 비워야 하나? | 비우기 자체를 목표로 두지 않습니다. 자료를 사용할 때 위치를 정하고, 메일을 판단했을 때 Action 또는 Archive로 처리합니다. | [최소 정리 원칙](policies/workspace.md#principles) |
| 운영현황이 너무 복잡하다 | 같은 정보를 중복 입력하는 필드를 줄입니다. 실제 누락이 반복된 항목만 기존 기록에 더합니다. | [운영 개선안 — 선택 적용](policies/folder-workflow.md) |

## 한 회차에 적용하면

가상의 과정운영 업무라면 **MASTER 복사 → Active에서 안내문 작업 → 발송 확인 후 해당 단계 완료 → 회차 종료 검토 → 전체 Archive 이동**으로 이어집니다. 일정은 Schedule, 중요한 변경 이유는 Decision Log에만 적습니다.

모든 단계 폴더가 완료라는 표시만으로 회차를 자동 종료하지 않습니다. 남은 업무와 보관 조건은 담당자가 판단하며, FolderState는 폴더를 자동 이동하지 않습니다.

처음 설정한다면 [도입 순서](getting-started.md), 반복적인 대기·인수인계 문제가 있다면 [선택 운영 개선안](policies/folder-workflow.md)을 확인하세요.
