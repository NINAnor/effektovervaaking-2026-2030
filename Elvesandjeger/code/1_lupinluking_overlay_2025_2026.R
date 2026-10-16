#Effektovervaaking - elvedyr (elvesandjeger og stor elvebreddedderkopp)
#Script for combining the 2026 lupin clearing polygons from MidNat with the
#2025 polygons so that the clearing history (2020-2025) is carried over to the
#new 2026 geometry.
#
#Background: In the 2026 delivery MidNat merged several polygons (e.g. Storrønningen
#22-26 -> 22, Gravråk 3+4+11 -> 3), added new polygons (Follstadøya 14-27, Fornes 1-2,
#Gravråk 15/17/18, Storrønningen 56c/61) and nudged vertices on ~20 polygons by
#0.2-5 m. GlobalID is regenerated in each export, so polygons cannot be joined on ID.
#
#Approach:
# 1. Overlay 2025 and 2026 polygons ("identity" overlay with 2026 as master):
#    - pieces covered by both years get all 2025 attributes (history 2020-2025)
#      + the 2026 attributes (_26)
#    - pieces only in 2026 (new polygons / extended areas) get the 2026 attributes
#      and Luket = "Nei" for 2020-2025
#    - parts of 2025 polygons that are no longer inside a 2026 polygon are dropped
# 2. Explode to single-part polygons. NO slivers are removed: the small pieces
#    created where the 2025 and 2026 boundaries do not coincide are kept so
#    that they can be assessed manually (see area_m2 column).
# 3. Add site name columns without Norwegian letters and write the result as a
#    shapefile (+ csv of the attribute table).
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

# Load the libraries
library(sf)
library(dplyr)
library(stringr)

sf_use_s2(FALSE) #planar geometry (data are in EUREF89 UTM32N, EPSG:25832)

#-------------------------------------------------------------------------------
# 1. Read the data
#-------------------------------------------------------------------------------

# 2025 polygons (MidNat delivery, contains the clearing history 2020-2025)
luk25 <- st_read("./Lupinluking_2025/Lupinluking_2025_MidNat/Lupinluking_2025_MidNat.shp")

# 2026 polygons: unzip the MidNat delivery into ./Lupinluking_2026 (only if not already done)
dir_26 <- "./Lupinluking_2026/Lupinluking_MidNat_2026"
if (!file.exists(file.path(dir_26, "Lupinluking_MidNat_2026.shp"))) {
  unzip("./Lupinluking_MidNat_2026.zip", exdir = dir_26, junkpaths = TRUE) #zip has a "Til NINA/" subfolder
}
luk26 <- st_read(file.path(dir_26, "Lupinluking_MidNat_2026.shp"))

nrow(luk25) #87
nrow(luk26) #102
st_crs(luk25) == st_crs(luk26) #both EPSG:25832
names(luk25)
names(luk26)

# MidNat uses 0000/00/00 as "no date" in the shapefiles, which GDAL reads as a
# nonsense date (year -1). Set all dates before 2000 to NA.
fix_dates <- function(x) {
  mutate(x, across(where(~ inherits(.x, "Date")), ~ if_else(.x < as.Date("2000-01-01"), as.Date(NA), .x)))
}
luk25 <- fix_dates(luk25)
luk26 <- fix_dates(luk26)

# Attributes are constant over the polygon (avoids warnings in st_intersection)
st_agr(luk25) <- "constant"
st_agr(luk26) <- "constant"

#-------------------------------------------------------------------------------
# 2. Select the columns to keep
#-------------------------------------------------------------------------------

# 2026: keep only the fields belonging to 2026 (suffix _26) plus the polygon name.
# The name is renamed to Lok_26 so that it does not clash with Lokalitet from 2025
# (shapefile field names are limited to 10 characters).
luk26_sel <- luk26 %>%
  dplyr::select(Lok_26 = Lokalitet, ends_with("_26"))
names(luk26_sel)

# 2025: keep the whole attribute table with the history 2020-2025 (Dato_, Luket_,
# Antall_, Komment_/Comment_ and Metode_ for each year). Only GlobalID (regenerated
# in every export, so meaningless) and the ArcGIS Shape_Length/Shape_Area fields
# (wrong after the overlay, area is recalculated below) are dropped.
# The 2025 name is also kept as Lok_25.
luk25_sel <- luk25 %>%
  dplyr::select(-GlobalID, -Shape_Leng, -Shape_Area) %>%
  mutate(Lok_25 = Lokalitet, .after = Lokalitet)
names(luk25_sel)

#-------------------------------------------------------------------------------
# 3. Overlay (identity: 2026 geometry is the master)
#-------------------------------------------------------------------------------

# 3a. Pieces that are inside both a 2025 and a 2026 polygon -> both sets of attributes
both <- st_intersection(luk25_sel, luk26_sel) %>%
  st_collection_extract("POLYGON") #drop points/lines where boundaries only touch

# 3b. Pieces of the 2026 polygons that are NOT covered by any 2025 polygon
#     (new polygons and areas added to existing polygons) -> only 2026 attributes
only26 <- st_difference(luk26_sel, st_union(luk25_sel)) %>%
  st_collection_extract("POLYGON")

