# 구현 및 검증 현황

최종 갱신: 2026-10-21 (Asia/Seoul)

## 상태
alpha.5 후보: 사용자의 요청에 따라 독립 AI 메뉴/상단 일반 대화 진입을 제거하고 과목·자료에 질문을 통합했습니다. 과목별 자료 목록/질문 패널, 자료 전체/현재 페이지/선택 문장, 범위별 대화 저장, PDF/텍스트 본문 버전 캐시와 키워드 기반 발췌 검색, 원문 페이지 버튼을 구현했습니다. PDF 리더는 탐색(페이지 썸네일/목차/주석), 확대/맞춤/검색, 읽기 색상, 주석 색상/현재 실행 중 생성한 주석 Undo/Redo, 너비 조절 질문 패널을 제공합니다. 로컬 unit/widget 40개 통과. 최종 정적 분석과 플랫폼 통합 검증/배포는 진행 중입니다. 실제 유료 생성 API 호출은 수행하지 않았습니다.

Canvas 수정 alpha.4 배포 완료: 사용자가 과목 목록은 조회되지만 가져오기에서 401이 발생한다고 보고. 기존 코드의 권한 오류/토큰 만료 오분류를 수정하고 파일 목록+모듈 탐색, 개별 권한 오류 건너뜀, 결과 보고를 추가했습니다. alpha.3 후보 CI는 실제 학교 LearningX 구조를 반영하기 위해 중단했습니다.

alpha.4 로컬 검증: unit/widget 전체 32개 통과, flutter analyze 오류/경고/info 없음. 새 테스트는 유효한 토큰의 Files 401/실제 인증 실패 구분, 비어 있거나 제한된 파일 목록에서 모듈 탐색/페이지네이션/중복 제거, 제한된 개별 다운로드와 과제 건너뜀, 로그인 HTML 거부, LearningX 서명 LTI 흐름/첨부파일/누락 다운로드 주소/신뢰하지 않는 출처 차단/비밀 외부 전송 방지를 포함합니다.

alpha.4 Actions 39601030713 전체 성공: Windows 포맷/분석/32개 테스트/문서 통합 테스트/release 빌드/설치형·Portable 패키징, Android 프로젝트 키 서명 APK/문서 통합 테스트/apksigner 검증, Release 게시 완료. 다운로드한 Windows 두 배포 파일 SHA256을 확인하고 dist/canvas-fix-alpha4/app/fenru.exe를 실행했으며 Fenru 창 응답 상태를 확인했습니다. 실제 GUI에서 과목 가져오기를 재시도한 사용자 결과는 아직 확인 전입니다.

실제 제주대 읽기 전용 진단: OS 보안 저장소의 Canvas 토큰을 메모리에서만 사용하고 값은 출력/파일 저장하지 않았습니다. 과목 13개 조회 200, 표본 3개 과목 파일 목록 401, 모듈/과제 200 확인. 자료가 LearningX ExternalTool로 게시되며 Canvas PAT와 별도 인증을 사용합니다. 공식 sessionless_launch → 같은 학교의 서명된 주차별 학습 LTI 인증 → LearningX 모듈 조회 → 첨부 파일 API/Commons XML 다운로드 정보 경로를 구현했습니다. 실제 Dart 어댑터로 첨부자료 과목 11개, PDF 과목 8개 다운로드 주소(추가 6개는 원본 저장소 다운로드 주소 없음)를 확인했고 PDF 1개 HTTP 200/%PDF-/295146 bytes 수신을 확인했습니다. 실험은 임시 진단 프로세스에서 수행했으며 사용자 작업 공간에 문서를 삽입하지 않았습니다. 영화/퀴즈/설문/출석 기록 완료 요청은 하지 않습니다. 최종 GUI 가져오기 확인은 빌드 후 필요합니다.

