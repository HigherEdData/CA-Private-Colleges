# Project Context: Extracting information from FTB PRA Response to Get IIC Offset Data 2018–2023

## Purpose

This dataset was created from `PRA Response/IIC Offset Data 2018.pdf` and `PRA Response/IIC Offset Data 2019-2023.pdf` to produce a normalized CSV, `d_IIC_Offset_Data_2018-2023.csv`, suitable for analysis.

The extraction work is implemented in `0_extract_iic_offset_2018_2023.py`. The script converts the tabular PDFs into row-level CSV output while preserving the page 1 header structure, carrying forward repeated-value blanks in the source tables, and filtering out subtotal/total rows.

Note that some further processing is performed in R and the code is available at 1_clean_iic_data.R. That file creates cleaned_IIC_Offset_Data_2018-2023.csv and cleaned_IIC_Offset_Data_2018-2023-cat6only.csv which is filtered to only private institutions in the PRA response.

## Source Files

- **Input PDF:** `PRA Response/IIC Offset Data 2018.pdf`
- **Input PDF:** `PRA Response/IIC Offset Data 2019-2023.pdf`
- **Extraction script:** `extract_iic_offset_2018_2023.py`
- **Output CSV:** `d_IIC_Offset_Data_2018-2023.csv`

## Output Schema

The CSV uses the headers from the top of page 1 of the PDF series:

| Column |
|---|
| CALENDAR YEAR |
| CATEGORY |
| AGENCY NAME |
| 1. PIT OFFSET COUNT |
| 1. PIT OFFSET AMOUNT |
| 2. LOTTERY OFFSET COUNT |
| 2. LOTTERY OFFSET AMOUNT |
| 3. UNCLAIMED PROPERTY OFFSET COUNT |
| 3. UNCLAIMED PROPERTY OFFSET AMOUNT |
| Total OFFSET COUNT |
| Total OFFSET AMOUNT |

The generated CSV currently contains 3,276 data rows plus the header row.

## Transformation Rules

The script follows these rules:

1. Convert the tables in both PDFs into one CSV.
2. Use the page 1 table headers as the CSV column names.
3. When `CALENDAR YEAR` is blank in the PDF, fill it with the most recent non-blank year appearing above that row.
4. When `CATEGORY` is blank in the PDF, fill it with the most recent non-blank category appearing above that row.
5. Drop rows labeled `Total` in `CALENDAR YEAR`, `CATEGORY`, or `AGENCY NAME`.
6. Drop subtotal and grand-total lines, including cases where `Total` is merged into the same extracted line as a year label.
7. Leave genuinely absent offset values blank in the CSV rather than forcing zeros.

## Parser Behavior

The script uses `pdfplumber` for character-level PDF text extraction with x-coordinate positions, replacing an earlier implementation that depended on a macOS-only Swift/PDFKit helper.

### Text Extraction

- Opens each PDF with `pdfplumber` and iterates over every character on every page.
- Groups characters into lines by their vertical position (`top` coordinate) using a configurable tolerance (3 points).
- Within each line, characters are sorted left-to-right and split into tokens based on horizontal gaps (2-point threshold).
- Each token retains its median x-coordinate for downstream column assignment.

### Line Parsing

- Skips known multi-line table header rows.
- Detects calendar years using the `CY####` pattern.
- Maps numeric category prefixes into full labels:
  - `2` → `2 - CITY`
  - `3` → `3 - COUNTY`
  - `4` → `4 - STATE`
  - `5` → `5 - COUNTY SUPERIOR COURT`
  - `6` → `6 - OTHER STATES`
  - `7` → `7 - SPECIAL DISTRICTS`
  - `8` → `8 - UNIV/COLLEGE/POST SEC INSTITUTIONS`
  - `Z` → `Z - OTHER`
- Carries forward the current year and category when the PDF leaves those cells blank for subsequent agency rows.
- Suppresses subtotal and total artifacts, including cases where `Total` is merged into the same extracted line as a year label.
- Handles duplicate/repeated year tokens that appear from PDF formatting artifacts.

### Agency Name Extraction

- Agency name tokens are identified by x-coordinate position, bounded within a defined range (`AGENCY_X_MIN` = 200, `AGENCY_X_MAX` = 380).
- Unicode normalization is applied: en-dashes, em-dashes, smart quotes, and non-breaking spaces are converted to their ASCII equivalents.
- Whitespace is collapsed.

### Column Assignment

- Count/amount pairs are detected using regex patterns (`count` = `^\d[\d,]*$`, `amount` = `^\$\d[\d,]*\.\d{2}$`).
- The last count/amount pair on each row is always assigned to the `Total` columns.
- Preceding pairs are assigned to `PIT`, `Lottery`, or `Unclaimed Property` based on their x-coordinate position using predefined thresholds:
  - x < 460 → PIT
  - x < 560 → Lottery
  - x < 680 → Unclaimed Property
- A template-based alignment system handles rows with varying numbers of offset pairs (2, 3, or 4 pairs). The script scores each possible template against the actual observed x-positions and selects the best fit.

## Data Quality Notes

- `AGENCY NAME` is assembled from non-numeric tokens within the defined x-coordinate range for each PDF line.
- Rows where the agency field contains `Total` are excluded.
- The combined CSV starts with CY2018 rows and ends with CY2023 rows.
- The combined CSV has no remaining rows containing `Total` in `CALENDAR YEAR`, `CATEGORY`, or `AGENCY NAME`.
- Genuinely absent offset values are left blank rather than filled with zeros.

## Usage

Run the extractor from the code directory or provide explicit paths:

```bash
python3 0_extract_iic_offset_2018_2023.py
```

Optional arguments:

- `--input` to override the default source PDF list
- `--output` to override the destination CSV path

Default behavior:

1. Read `PRA Response/IIC Offset Data 2018.pdf`
2. Read `PRA Response/IIC Offset Data 2019-2023.pdf`
3. Write `d_IIC_Offset_Data_2018-2023.csv`

## Implementation Dependencies

- Python 3
- `pdfplumber` (install via `pip install pdfplumber`)

The script is **cross-platform** (Windows, macOS, Linux). The earlier version depended on macOS-specific Swift/PDFKit tooling; this has been replaced with `pdfplumber` for portable character-level PDF extraction.

---

### Key changes from the old version:

1. **Replaced Swift/PDFKit with `pdfplumber`** — now cross-platform, no longer macOS-only
2. **Updated dependencies** — just Python 3 + `pdfplumber` (pip installable)
3. **Added detail on the character-level extraction approach** — line grouping by vertical position, tokenization by horizontal gaps
4. **Added detail on template-based column assignment** — how the script handles rows with 2, 3, or 4 count/amount pairs
5. **Added detail on Unicode normalization** for agency names
6. **Removed all references to Swift, `swiftc`, and PDFKit**