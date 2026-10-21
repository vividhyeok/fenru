# 아키텍처

현재 구조는 단일 Flutter 앱, 플랫폼별 공식 러너, Drift SQLite, 로컬 파일 저장소입니다. 별도 계정 서버나 중앙 DB를 운영하지 않습니다.

lib/core: DB·객체 모델·Workspace 저장/검색. lib/features: PDF Reader와 ZIP 백업. lib/integrations: Canvas 및 CredentialStore. lib/ui: 반응형 shell·온보딩·노트.

Presentation → Workspace → Drift/파일 구조입니다. Riverpod으로 워크스페이스 인스턴스를 주입하고 go_router로 최초 진입을 라우팅합니다. 세부 문서는 Navigator 화면으로 열립니다. 현 단계에서 별도 유스케이스 클래스를 남발하지 않았습니다. Workspace가 커지면 기능별 repository로 분리해야 합니다.

## ADR-001 — Flutter 안정 버전 고정
2026-10-21 공식 배포 목록을 확인하고 Flutter 3.47.7/Dart 3.13.5를 선택했습니다. Windows/Android 공식 러너를 tools/bootstrap.py로 생성합니다. CI가 생성 소스와 lockfile을 artifact로 보존합니다. 초기 플랫폼 소스 확정 후 생성 러너를 저장소에 포함시키는 것이 다음 단계입니다.

## ADR-002 — 명시적 Drift SQL
초기 데이터 모델은 UUID 객체와 JSON payload로 관리합니다. 메타데이터와 FTS 인덱스·outbox는 같은 트랜잭션에서 저장됩니다. 생성 코드 없이 명시적 SQL로 스키마를 검토할 수 있습니다. 도메인별 제약과 대규모 쿼리를 강화하기 위해 추후 정규화 마이그레이션이 필요합니다.

## ADR-003 — 원본 비파괴
자료는 UUID 파일명으로 복사합니다. 사용자 표시 이름은 별도 메타데이터이며 이름 변경이 주석 연결을 끊지 않습니다. PDF 주석은 원본 파일과 별도 객체입니다. 삭제는 tombstone입니다.

## ADR-004 — 수동 이동을 먼저 검증
클라우드 OAuth 배포 설정이 없는 상태에서 연결 성공을 가장하지 않습니다. ZIP 백업과 병합을 먼저 구현했습니다. Drive 객체 동기화는 미구현이며 전체 SQLite 파일 업로드로 대체하지 않습니다.
