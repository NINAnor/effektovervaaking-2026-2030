#### Data export from script 2 needs to be reformatted to fit with dataset from previous years

## Packages
library(readxl)
library(dplyr)
library(ggplot2)
library(sciplot)
library(boot)
library(Matrix)
library(lme4)
library(vegan)
library(tibble)
library(lubridate)
library(tidyr)
library(stringr)
library(openxlsx)

#### ---- Import data ---- ####

### new dataset from Survey123 ###
plot_2026 <- readxl::read_excel(here::here("data", 
                                           "S123_2026", 
                                           "GRUK_effekt_2026_processed", 
                                           "Exports", 
                                           "GRUK_effekt_2026_data_analyses.xlsx"), 
                                sheet = "plots" )

### Fyrsteila-dataset from 2025 ###
fil <- here::here("data", "Fyrsteilene data 2025_NINA.xlsx")


### Old datasets from 2022-25 ###
plot_2022_25 <- readxl::read_excel(here::here("data", "GRUK_effekt_data_2025_updated.xlsx"), sheet = "plots")

### species data from Survey123 2026 ###
plotspecies_2026 <- readxl::read_excel(here::here("data", 
                                                  "S123_2026", 
                                                  "GRUK_effekt_2026_processed", 
                                                  "Exports", 
                                                  "GRUK_effekt_2026_data_analyses.xlsx"), 
                                       sheet = "plot_species_long")
  
### old dataset from 2022-25 ###
plotspecies_2022_25 <- readxl::read_excel(here::here("data", 
                                                     "GRUK_effekt_data_2025_updated.xlsx"), sheet = "species.long")

### new 2026 circle data from Survey123
circle_2026 <- readxl::read_excel(here::here("data", 
                                             "S123_2026", 
                                             "GRUK_effekt_2026_processed",
                                             "Exports",
                                             "GRUK_effekt_2026_data_analyses.xlsx"), sheet = "circles")
                                             
circle_2022_25 <- readxl::read_excel(here::here("data", 
                                                "GRUK_effekt_data_2025_updated.xlsx"),
                                     sheet="circles")
                                                
### new 2026 circle species data from Survey123
circlespecies_2026 <- readxl::read_excel(here::here("data", 
                                                    "S123_2026", 
                                                    "GRUK_effekt_2026_processed",
                                                    "Exports",
                                                    "GRUK_effekt_2026_data_analyses.xlsx"), 
                                         sheet = "circle_species_long")

### old circle species data  
circlespecies_2022_25 <- readxl::read_excel(here::here("data", 
                                                       "GRUK_effekt_data_2025_updated.xlsx")
                                            ,sheet="species.circles")
#GPS data
GPS_GRUK <- readxl::read_excel(here::here("data", 
                                          "GRUK_effekt_vegruter_2026_oppdatert.xlsx"),
                               sheet="GRUK_effekt_vegruter_2026")
                                          
  
  
#### ---- Plot data ---- #### 
# creating variable names that correspond to existing dataset
plot_2026_rev <- plot_2026 %>%
  rename(
    Dato = event_time,
    Lokalitet = main_location_id,
    Rute = main_plot_id,
    Registrant = main_observant_name,
    Plot.mapping.unit = plot_nature_type,
    Field.layer = plot_cover_fieldlayer,
    Bryophytes = plot_cover_bryophytes,
    Dead.organic.matter = plot_cover_litter,
    Gravel.stone = plot_cover_bedrock,
    Lichens = plot_cover_lichen,
    Mineralsoil = plot_cover_baresoil
  )

plot_2026_rev <- plot_2026_rev %>%
  mutate(Kommentar = paste(plot_management_comments, plot_vegetation_comments, plot_marker_comments, sep = ";"))

plot_2026_rev <- plot_2026_rev %>%
  mutate(
    Ingen = as.integer(str_detect(plot_management_type, "(^|,)Ingen(,|$)")),
    Luking = as.integer(str_detect(plot_management_type, "(^|,)Luking(,|$)")),
    Duk = as.integer(str_detect(plot_management_type, "(^|,)Duk(,|$)")),
    Tilsåing = as.integer(str_detect(plot_management_type, "(^|,)Tilsåing(,|$)")),
    Tilplanting = as.integer(str_detect(plot_management_type, "(^|,)Tilplanting(,|$)")),
    Sprøyting = as.integer(str_detect(plot_management_type, "(^|,)Sprøyting(,|$)")),
    Beiting = as.integer(str_detect(plot_management_type, "(^|,)Beiting(,|$)")),
    Fjerning_vegetasjonsmatter = as.integer(
      str_detect(plot_management_type, "(^|,)Fjerning_vegetasjonsmatter(,|$)")
    )
  )

plot_2026_rev <- plot_2026_rev %>%
  rename(
    Plot.canvas = Duk,
    Plot.herbicide = Sprøyting,
    #Plot.shrub.clearing = Krattrydding,
    Plot.grazing = Beiting,
    Plot.weeding = Luking,
    Plot.revegetation = Tilplanting,
    Plot.seeding = Tilsåing,
    Plot.vegetation_removal = Fjerning_vegetasjonsmatter
  )

# B8 is repeated in the dataset
plot_2026_rev <- plot_2026_rev %>%
  filter(parentglobalid != "{008E1AD5-1FBA-470D-91AB-884C0778811E}")

