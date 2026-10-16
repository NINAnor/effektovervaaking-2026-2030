#Effektovervaaking - elvedyr (elvesandjeger og stor elvebreddedderkopp)
#Script for manually merging/deleting small polygons in the 2025-2026 overlay
#(output of 1_lupinluking_overlay_2025_2026.R). The pieces to merge were
#identified by inspecting the overlay in GIS, referring to the tempID column.
#
#Rules:
# - Each merge group is dissolved into one polygon.
# - The attributes (incl. tempID) of the LARGEST polygon in the group are kept.
# - area_m2 is recalculated; part_id/n_parts are replaced by n_merged and
#   merged_frm (the tempIDs that went into the polygon).
# - Polygons in the delete list are removed.
# - All other polygons are kept unchanged.
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(sf)
library(dplyr)

sf_use_s2(FALSE)

#-------------------------------------------------------------------------------
# 1. Read the overlay
#-------------------------------------------------------------------------------
ov <- st_read("./Lupinluking_2026/Lupinluking_2025_2026_overlay.shp")
nrow(ov) #252
st_agr(ov) <- "constant"

#-------------------------------------------------------------------------------
# 2. Instructions (round 1, 2026-09-16)
#-------------------------------------------------------------------------------
# Each vector is one merge group; the first tempID is the polygon that was named
# as the target. The attributes are taken from the largest polygon in the group
# (a warning is printed if that is not the named target).
merge_groups <- list(
  c(31, 32, 33, 34),
  c(41, 40, 57),
  c(226, 227),
  c(234, 235),
  c(113, 114, 115, 116, 117),
  c(216, 217),
  c(110, 109, 111),
  c(248, 246, 247),
  c(107, 108),
  c(123, 124),
  c(120, 121),
  c(239, 240),
  c(132, 131, 137),
  c(136, 144, 145),
  c(135, 143),
  c(162, 163, 165, 166, 167),
  c(169, 168),
  c(159, 158, 160),
  c(152, 154, 155),
  c(175, 172, 173, 174),
  c(176, 179, 183),
  c(177, 180, 181, 182),
  c(184, 178),
  c(73, 74),
  c(79, 80, 81),
  c(83, 84, 85, 86),
  c(87, 89, 91, 93),
  c(100, 97, 98),
  c(90, 92, 94, 96, 99),
  c(102, 104),
  c(64, 66, 67, 68, 69, 70),
  c(63, 60, 65),
  c(46, 47, 48, 51)
)

delete_ids <- c(54, 55, 56)

# Sanity checks on the instructions
all_ids <- c(unlist(merge_groups), delete_ids)
stopifnot(!any(duplicated(all_ids)))        #no tempID used twice
stopifnot(all(all_ids %in% ov$tempID))      #all tempIDs exist

#-------------------------------------------------------------------------------
# 3. Merge
#-------------------------------------------------------------------------------
merge_one <- function(ids, data) {
  grp <- data %>% filter(tempID %in% ids)
  keep <- grp %>% slice_max(area_m2, n = 1, with_ties = FALSE) #largest polygon
  if (keep$tempID != ids[1]) {
    message("Group ", paste(ids, collapse = ","), ": named target ", ids[1],
            " (", grp$area_m2[grp$tempID == ids[1]], " m2) is not the largest; attributes taken from ",
            keep$tempID, " (", keep$area_m2, " m2)")
  }
  geom <- st_union(st_geometry(grp))
  st_geometry(keep) <- geom
  keep %>% mutate(n_merged = nrow(grp),
                  merged_frm = paste(sort(ids), collapse = ";"))
}

merged <- bind_rows(lapply(merge_groups, merge_one, data = ov))
nrow(merged) #one row per group

# Non-contiguous results (union gave a multipolygon) -> worth checking in GIS
merged %>%
  st_drop_geometry() %>%
  mutate(n_polys = sapply(st_geometry(merged), function(g) length(st_cast(st_sfc(g), "POLYGON")))) %>%
  filter(n_polys > 1) %>%
  dplyr::select(tempID, merged_frm, n_polys)

#-------------------------------------------------------------------------------
# 4. Assemble: untouched polygons + merged polygons, minus deleted
#-------------------------------------------------------------------------------
untouched <- ov %>%
  filter(!tempID %in% all_ids) %>%
  mutate(n_merged = 1L, merged_frm = as.character(tempID))

result <- bind_rows(untouched, merged) %>%
  st_cast("MULTIPOLYGON") %>%
  mutate(area_m2 = round(as.numeric(st_area(geometry)), 2)) %>%
  dplyr::select(-part_id, -n_parts) %>%
  arrange(tempID) %>%
  dplyr::select(tempID, Lokalitet, Lok_25, Lok_26, site_name, site_code, new_26,
                n_merged, merged_frm, area_m2, everything())

nrow(result)          #252 - 69 absorbed - 3 deleted = 180
all(st_is_valid(result))

# Area check: the deleted polygons are missing, and the union in each merge
# group removes the small overlaps that existed between neighbouring pieces
cat("Area overlay:", round(sum(ov$area_m2)), "m2\n")
cat("Area deleted:", round(sum(ov$area_m2[ov$tempID %in% delete_ids], na.rm = TRUE), 1), "m2\n")
cat("Area result: ", round(sum(result$area_m2)), "m2\n")

# Remaining small pieces for the next round of checking
result %>%
  st_drop_geometry() %>%
  as_tibble() %>%
  filter(area_m2 < 10) %>%
  dplyr::select(tempID, Lok_25, Lok_26, new_26, area_m2) %>%
  arrange(area_m2) %>%
  print(n = Inf)

#-------------------------------------------------------------------------------
# 5. Write out (the overlay file is left untouched)
#-------------------------------------------------------------------------------
st_write(result, "./Lupinluking_2026/Lupinluking_2025_2026_merged.shp",
         append = FALSE, layer_options = "ENCODING=UTF-8")
write.csv(st_drop_geometry(result),
          "./Lupinluking_2026/Lupinluking_2025_2026_merged.csv", row.names = FALSE)
