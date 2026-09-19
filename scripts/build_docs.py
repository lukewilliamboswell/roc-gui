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


def build_inside_container(output: Path, want_pdf: bool, docs_version: str) -> None:
    site = output / "site"
    if site.exists():
        shutil.rmtree(site)
    site.mkdir(parents=True)

    # The theme is embedded in each page rather than linked, so a page keeps
    # working when opened straight from disk and Rouge's own stylesheet is
    # never left dangling by `linkcss`.
    theme_dir = DOCS / "theme"
    fonts_dir = theme_dir / "fonts"
    theme = ["-a", f"stylesdir={theme_dir}", "-a", "stylesheet=roc-gui.css"]
    diagram = [
        "-r", "asciidoctor-diagram",
        "-r", "/documents/docs/rouge_roc.rb",
        "-a", "mermaid-format=svg",
        # Diagrams carry the manual's palette and sit on the same warm
        # ground as the page, so no white plate shows around them.
        "-a", "mermaid-background=FAFAF7",
        "-a", "mermaid-scale=2",
        "-a", f"mermaid-config={DOCS / 'theme' / 'mermaid-config.json'}",
        "-a", "mermaid-puppeteer-config=/documents/.github/mermaid-puppeteer.json",
    ]
    version = ["-a", f"docs-version={docs_version}"]
    for source in sorted(DOCS.glob("*.adoc")):
        run(
            "asciidoctor", *diagram, *theme, *version, "-a", "source-highlighter=rouge",
            "-a", "toc=left", "-a", "sectanchors", "-D", str(site), str(source),
        )

    images = DOCS / "images"
    if images.is_dir():
        shutil.copytree(images, site / "images", dirs_exist_ok=True)
    # The stylesheet is embedded in each page, so its @font-face URLs are
    # resolved relative to the page. The faces ship beside the pages.
    if fonts_dir.is_dir():
        shutil.copytree(fonts_dir, site / "fonts", dirs_exist_ok=True)
    for face in ("SpaceGrotesk-Regular.ttf", "PlusJakartaSans-Regular.ttf"):
        if not (site / "fonts" / face).is_file():
            raise SystemExit(f"web font {face} was not published beside the pages")
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
            "asciidoctor-pdf", *diagram[:-2], *version,
            "-a", "source-highlighter=rouge",
            "-a", "rouge-style=rocgui",
            "-a", f"pdf-themesdir={theme_dir}",
            "-a", "pdf-theme=roc-gui",
            # Two levels in print. At three, the contents outran the pages
            # asciidoctor-pdf reserves for it and the preface was drawn over
            # its last page. The web contents keeps all three.
            "-a", "toclevels=2",
            # Vendored faces first, then the gem's own directory so the
            # bundled M+ 1mn mono and fallback faces stay resolvable.
            "-a", f"pdf-fontsdir={fonts_dir};GEM_FONTS_DIR",
            "-a", "mermaid-format=png",
            "-a", "mermaid-puppeteer-config=/documents/.github/mermaid-puppeteer.json",
            "-o", str(manual), str(DOCS / "index.adoc"),
        )
        if not manual.is_file() or not manual.stat().st_size:
            raise SystemExit("PDF manual was not generated")
        shutil.copy2(manual, site / manual.name)
        print(f"Manual: {manual}")


def build_api_reference(site: Path, roc: str) -> None:
    """Generate the platform's API reference beside the manual.

    The compiler is the only authority on the exposed modules and their
    signatures, so the reference is generated rather than transcribed, and
    generated here so prose and signatures ship as one site. It runs outside
    the container because the compiler is not part of the Asciidoctor image.
    """
    if shutil.which(roc) is None:
        raise SystemExit(f"{roc} is required to generate the platform API reference")
    api = site / "api"
    if api.exists():
        shutil.rmtree(api)
    run(roc, "docs", "platform/main.roc", f"--output={api}")
    if not (api / "index.html").is_file():
        raise SystemExit("platform API reference was not generated")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pdf", action="store_true", help="also build the standalone PDF manual")
    parser.add_argument("--roc", default="roc", help="compiler that generates the API reference")
    parser.add_argument("--docs-version", default="unreleased",
                        help="platform version this manual documents")
    parser.add_argument("--inside-container", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()
    output = Path(os.environ.get("DOCS_OUT", DEFAULT_OUT)).resolve()

    if args.inside_container:
        build_inside_container(output, args.pdf, args.docs_version)
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
    command += ["--docs-version", args.docs_version]
    if args.pdf:
        command.append("--pdf")
    run(*command)
    # After the container, so the generated reference is not removed with the
    # site tree the container rebuilds from scratch.
    build_api_reference(output / "site", args.roc)


if __name__ == "__main__":
    main()
