"""드라마박스·릴숏 각 1페이지 받아서 출시일/날짜 패턴 찾기"""
import requests
import re
from pathlib import Path

HEADERS = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"}

def search_dates(text, name):
    print(f"\n=== {name} ===")
    patterns = [
        r'"datePublished"\s*:\s*"(\d{4}-\d{2}-\d{2})"',
        r'"releaseDate"\s*:\s*"([^"]+)"',
        r'"release_date"\s*:\s*"([^"]+)"',
        r'"published_at"\s*:\s*"([^"]+)"',
        r'"date"\s*:\s*"(\d{4}-\d{2}-\d{2})"',
        r'datetime="([^"]+)"',
        r'(\d{4}-\d{2}-\d{2})',
        r'출시[^<]{0,50}',
        r'공개[^<]{0,50}',
        r'Release[^<]{0,50}',
        r'Premiered[^<]{0,50}',
    ]
    found = set()
    for p in patterns:
        for m in re.finditer(p, text, re.I):
            found.add(m.group(0)[:80])
    for s in sorted(found):
        print(" ", s[:100])

# 1) 드라마박스 1개
url_d = "https://www.dramaboxdb.com/movie/41000119171/"
r = requests.get(url_d, headers=HEADERS, timeout=15)
path_d = Path(__file__).parent / "dramabox_raw.html"
path_d.write_text(r.text, encoding="utf-8")
print(f"Dramabox: saved {len(r.text)} chars -> {path_d}")
search_dates(r.text, "Dramabox")

# 2) 릴숏 1개 (상세 URL 추측: /series/ id 또는 /drama/ id)
id_rs = "697b04f5730036c5b80141ee"
for path_try in [f"/series/{id_rs}", f"/drama/{id_rs}", f"/show/{id_rs}", f"/watch/{id_rs}"]:
    url_rs = f"https://www.reelshort.com{path_try}"
    r2 = requests.get(url_rs, headers=HEADERS, timeout=15, allow_redirects=True)
    if r2.status_code == 200 and len(r2.text) > 5000:
        path_rs = Path(__file__).parent / "reelshort_raw.html"
        path_rs.write_text(r2.text, encoding="utf-8")
        print(f"\nReelShort: saved {len(r2.text)} chars -> {path_rs} (URL: {url_rs})")
        search_dates(r2.text, "ReelShort")
        break
else:
    # fallback: reelshort 홈에서 검색 페이지나 다른 URL 시도
    url_rs = "https://www.reelshort.com/"
    r2 = requests.get(url_rs, headers=HEADERS, timeout=15)
    path_rs = Path(__file__).parent / "reelshort_raw.html"
    path_rs.write_text(r2.text, encoding="utf-8")
    print(f"\nReelShort: no series URL found, saved homepage {len(r2.text)} chars -> {path_rs}")
    search_dates(r2.text, "ReelShort (home)")
