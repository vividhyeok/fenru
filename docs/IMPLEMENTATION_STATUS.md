# 구현 및 검증 현황

최종 갱신: 2026-10-21 (Asia/Seoul)

## 상태
전체 요구사항 미완료. 로컬 학습 기능과 선택적 AI BYOK를 구현한 개발 프리릴리스 후보입니다. 기능 코드 작성과 실행 검증을 구분합니다.

## 코드 작성
- Flutter/Riverpod/go_router 앱, 반응형 내비게이션, 디자인 토큰, 온보딩 진행 저장
- Drift SQLite v1, FTS5, UUID 문서 ID, 별도 원본 복사·SHA256, 변경 outbox
- PDFium 뷰어, 페이지 이동/자동 저장, 책갈피/페이지 메모, 선택 영역 하이라이트/밑줄·본문 검색
- Markdown 편집·자동 저장·미리보기, 문서 연결
- 자료 폴더/태그/검색/다중 선택/휴지통, 일정·완료 상태
- Canvas HTTPS 인증·동일 출처 페이지네이션·429 재시도·선택 과목 파일 및 과제
- 백업/복원·경로 검증·체크섬·벡터 시계·동시 편집 충돌 복사본
- 앱 내부 도움말, CI Windows/Android 빌드와 태그 프리릴리스 워크플로
- OpenAI Responses/DeepSeek Chat SSE, 보안 BYOK 설정·모델 조회/직접 입력, 취소·부분 답변·사용량, 대화 저장·노트 생성
- 선택 텍스트/현재 PDF 페이지 컨텍스트(12,000자), 실제 제공한 문서·페이지만 허용하는 내부 출처 링크, 데스크톱 PDF+AI 분할
- Windows 작업 공간 중복 실행 잠금, 쓰기 직렬화, 앱 비활성화 시 노트 저장
- Windows Inno Setup/Portable, Android 프로젝트 서명 키 및 GitHub Secrets 구성

## 검증
- 원격 저장소가 비어 있음을 확인. GitHub vividhyeok 계정 인증 확인.
- 공식 Flutter 배포 메타데이터: Flutter 3.47.7 / Dart 3.13.5.
- pub.dev API로 직접 의존성 버전 확인.
- Flutter SDK 체크섬 검증/설치 완료. 로컬 flutter analyze 오류 없음.
- 로컬 unit/widget 테스트 21개 통과(쓰기 직렬화 포함). JSON 키 순서가 충돌로 오인되지 않도록 회귀 테스트를 추가해 재검증 중.
- Android API 36.1 x86_64 에뮬레이터에서 온보딩 → PDF 가져오기 → 렌더 → 텍스트 선택 → 하이라이트/책갈피 → DB 재오픈 보존 시나리오 통과.
- GitHub Actions 39561512851: Windows 분석/16개 테스트/release 빌드/설치 프로그램과 Android release APK 빌드 성공.
- GitHub Actions 39564266923: AI 포함 20개 테스트와 Windows 실제 문서 통합 테스트 통과. 전체 후속 빌드는 실행 결과 갱신 필요.
- Windows CI 배포본 실행·최초 온보딩 접근성 트리 확인. 컴퓨터 입력 도구가 SendInput 오류 87을 반환해 이를 수동 조작/시각 검증 성공으로 간주하지 않음. 위젯 테스트 렌더 6개를 별도로 생성·확인.
- 사용자가 Windows 앱 설정에서 Canvas 연결 완료를 보고. 비밀을 읽지 않고 URL 설정 저장/온보딩 완료만 확인. 아직 자료 가져오기 기록·객체는 없음.
- 사용자 승인 후 개발 환경 기존 키로 공식 OpenAI 모델 조회를 시도했으나 HTTP 401. 실제 생성 API 성공 미검증. 새 키는 앱 설정에 직접 입력.
- DeepSeek·Google 실제 계정 연동 미검증. Android 실물 기기 미검증.
- 로컬 Windows 컴파일은 Visual C++ ATL(atlstr.h) 구성요소 부족으로 차단. CI Windows 빌드는 성공.

## 미구현
Google OAuth/Drive 객체 동기화, 전체 문서/과목/라이브러리 RAG,
주석 Undo/Redo·색상 UI·목차·암호 입력 UI,
PDF 텍스트 인덱싱, Canvas Modules/Pages/공지/Calendar와 자동 주기,
Markdown 백링크·수식·이미지 삽입, Android Glance 위젯·공유 인텐트·알림,
Windows 트레이·파일 연결·창 위치, 영어 UI, Windows 코드 서명·MSIX.

## 알려진 제한
백업은 전체 ZIP을 메모리에 생성/해제하며 대용량에 적합하지 않습니다(1GB 한도).
현재 UI는 한국어입니다. 휴지통은 자료·노트·일정·주석을 표시하고 복구할 수 있습니다.
일부 Canvas 파일 리다이렉트는 보안상 거부하며 부분 가져오기는 유지합니다.
파일 변경 버전은 별도 문서로 보관하며 이전 주석을 신규 PDF 좌표로 자동 이전하지 않습니다.

## 다음 작업
1. 최종 CI/서명/APK 설치 검증 후 프리릴리스 공개.
2. 새 API 키로 실제 AI 생성/출처 이동, Canvas 실제 자료 가져오기 검증.
3. Drive OAuth와 객체 동기화, PDF 텍스트 인덱싱/RAG.
4. 플랫폼 위젯/트레이/알림, 번역, 큰 글꼴·실물 기기·성능 검증.

## 사용자/배포 자원 필요
- 로컬 빌드에 충분한 디스크 공간(최소 12GB 권장).
- 실제 연동 검증에 유효한 사용자 API 키. Canvas 계정은 사용자가 앱에 연결함.
- 배포용 Google OAuth 프로젝트/client ID와 Android SHA 등록.
- Android 프로젝트 키는 생성/Secrets 보관 완료. 별도 안전한 키 백업과 선택적 Windows 서명 인증서 필요.

## 산출물
검증 성공 전 정식 릴리스를 만들지 않습니다. 실제 릴리스와 다운로드 주소는 생성 후 기록합니다.
