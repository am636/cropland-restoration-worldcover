# Download and crop ESA WorldCover data for a small East Fife AOI.
# The AOI can be changed by editing the bounding box below.

library(terra)
library(sf)
library(dplyr)
library(readr)
library(tibble)


# User settings
aoi_name <- "east_fife_demo"

aoi_bbox <- c(
  xmin = -2.98,
  ymin = 56.22,
  xmax = -2.72,
  ymax = 56.36
)

# ESA WorldCover currently provides global 10 m maps for 2020 and 2021.
years <- c(2020, 2021)

# The two WorldCover years use different product versions.
worldcover_versions <- c(
  "2020" = "v100",
  "2021" = "v200"
)


worldcover_base_url <- "https://esa-worldcover.s3.eu-central-1.amazonaws.com"

dir.create("data/processed", recursive = TRUE, showWarnings = FALSE)
dir.create("outputs/qa", recursive = TRUE, showWarnings = FALSE)

# Small helper functions
make_aoi <- function(bbox, name) {
  st_as_sfc(st_bbox(bbox, crs = st_crs("EPSG:4326"))) |>
    st_as_sf() |>
    mutate(aoi = name)
}

tile_starts <- function(xmin, xmax, step = 3) {
  first <- floor(xmin / step) * step
  last <- floor((xmax - 1e-10) / step) * step
  seq(first, last, by = step)
}

format_worldcover_tile <- function(lat0, lon0) {
  lat_part <- paste0(ifelse(lat0 >= 0, "N", "S"), sprintf("%02d", abs(lat0)))
  lon_part <- paste0(ifelse(lon0 >= 0, "E", "W"), sprintf("%03d", abs(lon0)))
  paste0(lat_part, lon_part)
}

tiles_from_bbox <- function(bbox) {
  lons <- tile_starts(unname(bbox["xmin"]), unname(bbox["xmax"]))
  lats <- tile_starts(unname(bbox["ymin"]), unname(bbox["ymax"]))
  
  x <- expand.grid(lat0 = lats, lon0 = lons)
  x$tile <- mapply(format_worldcover_tile, x$lat0, x$lon0)
  
  x$tile
}

tile_url <- function(year, version, tile) {
  sprintf(
    "%s/%s/%s/map/ESA_WorldCover_10m_%s_%s_%s_Map.tif",
    worldcover_base_url,
    version,
    year,
    year,
    version,
    tile
  )
}

read_crop_tile <- function(url, aoi_vect) {
  r <- rast(url)
  r <- crop(r, aoi_vect, snap = "out")
  mask(r, aoi_vect)
}

save_class_counts <- function(r, year) {
  counts <- freq(r) |>
    as_tibble() |>
    rename(class_value = value, cell_count = count) |>
    arrange(class_value)
  
  out_file <- sprintf("outputs/qa/worldcover_class_counts_%s.csv", year)
  write_csv(counts, out_file)
  
  invisible(counts)
}

# AOI and tile selection
aoi <- make_aoi(aoi_bbox, aoi_name)

st_write(
  aoi,
  "data/processed/aoi.gpkg",
  delete_dsn = TRUE,
  quiet = TRUE
)

tiles <- tiles_from_bbox(aoi_bbox)
aoi_vect <- vect(aoi)

download_log <- tibble(
  year = integer(),
  version = character(),
  tile = character(),
  url = character()
)

# Read, crop and save the WorldCover rasters
for (year in years) {
  version <- unname(worldcover_versions[as.character(year)])
  parts <- list()
  
  for (i in seq_along(tiles)) {
    tile <- tiles[i]
    url <- tile_url(year, version, tile)
    
    message("Reading ", year, " tile ", tile)
    
    parts[[i]] <- read_crop_tile(url, aoi_vect)
    
    download_log <- bind_rows(
      download_log,
      tibble(
        year = year,
        version = version,
        tile = tile,
        url = url
      )
    )
  }
  
  landcover <- if (length(parts) == 1) {
    parts[[1]]
  } else {
    do.call(mosaic, parts)
  }
  
  names(landcover) <- paste0("worldcover_", year)
  
  out_file <- sprintf(
    "data/processed/worldcover_%s_%s.tif",
    year,
    aoi_name
  )
  
  writeRaster(
    landcover,
    out_file,
    overwrite = TRUE,
    datatype = "INT1U",
    gdal = c("COMPRESS=LZW")
  )
  
  save_class_counts(landcover, year)
}

write_csv(
  download_log,
  "outputs/qa/worldcover_download_log.csv"
)
