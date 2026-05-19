# Build spatial covariates for a simple cropland restoration opportunity index.

library(terra)
library(dplyr)
library(readr)
library(tibble)

# User settings
aoi_name <- "east_fife_demo"
input_year <- 2021

out_crs <- "EPSG:27700"
target_res <- 10
window_m <- 500

semi_natural_distance_cap_m <- 500
water_distance_cap_m <- 3000

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/qa", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

lc_file <- sprintf(
  "data/processed/landcover_broad_%s_%s.tif",
  input_year,
  aoi_name
)

if (!file.exists(lc_file)) {
  stop("Input file not found: ", lc_file)
}

# Project to a metre-based CRS before distance and window calculations.
lc <- rast(lc_file)
lc_bng <- project(lc, out_crs, method = "near", res = target_res)
names(lc_bng) <- paste0("landcover_broad_", input_year)

writeRaster(
  lc_bng,
  sprintf(
    "data/processed/landcover_broad_%s_%s_10m_bng.tif",
    input_year,
    aoi_name
  ),
  overwrite = TRUE,
  datatype = "INT1U",
  gdal = c("COMPRESS=LZW")
)

make_binary <- function(x, values, name) {
  y <- x %in% values
  y <- ifel(is.na(x), NA, y)
  names(y) <- name
  y
}

as_target <- function(x) {
  ifel(x == 1, 1, NA)
}

mask_to_land <- function(x, land_mask) {
  mask(x, land_mask, maskvalues = 0, updatevalue = NA)
}

score_from_distance <- function(x, cap_m) {
  y <- 1 - (x / cap_m)
  clamp(y, lower = 0, upper = 1, values = TRUE)
}

tree <- make_binary(lc_bng, 1, "tree_cover")
grass <- make_binary(lc_bng, 2, "grass_shrub")
crop <- make_binary(lc_bng, 3, "cropland")
built <- make_binary(lc_bng, 4, "built_up")
water <- make_binary(lc_bng, 6, "water_wetland")

land_mask <- ifel(!is.na(lc_bng) & lc_bng != 6, 1, 0)
names(land_mask) <- "land_mask"

candidate_cropland <- ifel(crop == 1 & land_mask == 1, 1, NA)
names(candidate_cropland) <- "candidate_cropland"

semi_natural <- ifel(tree == 1 | grass == 1, 1, 0)
semi_natural <- ifel(is.na(lc_bng), NA, semi_natural)
names(semi_natural) <- "semi_natural_context"

# Local class proportions in an approximately 500 m square window.
window_cells <- round(window_m / target_res)

if (window_cells %% 2 == 0) {
  window_cells <- window_cells + 1
}

actual_window_m <- window_cells * target_res
w <- matrix(1, window_cells, window_cells)

semi_nat_prop <- focal(
  semi_natural,
  w = w,
  fun = "mean",
  na.rm = TRUE,
  fillvalue = NA
)

built_prop <- focal(
  built,
  w = w,
  fun = "mean",
  na.rm = TRUE,
  fillvalue = NA
)

names(semi_nat_prop) <- sprintf("semi_natural_prop_%sm", window_m)
names(built_prop) <- sprintf("built_up_prop_%sm", window_m)

# Distance layers are in metres.
dist_semi_nat <- distance(as_target(semi_natural))
dist_water <- distance(as_target(water))

names(dist_semi_nat) <- "distance_to_semi_natural_m"
names(dist_water) <- "distance_to_water_wetland_m"

semi_nat_prop_land <- mask_to_land(semi_nat_prop, land_mask)
built_prop_land <- mask_to_land(built_prop, land_mask)
dist_semi_nat_land <- mask_to_land(dist_semi_nat, land_mask)
dist_water_land <- mask_to_land(dist_water, land_mask)

near_semi_nat <- score_from_distance(
  dist_semi_nat_land,
  semi_natural_distance_cap_m
)

near_water <- score_from_distance(
  dist_water_land,
  water_distance_cap_m
)

low_built_context <- 1 - built_prop_land

# Rule-based screening index; not a fitted ecological model.
index_raw <- (0.40 * semi_nat_prop_land) +
  (0.30 * near_semi_nat) +
  (0.15 * near_water) +
  (0.15 * low_built_context)

index <- clamp(index_raw, lower = 0, upper = 1, values = TRUE)
index <- mask(index, candidate_cropland)
names(index) <- "cropland_restoration_opportunity_index"

covariates <- c(
  lc_bng,
  land_mask,
  candidate_cropland,
  semi_nat_prop_land,
  built_prop_land,
  dist_semi_nat_land,
  dist_water_land,
  index
)

