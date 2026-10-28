#Effektovervaaking - elvesandjeger
#Effect of lupin clearing on elvesandjeger, 2026
#
#Part 1: lupin clearing per site and year 2020-2026 (area cleared, number of
#        lupins removed, lupins removed per m2) from the cleaned clearing polygons
#Part 2: analysis data set - each 2026 survey polygon linked to the lupin clearing
#        polygon it lies in (largest overlap)
#Part 3: models at the survey-polygon level: larvae (stage 1-3) in 2026 as a
#        function of clearing in 2025, controlling for month, substrate,
#        vegetation cover, trampling (slitasje) and site, with the searched area as
#        offset. Negative binomial GLMM (glmmTMB) with a random intercept per
#        lupin polygon (the same patches are visited in June, July and August).
#        Design: the effect analysis uses Kregnesteigen and Storrønningen, the two
#        sites with both clearing polygons and beetle observations. The Fornes
#        survey polygons outside the clearing polygons are used as a control
#        group (no lupin clearing); Fornes polygons overlapping a clearing polygon
#        are left out. Gravråk has only 2 observations and is
#        left out. Clearing done in 2026 is not used.
#Part 4: models at the lupin-polygon level (August, Kregnesteigen + Storrønningen):
#        larvae summed per clearing polygon, zeros for polygons without
#        observations -> NB / zero-inflated NB.
#Part 5: effect plots
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(sf)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(scales)
library(glmmTMB)
library(DHARMa)
library(emmeans)

sf_use_s2(FALSE)
`%||%` <- function(x, y) if (is.null(x)) y else x   # needed by glmmTMB print methods on R < 4.4
fig_dir <- "../Figures"
out_dir <- "./Elvesandjeger/2026"

# plotting theme / colours
ink <- "#0b0b0b"; ink2 <- "#52514e"; grid_col <- "#e6e5e1"
luket_cols <- c(Nei = "#9a9891", Delvis = "#eda100", Ja = "#2a78d6")
month_cols <- c(juni = "#2a78d6", juli = "#eb6834", august = "#1baf7a")
theme_viz <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = grid_col),
        axis.title = element_text(colour = ink2), plot.title = element_text(colour = ink, face = "bold"),
        plot.subtitle = element_text(colour = ink2), strip.text = element_text(colour = ink, face = "bold"),
        legend.position = "top")

# helper: coefficient table from a glmmTMB model
coef_tab <- function(m, name) {
  s <- summary(m)$coefficients$cond
  data.frame(model = name, term = rownames(s), estimate = s[, 1], se = s[, 2], z = s[, 3], p = s[, 4],
             rate_ratio = exp(s[, 1]), row.names = NULL)
}

#===============================================================================
# Part 1. Lupin clearing per site and year
#===============================================================================
lup <- st_read("./Lupinluking_2026/Lupinluking_2025_2026_clean.shp", quiet = TRUE) %>% st_make_valid()
lup_df <- st_drop_geometry(lup)

years <- 20:26
# Long table: one row per polygon piece and year.
# Antall_XX (lupins removed) is recorded per original polygon and is repeated on
# every piece of a polygon that was split in the overlay (Lok_25 for 2020-2025,
# Lok_26 for 2026). Area is per piece. So: area is summed over pieces, Antall is
# taken once per original polygon.
clear_long <- lup_df %>%
  dplyr::select(tempID, site_name, Lok_25, Lok_26, new_26, area_m2, matches("^(Luket|Antall)_2[0-6]$")) %>%
  pivot_longer(matches("^(Luket|Antall)_"), names_to = c(".value", "yr"), names_pattern = "(Luket|Antall)_(\\d\\d)") %>%
  mutate(year = 2000L + as.integer(yr),
         Luket = factor(Luket, levels = c("Nei", "Delvis", "Ja")),
         poly_key = if_else(year == 2026, Lok_26, Lok_25))          # original polygon the Antall belongs to

clear_site <- clear_long %>%
  filter(site_name != "Follstadoya") %>%                              # no beetle monitoring there
  group_by(site_name, year) %>%
  summarise(
    area_total   = sum(area_m2),
    area_ja      = sum(area_m2[Luket == "Ja"]),
    area_delvis  = sum(area_m2[Luket == "Delvis"]),
    area_cleared = area_ja + area_delvis,
    n_poly_cleared = n_distinct(poly_key[Luket %in% c("Ja", "Delvis")]),
    antall       = sum(distinct(pick(poly_key, Antall))$Antall, na.rm = TRUE),
    .groups = "drop") %>%
  mutate(lupins_per_m2 = ifelse(area_cleared > 0, antall / area_cleared, NA_real_),
         site_name = recode(site_name, Storronningen = "Storrønningen", Gravrak = "Gravråk"))
