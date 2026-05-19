# Make a simple cropland-to-semi-natural restoration scenario.

library(terra)
library(dplyr)
library(readr)
library(tibble)

# User settings
aoi_name <- "east_fife_demo"
input_year <- 2021

target_res <- 10
window_m <- 500
scenario_fraction <- 0.10

from_class <- 3L
to_class <- 2L
scenario_name <- "cropland_to_semi_natural_top10"

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/qa", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/tables", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

lc_file <- sprintf(
  "data/processed/landcover_broad_%s_%s_10m_bng.tif",
  input_year,
  aoi_name
)

cov_file <- sprintf(
  "data/processed/spatial_covariates_%s_%s_10m_bng.tif",
  aoi_name,
  input_year
)

if (!file.exists(lc_file)) {
  stop("Input land-cover file not found: ", lc_file)
}

if (!file.exists(cov_file)) {
  stop("Input covariate file not found: ", cov_file)
}

lc <- rast(lc_file)
covariates <- rast(cov_file)

baseline_index <- covariates[["cropland_restoration_opportunity_index"]]
candidate_cropland <- covariates[["candidate_cropland"]]
land_mask <- covariates[["land_mask"]]

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

build_context <- function(lc, land_mask, window_m, target_res) {
  tree <- make_binary(lc, 1, "tree_cover")
  grass <- make_binary(lc, 2, "grass_shrub")
  built <- make_binary(lc, 4, "built_up")
  water <- make_binary(lc, 6, "water_wetland")
  
  semi_natural <- ifel(tree == 1 | grass == 1, 1, 0)
  semi_natural <- ifel(is.na(lc), NA, semi_natural)
  
  window_cells <- round(window_m / target_res)
  
  if (window_cells %% 2 == 0) {
    window_cells <- window_cells + 1
  }
  
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
  
  dist_semi_nat <- distance(as_target(semi_natural))
  dist_water <- distance(as_target(water))
  
  semi_nat_prop <- mask_to_land(semi_nat_prop, land_mask)
  built_prop <- mask_to_land(built_prop, land_mask)
  dist_semi_nat <- mask_to_land(dist_semi_nat, land_mask)
  dist_water <- mask_to_land(dist_water, land_mask)
  
  near_semi_nat <- score_from_distance(dist_semi_nat, 500)
  near_water <- score_from_distance(dist_water, 3000)
  low_built_context <- 1 - built_prop
  
  context_index <- (0.40 * semi_nat_prop) +
    (0.30 * near_semi_nat) +
    (0.15 * near_water) +
    (0.15 * low_built_context)
  
  context_index <- clamp(context_index, lower = 0, upper = 1, values = TRUE)
  
  names(semi_nat_prop) <- sprintf("semi_natural_prop_%sm", window_m)
  names(built_prop) <- sprintf("built_up_prop_%sm", window_m)
  names(dist_semi_nat) <- "distance_to_semi_natural_m"
  names(dist_water) <- "distance_to_water_wetland_m"
  names(context_index) <- "landscape_context_index_land"
  
  c(
    semi_nat_prop,
    built_prop,
    dist_semi_nat,
    dist_water,
    context_index
  )
}