전체 요구사항 미완료. 로컬 학습 기능과 선택적 AI BYOK를 구현하고 Canvas/LearningX를 보완한 v0.1.0-alpha.4 개발 프리릴리스를 게시했습니다. 기능 코드 작성과 실행 검증을 구분합니다.

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
- 로컬 unit/widget 전체 25개 통과(쓰기 직렬화, 키 순서와 무관한 충돌, CDN 토큰 제거/HTTPS 제한, 안전한 파일명 포함). Windows 중복 실행 잠금 테스트를 추가하여 별도 1개도 통과.
- Android API 36.1 x86_64 에뮬레이터에서 온보딩 → PDF 가져오기 → 렌더 → 텍스트 선택 → 하이라이트/책갈피 → DB 재오픈 보존 시나리오 통과.
- GitHub Actions 39561512851: Windows 분석/16개 테스트/release 빌드/설치 프로그램과 Android release APK 빌드 성공.
- GitHub Actions 39564266923: AI 포함 20개 테스트와 Windows 실제 문서 통합 테스트 통과. 오래된 후보의 Android 실행은 최종 후보 검증으로 대체하여 중단.
- alpha.1 릴리스 실행은 Canvas CDN 보완을 포함하기 위해 중단. main 후속 실행에서 Visual Studio 18 CRT 디렉터리 구조 차이로 패키징 실패를 확인하여 재귀 탐색으로 수정.
- alpha.2 Actions 39568161638 전체 성공: 포맷·정적 분석·26개 unit/widget·Windows 문서 통합 테스트·Windows release 빌드/설치 프로그램/Portable 패키징·프로젝트 키 서명 Android release APK 빌드·Android API 35 문서 통합 테스트·apksigner 검증·프리릴리스 게시. 다운로드한 ZIP/설치 EXE의 SHA256이 배포 체크섬과 일치하고 Portable에 Visual C++ 런타임 DLL이 포함됨을 확인.
- 동일 CI의 배포 APK SHA256(4f833eb5…602d64)이 GitHub Release digest/체크섬과 일치함을 확인. Android API 35 800×1340 태블릿 에뮬레이터의 기존 Fenru 설치가 없는 상태에서 프로젝트 키 APK 설치 성공. 연결 없이 시작 → 홈 → 설정 → AI 키 입력 화면의 실제 렌더를 확인하고 docs/screenshots에 저장. 호스트 메모리 압박 중 Android System UI의 일시적 ANR이 나타났으므로 성능 검증 통과로 간주하지 않음.
- 태블릿 배포 앱을 강제 종료 후 다시 시작했을 때 온보딩을 반복하지 않고 홈으로 복원됨을 접근성 트리로 확인.
- Windows CI 배포본 실행·최초 온보딩 접근성 트리 확인. 컴퓨터 입력 도구가 SendInput 오류 87을 반환해 이를 수동 조작/시각 검증 성공으로 간주하지 않음. 위젯 테스트 렌더 6개를 별도로 생성·확인.
- 사용자가 Windows 앱 설정에서 Canvas 연결 완료를 보고. 비밀을 읽지 않고 URL 설정 저장/온보딩 완료만 확인. 아직 자료 가져오기 기록·객체는 없음.
- 사용자 승인 후 개발 환경 기존 키로 공식 OpenAI 모델 조회를 시도했으나 HTTP 401. 실제 생성 API 성공 미검증. 새 키는 앱 설정에 직접 입력하며 사용자는 아직 입력 전이라고 확인.
- DeepSeek·Google 실제 계정 연동 미검증. Android 실물 기기 미검증.
- 로컬 Windows 컴파일은 Visual C++ ATL(atlstr.h) 구성요소 부족으로 차단. CI Windows 빌드는 성공.

## 미구현
Google OAuth/Drive 객체 동기화, 임베딩 기반 의미 검색·전체 라이브러리 RAG,
OCR·PPTX/DOCX 본문 추출·PDF 암호 입력 UI,
PDF 텍스트 인덱싱, Canvas Pages/공지/Calendar와 자동 주기(Modules 파일/제주대 LearningX 문서는 지원),
Markdown 백링크·수식·이미지 삽입, Android Glance 위젯·공유 인텐트·알림,
Windows 트레이·파일 연결·창 위치, 영어 UI, Windows 코드 서명·MSIX.

## 알려진 제한
백업은 전체 ZIP을 메모리에 생성/해제하며 대용량에 적합하지 않습니다(1GB 한도).
현재 UI는 한국어입니다. 휴지통은 자료·노트·일정·주석을 표시하고 복구할 수 있습니다.
Canvas 다운로드는 HTTPS 리다이렉트를 처리하고 외부 호스트 토큰 제거·크기 검증·안전한 내부 파일명을 적용합니다. 실제 학교 파일 가져오기는 추가 검증이 필요합니다. 부분 가져오기는 유지합니다.
파일 변경 버전은 별도 문서로 보관하며 이전 주석을 신규 PDF 좌표로 자동 이전하지 않습니다.

## 다음 작업
1. 사용자 환경 피드백과 실물 기기/설치 프로그램 실행 검증.
2. 새 API 키로 실제 AI 생성/출처 이동, Canvas 실제 자료 가져오기 검증.
3. Drive OAuth와 객체 동기화, PDF 텍스트 인덱싱/RAG.
4. 플랫폼 위젯/트레이/알림, 번역, 큰 글꼴·실물 기기·성능 검증.

## 사용자/배포 자원 필요
- 로컬 빌드에 충분한 디스크 공간(최소 12GB 권장).
- 실제 연동 검증에 유효한 사용자 API 키. Canvas 계정은 사용자가 앱에 연결함.
- 배포용 Google OAuth 프로젝트/client ID와 Android SHA 등록.
- Android 프로젝트 키는 생성/Secrets 보관 완료. 별도 안전한 키 백업과 선택적 Windows 서명 인증서 필요.

## 산출물
- [최신 v0.1.0-alpha.4 프리릴리스](https://github.com/vividhyeok/fenru/releases/tag/v0.1.0-alpha.4)
- [최신 Windows 설치 프로그램](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.4/Fenru-Windows-x64-Setup.exe)
- [최신 Windows Portable ZIP](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.4/Fenru-Windows-x64-portable.zip)
- [최신 Android 프로젝트 키 서명 APK](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.4/Fenru-Android-release.apk)
- [최신 Actions 검증](https://github.com/vividhyeok/fenru/actions/runs/39601030713)

이전 검증/배포 기록:
- [v0.1.0-alpha.2 프리릴리스](https://github.com/vividhyeok/fenru/releases/tag/v0.1.0-alpha.2)
- [Windows 설치 프로그램](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.2/Fenru-Windows-x64-Setup.exe)
- [Windows Portable ZIP](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.2/Fenru-Windows-x64-portable.zip)
- [Android 프로젝트 키 서명 APK](https://github.com/vividhyeok/fenru/releases/download/v0.1.0-alpha.2/Fenru-Android-release.apk)
- [최종 Actions 검증](https://github.com/vividhyeok/fenru/actions/runs/39568161638)