print(as.data.frame(clear_site), digits = 3)
write.csv(clear_site, file.path(out_dir, "lupin_clearing_by_site_2020-2026.csv"), row.names = FALSE)

# Plot 1a: area cleared per site and year (Ja / Delvis stacked)
p_area <- clear_site %>%
  dplyr::select(site_name, year, Ja = area_ja, Delvis = area_delvis) %>%
  pivot_longer(c(Ja, Delvis), names_to = "Luket", values_to = "area") %>%
  mutate(Luket = factor(Luket, levels = c("Delvis", "Ja"))) %>%
  ggplot(aes(x = year, y = area, fill = Luket)) +
  geom_col(width = 0.75, colour = "white") +
  facet_wrap(~ site_name, scales = "free_y") +
  scale_fill_manual(values = luket_cols[c("Delvis", "Ja")], name = "Luket") +
  scale_x_continuous(breaks = 2020:2026) +
  scale_y_continuous(labels = label_comma()) +
  labs(title = "Area of lupin clearing per site, 2020–2026", x = NULL, y = "Area cleared (m²)") +
  theme_viz
ggsave(file.path(fig_dir, "lupiner/area_cleared_by_site_2020-2026.png"), p_area, width = 10, height = 6, dpi = 200, bg = "white")

# Plot 1b: number of lupins removed and lupins per m2 cleared
p_ant <- ggplot(clear_site, aes(x = year, y = antall)) +
  geom_col(width = 0.75, fill = "#2a78d6") +
  facet_wrap(~ site_name, scales = "free_y") +
  scale_x_continuous(breaks = 2020:2026) + scale_y_continuous(labels = label_comma()) +
  labs(title = "Number of lupins removed per site, 2020–2026", x = NULL, y = "Lupins removed (Antall)") +
  theme_viz
ggsave(file.path(fig_dir, "lupiner/lupins_removed_by_site_2020-2026.png"), p_ant, width = 10, height = 6, dpi = 200, bg = "white")

p_dens <- ggplot(clear_site %>% filter(!is.na(lupins_per_m2)), aes(x = year, y = lupins_per_m2, colour = site_name)) +
  geom_line(linewidth = 0.9) + geom_point(size = 2.5) +
  scale_colour_manual(values = c("Storrønningen" = "#2a78d6", "Kregnesteigen" = "#eb6834", "Fornes" = "#1baf7a", "Gravråk" = "#eda100"), name = NULL) +
  scale_x_continuous(breaks = 2020:2026) +
  labs(title = "Lupin density in cleared areas (lupins removed per m² cleared)", x = NULL, y = "Lupins per m² cleared") +
  theme_viz
ggsave(file.path(fig_dir, "lupiner/lupin_density_cleared_by_site_2020-2026.png"), p_dens, width = 9, height = 5, dpi = 200, bg = "white")

# Plot 1c: all sites together - is less clearing needed over time?
clear_tot <- clear_site %>% group_by(year) %>%
  summarise(area_cleared = sum(area_cleared), antall = sum(antall), .groups = "drop") %>%
  mutate(lupins_per_m2 = antall / area_cleared)
print(clear_tot)
write.csv(clear_tot, file.path(out_dir, "lupin_clearing_total_2020-2026.csv"), row.names = FALSE)

# 1d. Are the clearing operations controlling the invasion? Lupin density in a
#     polygon (lupins removed per m2, in years it was cleared) as a function of
#     whether it was cleared the year before, and of the number of previous
#     years it was cleared. NB GLMM on Antall with the polygon area as offset,
#     year and site as fixed effects, random intercept per polygon.
#     Units are the original polygons (pieces of a split polygon are summed;
#     for 2026 the previous-year status is that of the largest piece).
clear_panel <- clear_long %>%
  filter(site_name != "Follstadoya") %>%
  arrange(tempID, year) %>% group_by(tempID) %>%
  mutate(Luket_prev = lag(Luket),
         n_prev_cleared = lag(cumsum(Luket %in% c("Ja", "Delvis")), default = 0L)) %>% ungroup() %>%
  filter(!is.na(poly_key)) %>%
  group_by(site_name, unit = poly_key, year) %>%
  summarise(area = sum(area_m2), Antall = first(Antall), Luket = first(Luket),
            Luket_prev = Luket_prev[which.max(area_m2)], n_prev_cleared = max(n_prev_cleared), .groups = "drop") %>%
  mutate(lupins_per_m2 = Antall / area,
         Luket_prev = factor(Luket_prev, levels = c("Nei", "Delvis", "Ja")),
         site = factor(site_name), yearf = factor(year))
