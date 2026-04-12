library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)

##

setwd("G:/My Drive/SLLI/FTB Paper/")
combined_df<- read.csv("final code/cleaned_IIC_Offset_Data_2018-2023.csv") #cleaned csv of all institutions
cat6_df<- read.csv("final code/cleaned_IIC_Offset_Data_2018-2023-cat6only.csv") #cleaned csv of CAT 6 institutions only

#####################
####################################
# ------------------------------------------------------------------
# Count unique agencies
# ------------------------------------------------------------------
unique_agencies <- n_distinct(combined_df$AGENCY_CLEAN)
unique_agencies

unique_categories <- dplyr::n_distinct(combined_df$CATEGORY)
unique_categories

#################################################################################
#################################################################################
## analysis / graphs begin

# ------------------------------------------------------------------
# Top private institutions
# ------------------------------------------------------------------

#using cat6_df from above

agency_totals_2023 <- cat6_df %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_CLEAN) %>%
  summarise(Total_2023 = sum(Total_Amount, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Total_2023))

top_7_agencies <- head(agency_totals_2023$AGENCY_CLEAN, 7)

# need to group at this level because some agency names appear twice in the same year 
# e.g., STANFORD UNIVERSITY in 2020
top_7_df <- cat6_df %>%
  filter(AGENCY_CLEAN %in% top_7_agencies) %>%
  group_by(AGENCY_CLEAN, Year) %>%
  summarise(Total_Amount = sum(Total_Amount, na.rm = TRUE), .groups = "drop")

remaining_df <- cat6_df %>%
  filter(!AGENCY_CLEAN %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarise(Total_Amount = sum(Total_Amount, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_CLEAN = "Remaining Private Institutions")

plot_df <- bind_rows(top_7_df, remaining_df) %>%
  mutate(AGENCY_PLOT = factor(AGENCY_CLEAN, levels = c(top_7_agencies, "Remaining Private Institutions")))

# --- 8 distinct linetypes (including two custom hex-string patterns) ---
line_patterns <- c(
  "solid",      # _______________
  
  "dashed",     # _ _ _ _ _ _ _ _
  "dotted",     # ...............
  "dotdash",    # _ . _ . _ . _ .
  "longdash",   # __ __ __ __ __
  "twodash",    # _ _ __ _ _ __ _
  "1343",       # custom short-long
  "F282"        # custom long-short-short
)

# --- 8 colours chosen so their *luminance* values spread evenly in grayscale ---
line_colors <- c(
  "#000000",   # black
  "#D55E00",   # vermillion  → dark gray
  
  "#0072B2",   # blue        → medium-dark
  "#009E73",   # green       → medium
  "#CC79A7",   # pink        → medium-light
  "#E69F00",   # orange      → light
  "#56B4E9",   # sky blue    → lighter
  "#999999"    # gray        → light gray
)

# --- 8 distinct point shapes (one per line) ---
point_shapes <- c(16, 17, 15, 3, 8, 18, 4, 1)
#                  ●   ▲   ■   +   ✳   ◆   ×   ○

ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_Amount,
    color    = AGENCY_PLOT,
    linetype = AGENCY_PLOT,
    shape    = AGENCY_PLOT,
    group    = AGENCY_PLOT
  )
) +
  geom_line(size = 1) +
  geom_point(size = 2.5) +
  scale_color_manual(values = line_colors,    name = "Private Institution") +
  scale_linetype_manual(values = line_patterns, name = "Private Institution") +
  scale_shape_manual(values = point_shapes,   name = "Private Institution") +
  labs(
    title   = "Total Offset Amount Over Time by Private Institution",
    x       = "Year",
    y       = "Total Offset Amount",
    caption = "Note: totals for top 7 private institutions in 2023; others aggregated."
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.caption    = element_text(size = 8, face = "italic", hjust = 0.5)
  )

##################################################################################
library(ggplot2)
library(tidyr)
library(dplyr)
library(scales)
library(stringr)

total_offset_count_columns <- grep("TOTAL.OFFSET.COUNT$", names(combined_df), value = TRUE)

total_people_long <- cat6_df %>%
  mutate(
    Year = as.numeric(str_extract(CALENDAR.YEAR, "\\d{4}")),
    Total_People_Involved = replace_na(as.numeric(gsub("[,]", "", Total.OFFSET.COUNT)), 0)
  ) %>%
  select(AGENCY_CLEAN, CATEGORY, Year, Total_People_Involved) %>%
  filter(Total_People_Involved > 0)


