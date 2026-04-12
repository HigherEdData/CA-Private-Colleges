#!/usr/bin/env python3
"""Convert IIC Offset Data 2018.pdf and IIC Offset Data 2019-2023.pdf into a normalized CSV."""

from __future__ import annotations

import argparse
import csv
import itertools
import re
import sys
import unicodedata
from pathlib import Path

import pdfplumber


# ---------------------------------------------------------------------------
# Regex helpers
# ---------------------------------------------------------------------------
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
CATEGORY_CODE_RE = re.compile(r"^(?:CY\d{4}\s+)?([A-Za-z0-9]+)\s+-\s+")

CATEGORY_MAP = {
    "2": "2 - CITY",
    "3": "3 - COUNTY",
    "4": "4 - STATE",
    "5": "5 - COUNTY SUPERIOR COURT",
    "6": "6 - OTHER STATES",
    "7": "7 - SPECIAL DISTRICTS",
    "8": "8 - UNIV/COLLEGE/POST SEC INSTITUTIONS",
    "Z": "Z - OTHER",
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

# ---------------------------------------------------------------------------
# Column boundaries (x-coordinates in PDF points)
# ---------------------------------------------------------------------------
AGENCY_X_MIN = 200
AGENCY_X_MAX = 380


def normalize_agency(name: str) -> str:
    """Collapse whitespace and normalise Unicode so the same visual name
    always produces the same Python string."""
    name = unicodedata.normalize("NFKC", name)
    name = name.replace("\u2013", "-")   # en-dash
    name = name.replace("\u2014", "-")   # em-dash
    name = name.replace("\u2018", "'")   # left single quote
    name = name.replace("\u2019", "'")   # right single quote
    name = name.replace("\u201c", '"')   # left double quote
    name = name.replace("\u201d", '"')   # right double quote
    name = name.replace("\u00a0", " ")   # non-breaking space
    name = re.sub(r"\s+", " ", name).strip()
    return name


def is_total_row(year: str, category: str, agency: str, line_text: str = "") -> bool:
    """Return True if this row represents a subtotal / grand-total line."""
    for value in (year, category, agency, line_text):
        if re.search(r"\btotal\b", value, re.IGNORECASE):
            return True
    return False

def is_numeric_token(token: str) -> bool:
    return bool(COUNT_RE.match(token) or AMOUNT_RE.match(token))


# ---------------------------------------------------------------------------
# PDF extraction using pdfplumber (cross-platform replacement for Swift/PDFKit)
# ---------------------------------------------------------------------------

def extract_positioned_lines(pdf_path: Path) -> list[dict]:
    """Extract lines with positioned tokens from a PDF using pdfplumber.

    Each line dict has:
        page: int (1-based)
        line_number: int (0-based within page)
        text: str (full line text)
        tokens: list[dict] each with 'x' (float) and 'text' (str)
    """
    all_lines: list[dict] = []

    with pdfplumber.open(pdf_path) as pdf:
        for page_index, page in enumerate(pdf.pages):
            page_number = page_index + 1
            chars = page.chars
            if not chars:
                continue

            # Group characters into lines by their vertical position (top).
            # Use a tolerance to group characters on the same visual line.
            LINE_TOLERANCE = 3  # points

            # Sort characters by vertical position then horizontal
            sorted_chars = sorted(chars, key=lambda c: (round(c["top"] / LINE_TOLERANCE), c["x0"]))

            # Group into lines
            lines_on_page: list[list[dict]] = []
            current_line: list[dict] = []
            current_top = None

            for char in sorted_chars:
                char_top = round(char["top"] / LINE_TOLERANCE)
                if current_top is None or char_top != current_top:
                    if current_line:
                        lines_on_page.append(current_line)
                    current_line = [char]
                    current_top = char_top
                else:
                    current_line.append(char)

            if current_line:
                lines_on_page.append(current_line)

            # Process each line into tokens
            for line_number, line_chars in enumerate(lines_on_page):
                # Sort characters left to right within the line
                line_chars.sort(key=lambda c: c["x0"])

                # Build full line text
                full_text = ""
                prev_x1 = None
                SPACE_THRESHOLD = 2  # points gap to infer a space

                for char in line_chars:
                    char_text = char.get("text", "")
                    if not char_text:
                        continue
                    if prev_x1 is not None and (char["x0"] - prev_x1) > SPACE_THRESHOLD:
                        full_text += " "
                    full_text += char_text
                    prev_x1 = char["x1"]

                # Tokenize: split into words by detecting gaps
                tokens: list[dict] = []
                token_chars: list[dict] = []
                prev_x1 = None

                for char in line_chars:
                    char_text = char.get("text", "")
                    if not char_text or char_text.isspace():
                        # Whitespace character — flush current token
                        if token_chars:
                            token_text = "".join(c.get("text", "") for c in token_chars)
                            # Use median x0 of characters in the token
                            x_values = [c["x0"] for c in token_chars]
                            x_values.sort()
                            mid = len(x_values) // 2
                            token_x = (
                                x_values[mid]
                                if len(x_values) % 2 == 1
                                else (x_values[mid - 1] + x_values[mid]) / 2.0
                            )
                            tokens.append({"x": token_x, "text": token_text})
                            token_chars = []
                            prev_x1 = None
                        continue

                    # Check for gap between this char and previous
                    if prev_x1 is not None and (char["x0"] - prev_x1) > SPACE_THRESHOLD:
                        # Gap detected — flush current token
                        if token_chars:
                            token_text = "".join(c.get("text", "") for c in token_chars)
                            x_values = [c["x0"] for c in token_chars]
                            x_values.sort()
                            mid = len(x_values) // 2
                            token_x = (
                                x_values[mid]
                                if len(x_values) % 2 == 1
                                else (x_values[mid - 1] + x_values[mid]) / 2.0
                            )
                            tokens.append({"x": token_x, "text": token_text})
                            token_chars = []

                    token_chars.append(char)
                    prev_x1 = char["x1"]

                # Flush last token
                if token_chars:
                    token_text = "".join(c.get("text", "") for c in token_chars)
                    x_values = [c["x0"] for c in token_chars]
                    x_values.sort()
                    mid = len(x_values) // 2
                    token_x = (
                        x_values[mid]
                        if len(x_values) % 2 == 1
                        else (x_values[mid - 1] + x_values[mid]) / 2.0
                    )
                    tokens.append({"x": token_x, "text": token_text})

                all_lines.append({
                    "page": page_number,
                    "line_number": line_number,
                    "text": full_text,
                    "tokens": tokens,
                })

    return all_lines


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

        prefix_tokens = sorted(
            clean_prefix_tokens(line["tokens"]),
            key=lambda token: token["x"],
        )

        # --- Deduplicate / strip leading year tokens ----------------------
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
                if token["text"] == "Total" and token["x"] < AGENCY_X_MIN:
                    continue
                cleaned_prefix_tokens.append(token)
            prefix_tokens = cleaned_prefix_tokens

        year_token = next(
            (token for token in prefix_tokens if YEAR_RE.match(token["text"])),
            None,
        )
        if year_token is not None:
            year = year_token["text"]

        category_match = CATEGORY_CODE_RE.match(normalized_text)
        if category_match:
            category = CATEGORY_MAP.get(category_match.group(1), category)

        # -----------------------------------------------------------------
        # Agency name extraction – bounded range [AGENCY_X_MIN, AGENCY_X_MAX)
        # -----------------------------------------------------------------
        agency_tokens = [
            token["text"]
            for token in prefix_tokens
            if AGENCY_X_MIN <= token["x"] < AGENCY_X_MAX
            and not YEAR_RE.match(token["text"])
            and token["text"] != "Total"
        ]
        agency = normalize_agency(" ".join(agency_tokens))

        if is_total_row(year, category, agency, normalized_text):
            current_year = year if (year and "total" not in year.lower()) else current_year
            current_category = category if (category and "total" not in category.lower()) else current_category
            continue

        row = {field: "" for field in FIELDNAMES}
        row["CALENDAR YEAR"] = year
        row["CATEGORY"] = category
        row["AGENCY NAME"] = agency

        text_pairs = [(match.group(1), match.group(2)) for match in pair_matches]
        count_positions = infer_count_positions(
            known_positions, len(text_pairs), normalized_text, line
        )
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
                    f"Unrecognized offset column on page {line['page']} "
                    f"line {line['line_number']}: {normalized_text}"
                )

        total_count, total_amount, _ = pairs[-1]
        row["Total OFFSET COUNT"] = total_count
        row["Total OFFSET AMOUNT"] = total_amount
        
        if row["CALENDAR YEAR"] and not is_total_row(
                row["CALENDAR YEAR"],
                row["CATEGORY"],
                row["AGENCY NAME"],
                normalized_text,
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
            f"Unsupported pair count on page {line['page']} "
            f"line {line['line_number']}: {normalized_text}"
        )

    best_template = None
    best_score = None
    for template in candidates:
        score = template_alignment_score(template, known_positions)
        if best_score is None or score < best_score:
            best_score = score
            best_template = template

    return best_template[:]  # type: ignore[return-value]


