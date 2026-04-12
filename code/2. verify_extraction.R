library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)

##

setwd("G:/My Drive/SLLI/FTB Paper/")
combined_df<- read.csv("final code/cleaned_IIC_Offset_Data_2018-2023.csv") #cleaned csv of all institutions
cat6_df<- read.csv("final code/cleaned_IIC_Offset_Data_2018-2023-cat6only.csv") #cleaned csv of CAT 6 institutions only


# ------------------------------------------------------------------
# Verify totals are correct
# ------------------------------------------------------------------

cat6_df %>%
  summarise(
    All_Match    = all(Total_Count == PIT_Count + Lottery_Count + UCP_Count),
    Num_Mismatch = sum(Total_Count != PIT_Count + Lottery_Count + UCP_Count),
    Total_Rows   = n()
  )

# ------------------------------------------------------------------
# 1. Parse all the numeric columns (strip "$" and commas),
#    replacing NAs with 0 (blank = no offsets of that type)
# ------------------------------------------------------------------
check_df <- combined_df %>%
  mutate(
    PIT_Amount   = replace_na(as.numeric(gsub("[\\$,]", "", X1..PIT.OFFSET.AMOUNT)), 0),
    Lotto_Amount = replace_na(as.numeric(gsub("[\\$,]", "", X2..LOTTERY.OFFSET.AMOUNT)), 0),
    UCP_Amount   = replace_na(as.numeric(gsub("[\\$,]", "", X3..UNCLAIMED.PROPERTY.OFFSET.AMOUNT)), 0),
    Total_Amount = replace_na(as.numeric(gsub("[\\$,]", "", Total.OFFSET.AMOUNT)), 0),
    
    PIT_Count    = replace_na(as.numeric(gsub("[,]", "", X1..PIT.OFFSET.COUNT)), 0),
    Lotto_Count  = replace_na(as.numeric(gsub("[,]", "", X2..LOTTERY.OFFSET.COUNT)), 0),
    UCP_Count    = replace_na(as.numeric(gsub("[,]", "", X3..UNCLAIMED.PROPERTY.OFFSET.COUNT)), 0),
    Total_Count  = replace_na(as.numeric(gsub("[,]", "", Total.OFFSET.COUNT)), 0)
  ) %>%
  mutate(
    Calc_Amount  = PIT_Amount + Lotto_Amount + UCP_Amount,
    Calc_Count   = PIT_Count  + Lotto_Count  + UCP_Count,
    Amount_Match = near(Total_Amount, Calc_Amount, tol = 0.01),
    Count_Match  = (Total_Count == Calc_Count)
  )

# ------------------------------------------------------------------
# 2. Summary
# ------------------------------------------------------------------
cat("=== AMOUNT CHECK ===\n")
print(table(Amount_Match = check_df$Amount_Match, useNA = "ifany"))

cat("\n=== COUNT CHECK ===\n")
print(table(Count_Match = check_df$Count_Match, useNA = "ifany"))

# ------------------------------------------------------------------
# 3. Show mismatches (using head to avoid the print error)
# ------------------------------------------------------------------
amount_issues <- check_df %>%
  filter(!Amount_Match) %>%
  select(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN,
         PIT_Amount, Lotto_Amount, UCP_Amount,
         Calc_Amount, Total_Amount)

cat("\n=== AMOUNT MISMATCHES ===\n")
cat("Number of rows:", nrow(amount_issues), "\n")
if (nrow(amount_issues) > 0) print(head(as.data.frame(amount_issues), 50))

count_issues <- check_df %>%
  filter(!Count_Match) %>%
  select(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN,
         PIT_Count, Lotto_Count, UCP_Count,
         Calc_Count, Total_Count)

cat("\n=== COUNT MISMATCHES ===\n")
cat("Number of rows:", nrow(count_issues), "\n")
if (nrow(count_issues) > 0) print(head(as.data.frame(count_issues), 50))