cleared <- clear_panel %>% filter(Luket %in% c("Ja", "Delvis"), year >= 2021, !is.na(Luket_prev))
nrow(cleared); table(cleared$Luket_prev, cleared$year)
write.csv(clear_panel, file.path(out_dir, "lupin_clearing_polygon_panel_2020-2026.csv"), row.names = FALSE)

lup_prev <- glmmTMB(Antall ~ Luket_prev + yearf + site + offset(log(area)) + (1 | unit), family = nbinom2, data = cleared)
lup_nprev <- glmmTMB(Antall ~ n_prev_cleared + yearf + site + offset(log(area)) + (1 | unit), family = nbinom2, data = cleared)
summary(lup_prev)$coefficients$cond
anova(update(lup_prev, . ~ . - Luket_prev), lup_prev)
summary(lup_nprev)$coefficients$cond["n_prev_cleared", ]
em_prev <- emmeans(lup_prev, ~ Luket_prev, type = "response", offset = 0); print(em_prev)
em_year <- emmeans(lup_prev, ~ yearf, type = "response", offset = 0); print(em_year)
write.csv(bind_rows(
  data.frame(model = "lupins_vs_cleared_prev_year", term = rownames(summary(lup_prev)$coefficients$cond), summary(lup_prev)$coefficients$cond, row.names = NULL),
  data.frame(model = "lupins_vs_n_prev_years", term = rownames(summary(lup_nprev)$coefficients$cond), summary(lup_nprev)$coefficients$cond, row.names = NULL)),
  file.path(out_dir, "model_coefficients_lupin_density.csv"), row.names = FALSE)

p_prev <- ggplot(cleared, aes(x = Luket_prev, y = lupins_per_m2 + 0.01, colour = Luket_prev)) +
  geom_jitter(width = 0.2, alpha = 0.4, size = 1.5) +
  geom_pointrange(data = as.data.frame(em_prev), aes(y = response, ymin = asymp.LCL, ymax = asymp.UCL), colour = ink, linewidth = 0.9, size = 0.9) +
  scale_colour_manual(values = luket_cols, guide = "none") +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Lupin density in cleared polygons vs clearing the year before",
       subtitle = "points = polygon-years 2021–2026 (+0.01 to show zeros); black = NB GLMM mean ± 95 % CI",
       x = "Cleared the year before", y = "Lupins removed per m² (log scale)") + theme_viz
ggsave(file.path(fig_dir, "lupiner/lupin_density_vs_cleared_previous_year.png"), p_prev, width = 8, height = 5, dpi = 200, bg = "white")

#===============================================================================
# Part 2. Analysis data set: 2026 survey polygons linked to lupin polygons
#===============================================================================
obs <- st_read("./Elvesandjeger/2026/Elvesandjeger.shp", quiet = TRUE) %>%
  st_transform(25832) %>% st_make_valid() %>%
  rename(stad1 = larve_stad, stad2 = larve_st_1, stad3 = larve_st_2, site_code = lokalitet_) %>%
  mutate(area_m2 = as.numeric(st_area(geometry)), larvae = stad1 + stad2 + stad3,
         site = recode(tolower(site_code), forn = "Fornes", grav = "Gravråk", kreg = "Kregnesteigen", stor = "Storrønningen"))
st_agr(lup) <- "constant"; st_agr(obs) <- "constant"

# lupin polygon with the largest overlap
best <- st_intersection(obs %>% dplyr::select(GlobalID), lup %>% dplyr::select(tempID)) %>%
  mutate(a_in = as.numeric(st_area(geometry))) %>% st_drop_geometry() %>%
  group_by(GlobalID) %>% slice_max(a_in, n = 1, with_ties = FALSE) %>% ungroup()

