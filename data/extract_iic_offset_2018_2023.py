#!/usr/bin/env python3
"""Convert IIC Offset Data 2018.pdf and IIC Offset Data 2019-2023.pdf into a normalized CSV."""

from __future__ import annotations

import argparse
import csv
import itertools
import re
import subprocess
import sys
import tempfile
from pathlib import Path


SWIFT_HELPER = r"""
import Foundation
import PDFKit

struct Token {
    let x: Double
    let text: String
}

func escape(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\t", with: "\\t")
}

func emitLine(pageNumber: Int, lineNumber: Int, rawLine: String, tokens: [Token]) {
    print("L\t\(pageNumber)\t\(lineNumber)\t\(escape(rawLine))")
    for token in tokens {
        print("T\t\(pageNumber)\t\(lineNumber)\t\(String(format: "%.2f", token.x))\t\(escape(token.text))")
    }
}

let pdfPath = CommandLine.arguments[1]
guard let document = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
    fputs("Unable to open PDF at \(pdfPath)\n", stderr)
    exit(1)
}

for pageIndex in 0..<document.pageCount {
    guard let page = document.page(at: pageIndex), let pageString = page.string else { continue }
    let nsText = pageString as NSString
    var lineNumber = 0
    var lineStart = 0

    func processLine(start: Int, end: Int) {
        let rawLine = nsText.substring(with: NSRange(location: start, length: max(end - start, 0)))
        var tokens: [Token] = []
        var idx = start
        while idx < end {
            let current = nsText.substring(with: NSRange(location: idx, length: 1))
            if current == " " || current == "\t" || current == "\r" {
                idx += 1
                continue
            }

            let tokenStart = idx
            while idx < end {
                let value = nsText.substring(with: NSRange(location: idx, length: 1))
                if value == " " || value == "\t" || value == "\r" {
                    break
                }
                idx += 1
            }

            let tokenText = nsText.substring(with: NSRange(location: tokenStart, length: idx - tokenStart))
            var minX = Double.greatestFiniteMagnitude
            for charIndex in tokenStart..<idx {
                let rect = page.characterBounds(at: charIndex)
                minX = min(minX, rect.origin.x)
            }
            tokens.append(Token(x: minX, text: tokenText))
        }

        emitLine(pageNumber: pageIndex + 1, lineNumber: lineNumber, rawLine: rawLine, tokens: tokens)
        lineNumber += 1
    }

    for idx in 0..<nsText.length {
        if nsText.substring(with: NSRange(location: idx, length: 1)) == "\n" {
            processLine(start: lineStart, end: idx)
            lineStart = idx + 1
        }
    }

    if lineStart < nsText.length {
        processLine(start: lineStart, end: nsText.length)
    }
}
"""

COUNT_RE = re.compile(r"^\d[\d,]*$")
AMOUNT_RE = re.compile(r"^\$\d[\d,]*\.\d{2}$")
YEAR_RE = re.compile(r"^CY\d{4}$")
HEADER_LINES = {
    "CALENDAR YEAR CATEGORY AGENCY NAME OFFSET TYPE Values",
    "1. PIT 2. LOTTERY 3. UNCLAIMED PROPERTY Total OFFSET COUNT Total OFFSET AMOUNT",
    "OFFSET COUNT OFFSET AMOUNT OFFSET COUNT OFFSET AMOUNT OFFSET COUNT OFFSET AMOUNT",
}
MERGED_TOTAL_RE = re.compile(r"^(CY\d{4})\s+Total\s+\1\s+")
PAIR_RE = re.compile(r"(\d[\d,]*)\s+(\$\d[\d,]*\.\d{2})")
CATEGORY_CODE_RE = re.compile(r"^(?:CY\d{4}\s+)?(\d+)\s+-\s+")

CATEGORY_MAP = {
    "2": "2 - CITY",
    "3": "3 - COUNTY",
    "4": "4 - STATE",
    "5": "5 - COUNTY SUPERIOR COURT",
    "6": "6 - OTHER STATES",
    "7": "7 - SPECIAL DISTRICTS",
    "8": "8 - UNIV/COLLEGE/POST SEC INSTITUTIONS",
}

