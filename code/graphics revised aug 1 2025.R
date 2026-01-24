library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)

setwd("G:/My Drive/SLLI/FTB Paper/")
combined_df <- read.csv("Private_Use_of_FTB_2018_23_combined.csv")
# Reshape the data to a long format

###how many unique entities
unique_agencies <- dplyr::n_distinct(combined_df$AGENCY_NAME)
unique_agencies


total_offset_columns <- grep("TOTAL_OFFSET_AMOUNT", names(combined_df), value = TRUE)

total_offset_long <- combined_df %>%
  select(AGENCY_NAME, all_of(total_offset_columns)) %>%        # keep only needed columns
  pivot_longer(
    cols = everything()[!names(.) %in% "AGENCY_NAME"],        # all year columns
    names_to = "Year",
    values_to = "Total_Offset_Amount"
  ) %>%
  mutate(
    Year = as.numeric(str_extract(Year, "\\d{4}"))             # extract 4-digit year
  ) %>%
  filter(!is.na(Total_Offset_Amount))

agency_totals_2023 <- total_offset_long %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_NAME) %>%
  summarise(Total_2023 = sum(Total_Offset_Amount, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Total_2023))

top_7_agencies <- head(agency_totals_2023$AGENCY_NAME, 7)

top_7_df <- total_offset_long %>%
  filter(AGENCY_NAME %in% top_7_agencies)

remaining_df <- total_offset_long %>%
  filter(!AGENCY_NAME %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarise(Total_Offset_Amount = sum(Total_Offset_Amount, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_NAME = "Remaining Private Institutions")

plot_df <- bind_rows(top_7_df, remaining_df) %>%
  mutate(AGENCY_NAME = factor(AGENCY_NAME, levels = c(top_7_agencies, "Remaining Private Institutions")))

pat <- c("solid","dashed","dotted","solid","solid","solid","solid","dotdash")

ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_Offset_Amount,
    color    = AGENCY_NAME,
    linetype = AGENCY_NAME,
    group    = AGENCY_NAME
  )
) +
  geom_line(size = 1) +
  scale_color_discrete(name = "Private Institution") +
  scale_linetype_manual(values = pat, name = "Private Institution") +
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
    plot.caption    = element_text(size = 8, face = "italic", hjust = .5)
  )


##################################################################################
library(ggplot2)
library(tidyr)
library(dplyr)
library(scales)
library(stringr)

total_offset_count_columns <- grep("_TOTAL_OFFSET_COUNT$", names(combined_df), value = TRUE)

total_people_long <- combined_df %>%
  select(AGENCY_NAME, all_of(total_offset_count_columns)) %>%
  pivot_longer(
    cols  = -AGENCY_NAME,
    names_to  = "Year",
    values_to = "Total_People_Involved"
  ) %>%
  mutate(
    Year = as.numeric(str_extract(Year, "\\d{4}"))
  ) %>%
  filter(!is.na(Total_People_Involved))

agency_totals_2023 <- total_people_long %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_NAME) %>%
  summarise(Total_2023 = sum(Total_People_Involved, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Total_2023))

top_7_agencies <- head(agency_totals_2023$AGENCY_NAME, 7)

top_7_df <- total_people_long %>%
  filter(AGENCY_NAME %in% top_7_agencies)

remaining_df <- total_people_long %>%
  filter(!AGENCY_NAME %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarise(Total_People_Involved = sum(Total_People_Involved, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_NAME = "Remaining Private Institutions")

plot_df <- bind_rows(top_7_df, remaining_df) %>%
  mutate(AGENCY_NAME = factor(AGENCY_NAME, levels = c(top_7_agencies, "Remaining Private Institutions")))

pat <- c("solid","dashed","dotted","solid","solid","solid","solid","dotdash")

ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_People_Involved,
    color    = AGENCY_NAME,
    linetype = AGENCY_NAME,
    group    = AGENCY_NAME
  )
) +
  geom_line(size = 1) +
  scale_color_discrete(name = "Private Institution") +
  scale_linetype_manual(values = pat, name = "Private Institution") +
  labs(
    title   = "Total Individuals Offset Over Time by Private Institution",
    x       = "Year",
    y       = "Total Individuals Offset",
    caption = "Note: totals for top 7 private institutions in 2023; others aggregated."
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.caption    = element_text(size = 8, face = "italic", hjust = .2)
  )


