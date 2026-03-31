# Project Context: IIC Offset Data 2018-2023

## Purpose

This dataset was created from `PRA Response/IIC Offset Data 2018.pdf` and `PRA Response/IIC Offset Data 2019-2023.pdf` to produce a normalized CSV, `d_IIC_Offset_Data_2018-2023.csv`, suitable for analysis.

The extraction work is implemented in `extract_iic_offset_2018_2023.py`. The script converts the tabular PDFs into row-level CSV output while preserving the page 1 header structure and repairing repeated-value blanks in the source tables.

## Source Files

- Input PDF: `PRA Response/IIC Offset Data 2018.pdf`
- Input PDF: `PRA Response/IIC Offset Data 2019-2023.pdf`
- Extraction script: `extract_iic_offset_2018_2023.py`
- Output CSV: `d_IIC_Offset_Data_2018-2023.csv`

## Output Schema

The CSV uses the headers from the top of page 1 of the PDF series:

1. `CALENDAR YEAR`
2. `CATEGORY`
3. `AGENCY NAME`
4. `1. PIT OFFSET COUNT`
5. `1. PIT OFFSET AMOUNT`
6. `2. LOTTERY OFFSET COUNT`
7. `2. LOTTERY OFFSET AMOUNT`
8. `3. UNCLAIMED PROPERTY OFFSET COUNT`
9. `3. UNCLAIMED PROPERTY OFFSET AMOUNT`
10. `Total OFFSET COUNT`
11. `Total OFFSET AMOUNT`

The generated CSV currently contains 3,283 data rows plus the header row.

## Transformation Rules

The script follows these rules from the original extraction request:

- Convert the tables in `IIC Offset Data 2018.pdf` and `IIC Offset Data 2019-2023.pdf` into one CSV.
- Use the page 1 table headers as the CSV column names.
- When `CALENDAR YEAR` is blank in the PDF, fill it with the most recent nonblank year appearing above that row.
- When `CATEGORY` is blank in the PDF, fill it with the most recent nonblank category appearing above that row.
- Drop rows labeled `Total` in either `CALENDAR YEAR` or `CATEGORY`.
- Drop rows where `Total` appears in `AGENCY NAME`, which is needed because some PDF subtotal and grand-total lines are extracted into that field.

## Parser Behavior

The script does more than a simple text scrape because the PDF table layout is inconsistent.

- It compiles and runs a small Swift helper using `PDFKit` to extract text tokens with x-coordinate positions from each PDF page.
- It skips known multi-line table header rows.
- It detects calendar years using the `CY####` pattern.
- It maps numeric category prefixes in the PDF into full labels:
- `2 - CITY`
- `3 - COUNTY`
- `4 - STATE`
- `5 - COUNTY SUPERIOR COURT`
- `6 - OTHER STATES`
- `7 - SPECIAL DISTRICTS`
- `8 - UNIV/COLLEGE/POST SEC INSTITUTIONS`
- It carries forward the current year and category when the PDF leaves those cells blank for subsequent agency rows.
- It suppresses subtotal and total artifacts, including cases where `Total` is merged into the same extracted line as a year label.
- It now processes both input PDFs in sequence and appends the parsed rows into a single combined dataset ordered from `CY2018` through `CY2023`.
- It reconstructs offset columns by inferring which count/amount pair belongs to PIT, Lottery, Unclaimed Property, or Total based on token positions.
- It leaves genuinely absent offset values blank in the CSV rather than forcing zeros.

## Data Quality Notes

- `AGENCY NAME` is assembled from nonnumeric tokens in the agency-name portion of each PDF line.
- The final count/amount pair on each row is always treated as the total columns.
- Intermediate count/amount pairs are assigned to PIT, Lottery, or Unclaimed Property based on inferred x-position templates.
- Rows where the agency field contains `Total` are also excluded.
- The current combined CSV starts with `CY2018` rows and ends with `CY2023` rows.
- The current combined CSV has no remaining rows containing `Total` in `CALENDAR YEAR`, `CATEGORY`, or `AGENCY NAME`.

## Usage

Run the extractor from the data directory or provide explicit paths:

```bash
python3 extract_iic_offset_2018_2023.py
```

Optional arguments:

- `--input` to override the default source PDF list
- `--output` to override the destination CSV path

Default behavior:

- Read `PRA Response/IIC Offset Data 2018.pdf`
- Read `PRA Response/IIC Offset Data 2019-2023.pdf`
- Write `d_IIC_Offset_Data_2018-2023.csv`

## Implementation Dependencies

- Python 3
- macOS `PDFKit` via `swiftc`

The script depends on Swift and `PDFKit` because standard PDF text extraction was not reliable enough to preserve the table structure needed for accurate column assignment.