raster_stats <- function(x, layer_name, summary_scope) {
  vals <- values(x, mat = FALSE)
  vals <- vals[!is.na(vals)]
  
  if (length(vals) == 0) {
    return(
      tibble(
        layer = layer_name,
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
    layer = layer_name,
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

sum_raster <- function(x) {
  as.numeric(global(x, "sum", na.rm = TRUE)[1, 1])
}

scores <- values(baseline_index, mat = FALSE)
scores <- scores[is.finite(scores)]

if (length(scores) == 0) {
  stop("No valid cropland opportunity scores found.")
}

threshold <- as.numeric(
  quantile(scores, 1 - scenario_fraction, na.rm = TRUE)
)

selected <- ifel(
  !is.na(baseline_index) & baseline_index >= threshold,
  1,
  0
)

selected_plot <- ifel(selected == 1, 1, NA)
names(selected) <- "scenario_selected_cells"
names(selected_plot) <- "scenario_selected_cells"

scenario_lc <- ifel(selected == 1, to_class, lc)
names(scenario_lc) <- "scenario_broad_class"

baseline_context <- build_context(lc, land_mask, window_m, target_res)
scenario_context <- build_context(scenario_lc, land_mask, window_m, target_res)

semi_nat_change <- scenario_context[[sprintf("semi_natural_prop_%sm", window_m)]] -
  baseline_context[[sprintf("semi_natural_prop_%sm", window_m)]]

context_change <- scenario_context[["landscape_context_index_land"]] -
  baseline_context[["landscape_context_index_land"]]

names(semi_nat_change) <- sprintf("semi_natural_prop_%sm_difference", window_m)
names(context_change) <- "landscape_context_index_difference"

comparison <- c(
  baseline_context[["landscape_context_index_land"]],
  scenario_context[["landscape_context_index_land"]],
  context_change,
  semi_nat_change,
  selected
)

names(comparison) <- c(
  "baseline_landscape_context_index",
  "scenario_landscape_context_index",
  "landscape_context_index_difference",
  sprintf("semi_natural_prop_%sm_difference", window_m),
  "scenario_selected_cells"
)

scenario_lc_file <- sprintf(
  "data/processed/landcover_broad_%s_%s_%s_10m_bng.tif",
  input_year,
  aoi_name,
  scenario_name
)

comparison_file <- sprintf(
  "data/processed/restoration_scenario_comparison_%s_%s_10m_bng.tif",
  aoi_name,
  input_year
)

writeRaster(
  scenario_lc,
  scenario_lc_file,
  overwrite = TRUE,
  datatype = "INT1U",
  gdal = c("COMPRESS=LZW")
)

writeRaster(
  comparison,
  comparison_file,
  overwrite = TRUE,
  datatype = "FLT4S",
  gdal = c("COMPRESS=LZW")
)

cell_area_ha <- prod(res(lc)) / 10000

land_cells <- sum_raster(ifel(land_mask == 1, 1, 0))
crop_cells <- sum_raster(ifel(candidate_cropland == 1, 1, 0))
selected_cells <- sum_raster(selected)

scenario_area <- tibble(
  scenario = scenario_name,
  from_class = "cropland",
  to_class = "grass_shrub",
  selected_cells = selected_cells,
  selected_area_ha = selected_cells * cell_area_ha,
  selected_area_km2 = selected_cells * cell_area_ha / 100,
  percent_of_land = 100 * selected_cells / land_cells,
  percent_of_cropland = 100 * selected_cells / crop_cells,
  selection_threshold = threshold
)

scenario_summary <- bind_rows(
  raster_stats(
    comparison[["baseline_landscape_context_index"]],
    "baseline_landscape_context_index",
    "land cells"
  ),
  raster_stats(
    comparison[["scenario_landscape_context_index"]],
    "scenario_landscape_context_index",
    "land cells"
  ),
  raster_stats(
    comparison[["landscape_context_index_difference"]],
    "landscape_context_index_difference",
    "land cells"
  ),
  raster_stats(
    comparison[[sprintf("semi_natural_prop_%sm_difference", window_m)]],
    sprintf("semi_natural_prop_%sm_difference", window_m),
    "land cells"
  )
)

settings <- tibble(
  setting = c(
    "scenario_name",
    "input_year",
    "from_class",
    "to_class",
    "target_resolution_m",
    "window_m",
    "scenario_fraction",
    "selection_rule",
    "comparison_note"
  ),
  value = c(
    scenario_name,
    as.character(input_year),
    "cropland",
    "grass_shrub",
    as.character(target_res),
    as.character(window_m),
    as.character(scenario_fraction),
    "top-ranked cropland candidate cells by baseline restoration opportunity index",
    "scenario is a rule-based demonstration, not a restoration recommendation"
  )
)

write_csv(
  scenario_area,
  sprintf("outputs/tables/restoration_scenario_area_%s.csv", input_year)
)

write_csv(
  scenario_summary,
  sprintf("outputs/tables/restoration_scenario_summary_%s.csv", input_year)
)

write_csv(
  settings,
  sprintf("outputs/qa/restoration_scenario_settings_%s.csv", input_year)
)

plot_raster <- function(x, file, title) {
  png(file, width = 1300, height = 900, res = 130)
  plot(x, main = title, maxcell = 500000)
  dev.off()
}

plot_raster(
  selected_plot,
  sprintf("outputs/figures/restoration_selected_cells_%s.png", input_year),
  "Selected cropland cells for demonstration scenario"
)

plot_raster(
  scenario_lc,
  sprintf("outputs/figures/restoration_scenario_landcover_%s.png", input_year),
  "Scenario broad land-cover classes"
)

plot_raster(
  comparison[["scenario_landscape_context_index"]],
  sprintf("outputs/figures/restoration_scenario_context_index_%s.png", input_year),
  "Scenario landscape context index"
)

plot_raster(
  comparison[["landscape_context_index_difference"]],
  sprintf("outputs/figures/restoration_context_index_difference_%s.png", input_year),
  "Scenario minus baseline context index"
)

plot_raster(
  comparison[[sprintf("semi_natural_prop_%sm_difference", window_m)]],
  sprintf("outputs/figures/restoration_semi_natural_prop_difference_%s.png", input_year),
  sprintf("Change in semi-natural proportion, %s m window", window_m)
)

print(scenario_area)
print(scenario_summary)
