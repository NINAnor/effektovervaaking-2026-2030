#Effektovervaaking - elvedyr (elvesandjeger og stor elvebreddedderkopp)
#Script for topological cleaning of the merged 2025-2026 lupin polygons
#(output of 2_lupinluking_merge_polygons.R):
# 1. Snap vertices that lie within snap_tol (1 m) of a neighbouring polygon's
#    boundary onto that boundary. Polygons are processed from largest to
#    smallest, each one snapped to the polygons already processed, so large
#    polygons keep their shape and small ones adapt. Only vertices close to a
#    neighbour move - the polygon as a whole is not shifted.
# 2. Remove any remaining overlap with the already processed neighbours.
# 3. Remove slivers (narrower than sliver_width everywhere), polygons with
#    0 m2 and tiny polygons (< min_area). Multipart polygons are tested part
#    by part.
# 4. Tidy the attribute table: one block of Dato/Luket/Antall(/Metode)/Komment
#    per year 2020-2026, standardised Luket values (Ja/Delvis/Nei, no NA),
#    Nei/0 for earlier years in areas that are new in 2026, and Antall_luk =
#    number of years (2020-2026) the polygon was cleared (Ja or Delvis).
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(sf)
library(dplyr)
library(stringr)

sf_use_s2(FALSE)

# Parameters
snap_tol     <- 1.0  #m: vertices closer than this to a neighbour are snapped to it
sliver_width <- 0.5  #m: parts narrower than this everywhere are removed
min_area     <- 5    #m2: parts smaller than this are removed

#-------------------------------------------------------------------------------
# 1. Read
#-------------------------------------------------------------------------------
m <- st_read("./Lupinluking_2026/Lupinluking_2025_2026_merged.shp")
nrow(m) #180
st_agr(m) <- "constant"

# Helper: number of overlapping pairs and total overlap area in a layer
overlap_stats <- function(x) {
  ov <- st_overlaps(x)
  pairs <- do.call(rbind, lapply(seq_along(ov), function(i) {
    j <- ov[[i]][ov[[i]] > i]
    if (length(j)) cbind(i = rep(i, length(j)), j = j) else NULL
  }))
  if (is.null(pairs) || nrow(pairs) == 0) return(c(pairs = 0, area_m2 = 0))
  a <- sapply(seq_len(nrow(pairs)), function(k)
    sum(as.numeric(st_area(st_intersection(st_geometry(x)[pairs[k, 1]], st_geometry(x)[pairs[k, 2]])))))
  c(pairs = nrow(pairs), area_m2 = round(sum(a), 2))
}
cat("Overlaps before cleaning:\n"); print(overlap_stats(m))

#-------------------------------------------------------------------------------
# 2. Snap to neighbours and remove overlaps (largest polygon first)
#-------------------------------------------------------------------------------
m <- m %>% arrange(desc(area_m2))
g <- st_geometry(m)
done <- st_sfc(crs = st_crs(m)) #polygons already processed

for (i in seq_along(g)) {
  gi <- g[i]
  if (length(done) > 0) {
    # neighbours = processed polygons within snap_tol of this one
    nb <- done[lengths(st_is_within_distance(done, gi, dist = snap_tol)) > 0]
    if (length(nb) > 0) {
      nb_union <- st_union(nb)
      gi <- st_snap(gi, nb_union, tolerance = snap_tol) #move close vertices onto neighbour boundary
      gi <- st_make_valid(gi)
      gi <- st_difference(gi, nb_union)                 #remove remaining overlap with neighbours
      if (length(gi) == 0 || st_is_empty(gi)) {
        gi <- st_sfc(st_multipolygon(), crs = st_crs(m))
      } else {
        if (st_geometry_type(gi) == "GEOMETRYCOLLECTION") gi <- st_collection_extract(gi, "POLYGON")
        gi <- st_union(gi) #back to one (multi)polygon
      }
    }
  }
  g[i] <- gi
  done <- c(done, gi)
}
st_geometry(m) <- g