## for Fyrsteila, treatment "Luking" is actually "Fjerning_vegetasjonsmatter"
plot_2026_rev <- plot_2026_rev %>%
  mutate(
    change_weeding = Lokalitet == "Fyrsteila" & Plot.weeding == 1,
    Plot.weeding = if_else(change_weeding, 0, Plot.weeding),
    Plot.vegetation_removal = if_else(
      change_weeding,
      1,
      Plot.vegetation_removal
    )
  ) %>%
  select(-change_weeding)

## Also: SR treatment includes both herbicides, and removal of litter by raking
plot_2026_rev <- plot_2026_rev %>%
  mutate(
    Plot.litter_removal = if_else(
      Lokalitet == "Fyrsteila" & str_starts(Rute, "SR"),
      1,
      0
    )
  )

# for plots with Plot_canvas, include cover
plot_2026_rev <- plot_2026_rev %>%
  mutate(
    Plot.canvas = if_else(
      Plot.canvas == 1,
      plot_management_cover,
      Plot.canvas
    )
  )

# including the variables Tid og Tid_num
plot_2026_rev <- plot_2026_rev %>%
  mutate(
    Tid = case_when(
      Lokalitet == "Bleikøya" ~ "Etter5",
      Lokalitet == "Husbergøya" ~ "Etter3",
      Lokalitet == "Malmøya" ~ "Etter4",
      Lokalitet == "Nakholmen" ~ "Etter3",
      Lokalitet == "Padda" ~ "Etter6",
      Lokalitet == "Torvøya" ~ "Etter6",
      Lokalitet == "Fyrsteila" ~ "Etter2"
      
    ),
    Tid_num = case_when(
      Lokalitet == "Bleikøya" ~ 5,
      Lokalitet == "Husbergøya" ~ 3,
      Lokalitet == "Malmøya" ~ 4,
      Lokalitet == "Nakholmen" ~ 3,
      Lokalitet == "Padda" ~ 6,
      Lokalitet == "Torvøya" ~ 6,
      Lokalitet == "Fyrsteila" ~ 2
    )
  )

plot_2026_rev <- plot_2026_rev %>%
  mutate(Dato = as.Date(Dato, format = "%Y%m%d"))

## including plot size, and cleaning the columns where plot analyses been carried out
plot_2026_rev <- plot_2026_rev %>%
  rename(Plot_size = main_plot_size,
         Plot_analyses = plot_route_analyses) %>%
  mutate(
    Plot_analyses = if_else(
      Lokalitet == "Fyrsteila",
      "Yes",
      "No"
    )
  )

## keeping only the columns I need for the data
plot_2026_rev2 <- plot_2026_rev %>%
  select(-c(parentglobalid,year,month,day,main_time_start,main_time_end,main_comments,
            weather,longitude,latitude,plot_marker_comments,plot_gps_type,plot_gps_precision,plot_management_cover,
            plot_management_comments,plot_vegetation_comments,plot_cover_total,
            hovedtype_1m2,ke_beskrivelse_1m2,description_nature_type,nr_species)
       
  )


### Fyrsteila-dataset from 2025 ###

# Kobling mellom plotnummer i 2025-fila og riktig Rute
rute_lookup_2025 <- tibble(
  Plot = 1:44,
  Rute = c(
    paste0("D1_", 1:4),
    paste0("LS_", 1:8),
    paste0("L_", 1:8),
    paste0("S_", 1:8),
    paste0("SR_", 1:8),
    paste0("C_", 1:8)
  )
)

# Les inn miljø-/plotdata
Fyrsteila_plot_2025 <- read_excel(
  fil,
  sheet = "Env.var"
) %>%
  left_join(rute_lookup_2025, by = "Plot") %>%
  mutate(
    Lokalitet = "Fyrsteila"
  ) %>%
  select(
    Lokalitet,
    Rute,
    everything(),
    -Plot
  )

Fyrsteila_plot_2025 <- Fyrsteila_plot_2025 %>%
  rename(
    Bryophytes = `Moss cover`,
    Lichens = `Lichen cover`,
    Gravel.stone = `Stone Gravel`,
    Dead.organic.matter = Litter,
    Aspect_favourability = `Aspect Favourability`,
    Soil_depth_average = `Soil Depth Average`,
    Min_soil_depth = `Min Soil Depth`,
    Max_soil_depth = `Max Soil Depth`,
    Median_soil_depth = `Median Soil depth`
  )

Fyrsteila_plot_2025 <- Fyrsteila_plot_2025 %>%
  mutate(
    Tid_num = 1,
    Tid = "Etter1",
    Registrant = "MR",
    Dato = as.Date("2025-07-18"),
    
    Plot.canvas = if_else(
      str_starts(Rute, "D"),
      100,
      0
    ),
    
    Plot.herbicide = if_else(
      str_detect(Rute, "S"),
      1,
      0
    ),
    
    Plot.vegetation_removal = if_else(
      str_detect(Rute, "L"),
      1,
      0
    ),
    
    Plot.litter_removal = if_else(
      str_detect(Rute, "R"),
      1,
      0
    ),
    
    Plot.revegetation = if_else(
      Tuft == 1,
      1,
      0
    ),
    
    Plot.seeding = if_else(
      Seeds == 1,
      1,
      0
    ),
    
    Plot_size = "50 x 50",
    Plot_analyses = "Yes"
  )

Fyrsteila_plot_2025 <- Fyrsteila_plot_2025 %>%
  select(-c(`Removal treatment`,`Reveg treatment`,Tuft,Seeds)
  )


### old dataset from 2022-25 ###
plot_2022_25 <- plot_2022_25 %>% mutate(Dato = as.Date(Dato))

