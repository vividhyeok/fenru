# 빌드와 릴리스

GitHub Actions Verify and build는 main/PR에서 Windows 분석·테스트·release 빌드 후 Android release APK를 검증합니다. tools/bootstrap.py가 고정 Flutter SDK에서 플랫폼 러너를 생성합니다. source-verified artifact로 생성 러너·lockfile·format 결과를 보관합니다.

v* 태그에서 두 플랫폼 검증이 모두 성공하면 GITHUB_TOKEN(contents:write)으로 개발 prerelease를 생성합니다. Windows portable ZIP, Android test-signed APK, SHA256 체크섬을 업로드합니다. 실패한 빌드를 정식 릴리스로 생성하지 않습니다.

Android 현재 기본 러너는 debug/test 키를 release 빌드에 사용합니다. 이것은 정식 서명 설정이 아닙니다. 정식 배포 전 업로드 키를 GitHub Secrets(base64 keystore/store password/key alias/key password)로 주입하고 Gradle release signingConfig에 연결해야 합니다. 키를 소스/산출물에 포함하지 마세요. Windows도 서명되지 않습니다. 설치형 EXE/MSIX는 아직 없습니다.

업데이트 전 ZIP 백업을 수행하세요. Windows 실행 파일과 작업 공간은 분리되어 있습니다. Android 동일 서명 업데이트는 데이터를 보존하지만 다른 키로 설치하면 업데이트가 거부됩니다. 테스트 키는 장기 배포에 사용하지 마세요.

실제 릴리스 URL과 검증 결과는 생성 후 IMPLEMENTATION_STATUS.md에 기록합니다.
