# 구현 및 검증 현황

최종 갱신: 2026-10-22 (Asia/Seoul)

## 상태
alpha.7 배포 완료: 채팅 세로 공간 정리·패널 집중 보기·대화 기록/초안·저장 완료/노트 열기·출처 연계, PDF 자유 필기/형광펜/밑줄과 별도 자동 저장 정리 노트, 설치된 변환 프로그램을 통한 Office/한글 PDF 변환, Canvas 페이지/게시판/공지/답글/과제 첨부 탐색을 추가했습니다. 로컬 unit/widget 47개 통과. Windows Word/PowerPoint의 작성한 DOCX/PPTX 변환은 확인했으며 HWP/HWPX/LibreOffice 실제 변환은 미검증입니다. Android는 변환 엔진을 제공하지 않습니다. 실제 Canvas 새 탐색에서 표본 과목 한 개의 문서 12개(주차 8/공지 2/과제 2)를 읽기 전용으로 발견했습니다. 실제 자료 가져오기는 하지 않았습니다. alpha.6 후보의 네이티브 검증은 펜 저장 이후 하이라이트 메뉴 선택 대상을 혼동하여 실패했으며 테스트 선택자를 수정했습니다. alpha.6은 Release로 게시하지 않았습니다. Actions 39712689175 전체 성공: 포맷·분석·47개 테스트, Windows/Android PDF 펜 입력·텍스트 주석·Undo/Redo·정리 노트 자동 저장·재오픈 보존 통합 검증, Windows release/설치형/Portable 및 Android 프로젝트 서명 release APK/서명 확인, Release 게시를 통과했습니다. Windows 설치형과 Portable 배포 파일 SHA256 일치를 확인하고 실제 Windows 통합 테스트 PDF 렌더의 필기 위치를 시각 확인했습니다. 로컬 Windows 컴파일/수동 앱 실행 성공을 주장하지 않습니다.

alpha.5 배포 완료: 사용자의 요청에 따라 독립 AI 메뉴/상단 일반 대화 진입을 제거하고 과목·자료에 질문을 통합했습니다. 과목별 자료 목록/질문 패널, 자료 전체/현재 페이지/선택 문장, 범위별 대화 저장, PDF/텍스트 본문 버전 캐시와 키워드 기반 발췌 검색, 원문 페이지 버튼을 구현했습니다. PDF 리더는 탐색(페이지 썸네일/목차/주석), 확대/맞춤/검색, 읽기 색상, 주석 색상/현재 실행 중 생성한 주석 Undo/Redo, 너비 조절 질문 패널을 제공합니다. 로컬/CI unit/widget 40개와 정적 분석, Windows/Android 문서 통합 테스트, 두 플랫폼 release 빌드/패키징 및 Android 서명 검증을 통과했습니다. Actions 39614048408에서 alpha.5를 게시했습니다. Windows 설치형/Portable 배포 파일의 SHA256 일치를 확인했습니다. 실제 유료 생성 API 호출은 수행하지 않았습니다.

Canvas 수정 alpha.4 배포 완료: 사용자가 과목 목록은 조회되지만 가져오기에서 401이 발생한다고 보고. 기존 코드의 권한 오류/토큰 만료 오분류를 수정하고 파일 목록+모듈 탐색, 개별 권한 오류 건너뜀, 결과 보고를 추가했습니다. alpha.3 후보 CI는 실제 학교 LearningX 구조를 반영하기 위해 중단했습니다.

alpha.4 로컬 검증: unit/widget 전체 32개 통과, flutter analyze 오류/경고/info 없음. 새 테스트는 유효한 토큰의 Files 401/실제 인증 실패 구분, 비어 있거나 제한된 파일 목록에서 모듈 탐색/페이지네이션/중복 제거, 제한된 개별 다운로드와 과제 건너뜀, 로그인 HTML 거부, LearningX 서명 LTI 흐름/첨부파일/누락 다운로드 주소/신뢰하지 않는 출처 차단/비밀 외부 전송 방지를 포함합니다.

alpha.4 Actions 39601030713 전체 성공: Windows 포맷/분석/32개 테스트/문서 통합 테스트/release 빌드/설치형·Portable 패키징, Android 프로젝트 키 서명 APK/문서 통합 테스트/apksigner 검증, Release 게시 완료. 다운로드한 Windows 두 배포 파일 SHA256을 확인하고 dist/canvas-fix-alpha4/app/fenru.exe를 실행했으며 Fenru 창 응답 상태를 확인했습니다. 실제 GUI에서 과목 가져오기를 재시도한 사용자 결과는 아직 확인 전입니다.

