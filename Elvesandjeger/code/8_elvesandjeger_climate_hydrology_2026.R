#Effektovervaaking - elvesandjeger
#Climate, snow and river flow vs the elvesandjeger time series (exploratory)
#
#Data:
# - Data/klima_data_Kval_2023-2026.csv: daily mean temperature, MET station E6 Kvål
#   (SN67175), 4 Apr 2023 - 16 Sep 2026, gaps Feb-Apr 2025, no data Jul-Aug 2026
# - Data/Klima_data_Leinstrand_2020-2026.csv: daily precipitation, snow cover code
#   and snow depth, MET station Leinstrand (SN67150, downstream), 2020-01-01 - 2026-09-17
# - Data/NVE-Vannføring-dogn-v1.csv, NVE-Vannstand-dogn-v1.csv: daily discharge
#   (m3/s) and water level (m) at Gaulfoss (122.9.0), 2020-01-01 - 2026-09-16.
#   Reference values from NVE: mean annual flood 1008 m3/s, 5-year flood 1304,
#   10-year flood 1502. No year 2020-2026 reached the mean annual flood.
#
#Rationale: snowmelt drives the spring flood, and floods decide whether and for
#how long the sandbanks are under water. The threshold discharge at which the
#monitored sandbanks are inundated is not known, so discharge is used directly
#(peak and days above 300 / 500 m3/s) as an exposure index.
#
#Outputs (Data/Elvesandjeger/2026): yearly climate/hydrology summary, larvae per
#visit with exposure metrics, exploratory model results; figures in
#Figures/elvesandjeger.
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)
library(glmmTMB)
`%||%` <- function(x, y) if (is.null(x)) y else x   # glmmTMB print methods on R < 4.4

out_dir <- "./Elvesandjeger/2026"; fig_dir <- "../Figures/elvesandjeger"
ink <- "#0b0b0b"; ink2 <- "#52514e"; grid_col <- "#e6e5e1"
theme_viz <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = grid_col),
        axis.title = element_text(colour = ink2), plot.title = element_text(colour = ink, face = "bold"),
        plot.subtitle = element_text(colour = ink2), strip.text = element_text(colour = ink, face = "bold"),
        legend.position = "top")
stage_cols <- c("Stage 1" = "#2a78d6", "Stage 2" = "#eb6834", "Stage 3" = "#1baf7a")