dat <- obs %>% st_drop_geometry() %>%
  left_join(best, by = "GlobalID") %>%
  left_join(lup_df %>% dplyr::select(tempID, Lokalitet, Lok_26, Luket_24, Luket_25, Luket_26, Antall_24, Antall_25, Antall_luk, lup_area = area_m2), by = "tempID") %>%
  mutate(
    in_lupin_poly = !is.na(tempID),
    # survey polygons outside every clearing polygon (Fornes sandbank): never cleared
    across(c(Luket_24, Luket_25, Luket_26), ~ if_else(in_lupin_poly, .x, "Nei")),
    across(c(Antall_24, Antall_25, Antall_luk), ~ if_else(in_lupin_poly, .x, 0L)),
    patch_id = if_else(in_lupin_poly, paste0("lup_", tempID), paste0("out_", GlobalID)),
    lupins25_per_m2 = if_else(in_lupin_poly & Luket_25 != "Nei", Antall_25 / lup_area, 0),
    across(c(Luket_24, Luket_25, Luket_26), ~ factor(.x, levels = c("Nei", "Delvis", "Ja"))),
    maaned    = factor(maaned, levels = c("juni", "juli", "august")),
    site      = factor(site),
    substrat  = factor(substrat, levels = c("sand", "blanding", "silt")),
    slitasje  = as.numeric(slitasje), slitasje = if_else(slitasje > 5, NA_real_, slitasje),  # 99 = not recorded
    veg_frac  = vegetasjon / 100,
    log_area  = log(area_m2),
    # clearing history 2020-2025 (Antall_luk counts 2020-2026; 2026 clearing is not used)
    years_cleared_20_25 = Antall_luk - as.integer(Luket_26 == "Ja"),
    # analysis groups: effect sites by 2025 clearing status; Fornes observations
    # outside every clearing polygon as control (no lupin management)
    group = factor(case_when(site == "Fornes" & !in_lupin_poly ~ "Control",
                             site %in% c("Kregnesteigen", "Storrønningen") ~ as.character(Luket_25),
                             TRUE ~ NA_character_),
                   levels = c("Control", "Nei", "Delvis", "Ja"))
  )
nrow(dat) #133
table(dat$group, dat$maaned, useNA = "ifany")
table(dat$Luket_25, dat$maaned)
table(dat$in_lupin_poly, dat$site)
write.csv(dat, file.path(out_dir, "elvesandjeger_2026_analysis_data.csv"), row.names = FALSE)

# Overdispersion / zeros in the response
cat("larvae: zeros =", sum(dat$larvae == 0), "of", nrow(dat), "; var/mean =", round(var(dat$larvae) / mean(dat$larvae), 1), "\n")

#===============================================================================
# Part 3. Survey-polygon level models
#===============================================================================
# Effect sites: Kregnesteigen and Storrønningen (1 polygon without slitasje dropped)
dm <- dat %>% filter(site %in% c("Kregnesteigen", "Storrønningen"), !is.na(slitasje)) %>% droplevels()
nrow(dm)
table(dm$Luket_25, dm$maaned)

# 3a. Distribution: Poisson vs NB2 vs NB1 vs zero-inflated NB
f_full <- larvae ~ Luket_25 + maaned + substrat + veg_frac + slitasje + site + offset(log_area) + (1 | patch_id)
m_pois <- glmmTMB(f_full, family = poisson,  data = dm)
m_nb2  <- glmmTMB(f_full, family = nbinom2,  data = dm)
m_nb1  <- glmmTMB(f_full, family = nbinom1,  data = dm)
m_zinb <- glmmTMB(f_full, family = nbinom2, ziformula = ~ 1, data = dm)
aic_tab <- AIC(m_pois, m_nb2, m_nb1, m_zinb) %>% tibble::rownames_to_column("model") %>% arrange(AIC)
print(aic_tab)

sim_pois <- simulateResiduals(m_pois); testDispersion(sim_pois)   # strong overdispersion expected
sim_nb2  <- simulateResiduals(m_nb2)
png(file.path(fig_dir, "elvesandjeger/dharma_nb2_survey_level_2026.png"), width = 1600, height = 800, res = 150)
plot(sim_nb2); dev.off()
testDispersion(sim_nb2); testZeroInflation(sim_nb2); testOutliers(sim_nb2)