실제 제주대 읽기 전용 진단: OS 보안 저장소의 Canvas 토큰을 메모리에서만 사용하고 값은 출력/파일 저장하지 않았습니다. 과목 13개 조회 200, 표본 3개 과목 파일 목록 401, 모듈/과제 200 확인. 자료가 LearningX ExternalTool로 게시되며 Canvas PAT와 별도 인증을 사용합니다. 공식 sessionless_launch → 같은 학교의 서명된 주차별 학습 LTI 인증 → LearningX 모듈 조회 → 첨부 파일 API/Commons XML 다운로드 정보 경로를 구현했습니다. 실제 Dart 어댑터로 첨부자료 과목 11개, PDF 과목 8개 다운로드 주소(추가 6개는 원본 저장소 다운로드 주소 없음)를 확인했고 PDF 1개 HTTP 200/%PDF-/295146 bytes 수신을 확인했습니다. 실험은 임시 진단 프로세스에서 수행했으며 사용자 작업 공간에 문서를 삽입하지 않았습니다. 영화/퀴즈/설문/출석 기록 완료 요청은 하지 않습니다. 최종 GUI 가져오기 확인은 빌드 후 필요합니다.

전체 요구사항 미완료. 로컬 학습 기능과 선택적 AI BYOK를 구현하고 Canvas/LearningX를 보완한 v0.1.0-alpha.5 개발 프리릴리스를 게시했습니다. 기능 코드 작성과 실행 검증을 구분합니다.

## 코드 작성
- Flutter 앱, 반응형 내비게이션, 디자인 토큰, 한 화면 빠른 연결 (사용하지 않던 Riverpod/go_router 제거)
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


## 2026-11-04 로컬 개선 작업

- 안내 5단계를 한 화면의 실제 Canvas/AI 연결로 교체하고 시작하기에서 저장. 기존 제공자/모델/주소 재사용, 사용 한도는 접이식 고급 설정.
- 과목 화면에서 여러 파일 직접 추가. 폴더 간 동일 파일이 기존 과목에서 이동하지 않도록 중복 기준 보완.
- PDF 전문/현재 페이지/선택 문장/지정 페이지/관련 검색 구분. 전문은 발췌 제한 없이 읽을 수 있는 모든 페이지를 포함. 300,000자 및 사용자 토큰 한도 초과는 명시적 오류. OCR은 미제공.
- 획 지우개와 삭제 실행 취소/다시 실행, 보조 펜 버튼 이벤트 처리. 실물 Galaxy S펜은 미검증.
- 종이색/녹색 테마와 사각 버튼·내비게이션으로 정리. 새 폰트나 이미지 자산 추가 없음. 필기 입력 좌표 누적 시 전체 목록 복사를 제거.
- 직접 의존성 2개와 전이 의존성 3개 제거. 배포 용량/메모리/처리 속도 개선율은 아직 측정하지 않았으므로 수치로 주장하지 않음.

- 동기화 대상 과목 저장 및 기존 과목 자동 승계, 정상 동기화 완료 모달 제거. 공지/페이지/게시판/답글/과제 본문과 제공되는 강의계획을 과목 문서로 저장하고 변경 없는 본문은 재저장하지 않음. 시험 질문은 시험 안내와 관련 강의자료를 함께 검색하며 확정 정보와 학습 제안을 구분하도록 지시.
- [필기 조작 벤치마킹](INTERACTION_BENCHMARK.md): Xodo/Samsung Notes/Goodnotes 공식 문서 참고. 펜 필기와 손가락 탐색 분리, 고정 도구줄, 필기 중 버튼 전환과 지우개 삭제 미리보기.

- 최종 검증: 정적 분석 문제 없음, unit/widget 55개 통과. 390/768/1366 크기 라이트/다크 레이아웃 검증 및 데스크톱·모바일 테스트 렌더 시각 확인. Android arm64 release APK 31,320,152바이트(Flutter 표시 29.9MB) 빌드 성공. 로컬 기본 debug 인증서 서명으로 기존 프로젝트 서명 배포판의 업데이트용이 아님. Windows 빌드는 설치된 Visual C++에 ATL 헤더 atlstr.h가 없어 실패. 실제 기기/학교 전체 동기화/실제 생성 API 답변은 이번에 실행하지 않았음.


### Galaxy Tab S7 업데이트용 프로젝트 서명 APK

사용자 요청에 따라 기존 프로젝트 키를 재사용해 `0.1.0-alpha.8+8`로 빌드했습니다. 공개 alpha.7 인증서와 새 APK의 SHA-256 인증서 지문 일치를 검증하며, 앱 ID는 `com.vividhyeok.fenru`를 유지합니다. arm64 단일 APK(ABI 분할 versionCode 가산 없음), 31,524,493바이트. 결과는 `dist/android-update/Fenru-Android-release.apk`. 기존 프로젝트 서명 설치본에 `adb install -r`로 데이터를 유지하며 업데이트할 수 있습니다. 태블릿은 아직 페어링되지 않았으므로 실제 설치/설정 유지 확인은 연결 후 필요합니다. [Wi-Fi 연결 안내](GALAXY_TAB_WIFI_UPDATE.md)와 반복 빌드 스크립트 `tools/build_android_release.ps1`을 추가했습니다.


