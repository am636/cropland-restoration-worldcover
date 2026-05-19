# Reclassify ESA WorldCover classes into a smaller broad land-cover legend.

library(terra)
library(readr)
library(tibble)
library(dplyr)


# User settings
aoi_name <- "east_fife_demo"
years <- c(2020, 2021)


dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/qa", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# ESA WorldCover class values and names are taken from the official product legend.
worldcover_lookup <- tibble(
  worldcover_value = c(10, 20, 30, 40, 50, 60, 70, 80, 90, 95, 100),
  worldcover_class = c(
    "Tree cover",
    "Shrubland",
    "Grassland",
    "Cropland",
    "Built-up",
    "Bare or sparse vegetation",
    "Snow and ice",
    "Permanent water bodies",
    "Herbaceous wetland",
    "Mangroves",
    "Moss and lichen"
  ),
  broad_value = c(1, 2, 2, 3, 4, 5, 5, 6, 6, 6, 2),
  broad_class = c(
    "tree_cover",
    "grass_shrub",
    "grass_shrub",
    "cropland",
    "built_up",
    "bare_sparse",
    "bare_sparse",
    "water_wetland",
    "water_wetland",
    "water_wetland",
    "grass_shrub"
  )
)

broad_lookup <- worldcover_lookup |>
  distinct(broad_value, broad_class) |>
  arrange(broad_value)

write_csv(worldcover_lookup, "outputs/qa/worldcover_reclassification_lookup.csv")
write_csv(broad_lookup, "outputs/qa/landcover_broad_lookup.csv")

reclass_matrix <- worldcover_lookup |>
  select(worldcover_value, broad_value) |>
  as.matrix()

area_by_class <- function(r, year) {
  cell_area <- cellSize(r, unit = "ha")
  
  area <- zonal(cell_area, r, fun = "sum", na.rm = TRUE) |>
    as_tibble()
  names(area) <- c("broad_value", "area_ha")
  
  area <- area |>
    mutate(broad_value = as.integer(broad_value))
  
  cells <- freq(r) |>
    as_tibble() |>
    rename(broad_value = value, cell_count = count) |>
    select(broad_value, cell_count) |>
    mutate(broad_value = as.integer(broad_value))
  
  cells |>
    left_join(area, by = "broad_value") |>
    left_join(broad_lookup, by = "broad_value") |>
    mutate(
      year = year,
      area_km2 = area_ha / 100,
      area_percent = 100 * area_ha / sum(area_ha, na.rm = TRUE)
    ) |>
    select(
      year,
      broad_value,
      broad_class,
      cell_count,
      area_ha,
      area_km2,
      area_percent
    ) |>
    arrange(year, broad_value)
}

plot_broad <- function(r, year) {
  png(
    sprintf("outputs/figures/landcover_broad_%s_map.png", year),
    width = 1300,
    height = 900,
    res = 150
  )
  
  plot(
    r,
    main = sprintf("Broad land-cover classes, %s", year),
    col = c("darkgreen", "yellowgreen", "khaki", "grey45", "tan", "steelblue")
  )
  
  dev.off()
}

area_tables <- list()

for (year in years) {
  in_file <- sprintf(
    "data/processed/worldcover_%s_%s.tif",
    year,
    aoi_name
  )
  
  if (!file.exists(in_file)) {
    stop("Input file not found: ", in_file)
  }
  
  r <- rast(in_file)
  
  broad <- classify(r, reclass_matrix, others = NA)
  names(broad) <- paste0("landcover_broad_", year)
  
  out_file <- sprintf(
    "data/processed/landcover_broad_%s_%s.tif",
    year,
    aoi_name
  )
  
  writeRaster(
    broad,
    out_file,
    overwrite = TRUE,
    datatype = "INT1U",
    gdal = c("COMPRESS=LZW")
  )
  
  area_tables[[as.character(year)]] <- area_by_class(broad, year)
  plot_broad(broad, year)
}

area_summary <- bind_rows(area_tables)

write_csv(
  area_summary,
  "outputs/tables/landcover_broad_area_summary.csv"
)

print(area_summary)
