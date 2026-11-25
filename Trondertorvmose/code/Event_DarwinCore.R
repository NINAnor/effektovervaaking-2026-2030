#Code to create Eventcore data from Tr??ndertorvmose effektoverv??kning 2026 ####
#Will make one row per plot_ID in sheet one

# Mappe med datafilene (sett til stien til din egen datamappe)
data_dir <- "PATH/TO/DATA"

library(dplyr)
library(tibble)
library(readxl)
library(dplyr)
library(readr)

library(writexl)

#Recreate a eventcore df with the plot ids and columns
#Sheet Event####
# Plot IDs 
plot_ID <- c(
  "Kors_1", "Kors_2",
  "Kal_1", "Kal_2", "Kal_3", "Kal_4",
  "Hen_1", "Hen_2", "Hen_3", "Hen_4"
)

# GBIF sampling event column names
event_columns <- c(
  "type", "license", "datasetName", "ownerInstitutionCode",
  "informationWithheld", "dataGeneralizations", "dynamicProperties",
  "ansvarligNINA", "eventID", "parentEventID", "samplingProtocol",
  "sampleSizeValue", "sampleSizeUnit", "samplingEffort",
  "eventDate", "eventTime", "year", "month", "day",
  "habitat", "habitatNiN", "versionNiN", "fieldNumber",
  "fieldNotes", "eventRemarks", "locationID", "country",
  "stateProvince", "county", "locality", "longitude", "latitude",
  "originalkoordinat_longitude", "originalkoordinat_latitude",
  "UTMsone", "UTMost", "UTMnord", "footprintWKT",
  "coordinateUncertaintyInMeters", "coordinatePrecision",
  "minimumElevationInMeters", "maximumElevationInMeters",
  "minimumDepthInMeters", "maximumDepthInMeters",
  "locationAccordingTo"
)

# Create dataframe with one row per plot
Event <- as_tibble(
  setNames(
    replicate(length(event_columns), rep(NA_character_, length(plot_ID)),
              simplify = FALSE),
    event_columns
  )
)

# Populate eventID
Event$eventID <- paste0(plot_ID, "_2026")


Event <- Event %>%
  mutate(
    type = "field observation",
    datasetName = "Effektovervokning Sphagnum troendelagicum 2026",
    ownerInstitutionCode = "NINA",
    ansvarligNINA = "Fia Bengtsson",
    locationID = plot_ID,
    country = "Norway",
    stateProvince = "Troendelag",
    habitat= "mire",
    
    county = case_when(
      grepl("^Hen", plot_ID) ~ "Steinkjer",
      grepl("^(Kal|Kors)", plot_ID) ~ "Namsos"
    ),
    
    locality = case_when(
      grepl("^Kal", plot_ID) ~ "Kaldal",
      grepl("^Kors", plot_ID) ~ "Korsmyra",
      grepl("^Hen", plot_ID) ~ "Henningslettet"
    )
  )

#Load data 
Lokaliteter <- read_excel(
  file.path(data_dir, "Vegetasjonsanalyser_overvåking_data COPY.xlsx"),
  sheet = "Lokaliteter"
)
Event <- Event %>%
  left_join(
    Lokaliteter %>%
      select(Rute_kode, Latitude, Longitude, Altitude),
    by = c("locationID" = "Rute_kode")
  ) %>%
  mutate(
    originalkoordinat_latitude = as.character(Latitude),
    originalkoordinat_longitude = as.character(Longitude),
    
    minimumElevationInMeters = parse_number(as.character(Altitude)),
    maximumElevationInMeters = parse_number(as.character(Altitude))
  ) %>%
  select(-Latitude, -Longitude, -Altitude)

Lokaliteter %>%
  select(Rute_kode, Latitude, Longitude) %>%
  head(5)

Event <- Event %>%
  mutate(
    latitude = as.numeric(sub("^N", "", originalkoordinat_latitude)),
    longitude = as.numeric(sub("^E", "", originalkoordinat_longitude))
  )

Event %>%
  select(eventID, originalkoordinat_latitude,
         originalkoordinat_longitude, latitude, longitude)
#Change date format
Event <- Event %>%
  left_join(
    Lokaliteter %>%
      select(Rute_kode, Date),
    by = c("locationID" = "Rute_kode")
  ) %>%
  mutate(
    eventDate = format(as.Date(Date, format = "%d.%m.%Y"), "%Y-%m-%d"),
    year = as.integer(format(as.Date(Date, format = "%d.%m.%Y"), "%Y")),
    month = as.integer(format(as.Date(Date, format = "%d.%m.%Y"), "%m")),
    day = as.integer(format(as.Date(Date, format = "%d.%m.%Y"), "%d"))
  ) %>%
  select(-Date)

write_xlsx(
  list(Event = Event),
  file.path(data_dir, "Event2.xlsx")
)


#Done with sheet 1! Hurray!!####

