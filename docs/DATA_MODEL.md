# 데이터 모델 v1

objects: id(UUID 또는 결정적 충돌 해시), kind(document/note/annotation/course/task), payload(JSON), revision, device, updated(UTC), deleted(tombstone).

공통 payload의 _clock은 device → counter 벡터 시계입니다. title은 표시 이름입니다. document는 file(작업 공간 상대 경로), hash(SHA256), size, extension, originalName, folder, tags, page, lastRead, origin(선택적 Canvas 원본 ID), previousVersion을 가집니다. note는 body와 documentId를 가집니다. annotation은 documentId/page/type/body를 가집니다. task는 due/done/course/source/url을 가집니다.

preferences: 기기 전용 문자열 설정. 비밀 토큰은 포함하지 않습니다. outbox: 객체 ID와 대기 revision, attempts/next_attempt/error 필드. 큐 생성은 구현되어 있지만 클라우드 처리기는 없습니다. search_index: FTS5 title/body와 ID, unicode61 tokenizer. 저장/삭제 시 증분 갱신합니다.

schemaVersion=1. 새 버전 변경에는 onUpgrade와 이전 실제 DB 파일을 이용한 마이그레이션 테스트가 필요합니다. v1 생성·재오픈 테스트와 버전 간 마이그레이션 테스트는 서로 다릅니다. 후자는 아직 없습니다.