#-------------------------------------------------------------------------------
# 1. Read the climate and hydrology data
#-------------------------------------------------------------------------------
# Temperature (Kvål)
k <- read.csv2("./klima_data_Kval_2023-2026.csv", fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
names(k) <- c("navn", "stasjon", "dato", "temp")
k <- k %>% filter(grepl("^\\d", dato)) %>%
  mutate(date = as.Date(dato, "%d.%m.%Y"), temp = as.numeric(temp)) %>% dplyr::select(date, temp)

# Precipitation and snow (Leinstrand). Snødekke: MET code 0 = bare, 1 = patchy, 3 = mostly, 4 = fully snow covered
l <- read.csv2("./Klima_data_Leinstrand_2020-2026.csv", fileEncoding = "UTF-8-BOM", stringsAsFactors = FALSE)
names(l) <- c("navn", "stasjon", "dato", "precip", "snow_cover", "snow_depth")
l <- l %>% filter(grepl("^\\d", dato)) %>%
  mutate(date = as.Date(dato, "%d.%m.%Y"), across(c(precip, snow_cover, snow_depth), as.numeric)) %>%
  dplyr::select(date, precip, snow_cover, snow_depth)

# Discharge and water level (NVE, Gaulfoss). The files have statistical tables
# after the daily series, so only lines starting with a date are read.
read_nve <- function(f, val) {
  x <- readLines(f, encoding = "UTF-8"); x <- x[grepl("^20[0-9]{2}-[0-9]{2}-[0-9]{2}", x)]
  p <- strsplit(x, ";")
  data.frame(date = as.Date(substr(sapply(p, `[`, 1), 1, 10)),
             value = as.numeric(sub(",", ".", sapply(p, `[`, 2)))) %>% setNames(c("date", val))
}
q <- read_nve("./NVE-Vannføring-dogn-v1.csv", "q")   # m3/s
h <- read_nve("./NVE-Vannstand-dogn-v1.csv", "h")   # m
q_ref <- c(middelflom = 1008, flom5 = 1304.4, flom10 = 1502)
range(q$date); sum(is.na(q$q))

daily <- q %>% left_join(h, by = "date") %>% left_join(l, by = "date") %>% left_join(k, by = "date") %>%
  mutate(year = as.integer(format(date, "%Y")), mon = as.integer(format(date, "%m")))
write.csv(daily, file.path(out_dir, "daily_climate_hydrology_2020-2026.csv"), row.names = FALSE)

#-------------------------------------------------------------------------------
# 2. Yearly summaries
#-------------------------------------------------------------------------------
yearly <- daily %>% group_by(year) %>% summarise(
  # hydrology
  q_max            = max(q), q_max_date = date[which.max(q)],
  spring_peak      = max(q[mon %in% 4:6]), spring_peak_date = date[mon %in% 4:6][which.max(q[mon %in% 4:6])],
  d_over300_AprJun = sum(q[mon %in% 4:6] > 300), d_over300_JulAug = sum(q[mon %in% 7:8] > 300),
  d_over500        = sum(q > 500), d_over_middelflom = sum(q > q_ref["middelflom"]),
  # snow
  snow_max_cm      = max(snow_depth, na.rm = TRUE), snow_days_JanMay = sum(snow_depth[mon <= 5] > 0, na.rm = TRUE),
  last_snow_date   = suppressWarnings(max(date[snow_depth > 0 & mon < 8], na.rm = TRUE)),
  # precipitation
  precip_MayAug    = sum(precip[mon %in% 5:8], na.rm = TRUE), precip_year = sum(precip, na.rm = TRUE),
  # temperature (Kvål, 2023-2026 only)
  temp_AprMay      = if (sum(!is.na(temp[mon %in% 4:5])) >= 45) mean(temp[mon %in% 4:5], na.rm = TRUE) else NA_real_,
  temp_June        = if (sum(!is.na(temp[mon == 6])) >= 20) mean(temp[mon == 6], na.rm = TRUE) else NA_real_,
  temp_JulAug      = if (sum(!is.na(temp[mon %in% 7:8])) >= 45) mean(temp[mon %in% 7:8], na.rm = TRUE) else NA_real_,
  n_days = n(), .groups = "drop")
# winter temperature Dec (prev year) - Feb, and winter snow
winter <- daily %>% mutate(wy = if_else(mon == 12, year + 1L, year)) %>% filter(mon %in% c(12, 1, 2)) %>%
  group_by(year = wy) %>% summarise(temp_DecFeb = if (sum(!is.na(temp)) >= 60) mean(temp, na.rm = TRUE) else NA_real_,
                                    snow_days_DecFeb = sum(snow_depth > 0, na.rm = TRUE), .groups = "drop")
yearly <- yearly %>% left_join(winter, by = "year")
print(as.data.frame(yearly %>% mutate(across(where(is.numeric), ~ round(.x, 1)))))
write.csv(yearly, file.path(out_dir, "climate_hydrology_yearly_2020-2026.csv"), row.names = FALSE)

#-------------------------------------------------------------------------------
# 3. Larvae per visit (all sites, and per site) with exposure before the visit
#-------------------------------------------------------------------------------
master <- read.csv2("./Elvesandjeger/elvesandjeger_obs_2015-2026_master.csv", stringsAsFactors = FALSE) %>%
  filter(year >= 2020, month %in% c("juni", "juli", "august"), stage %in% c("stad1", "stad2", "stad3"),
         site %in% c("Storr", "Kreg", "Forn", "Grav")) %>%
  mutate(date = as.Date(date), point_id = paste(N, E, date))

exposure <- function(d, prev) {
  w  <- daily[daily$date > prev & daily$date <= d, ]
  w14 <- daily[daily$date > d - 14 & daily$date <= d, ]
  w30 <- daily[daily$date > d - 30 & daily$date <= d, ]
  c(q_max_since_prev = max(w$q), d_over300_since_prev = sum(w$q > 300), q_max_14d = max(w14$q),
    precip_14d = sum(w14$precip, na.rm = TRUE), precip_since_prev = sum(w$precip, na.rm = TRUE),
    temp_30d = if (sum(!is.na(w30$temp)) >= 20) mean(w30$temp, na.rm = TRUE) else NA_real_)
}
add_exposure <- function(v) {
  v <- v %>% arrange(date) %>%
    mutate(prev = if_else(month == "juni", as.Date(paste0(year - 1, "-09-01")), lag(date)))   # June: since 1 Sep previous year
  v$prev[v$month == "juni"] <- as.Date(paste0(v$year[v$month == "juni"] - 1, "-09-01"))
  v$prev[is.na(v$prev)]     <- as.Date(paste0(v$year[is.na(v$prev)] - 1, "-09-01"))   # first visit of a series
  cbind(v, t(sapply(seq_len(nrow(v)), function(i) exposure(v$date[i], v$prev[i]))))
}
visits <- master %>% group_by(year, month) %>%
  summarise(date = median(date), n_points = n_distinct(point_id), larvae = sum(obs, na.rm = TRUE),
            stad1 = sum(obs[stage == "stad1"], na.rm = TRUE), stad2 = sum(obs[stage == "stad2"], na.rm = TRUE),
            stad3 = sum(obs[stage == "stad3"], na.rm = TRUE), .groups = "drop") %>% add_exposure()
print(as_tibble(visits) %>% mutate(across(where(is.numeric), ~ round(.x, 1))) %>% dplyr::select(-prev), n = Inf)
write.csv(visits, file.path(out_dir, "larvae_visits_exposure_2020-2026.csv"), row.names = FALSE)

site_visits <- master %>% filter(site != "Grav") %>% group_by(year, month, site) %>%
  summarise(date = median(date), n_points = n_distinct(point_id), larvae = sum(obs, na.rm = TRUE),
            stad1 = sum(obs[stage == "stad1"], na.rm = TRUE), .groups = "drop")
site_visits <- bind_rows(lapply(split(site_visits, site_visits$site), add_exposure))

#-------------------------------------------------------------------------------
# 4. Exploratory models: site-visit counts vs exposure (year as random effect)
#-------------------------------------------------------------------------------
sv <- site_visits %>% mutate(month = factor(month, levels = c("juni", "juli", "august")), yearf = factor(year),
                             site = factor(site), log_qmax14 = log(q_max_14d))
res <- list()
for (resp in c("larvae", "stad1")) {
  f0 <- as.formula(paste(resp, "~ month + (1 | site) + (1 | yearf)"))
  m0 <- glmmTMB(f0, family = nbinom2, data = sv)
  for (v in c("log_qmax14", "d_over300_since_prev", "precip_14d")) {
    m1 <- glmmTMB(update(f0, as.formula(paste(". ~ . +", v))), family = nbinom2, data = sv)
    s <- summary(m1)$coefficients$cond[v, ]
    res[[length(res) + 1]] <- data.frame(response = resp, predictor = v, estimate = s[1], se = s[2],
                                         p_LRT = anova(m0, m1)[["Pr(>Chisq)"]][2], row.names = NULL)
  }
}
res <- bind_rows(res); print(res)
write.csv(res, file.path(out_dir, "model_climate_hydrology_exploratory.csv"), row.names = FALSE)

#-------------------------------------------------------------------------------
# 5. Figures
#-------------------------------------------------------------------------------
vis_dates <- visits %>% distinct(year, month, date)
# 5a. Hydrograph, snow depth and precipitation with visit dates
dl <- daily %>% dplyr::select(date, q, snow_depth, precip) %>%
  pivot_longer(-date, names_to = "var") %>%
  mutate(var = factor(var, levels = c("q", "snow_depth", "precip"),
                      labels = c("Discharge Gaulfoss (m³/s)", "Snow depth Leinstrand (cm)", "Precipitation Leinstrand (mm/day)")))
p_hyd <- ggplot(dl, aes(x = date, y = value)) +
  geom_line(data = dl %>% filter(var != "Precipitation Leinstrand (mm/day)"), colour = "#2a78d6", linewidth = 0.4) +
  geom_col(data = dl %>% filter(var == "Precipitation Leinstrand (mm/day)"), fill = "#2a78d6", width = 1) +
  geom_hline(data = data.frame(var = factor("Discharge Gaulfoss (m³/s)", levels = levels(dl$var)), y = c(300, 500, 1008)),
             aes(yintercept = y), colour = ink2, linetype = c("dotted", "dashed", "solid"), linewidth = 0.4) +
  geom_vline(data = vis_dates, aes(xintercept = date), colour = "#eb6834", linewidth = 0.4, alpha = 0.8) +
  facet_wrap(~ var, ncol = 1, scales = "free_y") +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(title = "River flow, snow and precipitation 2020–2026, with elvesandjeger visits (orange)",
       subtitle = "Discharge reference lines: 300 (dotted), 500 (dashed) m³/s and mean annual flood 1008 m³/s (solid)", x = NULL, y = NULL) + theme_viz
ggsave(file.path(fig_dir, "hydrology_climate_2020-2026.png"), p_hyd, width = 12, height = 8, dpi = 200, bg = "white")

# 5b. Larvae per visit vs peak discharge in the 14 days before the visit
vl <- visits %>% pivot_longer(c(stad1, stad2, stad3), names_to = "stage", values_to = "n") %>%
  mutate(stage = factor(stage, levels = c("stad1", "stad2", "stad3"), labels = names(stage_cols)),
         month = factor(month, levels = c("juni", "juli", "august")))
p_q <- ggplot(vl, aes(x = q_max_14d, y = n + 1, colour = stage, shape = month)) +
  geom_point(size = 3) + geom_text(aes(label = year), vjust = -0.9, size = 2.8, show.legend = FALSE) +
  scale_colour_manual(values = stage_cols, name = NULL) + scale_shape_discrete(name = "Visit") +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Larvae counted per visit vs peak discharge in the 14 days before the visit",
       subtitle = "all sites, 2020–2026", x = "Peak discharge, 14 days before visit (m³/s)", y = "Larvae counted + 1 (log scale)") + theme_viz