# ------------------------------------------------------------------
# 4. Quick sanity check: were any Total columns themselves blank?
# ------------------------------------------------------------------
cat("\n=== ROWS WHERE TOTAL AMOUNT WAS BLANK/UNPARSEABLE ===\n")
cat(sum(combined_df$Total.OFFSET.AMOUNT == "" | is.na(combined_df$Total.OFFSET.AMOUNT)), "\n")


#--
# checking specific schools:

combined_df %>%
  filter(AGENCY_CLEAN == "UMASS GLOBAL") %>%
  mutate(Total_Amount = replace_na(as.numeric(gsub("[\\$,]", "", Total.OFFSET.AMOUNT)), 0)) %>%
  summarise(Grand_Total = sprintf("%.2f", sum(Total_Amount)))

combined_df %>%
  filter(AGENCY_CLEAN == "UMASS GLOBAL") %>%
  mutate(
    Year = str_extract(CALENDAR.YEAR, "\\d{4}"),
    Total_Amount = replace_na(as.numeric(gsub("[\\$,]", "", Total.OFFSET.AMOUNT)), 0)
  ) %>%
  group_by(Year) %>%
  summarise(Total_Offset = sprintf("%.2f", sum(Total_Amount)))


#################################################################################

# ==================================================================
# ADDITIONAL PDF EXTRACTION VERIFICATION CHECKS
# ==================================================================
# Limited to Category 6 (privates)
# ------------------------------------------------------------------
# 1. Check for duplicate rows (PDF page breaks can cause repeats)
# ------------------------------------------------------------------

# --- Look at the "duplicate" groups and see if they should be aggregated ---
dupes_detail <- cat6_df %>%
  group_by(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN) %>%
  filter(n() > 1) %>%
  arrange(AGENCY_CLEAN, CALENDAR.YEAR) %>%
  select(CALENDAR.YEAR, CATEGORY, AGENCY.NAME, AGENCY_CLEAN,
         PIT_Count, PIT_Amount, Total_Count, Total_Amount)

cat("Distinct agencies affected:", n_distinct(dupes_detail$AGENCY_CLEAN), "\n")
cat("Total rows involved:", nrow(dupes_detail), "\n\n")

# --- Check: is the larger value the sum of the smaller ones? ---
dupes_summary <- cat6_df %>%
  group_by(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN) %>%
  filter(n() > 1) %>%
  summarise(
    n_rows    = n(),
    max_total = max(Total_Amount),
    sum_total = sum(Total_Amount),
    max_count = max(Total_Count),
    sum_count = sum(Total_Count),
    .groups = "drop"
  ) %>%
  mutate(
    max_equals_sum_minus_max = near(max_total, sum_total - max_total, tol = 0.01)
  )

print(as.data.frame(head(dupes_summary, 100)))

## Stanford is duplicated several times so we aggregate in code

# ------------------------------------------------------------------
# 2. Check for misaligned columns (counts in amount columns, etc.)
#    Counts should be whole numbers; amounts should not be
# ------------------------------------------------------------------
cat("\n=== FRACTIONAL COUNTS (suggests column misalignment) ===\n")
fractional <- combined_df %>%
  filter(PIT_Count != floor(PIT_Count) |
           Lottery_Count != floor(Lottery_Count) |
           UCP_Count != floor(UCP_Count) |
           Total_Count != floor(Total_Count))
cat("Rows with fractional counts:", nrow(fractional), "\n")
if (nrow(fractional) > 0) print(as.data.frame(fractional))

# ------------------------------------------------------------------
# 3. Check for negative values (shouldn't exist in offset data)
# ------------------------------------------------------------------
cat("\n=== NEGATIVE VALUES ===\n")
negatives <- combined_df %>%
  filter(PIT_Amount < 0 | Lottery_Amount < 0 | UCP_Amount < 0 |
           Total_Amount < 0 | PIT_Count < 0 | Lottery_Count < 0 |
           UCP_Count < 0 | Total_Count < 0)