agency_totals_2023 <- total_people_long %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_CLEAN) %>%
  summarise(Total_2023 = sum(Total_People_Involved, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Total_2023))

top_7_agencies <- head(agency_totals_2023$AGENCY_CLEAN, 7)

top_7_df <- total_people_long %>%
  filter(AGENCY_CLEAN %in% top_7_agencies) %>%
  group_by(AGENCY_CLEAN, Year) %>%
  summarise(Total_People_Involved = sum(Total_People_Involved, na.rm = TRUE), .groups = "drop")

remaining_df <- total_people_long %>%
  filter(!AGENCY_CLEAN %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarise(Total_People_Involved = sum(Total_People_Involved, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_CLEAN = "Remaining Private Institutions")

plot_df <- bind_rows(top_7_df, remaining_df) %>%
  mutate(AGENCY_CLEAN = factor(AGENCY_CLEAN, levels = c(top_7_agencies, "Remaining Private Institutions")))

# --- 8 distinct linetypes ---
line_patterns <- c(
  "solid",
  "dashed",
  "dotted",
  "dotdash",
  "longdash",
  "twodash",
  "1343",
  "F282"
)

# --- 8 colours with spread-out grayscale luminance ---
line_colors <- c(
  "#000000",
  "#D55E00",
  "#0072B2",
  "#009E73",
  "#CC79A7",
  "#E69F00",
  "#56B4E9",
  "#999999"
)

# --- 8 distinct point shapes ---
point_shapes <- c(16, 17, 15, 3, 8, 18, 4, 1)

ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_People_Involved,
    color    = AGENCY_CLEAN,
    linetype = AGENCY_CLEAN,
    shape    = AGENCY_CLEAN,
    group    = AGENCY_CLEAN
  )
) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  scale_color_manual(values = line_colors,      name = "Other State") +
  scale_linetype_manual(values = line_patterns,  name = "Other State") +
  scale_shape_manual(values = point_shapes,      name = "Other State") +
  labs(
    title   = "Total Individuals Offset Over Time by Other State",
    x       = "Year",
    y       = "Total Individuals Offset",
    caption = "Note: totals for top 7 other states in 2023; others aggregated."
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.caption    = element_text(size = 8, face = "italic", hjust = 0.5)
  )

#########################################################################
#########################################################################
#########################################################################

# ------------------------------------------------------------------
# Lottery + Unclaimed Property combined, Category 6
# ------------------------------------------------------------------

### graph top institutions getting illegal offsets

lottery_property_df <- combined_df %>%
  filter(CATEGORY == "6 - OTHER STATES") %>%
  mutate(
    Year          = as.numeric(str_extract(CALENDAR.YEAR, "\\d{4}")),
    Lotto_Amount  = replace_na(as.numeric(gsub("[\\$,]", "", X2..LOTTERY.OFFSET.AMOUNT)), 0),
    UCP_Amount    = replace_na(as.numeric(gsub("[\\$,]", "", X3..UNCLAIMED.PROPERTY.OFFSET.AMOUNT)), 0),
    Combined_Amount = Lotto_Amount + UCP_Amount
  ) %>%
  group_by(AGENCY_CLEAN, Year) %>%
  summarise(Total_Amount = sum(Combined_Amount, na.rm = TRUE), .groups = "drop")

# --- Institutions that exceeded $1,000 in ANY year get their own line ---
big_agencies <- lottery_property_df %>%
  filter(Total_Amount > 1000) %>%
  distinct(AGENCY_CLEAN) %>%
  pull(AGENCY_CLEAN)

cat("Institutions with >$1,000 in at least one year:", length(big_agencies), "\n")

# --- Order by total amount across all years (descending) ---
agency_order <- lottery_property_df %>%
  filter(AGENCY_CLEAN %in% big_agencies) %>%
  group_by(AGENCY_CLEAN) %>%
  summarise(Grand_Total = sum(Total_Amount, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Grand_Total)) %>%
  pull(AGENCY_CLEAN)

top_df <- lottery_property_df %>%
  filter(AGENCY_CLEAN %in% big_agencies)