ggsave(file.path(fig_dir, "larvae_vs_peak_discharge_2020-2026.png"), p_q, width = 9, height = 5.5, dpi = 200, bg = "white")

# 5c. Spring flood and snowmelt timing per year, with the June visit
p_spring <- yearly %>% dplyr::select(year, spring_peak_date, last_snow_date) %>%
  left_join(vis_dates %>% filter(month == "juni") %>% dplyr::select(year, june_visit = date), by = "year") %>%
  pivot_longer(-year, names_to = "event", values_to = "date") %>% filter(!is.na(date)) %>%
  mutate(doy = as.integer(format(date, "%j")), event = recode(event, spring_peak_date = "Spring flood peak", last_snow_date = "Last day with snow", june_visit = "June visit")) %>%
  ggplot(aes(x = doy, y = factor(year), colour = event)) +
  geom_point(size = 3.5) +
  scale_colour_manual(values = c("Spring flood peak" = "#2a78d6", "Last day with snow" = "#9a9891", "June visit" = "#eb6834"), name = NULL) +
  scale_x_continuous(breaks = c(60, 91, 121, 152, 182), labels = c("1 Mar", "1 Apr", "1 May", "1 Jun", "1 Jul")) +
  labs(title = "Snowmelt, spring flood and the June visit", x = NULL, y = NULL) + theme_viz
ggsave(file.path(fig_dir, "snowmelt_spring_flood_timing.png"), p_spring, width = 8, height = 4.5, dpi = 200, bg = "white")