# cleaning plot_2022_25, including plot size and only keeping rows where plots were analysed
plot_2022_25 <- plot_2022_25 %>%
  mutate(Plot_size = "50x50")
plot_2022_25 <- plot_2022_25 %>%
  mutate(
    Plot_analyses = if_else(
      if_any(
        c(
          Field.layer,
          Bryophytes,
          Lichens,
          Dead.organic.matter,
          Gravel.stone,
          Mineralsoil,
          Mineralsoil.gravel.stone
        ),
        ~ !is.na(.)
      ),
      "Yes",
      "No"
    )
  )
plot_2022_25 <- plot_2022_25 %>%
  mutate(
    Plot_analyses = case_when(
      Rute %in% c("B5", "B2", "B9", "B7") & Tid == "Etter4" ~ "Yes",
      Rute == "N7" & Tid == "Etter2" ~ "Yes",
      TRUE ~ Plot_analyses
    )
  )


### merging the three files into one ###
GRUK_plot_22_26 <- bind_rows(plot_2022_25, plot_2026_rev2,Fyrsteila_plot_2025) 

## including only rows/plots where plot analyses were carried out
GRUK_plot_22_26 <- GRUK_plot_22_26 %>%
  filter(Plot_analyses == "Yes")


#### ---- Species in plots data ---- #### 

# in the 2026-data, creating variable names that correspond to existing dataset
plotspecies_2026 <- plotspecies_2026 %>%
  rename(
    Dato = event_time,
    Lokalitet = main_location_id,
    Rute = main_plot_id,
    Registrant = main_observant_name,
    Latinsk_navn = plot_species,
    Dekning = plot_cover_species,
    Kommentar = plot_species_comments
  )

plotspecies_2026 <- plotspecies_2026 %>%
  mutate(Dekning = Dekning*100)

plotspecies_2026 <- plotspecies_2026 %>% 
  mutate(Dato = as.Date(Dato, format = "%Y%m%d"))

# including the variables Tid og Tid_num
plotspecies_2026 <- plotspecies_2026 %>%
  mutate(
    Tid = case_when(
      Lokalitet == "Bleikøya" ~ "Etter5",
      Lokalitet == "Husbergøya" ~ "Etter3",
      Lokalitet == "Malmøya" ~ "Etter4",
      Lokalitet == "Nakholmen" ~ "Etter3",
      Lokalitet == "Padda" ~ "Etter6",
      Lokalitet == "Torvøya" ~ "Etter6",
      Lokalitet == "Fyrsteila" ~ "Etter2"
      
    ),
    Tid_num = case_when(
      Lokalitet == "Bleikøya" ~ 5,
      Lokalitet == "Husbergøya" ~ 3,
      Lokalitet == "Malmøya" ~ 4,
      Lokalitet == "Nakholmen" ~ 3,
      Lokalitet == "Padda" ~ 6,
      Lokalitet == "Torvøya" ~ 6,
      Lokalitet == "Fyrsteila" ~ 2
    )
  )

### Including Fyrsteila data from 2025 ###

# Artsliste
species_list <- read_excel(
  fil,
  sheet = "Species_list"
)

# Dekning
fyrsteila_cover <- read_excel(
  fil,
  sheet = "Species percent"
) %>%
  mutate(plot_nr = row_number()) %>%
  pivot_longer(
    cols = -plot_nr,
    names_to = "Species_short",
    values_to = "Dekning"
  )

# Smårutefrekvens
fyrsteila_freq <- read_excel(
  fil,
  sheet = "Species presence absence"
) %>%
  mutate(plot_nr = row_number()) %>%
  pivot_longer(
    cols = -plot_nr,
    names_to = "Species_short",
    values_to = "Sub_plot_fq"
  )

# Slå sammen
Fyrsteila_species_2025 <- fyrsteila_cover %>%
  left_join(
    fyrsteila_freq,
    by = c("plot_nr", "Species_short")
  ) %>%
  left_join(
    species_list,
    by = "Species_short"
  ) %>%
  mutate(
    Lokalitet = "Fyrsteila"
  ) %>%
  select(
    Lokalitet,
    plot_nr,
    Latinsk_navn,
    Dekning,
    Sub_plot_fq
  )

Fyrsteila_species_2025 <- Fyrsteila_species_2025 %>%
  filter(Dekning > 0 | Sub_plot_fq > 0)

rute_lookup_2025 <- tibble(
  plot_nr = 1:44,
  Rute = c(
    paste0("D1_", 1:4),
    paste0("LS_", 1:8),
    paste0("L_", 1:8),
    paste0("S_", 1:8),
    paste0("SR_", 1:8),
    paste0("C_", 1:8)
  )
)

Fyrsteila_species_2025 <- Fyrsteila_species_2025 %>%
  left_join(rute_lookup_2025, by = "plot_nr") %>%
  select(
    Lokalitet,
    Rute,
    Latinsk_navn,
    Dekning,
    Sub_plot_fq
  )

Fyrsteila_species_2025 <- Fyrsteila_species_2025 %>%
  mutate(
    Tid_num = 1,
    Tid = "Etter1",
    Registrant = "MR",
    Dato = as.Date("2025-07-18")
  )


### 
plotspecies_2022_25 <- plotspecies_2022_25 %>%
  select(c(
    Lokalitet,
    Rute,
    Tid_num,
    Tid,
    Registrant,
    Dato,
    Latinsk_navn,
    Dekning,
    Kommentar)
  )

### old dataset from 2022-25 ###
plotspecies_2022_25 <- plotspecies_2022_25 %>% mutate(Dato = as.Date(Dato))