def template_alignment_score(
    template: list[float], known_positions: list[float]
) -> float:
    if not known_positions:
        return 0.0

    best = None
    for template_indexes in itertools.combinations(
        range(len(template)), len(known_positions)
    ):
        score = sum(
            abs(template[index] - known)
            for index, known in zip(template_indexes, known_positions, strict=True)
        )
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
            data_dir / "IIC Offset Data 2018.pdf",
            data_dir / "IIC Offset Data 2019-2023.pdf",
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


def main(input_paths: list[Path] | None = None, output_path: Path | None = None) -> int:
    if input_paths is None or output_path is None:
        args = build_parser().parse_args([])
        input_paths = input_paths or args.input
        output_path = output_path or args.output

    missing_inputs = [pdf_path for pdf_path in input_paths if not pdf_path.exists()]
    if missing_inputs:
        missing = ", ".join(str(pdf_path) for pdf_path in missing_inputs)
        raise FileNotFoundError(f"Input PDF not found: {missing}")

    rows: list[dict] = []
    for pdf_path in input_paths:
        lines = extract_positioned_lines(pdf_path)
        rows.extend(parse_row(lines))

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDNAMES)
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {len(rows)} rows from {len(input_paths)} PDF(s) to {output_path}")
    return 0


if __name__ == "__main__":
    main()