remaining_df <- lottery_property_df %>%
  filter(!AGENCY_CLEAN %in% big_agencies) %>%
  group_by(Year) %>%
  summarise(Total_Amount = sum(Total_Amount, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_CLEAN = "Remaining Institutions")

plot_df <- bind_rows(top_df, remaining_df) %>%
  mutate(AGENCY_PLOT = factor(AGENCY_CLEAN, 
                              levels = c(agency_order, "Remaining Institutions")))

# --- Dynamic aesthetics ---
n_groups <- n_distinct(plot_df$AGENCY_PLOT)

line_colors   <- c(scales::hue_pal()(n_groups - 1), "#999999")
point_shapes  <- rep(c(16, 17, 15, 3, 8, 18, 4, 1, 0, 2, 5, 6), length.out = n_groups)
line_patterns <- rep(c("solid", "dashed", "dotted", "dotdash", "longdash", "twodash"), 
                     length.out = n_groups)

# --- Plot ---
ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_Amount,
    color    = AGENCY_PLOT,
    linetype = AGENCY_PLOT,
    shape    = AGENCY_PLOT,
    group    = AGENCY_PLOT
  )
) +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  scale_color_manual(values = line_colors,       name = "Private Institution") +
  scale_linetype_manual(values = line_patterns,  name = "Private Institution") +
  scale_shape_manual(values = point_shapes,      name = "Private Institution") +
  labs(
    title   = "Lottery and Unclaimed Property Offset Amounts by Private Institution",
    x       = "Year",
    y       = "Total Offset Amount",
    caption = "Note: Institutions with >$1,000 in any year shown individually; all others aggregated \n(17 unique institutions in this time period)."
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.caption    = element_text(size = 8, face = "italic", hjust = 0.5)
  )


#####
##Lottery and unclaimed funds summary table
##

library(officer)
library(flextable)

# --- Build summary_tbl from cat6_df ---
summary_tbl <- cat6_df %>%
  group_by(AGENCY_CLEAN) %>%
  summarise(
    Years_Appearing                              = n_distinct(Year[Total_Count > 0]),
    `Total Individuals Offset`                   = sum(Total_Count, na.rm = TRUE),
    `Total Offset Amount`                        = sum(Total_Amount, na.rm = TRUE),
    `Total Unclaimed Property+Lottery Amounts`    = sum(Lottery_UCP_Amount, na.rm = TRUE),
    `Total Individuals Illegally Offset`         = sum(Lottery_UCP_Count, na.rm = TRUE),
    .groups = "drop"
  )

# --- Format and save as flextable ---
border_h     <- fp_border(color = "gray70", width = 0.5)
border_thick <- fp_border(color = "black", width = 1.5)

ft <- summary_tbl %>%
  arrange(AGENCY_CLEAN) %>%
  mutate(
    `Total Offset Amount` = ifelse(`Total Offset Amount` == 0, "",
                                   paste0("$", formatC(`Total Offset Amount`, format = "f", digits = 0, big.mark = ","))),
    `Total Unclaimed Property+Lottery Amounts` = ifelse(`Total Unclaimed Property+Lottery Amounts` == 0, "",
                                                        paste0("$", formatC(`Total Unclaimed Property+Lottery Amounts`, format = "f", digits = 0, big.mark = ","))),
    `Total Individuals Offset` = ifelse(`Total Individuals Offset` == 0, "",
                                        formatC(`Total Individuals Offset`, format = "d", big.mark = ",")),
    `Total Individuals Illegally Offset` = ifelse(`Total Individuals Illegally Offset` == 0, "",
                                                  formatC(`Total Individuals Illegally Offset`, format = "d", big.mark = ","))
  ) %>%
  rename(Agency = AGENCY_CLEAN) %>%
  flextable() %>%
  bold(part = "header") %>%
  align(j = -1, align = "right", part = "all") %>%
  align(j = 1, align = "left", part = "all") %>%
  bg(i = seq(2, nrow(summary_tbl), 2), bg = "#F2F2F2") %>%
  hline(part = "body", border = border_h) %>%
  hline_top(part = "header", border = border_thick) %>%
  hline_bottom(part = "header", border = border_thick) %>%
  hline_bottom(part = "body", border = border_thick) %>%
  fontsize(size = 8, part = "all") %>%
  padding(padding = 2, part = "all") %>%
  width(j = "Agency", width = 2) %>%
  width(j = "Years_Appearing", width = 0.6) %>%
  width(j = "Total Individuals Offset", width = 0.8) %>%
  width(j = "Total Offset Amount", width = 1) %>%
  width(j = "Total Unclaimed Property+Lottery Amounts", width = 1.2) %>%
  width(j = "Total Individuals Illegally Offset", width = 0.9) %>%
  set_caption("Summary of Offset Amounts and Individuals by Agency (Category 6)")

save_as_docx(
  ft,
  path = "Agency_Summary_Table.docx",
  pr_section = prop_section(
    page_size = page_size(orient = "portrait")
  )
)

ft

########

#numbers for paper
totals <- lottery_property_df %>%
  summarise(
    Total_All_Years  = sum(Total_Amount, na.rm = TRUE),
    Num_Years        = n_distinct(Year),
    Average_Per_Year = Total_All_Years / Num_Years
  )