# Check that no polygon has been pushed outwards by more than snap_tol:
# the area of the new polygon lying outside the original polygon buffered by
# snap_tol must be zero for every polygon.
m_old <- st_read("./Lupinluking_2026/Lupinluking_2025_2026_merged.shp", quiet = TRUE) %>% arrange(desc(area_m2))
outside <- sapply(seq_len(nrow(m)), function(i) {
  if (st_is_empty(g[i])) return(0)
  d <- st_difference(g[i], st_buffer(st_geometry(m_old)[i], snap_tol))
  if (length(d) == 0) 0 else sum(as.numeric(st_area(d)))
})
cat("Polygons extending > ", snap_tol, " m outside their original (should be 0):", sum(outside > 0.01), "\n")

# Area added by closing gaps to neighbours and removed by overlap removal
added   <- sapply(seq_len(nrow(m)), function(i) { d <- st_difference(g[i], st_geometry(m_old)[i]); if (length(d) == 0) 0 else sum(as.numeric(st_area(d))) })
removed <- sapply(seq_len(nrow(m)), function(i) { d <- st_difference(st_geometry(m_old)[i], g[i]); if (length(d) == 0) 0 else sum(as.numeric(st_area(d))) })
cat("Area added (gaps closed):", round(sum(added, na.rm = TRUE)), "m2; area removed (overlaps):", round(sum(removed, na.rm = TRUE)), "m2\n")

cat("Overlaps after snapping:\n"); print(overlap_stats(m[!st_is_empty(m), ]))

#-------------------------------------------------------------------------------
# 3. Remove slivers, 0 m2 and tiny polygons (part by part)
#-------------------------------------------------------------------------------
parts <- m %>%
  filter(!st_is_empty(geometry)) %>%
  st_cast("MULTIPOLYGON") %>%
  st_cast("POLYGON", warn = FALSE) %>%
  mutate(
    part_area = as.numeric(st_area(geometry)),
    sliver    = st_is_empty(st_buffer(geometry, dist = -sliver_width / 2)),
    tiny      = part_area < min_area,
    remove    = sliver | tiny
  )

# Summary of removed parts
parts %>%
  st_drop_geometry() %>%
  group_by(remove, sliver, tiny) %>%
  summarise(n_parts = n(), area_m2 = round(sum(part_area), 1), .groups = "drop")

# Whole polygons (tempID) that disappear completely
gone <- parts %>%
  st_drop_geometry() %>%
  group_by(tempID, Lok_25, Lok_26, new_26) %>%
  summarise(area_m2 = round(sum(part_area), 2), all_removed = all(remove), .groups = "drop") %>%
  filter(all_removed)
cat("Polygons removed completely:", nrow(gone), "\n")
print(as_tibble(gone), n = Inf)

clean <- parts %>%
  filter(!remove) %>%
  dplyr::select(-part_area, -sliver, -tiny, -remove)

# Re-assemble parts of the same polygon (tempID)
attr_cols <- setdiff(names(clean), "geometry")
clean <- clean %>%
  group_by(across(all_of(attr_cols))) %>%
  summarise(geometry = st_union(geometry), .groups = "drop") %>%
  st_cast("MULTIPOLYGON") %>%
  mutate(area_m2 = round(as.numeric(st_area(geometry)), 2)) %>%
  arrange(tempID)

#-------------------------------------------------------------------------------
# 4. Tidy the attribute table
#-------------------------------------------------------------------------------
years <- 20:26

# Dato_21 is a text field in the source ("dd.mm") -> convert to a proper date
dato21_raw <- clean$Dato_21
clean <- clean %>%
  mutate(Dato_21 = as.Date(if_else(is.na(Dato_21) | Dato_21 == "", NA_character_, paste0(Dato_21, ".2021")),
                           format = "%d.%m.%Y"))