### merging the three files into one
GRUK_plotspecies_22_26 <- bind_rows(plotspecies_2022_25, plotspecies_2026,Fyrsteila_species_2025) 

## removing plots with no data (dummy = Abies, or no data)
GRUK_plotspecies_22_26 <- GRUK_plotspecies_22_26 %>% 
  filter(!is.na(Latinsk_navn) & !Latinsk_navn %in% "Abies")

## making a draft file for checking species names in an easier way (for me at least)
write.csv(GRUK_plotspecies_22_26,
          file = here::here("data", "mitt_datasett.csv"), 
          row.names = FALSE)


## revising species names to ensure that all observations of a given taxon are recorded at the same taxonomic level
GRUK_plotspecies_22_26 <- GRUK_plotspecies_22_26 %>%
  mutate(Latinsk_navn = case_when(
    Latinsk_navn == "Anthyllis_vulneraria_vulneraria" ~ "Anthyllis_vulneraria_subsp._vulneraria",
    Latinsk_navn ==  "Arenaria_serpyllifolia_serpyllifolia" ~ "Arenaria_serpyllifolia_subsp._serpyllifolia",
    Latinsk_navn == "Campanula_rotundifolia" ~ "Campanula_rotundifolia_subsp._rotundifolia",
    Latinsk_navn == "Campanula_rotundifolia_rotundifolia" ~ "Campanula_rotundifolia_subsp._rotundifolia",
    Latinsk_navn == "Convolvulus_arvense" ~ "Convolvulus_arvensis",
    Latinsk_navn ==  "Lotus_corniculatus_corniculatus" ~ "Lotus_corniculatus_var._corniculatus",
    Latinsk_navn == "Poa" ~ "Poa_sp.",
    Latinsk_navn == "Potentilla_argentea" & Lokalitet == "Fyrsteila" ~ "Potentilla_neglecta",
    Latinsk_navn == "Rosa" ~ "Rosa_sp.",
    Latinsk_navn == "Rosa_mollis" ~ "Rosa_sp.",
   
    TRUE ~ Latinsk_navn
    
  ))

## revising given observations in plots to ensure that the time series is consistent
## for plots where both Potentilla neglecta and P. argentea are observed, I change to Potentilla_neglecta
## for plots where both Fragaria vesca and F.viridis are observed, I change to viridis
## for Hieracium, I think the option of murorum_agg was not there in all versions of the app

# This is not repeated for 2026-data, because it's already completed in the importet plotspecies_2022-25
# In the script above it is done for Fyrsteil, for Potentilla argentaa/neglecta. 

# GRUK_plotspecies <- GRUK_plotspecies %>%
#   mutate(Latinsk_navn = case_when(
#     Rute == "P1" & Latinsk_navn == "Prunus_sp." ~ "Prunus_cerasus",
#     Rute == "3-3a-3" & Latinsk_navn == "Potentilla_argentea" ~ "Potentilla_neglecta",
#     Rute == "3-3a-3" & Dekning =="40" & Latinsk_navn == "Sedum_album" ~ "Sedum_acre", # Sedum album recorded twice, and Secum acre recorded the next time with high abundance. Also checked photos to confirm that S. acre is right
#     Rute == "3-3b-15" & Latinsk_navn == "Allium_vineale" ~ "Allium_oleraceum",
#     Rute == "3-3b-4" & Latinsk_navn == "Allium_vineale" ~ "Allium_oleraceum",
#     Rute == "3-3b-5" & Latinsk_navn == "Fragaria_vesca" ~ "Fragaria_viridis",
#     Rute == "3-3b-8" & Latinsk_navn == "Fragaria_vesca" ~ "Fragaria_viridis",
#     Rute == "B8" & Latinsk_navn == "Fragaria_vesca" ~ "Fragaria_viridis",
#     Rute == "M1" & Latinsk_navn == "Fragaria_vesca" ~ "Fragaria_viridis",
#     Rute == "M6" & Latinsk_navn == "Potentilla_argentea" ~ "Potentilla_neglecta",
#     Rute == "N3" & Latinsk_navn == "Potentilla_argentea" ~ "Potentilla_neglecta",
#     Rute == "N5" & Latinsk_navn == "Potentilla_argentea" ~ "Potentilla_neglecta",
#     Rute == "P10" & Latinsk_navn == "Hieracium_sp." ~ "Hieracium_murorum_agg.",
#     Rute == "P15" & Latinsk_navn == "Hieracium_sp." ~ "Hieracium_murorum_agg.",
#     Rute == "P4" & Latinsk_navn == "Hieracium_sp." ~ "Hieracium_murorum_agg.",
#     Rute == "P5" & Latinsk_navn == "Hieracium_sp." ~ "Hieracium_murorum_agg.",
#     Rute == "TN5" & Latinsk_navn == "Potentilla_argentea" ~ "Potentilla_neglecta",
#     
#     TRUE ~ Latinsk_navn
#     
#   ))



#### ---- Circle data ---- ####

# creating variable names that correspond to existing dataset
circle_2026_rev <- circle_2026 %>%
  rename(
    Dato = event_time,
    Lokalitet = main_location_id,
    Rute = main_plot_id,
    Registrant = main_observant_name,
    Circle.mapping.unit = circle_nature_type,
    Circle.woody.field.layer = circle_cover_lowwoody,
    Circle.shrub.layer = circle_cover_shrubs,
    Circle.tree.layer = circle_cover_trees,
    Circle.invasive.species = circle_cover_alien_total,
    Circle.problematic.species = circle_cover_problematic_total,
    Circle.erosion = circle_cover_erosion,
    Circle.vehicle.tracks = circle_cover_vehicletracks,
    Circle.exposed.rock = circle_cover_bedrock,
    Circle.human.objects = circle_humanobjects,
    Comments = circle_management_comments
  )

circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Ingen = as.integer(str_detect(circle_management_type, "(^|,)Ingen(,|$)")),
    Luking = as.integer(str_detect(circle_management_type, "(^|,)Luking(,|$)")),
    Duk = as.integer(str_detect(circle_management_type, "(^|,)Duk(,|$)")),
    Krattrydding = as.integer(str_detect(circle_management_type, "(^|,)Krattrydding(,|$)")),
    Tilsåing = as.integer(str_detect(circle_management_type, "(^|,)Tilsåing(,|$)")),
    Tilplanting = as.integer(str_detect(circle_management_type, "(^|,)Tilplanting(,|$)")),
    Sprøyting = as.integer(str_detect(circle_management_type, "(^|,)Sprøyting(,|$)")),
    Beiting = as.integer(str_detect(circle_management_type, "(^|,)Beiting(,|$)")),
    Fjerning_vegetasjonsmatter = as.integer(
      str_detect(circle_management_type, "(^|,)Fjerning_vegetasjonsmatter(,|$)")
    )
  )

circle_2026_rev <- circle_2026_rev %>%
  rename(
    Circle.canvas = Duk,
    Circle.herbicide = Sprøyting,
    Circle.shrub.clearing = Krattrydding,
    Circle.grazing = Beiting,
    Circle.weeding = Luking,
    Circle.revegetation = Tilplanting,
    Circle.seeding = Tilsåing,
    Circle.vegetation_removal = Fjerning_vegetasjonsmatter
  )

# I don't know if there is another way than going through comments to assign values for Circle.canvas
# for the other management types, we use only 0/1
circle_2026_rev <- circle_2026_rev %>%
  mutate(Circle.canvas = case_when(
    Rute == "M3" & Circle.canvas == 1 ~ 25,
    Rute == "M4" & Circle.canvas == 1 ~ 10,
    Rute == "N2" & Circle.canvas == 1 ~ 1,
    Rute == "N11" & Circle.canvas == 1 ~ 55,
    Rute == "N12" & Circle.canvas == 1 ~ 70,
    Rute == "N6" & Circle.canvas == 1 ~ 10,
    Rute == "N7" & Circle.canvas == 1 ~ 15,
    Rute == "N6" & Circle.canvas == 1 ~ 10,
    TRUE ~ Circle.canvas))

# also, I need to include all the comments that we got afterwards on management actions, see file Notater fra felt_docx on Sharepoint. 
# Bleikøya: Rutene B1, B2, B3 og B4 har tilsåing i tillegg til luking og fjerning av vegetasjonsmatter
circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Circle.seeding = case_when(
      Rute %in% c("B1", "B2", "B3", "B4") ~ 1,
      TRUE ~ Circle.seeding
    )
  )

# also, B8 is repeated in the dataset
circle_2026_rev <- circle_2026_rev %>%
  filter(parentglobalid != "{008E1AD5-1FBA-470D-91AB-884C0778811E}")


# Nakholmen: N7 change revegetation to seeding
circle_2026_rev <- circle_2026_rev %>%
  mutate(
    change_seeding = Lokalitet == "Nakholmen" & Circle.revegetation == 1,
    Circle.revegetation = if_else(change_seeding, 0, Circle.revegetation),
    Circle.seeding = if_else(
      change_seeding,
      1,
      Circle.seeding
    )
  ) %>%
  select(-change_seeding)

# Luking av stankstorkenebb der presenningen er fjernet, N7 og N6
# Generell luking ellers, men vi ser ikke det i særlig grad? Ettersom det er gjennomført luking, skriver jeg luking = 1 på alle
circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Circle.weeding = case_when(
      Lokalitet == "Nakholmen" ~ 1,
      TRUE ~ Circle.weeding
    )
  )

# Husbergøya, noe krattrydding etter feltarbeidet i 2025, noe luking i 2026
# Vi har ikke notert spor etter nyere krattrydding i våre data, utelater derfor det. 

# Padda
# Gjennomført luking i området med rutene 1-6
# Arbeidet med å fjerne oppslag av kratt ikke gjennomført før feltarbeidet
circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Circle.weeding = case_when(
      Rute %in% c("P1", "P2", "P3", "P4", "P5", "P6") ~ 1,
      TRUE ~ Circle.weeding
    )
  )

# Malmøya
# Luking gjennomført over hele lokaliteten utover høsten 2025, og også i løpet av sommeren 2026, alle ruter
# Noe krattrydding høst 2025, men oppslag av kratt er ikke ryddet i 2026. Stoler på våre notater på krattrydding 
# I tillegg til duk er området nord for duken sprøytet, det omfatter rute 3, 4, 5 og 6
circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Circle.weeding = case_when(
      Lokalitet == "Malmøya" ~ 1,
      TRUE ~ Circle.weeding
    )
  )

circle_2026_rev <- circle_2026_rev %>%
  mutate(
    Circle.herbicide = case_when(
      Rute %in% c("M3", "M4", "M5", "M6") ~ 1,
      TRUE ~ Circle.herbicide
    )
  )


