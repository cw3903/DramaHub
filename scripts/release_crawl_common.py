#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
릴리즈 데이트 크롤러 3개 스크립트에서 공통으로 쓰는 fetch/파싱 로직.
"""

import re
from pathlib import Path

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("pip install -r requirements-crawler.txt 를 먼저 실행하세요.")
    raise

ROOT = Path(__file__).resolve().parent.parent
DRAMAS_JSON = ROOT / "assets" / "data" / "dramas.json"
REQUEST_TIMEOUT = 15
DELAY_DEFAULT = 1.5

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9,ko;q=0.8",
}

_dramabox_unreachable_warned = False


def normalize_date(s: str | None) -> str | None:
    if not s or not s.strip():
        return None
    s = s.strip()
    if re.match(r"^\d{4}-\d{2}-\d{2}$", s):
        return s
    m = re.search(r"(\d{4})-(\d{2})-(\d{2})", s)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    m = re.search(r"\b(20\d{2}|19\d{2})\b", s)
    if m:
        return f"{m.group(1)}-01-01"
    return None


def _extract_date_from_text(text: str) -> str | None:
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
    if not text:
        return None
    for key in ["datePublished", "releaseDate", "release_date", "releasedAt", "published_at", "created_at", "updated_at", "year", "aired", "firstShelfTime", "shelfTime"]:
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
        for tag in soup.find_all(attrs={"datetime": True}):
            d = normalize_date(tag.get("datetime"))
            if d:
                return d
        for tag in soup.find_all(attrs=lambda a: a and any(k.startswith("data-") for k in a)):
            for k, v in tag.attrs.items():
                if v and ("date" in k or "release" in k or "time" in k):
                    d = normalize_date(str(v))
                    if d:
                        return d
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
        for meta in soup.find_all("meta", attrs={"property": True}):
            p = (meta.get("property") or "").lower()
            c = meta.get("content")
            if c and ("date" in p or "release" in p or "time" in p):
                d = normalize_date(c)
                if d:
                    return d
        return _extract_date_from_text(soup.get_text())
    except Exception as e:
        print(f"  [Vigloo {id_vigloo}] {e}")
        return None


def _extract_dramabox_date_from_html(html: str, id_dramabox: str) -> str | None:
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
    """DramaBox DB 페이지에서 날짜 추출. www / 비www 둘 다 시도 (DNS 환경에 따라 하나만 되는 경우 대비)."""
    global _dramabox_unreachable_warned
    if not id_dramabox or not id_dramabox.strip():
        return None
    id_ = id_dramabox.strip()
    for host in ("https://www.dramaboxdb.com", "https://dramaboxdb.com"):
        url = f"{host}/movie/{id_}/"
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
            if not _dramabox_unreachable_warned:
                _dramabox_unreachable_warned = True
                print(f"  [Dramabox] dramaboxdb.com 연결 불가 (DNS/네트워크). 휴대폰 핫스팟·VPN 시도 권장. (에러: {e})")
            continue
    return None


def fetch_reelshort_release_date(id_reelshort: str) -> str | None:
    """ReelShort 상세 페이지에서 날짜 추출. URL: https://www.reelshort.com/movie/{id}"""
    if not id_reelshort or not id_reelshort.strip():
        return None
    id_ = id_reelshort.strip()
    url = f"https://www.reelshort.com/movie/{id_}"
    try:
        r = requests.get(url, headers=HEADERS, timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        html = r.text
        soup = BeautifulSoup(html, "html.parser")
        # 1) meta (og:published_time 등)
        for meta in soup.find_all("meta", attrs={"property": True}):
            p = (meta.get("property") or "").lower()
            c = meta.get("content")
            if c and ("date" in p or "release" in p or "time" in p):
                d = normalize_date(c)
                if d:
                    return d
        for meta in soup.find_all("meta", attrs={"name": True}):
            n = (meta.get("name") or "").lower()
            c = meta.get("content")
            if c and ("date" in n or "release" in n):
                d = normalize_date(c)
                if d:
                    return d
        # 2) datetime 속성
        for tag in soup.find_all(attrs={"datetime": True}):
            d = normalize_date(tag.get("datetime"))
            if d:
                return d
        # 3) script 내 JSON (SPA 데이터)
        for script in soup.find_all("script", type=re.compile(r"application/(ld\+)?json")):
            if script.string:
                d = _extract_date_from_json_like(script.string)
                if d:
                    return d
        for script in soup.find_all("script"):
            if script.string and ("release" in script.string.lower() or "date" in script.string or "publish" in script.string or "createdAt" in script.string):
                d = _extract_date_from_json_like(script.string)
                if d:
                    return d
        # 4) 본문 텍스트에서 YYYY-MM-DD
        return _extract_date_from_text(soup.get_text())
    except Exception as e:
        print(f"  [ReelShort {id_}] {e}")
        return None
