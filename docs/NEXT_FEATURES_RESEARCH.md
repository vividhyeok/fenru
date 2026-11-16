# 다음 기능 조사 — Galaxy Tab S7 기준 (2026-11-04)

현재 코드와 실제 사용 중인 고정 의존성을 확인하고, 후보 프로젝트의 공식 문서·저장소를 조사했습니다. 아래는 구현 후보이며 이번 조사에서 기능을 새로 설치하거나 태블릿 앱을 교체하지 않았습니다. 난이도와 우선순위는 통합 작업에 대한 판단이며 실측 개발 기간·속도는 아닙니다.

## 우선순위

|순서|기능|현 상태와 구현 방향|통합 부담|
|---|---|---|---|
|1|수동 OCR → 검색·AI 연결|PDF 도구의 글자 인식 버튼에서 현재 페이지/지정 페이지/문서 전체를 선택. 자동 스캔 감지·자동 실행은 하지 않음. 해시/페이지/엔진 버전별로 결과를 저장하고 검색·채팅에 연결|중간 이상|
|2|사진·스크린샷 → PDF|현재 변환 대상에 이미지 없음. 이미 쓰는 pdfrx_engine 0.7.4의 createFromJpegData, createNew, pages, encodePdf 사용. 여러 사진을 한 문서로 묶기|낮음~중간|
|3|페이지 추출·병합·회전·재정렬|현재 UI에 없음. 기존 엔진의 pages setter, assemble, encodePdf, rotatedBy/rotatedCW90를 활용. 새 PDF로 저장하며 원본 및 기존 질문 출처 유지|중간|
|4|과목 전체 본문 검색|현재 전역 FTS는 body/tags/folder/extracted를 색인하지만 PDF 텍스트 캐시는 직접 연결되지 않음. PDF/OCR 색인을 같은 검색 흐름으로 통합하고 문서·페이지로 이동|중간|
|5|공유 메뉴로 과목에 바로 추가|AndroidManifest에 SEND/VIEW 수신 필터 없음. 카카오톡·브라우저·파일 앱 공유 → Fenru → 마지막 과목 제안. content URI를 스트림으로 가져오기|낮음~중간|
|6|필기 포함 PDF 내보내기|현재 필기는 DB annotation이고 원본 PDF에 들어가지 않음. PDFium에 필기/하이라이트를 반영한 사본 내보내기. 원본 텍스트·벡터를 유지하는 방식 우선|중간 이상|
|7|암호 PDF 열기|현재 사용자 암호 입력 UI 없음. 기존 PdfPasswordProvider를 연결. 암호는 세션 기본값으로 처리하고 저장은 별도 선택|낮음~중간|
|8|중요 표시·오답·질문 모으기|기존 annotation/노트/과목 데이터 재사용. 별표한 페이지·하이라이트·질문을 복습 목록으로 모으기|낮음~중간|
|9|강의 녹음 + 텍스트 저장|과목 안에서 녹음 시작/일시정지/중지, 음성 원본 저장 후 텍스트 변환·타임스탬프·수정·검색·AI 연결. 화면 꺼짐과 앱 이동 중 녹음 유지 및 중단 복구 필요|중간 이상|
|10|DOCX/PPTX/XLSX/HWP/HWPX → PDF 확대|Windows에는 설치된 LibreOffice/Office/한글 호출이 이미 있음. Android는 엔진이 없고 XLS/XLSX도 현재 지원 목록에 없음. 문서별 레이아웃·글꼴·표·수식 검증 필요|높음|

## OCR 후보와 권장 설계