# 3b. Main model (NB2). Effect of clearing in 2025.
summary(m_nb2)
# Is the effect of 2025 clearing different between months (June = overwintered
# cohort, July/August = the new cohort)?
m_nb2_int <- update(m_nb2, . ~ . + Luket_25:maaned)
anova(m_nb2, m_nb2_int)
# Does clearing add anything beyond the covariates?
m_nb2_noclear <- update(m_nb2, . ~ . - Luket_25)
anova(m_nb2_noclear, m_nb2)

# Predicted larval density (per m2 searched) by clearing status, averaged over the
# other covariates; offset = 0 -> rate per 1 m2
em25 <- emmeans(m_nb2, ~ Luket_25, type = "response", offset = 0)
print(em25)
print(contrast(em25, method = "trt.vs.ctrl", ref = "Nei"), infer = TRUE)   # ratios Ja/Nei, Delvis/Nei
em25_month <- emmeans(m_nb2_int, ~ Luket_25 | maaned, type = "response", offset = 0)
print(em25_month)

# 3c. Alternative descriptions of clearing
#   - clearing history: number of years cleared 2020-2025
m_hist  <- update(m_nb2, . ~ . - Luket_25 + years_cleared_20_25)
#   - clearing intensity in 2025: lupins removed per m2 of the polygon
m_int25 <- update(m_nb2, . ~ . - Luket_25 + lupins25_per_m2)
#   - both 2024 and 2025 clearing
m_2425  <- update(m_nb2, . ~ . + Luket_24)
aic_alt <- AIC(m_nb2, m_nb2_noclear, m_hist, m_int25, m_2425) %>% tibble::rownames_to_column("model") %>% arrange(AIC)
print(aic_alt)
summary(m_hist)$coefficients$cond["years_cleared_20_25", ]
summary(m_int25)$coefficients$cond["lupins25_per_m2", ]

# 3d. Covariate effects (substrate, vegetation cover, trampling) - LRTs
anova(update(m_nb2, . ~ . - substrat), m_nb2)
anova(update(m_nb2, . ~ . - veg_frac), m_nb2)
anova(update(m_nb2, . ~ . - slitasje), m_nb2)

# 3e. Control group: Fornes observations outside all clearing polygons vs the
#     effect sites by clearing status (site cannot be included - it is confounded
#     with the control group)
dc <- dat %>% filter(!is.na(group), !is.na(slitasje)) %>% droplevels()
table(dc$group, dc$maaned)
m_ctrl <- glmmTMB(larvae ~ group + maaned + substrat + veg_frac + slitasje + offset(log_area) + (1 | patch_id),
                  family = nbinom2, data = dc)
summary(m_ctrl)$coefficients$cond
em_ctrl <- emmeans(m_ctrl, ~ group, type = "response", offset = 0); print(em_ctrl)
print(contrast(em_ctrl, method = "trt.vs.ctrl", ref = "Control"), infer = TRUE)

# 3f. By larval stage (adults are too few - 67 in total, 49 of them in June - and are not modelled)
stage_models <- lapply(c(stad1 = "stad1", stad2 = "stad2", stad3 = "stad3"), function(st) {
  f <- as.formula(paste(st, "~ Luket_25 + maaned + substrat + veg_frac + slitasje + site + offset(log_area) + (1 | patch_id)"))
  glmmTMB(f, family = nbinom2, data = dm)
})
stage_lrt <- sapply(stage_models, function(m) anova(update(m, . ~ . - Luket_25), m)[["Pr(>Chisq)"]][2])
print(stage_lrt)
stage_coefs <- bind_rows(lapply(names(stage_models), function(st) coef_tab(stage_models[[st]], paste0("nb2_", st))))
write.csv(stage_coefs, file.path(out_dir, "model_coefficients_by_stage_2026.csv"), row.names = FALSE)

# Save coefficient tables
coefs <- bind_rows(coef_tab(m_nb2, "nb2_main"), coef_tab(m_nb2_int, "nb2_month_interaction"),
                   coef_tab(m_hist, "nb2_years_cleared"), coef_tab(m_int25, "nb2_intensity_2025"),
                   coef_tab(m_2425, "nb2_luket24_25"), coef_tab(m_ctrl, "nb2_with_control"))
write.csv(coefs, file.path(out_dir, "model_coefficients_survey_level_2026.csv"), row.names = FALSE)
write.csv(bind_rows(aic_tab, aic_alt), file.path(out_dir, "model_aic_survey_level_2026.csv"), row.names = FALSE)