FIELDNAMES = [
    "CALENDAR YEAR",
    "CATEGORY",
    "AGENCY NAME",
    "1. PIT OFFSET COUNT",
    "1. PIT OFFSET AMOUNT",
    "2. LOTTERY OFFSET COUNT",
    "2. LOTTERY OFFSET AMOUNT",
    "3. UNCLAIMED PROPERTY OFFSET COUNT",
    "3. UNCLAIMED PROPERTY OFFSET AMOUNT",
    "Total OFFSET COUNT",
    "Total OFFSET AMOUNT",
]


def unescape(value: str) -> str:
    return value.replace("\\t", "\t").replace("\\\\", "\\")


def is_total_row(year: str, category: str, agency: str) -> bool:
    return any("Total" in value for value in (year, category, agency))


def extract_positioned_lines(pdf_path: Path) -> list[dict]:
    with tempfile.TemporaryDirectory(prefix="iic_offset_") as tmpdir:
        tmpdir_path = Path(tmpdir)
        swift_path = tmpdir_path / "extract.swift"
        binary_path = tmpdir_path / "extract_pdf_lines"
        module_cache = tmpdir_path / "swift-module-cache"
        swift_path.write_text(SWIFT_HELPER, encoding="utf-8")
        module_cache.mkdir(parents=True, exist_ok=True)

        compile_cmd = [
            "swiftc",
            "-module-cache-path",
            str(module_cache),
            "-framework",
            "PDFKit",
            str(swift_path),
            "-o",
            str(binary_path),
        ]
        subprocess.run(compile_cmd, check=True, capture_output=True, text=True)

        run_cmd = [str(binary_path), str(pdf_path)]
        result = subprocess.run(run_cmd, check=True, capture_output=True, text=True)

    lines: dict[tuple[int, int], dict] = {}
    order: list[tuple[int, int]] = []
    for raw in result.stdout.splitlines():
        parts = raw.split("\t")
        record_type = parts[0]
        page_number = int(parts[1])
        line_number = int(parts[2])
        key = (page_number, line_number)

        if record_type == "L":
            lines[key] = {
                "page": page_number,
                "line_number": line_number,
                "text": unescape(parts[3]),
                "tokens": [],
            }
            order.append(key)
        elif record_type == "T":
            lines[key]["tokens"].append(
                {
                    "x": float(parts[3]),
                    "text": unescape(parts[4]),
                }
            )

    return [lines[key] for key in order]


def is_numeric_token(token: str) -> bool:
    return bool(COUNT_RE.match(token) or AMOUNT_RE.match(token))


def clean_prefix_tokens(tokens: list[dict]) -> list[dict]:
    cleaned = tokens[:]
    if (
        len(cleaned) >= 3
        and YEAR_RE.match(cleaned[0]["text"])
        and cleaned[1]["text"] == "Total"
        and cleaned[2]["text"] == cleaned[0]["text"]
    ):
        cleaned = [cleaned[2], *cleaned[3:]]
    return cleaned


