# 구현 및 검증 현황

최종 갱신: 2026-10-21 (Asia/Seoul)

## 상태
전체 요구사항 미완료. 현재 로컬 기능 중심의 개발 프리릴리스 후보입니다. 기능 코드 작성과 실행 검증을 구분합니다.

## 코드 작성
- Flutter/Riverpod/go_router 앱, 반응형 내비게이션, 디자인 토큰, 온보딩 진행 저장
- Drift SQLite v1, FTS5, UUID 문서 ID, 별도 원본 복사·SHA256, 변경 outbox
- PDFium 뷰어, 페이지 이동/자동 저장, 책갈피/페이지 메모
- Markdown 편집·자동 저장·미리보기, 문서 연결
- 자료 폴더/태그/검색/다중 선택/휴지통, 일정·완료 상태
- Canvas HTTPS 인증·동일 출처 페이지네이션·429 재시도·선택 과목 파일 및 과제
- 백업/복원·경로 검증·체크섬·벡터 시계·동시 편집 충돌 복사본
- 앱 내부 도움말, CI Windows/Android 빌드와 태그 프리릴리스 워크플로

## 검증
- 원격 저장소가 비어 있음을 확인. GitHub vividhyeok 계정 인증 확인.
- 공식 Flutter 배포 메타데이터: Flutter 3.47.7 / Dart 3.13.5.
- pub.dev API로 직접 의존성 버전 확인.
- 로컬 SDK 다운로드 중 C: 공간 소진으로 중단. 로컬 분석/테스트/빌드/GUI 실행 미검증.
- GitHub Actions 결과는 실행 후 이 문서에 갱신해야 합니다.
- 실제 Canvas/OpenAI/DeepSeek/Google 계정 호출 테스트 미실행.

## 미구현
OpenAI/DeepSeek API·모델·스트리밍·채팅·문서 RAG/출처, Google OAuth/Drive 객체 동기화,
PDF 영역 하이라이트·밑줄·주석 Undo/Redo·목차/검색 UI·암호 입력 UI,
PDF 텍스트 인덱싱, Canvas Modules/Pages/공지/Calendar와 자동 주기,
Markdown 백링크·수식·이미지 삽입, Android Glance 위젯·공유 인텐트·알림,
Windows 트레이·파일 연결·창 위치, 영어 UI, 설치형 패키지·정식 서명.

## 알려진 제한
백업은 전체 ZIP을 메모리에 생성/해제하며 대용량에 적합하지 않습니다(1GB 한도).
현재 UI는 한국어입니다. 일반 노트/일정/주석 휴지통은 라이브러리에서 표시되지 않아 별도 복구 UI가 필요합니다.
일부 Canvas 파일 리다이렉트는 보안상 거부하며 부분 가져오기는 유지합니다.
파일 변경 버전은 별도 문서로 보관하며 이전 주석을 신규 PDF 좌표로 자동 이전하지 않습니다.

## 다음 작업
1. CI 분석·테스트·빌드 실패 해결, 실제 플랫폼 러너 및 lockfile 저장.
2. Windows GUI 실행과 Android 기기/에뮬레이터 시나리오 검증.
3. PDF 선택 영역 주석과 텍스트 추출/검색.
4. 선택적 AI BYOK, Drive OAuth 및 객체 동기화 구현.
5. 나머지 플랫폼 기능, 번역, 접근성/성능 검증 및 배포 개선.

## 사용자/배포 자원 필요
- 로컬 빌드에 충분한 디스크 공간(최소 12GB 권장).
- 실제 연동 검증 시 사용자가 승인한 API 키·Canvas 테스트 계정.
- 배포용 Google OAuth 프로젝트/client ID와 Android SHA 등록.
- Android 정식 서명 키(Secrets 주입), 선택적 Windows 서명 인증서.

## 산출물
검증 성공 전 정식 릴리스를 만들지 않습니다. 실제 릴리스와 다운로드 주소는 생성 후 기록합니다.