writeRaster(
  covariates,
  sprintf(
    "data/processed/spatial_covariates_%s_%s_10m_bng.tif",
    aoi_name,
    input_year
  ),
  overwrite = TRUE,
  gdal = c("COMPRESS=LZW")
)

summarise_layer <- function(x, nm, summary_scope) {
  vals <- values(x, mat = FALSE)
  vals <- vals[!is.na(vals)]
  
  if (length(vals) == 0) {
    return(
      tibble(
        layer = nm,
        summary_scope = summary_scope,
        n_cells = 0,
        min = NA_real_,
        q25 = NA_real_,
        median = NA_real_,
        mean = NA_real_,
        q75 = NA_real_,
        max = NA_real_,
        sd = NA_real_
      )
    )
  }
  
  tibble(
    layer = nm,
    summary_scope = summary_scope,
    n_cells = length(vals),
    min = min(vals),
    q25 = unname(quantile(vals, 0.25)),
    median = median(vals),
    mean = mean(vals),
    q75 = unname(quantile(vals, 0.75)),
    max = max(vals),
    sd = sd(vals)
  )
}

cov_summary <- bind_rows(
  summarise_layer(
    candidate_cropland,
    "candidate_cropland",
    "cropland candidate cells"
  ),
  summarise_layer(
    semi_nat_prop_land,
    names(semi_nat_prop_land),
    "land cells"
  ),
  summarise_layer(
    built_prop_land,
    names(built_prop_land),
    "land cells"
  ),
  summarise_layer(
    dist_semi_nat_land,
    "distance_to_semi_natural_m",
    "land cells"
  ),
  summarise_layer(
    dist_water_land,
    "distance_to_water_wetland_m",
    "land cells"
  ),
  summarise_layer(
    index,
    "cropland_restoration_opportunity_index",
    "cropland candidate cells"
  )
)

write_csv(
  cov_summary,
  sprintf("outputs/tables/spatial_covariate_summary_%s.csv", input_year)
)

mask_counts <- freq(land_mask) |>
  as_tibble() |>
  transmute(
    mask_value = as.integer(value),
    cell_count = as.numeric(count)
  )

mask_summary <- tibble(
  mask_value = c(1L, 0L),
  class = c("land", "water_wetland_or_outside")
) |>
  left_join(mask_counts, by = "mask_value") |>
  mutate(
    cell_count = ifelse(is.na(cell_count), 0, cell_count),
    percent = 100 * cell_count / sum(cell_count)
  )

write_csv(
  mask_summary,
  sprintf("outputs/qa/land_mask_summary_%s.csv", input_year)
)

settings <- tibble(
  setting = c(
    "input_landcover",
    "input_year",
    "output_crs",
    "target_resolution_m",
    "requested_window_m",
    "actual_window_m",
    "window_cells",
    "semi_natural_distance_cap_m",
    "water_distance_cap_m",
    "index_weight_semi_natural_proportion",
    "index_weight_near_semi_natural",
    "index_weight_near_water_wetland",
    "index_weight_low_built_context",
    "index_note"
  ),
  value = c(
    lc_file,
    as.character(input_year),
    out_crs,
    as.character(target_res),
    as.character(window_m),
    as.character(actual_window_m),
    as.character(window_cells),
    as.character(semi_natural_distance_cap_m),
    as.character(water_distance_cap_m),
    "0.40",
    "0.30",
    "0.15",
    "0.15",
    "rule-based screening index for cropland cells only; not a validated ecological model"
  )
)

write_csv(
  settings,
  sprintf("outputs/qa/spatial_covariate_settings_%s.csv", input_year)
)

plot_raster <- function(x, file, title) {
  png(file, width = 1300, height = 900, res = 130)
  plot(x, main = title, maxcell = 500000)
  dev.off()
}

plot_raster(
  candidate_cropland,
  sprintf("outputs/figures/candidate_cropland_%s.png", input_year),
  "Candidate cropland cells"
)

plot_raster(
  semi_nat_prop_land,
  sprintf("outputs/figures/semi_natural_prop_%sm_%s.png", window_m, input_year),
  sprintf("Semi-natural proportion, approx. %s m window", window_m)
)

plot_raster(
  built_prop_land,
  sprintf("outputs/figures/built_up_prop_%sm_%s.png", window_m, input_year),
  sprintf("Built-up proportion, approx. %s m window", window_m)
)

plot_raster(
  dist_water_land,
  sprintf("outputs/figures/distance_to_water_wetland_m_%s.png", input_year),
  "Distance to water/wetland, metres"
)

plot_raster(
  index,
  sprintf("outputs/figures/cropland_restoration_opportunity_index_%s.png", input_year),
  "Cropland restoration opportunity index"
)

print(cov_summary)
