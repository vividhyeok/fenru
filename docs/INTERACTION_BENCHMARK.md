# 필기·페이지 조작 벤치마킹 (2026-11-04)

|공식 자료|사용 흐름|Fenru 반영|
|---|---|---|
|[Xodo Stylus as Pen](https://feedback.xodo.com/support/solutions/articles/35000202850-using-stylus-as-pen-mode)|펜 필기와 손가락 이동·확대 분리|펜 전용을 기본값으로 하고 터치 제스처를 PDF 뷰어에 전달. 스타일러스 제스처는 필기 표면이 소비|
|[Samsung Notes S Pen](https://www.samsung.com/us/support/answer/ANS10003634/)|버튼을 누르면 지우개, 놓으면 이전 도구|보조 펜 버튼/뒤집힌 펜 이벤트 처리. 한 번의 접촉 중에도 펜→지우개→펜 전환|
|[Goodnotes Pen](https://support.goodnotes.com/hc/en-us/articles/7353756785679-Write-and-customize-ink-with-the-Pen-tool)|자주 쓰는 도구·색상·굵기를 가까이 배치|고정 도구줄에서 읽기·펜·형광펜·지우개·Undo/Redo, 색상과 굵기 저장|
|[Goodnotes Eraser](https://support.goodnotes.com/hc/en-us/articles/7353718249231-Erase-handwriting-and-page-content-with-the-Eraser-tool)|획 삭제와 복원, 지우개 범위 안내|획 단위 삭제와 복원. 지우개 원형 미리보기|

직접 다른 앱을 실행한 비교가 아닌 공식 사용 안내를 기준으로 한 비교입니다. 실물 Galaxy S펜의 버튼 이벤트, 플랫폼 손바닥 거부 동작, 장시간 필기 지연은 별도 기기 검증이 필요합니다. 영역 일부 지우기·라쏘 편집·필압 선 굵기는 이번 구현 범위에 포함하지 않았습니다.


## alpha.10: 필기 공간 정리
- 삼성 노트의 누르는 동안 지우개 패턴 유지. 기존 처리에서 빠져 있던 Flutter `kPrimaryStylusButton`을 `kSecondaryStylusButton`과 함께 처리한다. 두 버튼의 펜→지우개→펜 회귀 테스트를 각각 실행한다.
- [Flexcil 공식 도구 안내](https://support.flexcil.com/hc/en-us/articles/8164459936537-Pen-toolbar)의 선택한 도구 다시 누르기: 색상·굵기·즐겨찾기는 별도 패널에 배치.
- PDF 안의 48px 한 줄에 필기 도구만 유지하고, 페이지 번호 메뉴에 검색·이동·맞춤·책갈피·노트를 배치한다. AI 패널은 필기 도구줄 옆에서 상단부터 사용한다.
- 손가락 필기·읽기 배경은 전역 설정으로 이동. 집중 모드는 제목·필기 도구·탐색·AI를 숨긴다.
- 실물 버튼의 실제 입력 확인은 설치 후 별도 확인이 필요하다. 시뮬레이션 테스트 결과를 실물 검증으로 간주하지 않는다.
