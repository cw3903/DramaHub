#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vigloo/Dramabox/ReelShort 3개 JSON을 읽어서 dramas.json에 릴리즈데이트를 반영합니다.

사용 순서:
  1. python crawl_release_vigloo.py    → release_dates_vigloo.json
  2. python crawl_release_dramabox.py  → release_dates_dramabox.json
  3. python crawl_release_reelshort.py → release_dates_reelshort.json
  4. python update_dramas_release.py   → dramas.json (또는 dramas_with_release.json) 갱신
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DRAMAS_JSON = ROOT / "assets" / "data" / "dramas.json"
OUT_JSON = ROOT / "assets" / "data" / "dramas_with_release.json"
DATA_DIR = ROOT / "assets" / "data"

VIGLOO_JSON = DATA_DIR / "release_dates_vigloo.json"
DRAMABOX_JSON = DATA_DIR / "release_dates_dramabox.json"
REELSHORT_JSON = DATA_DIR / "release_dates_reelshort.json"


def load_mapping(path: Path) -> dict:
    """드라마 id → 날짜 문자열. 파일 없으면 빈 dict."""
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data if isinstance(data, dict) else {}


def main():
    import argparse
    parser = argparse.ArgumentParser(description="3개 release_dates_*.json → dramas.json 반영")
    parser.add_argument("--in-place", action="store_true", help="dramas.json 직접 수정 (기본은 dramas_with_release.json)")
    args = parser.parse_args()

    if not DRAMAS_JSON.exists():
        print(f"파일 없음: {DRAMAS_JSON}")
        return

    vigloo = load_mapping(VIGLOO_JSON)
    dramabox = load_mapping(DRAMABOX_JSON)
    reelshort = load_mapping(REELSHORT_JSON)
    print(f"로드: Vigloo {len(vigloo)}개, Dramabox {len(dramabox)}개, ReelShort {len(reelshort)}개")

    with open(DRAMAS_JSON, "r", encoding="utf-8") as f:
        dramas = json.load(f)

    for item in dramas:
        if not isinstance(item, dict):
            continue
        rid = item.get("id", "")
        if not rid:
            continue
        item["release_date_vigloo"] = vigloo.get(rid)
        item["release_date_dramabox"] = dramabox.get(rid)
        item["release_date_reelshort"] = reelshort.get(rid)
        # 표시용 통합 날짜 (우선순위: vigloo > dramabox > reelshort)
        item["release_date"] = (
            vigloo.get(rid) or dramabox.get(rid) or reelshort.get(rid)
            or item.get("release_date") or item.get("released_at") or item.get("releaseDate")
        )

    out_path = DRAMAS_JSON if args.in_place else OUT_JSON
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(dramas, f, ensure_ascii=False, indent=2)

    v_count = sum(1 for x in dramas if isinstance(x, dict) and x.get("release_date_vigloo"))
    d_count = sum(1 for x in dramas if isinstance(x, dict) and x.get("release_date_dramabox"))
    r_count = sum(1 for x in dramas if isinstance(x, dict) and x.get("release_date_reelshort"))
    any_count = sum(1 for x in dramas if isinstance(x, dict) and (x.get("release_date_vigloo") or x.get("release_date_dramabox") or x.get("release_date_reelshort") or x.get("release_date")))
    print(f"반영 완료. Vigloo:{v_count} Dramabox:{d_count} ReelShort:{r_count} (날짜 있는 항목: {any_count})")
    print(f"저장: {out_path}")


if __name__ == "__main__":
    main()
