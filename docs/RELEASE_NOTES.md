# Fenru 0.1.0-alpha.6 개발 프리릴리스

## 공부 작업 화면
- 채팅의 상시 설정/안내/추천 영역을 정리해 답변 공간을 확보했습니다. 참고 범위·모델·이전 대화·연결 노트는 대화 메뉴에서 엽니다.
- 과목/자료 질문 패널을 넓게 전환하고 다시 나란히 볼 수 있습니다. 작성 중 질문은 전환 시 유지됩니다. 과목 자료 검색·정렬, 최신 답변 이동, 한 문제씩 복습하는 질문 도구를 제공합니다.
- 답변을 노트로 저장하면 완료 메시지와 열기 버튼이 표시됩니다. 같은 답변은 기존 노트를 다시 열며 출처 페이지도 노트에서 확인합니다.

## PDF 필기와 정리 노트
- 리더 도구줄의 **읽기** 메뉴에서 펜 필기 / 자유 형광펜 / 직선 밑줄을 고릅니다. 색상·굵기, 주석 실행 취소/다시 실행, 주석 목록에서 삭제를 지원합니다.
- 텍스트 선택 하이라이트/밑줄, 검색, 목차, 책갈피 등 기존 기능을 유지합니다. 이동/텍스트 선택을 하려면 읽기 모드로 돌아가세요.
- **정리 노트** 버튼으로 해당 자료의 노트를 이어 씁니다. 넓은 화면(논리 폭 1100 이상)에서는 PDF 옆에서, 작은 화면에서는 별도 편집 화면에서 자동 저장합니다.
- 필기 좌표와 메모는 작업 공간에 별도로 저장하며 원본 PDF는 변경하지 않습니다. ZIP 백업에 포함됩니다. 필기가 합쳐진 PDF 내보내기, 필압·팜 리젝션은 제공하지 않습니다.

## 문서 자동 PDF 변환
- 새로 가져오는 DOC/DOCX/PPT/PPTX/HWP/HWPX/RTF/ODT/ODP에 대해 로컬 PDF 변환을 시도하고 원본도 보관합니다. Canvas 가져오기에도 적용됩니다. 변환 실패 원본은 자료를 열어 **PDF로 변환 · 재시도**할 수 있습니다.
- **Windows:** 설치된 LibreOffice를 우선 사용하고, Word·PowerPoint·한글의 문서 자동화 API를 사용할 수 있습니다. 실행 중인 사용자 Office 문서를 종료하지 않으며, 해당 앱을 닫고 재시도하도록 안내합니다. 매크로 자동 실행은 Word/PowerPoint에서 차단합니다. 한글은 자체 파일 접근 허용이 필요할 수 있습니다.
- **Android에는 변환 엔진이 없습니다.** 원본은 보관하며 Windows에서 만든 PDF를 백업으로 옮기거나 원본 앱에서 PDF로 저장해 가져오세요. 암호/DRM/폰트/설치 상태에 따라 변환이 제한되거나 모양이 달라질 수 있습니다.
- 개발 PC의 Word/PowerPoint로 작성한 DOCX/PPTX → PDF 변환과 한글 글자 렌더를 확인했습니다. HWP/HWPX 실제 변환 및 LibreOffice 변환은 아직 미검증입니다.

## Canvas 탐색 확대
파일 목록·주차 모듈·LearningX 외에 Canvas 페이지/모듈 Page, 게시판·공지 첨부, 열람 가능한 게시판 답글, 과제 설명의 Canvas 파일 링크를 탐색합니다. 같은 파일 ID는 한 번 가져옵니다. 학교가 제한한 자료는 건너뛰고 결과에 보고합니다. 모든 학교의 외부 자료실과 제한된 게시물을 보장하지 않습니다. 영상·퀴즈·출석 완료 요청은 실행하지 않습니다.

## 검증과 업데이트
47개 unit/widget 테스트 통과. PDF 펜 입력/검색/확대/주석 Undo·Redo/정리 노트 자동 저장/재오픈 보존을 Windows·Android 문서 통합 테스트로 검증합니다. 최종 결과는 Actions 및 구현 현황을 확인하세요. 이번 변경에서 실제 유료 AI 생성 요청은 하지 않았습니다.

Windows 설치형/Portable는 서명되지 않았습니다. Android APK는 기존 프로젝트 키로 서명합니다. 기존 Fenru를 종료하고 새 버전을 실행하세요. 자료와 연결 설정은 유지되며, 업데이트 전 ZIP 백업을 권장합니다. Google Drive 자동 동기화·의미 기반 전체 라이브러리 RAG/OCR 등 전체 제품 요구사항은 아직 완료되지 않았습니다.

구현 참고: [Word PDF 내보내기](https://learn.microsoft.com/en-us/office/vba/api/word.document.exportasfixedformat), [PowerPoint 저장 API](https://learn.microsoft.com/en-us/office/vba/api/powerpoint.presentation.saveas), [한컴 PDF 자동화 안내](https://forum.developer.hancom.com/t/insertpicture-hwp-pdf/2247), [Canvas 게시판 API](https://developerdocs.instructure.com/services/canvas/resources/discussion_topics), [Canvas 페이지 API](https://developerdocs.instructure.com/services/canvas/resources/pages).
