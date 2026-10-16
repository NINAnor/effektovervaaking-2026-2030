#Effektovervaaking - stor elvebreddedderkopp (Arctosa cinerea)
#(1) Master observation file 2020-2026 and (2) September density rasters
#    (juveniles, adults) 2020-2026 on the common 2 m grid used for elvesandjeger.
#
#Data:
# - Data/Elevebreddedderkopp/elvesbreddedderkopp_obs_2020-2024.csv: GPS points
#   2020-2024 (long format: one row per point and stage; mainly September)
# - Data/Elevebreddedderkopp/2026/EFFEKT_-_Elvebreddedderkopp_2024-2026.gpkg:
#   survey polygons (layer is named "Elvesandjeger" in the file) in EPSG:3857.
#   Sept 2024 (31 polygons, Gravråk only) was a pilot that duplicates the point
#   records of the same day (same locations, same counts) and is excluded here;
#   Sept 2025 (140) and Sept 2026 (57) are the polygon years.
#
#Rasters: same method as for elvesandjeger (ArcGIS Point Density settings):
#2 m cells, circular neighbourhood radius 20 m, individuals per m2. For the
#polygon years the count of each polygon is spread over the cells it covers.
#The old ArcGIS rasters (2020-2024, two different grids) are kept in
#Heatmaps/replaced_arcgis_2020-2024/.
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
sf_use_s2(FALSE)

D <- "./Elevebreddedderkopp"
H <- file.path(D, "Heatmaps")

#===============================================================================
# 1. Master observation file
#===============================================================================
# ---- 2020-2024 points ----
hist <- read.csv(file.path(D, "elvesbreddedderkopp_obs_2020-2024.csv"), stringsAsFactors = FALSE) %>%
  mutate(date = as.Date(date, "%Y-%m-%d"),
         N = as.numeric(utm_N), E = as.numeric(utm_E),
         site = recode(site, Forn = "Fornes", Grav = "Gravråk", Kreg = "Kregnesteigen", Stor = "Storrønningen"),
         stage = recode(stage, adult = "adult", juvenile = "juvenile"),
         source = "gps_point", area_m2 = NA_real_) %>%
  dplyr::select(locality, site, N, E, date, month, year, stage, obs, source, area_m2)
# 410 rows from 2023 have no date: use the median date of the other rows from the same year and month
month_no <- c(juni = 6, juli = 7, august = 8, september = 9)
hist <- hist %>% group_by(year, month) %>%
  mutate(date_missing = is.na(date),
         date = if_else(is.na(date), if (any(!is.na(date))) median(date, na.rm = TRUE) else as.Date(sprintf("%d-%02d-15", year, month_no[month])), date)) %>%
  ungroup()
table(hist$year[hist$date_missing], hist$month[hist$date_missing])
stopifnot(!any(is.na(hist$date)), !any(is.na(hist$N)))
table(hist$year, hist$month) / 2   # points per visit

# ---- 2025-2026 polygons ----
poly <- st_read(file.path(D, "2026/EFFEKT_-_Elvebreddedderkopp_2024-2026.gpkg"), quiet = TRUE) %>%
  st_transform(25832) %>%
  mutate(date = as.Date(dato), year = as.integer(format(date, "%Y")), month = "september",
         area_m2 = as.numeric(st_area(SHAPE)),
         site = recode(tolower(lokalitet), forn = "Fornes", grav = "Gravråk", gravråk = "Gravråk",
                       kreg = "Kregnesteigen", stor = "Storrønningen", annen = "Kregnesteigen"),  # "annen" lies on Kregnesteigen 4
         # substrate: free text -> three classes
         substrat_raw = substrat,
         substrat = case_when(str_detect(tolower(substrat), "blanding") ~ "blanding",
                              str_detect(tolower(substrat), "fin|silt") ~ "finsand_silt",
                              str_detect(tolower(substrat), "sand") ~ "sand",
                              TRUE ~ NA_character_),
         vegetasjon = as.numeric(vegetasjon))
table(poly$year); table(poly$substrat_raw, poly$substrat, useNA = "ifany")
poly26 <- poly %>% filter(year >= 2025)     # 2024 pilot polygons excluded (duplicates of the points)
st_write(poly26, file.path(D, "2026/elvebreddedderkopp_polygons_2025-2026_utm32.gpkg"), delete_dsn = TRUE, quiet = TRUE)