cat("Dato_21 values that could not be converted:",
    paste(unique(dato21_raw[!is.na(dato21_raw) & dato21_raw != "" & is.na(clean$Dato_21)]), collapse = ", "), "\n")

clean <- clean %>%
  # consistent comment field names, drop the empty ArcGIS "Field" column
  rename(Komment_25 = Comment_25, Komment_26 = Comment_26) %>%
  dplyr::select(-Field) %>%
  mutate(
    # Luket: Ja / Delvis / Nei. MidNat left the field blank (NA) or in lower
    # case for some polygons/years -> blank means not cleared.
    across(all_of(paste0("Luket_", years)), ~ str_to_title(str_trim(.x))),
    across(all_of(paste0("Luket_", years)), ~ if_else(is.na(.x) | .x == "", "Nei", .x)),
    # Antall: number of lupins removed, 0 when nothing recorded
    across(all_of(paste0("Antall_", years)), ~ coalesce(as.integer(.x), 0L)),
    # Areas that were not part of any polygon before 2026 (new_26 = 1) have
    # not been cleared in earlier years
    across(all_of(paste0("Luket_", 20:25)),  ~ if_else(new_26 == 1, "Nei", .x)),
    across(all_of(paste0("Antall_", 20:25)), ~ if_else(new_26 == 1, 0L, .x)),
    Metode_25 = if_else(new_26 == 1, "Ingen", Metode_25)
  )

table(unlist(st_drop_geometry(clean)[, paste0("Luket_", years)]), useNA = "ifany") #only Ja/Delvis/Nei

# Number of years (2020-2026) each polygon was cleared (Ja or Delvis).
# (Antall_luket is shortened to Antall_luk because shapefile field names are
# limited to 10 characters.)
luket_mat <- st_drop_geometry(clean)[, paste0("Luket_", years)]
clean$Antall_luk <- as.integer(rowSums(luket_mat == "Ja" | luket_mat == "Delvis"))
table(clean$Antall_luk)

# Column order: id/name fields, then one block per year 2020 -> 2026
year_cols <- unlist(lapply(years, function(y)
  intersect(paste0(c("Dato_", "Luket_", "Antall_", "Metode_", "Komment_"), y), names(clean))))
clean <- clean %>%
  dplyr::select(tempID, Lokalitet, Lok_25, Lok_26, site_name, site_code, new_26,
                n_merged, merged_frm, area_m2, Antall_luk, all_of(year_cols))
names(clean)

#-------------------------------------------------------------------------------
# 5. Checks
#-------------------------------------------------------------------------------
nrow(clean)
all(st_is_valid(clean))
cat("Overlaps after cleaning:\n"); print(overlap_stats(clean))
cat("Area before:", round(sum(m_old$area_m2)), "m2   after:", round(sum(clean$area_m2)), "m2\n")

# Remaining polygons < 10 m2
clean %>% st_drop_geometry() %>% as_tibble() %>%
  filter(area_m2 < 10) %>% dplyr::select(tempID, Lok_25, Lok_26, new_26, area_m2) %>% arrange(area_m2)

# Multipart polygons left (non-contiguous)
clean %>% st_drop_geometry() %>% as_tibble() %>%
  mutate(n_polys = sapply(st_geometry(clean), function(x) length(st_cast(st_sfc(x), "POLYGON")))) %>%
  filter(n_polys > 1) %>% dplyr::select(tempID, Lok_25, Lok_26, n_polys, area_m2)

#-------------------------------------------------------------------------------
# 6. Write out (merged file is left untouched)
#-------------------------------------------------------------------------------
st_write(clean, "./Lupinluking_2026/Lupinluking_2025_2026_clean.shp",
         append = FALSE, layer_options = "ENCODING=UTF-8")
write.csv(st_drop_geometry(clean),
          "./Lupinluking_2026/Lupinluking_2025_2026_clean.csv", row.names = FALSE)