## including variables Tid and Tid_num
circle_2026_rev <- circle_2026_rev %>%
  mutate( Tid = case_when(
    Lokalitet == "Bleikøya" ~ "Etter5",
    Lokalitet == "Husbergøya" ~ "Etter3",
    Lokalitet == "Malmøya" ~ "Etter4",
    Lokalitet == "Nakholmen" ~ "Etter3",
    Lokalitet == "Padda" ~ "Etter6",
    Lokalitet == "Torvøya" ~ "Etter6",
    Lokalitet == "Fyrsteila" ~ "Etter2"
    
  ),
  Tid_num = case_when(
    Lokalitet == "Bleikøya" ~ 5,
    Lokalitet == "Husbergøya" ~ 3,
    Lokalitet == "Malmøya" ~ 4,
    Lokalitet == "Nakholmen" ~ 3,
    Lokalitet == "Padda" ~ 6,
    Lokalitet == "Torvøya" ~ 6,
    Lokalitet == "Fyrsteila" ~ 2
    
  )
  )

## keeping only the columns I need for the data
circle_2026_rev2 <- circle_2026_rev %>%
  select(c(Lokalitet,Dato,Rute,Tid,Tid_num,Registrant,Circle.mapping.unit, Circle.woody.field.layer,Circle.shrub.layer, 
           Circle.tree.layer,Circle.invasive.species,Circle.problematic.species,Circle.erosion,Circle.vehicle.tracks,Circle.exposed.rock,
           Circle.canvas,Circle.herbicide,Circle.shrub.clearing,Circle.weeding,Circle.grazing,Circle.vegetation_removal,Circle.revegetation,Circle.seeding, Circle.human.objects,
           Comments,circle_comment,
  )
  )


### old data from 2022-25 ###
circle_2022_25 <- circle_2022_25 %>% mutate(Dato = as.Date(Dato))

### merging the two files into one
circle_2026_rev2 <- circle_2026_rev2 %>% 
  mutate(Dato = as.Date(Dato, format = "%Y%m%d"))

GRUK_circle_22_26 <- bind_rows(circle_2022_25, circle_2026_rev2) 

## Removing Fyrsteila from the data, and also
GRUK_circle_22_26 <- GRUK_circle_22_26 %>%
  filter(Lokalitet != "Fyrsteila")


#### ---- Species in circles data ---- #### 

# in the 2026-data, creating variable names that correspond to existing dataset
circlespecies_2026 <- circlespecies_2026 %>%
  rename(
    Dato = event_time,
    Lokalitet = main_location_id,
    Rute = main_plot_id,
    Registrant = main_observant_name,
    Latinsk_navn = circle_species
  )

# first rearranging and fixing problematic species
abies_rows <- circlespecies_2026 %>%
  filter(Latinsk_navn == "Abies_balsamea") %>%
  mutate(species_entry = circle_species_comments) %>%
  separate_rows(species_entry, sep = ",") %>%
  mutate(
    species_entry = str_trim(species_entry),
    
    # Hent dekning hvis det finnes et tall på slutten
    abundance_new = str_extract(
      species_entry,
      "\\d+(?:[\\.,]\\d+)?$"
    ),
    
    abundance_new = as.numeric(
      str_replace(abundance_new, ",", ".")
    ),
    
    # Hent artsnavnet uten eventuell dekning
    species_common = str_trim(
      str_remove(
        species_entry,
        "\\s+\\d+(?:[\\.,]\\d+)?$"
      )
    )
  )

abies_rows %>%
  select(Lokalitet, Rute, species_entry, species_common, abundance_new)

abies_rows <- abies_rows %>%
  filter(
    !(Latinsk_navn == "Abies_balsamea" &
        (is.na(species_entry) | trimws(species_entry) == ""))
  )

abies_rows %>%
  count(species_common, sort = TRUE)

circlespecies_2026 <- circlespecies_2026 %>%
  filter(Latinsk_navn != "Abies_balsamea" | is.na(Latinsk_navn)) %>%
  bind_rows(abies_rows)

circlespecies_2026 <- circlespecies_2026 %>%
  mutate(
    Latinsk_navn = if_else(
      Latinsk_navn == "Abies_balsamea",
      species_common,
      Latinsk_navn
    )
  )

# oppdaterer datasettet
circlespecies_2026_clean <- circlespecies_2026 %>%
  mutate(
    Dekning = case_when(
      !is.na(abundance_new) ~ abundance_new,
      
      str_detect(
        str_trim(circle_species_comments),
        "^\\d+(?:[\\.,]\\d+)?$"
      ) ~ as.numeric(
        str_replace(
          str_trim(circle_species_comments),
          ",",
          "."
        )
      ),
      
      TRUE ~ NA_real_
    )
  )

# changing misidentified åkervindel
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  mutate(
    Latinsk_navn = case_when(
      Latinsk_navn == "åkervindel" ~ "vindelslirekne",
      TRUE ~ Latinsk_navn
    )
  )

# including cover from the circle_2026 file
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  left_join(
    circle_2026_rev2 %>%
      select(
        Rute,
        Circle.invasive.species,
        Circle.problematic.species
      ),
    by = "Rute"
  ) %>%
  mutate(
    Dekning = case_when(
      !is.na(Dekning) ~ Dekning,
      
      circle_species_type == "alien" ~ Circle.invasive.species,
      
      circle_species_type == "problematic" ~ Circle.problematic.species,
      
      TRUE ~ Dekning
    )
  )

# I also need to replace norwegian names with latin. 
library(dplyr)
library(stringr)
library(readr)

# 1. LAST NED NORTAXA
download.file(
  "https://ipt.artsdatabanken.no/archive.do?r=artsnavnebase",
  destfile = "nortaxa.zip",
  mode = "wb"
)

