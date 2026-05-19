# Cropland restoration opportunity mapping with ESA WorldCover

This repository contains a compact R workflow for turning ESA WorldCover land-cover data into a simple cropland restoration opportunity screening example.

The workflow is intentionally modest. It is not a field-validated restoration model and it is not intended to make site-level land-management recommendations. The example is designed as a portfolio workflow showing raster data handling, land-cover reclassification, spatial covariate engineering and transparent scenario analysis in R.

## What the workflow does

The default example uses a small East Fife study area. The area can be changed by editing the bounding box in `R/01_get_worldcover.R`.

The workflow:

1. downloads and crops ESA WorldCover 2020 and 2021 data;
2. reclassifies the original WorldCover classes into broader land-cover classes;
3. compares broad classes between 2020 and 2021 as a cautious descriptive check;
4. builds spatial covariates from the 2021 broad land-cover map;
5. ranks cropland cells using a simple restoration opportunity index;
6. converts the top-ranked cropland cells to a grass/shrub proxy in a demonstration scenario;
7. compares baseline and scenario landscape context.

## Data source

The workflow uses ESA WorldCover 10 m land-cover products:

- ESA WorldCover 10 m 2020 v100
- ESA WorldCover 10 m 2021 v200

The scripts read the tiled Cloud Optimized GeoTIFFs directly from the public ESA WorldCover AWS bucket.

The 2020 and 2021 products use different product versions. The 2020-2021 difference step should therefore be interpreted cautiously. In this repository it is used as a workflow demonstration, not as a validated land-cover change product.

## Repository structure

```text
R/
  01_get_worldcover.R
  02_reclassify_landcover.R
  03_landcover_difference_summary.R
  04_build_spatial_covariates.R
  05_make_restoration_scenario.R

data/
  processed/        # generated locally

outputs/
  figures/          # generated locally
  tables/           # generated locally
  qa/               # generated locally
```

The `data/` and `outputs/` folders are created automatically when the scripts are run. They are ignored by Git because they contain generated data and outputs.

## R packages

The workflow uses:

```r
terra
sf
dplyr
readr
tibble
```

Install missing packages with:

```r
install.packages(c("terra", "sf", "dplyr", "readr", "tibble"))
```

## How to run

Run the scripts from the repository root, in order:

```r
source("R/01_get_worldcover.R")
source("R/02_reclassify_landcover.R")
source("R/03_landcover_difference_summary.R")
source("R/04_build_spatial_covariates.R")
source("R/05_make_restoration_scenario.R")
```

The first script downloads the input land-cover tiles, so it requires an internet connection. The remaining scripts use the generated files in `data/processed/`.

## Main outputs

Important table outputs include:

```text
outputs/tables/landcover_broad_area_summary.csv
outputs/tables/landcover_broad_difference_summary_2020_2021.csv
outputs/tables/spatial_covariate_summary_2021.csv
outputs/tables/restoration_scenario_area_2021.csv
outputs/tables/restoration_scenario_summary_2021.csv
```

Important figure outputs include:

```text
outputs/figures/landcover_broad_2021_map.png
outputs/figures/landcover_broad_difference_2020_2021_map.png
outputs/figures/cropland_restoration_opportunity_index_2021.png
outputs/figures/restoration_selected_cells_2021.png
outputs/figures/restoration_context_index_difference_2021.png
```

Raster outputs are written to `data/processed/`.

## Broad land-cover classes

The original ESA WorldCover classes are grouped into a smaller set of broad classes:

| Broad class | Includes |
|---|---|
| `tree_cover` | Tree cover |
| `grass_shrub` | Shrubland, grassland, moss and lichen |
| `cropland` | Cropland |
| `built_up` | Built-up |
| `bare_sparse` | Bare or sparse vegetation, snow and ice |
| `water_wetland` | Permanent water bodies, herbaceous wetland, mangroves |

This simplification keeps the workflow readable. It can be changed in `R/02_reclassify_landcover.R`.

## Spatial covariates

The covariate step uses the 2021 broad land-cover raster. It projects the raster to British National Grid before calculating metre-based distances and moving-window statistics.

The main covariates are:

- candidate cropland cells;
- local semi-natural proportion in an approximately 500 m square moving window;
- local built-up proportion in the same window;
- distance to existing semi-natural cover;
- distance to water or wetland.

Here, semi-natural cover is represented by the simplified `tree_cover` and `grass_shrub` broad classes.

## Restoration opportunity index

The restoration opportunity index is a rule-based screening score calculated for cropland cells only. It combines:

- local semi-natural cover;
- closeness to existing semi-natural cover;
- closeness to water or wetland;
- low local built-up cover.

The current weights are:

```text
0.40 semi-natural proportion
0.30 closeness to semi-natural cover
0.15 closeness to water/wetland
0.15 low built-up context
```

Distance scores are capped before being converted to 0-1 scores. The current caps are 500 m for distance to semi-natural cover and 3000 m for distance to water/wetland.

The index is a screening score for comparing candidate cropland cells within the example area. It is not a fitted model and should not be interpreted as a validated ecological response.

## Scenario

The scenario selects the top 10% of cropland cells according to the restoration opportunity index and changes them from `cropland` to `grass_shrub`, used here as a simple open semi-natural land-cover proxy.

This creates a simple before/after comparison:

```text
baseline broad land cover
→ selected cropland cells changed to grass/shrub
→ recomputed landscape context
→ scenario minus baseline difference
```

The scenario demonstrates raster-based screening and scenario comparison. It should not be interpreted as a restoration recommendation without additional ecological, land-ownership, agricultural, policy and field evidence.

## Things to change for another area

For a different study area, edit these settings in `R/01_get_worldcover.R`:

```r
aoi_name <- "east_fife_demo"

aoi_bbox <- c(
  xmin = -2.98,
  ymin = 56.22,
  xmax = -2.72,
  ymax = 56.36
)
```

For a different scenario strength, edit this setting in `R/05_make_restoration_scenario.R`:

```r
scenario_fraction <- 0.10
```

For a different spatial context scale, edit this setting in both `R/04_build_spatial_covariates.R` and `R/05_make_restoration_scenario.R`:

```r
window_m <- 500
```

## Limitations

This is a compact demonstration workflow. The main limitations are:

- no field validation;
- no land-ownership or management-feasibility information;
- no soil, slope, protected-area, habitat-condition or species data;
- a simple rule-based index rather than a fitted model;
- cautious interpretation needed for 2020-2021 WorldCover differences because the two products use different versions.

## Data citation

WorldCover 2020:

Zanaga, D. et al. (2021). ESA WorldCover 10 m 2020 v100. doi:10.5281/zenodo.5571936.

WorldCover 2021:

Zanaga, D. et al. (2022). ESA WorldCover 10 m 2021 v200. doi:10.5281/zenodo.7254221.