cat("Rows with negative values:", nrow(negatives), "\n")
if (nrow(negatives) > 0) print(as.data.frame(negatives))

# ------------------------------------------------------------------
# 4. Check for zero amounts with non-zero counts (and vice versa)
#    A count > 0 should have amount > 0, and amount > 0 should have count > 0
# ------------------------------------------------------------------
cat("\n=== COUNT/AMOUNT INCONSISTENCIES ===\n")
inconsistent <- combined_df %>%
  filter(
    (PIT_Count > 0 & PIT_Amount == 0) | (PIT_Count == 0 & PIT_Amount > 0) |
      (Lottery_Count > 0 & Lottery_Amount == 0) | (Lottery_Count == 0 & Lottery_Amount > 0) |
      (UCP_Count > 0 & UCP_Amount == 0) | (UCP_Count == 0 & UCP_Amount > 0)
  )
cat("Rows with count/amount mismatch:", nrow(inconsistent), "\n")
if (nrow(inconsistent) > 0) print(head(as.data.frame(inconsistent), 20))

# ------------------------------------------------------------------
# 5. Check year coverage — every year should appear
# ------------------------------------------------------------------
cat("\n=== YEAR COVERAGE ===\n")
print(table(cat6_df$CALENDAR.YEAR))

cat("\n=== CATEGORY COVERAGE BY YEAR ===\n")
print(table(cat6_df$CALENDAR.YEAR, cat6_df$CATEGORY))

# ------------------------------------------------------------------
# 6. Check for suspiciously large values (potential parsing errors)
#    e.g., two values merged into one
# ------------------------------------------------------------------
cat("\n=== LARGEST AMOUNTS (sanity check for merged values) ===\n")
cat6_df %>%
  arrange(desc(Total_Amount)) %>%
  select(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN, Total_Count, Total_Amount) %>%
  head(20) %>%
  as.data.frame() %>%
  print()

# ------------------------------------------------------------------
# 7. Check for suspiciously small per-person amounts
#    (could indicate a count that leaked into the amount column)
# ------------------------------------------------------------------
cat("\n=== LOWEST PER-PERSON AMOUNTS (< $1) ===\n")
per_person <- cat6_df %>%
  filter(Total_Count > 0) %>%
  mutate(Per_Person = Total_Amount / Total_Count) %>%
  filter(Per_Person < 1) %>%
  select(CALENDAR.YEAR, CATEGORY, AGENCY_CLEAN, Total_Count, Total_Amount, Per_Person)
cat("Rows:", nrow(per_person), "\n")
if (nrow(per_person) > 0) print(as.data.frame(per_person))

# ------------------------------------------------------------------
# 8. Check for institutions that appear in some years but not others
#    (could indicate missed rows during extraction)
# ------------------------------------------------------------------
cat("\n=== CAT 6 INSTITUTIONS NOT APPEARING IN ALL YEARS ===\n")
all_years <- n_distinct(cat6_df$Year)
sporadic <- cat6_df %>%
  group_by(AGENCY_CLEAN) %>%
  summarise(Years_Present = n_distinct(Year), .groups = "drop") %>%
  filter(Years_Present < all_years) %>%
  arrange(Years_Present)
cat("Institutions appearing in fewer than", all_years, "years:", nrow(sporadic), "\n")
if (nrow(sporadic) > 0) print(as.data.frame(sporadic))

# ------------------------------------------------------------------
# 9. Check for blank or unparseable agency names
# ------------------------------------------------------------------
cat("\n=== BLANK/MISSING AGENCY NAMES ===\n")
blank_names <- combined_df %>%
  filter(is.na(AGENCY_CLEAN) | AGENCY_CLEAN == "" | str_detect(AGENCY_CLEAN, "^\\d"))
cat("Rows with blank or numeric agency names:", nrow(blank_names), "\n")
if (nrow(blank_names) > 0) print(as.data.frame(blank_names))