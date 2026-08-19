#!/usr/bin/env python3
"""Validate PkgLift's dependency-free GitHub Pages output."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlparse
import struct
import sys
import xml.etree.ElementTree as ET
import zlib

BASE_PATH = "/PkgLift/"
BASE_URL = "https://www.svensson.design/PkgLift/"
SOCIAL_IMAGE = BASE_URL + "assets/social-card.png"


class DocumentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.links: list[str] = []
        self.assets: list[str] = []
        self.title_parts: list[str] = []
        self.in_title = False
        self.descriptions: list[str] = []
        self.canonicals: list[str] = []
        self.h1_count = 0
        self.lang: str | None = None
        self.viewport = False
        self.meta_names: dict[str, list[str]] = {}
        self.meta_properties: dict[str, list[str]] = {}
        self.errors: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "html":
            self.lang = values.get("lang")
        elif tag == "title":
            self.in_title = True
        elif tag == "h1":
            self.h1_count += 1
        elif tag == "a":
            href = values.get("href")
            if href:
                self.links.append(href)
            if values.get("target") == "_blank":
                rel = set((values.get("rel") or "").split())
                if "noopener" not in rel:
                    self.errors.append("target=_blank link lacks noopener")
        elif tag in {"img", "script", "link"}:
            if tag == "img" and "alt" not in values:
                self.errors.append("img is missing alt")
            candidate = values.get("src") or values.get("href")
            if candidate:
                self.assets.append(candidate)
        elif tag == "meta":
            name = values.get("name")
            prop = values.get("property")
            content = values.get("content") or ""
            if name:
                self.meta_names.setdefault(name, []).append(content)
            if prop:
                self.meta_properties.setdefault(prop, []).append(content)
            if name == "description" and content:
                self.descriptions.append(content)
            if name == "viewport":
                self.viewport = True
        if tag == "link" and values.get("rel") == "canonical" and values.get("href"):
            self.canonicals.append(values["href"] or "")

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self.in_title = False

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_parts.append(data)


def local_target(site: Path, url: str, source: Path) -> Path | None:
    parsed = urlparse(url)
    if parsed.scheme or parsed.netloc or url.startswith(("mailto:", "tel:", "data:")):
        return None
    path = unquote(parsed.path)
    if not path or path == "/":
        return None
    if path.startswith(BASE_PATH):
        relative = path[len(BASE_PATH):]
        target = site / relative
    elif path.startswith("/"):
        return None
    else:
        target = source.parent / path
    if str(target).endswith("/") or target.is_dir() or not target.suffix:
        target = target / "index.html"
    return target


def one(values: dict[str, list[str]], key: str, expected: str | None = None) -> bool:
    candidates = values.get(key, [])
    return len(candidates) == 1 and bool(candidates[0].strip()) and (
        expected is None or candidates[0] == expected
    )


def validated_png_dimensions(path: Path) -> tuple[int, int]:
    """Validate the complete non-interlaced PNG stream, not only its header."""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise ValueError("not a PNG")

    offset = 8
    chunk_index = 0
    header: tuple[int, int, int, int, int, int, int] | None = None
    palette_entries: int | None = None
    compressed = bytearray()
    saw_end = False

    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError("truncated chunk header")
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunk_type = data[offset + 4:offset + 8]
        payload_start = offset + 8
        payload_end = payload_start + length
        crc_end = payload_end + 4
        if crc_end > len(data):
            raise ValueError(f"truncated {chunk_type.decode('ascii', errors='replace')} chunk")
        payload = data[payload_start:payload_end]
        expected_crc = struct.unpack(">I", data[payload_end:crc_end])[0]
        actual_crc = zlib.crc32(chunk_type + payload) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise ValueError(f"CRC mismatch in {chunk_type.decode('ascii', errors='replace')} chunk")

        if chunk_type == b"IHDR":
            if chunk_index != 0 or header is not None or length != 13:
                raise ValueError("invalid IHDR chunk")
            header = struct.unpack(">IIBBBBB", payload)
        elif chunk_type == b"PLTE":
            if not payload or len(payload) % 3 != 0:
                raise ValueError("invalid PLTE chunk")
            palette_entries = len(payload) // 3
        elif chunk_type == b"IDAT":
            compressed.extend(payload)
        elif chunk_type == b"IEND":
            if length != 0:
                raise ValueError("invalid IEND chunk")
            saw_end = True
            offset = crc_end
            if offset != len(data):
                raise ValueError("data found after IEND")
            break

        offset = crc_end
        chunk_index += 1

    if header is None or not saw_end or not compressed:
        raise ValueError("missing IHDR, IDAT, or IEND chunk")

    width, height, bit_depth, color_type, compression, filtering, interlace = header
    if width <= 0 or height <= 0:
        raise ValueError("invalid dimensions")
    if compression != 0 or filtering != 0 or interlace != 0:
        raise ValueError("unsupported compression, filter, or interlace method")

    allowed_depths = {
        0: {1, 2, 4, 8, 16},
        2: {8, 16},
        3: {1, 2, 4, 8},
        4: {8, 16},
        6: {8, 16},
    }
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
    if color_type not in allowed_depths or bit_depth not in allowed_depths[color_type]:
        raise ValueError("invalid color type or bit depth")
    if color_type == 3 and (
        palette_entries is None or palette_entries > 2 ** bit_depth
    ):
        raise ValueError("indexed PNG has an invalid palette")

    row_bytes = (width * channels[color_type] * bit_depth + 7) // 8
    expected_size = height * (row_bytes + 1)
    try:
        decompressor = zlib.decompressobj()
        decoded = decompressor.decompress(bytes(compressed), expected_size + 1)
    except zlib.error as error:
        raise ValueError(f"invalid IDAT stream: {error}") from error
    if len(decoded) != expected_size or not decompressor.eof or decompressor.unused_data:
        raise ValueError("IDAT stream has an invalid decoded length or trailer")
    for row in range(height):
        if decoded[row * (row_bytes + 1)] > 4:
            raise ValueError("invalid scanline filter")

    return width, height


def validate(site: Path) -> list[str]:
    errors: list[str] = []
    required = [
        "index.html", "404.html", ".nojekyll", "robots.txt", "sitemap.xml",
        "site.webmanifest", "assets/styles.css", "assets/site.js", "assets/logo.svg",
        "assets/favicon.svg", "assets/social-card.png",
        "assets/github-social-preview.png",
        "cocoapods-to-swiftpm/index.html", "safe-migration/index.html",
        "compatibility/index.html", "case-study/index.html",
        "pilots/index.html", "troubleshooting/index.html", "registry/index.html",
    ]
    for relative in required:
        if not (site / relative).exists():
            errors.append(f"missing required file: {relative}")

    social_path = site / "assets/social-card.png"
    if social_path.exists():
        try:
            if validated_png_dimensions(social_path) != (1200, 630):
                errors.append("social-card.png must be exactly 1200x630")
        except ValueError as error:
            errors.append(f"invalid social-card.png: {error}")

    github_social_path = site / "assets/github-social-preview.png"
    if github_social_path.exists():
        try:
            if validated_png_dimensions(github_social_path) != (1280, 640):
                errors.append("github-social-preview.png must be exactly 1280x640")
        except ValueError as error:
            errors.append(f"invalid github-social-preview.png: {error}")

    html_files = sorted(site.rglob("*.html"))
    canonical_seen: set[str] = set()
    title_seen: set[str] = set()
    for file in html_files:
        parser = DocumentParser()
        text = file.read_text(encoding="utf-8")
        parser.feed(text)
        label = file.relative_to(site)
        title = "".join(parser.title_parts).strip()
        if not title:
            errors.append(f"{label}: missing title")
        elif title in title_seen:
            errors.append(f"{label}: duplicate title {title!r}")
        title_seen.add(title)
        if len(parser.descriptions) != 1 or not parser.descriptions[0].strip():
            errors.append(f"{label}: requires exactly one non-empty meta description")
        if len(parser.canonicals) != 1:
            errors.append(f"{label}: requires exactly one canonical URL")
        else:
            canonical = parser.canonicals[0]
            if not canonical.startswith(BASE_URL):
                errors.append(f"{label}: canonical is outside {BASE_URL}")
            if canonical in canonical_seen:
                errors.append(f"{label}: duplicate canonical {canonical}")
            canonical_seen.add(canonical)
        if parser.h1_count != 1:
            errors.append(f"{label}: expected one h1, found {parser.h1_count}")
        if parser.lang != "en":
            errors.append(f"{label}: html lang must be en")
        if not parser.viewport:
            errors.append(f"{label}: missing viewport meta")
        if not one(parser.meta_properties, "og:title"):
            errors.append(f"{label}: missing unique og:title")
        if not one(parser.meta_properties, "og:description"):
            errors.append(f"{label}: missing unique og:description")
        if not one(parser.meta_properties, "og:url"):
            errors.append(f"{label}: missing unique og:url")
        if not one(parser.meta_properties, "og:image", SOCIAL_IMAGE):
            errors.append(f"{label}: og:image must use the canonical social card")
        if not one(parser.meta_properties, "og:image:width", "1200"):
            errors.append(f"{label}: og:image:width must be 1200")
        if not one(parser.meta_properties, "og:image:height", "630"):
            errors.append(f"{label}: og:image:height must be 630")
        if not one(parser.meta_names, "twitter:card", "summary_large_image"):
            errors.append(f"{label}: twitter:card must be summary_large_image")
        if not one(parser.meta_names, "twitter:image", SOCIAL_IMAGE):
            errors.append(f"{label}: twitter:image must use the canonical social card")
        if label.name == "404.html" and not one(parser.meta_names, "robots", "noindex, follow"):
            errors.append("404.html: must be noindex, follow")
        if "http://" in text:
            errors.append(f"{label}: contains insecure http:// URL")
        errors.extend(f"{label}: {error}" for error in parser.errors)
        for url in parser.links + parser.assets:
            target = local_target(site, url, file)
            if target is not None and not target.exists():
                errors.append(f"{label}: broken local reference {url} -> {target.relative_to(site)}")

    try:
        root = ET.parse(site / "sitemap.xml").getroot()
        namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
        urls = {node.text for node in root.findall("s:url/s:loc", namespace)}
        expected = {
            BASE_URL,
            BASE_URL + "cocoapods-to-swiftpm/",
            BASE_URL + "safe-migration/",
            BASE_URL + "compatibility/",
            BASE_URL + "case-study/",
            BASE_URL + "pilots/",
            BASE_URL + "troubleshooting/",
            BASE_URL + "registry/",
        }
        if urls != expected:
            errors.append(f"sitemap URLs differ: missing={expected - urls}, extra={urls - expected}")
    except (ET.ParseError, OSError) as error:
        errors.append(f"invalid sitemap.xml: {error}")

    robots = (site / "robots.txt").read_text(encoding="utf-8")
    if f"Sitemap: {BASE_URL}sitemap.xml" not in robots:
        errors.append("robots.txt does not reference the canonical sitemap")

    for file in site.rglob("*"):
        if file.is_file() and file.stat().st_size > 500_000:
            errors.append(f"unexpected large file: {file.relative_to(site)} ({file.stat().st_size} bytes)")

    return errors


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", type=Path, required=True)
    args = parser.parse_args()
    errors = validate(args.site.resolve())
    if errors:
        print("Static site validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        raise SystemExit(1)
    html_count = len(list(args.site.rglob("*.html")))
    print(f"Validated {html_count} HTML pages, social metadata, and all local references.")


if __name__ == "__main__":
    main()
