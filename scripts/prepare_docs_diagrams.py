#!/usr/bin/env python3
"""Prepare Mermaid assets when their authored source changes, before rendering."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import tempfile
from pathlib import Path
from xml.dom import minidom


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
MERMAID_VERSION = "11.16.0"
MERMAID = re.compile(r"^\[mermaid\]\n\.\.\.\.\n(.*?)^\.\.\.\.\s*$", re.MULTILINE | re.DOTALL)


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def static_svg(source: str) -> str:
    document = minidom.parseString(source)
    # Mermaid includes stock icon definitions even when no participant uses
    # them. Referenced symbols are left intact for the renderer to validate.
    for symbol in list(document.getElementsByTagName("symbol")):
        if f"#{symbol.getAttribute('id')}" not in source:
            symbol.parentNode.removeChild(symbol)
    for element in document.getElementsByTagName("*"):
        # Sequence actors carry editor-only metadata. These presentation
        # attributes are CSS properties in the shared static SVG profile.
        for metadata in ("name", "data-type", "data-from", "data-to"):
            if element.hasAttribute(metadata):
                element.removeAttribute(metadata)
        for property_name in ("alignment-baseline", "fill-rule", "clip-rule"):
            if element.hasAttribute(property_name):
                value = element.getAttribute(property_name)
                style = element.getAttribute("style").rstrip(";")
                element.setAttribute("style", f"{style};{property_name}:{value}")
                element.removeAttribute(property_name)
    return document.documentElement.toxml()


def prepare() -> None:
    version = subprocess.check_output(["mmdc", "--version"], text=True).strip()
    if version != MERMAID_VERSION:
        raise SystemExit(f"mmdc {MERMAID_VERSION} is required; found {version}")

    assets = DOCS / "images" / "diagrams"
    assets.mkdir(parents=True, exist_ok=True)
    diagrams = []
    # Stage every asset before replacing the manifest. A failed authoring run
    # cannot register a partial set as a complete preparation.
    with tempfile.TemporaryDirectory(prefix="roc-gui-diagrams-") as temporary:
        staging = Path(temporary)
        for source in sorted(DOCS.glob("*.adoc")):
            for index, match in enumerate(MERMAID.finditer(source.read_text()), 1):
                body = match.group(1).encode()
                name = f"{source.stem}-{index}"
                diagram = staging / f"{name}.mmd"
                diagram.write_bytes(body)
                entry = {"source_sha256": digest(body), "href": f"images/diagrams/{name}.png"}
                for extension in ("png", "svg"):
                    output = staging / f"{name}.{extension}"
                    subprocess.run(
                        [
                            "mmdc", "--input", str(diagram), "--output", str(output),
                            "--configFile", str(DOCS / "diagrams" / "mermaid-config.json"),
                            "--puppeteerConfigFile", str(ROOT / ".github" / "mermaid-puppeteer.json"),
                            "--backgroundColor", "#FFFFFF", "--scale", "2", "--width", "1600",
                        ],
                        check=True,
                    )
                    if extension == "svg":
                        output.write_text(static_svg(output.read_text()))
                    entry[extension] = f"images/diagrams/{name}.{extension}"
                    entry[f"{extension}_sha256"] = digest(output.read_bytes())
                diagrams.append(entry)
        for entry in diagrams:
            for extension in ("png", "svg"):
                filename = Path(entry[extension]).name
                (assets / filename).write_bytes((staging / filename).read_bytes())
    manifest = {"schema_version": 2, "diagrams": diagrams}
    (DOCS / "prepared-diagrams.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {len(diagrams)} Mermaid diagrams")


if __name__ == "__main__":
    prepare()