cen <- st_coordinates(st_centroid(poly26))
obs_poly <- poly26 %>% st_drop_geometry() %>%
  mutate(N = cen[, "Y"], E = cen[, "X"], locality = site, source = "polygon_centroid") %>%
  pivot_longer(c(juvenile, voksne), names_to = "stage", values_to = "obs") %>%
  mutate(stage = recode(stage, voksne = "adult")) %>%
  dplyr::select(locality, site, N, E, date, month, year, stage, obs, source, area_m2)

master <- bind_rows(hist, obs_poly) %>% arrange(year, date, site, stage)
master %>% filter(month == "september") %>% group_by(year, stage) %>%
  summarise(obs = sum(obs, na.rm = TRUE), n = n(), .groups = "drop") %>%
  pivot_wider(names_from = stage, values_from = c(obs, n)) %>% print()
write.csv2(master, file.path(D, "elvebreddedderkopp_obs_2020-2026_master.csv"), row.names = FALSE)
master_wide <- master %>%
  pivot_wider(names_from = stage, values_from = obs, values_fn = ~ sum(.x, na.rm = TRUE)) %>%
  st_as_sf(coords = c("E", "N"), crs = 25832, remove = FALSE)
st_write(master_wide, file.path(D, "elvebreddedderkopp_obs_2020-2026_master.shp"), append = FALSE,
         layer_options = "ENCODING=UTF-8", quiet = TRUE)

#===============================================================================
# 2. September density rasters 2020-2026 on the common grid
#===============================================================================
cell_size <- 2; radius <- 20
template <- rast("./Elvesandjeger/Heatmaps/dens_stad3_2026.tif")
template <- rast(ext(template), resolution = cell_size, crs = "EPSG:25832")

density_raster <- function(cnt, r) {
  w <- focalMat(cnt, r, type = "circle"); w[w > 0] <- 1
  focal(cnt, w = w, fun = "sum", na.rm = TRUE, expand = FALSE) / (pi * r^2)
}
# polygons: spread each polygon's count over the cells it covers
count_raster_poly <- function(polys, field) {
  cnt <- template; values(cnt) <- 0
  polys <- polys[!is.na(polys[[field]]) & polys[[field]] > 0, ]
  for (i in seq_len(nrow(polys))) {
    p <- vect(polys[i, ]); e <- ext(buffer(p, cell_size * 2))
    cov <- rasterize(p, crop(template, e, snap = "out"), cover = TRUE); cov[is.na(cov)] <- 0
    part <- cov * cell_size^2 / polys$area_m2[i] * polys[[field]][i]
    cnt <- cnt + extend(part, template, fill = 0)
  }
  cnt
}

bak <- file.path(H, "replaced_arcgis_2020-2024"); dir.create(bak, showWarnings = FALSE)
old <- list.files(H, pattern = "^density_(juveniles|adults)_sep20(2[0-4])\\.(tif|tfw|tif\\.aux\\.xml|tif\\.xml)$", full.names = TRUE)
file.copy(old, bak, overwrite = FALSE)

stages <- c(juveniles = "juvenile", adults = "adult")
for (yr in 2020:2026) {
  for (s in names(stages)) {
    fld <- stages[[s]]
    if (yr <= 2024) {
      pts <- master_wide %>% filter(year == yr, month == "september")
      p <- pts[pts[[fld]] > 0, ]
      cnt <- if (nrow(p)) rasterize(vect(p), template, field = fld, fun = "sum", background = 0) else { z <- template; values(z) <- 0; z }
    } else {
      pp <- poly26 %>% filter(year == yr) %>% rename(adult = voksne)
      cnt <- count_raster_poly(pp, fld)
    }
    d <- density_raster(cnt, radius); names(d) <- sprintf("density_%s_sep%d", s, yr)
    writeRaster(d, file.path(H, sprintf("density_%s_sep%d.tif", s, yr)), overwrite = TRUE, datatype = "FLT4S", gdal = "COMPRESS=LZW")
    cat(sprintf("%d %-9s count=%6.0f  raster integral=%7.1f  max=%.4f\n", yr, s,
                global(cnt, "sum")[[1]], global(d, "sum")[[1]] * cell_size^2, global(d, "max")[[1]]))
  }
}
ref <- rast("./Elvesandjeger/Heatmaps/dens_stad3_2026.tif")
for (f in list.files(H, pattern = "^density_.*_sep20(2[0-6])\\.tif$", full.names = TRUE))
  if (!compareGeom(rast(f), ref, stopOnError = FALSE)) cat("GRID MISMATCH:", f, "\n")
cat("grid check done\n")
