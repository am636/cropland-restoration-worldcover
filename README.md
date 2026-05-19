# Cropland restoration opportunity mapping with ESA WorldCover

A compact R workflow using ESA WorldCover land-cover data to build a simple cropland restoration screening workflow for East Fife, Scotland.

The project demonstrates raster data handling, land-cover reclassification, spatial covariate engineering and rule-based scenario comparison in R. It is a reproducible portfolio workflow, not a field-validated restoration model or site-level land-management recommendation.

## Workflow

The scripts should be run from the repository root in order:

```r
source("R/01_get_worldcover.R")
source("R/02_reclassify_landcover.R")
source("R/03_landcover_difference_summary.R")
source("R/04_build_spatial_covariates.R")
source("R/05_make_restoration_scenario.R")
```

The workflow:

1. downloads and crops ESA WorldCover 2020 and 2021 data for a small East Fife study area;
2. reclassifies the original WorldCover classes into broader land-cover groups;
3. summarises broad land-cover differences between 2020 and 2021;
4. builds spatial covariates from the 2021 broad land-cover map;
5. ranks cropland cells using a transparent restoration opportunity index;
6. converts the top-ranked cropland cells to a grass/shrub proxy in a demonstration scenario;
7. compares baseline and scenario landscape context.

## Method summary

WorldCover classes are grouped into six broad classes: `tree_cover`, `grass_shrub`, `cropland`, `built_up`, `bare_sparse` and `water_wetland`.

The restoration opportunity index is calculated for cropland cells only. It combines local semi-natural cover, closeness to existing semi-natural cover, closeness to water or wetland, and low local built-up cover. The weights are transparent assumptions for demonstration, not fitted model coefficients.

The scenario selects the top 10% of cropland cells according to this index and changes them to `grass_shrub`, used here as a simple open semi-natural land-cover proxy.

## Main outputs

Generated rasters are written to `data/processed/`. Summary tables and figures are written to `outputs/`.

Key outputs include:

```text
outputs/tables/landcover_broad_area_summary.csv
outputs/tables/landcover_broad_difference_summary_2020_2021.csv
outputs/tables/spatial_covariate_summary_2021.csv
outputs/tables/restoration_scenario_area_2021.csv
outputs/tables/restoration_scenario_summary_2021.csv
outputs/figures/cropland_restoration_opportunity_index_2021.png
outputs/figures/restoration_context_index_difference_2021.png
```

The `data/` and `outputs/` folders are generated locally and ignored by Git.

## Requirements

```r
install.packages(c("terra", "sf", "dplyr", "readr", "tibble"))
```

## Notes

The workflow uses ESA WorldCover 10 m products for 2020 and 2021. These products use different versions, so the 2020-2021 comparison is included as a descriptive workflow step rather than a validated land-cover change analysis.

The restoration scenario is a rule-based screening example. It does not include field validation, land ownership, agricultural feasibility, soil, slope, habitat condition or species data.

## Data citation

Zanaga, D. et al. (2021). ESA WorldCover 10 m 2020 v100. doi:10.5281/zenodo.5571936.

Zanaga, D. et al. (2022). ESA WorldCover 10 m 2021 v200. doi:10.5281/zenodo.7254221.
