# Galaxy Tab S7: Wi-Fi 연결과 데이터 유지 업데이트

Android 11 이상에서 PC와 태블릿을 같은 Wi-Fi에 연결합니다. PC의 ADB는 이미 `C:/Users/user/AppData/Local/Android/sdk/platform-tools/adb.exe`에 준비되어 있습니다.

1. 태블릿 설정 → 태블릿 정보 → 소프트웨어 정보 → 빌드번호를 7번 눌러 개발자 옵션을 활성화합니다.
2. 설정 → 개발자 옵션 → 무선 디버깅을 켜고 해당 네트워크에서 허용합니다.
3. 무선 디버깅 기본 화면의 **IP 주소 및 포트**를 기록합니다. 이것이 연결 주소입니다.
4. **페어링 코드로 기기 페어링**을 눌러 별도의 IP:포트와 6자리 코드를 확인합니다. 이 창을 열어둔 채 페어링합니다.

PowerShell 예시에서 주소는 태블릿에 표시된 실제 값으로 바꿉니다. 페어링용 포트와 연결용 포트는 서로 다를 수 있습니다.

```powershell
$adb = 'C:\Users\user\AppData\Local\Android\sdk\platform-tools\adb.exe'
& $adb pair '태블릿IP:페어링포트'
# 요청하면 태블릿의 6자리 코드 입력
& $adb connect '태블릿IP:연결포트'
& $adb devices
& $adb -s '태블릿IP:연결포트' install -r 'C:\Users\user\Documents\ChatGPT\fenru\dist\android-update\Fenru-Android-release.apk'
```

`install -r`은 기존 앱의 데이터를 유지하면서 교체합니다. 기존 앱을 삭제하거나 앱 데이터 지우기를 실행하지 않습니다. 설치에 실패해도 삭제 후 재설치로 우회하지 말고 오류를 확인합니다.

이번 업데이트는 앱 ID `com.vividhyeok.fenru`, 버전 `0.1.0-alpha.10`/versionCode `9`, 기존 프로젝트 배포 인증서를 사용합니다. alpha.7 공개 서명과 비교하여 인증서 SHA-256 `b2f9b21cb92f4c424d942a722986ec5b9c76c981154a7355b713b155025c629a`를 확인합니다. 로컬 자료·설정·API 키 저장 방식은 바꾸지 않습니다. 기기에 설치된 앱도 같은 프로젝트 배포 서명일 때 업데이트가 가능합니다.

다음 업데이트 빌드는 프로젝트 루트에서 `./tools/build_android_release.ps1`을 실행합니다. 기존 프로젝트 키를 재사용하며 인증서가 다르면 업데이트 파일 내보내기를 중단합니다. 비밀번호는 Windows DPAPI에서 메모리로만 풀고 빌드 종료 시 프로세스 환경변수를 원래대로 복구합니다.

공식 안내: [Android Wi-Fi ADB](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi), [앱 서명과 업데이트](https://developer.android.com/studio/publish/app-signing), [Samsung 개발자 옵션](https://www.samsung.com/us/support/answer/ANS10003430/).
