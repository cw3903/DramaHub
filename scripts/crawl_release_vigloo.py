#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Vigloo만 크롤링해서 release_dates_vigloo.json 생성.
dramas.json의 id_vigloo가 있는 항목만 요청합니다.
"""

import json
import time
from pathlib import Path

from release_crawl_common import (
    DRAMAS_JSON,
    DELAY_DEFAULT,
    fetch_vigloo_release_date,
)

ROOT = Path(__file__).resolve().parent.parent
OUT_JSON = ROOT / "assets" / "data" / "release_dates_vigloo.json"


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Vigloo 릴리즈 날짜만 크롤링 → release_dates_vigloo.json")
    parser.add_argument("--limit", type=int, default=0, help="테스트용 최대 개수 (0=전체)")
    parser.add_argument("--delay", type=float, default=DELAY_DEFAULT, help="요청 간 딜레이(초)")
    parser.add_argument("--debug", action="store_true", help="첫 응답 HTML을 vigloo_sample.html에 저장")
    args = parser.parse_args()

    if not DRAMAS_JSON.exists():
        print(f"파일 없음: {DRAMAS_JSON}")
        return

    with open(DRAMAS_JSON, "r", encoding="utf-8") as f:
        dramas = json.load(f)

    debug_path = (ROOT / "scripts" / "vigloo_sample.html") if args.debug else None
    result = {}
    total = 0
    for i, item in enumerate(dramas):
        if args.limit > 0 and i >= args.limit:
            break
        if not isinstance(item, dict):
            continue
        rid = item.get("id", "")
        id_v = (item.get("id_vigloo") or "").strip()
        if not id_v:
            continue
        total += 1
        date = fetch_vigloo_release_date(id_v, debug_save_path=debug_path)
        if debug_path:
            debug_path = None
        time.sleep(args.delay)
        if date:
            result[rid] = date
            print(f"[{len(result)}] id={rid} release_date_vigloo={date}")
        if (i + 1) % 50 == 0 and total:
            print(f"  ... {i+1} 항목 중 Vigloo ID 있음 {total}개, 채워진 수 {len(result)}")

    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(result, f, ensure_ascii=False, indent=2)
    print(f"\n완료. Vigloo 릴리즈데이트 {len(result)}개 → {OUT_JSON}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n중단됨 (Ctrl+C)")
        raise SystemExit(0)
