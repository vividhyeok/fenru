# Canvas 연결

학교 Canvas → 계정 → 설정 → 새 액세스 토큰을 발급합니다. Fenru 설정의 연결에서 https://school.instructure.com 같은 기본 URL과 개인 토큰을 입력합니다. 연결 테스트 성공 후 OS 보안 저장소에 토큰을 보관합니다. 비밀번호는 수집하지 않습니다.

과목 → Canvas 자료 가져오기 → 과목 선택으로 파일과 과제를 가져옵니다. Files updated_at과 외부 ID를 비교해 재다운로드를 줄입니다. 수정 자료는 별도 문서/previousVersion으로 보존하며 이전 주석을 삭제하지 않습니다. 실제 계정은 검증하지 않았습니다.

페이지네이션은 Link rel=next를 따라 동일 출처에서만 수행합니다. 429는 Retry-After/제한된 지수 대기로 재시도합니다. 401/403/404/연결 실패는 사용자 메시지로 구분합니다. 파일 다운로드는 HTTPS 리다이렉트를 최대 6단계 처리하고 학교 외부 호스트에는 Canvas Bearer를 보내지 않습니다. HTTP 다운그레이드·인증정보 URL·반복 경로는 거부하고 파일 크기를 API와 비교합니다. Windows에서 허용되지 않는 원본 파일명도 메타데이터로 보존하며 내부 파일은 UUID로 저장합니다. Modules/Pages/공지/달력과 자동 주기는 미지원입니다. 제출/성적 쓰기 요청은 하지 않습니다.

공식 API: https://developerdocs.instructure.com/services/canvas
