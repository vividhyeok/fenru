# Canvas 연결

학교 Canvas → 계정 → 설정 → 새 액세스 토큰을 발급합니다. Fenru 설정의 연결에서 https://school.instructure.com 같은 기본 URL과 개인 토큰을 입력합니다. 연결 테스트 성공 후 OS 보안 저장소에 토큰을 보관합니다. 비밀번호는 수집하지 않습니다.

과목 → Canvas 자료 가져오기 → 과목 선택으로 파일과 과제를 가져옵니다. alpha.3부터 파일 목록과 주차별 모듈의 File 항목을 모두 확인합니다. 파일 목록이 비었거나 학교가 숨겼어도 모듈 항목을 개별 페이지네이션하고 파일 ID로 중복 제거합니다. 파일 메타데이터도 제한되면 해당 파일의 공개 다운로드 경로를 시도하며, 서버가 거부하는 파일은 건너뜁니다. 접근 권한을 우회하지 않습니다. Files updated_at과 외부 ID를 비교해 재다운로드를 줄입니다. 수정 자료는 별도 문서/previousVersion으로 보존하며 이전 주석을 삭제하지 않습니다. 메타데이터를 읽을 수 없는 모듈 파일의 변경 감지는 제한됩니다.

과목 목록 조회에 성공했다면 그 시점의 토큰 인증은 통과한 것입니다. 이후 파일 목록의 HTTP 401은 접근 제한일 수도 있으므로, 이미 성공한 과목 API를 재확인해 인증 실패와 구분합니다. 제한된 파일/과제 때문에 전체 가져오기를 중단하지 않고 저장 수·기존 파일 수·과제 수·건너뜀·경고를 결과 화면과 설정에 표시합니다. 제주대는 https://canvas.jejunu.ac.kr 기본 주소를 사용하며 SSO 로그인 페이지의 jnuclass 주소로 바꾸지 않습니다. 사용자의 실제 학교 자료 가져오기 성공은 아직 확인 전입니다.

페이지네이션은 Link rel=next를 따라 동일 출처에서만 수행합니다. 429는 Retry-After/제한된 지수 대기로 재시도합니다. 401/403/404/연결 실패는 사용자 메시지로 구분합니다. 파일 다운로드는 HTTPS 리다이렉트를 최대 6단계 처리하고 학교 외부 호스트에는 Canvas Bearer를 보내지 않습니다. HTTP 다운그레이드·인증정보 URL·반복 경로는 거부하고 파일 크기를 API와 비교합니다. 로그인 HTML을 파일로 잘못 저장하지 않도록 검사합니다. Windows에서 허용되지 않는 원본 파일명도 메타데이터로 보존하며 내부 파일은 UUID로 저장합니다. 모듈의 Pages/외부 LTI 자료·공지·달력과 자동 주기는 미지원입니다. 제출/성적 쓰기 요청은 하지 않습니다.

참고 조사: [Obsidian Canvas Sync](https://github.com/SixFiveMil/obsidian-canvas-sync/blob/main/src/api/canvas-client.ts)는 모듈별 파일 ID 발견/파일 목록 병합과 접근 기능 진단을 사용합니다. [CanvasSync](https://github.com/perslev/CanvasSync/blob/master/CanvasSync/entities/module.py)는 모듈 항목에서 File을 찾은 뒤 파일 정보를 조회합니다. 이 흐름과 공식 REST 규격을 참고하여 Dart로 작성했으며 소스 코드를 복사하지 않았습니다. GPAI 공개 사이트에서는 Canvas 가져오기 내부 구현을 확인하지 못했습니다.

공식 API: https://developerdocs.instructure.com/services/canvas

## 제주대 LearningX (alpha.4)

실제 진단에서 Canvas 과목 목록은 정상(13개)인데 Files 목록은 401이고, 주차별 자료는 ExternalTool로 제공됨을 확인했습니다. 이 경우 Canvas 토큰만 LearningX API에 그대로 보내면 실패합니다. 앱은 공식 Canvas sessionless_launch로 학교의 주차별 학습(modulebuilder) LTI 인증 양식을 받아 같은 학교 주소에만 제출하고, 발급된 LearningX 단기 토큰을 메모리에서 사용합니다. 추가 학교 비밀번호 입력은 필요하지 않습니다. 강의 항목 뷰어, 영상 재생, 퀴즈·설문 응답, 출석 완료 API는 호출하지 않습니다.

LearningX attachment는 Canvas의 단일 파일 API로, Commons PDF/문서는 common.jejunu.ac.kr의 content.php XML에 있는 원본 다운로드 주소로 가져옵니다. 정확한 학교/Commons 출처를 검증하며 Canvas/LearningX 토큰과 학교 쿠키를 Commons에 전송하지 않습니다. 출처가 명확한 기존 HTTP Commons 링크는 HTTPS로 올려 요청합니다. 다른 학교의 Commons 주소는 별도 검증 후 지원해야 합니다. 일부 과거 자료는 view_url이 없어 content_id로 조회하며, 저장소에서 원본 다운로드 주소를 주지 않으면 경고에 남깁니다. 실제 파일을 다운로드하면 학교 서버의 접속 기록은 남을 수 있습니다.

추가 참고: [Canvas 공식 sessionless launch](https://developerdocs.instructure.com/services/canvas/resources/external_tools), [LearningX/Commons 자료 처리 사례](https://github.com/ghdtjdwn/ssuMCP/blob/main/docs/adr/0033-lms-material-zip-export.md), [LearningX 인증과 조회 사례](https://github.com/cwon-z/skku-icampus-mcp/blob/main/docs/icampus-notes.md). 공개 인터페이스 흐름을 참고했으며 소스 코드를 복사하지 않았습니다.
