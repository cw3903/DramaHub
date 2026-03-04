# 릴리즈데이트 크롤러 (dramas.json)

**3개의 파이썬 스크립트**가 각각 **1개의 JSON**을 만들고, 마지막에 **dramas.json을 한 번에 갱신**하는 구조입니다.

| 순서 | 스크립트 | 출력 JSON |
|------|----------|-----------|
| 1 | `crawl_release_vigloo.py` | `release_dates_vigloo.json` |
| 2 | `crawl_release_dramabox.py` | `release_dates_dramabox.json` |
| 3 | `crawl_release_reelshort.py` | `release_dates_reelshort.json` |
| 4 | `update_dramas_release.py` | **dramas.json** (또는 dramas_with_release.json)에 3개 JSON 반영 |

## 사용법

```bash
cd scripts
pip install -r requirements-crawler.txt

# 1) Vigloo만 크롤링 → release_dates_vigloo.json
python crawl_release_vigloo.py

# 2) Dramabox만 크롤링 → release_dates_dramabox.json
python crawl_release_dramabox.py

# 3) ReelShort만 크롤링 → release_dates_reelshort.json
python crawl_release_reelshort.py

# 4) 위 3개 JSON을 dramas.json에 반영
python update_dramas_release.py              # 결과를 dramas_with_release.json에 저장
python update_dramas_release.py --in-place   # dramas.json 직접 수정
```

- **테스트(처음 N개만)**  
  `python crawl_release_vigloo.py --limit 10` 등
- **딜레이 조정**  
  `python crawl_release_vigloo.py --delay 2` 등

## 출력

- **1~3단계**: `assets/data/release_dates_vigloo.json`, `release_dates_dramabox.json`, `release_dates_reelshort.json`  
  (각 파일은 `{ "드라마id": "YYYY-MM-DD", ... }` 형태)
- **4단계**: `dramas_with_release.json` (기본) 또는 `--in-place` 시 `dramas.json`  
  각 드라마에 `release_date_vigloo`, `release_date_dramabox`, `release_date_reelshort`, `release_date`(통합) 필드가 채워집니다.

## 데이터 소스

| 플랫폼   | ID 필드        | 크롤러 출력 → 반영 필드        | URL 예시 |
|----------|----------------|---------------------------------|----------|
| Vigloo   | `id_vigloo`     | release_dates_vigloo.json → `release_date_vigloo` | `https://www.vigloo.com/en/content/{id}` |
| Dramabox | `id_dramabox`   | release_dates_dramabox.json → `release_date_dramabox` | `https://www.dramaboxdb.com/movie/{id}/` |
| ReelShort| `id_reelshort`  | release_dates_reelshort.json → `release_date_reelshort` | `https://www.reelshort.com/movie/{id}` |

## 주의사항

1. **사이트 구조**  
   각 사이트 HTML이 바뀌면 스크립트 안의 선택자/정규식을 수정해야 할 수 있습니다.  
   브라우저 개발자도구로 상세 페이지를 열고, “릴리즈일/공개일”이 들어 있는 태그를 확인한 뒤 `crawl_release_dates.py`의 해당 플랫폼 함수를 수정하세요.

2. **Vigloo / JS 렌더링**  
   Vigloo는 상세 페이지가 **JavaScript로 렌더링**되는 SPA일 수 있어, `requests`로 받은 HTML에는 날짜가 없을 수 있습니다.  
   - `python crawl_release_dates.py --limit 1 --debug` 로 실행하면 `scripts/vigloo_sample.html` 에 첫 응답이 저장됩니다.  
   - 이 파일을 열어서 날짜가 어떤 태그/JSON에 들어있는지 확인한 뒤, `crawl_release_dates.py`의 `fetch_vigloo_release_date` 를 수정하세요.  
   - HTML에 전혀 없으면 `playwright`로 실제 브라우저를 띄워 렌더링된 HTML을 가져오는 방식으로 확장해야 합니다.

3. **이용약관**  
   각 서비스의 이용약관/로봇 정책을 확인하고, 크롤링이 허용되는 범위에서만 사용하세요.  
   가능하면 공식 API나 제공 데이터가 있으면 그걸 우선 사용하는 것이 좋습니다.

4. **요청 간격**  
   기본 `--delay`로 서버에 부담을 줄이세요. 차단되면 `--delay` 값을 더 크게 해보세요.

5. **Dramabox에서 “연결 불가”가 나올 때**  
   일부 네트워크에서는 `dramaboxdb.com` DNS 조회가 안 될 수 있습니다.  
   **휴대폰 핫스팟**이나 **VPN**으로 다른 네트워크에서 `crawl_release_dramabox.py`를 실행해 보세요.  
   (스크립트는 www / 비www 둘 다 시도합니다.)

6. **ReelShort**  
   상세 페이지(`https://www.reelshort.com/movie/{id}`)에서 meta·script·본문의 날짜를 파싱합니다.  
   해당 페이지에 릴리즈일이 없으면 0개로 남을 수 있습니다.
