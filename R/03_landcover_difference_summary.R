# Summarise broad land-cover differences between 2020 and 2021.

library(terra)
library(readr)
library(tibble)
library(dplyr)


# User settings
aoi_name <- "east_fife_demo"
from_year <- 2020
to_year <- 2021
year_label <- paste0(from_year, "_", to_year)


dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/qa", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

lookup <- read_csv(
  "outputs/qa/landcover_broad_lookup.csv",
  show_col_types = FALSE
) |>
  mutate(broad_value = as.integer(broad_value))

from_file <- sprintf(
  "data/processed/landcover_broad_%s_%s.tif",
  from_year,
  aoi_name
)

to_file <- sprintf(
  "data/processed/landcover_broad_%s_%s.tif",
  to_year,
  aoi_name
)

if (!file.exists(from_file)) {
  stop("Input file not found: ", from_file)
}

if (!file.exists(to_file)) {
  stop("Input file not found: ", to_file)
}

lc_from <- rast(from_file)
lc_to <- rast(to_file)

if (!compareGeom(lc_from, lc_to, stopOnError = FALSE)) {
  stop("The reclassified rasters are not aligned.")
}

cell_area <- cellSize(lc_from, unit = "ha")

# Combining class codes gives a compact transition code, for example 203 = class 2 to class 3.
transition <- lc_from * 100 + lc_to
names(transition) <- paste0("transition_", year_label)

writeRaster(
  transition,
  sprintf(
    "data/processed/landcover_broad_transition_%s_%s.tif",
    year_label,
    aoi_name
  ),
  overwrite = TRUE,
  datatype = "INT2U",
  gdal = c("COMPRESS=LZW")
)

transition_area <- zonal(cell_area, transition, fun = "sum", na.rm = TRUE) |>
  as_tibble()
names(transition_area) <- c("transition_code", "area_ha")

transition_area <- transition_area |>
  mutate(transition_code = as.integer(transition_code))

transition_cells <- freq(transition) |>
  as_tibble() |>
  rename(transition_code = value, cell_count = count) |>
  select(transition_code, cell_count) |>
  mutate(transition_code = as.integer(transition_code))

transition_table <- transition_cells |>
  left_join(transition_area, by = "transition_code") |>
  mutate(
    from_value = as.integer(floor(transition_code / 100)),
    to_value = as.integer(transition_code %% 100),
    area_km2 = area_ha / 100,
    area_percent = 100 * area_ha / sum(area_ha, na.rm = TRUE)
  ) |>
  left_join(
    rename(lookup, from_value = broad_value, from_class = broad_class),
    by = "from_value"
  ) |>
  left_join(
    rename(lookup, to_value = broad_value, to_class = broad_class),
    by = "to_value"
  ) |>
  select(
    from_value,
    from_class,
    to_value,
    to_class,
    cell_count,
    area_ha,
    area_km2,
    area_percent
  ) |>
  arrange(from_value, to_value)

write_csv(
  transition_table,
  sprintf("outputs/tables/landcover_broad_transition_%s.csv", year_label)
)

stable_changed <- ifel(lc_from == lc_to, 0, 1)
names(stable_changed) <- "broad_class_difference"

writeRaster(
  stable_changed,
  sprintf(
    "data/processed/landcover_broad_difference_%s_%s.tif",
    year_label,
    aoi_name
  ),
  overwrite = TRUE,
  datatype = "INT1U",
  gdal = c("COMPRESS=LZW")
)

difference_summary <- freq(stable_changed) |>
  as_tibble() |>
  rename(difference_value = value, cell_count = count) |>
  mutate(
    difference_value = as.integer(difference_value),
    difference_type = if_else(
      difference_value == 0,
      "same_broad_class",
      "different_broad_class"
    ),
    percent = 100 * cell_count / sum(cell_count)
  ) |>
  select(
    difference_value,
    difference_type,
    cell_count,
    percent
  )

write_csv(
  difference_summary,
  sprintf("outputs/tables/landcover_broad_difference_summary_%s.csv", year_label)
)

png(
  sprintf("outputs/figures/landcover_broad_difference_%s_map.png", year_label),
  width = 1300,
  height = 900,
  res = 150
)

plot(
  stable_changed,
  main = sprintf("Broad class difference, %s to %s", from_year, to_year),
  col = c("grey85", "firebrick"),
  axes = FALSE,
  legend = FALSE
)

legend(
  "topright",
  legend = c("Same broad class", "Different broad class"),
  fill = c("grey85", "firebrick"),
  bty = "n",
  inset = 0.02
)

dev.off()

note <- c(
  "Broad class differences are summarised for workflow demonstration.",
  "They should not be treated as field-validated land-cover change."
)

writeLines(
  note,
  sprintf("outputs/qa/change_interpretation_note_%s.txt", year_label)
)

print(difference_summary)
print(head(transition_table, 20))
