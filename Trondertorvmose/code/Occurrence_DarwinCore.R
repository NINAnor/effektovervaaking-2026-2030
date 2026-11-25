#Code to make the file for effektoverv??kning till Darwincore####
#In this script we load the original data, 
#choose the sites from 2026
#calculate frequency for each species
#get a species list to load into navn vask
#We need to load the result from navn vask (name_search_20_11_2026.xlsx)
#We need to also load "Event" which is produced in another sheet
#then we make the OCCURRENCE sheet
#and save both Occurrence and Event into a new excel
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
library(readxl)
library(writexl)
library(dplyr)
library(tidyr)
#Data loading####
dat<-read_excel("C:/Users/fia.bengtsson/OneDrive - NINA/Documents/Effektoverv??kning/Vegetasjonsanalyser_overv??king_data COPY.xlsx", sheet = "2026", .name_repair = "minimal")
names(dat)


# Exclude column B
dat <- dat[, -2]

# Extract plot names from column names
plot_id <- names(dat)[-1]

# Remove the automatic suffixes added by read_excel
plot_id <- sub("\\.\\.\\.[0-9]+$", "", plot_id)

# Define plots to keep
keep_plots <- c(
  "Kors_1", "Kors_2",
  "Kal_1", "Kal_2", "Kal_3", "Kal_4",
  "Hen_1", "Hen_2", "Hen_3", "Hen_4"
)

# Find matching column positions
keep_cols <- which(plot_id %in% keep_plots)

# Check what was found
#print(unique(plot_id))
#print(keep_cols)
#print(unique(plot_id[keep_cols]))

#This can be saved if we want to look at subplot data for those plots (2026)
# Keep column A and matching columns
dat <- dat[, c(1, keep_cols + 1)]

plot_id <- plot_id[keep_cols]


## Extract subplot numbers
subplot <- as.numeric(unlist(dat[1, -1]))

# Remove first row (subplot numbers)
dat_species <- dat[-1, ]

names(dat_species)<- c("Art", plot_id)

#Calculate frequency#### 
#(now i kept only Plot_id and species data!)
# Convert to long format
dat_long <- dat_species %>%
  pivot_longer(
    cols = -Art,
    names_to = "Felt_rute",
    values_to = "Presence"
  ) %>%
  mutate(Presence = ifelse(is.na(Presence), 0, 1))

# Calculate frequency per species and Felt_rute
Frekvens <- dat_long %>%
  group_by(Art, Felt_rute) %>%
  summarise(
    Frekvens = sum(Presence) / 16 * 100,
    .groups = "drop"
  )
write_xlsx(Frekvens, "Frekvens_2026.xlsx")

#Make a species name list that can be pasted into NAVNEVASK####
# Extract unique species names
species_names <- unique(Frekvens$Art)

# Copy to clipboard
#install.packages("clipr")  # Only needed once
#clipr::write_clip(species_names)

#For the sheet occurrence####
#Now the names need be fixed up#
#str(Frekvens)
#loading the datavask file I got from artsdatabanken based on the 
#species in Frekvens
namefix<-read_excel("C:/Users/fia.bengtsson/OneDrive - NINA/Documents/Effektoverv??kning/name_search_20_11_2026.xlsx")
#Joining frekvens with datavask based on Art and Input should be the same
#Frekvens now has all the taxonomic info
Frekvens <- Frekvens %>%
  left_join(namefix, by = c("Art" = "Input"))

#Making the new df 
Event <- read_excel("Event.xlsx", sheet = "Event")

#The columns and the stuff we use Frekvens for
Occurrence <- Frekvens %>%
  transmute(
    Felt_rute,#just temporary
    eventID = NA_character_,
    basisOfRecord = "HumanObservation",
    occurrenceRemarks = "PlotData",
    recordNumber = NA_character_,
    recordedBy = NA_character_,
    individualCount = NA_real_,
    organismQuantity = Frekvens,
    organismQuantityType = "Frequency in 50x50 centimeter square (of occupied subplots out of 16)",
    sex = NA_character_,
    lifeStage = NA_character_,
    establishmentMeans = NA_character_,
    occurrenceStatus = NA_character_,
    preparations = NA_character_,
    organismRemarks = NA_character_,
    identifiedBy = NA_character_,
    dateIdentified = NA_character_,
    identificationRemarks = NA_character_,
    typeStatus = NA_character_,
    identificationQualifier =  NA_character_,
    scientificName = ScientificName,
    LatinskNavnID = ScientificNameId,
    kingdom = Kingdom,
    phylum = Phylum,
    class = Class,
    order = Order,
    family = Family,
    genus = Genus,
    specificEpithet = SpecificEpithet,
    subspecies = NA_character_,
    scientificNameAuthorship = ScientificNameAuthorship,
    vernacularName = VernacularNameBokmaal,
    taxonRemarks = NA_character_,
    associatedMedia = NA_character_
  )
