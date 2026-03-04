#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
비글루, 릴숏, 드라마박스 목록 페이지 전체 크롤링.
각 URL별로 페이지네이션 끝까지 순회하며 드라마 링크를 수집합니다.

사용법:
  pip install -r requirements-crawler.txt
  python crawl_drama_listings.py [--site vigloo|reelshort|dramabox] [--delay 1.5]

출력: scripts/crawled_listings/{site}_{slug}.json (URL별 수집 결과)
"""

import json
import re
import time
from pathlib import Path
from urllib.parse import urljoin, urlparse

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("pip install -r requirements-crawler.txt 를 먼저 실행하세요.")
    raise

ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "crawled_listings"
DELAY = 1.5
REQUEST_TIMEOUT = 20
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9,ko;q=0.8",
}

# 크롤링 대상 URL (각 항목: (사이트명, URL, 페이지네이션 방식))
# 페이지네이션: "none" | "path" (경로에 /2, /3 붙음) | "path_genres" (드라마박스: /genres/0/2)
CRAWL_TARGETS = [
    # --- 비글루 (한국어 4개 탭, 페이지 없음 또는 1페이지만) ---
    ("vigloo", "https://www.vigloo.com/ko", "none"),
    ("vigloo", "https://www.vigloo.com/ko?tab=recommended", "none"),
    ("vigloo", "https://www.vigloo.com/ko?tab=all", "none"),
    ("vigloo", "https://www.vigloo.com/ko?tab=ranking", "none"),
    # --- 릴숏 KO ---
    ("reelshort", "https://www.reelshort.com/ko", "none"),
    ("reelshort", "https://www.reelshort.com/ko/tags/movie-actors", "path"),
    ("reelshort", "https://www.reelshort.com/ko/tags/movie-actresses", "path"),
    ("reelshort", "https://www.reelshort.com/ko/tags/movie-identities", "path"),
    ("reelshort", "https://www.reelshort.com/ko/tags/story-beats", "path"),
    # --- 릴숏 EN ---
    ("reelshort", "https://www.reelshort.com/en", "none"),
    ("reelshort", "https://www.reelshort.com/tags/movie-actors", "path"),
    ("reelshort", "https://www.reelshort.com/tags/movie-actresses", "path"),
    ("reelshort", "https://www.reelshort.com/tags/movie-identities", "path"),
    ("reelshort", "https://www.reelshort.com/tags/story-beats", "path"),
    # --- 릴숏 JA ---
    ("reelshort", "https://www.reelshort.com/ja", "none"),
    ("reelshort", "https://www.reelshort.com/ja/tags/movie-actors", "path"),
    ("reelshort", "https://www.reelshort.com/ja/tags/movie-actresses", "path"),
    ("reelshort", "https://www.reelshort.com/ja/tags/movie-identities", "path"),
    ("reelshort", "https://www.reelshort.com/ja/tags/story-beats", "path"),
    # --- 드라마박스 KO ---
    ("dramabox", "https://www.dramaboxdb.com/ko", "none"),
    ("dramabox", "https://www.dramaboxdb.com/ko/genres", "path_genres"),
    # --- 드라마박스 EN ---
    ("dramabox", "https://www.dramaboxdb.com/", "none"),
    ("dramabox", "https://www.dramaboxdb.com/genres", "path_genres"),
    # --- 드라마박스 JA ---
    ("dramabox", "https://www.dramaboxdb.com/ja", "none"),
    ("dramabox", "https://www.dramaboxdb.com/ja/genres", "path_genres"),
]


def fetch(url: str) -> str | None:
    try:
        r = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        return r.text
    except Exception as e:
        print(f"  [ERR] {url}: {e}")
        return None


def extract_vigloo_links(html: str, base_url: str) -> list[dict]:
    """비글루: /ko/content/ID 또는 /en/content/ID 링크 추출."""
    soup = BeautifulSoup(html, "html.parser")
    out = []
    seen = set()
    for a in soup.find_all("a", href=True):
        href = a.get("href", "").strip()
        if "/content/" in href:
            full = urljoin(base_url, href)
            if full not in seen:
                seen.add(full)
                m = re.search(r"/content/(\d+)", full)
                out.append({"url": full, "id_vigloo": m.group(1) if m else None, "title": (a.get_text() or "").strip()[:200]})
    # __NEXT_DATA__ 내 programId 등도 수집
    for script in soup.find_all("script", id="__NEXT_DATA__"):
        if script.string:
            try:
                data = json.loads(script.string)
                props = data.get("props", {}).get("pageProps", {})
                for key in ["program", "programs", "list", "contents"]:
                    val = props.get(key)
                    if isinstance(val, dict) and "id" in val:
                        pid = str(val["id"])
                        title = val.get("title") or val.get("name") or ""
                        url = f"https://www.vigloo.com/ko/content/{pid}"
                        if url not in seen:
                            seen.add(url)
                            out.append({"url": url, "id_vigloo": pid, "title": str(title)[:200]})
                    elif isinstance(val, list):
                        for item in val:
                            if isinstance(item, dict) and "id" in item:
                                pid = str(item["id"])
                                title = item.get("title") or item.get("name") or ""
                                url = f"https://www.vigloo.com/ko/content/{pid}"
                                if url not in seen:
                                    seen.add(url)
                                    out.append({"url": url, "id_vigloo": pid, "title": str(title)[:200]})
            except json.JSONDecodeError:
                pass
    return out


def extract_dramabox_links(html: str, base_url: str) -> list[dict]:
    """드라마박스: /movie/ID/... 링크 추출."""
    soup = BeautifulSoup(html, "html.parser")
    out = []
    seen = set()
    for a in soup.find_all("a", href=True):
        href = a.get("href", "").strip()
        m = re.search(r"/movie/(\d+)(?:/|$)", href)
        if m:
            full = urljoin(base_url, href)
            if full not in seen:
                seen.add(full)
                out.append({"url": full, "id_dramabox": m.group(1), "title": (a.get_text() or "").strip()[:200]})
    return out


def extract_reelshort_links(html: str, base_url: str) -> list[dict]:
    """릴숏: /movie/슬러그-ID 또는 /ko/movie/... 링크 추출."""
    soup = BeautifulSoup(html, "html.parser")
    out = []
    seen = set()
    for a in soup.find_all("a", href=True):
        href = a.get("href", "").strip()
        # /movie/title-slug-24hexid
        m = re.search(r"/movie/([^/]+)-([a-f0-9]{24})$", href, re.I)
        if m:
            full = urljoin(base_url, href)
            if full not in seen:
                seen.add(full)
                out.append({"url": full, "id_reelshort": m.group(2), "title": (a.get_text() or "").strip()[:200]})
    return out


def get_next_page_url(base: str, page: int, style: str) -> str:
    if style == "path":
        # reelshort: .../movie-actors/2
        return base.rstrip("/") + "/" + str(page)
    if style == "path_genres":
        # dramabox: .../genres/0/2
        return base.rstrip("/") + "/0/" + str(page)
    return base


def get_last_page_from_html(html: str, style: str) -> int | None:
    """페이지 HTML에서 마지막 페이지 번호 추출 (없으면 None)."""
    if not html:
        return None
    # 예: 1 2 3 ... 36 또는 ... 57
    if style == "path":
        m = re.search(r"\.\.\.\s*\[?(\d+)\]?|/(\d+)\s*[<\s]|page.*?(\d+)", html)
        if m:
            return int(m.group(1) or m.group(2) or m.group(3))
    if style == "path_genres":
        m = re.search(r"\.\.\.\s*\[?(\d+)\]?|/0/(\d+)[\"'\s/]|1/(\d+)", html)
        if m:
            return int(m.group(1) or m.group(2) or m.group(3))
    return None


def crawl_one_url(site: str, url: str, pagination: str, delay: float) -> list[dict]:
    """단일 URL(및 해당 URL의 모든 페이지) 크롤링."""
    all_items = []
    page = 1
    base = url.rstrip("/")
    while True:
        if page == 1:
            page_url = base
        else:
            page_url = get_next_page_url(base, page, pagination)
        html = fetch(page_url)
        time.sleep(delay)
        if not html:
            break
        if site == "vigloo":
            items = extract_vigloo_links(html, base)
        elif site == "dramabox":
            items = extract_dramabox_links(html, base)
        elif site == "reelshort":
            items = extract_reelshort_links(html, base)
        else:
            items = []
        if not items and page > 1:
            break
        all_items.extend(items)
        if pagination == "none":
            break
        # 다음 페이지 존재 여부: 링크에 page+1 이 있거나, 마지막 페이지 번호 확인
        last = get_last_page_from_html(html, pagination)
        if last is not None and page >= last:
            break
        # 다음 페이지 링크가 HTML에 없으면 빈 리스트가 나올 수 있음
        if page > 1 and not items:
            break
        page += 1
        # 무한 방지: 500페이지 이상이면 중단
        if page > 500:
            print(f"  [WARN] {url}: 500페이지 제한 도달")
            break
    return all_items


def slug_from_url(url: str) -> str:
    """URL을 파일명용 슬러그로."""
    from urllib.parse import urlparse, parse_qs
    p = urlparse(url)
    path = (p.path or "").strip("/").replace("/", "_")
    q = parse_qs(p.query)
    if q:
        path += "_" + "_".join(f"{k}_{v[0]}" for k, v in sorted(q.items())[:3])
    return re.sub(r"[^\w\-]", "", path)[:80] or "index"


def main():
    import argparse
    parser = argparse.ArgumentParser(description="비글루/릴숏/드라마박스 목록 전체 크롤링")
    parser.add_argument("--site", choices=["vigloo", "reelshort", "dramabox"], help="특정 사이트만 크롤링")
    parser.add_argument("--delay", type=float, default=DELAY, help="요청 간 딜레이(초)")
    parser.add_argument("--dry-run", action="store_true", help="URL만 출력하고 크롤링 안 함")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    targets = [t for t in CRAWL_TARGETS if not args.site or t[0] == args.site]

    if args.dry_run:
        for site, url, pag in targets:
            print(f"{site}\t{pag}\t{url}")
        return

    for site, url, pagination in targets:
        slug = slug_from_url(url)
        out_file = OUT_DIR / f"{site}_{slug}.json"
        print(f"[{site}] {url} (pagination={pagination}) ...")
        items = crawl_one_url(site, url, pagination, args.delay)
        # URL 기준 중복 제거
        by_url = {x["url"]: x for x in items}
        unique = list(by_url.values())
        out_file.write_text(json.dumps(unique, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"  -> {len(unique)}개 저장: {out_file.name}")


if __name__ == "__main__":
    main()