def parse_row(lines: list[dict]) -> list[dict]:
    rows: list[dict] = []
    current_year = ""
    current_category = ""

    for line in lines:
        text = " ".join(line["text"].split())
        if not text or text in HEADER_LINES:
            continue

        normalized_text = MERGED_TOTAL_RE.sub(r"\1 ", text)
        pair_matches = list(PAIR_RE.finditer(normalized_text))
        if not pair_matches:
            continue

        desired_counts = [match.group(1) for match in pair_matches]
        count_candidates = [token for token in line["tokens"] if COUNT_RE.match(token["text"])]
        remaining_counts: dict[str, int] = {}
        for count in desired_counts:
            remaining_counts[count] = remaining_counts.get(count, 0) + 1

        known_positions = []
        for token in count_candidates:
            if remaining_counts.get(token["text"], 0) > 0:
                remaining_counts[token["text"]] -= 1
                if token["x"] > 0:
                    known_positions.append(token["x"])

        known_positions.sort()

        year = current_year
        category = current_category

        prefix_tokens = sorted(clean_prefix_tokens(line["tokens"]), key=lambda token: token["x"])
        year_tokens = [token for token in prefix_tokens if YEAR_RE.match(token["text"])]
        if len(year_tokens) > 1:
            keep_year = year_tokens[-1]["text"]
            removed_first_year = False
            cleaned_prefix_tokens = []
            for token in prefix_tokens:
                if YEAR_RE.match(token["text"]):
                    if not removed_first_year:
                        removed_first_year = True
                        continue
                    if token["text"] != keep_year:
                        continue
                if token["text"] == "Total" and token["x"] < 210:
                    continue
                cleaned_prefix_tokens.append(token)
            prefix_tokens = cleaned_prefix_tokens

        year_token = next((token for token in prefix_tokens if YEAR_RE.match(token["text"])), None)
        if year_token is not None:
            year = year_token["text"]

        category_match = CATEGORY_CODE_RE.match(normalized_text)
        if category_match:
            category = CATEGORY_MAP.get(category_match.group(1), category)

        agency_tokens = [
            token["text"]
            for token in prefix_tokens
            if token["x"] >= 210 and not is_numeric_token(token["text"])
        ]
        agency = " ".join(agency_tokens).strip()

        if is_total_row(year, category, agency):
            current_year = year or current_year
            current_category = category or current_category
            continue

        row = {field: "" for field in FIELDNAMES}
        row["CALENDAR YEAR"] = year
        row["CATEGORY"] = category
        row["AGENCY NAME"] = agency

        text_pairs = [(match.group(1), match.group(2)) for match in pair_matches]
        count_positions = infer_count_positions(known_positions, len(text_pairs), normalized_text, line)
        pairs = [
            (count, amount, x_pos)
            for (count, amount), x_pos in zip(text_pairs, count_positions, strict=True)
        ]

        for count, amount, x_pos in pairs[:-1]:
            if x_pos < 460:
                row["1. PIT OFFSET COUNT"] = count
                row["1. PIT OFFSET AMOUNT"] = amount
            elif x_pos < 560:
                row["2. LOTTERY OFFSET COUNT"] = count
                row["2. LOTTERY OFFSET AMOUNT"] = amount
            elif x_pos < 680:
                row["3. UNCLAIMED PROPERTY OFFSET COUNT"] = count
                row["3. UNCLAIMED PROPERTY OFFSET AMOUNT"] = amount
            else:
                raise ValueError(
                    f"Unrecognized offset column on page {line['page']} line {line['line_number']}: {normalized_text}"
                )

        total_count, total_amount, _ = pairs[-1]
        row["Total OFFSET COUNT"] = total_count
        row["Total OFFSET AMOUNT"] = total_amount

        if row["CALENDAR YEAR"] and not is_total_row(
            row["CALENDAR YEAR"],
            row["CATEGORY"],
            row["AGENCY NAME"],
        ):
            rows.append(row)

        current_year = year or current_year
        current_category = category or current_category

    return rows


def infer_count_positions(
    known_positions: list[float],
    pair_count: int,
    normalized_text: str,
    line: dict,
) -> list[float]:
    templates = {
        2: [[400.0, 710.0]],
        3: [[400.0, 495.0, 710.0], [400.0, 610.0, 710.0]],
        4: [[400.0, 495.0, 610.0, 710.0]],
    }
    candidates = templates.get(pair_count)
    if not candidates:
        raise ValueError(
            f"Unsupported pair count on page {line['page']} line {line['line_number']}: {normalized_text}"
        )

    best_template = None
    best_score = None
    for template in candidates:
        score = template_alignment_score(template, known_positions)
        if best_score is None or score < best_score:
            best_score = score
            best_template = template

    return best_template[:]  # type: ignore[return-value]


def template_alignment_score(template: list[float], known_positions: list[float]) -> float:
    if not known_positions:
        return 0.0

    best = None
    for template_indexes in itertools.combinations(range(len(template)), len(known_positions)):
        score = sum(abs(template[index] - known) for index, known in zip(template_indexes, known_positions, strict=True))
        if best is None or score < best:
            best = score
    return float(best)


def build_parser() -> argparse.ArgumentParser:
    data_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        nargs="+",
        default=[
            data_dir / "PRA Response" / "IIC Offset Data 2018.pdf",
            data_dir / "PRA Response" / "IIC Offset Data 2019-2023.pdf",
        ],
        help="One or more source PDF paths.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=data_dir / "d_IIC_Offset_Data_2018-2023.csv",
        help="Path to the output CSV.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()

    missing_inputs = [pdf_path for pdf_path in args.input if not pdf_path.exists()]
    if missing_inputs:
        missing = ", ".join(str(pdf_path) for pdf_path in missing_inputs)
        raise FileNotFoundError(f"Input PDF not found: {missing}")

    rows: list[dict] = []
    for pdf_path in args.input:
        lines = extract_positioned_lines(pdf_path)
        rows.extend(parse_row(lines))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows from {len(args.input)} PDF(s) to {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as exc:
        if exc.stderr:
            sys.stderr.write(exc.stderr)
        raise