#Populate eventID
Occurrence <- Occurrence %>%
  select(-eventID) %>%
  left_join(
    Event %>% select(locationID, eventID),
    by = c("Felt_rute" = "locationID")
  )


# Join information from Lokaliteter

#Ladda lokaliteter i r-fil Event_DarwinCore.R#

Occurrence <- Occurrence %>%
  left_join(
    Lokaliteter %>%
      select(
        Rute_kode,
        recordedBy_new = `Recorded by 2026`
      ),
    by = c("Felt_rute" = "Rute_kode")
  ) %>%
  mutate(
    recordedBy_new = case_when(
      recordedBy_new == "Kristian og Magni" ~
        "Magni Olsen Kyrkjeeide, Kristian Hassel",#this wasnt neccessary, i relaised we were all on the relevant plots but anywasy
      TRUE ~ recordedBy_new
    ),
    recordedBy = recordedBy_new,
    identifiedBy = recordedBy_new
  ) %>%
  select(-recordedBy_new, -Felt_rute)

#Move eventID up fromt
Occurrence <- Occurrence %>%
relocate(eventID, .before = everything())

#XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
#Add cover for S. troendelagicum!!!####
#data loading
covertroendelagicum<-read_excel("C:/Users/fia.bengtsson/OneDrive - NINA/Documents/Effektoverv??kning/Vegetasjonsanalyser_overv??king_data COPY.xlsx", sheet = "Dekning Stroend", .name_repair = "minimal")

# Create Sphagnum troendelagicum cover observations ####

# Start from Frekvens, which still contains Felt_rute
STrond <- Frekvens %>%
  filter(ScientificName == "Sphagnum troendelagicum") %>%
  select(Felt_rute)

# Match cover data using Felt_rute and Rute
STrond <- STrond %>%
  left_join(
    covertroendelagicum %>%
      transmute(
        Felt_rute = Rute,
        organismQuantity = as.character(`Dekning 2026`) %>%
          gsub("<", "0.1", ., fixed = TRUE) %>%
          as.numeric()
      ),
    by = "Felt_rute"
  )

# Match eventID using Event
STrond <- STrond %>%
  left_join(
    Event %>% select(locationID, eventID),
    by = c("Felt_rute" = "locationID")
  )

# Check matching
print(STrond)

# Copy original Sphagnum troendelagicum observations and replace quantity information
STrond_new <- Occurrence %>%
  filter(
    scientificName == "Sphagnum troendelagicum"
  )

# Replace only the three relevant fields
STrond_new$eventID <- STrond$eventID
STrond_new$organismQuantity <- STrond$organismQuantity

STrond_new <- STrond_new %>%
  mutate(
    organismQuantityType =
      "Cover in percent (visually estimated in a 50x50cm square plot)"
  )

# Add cover observations
Occurrence <- bind_rows(Occurrence, STrond_new)

#Check S troend
Occurrence %>%
  filter(scientificName == "Sphagnum troendelagicum") %>%
  count(organismQuantityType)

#Last sheet! Measure or Fact
peat<-read_excel("C:/Users/fia.bengtsson/OneDrive - NINA/Documents/Effektoverv??kning/Vegetasjonsanalyser_overv??king_data COPY.xlsx", sheet = "Torvdybde", .name_repair = "minimal")
str(peat)

#Measurement df
library(dplyr)

Measurement <- Event %>%
  inner_join(
    peat %>% select(Rute, Snitt),
    by = c("locationID" = "Rute")
  ) %>%
  left_join(
    Lokaliteter %>%
      select(
        Rute_kode,
        measurementDeterminedBy = `Recorded by 2026`
      ),
    by = c("locationID" = "Rute_kode")
  ) %>%
  transmute(
    eventID = eventID,
    measurementID = NA_character_,
    measurementType = "peat depth",
    measurementValue = as.character(Snitt),
    measurementAccuracy = NA_character_,
    measurementUnit = "centimeters",
    measurementDeterminedBy = measurementDeterminedBy,
    measurementDeterminedDate = eventDate,
    measurementMethod = "average from 4 measurements with peat probe",
    measurementRemarks = NA_character_
  )


#Filter only S. troendelag for occurrence
#Check S troend
Occurrence_S_troend<-Occurrence %>%
  filter(scientificName == "Sphagnum troendelagicum")



#Save all three sheets to excel!!####
#write_xlsx(
 # list(
  #  Event = Event,
   # Occurrence = Occurrence,
   # MeasurementOrFact = Measurement
  #),
  #"EventCore_Troender2026_all species data.xlsx"
#)
