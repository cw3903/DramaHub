"""Vigloo 한 페이지만 받아서 출시일/날짜 관련 문자열 찾기"""
import requests
import re
from pathlib import Path

url = "https://www.vigloo.com/en/content/15001189"
r = requests.get(url, headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"})
path = Path(__file__).parent / "vigloo_raw.html"
path.write_text(r.text, encoding="utf-8")
print("Saved", len(r.text), "chars to", path)

# 날짜/출시 관련 패턴
text = r.text
patterns = [
    r"release[A-Za-z]*[\"']?\s*:\s*[\"']?(\d{4}[-\d]*)",
    r"date[\"']?\s*:\s*[\"']?(\d{4}[-\d]*)",
    r"published[A-Za-z]*[\"']?\s*:\s*[\"']?(\d{4}[-\d]*)",
    r"출시[^<]{0,30}",
    r"공개[^<]{0,30}",
    r"(\d{4}-\d{2}-\d{2})",
    r"datetime[\"']?\s*=\s*[\"']([^\"']+)",
]
found = set()
for p in patterns:
    for m in re.finditer(p, text, re.I):
        s = m.group(0).strip()[:100]
        found.add(s)
for s in sorted(found):
    print(s)
