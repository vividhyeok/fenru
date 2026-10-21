# Google Drive

현재 버전은 Drive OAuth 또는 자동 동기화를 제공하지 않습니다. 설정 화면에도 미지원이라고 표시합니다. ZIP 백업과 병합 복원으로 자료를 옮길 수 있습니다.

배포 구현 전 운영자가 Google Cloud OAuth 동의 화면/공개 client ID를 등록하고 Android 패키지 com.vividhyeok.fenru 및 SHA를 등록해야 합니다. 공개 앱에 client secret을 포함해서는 안 됩니다. 데스크톱 loopback/PKCE와 Android용 인증을 각각 검증하고 최소 drive.file/필요한 appdata 범위를 사용해야 합니다. 사용자가 각자 OAuth 앱을 생성하게 하는 구성을 기본값으로 삼지 않습니다.

현재 사용자에게 Google 비밀번호나 토큰을 요구하지 않습니다. 실제 두 기기 동기화는 미검증입니다.
