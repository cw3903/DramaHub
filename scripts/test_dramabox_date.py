# Quick test: extract date from dramabox_raw.html for id 41000119171
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
html = (ROOT / "dramabox_raw.html").read_text(encoding="utf-8")
id_ = "41000119171"

def normalize_date(s):
    if not s:
        return None
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", s)
    return f"{m.group(1)}-{m.group(2)}-{m.group(3)}" if m else None

# Find id then firstShelfTime in next 800 chars
idx = html.find(id_)
if idx != -1:
    chunk = html[idx : idx + 800]
    for key in ["firstShelfTime", "shelfTime"]:
        m = re.search(rf'["\']{key}["\']\s*:\s*["\'](\d{{4}}-\d{{2}}-\d{{2}})', chunk)
        if m:
            print(f"Found {key}:", normalize_date(m.group(1)))
            break
else:
    print("id not found")
