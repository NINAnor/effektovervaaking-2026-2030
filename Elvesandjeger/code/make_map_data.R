#Effektovervaaking - elvesandjeger
#Map data for the site map in the report (section 3.1).
#
#Writes data/kart_elvedyr.gpkg with the layers
# - norge:            Norway, county polygons dissolved and simplified (EPSG:25833)
# - trondelag:        Trøndelag county, simplified (EPSG:25833)
# - gaula:            main course of Gaula, NVE Elvenett (vassdrag 122.Z) (EPSG:25832)
# - lukeomrade:       minimum bounding geometry (convex hull) of the lupin clearing
#                     polygons per site (Lupinluking_2025_2026_merged.shp) (EPSG:25832)
# - sandjegeromrade:  convex hull of the elvesandjeger records with larvae or adults
#                     in the last three years per site (master file) (EPSG:25832)
# - utsnitt:          square map frame per site around both hulls (EPSG:25832)
#
#and per site
# - data/ortofoto_<site>.jpg: Norge i bilder orthophoto covering exactly the site frame
#   (Kartverket/Geovekst, WMS https://wms.geonorge.no/skwms1/wms.nib, layer "ortofoto")
# - img/foto_<site>.jpg:      site photo, turned upright (EXIF orientation) and resized
# - img/foto_hull.jpg:        photo of larval holes for the introduction, cropped to the pencil and
#                             holes and sized as img/foto_elvesandjeger_voksen.jpg (610 x 516)
#
#Only the four monitoring sites are kept (Follstadøya has clearing but no elvesandjeger monitoring).
#Run again when the clearing polygons, the master file or the site photos change.
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
p_photos <- "/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Figures/elvesandjeger/Photos"
#p_photos <- "P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Figures/elvesandjeger/Photos" #Windows

out <- here::here("data", "kart_elvedyr.gpkg")

sites <- c(Storronningen = "Storrønningen", Kregnesteigen = "Kregnesteigen", Fornes = "Fornes", Gravrak = "Gravråk")
site_file <- setNames(names(sites), sites) # file names without æøå, e.g. ortofoto_Gravrak.jpg
master_codes <- c(Storr = "Storrønningen", Kreg = "Kregnesteigen", Forn = "Fornes", Grav = "Gravråk")

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

# Records with larvae or adults in the last three years (GPS points to 2025, polygon centroids from 2026)
master <- read.csv2(list.files(here::here("data"), "_master\\.csv$", full.names = TRUE))
last_years <- seq(max(master$year) - 2, max(master$year))
recs <- master %>%
  filter(year %in% last_years, site %in% names(master_codes), stage != "larva", obs > 0, !is.na(N), !is.na(E)) %>%
  distinct(site, N, E, year)
sandjegeromrade <- st_as_sf(recs, coords = c("E", "N"), crs = 25832) %>%
  mutate(site = unname(master_codes[site])) %>%
  group_by(site) %>%
  summarise(n_punkter = n(), aar = paste(range(year), collapse = "-")) %>%
  st_convex_hull()

#-------------------------------------------------------------------------------
# Square map frame per site around the clearing and elvesandjeger hulls
#-------------------------------------------------------------------------------
site_frame <- function(s) {
  g <- st_union(st_geometry(filter(lukeomrade, site == s)), st_geometry(filter(sandjegeromrade, site == s)))
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
photo_file <- c(Storronningen = "storr", Kregnesteigen = "kreg", Fornes = "fornes", Gravrak = "gravrak")
if (dir.exists(p_photos)) {
  for (f in names(sites)) {
    image_read(file.path(p_photos, paste0("elvesandjeger_", photo_file[f], "_2026.jpg"))) %>%
      image_orient() %>%
      image_resize("1280x1280>") %>%
      image_write(here::here("img", paste0("foto_", f, ".jpg")), quality = 85)
  }
  image_read(file.path(p_photos, "elvesandjeger_hull_2026.jpg")) %>%
    image_orient() %>%
    image_resize("1280x1280>") %>%
    image_crop("851x720+60+350") %>% # pencil and cluster of holes
    image_resize("610x516!") %>%     # same size as the adult photo
    image_write(here::here("img", "foto_hull.jpg"), quality = 85)
}

#-------------------------------------------------------------------------------
# Write
#-------------------------------------------------------------------------------
if (file.exists(out)) file.remove(out)
st_write(norge, out, layer = "norge", quiet = TRUE)
st_write(trondelag, out, layer = "trondelag", quiet = TRUE)
st_write(gaula, out, layer = "gaula", quiet = TRUE)
st_write(lukeomrade, out, layer = "lukeomrade", quiet = TRUE)
st_write(sandjegeromrade, out, layer = "sandjegeromrade", quiet = TRUE)
st_write(utsnitt, out, layer = "utsnitt", quiet = TRUE)
print(st_layers(out))
