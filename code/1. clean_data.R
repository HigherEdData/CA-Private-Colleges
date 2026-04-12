library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)

setwd("G:/My Drive/SLLI/FTB Paper/")
combined_df <- read.csv("final code/d_IIC_Offset_Data_2018-2023.csv") #PDF extraction in Python

# ------------------------------------------------------------------
# Step 1: Strip trailing numeric junk from AGENCY.NAME
# The PDF extraction sometimes lets count/amount values from
# adjacent columns leak into the name field.
# Pattern: one or more trailing (count or $amount) tokens.
# e.g. "KERN COUNTY TREASURER-TAX COLLECTO 52 $1,234.56"
#    → "KERN COUNTY TREASURER-TAX COLLECTO"
# ------------------------------------------------------------------
combined_df <- combined_df %>%
  mutate(
    AGENCY_CLEAN = AGENCY.NAME %>%
      str_remove("(\\s+(\\d[\\d,]*|\\$[\\d,]+\\.\\d{2}))+\\s*$") %>%
      str_trim()
  )

# ------------------------------------------------------------------
# Step 2: Reconcile truncated names
# Long names sometimes get cut at slightly different points across
# PDF pages (e.g. "...TAX COLLECTOR" vs "...TAX COLLECTO").
# We merge these by treating a shorter name as identical to a
# longer one ONLY when:
#   (a) the shorter name is >= 25 characters  (avoids false matches)
#   (b) the longer name starts with the shorter name
#   (c) the length difference is at most 5 characters
# ------------------------------------------------------------------
unique_names <- unique(combined_df$AGENCY_CLEAN)
unique_names <- unique_names[order(nchar(unique_names))]   # shortest first

# Start with identity mapping
name_map <- setNames(unique_names, unique_names)

for (short in unique_names) {
  if (nchar(short) < 25) next
  
  candidates <- unique_names[
    nchar(unique_names) > nchar(short) &
      nchar(unique_names) <= nchar(short) + 5 &
      startsWith(unique_names, short)
  ]
  
  if (length(candidates) > 0) {
    name_map[short] <- candidates[which.max(nchar(candidates))]
  }
}

# Resolve any chains (A→B and B→C becomes A→C)
changed <- TRUE
while (changed) {
  changed <- FALSE
  for (nm in names(name_map)) {
    target <- name_map[[nm]]
    if (name_map[[target]] != target) {
      name_map[[nm]] <- name_map[[target]]
      changed <- TRUE
    }
  }
}

combined_df <- combined_df %>%
  mutate(AGENCY_CLEAN = unname(name_map[AGENCY_CLEAN]))

# ------------------------------------------------------------------
# Step 3: Manual overrides for known abbreviations / aliases
# ------------------------------------------------------------------

# Need to do this manually because UNIVERSITY OF SOUTHERN CALIFORNIA 
# appears different in the 2018 PRA document and in the 2019-2023 document
# have also grouped Stanford and Stanford Redwood City Campus since they 
# are the same legal entity

manual_map <- c(
  "UNIVERSITY OF SOUTHERN CALIF."  = "UNIVERSITY OF SOUTHERN CALIFORNIA",
  "UNIVERSITY OF SOUTHERN CALIF"   = "UNIVERSITY OF SOUTHERN CALIFORNIA",
  "STANFORD REDWOOD CITY CAMPUS"   = "STANFORD UNIVERSITY"
)

combined_df <- combined_df %>%
  mutate(
    AGENCY_CLEAN = ifelse(AGENCY_CLEAN %in% names(manual_map),
                          manual_map[AGENCY_CLEAN],
                          AGENCY_CLEAN)
  )

##clean column names etc in combined_df
# --- Clean up combined_df ---
combined_df <- combined_df %>%
  mutate(
    Year = as.numeric(str_extract(CALENDAR.YEAR, "\\d{4}")),
    PIT_Count           = replace_na(as.numeric(gsub("[,]", "", X1..PIT.OFFSET.COUNT)), 0),
    PIT_Amount          = replace_na(as.numeric(gsub("[\\$,]", "", X1..PIT.OFFSET.AMOUNT)), 0),
    Lottery_Count       = replace_na(as.numeric(gsub("[,]", "", X2..LOTTERY.OFFSET.COUNT)), 0),
    Lottery_Amount      = replace_na(as.numeric(gsub("[\\$,]", "", X2..LOTTERY.OFFSET.AMOUNT)), 0),
    UCP_Count           = replace_na(as.numeric(gsub("[,]", "", X3..UNCLAIMED.PROPERTY.OFFSET.COUNT)), 0),
    UCP_Amount          = replace_na(as.numeric(gsub("[\\$,]", "", X3..UNCLAIMED.PROPERTY.OFFSET.AMOUNT)), 0),
    Total_Count         = replace_na(as.numeric(gsub("[,]", "", Total.OFFSET.COUNT)), 0),
    Total_Amount        = replace_na(as.numeric(gsub("[\\$,]", "", Total.OFFSET.AMOUNT)), 0),
    Lottery_UCP_Amount  = Lottery_Amount + UCP_Amount,
    Lottery_UCP_Count   = Lottery_Count + UCP_Count
  )

# Filter to category 6 (private schools)
cat6_df <- combined_df %>%
  filter(CATEGORY == "6 - OTHER STATES")

write.csv(combined_df, "final code/cleaned_IIC_Offset_Data_2018-2023.csv", row.names = FALSE) 
write.csv(cat6_df, "final code/cleaned_IIC_Offset_Data_2018-2023-cat6only.csv", row.names = FALSE)