total_2023 <- lottery_property_df %>%
  filter(Year == 2023) %>%
  summarise(Total_2023 = sum(Total_Amount, na.rm = TRUE))

cat("Lottery + Unclaimed Property Offsets (Category 6 - Private Institutions)\n")
cat("-----------------------------------------------------------------------\n")
cat("Total (all years):  $", formatC(totals$Total_All_Years, format = "f", digits = 2, big.mark = ","), "\n")
cat("Number of years:    ", totals$Num_Years, "\n")
cat("Average per year:   $", formatC(totals$Average_Per_Year, format = "f", digits = 2, big.mark = ","), "\n")
cat("Total (2023 only):  $", formatC(total_2023$Total_2023, format = "f", digits = 2, big.mark = ","), "\n")

############################################################
########################################################################################################################

library(officer)

# --- Build amounts and counts from already-cleaned cat6_df ---
summary_both <- cat6_df %>%
  group_by(AGENCY_CLEAN, Year) %>%
  summarise(
    Amount = sum(Lottery_UCP_Amount, na.rm = TRUE),
    Count  = sum(Lottery_UCP_Count, na.rm = TRUE),
    .groups = "drop"
  )

# Amounts wide
amounts_wide <- summary_both %>%
  select(AGENCY_CLEAN, Year, Amount) %>%
  pivot_wider(names_from = Year, values_from = Amount, values_fill = 0) %>%
  mutate(Total = rowSums(select(., where(is.numeric)))) %>%
  arrange(AGENCY_CLEAN)

institution_order <- amounts_wide$AGENCY_CLEAN

# Counts wide (match order)
counts_wide <- summary_both %>%
  select(AGENCY_CLEAN, Year, Count) %>%
  pivot_wider(names_from = Year, values_from = Count, values_fill = 0) %>%
  mutate(Total = rowSums(select(., where(is.numeric)))) %>%
  slice(match(institution_order, AGENCY_CLEAN))

# --- Format as strings ---
year_cols <- setdiff(names(amounts_wide), "AGENCY_CLEAN")

amounts_str <- amounts_wide %>%
  mutate(across(all_of(year_cols), ~ ifelse(.x == 0, "",
                                            paste0("$", formatC(.x, format = "f", digits = 0, big.mark = ","))))) %>%
  rename(`Private Institution` = AGENCY_CLEAN)

counts_str <- counts_wide %>%
  mutate(across(all_of(year_cols), ~ ifelse(.x == 0, "",
                                            paste0("(n=", formatC(.x, format = "d", big.mark = ","), ")")))) %>%
  mutate(AGENCY_CLEAN = "") %>%
  rename(`Private Institution` = AGENCY_CLEAN)

# --- Interleave: amount row then count row per institution ---
n_inst <- nrow(amounts_str)
display_table <- bind_rows(
  lapply(1:n_inst, function(i) bind_rows(amounts_str[i, ], counts_str[i, ]))
)

# --- Build flextable ---
border_h     <- fp_border(color = "gray70", width = 0.5)
border_thick <- fp_border(color = "black", width = 1.5)

count_rows <- seq(2, nrow(display_table), 2)
shade_institutions <- seq(2, n_inst, 2)
shade_rows <- unlist(lapply(shade_institutions, function(i) c(2*i - 1, 2*i)))

ft <- display_table %>%
  flextable() %>%
  bold(part = "header") %>%
  align(j = -1, align = "right", part = "all") %>%
  align(j = 1, align = "left", part = "all") %>%
  italic(i = count_rows, part = "body") %>%
  fontsize(size = 8, part = "all") %>%
  fontsize(size = 7, i = count_rows, part = "body") %>%
  bg(i = shade_rows, bg = "#F2F2F2") %>%
  hline(i = count_rows, part = "body", border = border_h) %>%
  hline_top(part = "header", border = border_thick) %>%
  hline_bottom(part = "header", border = border_thick) %>%
  hline_bottom(part = "body", border = border_thick) %>%
  padding(padding = 2, part = "all") %>%
  width(j = "Private Institution", width = 2) %>%
  autofit(add_w = 0) %>%
  set_caption("Lottery and Unclaimed Property Offset Amounts by Private Institution (Category 6)\nParentheses show number of individuals.")

save_as_docx(
  ft,
  path = "Lottery_UCP_Offsets_Cat6_Table.docx",
  pr_section = prop_section(
    page_size = page_size(orient = "landscape")
  )
)

ft