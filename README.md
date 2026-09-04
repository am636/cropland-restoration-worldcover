# Cropland restoration screening in East Fife with ESA WorldCover

This repository contains a compact R case study using ESA WorldCover data to explore where cropland in East Fife, Scotland, is located in relation to semi-natural cover, water and built-up land.

The analysis is intentionally simple. It combines land-cover reclassification, local spatial context and distance-based covariates to build an illustrative cropland-restoration screening index, then compares the baseline landscape with a scenario in which the highest-ranked cropland cells are reassigned to a grass/shrub class.

## Workflow

Run the scripts from the repository root in order:

```r
source("R/01_get_worldcover.R")
source("R/02_reclassify_landcover.R")
source("R/03_landcover_difference_summary.R")
source("R/04_build_spatial_covariates.R")
source("R/05_make_restoration_scenario.R")
```

The scripts:

1. download and crop ESA WorldCover 2020 and 2021 data for East Fife;
2. reclassify the original WorldCover legend into broader land-cover groups;
3. summarise differences between the two annual products;
4. derive local semi-natural cover, built-up context and distance covariates;
5. calculate a transparent restoration-screening score for cropland cells;
6. select the top-ranked 10% of candidate cropland cells for an illustrative scenario;
7. compare baseline and scenario landscape context.

## Land-cover groups

The original WorldCover classes are grouped into six broader classes:

- tree cover
- grass/shrub
- cropland
- built-up
- bare/sparse
- water/wetland

## Screening index

The cropland screening score combines:

- local semi-natural cover;
- distance to existing semi-natural cover;
- distance to water or wetland;
- low local built-up cover.

The weights are explicit assumptions rather than fitted coefficients. They can be changed in `R/04_build_spatial_covariates.R`.

## Interpretation

The 2020 and 2021 WorldCover products use different product versions, so the comparison should be treated as descriptive rather than as a validated land-cover-change analysis.

The scenario is also illustrative. It does not include land ownership, agricultural feasibility, soils, slope, habitat condition, species requirements or field validation, so it should not be interpreted as a site-level restoration recommendation.

## Data

ESA WorldCover 10 m 2020 v100: Zanaga, D. et al. (2021), DOI 10.5281/zenodo.5571936.

ESA WorldCover 10 m 2021 v200: Zanaga, D. et al. (2022), DOI 10.5281/zenodo.7254221.

Generated rasters, tables and figures are written to local `data/` and `outputs/` folders and are not versioned.

**Author:** Ali Moayedi  
University of St Andrews