실물 Galaxy Tab S7(SM-T870) Wi-Fi ADB 페어링 후 설치된 alpha.7의 APK v2 서명 블록에서 인증서 SHA-256을 읽어 프로젝트 배포 서명과 일치함을 확인했습니다. `adb install -r`로 alpha.8 업데이트 성공. 기존 앱 UID와 최초 설치 시간이 유지됐으며, 앱 실행 후 온보딩을 다시 거치지 않고 기존 홈에서 자료 35개·노트 11개·남은 할 일 40개와 읽던 페이지가 표시되는 것을 확인했습니다. API 키 값은 읽거나 출력하지 않았으며 실제 AI 요청은 실행하지 않았습니다. 실물 S펜의 필기/버튼 동작은 아직 별도 확인이 필요합니다.


## alpha.9 읽기 편의성 개선

- PDF의 출처/책갈피/목차/페이지 탐색/검색 결과 이동 전 위치와 확대 상태를 30개까지 기억하고 복귀.
- 도구·색상·굵기 펜 즐겨찾기 3개, 길게 눌러 현재 설정 저장.
- 문서별 중심 위치·확대율·맞춤 방식·질문 패널 너비/표시 상태 보관.
- 질문 입력창 가까이에 현재 참조 모드·페이지 번호·지정 범위를 상시 표시하고 눌러 변경.
- 동기화 자료에 수정본별 수신 표시를 붙여 과목에서 새 자료 필터와 읽음 처리를 제공. 동일 내용은 기존 확인 상태 유지. 기존 자료의 읽음 여부는 추측하지 않음.
- 새 외부 의존성 없음. OCR/녹음 등 조사 목록의 별도 대형 기능은 이번 변경에 포함하지 않음.


alpha.9 검증: 정적 분석 문제 없음, unit/widget 60개 통과. 문서별 보기 저장/잘못된 설정 복구·펜 즐겨찾기 저장·동기화 수정본 읽음 상태·새 자료 필터·참조 페이지 표시 갱신을 추가 검증했습니다. 320px 질문 패널에서 입력 안내 문구 줄바꿈 때문에 답변 영역이 줄어드는 문제를 수정했고, 기존 답변 공간 회귀 테스트를 유지한 채 통과했습니다. 질문 패널 테스트 렌더를 시각 확인했습니다. 현재 실물 태블릿의 Wi-Fi ADB 주소에 연결할 수 없어 새 버전의 실기기 동작은 아직 확인하지 않았습니다.

alpha.9 프로젝트 배포 서명 APK 빌드 및 기존 인증서 일치 검증 완료. versionCode 9, 31,525,049바이트, 결과 `dist/android-update/Fenru-Android-release.apk`. 태블릿 연결 불가로 실제 설치는 수행하지 않았습니다.

실물 Galaxy Tab S7에 Wi-Fi ADB로 alpha.8 → alpha.9 `install -r` 업데이트 성공. 앱 UID와 최초 설치 시간이 유지됐고 alpha.9 실행 후 기존 홈에서 자료 35개·노트 12개·남은 할 일 40개가 표시되는 것을 확인했습니다. 신규 편의 기능 각각의 실물 펜/터치 조작은 별도 확인 대상입니다.


## alpha.10 필기 화면 단순화

- PDF 진입 시 펜을 기본 선택. S펜 주 버튼(기존 누락)과 보조 버튼을 모두 누르는 동안 획 지우개로 처리하며 놓으면 이전 필기 도구로 복귀.
- 두 줄 도구를 PDF 영역 내부 48px 한 줄로 축소하고, AI는 제목 아래부터 사용. 선택한 펜/형광펜 다시 누르면 색상·굵기·즐겨찾기를 표시.
- 페이지 번호 메뉴에서 검색·탐색·확대·맞춤·책갈피·메모·정리 노트를 사용. 손가락 입력과 읽기 배경은 설정으로 이동.
- 집중 필기 모드는 제목·도구·탐색·AI를 숨기고 복귀 버튼만 표시.
- 정적 분석 문제 없음, unit/widget 테스트 64개 통과. 두 종류의 펜 버튼 전환과 320/600/900px 필기 도구줄 회귀 테스트 포함. 실제 PDF를 띄운 Windows 위젯 테스트는 네이티브 렌더링이 종료되지 않아 검증으로 계산하지 않았으며 테스트 파일을 제거. 기존 Windows 앱 통합 검증은 ATL 헤더 부족 제약 유지.
- 새 외부 의존성 추가 없음. OCR·녹음/전사는 이 변경에 포함하지 않음.