- **Tesseract4Android / Tesseract 5**: Apache-2.0 오픈소스 Android/JNI 후보. 한국어·영어 언어 데이터를 앱 전용 경로에 준비해야 함. Flutter에는 네이티브 채널을 연결해야 하며 PDF 렌더 이미지 전달, 취소와 자원 해제를 구현해야 함. [공식 저장소](https://github.com/adaptech-cz/Tesseract4Android), [공식 언어 모델](https://github.com/tesseract-ocr/tessdata_fast).
- **PaddleOCR**: Apache-2.0. 한국어 인식 모델 후보를 비교할 가치가 있으나, Android 추론 런타임과 모델 변환/배포까지 포함하므로 간단한 Dart 의존성 추가로 끝나지 않음. S7에서 Tesseract와 같은 문서로 정확도·지연·발열을 비교한 후 결정. [공식 저장소](https://github.com/PaddlePaddle/PaddleOCR), [인식 모델 문서](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/module_usage/text_recognition.en.md).
- **ML Kit**: 한국어 온디바이스 OCR 대안. Google SDK 자체는 오픈소스 엔진 후보와 구분해야 함. 공식 문서상 모델 동적 다운로드형과 앱 번들형이 있고, 동적 방식은 첫 사용 모델 준비가 필요함. 순수 오픈소스가 필수이면 기본 엔진 후보에서 제외. [공식 문서](https://developers.google.com/ml-kit/vision/text-recognition/v2/android).
- **OCRmyPDF**: 검색 가능한 PDF 텍스트층 생성에 유용한 데스크톱 후보. Python과 OCR/이미지 처리 도구 의존성을 태블릿 앱 안에 그대로 넣는 것은 부담이 큼. [공식 저장소](https://github.com/ocrmypdf/OCRmyPDF).

사용자 요청에 따라 OCR은 **수동 실행**으로 확정합니다. 자동으로 스캔 여부를 판단하거나 가져오기 직후 실행하지 않습니다. 사용자가 ‘글자 인식(OCR)’을 누르고 현재 페이지/지정 페이지/문서 전체를 선택한 뒤 실행합니다. 진행률·취소·재시도·이미 처리한 결과 재사용을 제공하고, 결과를 검색/AI에 반영합니다. 글자가 없거나 인식 실패한 페이지도 상태를 저장하여 불필요하게 재시도하지 않습니다. 필기 중 OCR 작업은 양보하도록 설계합니다.

1단계는 인식한 본문으로 검색과 AI 질문을 가능하게 하고, 2단계는 글자/줄 좌표를 이용한 선택·하이라이트와 검색 가능한 PDF 사본 내보내기입니다. 원본 PDF에 텍스트층을 넣는 것과 앱 내부에서 OCR 텍스트를 참고하는 것은 서로 다른 작업입니다. 기본 OCR로 손글씨·수식·복잡한 표까지 정확하게 읽는다고 약속할 수 없으며, 실제 학교 자료로 별도 평가해야 합니다.

## PDF 변환과 편집에서 확인한 점

설치된 `pdfrx_engine-0.7.4/lib/src/pdf_document.dart`에 `createFromJpegData`, `createNew`, `pages` setter, `assemble`, `encodePdf`가 있고 `pdf_page.dart`에는 회전 확장이 있습니다. 사진→PDF와 페이지 조작 때문에 새 PDF 렌더러를 추가할 필요가 없습니다. PNG는 입력 이미지 디코딩/변환 경로 또는 이미지 생성 라이브러리 검토가 필요하며, 무조건 JPEG로 재압축하지 않아야 합니다. [공식 API](https://pub.dev/documentation/pdfrx/latest/pdfrx/PdfDocument-class.html).

텍스트·이미지·정리 노트에서 새 PDF를 만드는 작업에는 Apache-2.0의 [dart_pdf](https://github.com/DavBfr/dart_pdf)도 후보입니다. 기존 PDF를 이미지로 통째로 다시 만들어 내보내면 텍스트 선택과 벡터 품질을 잃을 수 있으므로, 원본 내용을 유지하는 편집 경로를 우선합니다.

페이지 조작은 새 문서로 저장하고 필기·책갈피의 페이지 번호를 함께 대응시켜야 합니다. 기존 대화의 출처는 원본 문서를 계속 가리키도록 유지합니다. 라이브러리에 기능이 있다는 것과 앱의 모든 기록이 안전하게 연결된다는 것은 별도 검증 대상입니다.

Office 변환은 [LibreOffice 공식 CLI](https://help.libreoffice.org/latest/en-US/text/shared/guide/start_parameters.html)를 현재 데스크톱 구현에서 이미 호출합니다. 이를 Android에서 그대로 실행할 수 있다고 보면 안 됩니다. 한글·Office 문서의 본문 추출과 원래 모양 그대로 PDF 변환도 구분해야 합니다. HWP/HWPX는 실제 학교 문서 표본 검증 없이는 변환 품질을 판단하지 않습니다.

## 그 외 근거

- [Android 공유 수신](https://developer.android.com/training/sharing/receive): 앱에서 공유 파일을 받는 네이티브 연결을 구현할 수 있음.
- [SQLite FTS5](https://www.sqlite.org/fts5.html): 현재 앱이 사용하는 검색 엔진에 PDF/OCR 본문을 연결하는 방향. 별도 벡터 DB나 AI API 없이 시작 가능.

## 다음 버전 묶음 제안

첫 묶음: 사진→PDF, 페이지 추출/회전/병합, 공유 가져오기, 암호 PDF 입력.
두 번째 묶음: 수동 OCR + 본문 검색 + AI 출처 연결.
강의 녹음·텍스트 저장도 필수 개발 목록에 추가하며, 백그라운드 녹음 안정성과 전사 엔진 검증을 별도로 수행.
세 번째 묶음: 필기 포함 PDF 내보내기 + 중요 표시/오답 복습.
Office/HWP 고품질 자동 변환은 독립 과제로 검증.


## 강의 녹음과 전사 — 추가 요구사항

사용 흐름: 과목에서 녹음 시작 → 필요 시 일시정지/재개 → 종료 시 음성 원본부터 저장 → 텍스트 변환 → 같은 과목의 강의 기록으로 저장. 전사가 실패해도 음성은 남기고 나중에 다시 변환할 수 있어야 합니다.

필수 항목:

- 과목·날짜·강의 제목과 연결된 음성 원본 및 전사문. 기존 녹음 파일도 가져와서 전사할 수 있는 구조.
- 녹음 시간과 상태를 명확히 표시하고 화면을 끄거나 PDF·다른 앱으로 이동해도 녹음을 유지. Android 마이크 권한 및 foreground service/알림 처리가 필요.
- 문단별 타임스탬프, 해당 구간 재생, 전사문 수정. 원래 인식 결과와 수정본을 구분할 수 있는 저장 구조.
- 전사문을 과목 본문 검색과 질문 근거에 포함. ‘교수님이 말한 시험 범위’ 질문에서 공지·강의 PDF·전사문을 함께 검색하고 문서 출처와 녹음 시점을 구분.
- 파일부터 안전하게 저장한 뒤 전사 수행. 긴 강의를 통째로 메모리에 올리지 않고 구간별 처리하고, 진행률·취소·재시도 제공.
- 강의 녹음 중 텍스트 변환보다 원본 녹음 안정성을 우선. 기본 전사 시점은 녹음 종료 후 자동 시작이며 실시간 자막은 별도 기능.

구현 후보:

- [record](https://pub.dev/packages/record): Flutter 오디오 녹음 후보. 실제 녹음 유지·권한·장시간 테스트는 앱에서 별도로 연결해야 함.
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp): MIT 오픈소스 온디바이스 전사 후보이며 Android 예제가 있음. API 키 없이 처리하는 방향을 우선 검토. 한국어를 지원하는 다국어 모델을 사용하고, 모델은 앱과 분리해 최초 한 번 준비하여 APK에 대형 모델을 모두 포함하지 않음. S7에서 정확도·처리 시간·메모리·발열을 측정한 뒤 모델 결정. 작은 모델이 강의 전문용어까지 충분히 정확하다고 가정하지 않음.
- Android [SpeechRecognizer](https://developer.android.com/reference/android/speech/SpeechRecognizer)는 공식 문서상 장시간 연속 인식용이 아니므로 강의 전체 녹음/전사의 핵심 엔진으로 사용하지 않는 방향. 기기별 온디바이스 인식 지원도 확인이 필요.

추가 설정을 반복시키지 않도록 마지막 과목·전사 언어·모델 설정을 기억합니다. 기본 계획은 로컬 전사이며, 외부 API 전사는 사용자가 필요로 할 때 별도 선택 기능으로 검토합니다. 이번 요구사항 갱신에서 외부 API 호출이나 새 키 설정은 진행하지 않았습니다.
