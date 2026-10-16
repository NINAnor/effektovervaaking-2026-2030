#Effektovervaaking - elvesandjeger
#(1) Build a master observation file 2015-2026 with correct larval stages, and
#(2) rebuild the August density rasters 2020-2024 on the common 2 m grid used
#    for 2025-2026.
#
#Why:
# - The 2024 prepare script (Scripts/1_elvesandjeger_prepare_data.R) renamed the
#   Excel columns 3st -> stad1 and 1st -> stad3, so elvesandjeger_2024.shp and
#   the ArcGIS rasters dens_stad1_2024 / dens_stad3_2024 had stages 1 and 3
#   swapped. The long-term csv (elvesandjeger_obs_2015-2025.csv, rebuilt Nov
#   2025) has the correct stages and is used as the source here.
# - The ArcGIS rasters 2020-2023 were made on a smaller grid (no Gravråk, Fornes
#   cut at the eastern edge) offset 1 m from the 2024-2026 grid.
# - The 2023 ArcGIS rasters also included the repeat visit on 30-31 August
#   (labelled "september" in the data), double-counting the mid-August visit.
#   Here one visit per month is used: the rows labelled "august".
#
#Method for the rasters (same as 5_elvesandjeger_heatmaps_2026.R / ArcGIS Point
#Density): counts summed within a 20 m circle around each 2 m cell, divided by
#the circle area -> individuals per m2.
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(sf)
library(dplyr)
library(tidyr)
library(stringr)
library(terra)

#===============================================================================
# 1. Master observation file 2015-2026
#===============================================================================

# ---- 2015-2025 (long format, one row per point and stage) ----
hist <- read.csv2("./Elvesandjeger/elvesandjeger_obs_2015-2025.csv", stringsAsFactors = FALSE) %>%
  mutate(
    month = tolower(month),                          # "August" (2025) -> "august"
    stage = recode(tolower(stage), voksne = "voksne"),# "Voksne" (2024) -> "voksne"
    N = as.numeric(N), E = as.numeric(E),
    # dates: dd.mm.yyyy up to 2024, ISO date-time in 2025
    date = coalesce(as.Date(date, format = "%d.%m.%Y"), as.Date(substr(date, 1, 10), format = "%Y-%m-%d")),
    site = case_when(str_detect(locality, "^Storr") ~ "Storr",
                     str_detect(locality, "^Kreg")  ~ "Kreg",
                     str_detect(locality, "^Forn")  ~ "Forn",
                     str_detect(locality, "^Grav")  ~ "Grav",
                     TRUE ~ site),
    source = "gps_point", area_m2 = NA_real_
  )
stopifnot(!any(is.na(hist$date)), !any(is.na(hist$N)))
table(hist$year, hist$month)
table(hist$stage)

# ---- 2026 (polygons -> centroid coordinates; larva = sum of stages) ----
poly26 <- st_read("./Elvesandjeger/2026/Elvesandjeger.shp", quiet = TRUE) %>%
  st_transform(25832) %>%
  rename(stad1 = larve_stad, stad2 = larve_st_1, stad3 = larve_st_2, voksne = voksne)
cen <- st_coordinates(st_centroid(poly26))
obs26 <- poly26 %>% st_drop_geometry() %>%
  mutate(N = cen[, "Y"], E = cen[, "X"], area_m2 = as.numeric(st_area(poly26)),
         locality = recode(tolower(lokalitet_), forn = "Fornes", grav = "Gravrak", kreg = "Kregnesteigen", stor = "Storronningen"),
         site = recode(tolower(lokalitet_), forn = "Forn", grav = "Grav", kreg = "Kreg", stor = "Storr"),
         spat_ref = "utm32", date = as.Date(dato), month = maaned, year = 2026L,
         larva = stad1 + stad2 + stad3, source = "polygon_centroid") %>%
  pivot_longer(c(stad1, stad2, stad3, larva, voksne), names_to = "stage", values_to = "obs") %>%
  dplyr::select(locality, spat_ref, N, E, date, month, year, site, stage, obs, source, area_m2)

