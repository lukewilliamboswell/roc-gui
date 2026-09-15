#!/usr/bin/env python3
"""Build the documentation with Asciidoctor isolated in Docker."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
DEFAULT_OUT = ROOT / ".docs-out"
IMAGE = "roc-gui-docs:local"


def run(*command: str, **kwargs: object) -> None:
    subprocess.run(command, cwd=ROOT, check=True, **kwargs)


def build_inside_container(output: Path, want_pdf: bool) -> None:
    site = output / "site"
    if site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True)

    # The theme is embedded in each page rather than linked, so a page keeps
    # working when opened straight from disk and Rouge's own stylesheet is
    # never left dangling by `linkcss`.
    theme_dir = DOCS / "theme"
    theme = ["-a", f"stylesdir={theme_dir}", "-a", "stylesheet=roc-gui.css"]
    diagram = [
        "-r", "asciidoctor-diagram",
        "-r", "/documents/rouge_roc.rb",
        "-a", "mermaid-format=svg",
        "-a", "mermaid-puppeteer-config=/documents/.github/mermaid-puppeteer.json",
    ]
    for source in sorted(DOCS.glob("*.adoc")):
        run(
            "asciidoctor", *diagram, *theme, "-a", "source-highlighter=rouge",
            "-a", "toc=left", "-a", "sectanchors", "-D", str(site), str(source),
        )

    images = DOCS / "images"
    if images.is_dir():
        shutil.copytree(images, site / "images", dirs_exist_ok=True)
    architecture = site / "architecture.html"
    architecture_html = architecture.read_text(encoding="utf-8") if architecture.is_file() else ""
    if '<img src="diag-mermaid-' not in architecture_html or ".svg" not in architecture_html:
        raise SystemExit("architecture Mermaid diagram was not rendered to SVG")
    index_html = (site / "index.html").read_text(encoding="utf-8")
    if "Roc GUI documentation theme" not in index_html:
        raise SystemExit("custom stylesheet was not embedded in the page")
    roc_html = (site / "getting-started.html").read_text(encoding="utf-8")
    scm_html = (site / "specifications.html").read_text(encoding="utf-8")
    if 'data-lang="roc"' not in roc_html or '<span class="k">' not in roc_html:
        raise SystemExit("Roc source was not syntax highlighted")
    if 'data-lang="scheme"' not in scm_html or '<span class="nf">' not in scm_html:
        raise SystemExit("SCM source was not syntax highlighted")
    print(f"Site: {site / 'index.html'}")

    if want_pdf:
        manual = output / "roc-gui.pdf"
        run(
            "asciidoctor-pdf", *diagram[:-2],
            "-a", f"pdf-themesdir={theme_dir}", "-a", "pdf-theme=roc-gui",
            "-a", "mermaid-format=png",
            "-a", "mermaid-puppeteer-config=/documents/.github/mermaid-puppeteer.json",
            "-o", str(manual), str(DOCS / "index.adoc"),
        )
        if not manual.is_file() or not manual.stat().st_size:
            raise SystemExit("PDF manual was not generated")
        shutil.copy2(manual, site / manual.name)
        print(f"Manual: {manual}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", action="store_true", help="also build the standalone PDF manual")
    parser.add_argument("--inside-container", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = Path(os.environ.get("DOCS_OUT", DEFAULT_OUT)).resolve()

    if args.inside_container:
        build_inside_container(output, args.pdf)
        return

    if shutil.which("docker") is None:
        raise SystemExit("Docker is required to build the documentation")
    run("docker", "build", "--tag", IMAGE, "--file", ".github/docs.Dockerfile", ".")
    command = [
        "docker", "run", "--rm", "--user", f"{os.getuid()}:{os.getgid()}",
        "--env", "XDG_CACHE_HOME=/tmp", "--env", "XDG_CONFIG_HOME=/tmp",
        "--volume", f"{ROOT}:/documents", "--workdir", "/documents", IMAGE,
        "python3", "scripts/build_docs.py", "--inside-container",
    ]
    if args.pdf:
        command.append("--pdf")
    run(*command)


if __name__ == "__main__":
    main()
