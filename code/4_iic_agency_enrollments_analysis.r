library(dplyr)
library(ggplot2)
library(rlang)
library(scales)

library(readr)

enrollments <- read_csv("G:/My Drive/SLLI/FTB Paper/enrollments.csv")
View(enrollments)

# parse m/d/yy → Date
library(lubridate)
enrollments$`Enrollment Date` <- mdy(enrollments$`Enrollment Date`)

# verify
range(enrollments$`Enrollment Date`, na.rm = TRUE)
sum(is.na(enrollments$`Enrollment Date`))


# pick the school column automatically
char_cols <- names(enrollments)[sapply(enrollments, is.character)]
school_col <- if ("School" %in% names(enrollments)) {
  "School"
} else if ("AGENCY_NAME" %in% names(enrollments)) {
  "AGENCY_NAME"
} else {
  setdiff(char_cols, "Enrollment Date")[1]
}

# order schools by first appearance
enr <- enrollments %>%
  mutate(
    School = .data[[school_col]],
    `Enrollment Date` = as.Date(`Enrollment Date`)  # no-op if already Date
  ) %>%
  group_by(School) %>%
  mutate(first_date = min(`Enrollment Date`, na.rm = TRUE)) %>%
  ungroup() %>%
  mutate(School = reorder(School, first_date))
library(dplyr)
library(lubridate)
library(ggplot2)
library(scales)

# yearly breaks across full range
xrng <- range(enr$`Enrollment Date`, na.rm = TRUE)
x0   <- floor_date(xrng[1], "year")
x1   <- ceiling_date(xrng[2], "year")
year_breaks <- seq(x0, x1, by = "1 year")

# caption: all 2013 enrollments span and days (inclusive)
d2013   <- filter(enr, year(`Enrollment Date`) == 2013)
start13 <- min(d2013$`Enrollment Date`, na.rm = TRUE)
end13   <- max(d2013$`Enrollment Date`, na.rm = TRUE)
days13  <- as.integer(end13 - start13) + 1L
cap <- sprintf(
  "All 2013 enrollments occurred between %s and %s (%d days)\nSource: Controller PRA Production Parts 1 & 2",
  format(start13, "%b %d"), format(end13, "%b %d"), days13
)


ggplot(enr, aes(x = `Enrollment Date`, y = School)) +
      geom_point(size = 1.6, alpha = 0.8, position = position_jitter(height = 0.15)) +
      scale_x_date(
        limits       = c(x0, x1),
        breaks       = year_breaks,            # Jan 1 each year → tick/gridline at year
        labels       = label_date("%Y"),
        minor_breaks = NULL,
        expand       = expansion(mult = c(0.01, 0.01))
      ) +
      labs(
        title   = "Private School Enrollment in Intercept Program by Date",
        x       = "",
        y       = "",
        caption = cap
      ) +
      theme_minimal(base_size = 11) +
      theme(
        panel.grid.minor.x = element_blank(),
        axis.text.x        = element_text(angle = 0, hjust = 0.5, vjust = 0.5)
      )
    