#===============================================================================
# Part 4. Lupin-polygon level (August 2026): zeros included
#===============================================================================
aug <- dat %>% filter(maaned == "august", in_lupin_poly) %>%
  group_by(tempID) %>% summarise(larvae = sum(larvae), n_survey = n(), .groups = "drop")
L <- lup_df %>%
  filter(site_name %in% c("Kregnesteigen", "Storronningen")) %>%
  left_join(aug, by = "tempID") %>%
  mutate(larvae = coalesce(larvae, 0), occupied = as.integer(larvae > 0),
         across(c(Luket_24, Luket_25, Luket_26), ~ factor(.x, levels = c("Nei", "Delvis", "Ja"))),
         site = factor(recode(site_name, Storronningen = "Storrønningen", Gravrak = "Gravråk")),
         log_area = log(area_m2),
         years_cleared_20_25 = Antall_luk - as.integer(Luket_26 == "Ja"))
nrow(L); table(L$Luket_25, L$occupied)
cat("lupin-polygon level: zeros =", sum(L$larvae == 0), "of", nrow(L), "\n")

# NB vs zero-inflated NB vs hurdle (truncated NB for counts > 0, binomial for occupancy)
L_nb   <- glmmTMB(larvae ~ Luket_25 + site + offset(log_area), family = nbinom2, data = L)
L_zinb <- glmmTMB(larvae ~ Luket_25 + site + offset(log_area), ziformula = ~ 1, family = nbinom2, data = L)
L_zinb2 <- glmmTMB(larvae ~ Luket_25 + site + offset(log_area), ziformula = ~ Luket_25, family = nbinom2, data = L)
L_hurdle_occ <- glm(occupied ~ Luket_25 + site + log_area, family = binomial, data = L)
L_hurdle_cnt <- glmmTMB(larvae ~ Luket_25 + site + offset(log_area), family = truncated_nbinom2, data = L %>% filter(larvae > 0))
print(AIC(L_nb, L_zinb, L_zinb2) %>% tibble::rownames_to_column("model") %>% arrange(AIC))
sim_L <- simulateResiduals(L_zinb); testZeroInflation(sim_L); testDispersion(sim_L)
summary(L_zinb)
summary(L_hurdle_occ)$coefficients
summary(L_hurdle_cnt)$coefficients$cond
em_L <- emmeans(L_zinb, ~ Luket_25, type = "response", offset = 0); print(em_L)
em_occ <- emmeans(L_hurdle_occ, ~ Luket_25, type = "response"); print(em_occ)
# history
L_hist <- glmmTMB(larvae ~ years_cleared_20_25 + site + offset(log_area), ziformula = ~ 1, family = nbinom2, data = L)
summary(L_hist)$coefficients$cond
write.csv(bind_rows(coef_tab(L_zinb, "zinb_lupinpoly_aug"), coef_tab(L_hist, "zinb_lupinpoly_years_cleared"),
                    coef_tab(L_hurdle_cnt, "trunc_nb_lupinpoly_counts")),
          file.path(out_dir, "model_coefficients_lupinpoly_level_2026.csv"), row.names = FALSE)

#===============================================================================
# Part 5. Effect plots
#===============================================================================
# 5a. Observed larval density per survey polygon by clearing status and month
p_raw <- ggplot(dm, aes(x = Luket_25, y = larvae / area_m2, colour = Luket_25)) +
  geom_jitter(width = 0.2, alpha = 0.7, size = 2) +
  stat_summary(fun = median, geom = "crossbar", width = 0.5, colour = ink, linewidth = 0.4) +
  facet_wrap(~ maaned) +
  scale_colour_manual(values = luket_cols, guide = "none") +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Observed larval density in 2026 survey polygons by lupin clearing in 2025",
       subtitle = "points = survey polygons, bar = median", x = "Luket 2025", y = "Larvae per m² searched (log scale)") +
  theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_density_vs_luket25_raw.png"), p_raw, width = 10, height = 5, dpi = 200, bg = "white")

# 5b. Model-predicted density by clearing status (main model) and by month (interaction model)
em_df <- as.data.frame(em25) %>% mutate(maaned = "all months (main model)")
em_m  <- as.data.frame(em25_month) %>% mutate(maaned = as.character(maaned))
pred <- bind_rows(em_df, em_m) %>%
  mutate(maaned = factor(maaned, levels = c("all months (main model)", "juni", "juli", "august")))
