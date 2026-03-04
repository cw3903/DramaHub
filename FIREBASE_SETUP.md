# CONFIGURATION_NOT_FOUND 해결 방법

로그인 시 `CONFIGURATION_NOT_FOUND` 가 나오면 아래를 **순서대로** 확인하세요.

---

## 1. Firebase Authentication 사용 설정

1. https://console.firebase.google.com 접속
2. 프로젝트 **dramahub-22ff2** 선택
3. 왼쪽 메뉴 **빌드** → **Authentication** 클릭
4. **시작하기** 버튼이 보이면 클릭해서 Authentication 사용 설정
5. **Sign-in method** (또는 **로그인 방법**) 탭 클릭
6. **이메일/비밀번호** 행에서 **사용 설정** 켜기 → **저장**

---

## 2. Android 앱에 SHA 지문 추가 (필수는 아니지만 권장)

1. 터미널에서 실행 (프로젝트 폴더에서):
   ```
   cd C:\Users\heo\drama_hub\android
   gradlew.bat signingReport
   ```
   (또는 `.\gradlew.bat signingReport`)
2. 출력에서 **Variant: debug** 아래 **SHA1:** 값 복사 (예: `AA:BB:CC:...`)
3. Firebase 콘솔 → **프로젝트 설정** (톱니바퀴) → **일반** 탭
4. **내 앱** 카드에서 Android 앱 (**com.dramahub.app**) 선택
5. **SHA 인증서 지문** → **지문 추가** → 방금 복사한 SHA1 붙여넣기 → 저장
6. **google-services.json** 다시 다운로드 후 `drama_hub/android/app/` 에 덮어쓰기
7. `flutter clean` → `flutter run` 다시 실행

---

## 3. 정리

- **Authentication 사용** + **이메일/비밀번호 사용 설정** 까지 하면 대부분 해결됩니다.
- SHA 추가 후에는 **google-services.json 다시 받아서** 넣고, **클린 빌드** 한 번 해주세요.
