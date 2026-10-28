#!/usr/bin/env python3
"""Check the published manual's links, source text and API handoff."""

from __future__ import annotations

import argparse
from collections import Counter
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit


ROOT = Path(__file__).resolve().parents[1]
SOURCES = re.compile(
    r"(?:^\[(?P<kind>source(?:,(?P<lang>[^\]\n]+))?|mermaid)\]\n)?"
    r"^(?P<fence>----|\.\.\.\.)\n(?P<body>.*?)^(?P=fence)[ \t]*$",
    re.MULTILINE | re.DOTALL,
)


class Page(HTMLParser):
    def __init__(self, source: str) -> None:
        super().__init__(convert_charrefs=True)
        self.ids: list[str] = []
        self.links: list[str] = []
        self.listings: list[tuple[str, str]] = []
        self._language: str | None = None
        self._text: list[str] = []
        self.feed(source)

    def handle_starttag(self, tag: str, attributes: list[tuple[str, str | None]]) -> None:
        attrs = dict(attributes)
        if attrs.get("id"):
            self.ids.append(attrs["id"])
        for name in ("href", "src"):
            if attrs.get(name):
                self.links.append(attrs[name])
        if tag == "code" and "data-lang" in attrs:
            self._language = attrs["data-lang"]
            self._text = []

    def handle_data(self, text: str) -> None:
        if self._language is not None:
            self._text.append(text)

    def handle_endtag(self, tag: str) -> None:
        if tag == "code" and self._language is not None:
            self.listings.append((self._language, "".join(self._text)))
            self._language = None


def check(output: Path) -> None:
    site = output / "site"
    pages = {p.name: Page(p.read_text()) for p in site.glob("*.html")}
    links = 0
    for route, page in pages.items():
        assert len(page.ids) == len(set(page.ids)), f"duplicate IDs: {route}"
        for href in page.links:
            url = urlsplit(href)
            if url.scheme or url.netloc:
                continue
            target = (site / unquote(url.path or route)).resolve()
            assert target.is_relative_to(site.resolve()), f"link leaves site: {route}: {href}"
            assert target.exists(), f"missing target: {route}: {href}"
            if url.fragment and target.name in pages:
                assert unquote(url.fragment) in pages[target.name].ids, f"missing fragment: {route}: {href}"
            links += 1
    expected = Counter(
        (match.group("lang") or "", match.group("body"))
        for source in (ROOT / "docs").rglob("*.adoc")
        for match in SOURCES.finditer(source.read_text())
        if match.group("kind") != "mermaid"
    )
    assert Counter(pages["index.html"].listings) == expected, "manual source listing bytes changed"
    assert (site / "api/index.html").stat().st_size > 0, "compiler API reference missing"
    assert (site / "index.md").is_file() and (site / "llms.txt").is_file(), "Markdown discovery missing"
    pdf = (output / "roc-gui.pdf").read_bytes()
    assert pdf.startswith(b"%PDF-") and (site / "roc-gui.pdf").read_bytes() == pdf, "PDF handoff differs"
    manifest = json.loads((ROOT / "docs/prepared-diagrams.json").read_text())
    for diagram in manifest["diagrams"]:
        for extension in ("png", "svg"):
            asset = diagram[extension]
            assert (site / asset).read_bytes() == (ROOT / "docs" / asset).read_bytes(), f"asset changed: {asset}"
    print(f"Checked {len(pages)} pages, {links} local links, {sum(expected.values())} source listings, API and PDF")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / ".docs-out")
    check(parser.parse_args().output)
