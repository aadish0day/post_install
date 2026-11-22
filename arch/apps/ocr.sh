#!/usr/bin/env python3
"""
High-Fidelity Tesseract OCR Processor (v3.0)

What changed vs v2:
- Markdown export is actually wired up (--md), and works on any document
- Entity repair only touches known/declared entities, so `int size;` stays intact
- Braces, brackets and page numbers are no longer deleted from real content
- Repeating headers/footers are detected automatically (plus optional regex filters)
- PDFs with a real text layer skip OCR for those pages (use --force-ocr to override)
- Pages are OCR'd in parallel, rendered one at a time into a private temp dir
- Dictionary stays ON for prose; --code turns it off for code/XML heavy pages
- Proper exit codes, stderr progress, tessdata path option, batch output dir
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from collections import Counter
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageOps, ImageSequence

EDGE = 3  # how many non-empty lines at top/bottom count as header/footer area
MIN_EMBEDDED_CHARS = 200  # a PDF page needs this much real text to skip OCR
HEADER_THRESHOLD = 0.6  # fraction of pages a line must repeat on to be a header/footer

# Watermark lines that are safe to drop anywhere on a page (document specific).
DEFAULT_NOISE = [
    r"^\s*Automatic Zoom\s*$",
    r"^\s*All Rights Reserved\.?\s*$",
    r"^.{0,30}WEBSECURE.*$",
]

# Junk that is only removed near the top/bottom of a page.
PAGE_NUM_RE = re.compile(
    r"^\s*(?:page\s*)?\d{1,4}(?:\s*(?:/|of)\s*\d{1,4})?\s*$", re.IGNORECASE
)
LOGO_GARBAGE_RE = re.compile(r"^\s*(Feo|Pig|An|Te|WI|Fol)\s*$", re.IGNORECASE)
STRAY_RE = re.compile(r"^\s*[.,:;|_~'\"`]{1,3}\s*$")  # braces/brackets are NOT stray

QUOTE_MAP = str.maketrans({"\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'"})
LIGATURES = {"\ufb01": "fi", "\ufb02": "fl", "\ufb00": "ff", "\u00a0": " "}


@dataclass
class Options:
    lang: str = "eng"
    dpi: int = 300
    psm: int | None = None
    oem: int = 1
    code: bool = False
    preprocess: bool = True
    tessdata: str | None = None
    jobs: int = 2
    force_ocr: bool = False


# ----------------------------------------------------------------------------
# OCR layer
# ----------------------------------------------------------------------------


def build_config(opt: Options) -> str:
    psm = opt.psm if opt.psm is not None else (6 if opt.code else 3)
    parts = [f"--oem {opt.oem}", f"--psm {psm}", "-c preserve_interword_spaces=1"]
    if opt.code:
        # Dictionaries hurt code, XML and URLs; they help normal prose, so only skip them here.
        parts += ["-c load_system_dawg=0", "-c load_freq_dawg=0"]
    if opt.tessdata:
        parts.append(f'--tessdata-dir "{opt.tessdata}"')
    return " ".join(parts)


def preprocess(img: Image.Image, opt: Options, upscale: bool) -> Image.Image:
    if not opt.preprocess:
        return img
    img = ImageOps.exif_transpose(img).convert("L")
    if upscale and img.width < 1600:
        factor = min(3, -(-1600 // img.width))
        img = img.resize((img.width * factor, img.height * factor), Image.LANCZOS)
    return ImageOps.autocontrast(img, cutoff=1)


def ocr_image(img: Image.Image, opt: Options) -> str:
    import pytesseract

    return pytesseract.image_to_string(img, lang=opt.lang, config=build_config(opt))


def ocr_image_file(path: Path, opt: Options, log: Callable[[str], None]) -> list[str]:
    pages = []
    with Image.open(path) as im:
        for i, frame in enumerate(ImageSequence.Iterator(im), 1):
            log(f"    frame {i}")
            pages.append(ocr_image(preprocess(frame.copy(), opt, upscale=True), opt))
    return pages


def pdf_page_count(pdf: Path) -> int:
    out = subprocess.run(
        ["pdfinfo", str(pdf)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=True,
    ).stdout
    m = re.search(r"^Pages:\s+(\d+)", out, re.MULTILINE)
    if not m:
        raise RuntimeError("could not read page count from pdfinfo")
    return int(m.group(1))


def embedded_pages(pdf: Path) -> list[str]:
    """Text layer per page, or [] if pdftotext is unavailable."""
    if not shutil.which("pdftotext"):
        return []
    r = subprocess.run(
        ["pdftotext", "-layout", str(pdf), "-"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return r.stdout.split("\f") if r.returncode == 0 else []


def ocr_pdf(pdf: Path, opt: Options, log: Callable[[str], None]) -> list[str]:
    for tool in ("pdftoppm", "pdfinfo"):
        if not shutil.which(tool):
            raise RuntimeError(f"'{tool}' not found (install poppler-utils)")

    total = pdf_page_count(pdf)
    embedded = [] if opt.force_ocr else embedded_pages(pdf)
    log(f"    {total} pages, {opt.dpi} DPI, {opt.jobs} worker(s)")

    with tempfile.TemporaryDirectory(prefix="ocr_") as tmp:

        def work(n: int) -> str:
            if (
                n - 1 < len(embedded)
                and len(embedded[n - 1].strip()) >= MIN_EMBEDDED_CHARS
            ):
                log(f"    page {n}/{total}: text layer")
                return embedded[n - 1]
            d = Path(tmp) / f"p{n}"
            d.mkdir()
            subprocess.run(
                [
                    "pdftoppm",
                    "-png",
                    "-r",
                    str(opt.dpi),
                    "-f",
                    str(n),
                    "-l",
                    str(n),
                    str(pdf),
                    str(d / "pg"),
                ],
                check=True,
                capture_output=True,
            )
            imgs = sorted(d.glob("pg-*.png"))
            with Image.open(imgs[0]) as im:
                text = ocr_image(preprocess(im, opt, upscale=False), opt)
            shutil.rmtree(d, ignore_errors=True)
            log(f"    page {n}/{total}: OCR")
            return text

        with ThreadPoolExecutor(max_workers=opt.jobs) as ex:
            return list(ex.map(work, range(1, total + 1)))


def ocr_document(path: Path, opt: Options, log: Callable[[str], None]) -> list[str]:
    if path.suffix.lower() == ".pdf":
        return ocr_pdf(path, opt, log)
    return ocr_image_file(path, opt, log)


# ----------------------------------------------------------------------------
# Cleaning
# ----------------------------------------------------------------------------


def build_entity_fixer(raw_pages: list[str]) -> Callable[[str], str]:
    """
    Repairs 'slt;' -> '&lt;' and 'sxxe;' -> '&xxe;' but ONLY for standard entities
    and entities the document itself declares via <!ENTITY name ...>.
    """
    declared = set(
        re.findall(r"<!ENTITY\s+(?:%\s+)?([A-Za-z_][\w.-]*)", "\n".join(raw_pages))
    )
    names = sorted(
        {"lt", "gt", "amp", "quot", "apos"} | declared, key=len, reverse=True
    )
    named = re.compile(r"(?<![\w&])s(" + "|".join(re.escape(n) for n in names) + r");")
    lt_variants = re.compile(r"(?<![\w&])s[1lI]t;")

    def fix(line: str) -> str:
        line = lt_variants.sub("&lt;", line)
        return named.sub(r"&\1;", line)

    return fix


def collapse_blank(text: str) -> str:
    text = "\n".join(l.rstrip() for l in text.split("\n"))
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def drop_edge_junk(lines: list[str]) -> list[str]:
    idx = [i for i, l in enumerate(lines) if l.strip()]
    edge = set(idx[:EDGE] + idx[-EDGE:])
    drop = {
        i
        for i in edge
        if PAGE_NUM_RE.match(lines[i]) or LOGO_GARBAGE_RE.match(lines[i])
    }
    return [l for i, l in enumerate(lines) if i not in drop]


def clean_page(
    text: str, fix_entities: Callable[[str], str], noise: list[re.Pattern]
) -> str:
    text = text.replace("\r", "").replace("\f", "")
    for src, dst in LIGATURES.items():
        text = text.replace(src, dst)
    text = text.translate(QUOTE_MAP)

    lines = [
        l
        for l in text.split("\n")
        if not any(p.match(l) for p in noise) and not STRAY_RE.match(l)
    ]
    lines = drop_edge_junk(lines)
    lines = [fix_entities(l) for l in lines]
    return collapse_blank("\n".join(lines))


def norm_key(line: str) -> str:
    return re.sub(r"\d+", "#", re.sub(r"\s+", " ", line.strip().lower()))


def strip_repeating_edges(pages: list[str]) -> list[str]:
    """Remove lines that repeat in the header/footer area of most pages."""
    n = len(pages)
    if n < 3:
        return pages
    split = [p.split("\n") for p in pages]

    def edge_indices(lines: list[str]) -> list[int]:
        idx = [i for i, l in enumerate(lines) if l.strip()]
        # Code-like or very long lines are never treated as running headers/footers.
        return [
            i
            for i in idx[:EDGE] + idx[-EDGE:]
            if len(lines[i].strip()) <= 80
            and not any(p.search(lines[i]) for p in CODE_HINTS)
        ]

    counts: Counter = Counter()
    for lines in split:
        counts.update({norm_key(lines[i]) for i in edge_indices(lines)})
    repeating = {
        k for k, c in counts.items() if c / n >= HEADER_THRESHOLD and len(k) >= 4
    }
    if not repeating:
        return pages

    out = []
    for lines in split:
        drop = {i for i in edge_indices(lines) if norm_key(lines[i]) in repeating}
        out.append(
            collapse_blank("\n".join(l for i, l in enumerate(lines) if i not in drop))
        )
    return out


def postprocess(
    raw_pages: list[str], noise: list[re.Pattern], keep_headers: bool
) -> list[str]:
    fix_entities = build_entity_fixer(raw_pages)
    pages = [clean_page(p, fix_entities, noise) for p in raw_pages]
    if not keep_headers:
        pages = strip_repeating_edges(pages)
    return pages


def format_text(pages: list[str]) -> str:
    if len(pages) == 1:
        return pages[0]
    return "\n\n".join(f"--- [Page {n}] ---\n\n{p}" for n, p in enumerate(pages, 1))


# ----------------------------------------------------------------------------
# Markdown
# ----------------------------------------------------------------------------

CODE_HINTS = [
    re.compile(r"^\s*</?[A-Za-z!?][^<>]*>"),  # XML/HTML tag
    re.compile(r"^\s*<!\[?[A-Z]"),  # <!DOCTYPE, <!ENTITY
    re.compile(r"&\w+;"),  # entity reference
    re.compile(r"^\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s+/\S*"),
    re.compile(r"^\s*HTTP/\d"),
    re.compile(
        r"^\s*(Host|Content-Type|Content-Length|User-Agent|Cookie|Accept)\s*:",
        re.IGNORECASE,
    ),
    re.compile(r"^\s*\$\s+\S"),  # shell prompt
    re.compile(r"[{};]\s*$"),  # braces / statement end
    re.compile(
        r"^\s*(import \w|def \w+\(|function\s*\w*\(|const |let |var |SELECT |INSERT INTO|UPDATE \w+ SET)"
    ),
    re.compile(r"root:x:\d+"),
]
BULLET_RE = re.compile(
    r"^\s*[\u00ab\u00bb+\u2022*\u00b7\u25cf\u25cb\u25aa\u25a0-]\s+(.*)$"
)
NUM_RE = re.compile(r"^\s*\d+[.)]\s+")


def is_code(lines: list[str]) -> bool:
    hits = sum(any(p.search(l) for p in CODE_HINTS) for l in lines)
    return hits / len(lines) >= 0.6


def is_heading(line: str) -> bool:
    s = line.strip()
    if not 3 <= len(s) <= 70 or s[-1] in ".,;:" or len(s.split()) > 10:
        return False
    return s[0].isupper() or s[0].isdigit()


def heading_md(line: str) -> str:
    s = line.strip()
    m = re.match(r"^(\d+(?:\.\d+)*)[.)]?\s+", s)
    level = min(m.group(1).count(".") + 2, 4) if m else 2
    return f"{'#' * level} {s}"


def join_pair(a: str, b: str) -> str:
    if re.search(r"[A-Za-z]-$", a) and b[:1].islower():  # de-hyphenate wrapped words
        return a[:-1] + b
    return f"{a} {b}"


def prose_md(lines: list[str]) -> str:
    items: list[str] = []
    for ln in lines:
        s = ln.strip()
        m = BULLET_RE.match(ln)
        if m:
            items.append("- " + m.group(1).strip())
        elif NUM_RE.match(ln) or not items:
            items.append(s)
        else:
            items[-1] = join_pair(items[-1], s)
    return "\n".join(items)


def fence(lines: list[str]) -> str:
    body = textwrap.dedent("\n".join(lines)).strip("\n")
    first = lines[0].lstrip()
    if first.startswith("<"):
        lang = "xml"
    elif re.match(r"(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s|HTTP/", first):
        lang = "http"
    elif first.startswith("$ "):
        lang = "sh"
    else:
        lang = ""
    return f"```{lang}\n{body}\n```"


def page_to_md(page: str) -> list[str]:
    items: list[tuple[str, object]] = []
    for block in re.split(r"\n\s*\n", page):
        lines = [l.rstrip() for l in block.split("\n") if l.strip()]
        if not lines:
            continue
        if is_code(lines):
            items.append(("code", list(lines)))
        elif len(lines) == 1 and not BULLET_RE.match(lines[0]) and is_heading(lines[0]):
            items.append(("text", heading_md(lines[0])))
        else:
            items.append(("text", prose_md(lines)))

    merged: list[tuple[str, object]] = []
    for kind, payload in items:
        if kind == "code" and merged and merged[-1][0] == "code":
            merged[-1][1].extend([""] + payload)  # type: ignore[union-attr]
        else:
            merged.append((kind, payload))
    return [fence(p) if k == "code" else p for k, p in merged]  # type: ignore[arg-type]


def to_markdown(pages: list[str]) -> str:
    out: list[str] = []
    for n, page in enumerate(pages, 1):
        if len(pages) > 1:
            out.append(f"<!-- Page {n} -->")
        out.extend(page_to_md(page))
    return "\n\n".join(out).strip() + "\n"


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------


def save(out: Path, txt: str, md: str | None, also_md: bool) -> list[Path]:
    out.parent.mkdir(parents=True, exist_ok=True)
    written = []
    if out.suffix.lower() == ".md":
        out.write_text(md or "", encoding="utf-8")
        written.append(out)
    else:
        out.write_text(txt, encoding="utf-8")
        written.append(out)
        if also_md and md is not None:
            sib = out.with_suffix(".md")
            sib.write_text(md, encoding="utf-8")
            written.append(sib)
    return written


def process_file(path_str: str, opt: Options, args, noise, log, multi: bool) -> bool:
    path = Path(path_str)
    if not path.is_file():
        print(f"[!] File not found: {path_str}", file=sys.stderr)
        return False

    log(f"[*] Processing: {path.name}")
    try:
        raw = ocr_document(path, opt, log)
    except Exception as exc:  # noqa: BLE001
        print(f"[!] {path.name}: {exc}", file=sys.stderr)
        return False

    pages = postprocess(raw, noise, args.keep_headers)
    txt = format_text(pages)
    out_path = (
        Path(args.output)
        if args.output
        else (Path(args.outdir) / (path.stem + ".txt") if args.outdir else None)
    )
    need_md = args.md or (out_path is not None and out_path.suffix.lower() == ".md")
    md = to_markdown(pages) if need_md else None

    if out_path:
        for p in save(out_path, txt, md, args.md):
            log(f"[ok] Saved: {p}")
    else:
        if multi:
            print(f"===== {path.name} =====")
        print(md if args.md else txt)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(
        description="High-fidelity OCR. Prints to stdout like `cat`, or saves with -o / -d.",
        epilog="Examples:\n  ocr scan.png\n  ocr scan.png | grep secret\n"
        "  ocr doc.pdf -o out.txt --md\n  ocr *.pdf -d ./out --md\n  ocr page.png --code",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("files", nargs="+", help="images or PDFs")
    ap.add_argument(
        "-o", "--output", help="output file (single input). .md writes Markdown only"
    )
    ap.add_argument("-d", "--outdir", help="output directory for batch runs")
    ap.add_argument(
        "--md", action="store_true", help="also write Markdown (stdout: print Markdown)"
    )
    ap.add_argument(
        "--code", action="store_true", help="code/XML mode: dictionaries off, psm 6"
    )
    ap.add_argument("--psm", type=int, help="override Tesseract page segmentation mode")
    ap.add_argument("--oem", type=int, default=1)
    ap.add_argument("--lang", default="eng")
    ap.add_argument("--dpi", type=int, default=300)
    ap.add_argument(
        "--tessdata",
        default=os.environ.get("OCR_TESSDATA"),
        help="dir containing *.traineddata (default: $OCR_TESSDATA or system)",
    )
    ap.add_argument("-j", "--jobs", type=int, default=min(4, os.cpu_count() or 1))
    ap.add_argument("--force-ocr", action="store_true", help="ignore PDF text layers")
    ap.add_argument(
        "--no-preprocess", action="store_true", help="skip grayscale/contrast/upscale"
    )
    ap.add_argument(
        "--strip",
        action="append",
        default=[],
        metavar="REGEX",
        help="extra line-removal regex (repeatable)",
    )
    ap.add_argument(
        "--no-default-noise",
        action="store_true",
        help="disable built-in watermark filters",
    )
    ap.add_argument(
        "--keep-headers",
        action="store_true",
        help="disable repeating header/footer removal",
    )
    ap.add_argument("-q", "--quiet", action="store_true")
    args = ap.parse_args()

    if args.output and len(args.files) > 1:
        ap.error("-o can only be used with a single input; use -d for batches")

    try:
        import pytesseract

        pytesseract.get_tesseract_version()
    except ImportError:
        print(
            "[!] pytesseract is not installed (pip install pytesseract)",
            file=sys.stderr,
        )
        return 1
    except pytesseract.TesseractNotFoundError:
        print("[!] tesseract binary not found in PATH", file=sys.stderr)
        return 1

    jobs = max(1, args.jobs)
    if jobs > 1:
        os.environ.setdefault("OMP_THREAD_LIMIT", "1")  # avoid CPU oversubscription

    opt = Options(
        lang=args.lang,
        dpi=args.dpi,
        psm=args.psm,
        oem=args.oem,
        code=args.code,
        preprocess=not args.no_preprocess,
        tessdata=args.tessdata,
        jobs=jobs,
        force_ocr=args.force_ocr,
    )

    patterns = ([] if args.no_default_noise else DEFAULT_NOISE) + args.strip
    noise = [re.compile(p, re.IGNORECASE) for p in patterns]

    show = not args.quiet and sys.stderr.isatty()
    log = (lambda m: print(m, file=sys.stderr)) if show else (lambda m: None)
    # Saved-file notices are always useful when writing to disk
    if (args.output or args.outdir) and not args.quiet:
        log = lambda m: print(m, file=sys.stderr)

    multi = len(args.files) > 1
    ok = [process_file(f, opt, args, noise, log, multi) for f in args.files]
    return 0 if all(ok) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:  # e.g. `ocr x.pdf | head`
        os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        sys.exit(1)