p_eff <- ggplot(pred, aes(x = Luket_25, y = response, colour = Luket_25)) +
  geom_pointrange(aes(ymin = asymp.LCL, ymax = asymp.UCL), linewidth = 0.8, size = 0.8) +
  facet_wrap(~ maaned, nrow = 1) +
  scale_colour_manual(values = luket_cols, guide = "none") +
  scale_y_log10() +
  labs(title = "Predicted larval density in 2026 by lupin clearing in 2025",
       subtitle = "NB GLMM; mean ± 95 % CI at average substrate, vegetation cover and trampling",
       x = "Luket 2025", y = "Larvae per m² searched (log scale)") +
  theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_density_vs_luket25_model.png"), p_eff, width = 11, height = 4.5, dpi = 200, bg = "white")

# 5c. Clearing history: predicted density vs number of years cleared
nd <- expand.grid(years_cleared_20_25 = 0:6, maaned = "august", substrat = "sand", veg_frac = median(dm$veg_frac),
                  slitasje = median(dm$slitasje), site = "Storrønningen", log_area = 0, patch_id = NA)
pr <- predict(m_hist, newdata = nd, type = "link", se.fit = TRUE, re.form = NA)
nd$fit <- exp(pr$fit); nd$lo <- exp(pr$fit - 1.96 * pr$se.fit); nd$hi <- exp(pr$fit + 1.96 * pr$se.fit)
p_hist <- ggplot(nd, aes(x = years_cleared_20_25, y = fit)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#cde2fb") + geom_line(colour = "#2a78d6", linewidth = 1) +
  geom_jitter(data = dm, aes(x = years_cleared_20_25, y = larvae / area_m2), width = 0.15, alpha = 0.4, size = 1.5, colour = ink2) +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Larval density in 2026 vs number of years the patch was cleared (2020–2025)",
       subtitle = "line = NB GLMM prediction (August, sand, Storrønningen, median vegetation and trampling); points = survey polygons",
       x = "Years cleared 2020–2025", y = "Larvae per m² searched (log scale)") +
  theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_density_vs_years_cleared.png"), p_hist, width = 9, height = 5, dpi = 200, bg = "white")

# 5d. Control group comparison
p_ctrl <- as.data.frame(em_ctrl) %>%
  ggplot(aes(x = group, y = response, colour = group)) +
  geom_pointrange(aes(ymin = asymp.LCL, ymax = asymp.UCL), linewidth = 0.8, size = 0.8) +
  scale_colour_manual(values = c(Control = "#1baf7a", luket_cols), guide = "none") +
  scale_y_log10() +
  labs(title = "Larval density 2026: control (Fornes, no clearing) vs clearing status 2025 at Kregnesteigen/Storrønningen",
       subtitle = "NB GLMM; mean ± 95 % CI", x = NULL, y = "Larvae per m² searched (log scale)") +
  theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_density_control_vs_luket25.png"), p_ctrl, width = 8, height = 5, dpi = 200, bg = "white")

