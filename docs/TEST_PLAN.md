# 검증 계획과 증거

자동 테스트: 노트 저장/FTS/휴지통/복구, 가져오기 복사/중복/페이지, DB 종료/재오픈, 백업 두 기기 동시 편집·멱등, Canvas URL 검증, 로컬 전용 온보딩 위젯. 테스트 파일을 작성한 사실과 테스트 성공은 다릅니다. 결과는 IMPLEMENTATION_STATUS.md 및 Actions에서 확인하세요.

추가 필수: 악성 ZIP 경로·체크섬·압축 폭탄·부분 쓰기 실패, Canvas 페이지네이션/401/403/429 mock, 동시 삭제/수정, v1→v2 마이그레이션, 노트 저장 실패 후 재시도, PDF 렌더/선택/주석 재실행, 좁은 화면/다크/큰 글꼴/수천 자료 성능.

실제 기기 시나리오: Windows 최초 실행→가져오기→PDF→노트→재실행, Android 동일 흐름, ZIP 이동 및 동시 편집, 실제 Canvas, 최종 AI/Drive 계정 연결, 위젯/공유/알림. 미구현 기능은 시나리오 통과로 표시하지 않습니다.

integration_test/local_flow_test.dart는 실제 앱 최초 진입 smoke test입니다. CI에서 현재 unit/widget만 실행하며 플랫폼 integration test 실행은 추가해야 합니다.
