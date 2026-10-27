#Effektovervaaking - stor elvebreddedderkopp
#Map data for the site map in the report (section 3.1).
#
#Writes data/kart_elvedyr.gpkg with the layers
# - norge:            Norway, county polygons dissolved and simplified (EPSG:25833)
# - trondelag:        Trøndelag county, simplified (EPSG:25833)
# - gaula:            main course of Gaula, NVE Elvenett (vassdrag 122.Z) (EPSG:25832)
# - lukeomrade:       minimum bounding geometry (convex hull) of the lupin clearing
#                     polygons per site (Lupinluking_2025_2026_merged.shp) (EPSG:25832)
# - edderkoppomrade:  convex hull of the spider survey polygons 2025-2026 per site (EPSG:25832)
# - utsnitt:          square map frame per site around both hulls (EPSG:25832)
#
#and per site
# - data/ortofoto_<site>.jpg: Norge i bilder orthophoto covering exactly the site frame
#   (Kartverket/Geovekst, WMS https://wms.geonorge.no/skwms1/wms.nib, layer "ortofoto")
# - img/foto_<site>.jpg:      site photo, turned upright (EXIF orientation) and resized
#
#Only the four monitoring sites are kept (Follstadøya has clearing but no spider monitoring).
#Run again when the clearing polygons or the spider polygons change.
#
#Author: Megan Nowell
#Date: 2026

library(sf)
library(dplyr)
library(magick)

p_elvedyr <- "/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data"
#p_elvedyr <- "P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data" #Windows
p_geo <- "/data/R/GeoSpatialData"
#p_geo <- "R:/GeoSpatialData" #Windows
p_photos <- "/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Figures/elvebreddedderkopp/2026/Photos"
#p_photos <- "P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Figures/elvebreddedderkopp/2026/Photos" #Windows

out <- here::here("data", "kart_elvedyr.gpkg")

sites <- c(Storronningen = "Storrønningen", Kregnesteigen = "Kregnesteigen", Fornes = "Fornes", Gravrak = "Gravråk")
site_file <- setNames(names(sites), sites) # file names without æøå, e.g. ortofoto_Gravrak.jpg
spider_codes <- c(stor = "Storrønningen", kreg = "Kregnesteigen", forn = "Fornes", grav = "Gravråk")

#-------------------------------------------------------------------------------
# Norway and Trøndelag (Kartverket county polygons with coastline, simplified)
#-------------------------------------------------------------------------------
fylker <- st_read(file.path(p_geo, "AdministrativeUnits/Norway_AdministrativeUnits/Processed",
                            "Norge_kystlinje_fylker_2024_simplify.shp"), quiet = TRUE) %>%
  st_make_valid()
norge <- fylker %>%
  summarise() %>%
  st_simplify(dTolerance = 1000, preserveTopology = TRUE)
trondelag <- fylker %>%
  filter(fylkesnumm == "50") %>%
  summarise() %>%
  st_simplify(dTolerance = 500, preserveTopology = TRUE)

#-------------------------------------------------------------------------------
# Gaula main course (NVE Elvenett, main river layer)
#-------------------------------------------------------------------------------
gaula <- st_read(file.path(p_geo, "Hydrography/Norway_RiverNetwork/Original/Elv_2023.gdb"),
                 layer = "Elv_Hovedelv", quiet = TRUE) %>%
  filter(nedborfeltVassdragNr == "122.Z") %>%
  st_transform(25832) %>%
  summarise(elvenavn = "Gaula")

#-------------------------------------------------------------------------------
# Minimum bounding geometry (convex hull) per site
#-------------------------------------------------------------------------------
lukeomrade <- st_read(file.path(p_elvedyr, "Lupinluking_2026/Lupinluking_2025_2026_merged.shp"), quiet = TRUE) %>%
  st_make_valid() %>%
  filter(site_name %in% names(sites)) %>%
  mutate(site = unname(sites[site_name])) %>%
  group_by(site) %>%
  summarise(n_polygoner = n()) %>%
  st_convex_hull()

edderkoppomrade <- st_read(file.path(p_elvedyr, "Elevebreddedderkopp/2026/elvebreddedderkopp_polygons_2025-2026_utm32.gpkg"),
                           quiet = TRUE) %>%
  st_make_valid() %>%
  filter(lokalitet %in% names(spider_codes)) %>% # "annen" (one 2026 polygon outside the sites) is left out
  mutate(site = unname(spider_codes[lokalitet])) %>%
  group_by(site) %>%
  summarise(n_polygoner = n(), aar = paste(sort(unique(year)), collapse = "-")) %>%
  st_convex_hull()

#-------------------------------------------------------------------------------
# Square map frame per site around the clearing and spider hulls
#-------------------------------------------------------------------------------
site_frame <- function(s) {
  g <- st_union(st_geometry(filter(lukeomrade, site == s)), st_geometry(filter(edderkoppomrade, site == s)))
  bb <- st_bbox(g)
  half <- max(diff(bb[c("xmin", "xmax")]), diff(bb[c("ymin", "ymax")])) / 2
  half <- half * 1.25 + 40 # some context around the hulls
  cx <- mean(bb[c("xmin", "xmax")]); cy <- mean(bb[c("ymin", "ymax")])
  st_as_sfc(st_bbox(c(xmin = cx - half, xmax = cx + half, ymin = cy - half, ymax = cy + half), crs = st_crs(g)))
}
utsnitt <- st_sf(site = unname(sites), geometry = do.call(c, lapply(unname(sites), site_frame)))

#-------------------------------------------------------------------------------
# Orthophoto (Norge i bilder) per site frame
#-------------------------------------------------------------------------------
for (i in seq_len(nrow(utsnitt))) {
  bb <- round(st_bbox(utsnitt[i, ]))
  url <- paste0("https://wms.geonorge.no/skwms1/wms.nib?service=WMS&version=1.3.0&request=GetMap",
                "&layers=ortofoto&styles=&crs=EPSG:25832&format=image/jpeg&width=1400&height=1400",
                "&bbox=", paste(bb[c("xmin", "ymin", "xmax", "ymax")], collapse = ","))
  download.file(url, here::here("data", paste0("ortofoto_", site_file[utsnitt$site[i]], ".jpg")), mode = "wb", quiet = TRUE)
}
utsnitt$ortofoto_bbox <- sapply(seq_len(nrow(utsnitt)), function(i) paste(round(st_bbox(utsnitt[i, ])), collapse = ","))

#-------------------------------------------------------------------------------
# Site photos -> img/ (upright, max 1280 px)
#-------------------------------------------------------------------------------
for (f in names(sites)) {
  image_read(file.path(p_photos, paste0("Foto_", f, ".jpg"))) %>%
    image_orient() %>%
    image_resize("1280x1280>") %>%
    image_write(here::here("img", paste0("foto_", f, ".jpg")), quality = 85)
}

#-------------------------------------------------------------------------------
# Write
#-------------------------------------------------------------------------------
if (file.exists(out)) file.remove(out)
st_write(norge, out, layer = "norge", quiet = TRUE)
st_write(trondelag, out, layer = "trondelag", quiet = TRUE)
st_write(gaula, out, layer = "gaula", quiet = TRUE)
st_write(lukeomrade, out, layer = "lukeomrade", quiet = TRUE)
st_write(edderkoppomrade, out, layer = "edderkoppomrade", quiet = TRUE)
st_write(utsnitt, out, layer = "utsnitt", quiet = TRUE)
print(st_layers(out))