# 5e. Covariates: predicted density vs vegetation cover and trampling
pred_cov <- function(var, values) {
  nd <- data.frame(Luket_25 = "Ja", maaned = "august", substrat = "sand", veg_frac = median(dm$veg_frac),
                   slitasje = median(dm$slitasje), site = "Storrønningen", log_area = 0, patch_id = NA)
  nd <- nd[rep(1, length(values)), ]; nd[[var]] <- values
  pr <- predict(m_nb2, newdata = nd, type = "link", se.fit = TRUE, re.form = NA)
  nd %>% mutate(fit = exp(pr$fit), lo = exp(pr$fit - 1.96 * pr$se.fit), hi = exp(pr$fit + 1.96 * pr$se.fit))
}
pv <- pred_cov("veg_frac", seq(0, 0.75, 0.05)); ps <- pred_cov("slitasje", 1:5)
p_veg <- ggplot(pv, aes(x = veg_frac * 100, y = fit)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#cde2fb") + geom_line(colour = "#2a78d6", linewidth = 1) +
  geom_jitter(data = dm, aes(x = vegetasjon, y = larvae / area_m2), width = 2, alpha = 0.4, size = 1.5, colour = ink2) +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Vegetation cover", x = "Vegetation cover (%)", y = "Larvae per m² searched (log scale)") + theme_viz
p_sli <- ggplot(ps, aes(x = slitasje, y = fit)) +
  geom_ribbon(aes(ymin = lo, ymax = hi), fill = "#cde2fb") + geom_line(colour = "#2a78d6", linewidth = 1) +
  geom_jitter(data = dm, aes(x = slitasje, y = larvae / area_m2), width = 0.15, alpha = 0.4, size = 1.5, colour = ink2) +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Trampling (slitasje)", x = "Slitasje (1 = none, 5 = heavy)", y = NULL) + theme_viz
p_sub <- as.data.frame(emmeans(m_nb2, ~ substrat, type = "response", offset = 0)) %>%
  ggplot(aes(x = substrat, y = response)) +
  geom_pointrange(aes(ymin = asymp.LCL, ymax = asymp.UCL), colour = "#2a78d6", linewidth = 0.8, size = 0.8) +
  scale_y_log10() + labs(title = "Substrate", x = NULL, y = NULL) + theme_viz
png(file.path(fig_dir, "elvesandjeger/larvae26_covariate_effects.png"), width = 2400, height = 800, res = 200, bg = "white")
gridExtra::grid.arrange(p_veg, p_sli, p_sub, ncol = 3)
dev.off()

# 5f. Per-stage effect of clearing 2025 (rate ratios with 95 % CI)
p_stage <- stage_coefs %>%
  filter(term %in% c("Luket_25Ja", "Luket_25Delvis", "veg_frac", "slitasje", "substratblanding", "substratsilt")) %>%
  mutate(stage = recode(model, nb2_stad1 = "Stage 1", nb2_stad2 = "Stage 2", nb2_stad3 = "Stage 3"),
         term = recode(term, Luket_25Ja = "Cleared 2025 (vs not)", Luket_25Delvis = "Partly cleared 2025 (vs not)",
                       veg_frac = "Vegetation cover (per +10 %)", slitasje = "Trampling (per class)",
                       substratblanding = "Blanding (vs sand)", substratsilt = "Silt (vs sand)"),
         estimate = if_else(term == "Vegetation cover (per +10 %)", estimate / 10, estimate),
         se = if_else(term == "Vegetation cover (per +10 %)", se / 10, se),
         rr = exp(estimate), lo = exp(estimate - 1.96 * se), hi = exp(estimate + 1.96 * se)) %>%
  ggplot(aes(x = rr, y = term, colour = stage)) +
  geom_vline(xintercept = 1, colour = ink2, linetype = "dashed") +
  geom_pointrange(aes(xmin = lo, xmax = hi), position = position_dodge(width = 0.6), linewidth = 0.7) +
  scale_colour_manual(values = c("Stage 1" = "#2a78d6", "Stage 2" = "#eb6834", "Stage 3" = "#1baf7a"), name = NULL) +
  scale_x_log10() +
  labs(title = "Effects on larval density in 2026 by larval stage", subtitle = "NB GLMM rate ratios ± 95 % CI, Kregnesteigen + Storrønningen",
       x = "Rate ratio (log scale)", y = NULL) + theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_effects_by_stage.png"), p_stage, width = 9, height = 5, dpi = 200, bg = "white")

# 5g. Lupin-polygon level: occupancy and larvae per polygon in August by clearing status
p_L <- L %>% mutate(dens = larvae / area_m2) %>%
  ggplot(aes(x = Luket_25, y = dens + 1e-4, colour = Luket_25)) +
  geom_jitter(width = 0.2, alpha = 0.6, size = 2) +
  facet_wrap(~ site, nrow = 1) +
  scale_colour_manual(values = luket_cols, guide = "none") +
  scale_y_log10(breaks = c(1e-4, 1e-3, 1e-2, 1e-1, 1), labels = c("0", "0.001", "0.01", "0.1", "1")) +
  labs(title = "August 2026 larvae per lupin clearing polygon by clearing in 2025",
       subtitle = "points = clearing polygons (zeros plotted at 0)", x = "Luket 2025", y = "Larvae per m² of clearing polygon (log scale)") +
  theme_viz
ggsave(file.path(fig_dir, "elvesandjeger/larvae26_lupinpoly_vs_luket25.png"), p_L, width = 11, height = 4.5, dpi = 200, bg = "white")
