
ipak <- function(pkg){
  new.pkg <- pkg[!(pkg %in% installed.packages()[, "Package"])]
  if (length(new.pkg)) 
    install.packages(new.pkg, dependencies = TRUE)
  sapply(pkg, require, character.only = TRUE)
}


# Function to rename files
rename_file <- function(file_path) {
  # Extract the filename without the path
  file_name <- basename(file_path)
  
  # Use regex to extract relevant part of the filename
  new_name <- sub("^ATT\\d+_\\{[^}]+\\}_", "", file_name)
  
  # Endre "-" til "_"
  new_name <- gsub("-", "_", new_name)
  
  # Define the new file path
  new_file_path <- file.path(dest_dir, new_name)
  
  # Copy the file to the new location with the new name
  file.copy(file_path, new_file_path)
}


#' Build and export a "dirty" table from survey inputs
#'
#' @param filepath Path to a .zip (containing a .gdb), a .gdb folder, or an .xlsx
#' @param outputpath Folder where the processed file should be written
#' @param project Project name used in the output folder/file names
#' @param gdb_layers Named list with layers for gdb input (default: surveyPoint/art)
#' @param xlsx_sheets Named list with sheets for xlsx input (default: surveyPoint_0/art_1)
#' @return Invisibly returns a list with `data` (the tibble) and `outfile` (written path)
#' @examples
#' res <- build_dirty_table("data/myfile.zip", "out", "myproj")
survey123_to_table <- function(filepath,
                               outputpath,
                              project,
                              gdb_layers   = list(survey = "surveyPoint", art = "art"),
                              xlsx_sheets  = list(survey = "surveyPoint_0", art = "art_1")) {
  
  # ---- helpers ----
  stop_if_missing <- function(pkgs) {
    miss <- pkgs[!vapply(pkgs, requireNamespace, FUN.VALUE = logical(1), quietly = TRUE)]
    if (length(miss)) stop("Missing required packages: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  
  rename_if_exists <- function(df, renames) {
    # renames: named list where names are new names, values are character vectors of candidate old names
    for (new_name in names(renames)) {
      olds <- renames[[new_name]]
      match <- olds[olds %in% names(df)]
      if (length(match) > 0) {
        df <- dplyr::rename(df, !!rlang::sym(new_name) := !!rlang::sym(match[1]))
      }
    }
    df
  }
  
  reorder_numbers <- function(x) {
    if (is.null(x)) return(x)
    vapply(strsplit(as.character(x), ","), function(y) {
      y <- trimws(y)
      y <- y[nzchar(y)]
      if (!length(y)) return(NA_character_)
      paste(sort(as.numeric(y)), collapse = ",")
    }, FUN.VALUE = character(1))
  }
  
  to_lower_names <- function(df) { names(df) <- tolower(names(df)); df }
  
  # ---- deps ----
  stop_if_missing(c("sf", "dplyr", "stringr", "readxl", "openxlsx", "rlang"))
  
  # ---- import ----
  ext <- tolower(tools::file_ext(filepath))
  read_env_species <- function(filepath, ext) {
    if (ext == "zip") {
      # unzip next to the file (like your original)
      exdir <- dirname(filepath)
      #utils::unzip(filepath, exdir = exdir)
      files <- utils::unzip(filepath, exdir = exdir, unzip = "internal")
      gdb_dirs <- unique(dirname(files[grepl("\\.gdb(/|\\\\)", files)]))

      # choose most recently modified folder inside exdir
      #folders <- list.dirs(exdir, full.names = TRUE, recursive = FALSE)
      #if (!length(folders)) stop("No folders found after unzipping '", filepath, "'.")
      #gdb_folder <- folders[which.max(file.info(folders)$mtime)]
      
      # import all layers except ATTACH
      layers <- st_layers(gdb_dirs)$name
      layers_to_read <- layers[!grepl("ATTACH", layers, ignore.case = TRUE)]
      list <- lapply(layers_to_read, function(lyr) st_read(gdb_dirs, layer = lyr))
      names(list) <- layers_to_read
      
      #env <- sf::st_read(gdb_folder, layer = "surveyPoint", quiet = TRUE) #layer = gdb_layers$survey, quiet = TRUE)
      #sp  <- sf::st_read(gdb_folder, layer = "art",    quiet = TRUE) #layer = gdb_layers$art,    quiet = TRUE)
      return(list)
    }
    
    if (ext == "gdb") {
      # import all layers except ATTACH
      layers <- st_layers(filepath)$name
      layers_to_read <- layers[!grepl("ATTACH", layers, ignore.case = TRUE)]
      sf_list <- lapply(layers_to_read, function(lyr) st_read(gdb_folder, layer = lyr))
      names(list) <- layers_to_read
      
      #env <- sf::st_read(gdb_folder, layer = "surveyPoint", quiet = TRUE) #layer = gdb_layers$survey, quiet = TRUE)
      #sp  <- sf::st_read(gdb_folder, layer = "art",    quiet = TRUE) #layer = gdb_layers$art,    quiet = TRUE)
      return(sf_list)
    }
    
    if (ext == "xlsx") {
      # import all layers except ATTACH
      sheets <- excel_sheets(filepath)
      sheets_to_read <- sheets[!grepl("ATTACH", sheets, ignore.case = TRUE)]
      list <- lapply(sheets_to_read, function(sh) read_excel(path, sheet = sh))
      names(list) <- sheets_to_read
      
      #env <- sf::st_read(gdb_folder, layer = "surveyPoint", quiet = TRUE) #layer = gdb_layers$survey, quiet = TRUE)
      #sp  <- sf::st_read(gdb_folder, layer = "art",    quiet = TRUE) #layer = gdb_layers$art,    quiet = TRUE)
      return(list)
    }
    
    stop("Unsupported file type: ", ext)
  }
  
  imported <- read_env_species(filepath, ext)
  env <- imported$surveyPoint
  others <- imported[setdiff(names(imported), "surveyPoint")] #species <- imported$species
  
  # ---- coordinates / geometry handling ----
  if (inherits(env, "sf")) {
    coords <- sf::st_coordinates(env)
    env$longitude <- coords[, 1]
    env$latitude  <- coords[, 2]
    env <- sf::st_drop_geometry(env)
  } else {
    # If from Excel and columns are named x/y, standardize
    if (all(c("x", "y") %in% names(env))) {
      env <- dplyr::rename(env, longitude = x, latitude = y)
    }
  }
  
  # ---- lower-case and id alignment ----
  env     <- to_lower_names(env)
  others <- lapply(others, to_lower_names) #species <- to_lower_names(species)
  
  if ("globalid" %in% names(env)) {
    env <- dplyr::rename(env, parentglobalid = globalid)
  }
  
  # ---- join ----
  #dat <- dplyr::left_join(env, species, by = "parentglobalid", keep = FALSE)
  
  dat <- env %>%
    dplyr::select(
      -dplyr::any_of(c(
        "veg_html_rows","objectid","display_tot","creationdate","creator",
        "editdate","editor","veg_html_row"
      )))
  for (nm in names(others)) {
    layer <- others[[nm]]
    if (!"parentglobalid" %in% names(layer)) next
    
    # drop geometry for non-env layers
    if (inherits(layer, "sf")) layer <- sf::st_drop_geometry(layer)
    
    # remove unnecessary columns
    layer <- dplyr::select(
      layer,
      -dplyr::any_of(c(
        "veg_html_rows","objectid","display_tot","creationdate","creator",
        "editdate","editor","veg_html_row", "globalid"
      )))
    
    #names(layer)[names(layer) %in% "globalid"] <- paste0(nm, "_globalid")
    
    dat <- dplyr::left_join(dat, layer, by = "parentglobalid")
  }
  
  # ---- rename columns to canonical names (only when present) ----
  renames <- list(
    event_time  = c("registreringsdato","registreringsdato:","dato"),
    
    main_time_end  = c("klokkeslett_slutt"),
    
    locality    = c("lokalitet"),
    polygon_id  = c("polygon_id"),
    plot_id     = c("rute_id"),
    registrator = c("bruker_navn","observatør","observator","observatørnavn"),
    weather     = c("vaer","værforhold","vaerforhold"),
    gps_accuracy = c("noeyaktighet","nøyaktighet","gps_noeyaktighet","gps_nøyaktighet"),
    
    # Plant cover
    cover_field_layer       = c("dekning % av karplanter i feltsjikt"),
    cover_vegetation_total  = c("tot_dekning","total_dekning"),
    cover_bottom_layer      = c("bunnsjikt_dekning","dekning % av bunnsjikt"),
    cover_bryophytes        = c("dekning_moser","moser_dekning"),
    cover_lichens           = c("dekning_lav","lav_dekning"),
    cover_litter            = c("stroe_dekning","strø_dekning","dekning_strø","dekning % av strø"),
    cover_rock              = c("grus_stein_berg_fjell_dekning","dekning % av grus/stein/berg/fjell"),
    cover_crust             = c("crust_dekning"),
    cover_bare_soil         = c("jord_dekning","dekning % av bar jord"),
    
    cover_woody_plants_field_layer = c("dekning % av vedplanter i feltsjikt"),
    cover_shrub_layer              = c("dekning % av vedplanter i busksjikt"),
    cover_tree_layer               = c("dekning % tresjikt"),
    
    cover_species = c("sp_dekning","dekning %"),
    
    # Vegetation heights
    vegheight1 = c("vegetasjonshøyde måling 1","veg_hoyde1","veg_høyde1"),
    vegheight2 = c("vegetasjonshøyde måling 2","veg_hoyde2","veg_høyde2"),
    vegheight3 = c("vegetasjonshøyde måling 3","veg_hoyde3","veg_høyde3"),
    vegheight4 = c("vegetasjonshøyde måling 4","veg_hoyde4","veg_høyde4"),
    
    # Fastmerker
    benchmarked = c("fastmerker","er det satt ned fastmerker?"),
    
    # Sub-plots
    species                 = c("navn","species_name"),
    preferred_popularname   = c("sp_species"),
    fertile                 = c("fertile skudd","fertile_skudd"),
    plot_subplots           = c("smårutene nr.","smårutene nr","ruter","smarutene nr.","smarutene nr")#,
    
    # ids
    #parenteventid = c("parentglobalid"),
    #eventid       = c("globalid")
  )
  
  dat <- rename_if_exists(dat, renames)
  
  # ---- date parts, subplot ordering, veg height mean, preferred name cleanup ----
  if ("main_date" %in% names(dat)) {
    # parse date/time flexibly, then standardize
    et <- suppressWarnings(as.POSIXct(dat$main_date, tz = "UTC"))
    if (all(is.na(et))) et <- suppressWarnings(as.Date(dat$main_date))
    dte <- as.Date(et)
    dat$year  <- format(dte, "%Y")
    dat$month <- format(dte, "%m")
    dat$day   <- format(dte, "%d")
    dat$main_date <- format(dte, "%Y%m%d") # no hyphens
  }
  
  #if ("plot_subplots" %in% names(dat)) {
  #  dat$plot_subplots <- reorder_numbers(dat$plot_subplots)
  #}
  
  #hv_cols <- intersect(c("vegheight1","vegheight2","vegheight3","vegheight4"), names(dat))
  #if (length(hv_cols)) {
  #  dat$plot_height_vegetation_mean <- rowMeans(dat[hv_cols], na.rm = TRUE)
  #}
  
  if ("preferred_popularname" %in% names(dat)) {
    dat$preferred_popularname <- stringr::str_extract(dat$preferred_popularname, "(?<=\\().+?(?=\\))")
  }
  
  # ---- drop all-NA columns ----
  dat <- dplyr::select(dat, dplyr::where(~ !all(is.na(.))))
  
  # ---- arrange column order ----
  dat <- dat %>%
    relocate(c("year","month","day"),.after = main_date) %>%
    relocate(c("main_time_end"),.after = main_time_start) %>%
    relocate(c("longitude", "latitude"),.after = main_plot_id)
    
  
  # ---- write output ----
  processed_folder <- file.path(outputpath, paste0(project, "_processed"))
  if (!dir.exists(processed_folder)) {
    dir.create(processed_folder, recursive = TRUE)
    message("Directory created for processed data: ", processed_folder)
  }
  
  outfile <- file.path(processed_folder, paste0(project, "_export_dirty.xlsx"))
  openxlsx::write.xlsx(dat, file = outfile, colNames = TRUE)
  
  message("Wrote: ", outfile)
  invisible(list(data = dat, outfile = outfile))
}


###############################################################################
##### Table diagnostics and cleaning                                      #####

# Function for getting names from nortaxa
nortaxa_names <- function(speciesname) {
  
  # Use tryCatch to handle errors and return a dataframe with original_name and NAs
  tryCatch({
    # Replace underscores with plus signs for URL encoding
    speciesnameURL <- gsub("_", "+", speciesname)
    speciesURL <- paste0("https://nortaxa.artsdatabanken.no/api/v1/TaxonName/Search?Search=", speciesnameURL)
    # Make the API call
    r <- GET(url = speciesURL)
    
    # Check if the API request was successful
    if (http_type(r) != "application/json" || status_code(r) != 200) {
      return(data.frame(original_name = speciesname,
                        taxonId = NA,
                        acceptedScientificName.name = NA,
                        pref_popular_name = NA,
                        stringsAsFactors = FALSE))
    }
    
    # Parse the response content
    r_content <- content(r, as = "text", encoding = "UTF-8")
    
    # Ensure valid JSON is returned
    if (nchar(r_content) == 0) {
      warning(paste("API returned empty content for species:", speciesname))
      # Return dataframe with speciesname and NA for other columns
      return(data.frame(original_name = speciesname, taxonId = NA, acceptedScientificName.name = NA, pref_popular_name = NA, stringsAsFactors = FALSE))
    }
    
    # Convert JSON to dataframe
    df <- fromJSON(r_content, flatten = TRUE)
    
    # Only keep accepted names and filter based on speciesURL + signs and rank
    df_filtered <- df %>%
      filter(
        case_when(
          str_count(speciesURL, "\\+") == 0 ~ acceptedScientificName.rank == "Genus",
          str_count(speciesURL, "\\+") == 1 ~ acceptedScientificName.rank == "Species",
          str_count(speciesURL, "\\+") == 2 ~ acceptedScientificName.rank == "Subspecies",
          str_count(speciesURL, "\\+") == 3 ~ acceptedScientificName.rank == "Variety",
          TRUE ~ FALSE  # Default case if no condition matches
        ),
        acceptedScientificName.isSearchMatch  # Filter for search match
      )
    
    # If no rows pass the filter, return speciesname with NA for other columns
    if (nrow(df_filtered) == 0) {
      return(data.frame(original_name = speciesname, taxonId = NA, acceptedScientificName.name = NA, pref_popular_name = NA, stringsAsFactors = FALSE))
    }
    
    # Add the speciesname and first popular name if it exists
    df_final <- df_filtered %>%
      mutate(pref_popular_name = map_chr(preferredVernacularNames, ~ if (!is.null(.x) && length(.x$name) > 0) {.x$name[1]} else {NA_character_}),
             original_name = speciesname) %>%
      # Reorder the columns
      select(original_name, taxonId, acceptedScientificName.name, pref_popular_name) %>%
      slice(1)
    
    return(df_final)  # Return the processed dataframe
    
  }, error = function(e) {
    # Handle any error that occurs in the tryCatch block
    warning(paste("Error processing species:", speciesname, " - ", e$message))
    # Return a dataframe with original_name and NA for other columns
    return(data.frame(original_name = speciesname, taxonId = NA, acceptedScientificName.name = NA, pref_popular_name = NA, stringsAsFactors = FALSE))
  })
}

### Prosesser

process_and_diagnose <- function(
    dat,
    export_diagnostics = TRUE,
    diagnostics_folder = NULL,
    project = NULL,
    collctd_hpcoords = NULL,
    hpcoords = NULL,
    hpcrs = NULL,
    check_GIS = TRUE,
    outputpath = NULL#,
    #export_analyses = TRUE
) {
  # ---- deps (soft checks) ----
  req_pkgs <- c("dplyr","tidyr","sf","stringr","openxlsx")
  missing_pkgs <- req_pkgs[!vapply(req_pkgs, requireNamespace, FUN.VALUE = TRUE, quietly = TRUE)]
  if (length(missing_pkgs)) {
    stop("Missing required packages: ", paste(missing_pkgs, collapse = ", "),
         ". Please install them before running.")
  }
  `%>%` <- dplyr::`%>%`
  
  # Project name
  if (is.null(project)) {
    if (exists("project", envir = .GlobalEnv)) {
      project <- get("project", envir = .GlobalEnv)
    } else {
      stop("`project` not provided and not found in global environment.")
    }
  }
  
  
  # Diagnostics folder
  if (isTRUE(export_diagnostics)) {
    if (is.null(diagnostics_folder)) {
      if (exists("diagnostics_folder", envir = .GlobalEnv)) {
        diagnostics_folder <- get("diagnostics_folder", envir = .GlobalEnv)
      } else if (!is.null(outputpath)) {
        diagnostics_folder <- file.path(outputpath, "Diagnostics")
      } else {
        stop("`diagnostics_folder` not provided, not found globally, and no `outputpath` supplied.")
      }
    }
    if (!dir.exists(diagnostics_folder)) {
      dir.create(diagnostics_folder, recursive = TRUE, showWarnings = FALSE)
      message("Created diagnostics folder: ", diagnostics_folder)
    }
  }
  
  # Exports folder
  if (is.null(outputpath)) {
    if (exists("outputpath", envir = .GlobalEnv)) {
      outputpath <- get("outputpath", envir = .GlobalEnv)
    } else {
      stop("`outputpath` is required (not provided and not found in global environment).")
    }
  }
  exports_folder <- file.path(outputpath, "Exports")
  if (!dir.exists(exports_folder)) {
    dir.create(exports_folder, recursive = TRUE, showWarnings = FALSE)
  }
  
  
  
  # ===============================
  # Prosesser og diagnostiser plot ID
  # ===============================
  message("Prosesser og diagnostiser plot ID")
  datplot <- dat %>%
    dplyr::select(dplyr::any_of(c("main_plot_id", "maindate", "main_location_id","plot_nature_type"))) %>%
    dplyr::group_by(dplyr::across(dplyr::everything())) %>%
    dplyr::summarise(main_plot_id_nr = dplyr::n(), .groups = "drop") %>%
    dplyr::distinct()
  
  if (export_diagnostics) {
    readme_lines <- paste0(c(
      "The file _plot_names.xlsx includes the plot names in the dataset, when they",
      "were registered (date/eventTime), ecosystem type and mapping unit, and number",
      "of times this combination of columns are represented in the dataset. This",
      "will likely represent the number of species registrered in each plot.",
      "",
      "Nr of unique plots present in dataframe:",
      length(unique(datplot$main_plot_id))
    ))
    writeLines(readme_lines, con = file.path(diagnostics_folder, "README_plot_names.txt"))
    openxlsx::write.xlsx(datplot, file = file.path(diagnostics_folder, paste0(project, "_plot_names.xlsx")), colNames = TRUE)
  }
  
  # ===================================
  # Prosesser og diagnostiser koordinater
  # ===================================
  dathpcoordsw <- NULL
  
  if (is.null(collctd_hpcoords)) {
    if (exists("collctd_hpcoords", envir = .GlobalEnv)) {
      collctd_hpcoords <- get("collctd_hpcoords", envir = .GlobalEnv)
    } else {
      collctd_hpcoords <- FALSE  # safe fallback
    }
  }
  
  if (isTRUE(collctd_hpcoords)) {
    message("Prosesser og diagnostiser koordinater")
    
    hpcoords2 <- hpcoords %>%
      dplyr::select(1:4) %>%
      stats::setNames(c("Point","Y","X","Elev")) %>%
      dplyr::mutate(plot_id = sub("(.+?)(\\_.*)", "\\1", Point))
    
    dathpcoords <- hpcoords2 %>%
      dplyr::full_join(dat %>% dplyr::select(main_plot_id, plot_gps_type) %>% dplyr::distinct(),
                       by = c("plot_id" = "main_plot_id"))
    
    # If any Y are NA, try Survey123 coords (lat/long -> hpcrs)
    hpcoordsNA <- unique(dathpcoords$plot_id[is.na(dathpcoords$Y)])
    if (length(hpcoordsNA) > 0) {
      # Need latitude/longitude columns in dat
      if (!all(c("longitude","latitude","main_plot_id") %in% names(dat))) {
        stop("Some plots missing HP coords but dat lacks 'longitude'/'latitude' to backfill from Survey123.")
      }
      survey123coords <- dat %>%
        dplyr::filter(main_plot_id %in% hpcoordsNA) %>%
        dplyr::select(main_plot_id, longitude, latitude) %>%
        dplyr::distinct() %>%
        tidyr::drop_na()
      
      if (nrow(survey123coords) > 0) {
        survey123_sf <- sf::st_as_sf(survey123coords, coords = c("longitude","latitude"), crs = "EPSG:4326") %>%
          sf::st_transform(crs = hpcrs)
        coordssurvey123 <- sf::st_coordinates(survey123_sf)
        survey123coords2 <- survey123_sf %>%
          cbind(coordssurvey123) %>%
          sf::st_drop_geometry() %>%
          dplyr::mutate(
            gps = "Survey123",
            Point = paste0(main_plot_id, "_no"),
            plot_id = main_plot_id
          ) %>%
          dplyr::rename(X = X, Y = Y) %>%
          dplyr::select(plot_id, Point, Y, X, gps)
        dathpcoords <- dathpcoords %>%
          dplyr::full_join(survey123coords2, by = c("plot_id","Point","Y","X","gps"))
      }
    }
    
    # Fill row-wise per plot_id
    dathpcoords <- dathpcoords %>%
      dplyr::group_by(plot_id) %>%
      tidyr::fill(Point, Y, X, Elev, .direction = "downup") %>%
      dplyr::ungroup() %>%
      dplyr::distinct()
    
    plotcoordsnr <- dathpcoords %>%
      dplyr::group_by(plot_id) %>%
      dplyr::summarise(nr_coords = dplyr::n(), .groups = "drop")
    
    dathpcoords <- dathpcoords %>%
      dplyr::left_join(plotcoordsnr, by = "plot_id") %>%
      dplyr::filter(!is.na(Y)) %>%
      dplyr::rename(UTMost = X, UTMnord = Y, minimumElevationInMeters = Elev) %>%
      dplyr::mutate(UTMsone = substr(hpcrs, nchar(hpcrs)-1, nchar(hpcrs)),
                    Plot_corner = sub(".*_", "", Point))
    
    # Wide, one row per plot_id
    dathpcoordsw <- dathpcoords %>%
      dplyr::select(minimumElevationInMeters, plot_id, gps, nr_coords, UTMsone, UTMnord, UTMost, Plot_corner) %>%
      tidyr::pivot_wider(names_from = Plot_corner, values_from = c(UTMnord, UTMost)) %>%
      dplyr::group_by(plot_id) %>%
      tidyr::fill(UTMnord_sv, UTMnord_no, UTMost_sv, UTMost_no, .direction = "downup") %>%
      dplyr::distinct() %>%
      dplyr::summarise(
        minimumElevationInMeters = mean(minimumElevationInMeters, na.rm = TRUE),
        gps = dplyr::first(gps),
        nr_coords = dplyr::first(nr_coords),
        UTMsone = dplyr::first(UTMsone),
        UTMnord_sv = dplyr::first(UTMnord_sv),
        UTMnord_no = dplyr::first(UTMnord_no),
        UTMost_sv = dplyr::first(UTMost_sv),
        UTMost_no = dplyr::first(UTMost_no),
        .groups = "drop"
      )
    
    # Merge onto dat (drop any existing 'gps' col to avoid clash)
    dat <- dat %>%
      dplyr::select(-dplyr::any_of("gps")) %>%
      dplyr::full_join(dathpcoordsw, by = c("main_plot_id" = "plot_id")) %>%
      dplyr::select(-dplyr::any_of("nr_coords"))
    
    if (export_diagnostics) {
      readme_lines <- paste0(c(
        "The file _plot_coords.xlsx includes the high precision coordinates",
        "and Survey123 coordinates if the high precision ones were missing.",
        "Check for writing errors in names and if any plot_ids have more than two",
        "coordinates. Also check if the corner coordinates are correct in regards to",
        "sv and no (should not be sw or ne, but if they should be, the scripts below",
        "needs to be edited to match this."
      ))
      writeLines(readme_lines, con = file.path(diagnostics_folder, "README_coords.txt"))
      openxlsx::write.xlsx(dathpcoords, file = file.path(diagnostics_folder, paste0(project, "_plot_coords.xlsx")), colNames = TRUE)
    }
  }
  
  # ===============================
  # Optional simple GIS check
  # ===============================
  if (isTRUE(check_GIS) && isTRUE(collctd_hpcoords)) {
    # Build corners from *_no and *_sv
    plotcoordcor <- dat %>%
      dplyr::select(main_plot_id, UTMnord_no, UTMost_no, UTMnord_sv, UTMost_sv)
    
    plotcoordw <- plotcoordcor %>%
      dplyr::rename(y_no = UTMnord_no, x_no = UTMost_no, y_sv = UTMnord_sv, x_sv = UTMost_sv)
    
    xc <- (plotcoordw$x_no + plotcoordw$x_sv)/2 ; yc <- (plotcoordw$y_no + plotcoordw$y_sv)/2
    xd <- (plotcoordw$x_no - plotcoordw$x_sv)/2 ; yd <- (plotcoordw$y_no - plotcoordw$y_sv)/2
    
    plotcoordw$y_nv <- yc + xd ; plotcoordw$x_nv <- xc - yd
    plotcoordw$y_so <- yc - xd ; plotcoordw$x_so <- xc + yd
    
    plotcoords <- plotcoordw %>%
      tidyr::pivot_longer(
        cols = tidyselect::starts_with(c("x_","y_")),
        names_to = c(".value","corner"),
        names_sep = "_"
      ) %>%
      dplyr::rename(UTMnord = y, UTMost = x) %>%
      tidyr::drop_na()
    
    sfplotpoints <- sf::st_as_sf(plotcoords, coords = c("UTMost","UTMnord"), crs = hpcrs)
    
    sfplotpolygons <- sfplotpoints %>%
      dplyr::group_by(main_plot_id) %>%
      dplyr::summarise(geometry = sf::st_union(geometry), .groups = "drop") %>%
      sf::st_convex_hull() %>%
      dplyr::left_join(plotcoords %>% dplyr::select(-corner, -UTMost, -UTMnord), by = "main_plot_id") %>%
      dplyr::mutate(area = sf::st_area(dplyr::cur_data_all()))
    
    # Quick map if mapview is available
    if (requireNamespace("mapview", quietly = TRUE)) {
      mapview::mapview(sfplotpolygons,
                       col.regions = "darkred",
                       label = "main_plot_id",
                       layer.name = "main_plot_id",
                       legend = FALSE)
    } else {
      message("Package 'mapview' not installed; skipping quick map.")
    }
  }
  
  # ==================================
  # Prosesser og diagnostiser artsnavn i plot
  # ==================================
    message("Prosesser og diagnostiser artsnavn")

    nortaxa_plot_species <- lapply(dat$plot_species, nortaxa_names) %>%
      dplyr::bind_rows() %>%
      dplyr::distinct() %>%
      dplyr::arrange(.data$original_name)
    
    plot_speciesnr <- dat %>%
      dplyr::group_by(plot_species) %>%
      dplyr::summarise(plot_species_nr = dplyr::n(), .groups = "drop")
    
    nortaxa_plot_species_out <- nortaxa_plot_species %>%
      dplyr::left_join(dplyr::rename(plot_speciesnr, original_name = plot_species), by = "original_name")# %>%
     # tidyr::drop_na()
    
    if (export_diagnostics) {
      readme_lines <- paste0(c(
        "The file _plot_species_names.xlsx includes the original name found in the Survey123 dataset",
        "and what name it matches to in Artsdatabanken. Here you can also see which names have writing errors etc."
      ))
      writeLines(readme_lines, con = file.path(diagnostics_folder, "README_plot_speciesnames.txt"))
      openxlsx::write.xlsx(nortaxa_plot_species_out, file = file.path(diagnostics_folder, paste0(project, "_plot_species_names.xlsx")), colNames = TRUE)
    }
    
  # ==================================
  # Prosesser og diagnostiser artsnavn i sirkel (hvis tilgjengelig)
  # ==================================
    
    # Rødliste
  if(any(grepl("circle_redlist_species", names(dat)))){
    
    nortaxa_circle_redlist_species <- lapply(dat$circle_redlist_species, nortaxa_names) %>%
      dplyr::bind_rows() %>%
      dplyr::distinct() %>%
      dplyr::arrange(.data$original_name)
    
    circle_redlist_speciesnr <- dat %>%
      dplyr::group_by(circle_redlist_species) %>%
      dplyr::summarise(circle_redlist_species_nr = dplyr::n(), .groups = "drop")
    
    nortaxa_circle_redlist_species_out <- nortaxa_circle_redlist_species %>%
      dplyr::left_join(dplyr::rename(circle_redlist_speciesnr, original_name = circle_redlist_species), by = "original_name") #%>%
      #tidyr::drop_na()
    
    if (export_diagnostics) {
      readme_lines <- paste0(c(
        "The file _circle_redlist_species_names.xlsx includes the original name found in the Survey123 dataset",
        "and what name it matches to in Artsdatabanken. Here you can also see which names have writing errors etc."
      ))
      writeLines(readme_lines, con = file.path(diagnostics_folder, "README_circle_redlist_speciesnames.txt"))
      openxlsx::write.xlsx(nortaxa_circle_redlist_species_out, file = file.path(diagnostics_folder, paste0(project, "_circle_redlist_species_names.xlsx")), colNames = TRUE)
    }
    
  }
    
    # Fremmed
    if(any(grepl("circle_alien_species", names(dat)))){
      
      nortaxa_circle_alien_species <- lapply(dat$circle_alien_species, nortaxa_names) %>%
        dplyr::bind_rows() %>%
        dplyr::distinct() %>%
        dplyr::arrange(.data$original_name)
      
      circle_alien_speciesnr <- dat %>%
        dplyr::group_by(circle_alien_species) %>%
        dplyr::summarise(circle_alien_species_nr = dplyr::n(), .groups = "drop")
      
      nortaxa_circle_alien_species_out <- nortaxa_circle_alien_species %>%
        dplyr::left_join(dplyr::rename(circle_alien_speciesnr, original_name = circle_alien_species), by = "original_name") #%>%
        #tidyr::drop_na()
      
      if (export_diagnostics) {
        readme_lines <- paste0(c(
          "The file _circle_alien_species_names.xlsx includes the original name found in the Survey123 dataset",
          "and what name it matches to in Artsdatabanken. Here you can also see which names have writing errors etc."
        ))
        writeLines(readme_lines, con = file.path(diagnostics_folder, "README_circle_alien_speciesnames.txt"))
        openxlsx::write.xlsx(nortaxa_circle_alien_species_out, file = file.path(diagnostics_folder, paste0(project, "_circle_alien_species_names.xlsx")), colNames = TRUE)
      }
      
    }
    
    # Problem
    if(any(grepl("circle_problematic_species", names(dat)))){
      
      nortaxa_circle_problematic_species <- lapply(dat$circle_problematic_species, nortaxa_names) %>%
        dplyr::bind_rows() %>%
        dplyr::distinct() %>%
        dplyr::arrange(.data$original_name)
      
      circle_problematic_speciesnr <- dat %>%
        dplyr::group_by(circle_problematic_species) %>%
        dplyr::summarise(circle_problematic_species_nr = dplyr::n(), .groups = "drop")
      
      nortaxa_circle_problematic_species_out <- nortaxa_circle_problematic_species %>%
        dplyr::left_join(dplyr::rename(circle_problematic_speciesnr, original_name = circle_problematic_species), by = "original_name") #%>%
        #tidyr::drop_na()
      
      if (export_diagnostics) {
        readme_lines <- paste0(c(
          "The file _circle_problematic_species_names.xlsx includes the original name found in the Survey123 dataset",
          "and what name it matches to in Artsdatabanken. Here you can also see which names have writing errors etc."
        ))
        writeLines(readme_lines, con = file.path(diagnostics_folder, "README_circle_problematic_speciesnames.txt"))
        openxlsx::write.xlsx(nortaxa_circle_problematic_species_out, file = file.path(diagnostics_folder, paste0(project, "_circle_problematic_species_names.xlsx")), colNames = TRUE)
      }
      
    }
    
  
  # ===============================
  # Eksporter prosessert tabell (analyses)
  # ===============================
  message("Eksporterer prosessert data")
    
  #if (export_analyses) {
    
    # Plot species long
    plot_species <- dat_plot <- dat_circle <- circle_species <- NULL
    
    if ("plot_subplot_count" %in% names(dat)) {
      plot_species <- dat %>%
        dplyr::mutate(plot_subplot_count = stringr::str_count(.data$plot_subplot_count, ",") + 1) %>%
        dplyr::select(-plot_subplot_count)
    }
    
    if ("plot_cover_species" %in% names(dat)) {
      plot_species <- dat %>%
        dplyr::mutate(plot_cover_species = as.numeric(.data$plot_cover_species) / 100) %>%
        dplyr::select(-plot_cover_species)
    }
    
    if(any(!names(dat) %in% c("plot_subplot_count", "plot_cover_species"))) {
      plot_species <- dat %>%
        dplyr::mutate(freq_sub_plots = NA_real_)
    }
  
  plot_species <- plot_species %>%
    select(any_of(c("main_location_id","main_plot_id", "main_date", "main_observant_name", "plot_species", 
                    "plot_subplot_count", "plot_cover_species",
                  "freq_sub_plots", "plot_species_fertile","plot_species_comments"))) %>%
    unique()
  
  # Circle species long

  if(any(grepl("circle", names(dat)))){
  circle_species <- dat %>%
    rename(circle_alien_comments=circle_alien_comment) %>%
    tidyr::pivot_longer(
      cols = starts_with("circle_"),
      names_to = c("circle_species_type", ".value"),
      names_pattern = "circle_(alien|problematic)_(.*)"
    ) %>%
    rename(circle_species=species,
           circle_species_comments=comments) %>%
    dplyr::filter(!is.na(circle_species)) %>%  # keep only rows with species
    dplyr::mutate(
      circle_species_type = dplyr::recode(circle_species_type,
                                   alien = "alien",
                                   problematic = "problematic")
    ) %>%
    select(any_of(c("main_location_id","main_plot_id", "main_date", "main_observant_name","circle_species","circle_species_type", "circle_species_comments"))) %>%
    unique()
  }

    # Species wide
    #plot_speciesw <- plot_species %>%
    #  tidyr::pivot_wider(id_cols = main_plot_id,              # rows
    #                    names_from = plot_species, 
    #                    values_from = freq_sub_plots,
    #                    values_fill = 0                      # fill missing with 0
    #  )
    
    
    # Plot dataset
    datspeciesnr <- dat %>% # Number of species per plot
      dplyr::group_by(main_plot_id) %>%
      dplyr::summarise(nr_species = dplyr::n_distinct(plot_species, na.rm = TRUE), .groups = "drop")
    
    dat_plot <- dat %>%
      dplyr::select(!dplyr::any_of(c("eventid", 
                                     "plot_species", "plot_species_uncertain", "fetch_cover","fetch_species",
                                     "plot_subplot_count", "plot_cover_species",
                                     "plot_species_fertile", "preferred_popularname", "main_circle_nature_type")),
                    -tidyselect::starts_with("circle_"), # Removes all circle_* columns
                    -tidyselect::starts_with("plot_focal_"),
                    -tidyselect::starts_with("rute_")
                    ) %>%
      
      dplyr::distinct() %>%
      dplyr::left_join(datspeciesnr, by = "main_plot_id")
    
    datspeciesnr <- dat %>% # Number of species per plot
      dplyr::group_by(main_plot_id) %>%
      dplyr::summarise(nr_species = dplyr::n_distinct(plot_species, na.rm = TRUE), .groups = "drop")
    
    # Circle dataset
    if(any(grepl("circle", names(dat)))){
      datspeciescircle_nr <- dat %>% # Number of species per plot
        dplyr::group_by(main_plot_id) %>%
        dplyr::summarise(nr_species = dplyr::n_distinct(c(circle_alien_species, circle_problematic_species), na.rm = TRUE), .groups = "drop")
      
      dat_circle <- dat %>%
        rename(circle_alien_comments=circle_alien_comment) %>%
        dplyr::select(!dplyr::any_of(c("eventid", 
                                       "fetch_cover","fetch_species",
                                       "preferred_popularname",
                                       "circle_alien_species", "circle_problematic_species",
                                       "circle_alien_comments", "circle_problematic_comments"
        )),
        -tidyselect::starts_with("plot_") # Removes all plot_* columns
        ) %>%
        dplyr::distinct() %>%
        dplyr::left_join(datspeciescircle_nr, by = "main_plot_id")
      
    }
    
    # Focal dataset
    if(any(grepl("focal", names(dat)))){
      
      rename_map <- c(circle_alien_comment = "circle_alien_comments")
      
      dat_focal <- dat %>%
        rename(any_of(rename_map)) %>%
        dplyr::select(-tidyselect::starts_with("plot_"), # Removes all plot_* columns
                      
          -dplyr::any_of(c("eventid", "preferred_popularname",
                                       "circle_alien_species", "circle_problematic_species",
                                       "circle_alien_comments", "circle_problematic_comments"
                           
        )),
        tidyselect::starts_with("plot_focal")
        ) %>%
        # Remove the ones where rute is NA
        filter(!if_all(dplyr::matches("^rute_\\d+$"), is.na)) %>%
        dplyr::distinct()
      
    }
    
    
    # Write Excel with three sheets
    wb <- openxlsx::createWorkbook()
    openxlsx::addWorksheet(wb, "plots")
    openxlsx::addWorksheet(wb, "plot_species_long")
    
    if(any(grepl("circle", names(dat)))){
      openxlsx::addWorksheet(wb, "circles")
      openxlsx::addWorksheet(wb, "circle_species_long")
      
    }
    
    if(any(grepl("focal", names(dat)))){
      openxlsx::addWorksheet(wb, "focalspecies")

    }
    
    #openxlsx::addWorksheet(wb, "plot_species_wide")
    openxlsx::writeData(wb, sheet = "plots", dat_plot, na.string = "")
    openxlsx::writeData(wb, sheet = "plot_species_long", plot_species, na.string = "")
    
    if(any(grepl("circle", names(dat)))){
      openxlsx::writeData(wb, sheet = "circles", dat_circle, na.string = "")
      openxlsx::writeData(wb, sheet = "circle_species_long", circle_species, na.string = "")
    }
    
    if(any(grepl("focal", names(dat)))){
      openxlsx::writeData(wb, sheet = "focalspecies", dat_focal, na.string = "")
    }
    
    #openxlsx::writeData(wb, sheet = "plot_species_wide", plot_speciesw, na.string = "")
    openxlsx::saveWorkbook(wb, file = file.path(exports_folder, paste0(project, "_data_analyses.xlsx")), overwrite = TRUE)
  #}
 
}

