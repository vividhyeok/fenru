# 빌드와 릴리스

GitHub Actions Verify and build는 main/PR에서 포맷·Windows 분석·unit/widget·Windows 문서 통합 테스트·release 빌드 후 Android release APK와 에뮬레이터 문서 통합 테스트를 검증합니다. Linux 에뮬레이터에는 KVM 권한을 준비합니다. tools/bootstrap.py가 고정 Flutter SDK에서 플랫폼 러너를 생성하며 기존 러너는 보존합니다. source-verified artifact로 러너·lockfile을 보관합니다. 테스트 화면은 ui-screenshots artifact로 분리하여 릴리스 파일에 폴더가 섞이지 않게 합니다.

v* 태그에서 두 플랫폼 검증이 모두 성공하면 GITHUB_TOKEN(contents:write)으로 개발 prerelease를 생성합니다. Windows portable ZIP, Android test-signed APK, SHA256 체크섬을 업로드합니다. 실패한 빌드를 정식 릴리스로 생성하지 않습니다.

프로젝트 Android RSA 4096 서명 키를 생성하고 GitHub Secrets(FENRU_KEYSTORE_B64/FENRU_STORE_PASSWORD/FENRU_KEY_ALIAS/FENRU_KEY_PASSWORD)에 보관했습니다. 비공개 로컬 사본은 tools/local/fenru-release.jks, 비밀번호는 동일 Windows 사용자만 복호화 가능한 signing-password.dpapi에 보관합니다. 이 디렉터리는 Git에서 제외됩니다. 기존 키는 생성 스크립트가 덮어쓰지 않습니다. 장기 보관과 복구용 별도 안전한 백업을 유지하세요. 키와 비밀번호가 모두 유실되면 같은 앱 서명 업데이트가 불가능할 수 있습니다.

CI는 PR에 서명 Secrets를 제공하지 않습니다. main/태그 빌드는 임시 경로에서 키를 복원해 서명한 뒤 런타임 테스트 전에 지웁니다. apksigner 검증 결과와 공개 인증서 지문을 artifact로 제공합니다. Secrets가 없는 빌드는 test-signed.apk라는 이름으로 명확히 구분합니다. GitHub 서명 키는 Play 배포 계정 등록이나 Google OAuth SHA 등록을 대신하지 않습니다.

Windows는 Portable ZIP과 Inno Setup 설치 프로그램을 제공합니다. 서명 인증서가 없어 Windows EXE는 서명되지 않았습니다. CI 패키징에 Visual C++ 재배포 런타임 DLL을 포함합니다. MSIX는 없습니다.

업데이트 전 ZIP 백업을 수행하세요. Windows 실행 파일과 작업 공간은 분리되어 있습니다. Android 동일 서명 업데이트는 데이터를 보존하지만 다른 키로 설치하면 업데이트가 거부됩니다. 테스트 키는 장기 배포에 사용하지 마세요.

실제 릴리스 URL과 검증 결과는 생성 후 IMPLEMENTATION_STATUS.md에 기록합니다.