# Pakk ut filene
unzip("nortaxa.zip", exdir = "nortaxa")

# Se hvilke filer som ble pakket ut
list.files("nortaxa")

# 2. LES INN TAXON- OG VERNACULAR-FILENE
taxon <- read_tsv(
  "nortaxa/taxon.txt",
  show_col_types = FALSE
)

vernacular <- read_tsv(
  "nortaxa/vernacularname.txt",
  show_col_types = FALSE
)

# 3. OPPSLAG FOR VITENSKAPELIGE NAVN
latin_lookup <- taxon %>%
  select(
    taxonID,
    acceptedNameUsageID,
    scientificName,
    taxonomicStatus
  ) %>%
  left_join(
    taxon %>%
      select(
        acceptedNameUsageID = taxonID,
        accepted_scientificName = scientificName
      ),
    by = "acceptedNameUsageID"
  ) %>%
  mutate(
    Vitenskapelig_navn = coalesce(
      accepted_scientificName,
      scientificName
    ),
    navn_sok = scientificName %>%
      str_replace_all("_", " ") %>%
      str_squish() %>%
      str_to_lower()
  ) %>%
  select(
    navn_sok,
    Vitenskapelig_navn,
    taxonomicStatus
  ) %>%
  distinct(navn_sok, .keep_all = TRUE)

# 4. OPPSLAG FOR NORSKE NAVN
norwegian_lookup <- vernacular %>%
  left_join(
    taxon %>%
      select(
        id,
        taxonID,
        acceptedNameUsageID,
        scientificName
      ),
    by = "id"
  ) %>%
  left_join(
    taxon %>%
      select(
        acceptedNameUsageID = taxonID,
        accepted_scientificName = scientificName
      ),
    by = "acceptedNameUsageID"
  ) %>%
  mutate(
    Vitenskapelig_navn = coalesce(
      accepted_scientificName,
      scientificName
    ),
    navn_sok = vernacularName %>%
      str_squish() %>%
      str_to_lower()
  ) %>%
  transmute(
    navn_sok,
    Vitenskapelig_navn,
    language,
    isPreferredName
  )

# 5. ETT TREFF PER NORSK NAVN
norwegian_lookup <- norwegian_lookup %>%
  arrange(desc(isPreferredName)) %>%
  distinct(navn_sok, .keep_all = TRUE)

# 6. NAVN FRA DITT DATASSETT
artsnavn <- circlespecies_2026_clean %>%
  distinct(Latinsk_navn) %>%
  filter(
    !is.na(Latinsk_navn),
    Latinsk_navn != ""
  ) %>%
  mutate(
    navn_sok = Latinsk_navn %>%
      str_replace_all("_", " ") %>%
      str_squish() %>%
      str_to_lower()
  )

# 7. MATCH NAVNENE
artsnavn_matchet <- artsnavn %>%
  left_join(
    latin_lookup %>%
      select(
        navn_sok,
        latin_treff = Vitenskapelig_navn
      ),
    by = "navn_sok"
  ) %>%
  left_join(
    norwegian_lookup %>%
      select(
        navn_sok,
        norsk_treff = Vitenskapelig_navn
      ),
    by = "navn_sok"
  ) %>%
  mutate(
    Vitenskapelig_navn = coalesce(
      latin_treff,
      norsk_treff
    )
  )

# Antall navn uten treff
artsnavn_matchet %>%
  summarise(
    antall_navn = n(),
    uten_treff = sum(is.na(Vitenskapelig_navn))
  )
artsnavn_matchet %>%
  filter(is.na(Vitenskapelig_navn)) %>%
  select(Latinsk_navn)

# 7B. MANUELLE KORREKSJONER
manuell_lookup <- tribble(
  ~Latinsk_navn,                         ~Vitenskapelig_navn_manuell,
  "Mjølke sp.",                          "Epilobium sp.",
  "mjølke sp.",                          "Epilobium sp.",
  "mjølke",                              "Epilobium sp.",
  "Mjølke",                              "Epilobium sp.",
  "Mjølke sp",                           "Epilobium sp.",
  "svineblom sp",                        "Senecio sp.",
  "Allium_schoenoprasum_schoenoprasum", "Allium schoenoprasum subsp. schoenoprasum",
  "krattumleblom", "Geum urbanum",
  "Vindesvinerot", "Fallopia convolvulus"
)

artsnavn_matchet <- artsnavn_matchet %>%
  left_join(
    manuell_lookup,
    by = "Latinsk_navn"
  ) %>%
  mutate(
    Vitenskapelig_navn = coalesce(
      Vitenskapelig_navn,
      Vitenskapelig_navn_manuell
    )
  ) %>%
  select(-Vitenskapelig_navn_manuell)

# kontroller om det fortsatt er arter uten vitenskapelig navn
artsnavn_matchet %>%
  filter(is.na(Vitenskapelig_navn)) %>%
  select(Latinsk_navn)

# 8. KOBLE RESULTATET TILBAKE TIL circlespecies_2026_clean
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  left_join(
    artsnavn_matchet %>%
      select(
        Latinsk_navn,
        Vitenskapelig_navn
      ),
    by = "Latinsk_navn"
  )

# 9. LAG NY KOLONNE MED KUN VITENSKAPELIGE NAVN
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  mutate(
    Latinsk_navn_ny = coalesce(
      Vitenskapelig_navn,
      Latinsk_navn
    )
  )

# 10. GJØR MELLOMROM OM TIL UNDERSTREK IGJEN
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  mutate(
    Latinsk_navn_ny = str_replace_all(
      Latinsk_navn_ny,
      " ",
      "_"
    )
  )