#########################################################################
#combining lottery and Unclaimed property in one graph
# Identify the columns for LOTTERY_OFFSET_AMOUNT and UNCLAIMED_PROPERTY_OFFSET_AMOUNT using grep
lottery_amount_columns   <- grep("^X?\\d{4}_LOTTERY_OFFSET_AMOUNT$", 
                                 names(combined_df), value = TRUE)
unclaimed_property_columns <- grep("^X?\\d{4}_UNCLAIMED_PROPERTY_OFFSET_AMOUNT$", 
                                   names(combined_df), value = TRUE)

# Create the lottery_amounts and unclaimed_property_amounts dataframes with AGENCY_NAME and relevant year columns
lottery_amounts <- combined_df %>%
  select(AGENCY_NAME, all_of(lottery_amount_columns)) %>%
  rename_with(~ sub("_LOTTERY_OFFSET_AMOUNT", "", .x), all_of(lottery_amount_columns))  # Rename columns to just the year

unclaimed_property_amounts <- combined_df %>%
  select(AGENCY_NAME, all_of(unclaimed_property_columns)) %>%
  rename_with(~ sub("_UNCLAIMED_PROPERTY_OFFSET_AMOUNT", "", .x), all_of(unclaimed_property_columns))  # Rename columns to just the year

# Combine both datasets by summing the corresponding year columns
combined_lottery_property <- lottery_amounts %>%
  left_join(unclaimed_property_amounts, by = "AGENCY_NAME", suffix = c(".lottery", ".property")) %>%  # Join with suffixes for differentiation
  mutate(across(ends_with(".lottery"), ~ replace_na(.x, 0))) %>%  # Replace NA in LOTTERY columns with 0
  mutate(across(ends_with(".property"), ~ replace_na(.x, 0)))  # Replace NA in Property columns with 0

# Sum corresponding year columns and select only the final combined columns
# Sum lottery + property, keep only year columns, drop leading “X”
combined_lottery_property <- combined_lottery_property %>%
  mutate(across(
    ends_with(".lottery"),
    ~ .x + get(sub("\\.lottery$", ".property", cur_column()))
  )) %>%                                              # create summed columns
  rename_with(~ sub("\\.lottery$", "", .x),            # drop “.lottery” suffix
              ends_with(".lottery")) %>%
  select(AGENCY_NAME, matches("^X?\\d{4}$")) %>%       # keep year columns
  rename_with(~ sub("^X", "", .x), -AGENCY_NAME)       # strip leading X

#reshape for plotting
combined_lottery_property_long <- combined_lottery_property %>%
  pivot_longer(
    cols = -AGENCY_NAME,
    names_to = "Year",
    values_to = "Total_Offset_Amount"
  ) %>%
  mutate(Year = as.numeric(Year))

# Calculate total offset amount for each agency for 2023
agency_totals_2023 <- combined_lottery_property_long %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_NAME) %>%
  summarize(Total_2023 = sum(Total_Offset_Amount, na.rm = TRUE)) %>%
  arrange(desc(Total_2023))

# Identify the top 7 agencies based on 2023 totals
top_7_agencies <- agency_totals_2023$AGENCY_NAME[1:7]

# Separate the data for top 7 agencies and the remaining ones
top_7_df <- combined_lottery_property_long %>%
  filter(AGENCY_NAME %in% top_7_agencies)

