# 오픈소스 검토 (2026-10-21)

직접 의존성 버전은 pub.dev API, 후보 저장소의 라이선스/최근 push는 GitHub API로 확인했습니다. 실제 호환성은 dependency resolution 및 플랫폼 빌드 결과로 확인합니다. 라이선스 파일은 배포 시 Flutter 라이선스 레지스트리와 원본 패키지를 기준으로 확인하세요.

| 기술 | 목적 | 라이선스 | 플랫폼/선택 |
|---|---|---|---|
| Flutter/Dart | 앱과 런타임 | BSD-3-Clause | Windows/Android, 채택 |
| Riverpod | 의존성 주입 | MIT | Dart/Flutter, 채택 |
| go_router | 최초 진입 라우팅 | BSD-3-Clause | Flutter, 채택 |
| Drift/sqlite3 | 영구 저장/FTS | MIT | Windows/Android, 채택 |
| pdfrx/PDFium | PDF 렌더와 선택 | MIT / PDFium BSD 및 제3자 고지 | Windows/Android, 채택 |
| file_picker/path_provider | 시스템 파일 선택/지원 경로 | MIT / BSD-3-Clause | Windows/Android, 채택 |
| flutter_markdown_plus | Markdown 미리보기 | BSD-3-Clause | Flutter, 채택 |
| flutter_secure_storage | OS 비밀 저장소 | BSD-3-Clause | Windows/Android, 채택 |
| Dio | Canvas HTTP | MIT | Dart, 채택 |
| archive/crypto/uuid/path | ZIP/해시/ID/경로 | MIT / BSD-3-Clause | Dart, 채택 |
| open_filex/url_launcher | 외부 앱/웹 열기 | BSD-3-Clause | Windows/Android, 채택 |
| desktop_drop 0.8.0 | Windows 파일 드롭 | MIT | Windows/Android 앱 빌드. 0.9.2는 file_picker의 cross_file 제약과 충돌하여 미채택 |
| html 0.15.7 / xml 7.1.0 | 학교 LTI 인증 양식 / Commons 다운로드 메타데이터 파싱 | MIT | 공개 패키지 의존성으로 채택, 임의 스크립트 실행 없음 |

모든 패키지는 소스 복사 대신 pub 의존성으로 사용합니다. 고정 버전과 전이 의존성 lockfile을 유지하며 라이선스 화면을 앱 설정에서 제공합니다. PDFium 제3자 고지와 플랫폼 DLL 배포 포함 여부는 패키징 검증이 필요합니다.

Windows 배포에는 앱 로컬 Visual C++ CRT DLL을 추가합니다. 이는 오픈소스 패키지가 아니며 Microsoft 재배포 조건이 적용됩니다. 빌드 러너의 공식 Visual Studio redistributable 디렉터리에서 가져옵니다. https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files

## 조사 후보

| 저장소 | 확인된 라이선스 | 최근 push | 코드 직접 사용 | 판단/대안 |
|---|---|---|---|---|
| vividhyeok/peer-reviewer | API에서 라이선스 미확인 | 2026-05-12 | 없음 | 문서 중심 주석 UX 후보, 소스 복사 안 함 |
| SixFiveMil/obsidian-canvas-sync | MIT | 2026-09-22 | 없음 | Obsidian/TypeScript, Dart Canvas REST로 대체 |
| BrkBuilds/Canvas-Downloader | GPL-3.0 | 2026-09-28 | 없음 | Python 런타임/라이선스 결합 피하고 공식 REST 사용 |
| ucfopen/canvasapi | MIT | 2026-04-16 | 없음 | Python 래퍼 대신 Dart REST |
| perslev/CanvasSync | MIT | 2025-05-04 | 없음 | 데스크톱 스크립트 내장 대신 REST |
| logancyang/obsidian-copilot | AGPL-3.0 | 2026-10-21 | 없음 | 소스 통합하지 않음, 향후 로컬 RAG 자체 경계 설계 |
| Yima-Gu/obsidian-lecture-lens | MIT | 2026-07-29 | 없음 | Obsidian 런타임에 의존하므로 내장 안 함 |
| Stirling-Tools/Stirling-PDF | API NOASSERTION, 직접 확인 필요 | 2026-10-21 | 없음 | 서버/OCR 의존성 미추가. 선택적 외부 변환기로 재검토 |

최근 push는 유지보수 품질이나 보안 보증을 의미하지 않습니다. 상세 알고리즘/UX 소스 검토는 추가로 필요합니다. 참고 저장소 코드를 복사했다고 주장하지 않습니다.