# 11. KONTROLLER GAMMELT MOT NYTT NAVN
circlespecies_2026_clean %>%
  distinct(
    Latinsk_navn,
    Latinsk_navn_ny
  ) %>%
  arrange(Latinsk_navn) %>%
  View()



## including variables Tid and Tid_num
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  mutate(
    Tid = case_when(
      Lokalitet == "Bleikøya" ~ "Etter5",
      Lokalitet == "Husbergøya" ~ "Etter3",
      Lokalitet == "Malmøya" ~ "Etter4",
      Lokalitet == "Nakholmen" ~ "Etter3",
      Lokalitet == "Padda" ~ "Etter6",
      Lokalitet == "Torvøya" ~ "Etter6",
      Lokalitet == "Fyrsteila" ~ "Etter2"
      
    ),
    Tid_num = case_when(
      Lokalitet == "Bleikøya" ~ 5,
      Lokalitet == "Husbergøya" ~ 3,
      Lokalitet == "Malmøya" ~ 4,
      Lokalitet == "Nakholmen" ~ 3,
      Lokalitet == "Padda" ~ 6,
      Lokalitet == "Torvøya" ~ 6,
      Lokalitet == "Fyrsteila" ~ 2
    )
  )

### fixing formatting stuff before merging
circlespecies_2026_clean <- circlespecies_2026_clean %>% 
  mutate(Dato = as.Date(Dato, format = "%Y%m%d"))
circlespecies_2026_clean <- circlespecies_2026_clean %>%
  select(-Latinsk_navn) %>%
  rename(
    Latinsk_navn = Latinsk_navn_ny
  )

circlespecies_2026_clean2 <- circlespecies_2026_clean %>%
  select(c(Lokalitet,Rute,Tid_num,Tid,Registrant,Dato,Latinsk_navn,Dekning))

### old data from 2022-25

circlespecies_2022_25 <- circlespecies_2022_25 %>% 
  mutate(Dato = as.Date(Dato))

circlespecies_2022_25 <- circlespecies_2022_25 %>%
  select(c(Lokalitet,Rute,Tid_num,Tid,Registrant,Dato,Latinsk_navn,Dekning))

GRUK_circlespecies_22_26 <- bind_rows(circlespecies_2022_25, circlespecies_2026_clean2) 

## making a draft file for checking species names in an easier way (for me at least)
write.csv(GRUK_circlespecies_22_26, 
          file = here("data", "sirkelarterkladd.csv"),
          row.names = FALSE)

## correcting stuff
GRUK_circlespecies_22_26 <- GRUK_circlespecies_22_26 %>% 
  filter(!is.na(Latinsk_navn) & !Latinsk_navn %in% "Abies_balsamea")
GRUK_circlespecies_22_26 <- GRUK_circlespecies_22_26 %>%
  mutate(Latinsk_navn = case_when(
    Latinsk_navn == "Allium_schoenoprasum_schoenoprasum" ~ "Allium_schoenoprasum_subsp._schoenoprasum",
    Latinsk_navn == "Iris_sp." ~ "Iris_siberica",
    Latinsk_navn ==  "Pastinaca_sativa_hortensis" ~ "Pastinaca_sativa_var._hortensis",
    TRUE ~ Latinsk_navn
  ))


#### ---- Export data as an excel-file ---- ####

# one for the complete dataset

wb <- createWorkbook()

addWorksheet(wb, "plots")
writeData(wb, "plots", GRUK_plot_22_26)

addWorksheet(wb, "species.long")
writeData(wb, "species.long", GRUK_plotspecies_22_26)

addWorksheet(wb, "circles")
writeData(wb, "circles", GRUK_circle_22_26)

addWorksheet(wb, "species.circles")
writeData(wb, "species.circles", GRUK_circlespecies_22_26)

addWorksheet(wb, "GPS")
writeData(wb, "GPS", GPS_GRUK)

openxlsx::saveWorkbook(
  wb,
  file = here::here("data", "GRUK_effekt_data_2026.xlsx"),
  overwrite = TRUE
)

#### ---- Exporting also only new data as an excel-file ---- ####

plots_new_2026 <- bind_rows(plot_2026_rev2,Fyrsteila_plot_2025) 
## including only rows/plots where plot analyses were carried out
plots_new_2026 <- plots_new_2026 %>%
  filter(Plot_analyses == "Yes")
plotspecies_new_2026 <- GRUK_plotspecies_22_26 %>%
  filter(lubridate::year(Dato) == 2026 | Lokalitet == "Fyrsteila")
circle_2026_new <- GRUK_circle_22_26 %>%
  filter(lubridate::year(Dato) == 2026)
circlespecies_2026_new <- GRUK_circlespecies_22_26 %>%
  filter(lubridate::year(Dato) == 2026)



wb <- createWorkbook()

addWorksheet(wb, "plots")
writeData(wb, "plots", plots_new_2026)

addWorksheet(wb, "species.long")
writeData(wb, "species.long", plotspecies_new_2026)

addWorksheet(wb, "circles")
writeData(wb, "circles", circle_2026_new)

addWorksheet(wb, "species.circles")
writeData(wb, "species.circles", circlespecies_2026_new)

addWorksheet(wb, "GPS")
writeData(wb, "GPS", GPS_GRUK)

openxlsx::saveWorkbook(
  wb,
  file = here::here("data", "GRUK_effekt_data_2026_only.xlsx"),
  overwrite = TRUE
)