remaining_df <- combined_lottery_property_long %>%
  filter(!AGENCY_NAME %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarize(Total_Offset_Amount = sum(Total_Offset_Amount, na.rm = TRUE)) %>%
  mutate(AGENCY_NAME = "Remaining Private Institutions")

# Combine the top 7 data with the aggregated remaining data into a new dataframe for plotting
plot_df <- bind_rows(top_7_df, remaining_df)

# Set factor levels for AGENCY_NAME based on 2023 values for sorting in the legend
plot_df$AGENCY_NAME <- factor(plot_df$AGENCY_NAME, levels = c(top_7_agencies, "Remaining Private Institutions"))

# Create the line plot with adjusted y-axis limits
pat <- c("solid","dashed","dotted","solid","solid","solid","solid","dotdash")

ggplot(
  plot_df,
  aes(
    x        = Year,
    y        = Total_Offset_Amount,
    color    = AGENCY_NAME,
    linetype = AGENCY_NAME,
    group    = AGENCY_NAME
  )
) +
  geom_line(size = 1) +
  scale_color_discrete(name = "Private Institution") +
  scale_linetype_manual(values = pat, name = "Private Institution") +
  labs(
    title   = "Total Lottery and Unclaimed Property Offset Amount Over Time by Private Institution",
    x       = "Year",
    y       = "Total Offset Amount",
    caption = "Note: combined Lottery + Unclaimed Property offsets for top 7 institutions (2023) and all others aggregated."
  ) +
  scale_y_continuous(labels = comma, limits = c(0, 7500)) +
  theme_minimal() +
  theme(
    legend.position = "right",
    plot.caption    = element_text(size = 8, face = "italic", hjust = .1)
  )


##############
library(ggplot2)
library(tidyr)
library(dplyr)
library(scales)
library(stringr)

unclaimed_property_amount_columns <- grep("^X?\\d{4}_UNCLAIMED_PROPERTY_OFFSET_AMOUNT$",
                                          names(combined_df), value = TRUE)

unclaimed_property_long <- combined_df %>%
  select(AGENCY_NAME, all_of(unclaimed_property_amount_columns)) %>%
  pivot_longer(
    cols = -AGENCY_NAME,
    names_to = "Year",
    values_to = "Unclaimed_Property_Offset_Amount"
  ) %>%
  mutate(Year = as.numeric(str_extract(Year, "\\d{4}"))) %>%
  filter(!is.na(Unclaimed_Property_Offset_Amount))

agency_totals_2023 <- unclaimed_property_long %>%
  filter(Year == 2023) %>%
  group_by(AGENCY_NAME) %>%
  summarise(Total_2023 = sum(Unclaimed_Property_Offset_Amount, na.rm = TRUE), .groups = "drop") %>%
  arrange(desc(Total_2023))

top_7_agencies <- head(agency_totals_2023$AGENCY_NAME, 7)

top_7_df <- unclaimed_property_long %>%
  filter(AGENCY_NAME %in% top_7_agencies)

remaining_df <- unclaimed_property_long %>%
  filter(!AGENCY_NAME %in% top_7_agencies) %>%
  group_by(Year) %>%
  summarise(Unclaimed_Property_Offset_Amount = sum(Unclaimed_Property_Offset_Amount, na.rm = TRUE), .groups = "drop") %>%
  mutate(AGENCY_NAME = "Remaining Private Institutions")

plot_df <- bind_rows(top_7_df, remaining_df) %>%
  mutate(AGENCY_NAME = factor(AGENCY_NAME, levels = c(top_7_agencies, "Remaining Private Institutions")))

ggplot(plot_df, aes(x = Year, y = Unclaimed_Property_Offset_Amount, color = AGENCY_NAME, group = AGENCY_NAME)) +
  geom_line(size = 1) +
  labs(
    title = "Unclaimed Property Offset Amount Over Time by Private Institution",
    x = "Year",
    y = "Unclaimed Property Offset Amount"
  ) +
  scale_y_continuous(labels = comma) +
  theme_minimal() +
  theme(legend.position = "right") +
  scale_color_discrete(name = "Private Institution")

############################################################
########################################################################################################################
#table
library(dplyr)

# column groups
cnt_tot  <- grep("_TOTAL_OFFSET_COUNT$",              names(combined_df), value = TRUE)
amt_tot  <- grep("_TOTAL_OFFSET_AMOUNT$",             names(combined_df), value = TRUE)
cnt_il   <- c(grep("_UNCLAIMED_PROPERTY_OFFSET_COUNT$",names(combined_df), value = TRUE),
              grep("_LOTTERY_OFFSET_COUNT$",           names(combined_df), value = TRUE))
amt_il   <- c(grep("_UNCLAIMED_PROPERTY_OFFSET_AMOUNT$",names(combined_df), value = TRUE),
              grep("_LOTTERY_OFFSET_AMOUNT$",           names(combined_df), value = TRUE))

summary_tbl <- combined_df %>% 
  rowwise() %>% 
  mutate(
    Years_Appearing                   = sum(c_across(all_of(cnt_tot)) > 0),
    `Total Individuals Offset`        = sum(c_across(all_of(cnt_tot)),  na.rm = TRUE),
    `Total Offset Amount`             = sum(c_across(all_of(amt_tot)),  na.rm = TRUE),
    `Total  Unclaimed Property+Lottery Amounts` = sum(c_across(all_of(amt_il)),  na.rm = TRUE),
    `Total Individuals Illegally Offset`       = sum(c_across(all_of(cnt_il)),  na.rm = TRUE)
  ) %>% 
  ungroup() %>% 
  select(AGENCY_NAME, Years_Appearing,
         `Total Individuals Offset`,
         `Total Offset Amount`,
         `Total  Unclaimed Property+Lottery Amounts`,
         `Total Individuals Illegally Offset`)

write.csv(summary_tbl, "agency_summary.csv", row.names = FALSE)