# For information: parts of the 2025 polygons that are no longer inside a 2026
# polygon. These are dropped from the output (2026 geometry is the master).
only25 <- st_difference(luk25_sel, st_union(luk26_sel)) %>%
  st_collection_extract("POLYGON")
cat("Area in 2025 but not in 2026 (dropped):", round(sum(st_area(only25))), "m2\n")

# Combine 3a and 3b. Rows from only26 get NA for the 2025 columns.
overlay <- bind_rows(both, only26) %>%
  mutate(new_26 = is.na(Lok_25)) #TRUE = area not covered by a 2025 polygon

nrow(overlay)

#-------------------------------------------------------------------------------
# 4. Explode to single-part polygons (no sliver removal)
#-------------------------------------------------------------------------------

# Each 2025 x 2026 combination can consist of several separate parts (e.g. a
# wide piece plus thin slivers along a nudged boundary). They are split into
# single polygons so that each small piece is its own row and can be assessed
# and deleted manually. part_id numbers the parts within each combination.
overlay <- overlay %>%
  st_cast("MULTIPOLYGON") %>%
  st_cast("POLYGON", warn = FALSE) %>%
  mutate(area_m2 = round(as.numeric(st_area(geometry)), 2)) %>%
  group_by(Lok_25, Lok_26) %>%
  mutate(part_id = row_number(), n_parts = n()) %>%
  ungroup()

nrow(overlay)

# Overview of the small pieces to assess manually
overlay %>%
  st_drop_geometry() %>%
  mutate(size = cut(area_m2, c(0, 1, 10, 50, Inf), labels = c("<1 m2", "1-10 m2", "10-50 m2", ">50 m2"), include.lowest = TRUE)) %>%
  count(size, new_26)

#-------------------------------------------------------------------------------
# 5. Fill in the history for the new 2026 rows and add site name columns
#-------------------------------------------------------------------------------

# Areas that were not part of any 2025 polygon have not been cleared in earlier
# years: Luket = "Nei", Antall = 0 and Metode = "Ingen" for 2020-2025.
# Lokalitet is filled with the 2026 name so that every row has a name
# (Lok_25 stays NA for these rows).
overlay <- overlay %>%
  mutate(
    across(c(Luket_20, Luket_21, Luket_22, Luket_23, Luket_24, Luket_25),
           ~ if_else(new_26, "Nei", .x)),
    across(c(Antall_20, Antall_21, Antall_22, Antall_23, Antall_24, Antall_25),
           ~ if_else(new_26, 0L, as.integer(.x))),
    Metode_25 = if_else(new_26, "Ingen", Metode_25),
    Antall_26 = as.integer(Antall_26),
    Lokalitet = if_else(new_26, Lok_26, Lokalitet)
  )

# Site name columns:
#  site_name = locality name without the polygon number and without Norwegian
#              letters (e.g. "Storrønningen 22" -> "Storronningen", "Gravråk 3" -> "Gravrak")
#  site_code = first four letters of site_name (e.g. "Stor", "Grav")
overlay <- overlay %>%
  mutate(
    site_name = str_remove(Lokalitet, "\\s+\\d.*$"), #remove " 22", " 56a", " 1-4"
    site_name = str_replace_all(site_name, c("ø" = "o", "å" = "a", "æ" = "ae",
                                             "Ø" = "O", "Å" = "A", "Æ" = "Ae")),
    site_code = str_sub(site_name, 1, 4)
  ) %>%
  arrange(Lok_26, Lok_25, part_id) %>%
  mutate(tempID = row_number()) %>% #temporary integer ID (1..n) for every polygon feature
  dplyr::select(tempID, Lokalitet, Lok_25, Lok_26, site_name, site_code, new_26,
                part_id, n_parts, area_m2, everything())

table(overlay$site_name, overlay$site_code)
names(overlay)
head(overlay)

#-------------------------------------------------------------------------------
# 6. Checks
#-------------------------------------------------------------------------------

# Total area should equal the 2026 total (nothing removed)
cat("Total area 2026 delivery:", round(sum(st_area(luk26))), "m2\n")
cat("Total area overlay:      ", round(sum(overlay$area_m2)), "m2\n")

# Merged polygons in 2026 -> several 2025 names per 2026 name
overlay %>%
  st_drop_geometry() %>%
  filter(!new_26, part_id == 1) %>%
  group_by(Lok_26) %>%
  filter(n() > 1) %>%
  dplyr::select(Lok_26, Lok_25, area_m2, Luket_23, Luket_24, Luket_25, Luket_26) %>%
  arrange(Lok_26)

# New areas in 2026
overlay %>%
  st_drop_geometry() %>%
  filter(new_26) %>%
  dplyr::select(Lok_26, part_id, area_m2, Luket_25, Luket_26) %>%
  print(n = Inf)

plot(st_geometry(luk26), border = "grey")
plot(overlay["new_26"], add = TRUE)

#-------------------------------------------------------------------------------
# 7. Write out
#-------------------------------------------------------------------------------

# Shapefile: logical new_26 is written as integer (1 = new in 2026).
st_write(overlay, "./Lupinluking_2026/Lupinluking_2025_2026_overlay.shp",
         append = FALSE, layer_options = "ENCODING=UTF-8")

# Attribute table as csv
write.csv(st_drop_geometry(overlay),
          "./Lupinluking_2026/Lupinluking_2025_2026_overlay.csv",
          row.names = FALSE)
