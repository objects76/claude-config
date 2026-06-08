---
name: weekly-work
description: Automates weekly work report updates by extracting work entries from daily work log and organizing them by Domain for the weekly report sheet.
---

# Weekly Work Skill

주간업무보고 시트를 자동으로 업데이트합니다.

이 스킬은 다음 작업을 내부적으로 수행합니다.
- 업무일지에서 최근 기간의 작업 내역 읽기
- Domain 기준으로 작업 내용 정리
- 주간업무보고 시트의 최신 주간 탭을 찾아 반영

## When to Use

- 주간업무보고를 업데이트해야 할 때
- 업무일지 내용을 Domain 기준으로 정리해서 올려야 할 때

## Prerequisites

- Google Workspace 인증이 되어 있어야 함
- 업무일지 시트와 주간업무보고 시트에 접근 가능해야 함

## Usage

```bash
~/.nanobot/workspace/skills/weekly-work/generate.sh
```

실행하면 스크립트가 필요한 단계들을 자동으로 처리합니다.

에이전트가 사용할 때는 다음 순서를 우선 따릅니다.
- 먼저 업무일지와 주간보고 탭을 읽어 반영할 내용을 생성한다.
- 오늘 날짜(MMDD format)의 탭이 없으면 아래 "탭이 없을 때 절차"를 따라 새 탭을 생성한 뒤 반영한다. 최신 탭 E21에 그대로 덮어쓰면 지난주 보고가 사라지므로 금지.
- 사용자가 별도 중단을 요청하지 않은 한, 갱신 여부를 다시 묻지 말고 바로 실제 update를 실행한다.
- 셸에서 직접 큰 JSON 문자열을 인라인으로 넘기기보다 Python subprocess로 `gws`를 호출해 quoting 오류를 피한다.
- 스크립트가 대기하거나 timeout되면, `generate.sh` 전체 실행 대신 개별 `gws` 호출로 읽기/생성/업데이트를 분리 수행한다.
- 날짜 계산은 가능하면 사용자 로컬 시간대(한국 기준이면 Asia/Seoul)를 기준으로 확인한다.
- update 후에는 대상 셀을 다시 읽어 검증 결과까지 함께 보고한다.

## 탭이 없을 때 절차

오늘 날짜(MMDD) 탭이 없으면 다음 순서로 처리합니다. (예: 2026-06-04 목요일 실행 시 최신 탭이 `0528`이었던 경우)

1. **새 탭 생성** — 가장 최신 MMDD 탭(예: `0528`)을 복제해 오늘 날짜 탭(예: `0604`)을 맨 앞에 생성
   - `gws sheets spreadsheets batchUpdate` + `duplicateSheet` 요청: `sourceSheetId`=최신 탭, `insertSheetIndex: 0`, `newSheetName`=오늘 날짜 MMDD
2. **D21 (지난 주)** — 기존 최신 탭의 `E21` 내용을 읽어 새 탭의 `D21`로 이동
3. **E21 (이번 주)** — 업무일지에서 추출한 이번 주(지난 금요일~오늘) 내용을 새 탭의 `E21`에 반영
   - D21/E21은 `values batchUpdate` 한 번으로 함께 업데이트 (Python에서 JSON 직렬화 후 전달)
4. **검증** — 새 탭의 `C21:E21`을 다시 읽어 정상 반영 확인 후, 검증 결과까지 함께 보고

## Output Target

- 주간업무보고 spreadsheet ID: `12Cs1IAzALEZQnKKF3OJGL4haOv670a6YFODWLCgOWo0`
- 사용자 행: `김정진` → Row 21 (Row 22는 `자료 링크` 행 — `generate.sh`의 `USER_ROW=22`는 잘못된 값)
- 기본 업데이트 대상: 이번 주 column `E` (`E21`), 지난 주는 column `D` (`D21`)
- 주간 탭은 최신 날짜탭(MMDD)을 자동 선택하되, 오늘 날짜 탭이 없으면 최신 탭을 복사해 생성

## Notes

- 날짜 범위와 최신 주간 탭 선택은 스크립트가 자동 처리합니다.
- Domain이 비어 있는 연속 행은 시트 구조에 따라 기대한 대로 집계되지 않을 수 있으니 결과를 한 번 확인하는 것이 좋습니다.
- 수동으로 값만 넣는 것이 아니라, 실제 시트 업데이트까지 수행합니다.
- 사용자 선호: 주간 업무보고 요청 시 갱신 여부를 다시 묻지 말고 바로 반영합니다.
- 현재 `generate.sh`는 마지막 단계에서 `read -p` 확인 입력을 기다리므로, 비대화형 실행 환경에서는 timeout될 수 있습니다.
- `gws sheets spreadsheets values update` 호출 시 본문에 괄호, 줄바꿈, 작은따옴표가 섞이면 셸 quoting 오류가 날 수 있으므로 Python에서 JSON 직렬화 후 인자로 넘기는 방식이 더 안전합니다.
- 최신 주간 탭은 MMDD 형식 탭 중 가장 큰 월/일 값을 선택합니다.
- 주간 탭 이름은 목요일 날짜(MMDD)이며, 보고 기간은 금~목입니다. 목요일 오전에는 이번 주 탭이 아직 생성되지 않았을 수 있습니다 — 이 경우 최신 탭을 복제해 오늘 날짜 탭을 직접 생성합니다.
- 탭 복제 시 전체 멤버의 D/E 값이 그대로 복사되므로, 본인 행(Row 21)만 수정하고 다른 멤버의 셀은 건드리지 않습니다.

## Red Flags

- Google Workspace 인증이 안 되어 있으면 실패할 수 있음
- 업무일지 시트 컬럼 구조가 바뀌면 파싱 로직 수정이 필요할 수 있음
- 실행 전 미리보기 내용을 확인하는 것이 안전함
- 비대화형 환경에서 `generate.sh`를 그대로 실행하면 사용자 입력 대기로 멈출 수 있음
- 셸 quoting 실패 시 update 단계만 별도로 Python subprocess 방식으로 재실행하는 것이 좋음
