# Play Console 업로드용 출시(릴리스) 서명 설정

디버그 서명 AAB는 Play Console에서 거부됩니다. 아래 순서대로 하면 됩니다.

## 1. 키스토어 만들기 (최초 1회)

`android` 폴더에서 PowerShell 또는 CMD 실행 후 아래 명령 실행.

**Windows에서 `keytool`을 찾을 수 없다면** Android Studio에 포함된 keytool 전체 경로 사용:

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore app-release.keystore -alias dramahub -keyalg RSA -keysize 2048 -validity 10000
```

(Java가 PATH에 있으면 `keytool` 만 써도 됩니다.)

- 나오는 질문에 **키스토어 비밀번호**, **키 비밀번호**, 이름 등 입력
- **비밀번호 두 개는 꼭 기억해 두세요.** 분실 시 Play 업로드 불가
- `app-release.keystore` 파일이 `android` 폴더에 생성됨

## 2. key.properties 만들기

1. `key.properties.example` 를 복사해서 `key.properties` 로 저장
2. `key.properties` 를 열어서 아래처럼 **본인 값**으로 수정:

```properties
storePassword=방금_키스토어에_설정한_비밀번호
keyPassword=방금_키에_설정한_비밀번호
keyAlias=dramahub
storeFile=app-release.keystore
```

- `storeFile` 은 `android` 폴더 기준 파일 이름만 적으면 됨 (`app-release.keystore`)

## 3. AAB 다시 빌드

프로젝트 루트(drama_hub)에서:

```bash
flutter build appbundle
```

생성된 `build/app/outputs/bundle/release/app-release.aab` 를 Play Console에 업로드하면 됩니다.

---

- `key.properties`, `*.keystore` 는 Git에 올라가지 않도록 이미 제외되어 있습니다.
- 키스토어와 비밀번호는 백업해 두고, Play Console 앱 서명은 나중에 Google Play App Signing으로 전환할 수 있습니다.
