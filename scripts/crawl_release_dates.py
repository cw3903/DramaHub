#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dramas.json에 소스별 릴리즈 날짜를 채우는 크롤러.
Vigloo → release_date_vigloo, Dramabox → release_date_dramabox, ReelShort → release_date_reelshort
각 소스별로 1개씩 구분해 저장합니다.

사용법:
  pip install -r requirements-crawler.txt
  python crawl_release_dates.py

출력: assets/data/dramas_with_release.json (원본은 덮어쓰지 않음)
앱은 release_date_vigloo > release_date_dramabox > release_date_reelshort > 레거시 순으로 사용합니다.
"""

import json
import re
import time
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("pip install -r requirements-crawler.txt 를 먼저 실행하세요.")
    raise

# 프로젝트 루트 기준 경로 (스크립트는 scripts/ 에 있음)
ROOT = Path(__file__).resolve().parent.parent
DRAMAS_JSON = ROOT / "assets" / "data" / "dramas.json"
OUT_JSON = ROOT / "assets" / "data" / "dramas_with_release.json"

# 요청 간 딜레이(초) - 서버 부하 줄이기
DELAY = 1.5
REQUEST_TIMEOUT = 15

# Dramabox 연결 실패 시 같은 에러 반복 출력 방지 (한 번만 경고)
_dramabox_unreachable_warned = False

# User-Agent (일부 사이트는 봇 차단)
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9,ko;q=0.8",
}


def normalize_date(s: str | None) -> str | None:
    """YYYY-MM-DD 형태로 정규화. 파싱 실패 시 None."""
    if not s or not s.strip():
        return None
    s = s.strip()
    # 이미 YYYY-MM-DD
    if re.match(r"^\d{4}-\d{2}-\d{2}$", s):
        return s
    # YYYY-MM-DD 추출
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    # YYYY만
    m = re.search(r"\b(20\d{2}|19\d{2})\b", s)
    if m:
        return f"{m.group(1)}-01-01"
    return None


def _extract_date_from_text(text: str) -> str | None:
    """텍스트에서 릴리즈/공개일 관련 문맥의 날짜만 추출."""
    if not text:
        return None
    for pattern in [
        r"(?:release|premiered|aired|date|published|updated|created)\s*[:\-]\s*[\"']?(\d{4}-\d{2}-\d{2})",
        r"(?:release|premiered|aired|date|published|updated|created)\s*[:\-]\s*[\"']?(\d{4})",
        r"(\d{4}-\d{2}-\d{2})",
    ]:
        m = re.search(pattern, text, re.I)
        if m:
            return normalize_date(m.group(1))
    return None


def _extract_date_from_json_like(text: str) -> str | None:
    """JSON 형태 문자열에서 날짜 필드 추출. Vigloo는 schema.org ld+json 에 datePublished 사용."""
    if not text:
        return None
    for key in ["datePublished", "releaseDate", "release_date", "releasedAt", "published_at", "created_at", "updated_at", "year", "aired", "firstShelfTime", "shelfTime"]:
        # "releaseDate":"2024-01-15" 또는 "releaseDate": "2024-01-15"
        for pattern in [
            rf'["\']{key}["\']\s*:\s*["\'](\d{{4}}-\d{{2}}-\d{{2}})[T\s]\d{{2}}:\d{{2}}',
            rf'["\']{key}["\']\s*:\s*["\'](\d{{4}}-\d{{2}}-\d{{2}})["\']',
            rf'["\']{key}["\']\s*:\s*["\'](\d{{4}})["\']',
            rf'["\']{key}["\']\s*:\s*(\d{{4}}-\d{{2}}-\d{{2}})',
            rf'["\']{key}["\']\s*:\s*(\d{{4}})',
        ]:
            m = re.search(pattern, text, re.I)
            if m:
                return normalize_date(m.group(1))
    return None


def fetch_vigloo_release_date(id_vigloo: str, debug_save_path: Path | None = None) -> str | None:
    """Vigloo 상세 페이지에서 날짜 추출. (SPA라면 HTML에 없을 수 있음 → Playwright 필요)"""
    if not id_vigloo or not id_vigloo.strip():
        return None
    url = f"https://www.vigloo.com/en/content/{id_vigloo.strip()}"
    try:
        r = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        html = r.text
        if debug_save_path:
            debug_save_path.write_text(html, encoding="utf-8")
            print(f"  [디버그] HTML 저장: {debug_save_path}")
        soup = BeautifulSoup(html, "html.parser")
        # 1) datetime 속성
        for tag in soup.find_all(attrs={"datetime": True}):
            d = normalize_date(tag.get("datetime"))
            if d:
                return d
        # 2) data-* 속성
        for tag in soup.find_all(attrs=lambda a: a and any(k.startswith("data-") for k in a)):
            for k, v in tag.attrs.items():
                if v and ("date" in k or "release" in k or "time" in k):
                    d = normalize_date(str(v))
                    if d:
                        return d
        # 3) script 내 JSON (Next.js 등)
        for script in soup.find_all("script", type=re.compile(r"application/(ld\+)?json")):
            if script.string:
                d = _extract_date_from_json_like(script.string)
                if d:
                    return d
        for script in soup.find_all("script"):
            if script.string and ("release" in script.string.lower() or "date" in script.string):
                d = _extract_date_from_json_like(script.string)
                if d:
                    return d
        # 4) meta (og:published_time 등)
        for meta in soup.find_all("meta", attrs={"property": True}):
            p = (meta.get("property") or "").lower()
            c = meta.get("content")
            if c and ("date" in p or "release" in p or "time" in p):
                d = normalize_date(c)
                if d:
                    return d
        # 5) 본문 텍스트
        return _extract_date_from_text(soup.get_text())
    except Exception as e:
        print(f"  [Vigloo {id_vigloo}] {e}")
        return None


def _extract_dramabox_date_from_html(html: str, id_dramabox: str) -> str | None:
    """DramaBox 페이지 HTML에서 해당 작품(bookId)의 firstShelfTime/shelfTime만 추출.
    __NEXT_DATA__ 내 bookInfo에 "bookId":"41000119171" 뒤 firstShelfTime이 있음."""
    id_ = id_dramabox.strip()
    needle = f'"bookId":"{id_}"'
    idx = html.find(needle)
    if idx == -1:
        idx = html.find(f'"bookId": {id_}')
    if idx != -1:
        chunk = html[idx : idx + 600]
        for key in ["firstShelfTime", "shelfTime"]:
            m = re.search(rf'["\']{key}["\']\s*:\s*["\'](\d{{4}}-\d{{2}}-\d{{2}})', chunk)
            if m:
                return normalize_date(m.group(1))
    return None


def fetch_dramabox_release_date(id_dramabox: str) -> str | None:
    """DramaBox DB 페이지에서 날짜 추출 (firstShelfTime/shelfTime 또는 기존 방식)."""
    if not id_dramabox or not id_dramabox.strip():
        return None
    id_ = id_dramabox.strip()
    url = f"https://www.dramaboxdb.com/movie/{id_}/"
    try:
        r = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        html = r.text
        d = _extract_dramabox_date_from_html(html, id_)
        if d:
            return d
        soup = BeautifulSoup(html, "html.parser")
        for tag in soup.find_all(["time", "span", "div"], attrs={"datetime": True}):
            dt = tag.get("datetime")
            if dt:
                d = normalize_date(dt)
                if d:
                    return d
        return _extract_date_from_text(soup.get_text())
    except Exception as e:
        global _dramabox_unreachable_warned
        if not _dramabox_unreachable_warned:
            _dramabox_unreachable_warned = True
            print(f"  [Dramabox] dramaboxdb.com 연결 불가 (DNS/네트워크). 이후 Dramabox 요청은 스킵합니다. (에러: {e})")
        return None


def fetch_reelshort_release_date(id_reelshort: str) -> str | None:
    """ReelShort은 id가 있을 때 상세 URL이 있으면 추가. (현재는 검색/상세 구조 확인 필요)"""
    if not id_reelshort or not id_reelshort.strip():
        return None
    # reelshort.com 상세 URL 패턴이 있으면 여기 추가
    return None


def main():
    import argparse
    parser = argparse.ArgumentParser(description="dramas.json에 release_date 크롤링")
    parser.add_argument("--limit", type=int, default=0, help="테스트용: 처리할 최대 개수 (0=전체)")
    parser.add_argument("--delay", type=float, default=DELAY, help="요청 간 딜레이 초")
    parser.add_argument("--debug", action="store_true", help="첫 Vigloo 응답 HTML을 scripts/vigloo_sample.html 에 저장")
    parser.add_argument("--in-place", action="store_true", help="결과를 dramas.json에 덮어쓰기 (기본은 dramas_with_release.json)")
    args = parser.parse_args()
    delay_sec = args.delay
    debug_path = (ROOT / "scripts" / "vigloo_sample.html") if args.debug else None

    if not DRAMAS_JSON.exists():
        print(f"파일 없음: {DRAMAS_JSON}")
        return

    with open(DRAMAS_JSON, "r", encoding="utf-8") as f:
        dramas = json.load(f)

    total = len(dramas)
    if args.limit > 0:
        total = min(total, args.limit)
        print(f"테스트 모드: 상위 {total}개만 처리")
    updated_v = 0
    updated_d = 0
    updated_r = 0
    for i, item in enumerate(dramas):
        if args.limit > 0 and i >= args.limit:
            break
        if not isinstance(item, dict):
            continue
        rid = item.get("id", "")
        # 이미 어떤 소스로든 날짜가 있으면 해당 소스는 스킵 (없는 소스만 채움)
        has_v = bool(item.get("release_date_vigloo"))
        has_d = bool(item.get("release_date_dramabox"))
        has_r = bool(item.get("release_date_reelshort"))
        has_legacy = bool(
            item.get("release_date") or item.get("released_at") or item.get("releaseDate")
        )
        if has_v and has_d and has_r:
            continue  # 세 소스 다 있으면 스킵
        # 레거시만 있어도 일단 통과 (vigloo/dramabox/reelshort 빈 칸만 채움)

        id_v = (item.get("id_vigloo") or "").strip()
        id_d = (item.get("id_dramabox") or "").strip()
        id_r = (item.get("id_reelshort") or "").strip()

        if id_v and not has_v:
            date_v = fetch_vigloo_release_date(id_v, debug_save_path=debug_path)
            if debug_path:
                debug_path = None
            time.sleep(delay_sec)
            if date_v:
                item["release_date_vigloo"] = date_v
                updated_v += 1
                print(f"[{i+1}/{total}] id={rid} release_date_vigloo={date_v}")
        if id_d and not has_d:
            date_d = fetch_dramabox_release_date(id_d)
            time.sleep(delay_sec)
            if date_d:
                item["release_date_dramabox"] = date_d
                updated_d += 1
                print(f"[{i+1}/{total}] id={rid} release_date_dramabox={date_d}")
        if id_r and not has_r:
            date_r = fetch_reelshort_release_date(id_r)
            if date_r:
                time.sleep(delay_sec)
                item["release_date_reelshort"] = date_r
                updated_r += 1
                print(f"[{i+1}/{total}] id={rid} release_date_reelshort={date_r}")

        if (i + 1) % 50 == 0:
            print(f"  ... {i+1}/{total} 처리됨 (Vigloo:{updated_v} Dramabox:{updated_d} ReelShort:{updated_r})")

    out_path = DRAMAS_JSON if args.in_place else OUT_JSON
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(dramas, f, ensure_ascii=False, indent=2)

    updated_any = updated_v + updated_d + updated_r
    print(f"\n완료. Vigloo={updated_v}, Dramabox={updated_d}, ReelShort={updated_r} (총 {updated_any}/{total})")
    print(f"저장: {out_path}")
    if not args.in_place:
        print("원본 덮어쓰지 않음. 확인 후 dramas_with_release.json → dramas.json 복사하거나 --in-place 로 실행하세요.")
    if updated_any == 0 and total > 0:
        print("\n[참고] Vigloo/드라마박스는 페이지가 JS로 렌더링되면 HTML에 날짜가 없을 수 있습니다.")
        print("  - 한 번 실행: python crawl_release_dates.py --limit 1 --debug")
        print("  - scripts/vigloo_sample.html 을 열어 날짜가 어디에 있는지 확인 후 스크립트 선택자 수정.")
        print("  - 또는 Playwright로 브라우저 렌더링 후 HTML을 가져오는 방식으로 확장할 수 있습니다.")


if __name__ == "__main__":
    main()