master <- bind_rows(hist, obs26) %>%
  mutate(date_month = as.integer(format(date, "%m"))) %>%   # calendar month of the date (the month
  arrange(year, month, date, locality, stage)               # label is the survey round)

# Check: stage totals per year and survey round (August). A few counts are NA
# in the source (2020: 1, 2021: 2) and are treated as 0 in sums.
master %>% filter(month == "august") %>%
  group_by(year, stage) %>% summarise(obs = sum(obs, na.rm = TRUE), .groups = "drop") %>%
  pivot_wider(names_from = stage, values_from = obs) %>% print(n = Inf)

write.csv2(master, "./Elvesandjeger/elvesandjeger_obs_2015-2026_master.csv", row.names = FALSE)

# Wide version as a point shapefile (one row per observation point / polygon
# centroid). In 2015-2019 (and twice in 2025) two waypoints share exactly the
# same coordinates and date; their counts are summed into one point.
master_wide <- master %>%
  pivot_wider(names_from = stage, values_from = obs, values_fn = ~ sum(.x, na.rm = TRUE)) %>%
  st_as_sf(coords = c("E", "N"), crs = 25832, remove = FALSE)
st_write(master_wide, "./Elvesandjeger/elvesandjeger_obs_2015-2026_master.shp",
         append = FALSE, layer_options = "ENCODING=UTF-8")

#===============================================================================
# 2. Rebuild the August density rasters 2020-2024 on the common grid
#===============================================================================
cell_size <- 2; radius <- 20
H <- "./Elvesandjeger/Heatmaps"

# Common grid = the 2025/2026 rasters
template <- rast(file.path(H, "dens_stad3_2025.tif"))
template <- rast(ext(template), resolution = cell_size, crs = "EPSG:25832")

density_raster <- function(cnt, r) {
  w <- focalMat(cnt, r, type = "circle"); w[w > 0] <- 1
  focal(cnt, w = w, fun = "sum", na.rm = TRUE, expand = FALSE) / (pi * r^2)
}

# Keep a copy of the ArcGIS rasters that are replaced
bak <- file.path(H, "replaced_arcgis_2020-2024")
dir.create(bak, showWarnings = FALSE)

stages <- c(stad1 = "stad1", stad2 = "stad2", stad3 = "stad3", adults = "voksne") #file name = column
for (yr in 2020:2024) {
  pts <- master_wide %>% filter(year == yr, month == "august")
  stopifnot(all(st_within(pts, st_as_sfc(st_bbox(template)) %>% st_set_crs(25832), sparse = FALSE)))
  for (s in names(stages)) {
    fld <- stages[[s]]
    f_out <- file.path(H, sprintf("dens_%s_%d.tif", s, yr))
    # back up the old file(s) before overwriting
    old <- list.files(H, pattern = sprintf("^dens_%s_%d\\.(tif|tfw|tif\\.aux\\.xml|tif\\.xml)$", s, yr), full.names = TRUE)
    file.copy(old, bak, overwrite = FALSE)
    p <- pts[!is.na(pts[[fld]]) & pts[[fld]] > 0, ]
    cnt <- if (nrow(p)) rasterize(vect(p), template, field = fld, fun = "sum", background = 0) else { z <- template; values(z) <- 0; z }
    d <- density_raster(cnt, radius); names(d) <- sprintf("dens_%s_%d", s, yr)
    writeRaster(d, f_out, overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=LZW")
    cat(sprintf("%d %-6s points=%3d  count=%6.0f  raster integral=%7.1f  max=%.4f\n", yr, s, nrow(p),
                sum(p[[fld]]), global(d, "sum")[[1]] * cell_size^2, global(d, "max")[[1]]))
  }
}

# All rasters 2020-2026 on the same grid?
ref <- rast(file.path(H, "dens_stad3_2026.tif"))
for (f in list.files(H, pattern = "^dens_.*_20(2[0-6])\\.tif$", full.names = TRUE))
  if (!compareGeom(rast(f), ref, stopOnError = FALSE)) cat("GRID MISMATCH:", f, "\n")
cat("grid check done\n")
