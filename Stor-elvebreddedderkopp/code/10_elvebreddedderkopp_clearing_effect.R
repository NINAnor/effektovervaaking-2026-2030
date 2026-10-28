#Effektovervaaking - stor elvebreddedderkopp
#Effect of lupin clearing on elvebreddedderkopp (juveniles and adults), 2025-2026
#
#Design: survey polygons from September 2025 and 2026 are linked to the clearing
#polygon they overlap most. Effect sites = Kregnesteigen, Storrønningen and
#Gravråk (clearing polygons with both cleared and uncleared patches, and spider
#observations). Fornes = control: the spider polygons there that lie outside the
#clearing polygons (most of them); Fornes polygons overlapping a clearing polygon
#are left out of the control. Predictor of interest: clearing in the year before the survey
#(Luket_24 for the 2025 polygons, Luket_25 for the 2026 polygons). Slitasje is
#not used (to be re-digitised). Substrate collapsed to sand / finsand_silt /
#blanding; vegetation cover in % (missing for 61 polygons in 2025).
#Model: negative binomial GLMM (glmmTMB) with log(polygon area) as a covariate
#(NOT as an offset: counts do not scale proportionally with polygon area - the
#estimated slope is ~0.6 - because larger polygons take in more empty ground)
#and a random intercept per clearing polygon (patch). The offset version is kept
#as a sensitivity model. Predictions are given for a standard 50 m2 polygon.
#
#Author: Megan Nowell
#Date: 2026

setwd("/data/P-Prosjekter2/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data")
#setwd("P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/05 Elvedyr/Data") #Windows

library(sf)
library(dplyr)
library(tidyr)
library(ggplot2)
library(scales)
library(glmmTMB)
library(DHARMa)
library(emmeans)
sf_use_s2(FALSE)
`%||%` <- function(x, y) if (is.null(x)) y else x

D <- "./Elevebreddedderkopp"; out_dir <- file.path(D, "2026"); fig_dir <- "../Figures/elvebreddedderkopp"
dir.create(fig_dir, showWarnings = FALSE)
ink <- "#0b0b0b"; ink2 <- "#52514e"; grid_col <- "#e6e5e1"
luket_cols <- c(Nei = "#9a9891", Delvis = "#eda100", Ja = "#2a78d6")
theme_viz <- theme_minimal(base_size = 12) +
  theme(panel.grid.minor = element_blank(), panel.grid.major = element_line(colour = grid_col),
        axis.title = element_text(colour = ink2), plot.title = element_text(colour = ink, face = "bold"),
        plot.subtitle = element_text(colour = ink2), strip.text = element_text(colour = ink, face = "bold"),
        legend.position = "top")
coef_tab <- function(m, name) {
  s <- summary(m)$coefficients$cond
  data.frame(model = name, term = rownames(s), estimate = s[, 1], se = s[, 2], z = s[, 3], p = s[, 4], rate_ratio = exp(s[, 1]), row.names = NULL)
}

#===============================================================================
# 1. Analysis data set
#===============================================================================
lup <- st_read("./Lupinluking_2026/Lupinluking_2025_2026_clean.shp", quiet = TRUE) %>% st_make_valid()
lup_df <- st_drop_geometry(lup)
poly <- st_read(file.path(out_dir, "elvebreddedderkopp_polygons_2025-2026_utm32.gpkg"), quiet = TRUE) %>% st_make_valid() %>%
  rename(adult = voksne)
st_agr(lup) <- "constant"; st_agr(poly) <- "constant"

best <- st_intersection(poly %>% dplyr::select(GlobalID), lup %>% dplyr::select(tempID)) %>%
  mutate(a_in = as.numeric(st_area(geom))) %>% st_drop_geometry() %>%
  group_by(GlobalID) %>% slice_max(a_in, n = 1, with_ties = FALSE) %>% ungroup()

luket_long <- lup_df %>% dplyr::select(tempID, matches("^Luket_2[0-6]$")) %>%
  pivot_longer(-tempID, names_to = "yr", names_prefix = "Luket_", values_to = "Luket") %>%
  mutate(year = 2000L + as.integer(yr))

dat <- poly %>% st_drop_geometry() %>%
  left_join(best, by = "GlobalID") %>%
  mutate(in_lupin_poly = !is.na(tempID),
         patch_id = if_else(in_lupin_poly, paste0("lup_", tempID), paste0("out_", GlobalID)))
# clearing status the year before the survey and the number of earlier years cleared
prev <- dat %>% dplyr::select(GlobalID, tempID, year) %>% filter(!is.na(tempID)) %>%
  left_join(luket_long, by = "tempID", relationship = "many-to-many") %>%
  group_by(GlobalID) %>%
  summarise(Luket_prev = Luket[year.y == year.x[1] - 1],
            Luket_prev2 = Luket[year.y == year.x[1] - 2],
            years_cleared_before = sum(Luket[year.y < year.x[1]] %in% c("Ja", "Delvis")), .groups = "drop")
dat <- dat %>% left_join(prev, by = "GlobalID") %>%
  mutate(across(c(Luket_prev, Luket_prev2), ~ factor(if_else(in_lupin_poly, .x, "Nei"), levels = c("Nei", "Delvis", "Ja"))),
         years_cleared_before = coalesce(years_cleared_before, 0L),
         yearf = factor(year), site = factor(site),
         substrat = factor(substrat, levels = c("sand", "finsand_silt", "blanding")),
         veg_frac = vegetasjon / 100, log_area = log(area_m2),
         group = factor(case_when(site == "Fornes" & !in_lupin_poly ~ "Control",
                                  site %in% c("Kregnesteigen", "Storrønningen", "Gravråk") ~ as.character(Luket_prev),
                                  TRUE ~ NA_character_), levels = c("Control", "Nei", "Delvis", "Ja")))
table(dat$site, dat$year); table(dat$group, dat$year, useNA = "ifany"); table(dat$Luket_prev, dat$site, dat$year)
write.csv(dat, file.path(out_dir, "elvebreddedderkopp_2025-2026_analysis_data.csv"), row.names = FALSE)

cat("juveniles: zeros =", sum(dat$juvenile == 0, na.rm = TRUE), "of", nrow(dat), "; var/mean =", round(var(dat$juvenile, na.rm = TRUE) / mean(dat$juvenile, na.rm = TRUE), 1), "\n")
cat("adults:    zeros =", sum(dat$adult == 0, na.rm = TRUE), "of", nrow(dat), "; var/mean =", round(var(dat$adult, na.rm = TRUE) / mean(dat$adult, na.rm = TRUE), 1), "\n")

#===============================================================================
# 2. Models - effect sites (Kregnesteigen, Storrønningen, Gravråk)
#===============================================================================
dm <- dat %>% filter(site %in% c("Kregnesteigen", "Storrønningen", "Gravråk")) %>% droplevels()
nrow(dm); table(dm$Luket_prev, dm$year)

fit_set <- function(resp) {
  d <- dm %>% filter(!is.na(.data[[resp]]))
  f <- as.formula(paste(resp, "~ Luket_prev + yearf + substrat + site + log_area + (1 | patch_id)"))
  m_pois <- glmmTMB(f, family = poisson, data = d)
  m_nb2  <- glmmTMB(f, family = nbinom2, data = d)
  m_zinb <- glmmTMB(f, family = nbinom2, ziformula = ~ 1, data = d)
  m_off  <- glmmTMB(update(f, . ~ . - log_area + offset(log_area)), family = nbinom2, data = d)   # sensitivity: area as offset
  aic <- AIC(m_pois, m_nb2, m_zinb) %>% tibble::rownames_to_column("model") %>% mutate(response = resp)
  sim <- simulateResiduals(m_nb2)
  png(file.path(fig_dir, sprintf("dharma_nb2_%s.png", resp)), width = 1600, height = 800, res = 150); plot(sim); dev.off()
  disp <- testDispersion(sim)$p.value; zi <- testZeroInflation(sim)$p.value
  m_nocl <- update(m_nb2, . ~ . - Luket_prev)
  m_int  <- update(m_nb2, . ~ . + Luket_prev:yearf)
  m_hist <- update(m_nb2, . ~ . - Luket_prev + years_cleared_before)
  m_2yr  <- update(m_nb2, . ~ . + Luket_prev2)
  # vegetation cover only where recorded (2026 complete, 2025 partly)
  dv <- d %>% filter(!is.na(veg_frac))
  m_veg  <- glmmTMB(update(f, . ~ . + veg_frac), family = nbinom2, data = dv)
  m_veg0 <- glmmTMB(f, family = nbinom2, data = dv)
  lrt <- function(m0, m1) anova(m0, m1)[["Pr(>Chisq)"]][2]
  list(resp = resp, d = d, aic = aic, disp_p = disp, zi_p = zi, m = m_nb2, m_off = m_off, m_int = m_int, m_hist = m_hist, m_2yr = m_2yr, m_veg = m_veg,
       lrt = c(clearing_prev_year = lrt(m_nocl, m_nb2), clearing_x_year = lrt(m_nb2, m_int),
               substrate = lrt(update(m_nb2, . ~ . - substrat), m_nb2), site = lrt(update(m_nb2, . ~ . - site), m_nb2),
               year = lrt(update(m_nb2, . ~ . - yearf), m_nb2), vegetation = lrt(m_veg0, m_veg)),
       em = as.data.frame(emmeans(m_nb2, ~ Luket_prev, type = "response", at = list(log_area = log(50)))),
       em_year = as.data.frame(emmeans(m_int, ~ Luket_prev | yearf, type = "response", at = list(log_area = log(50)))),
       contr = as.data.frame(contrast(emmeans(m_nb2, ~ Luket_prev, type = "response", at = list(log_area = log(50))), "trt.vs.ctrl", ref = "Nei"), infer = TRUE))
}
res <- lapply(c(juvenile = "juvenile", adult = "adult"), fit_set)
for (r in res) {
  cat("\n=====", r$resp, "  DHARMa dispersion p =", round(r$disp_p, 3), " zero-inflation p =", round(r$zi_p, 3), "\n"); print(r$aic)
  print(round(summary(r$m)$coefficients$cond, 3)); print(round(r$lrt, 3)); print(r$em); print(r$contr); print(r$em_year)
  cat("sensitivity (area as offset): "); so <- summary(r$m_off)$coefficients$cond; print(round(cbind(RR = exp(so[, 1]), p = so[, 4])[grep("Luket", rownames(so)), ], 3))
  cat("years cleared before:"); print(round(summary(r$m_hist)$coefficients$cond["years_cleared_before", ], 3))
  cat("vegetation:"); print(round(summary(r$m_veg)$coefficients$cond["veg_frac", ], 3))
}

#===============================================================================
# 3. Control group (Fornes, outside clearing polygons)
#===============================================================================
dc <- dat %>% filter(!is.na(group)) %>% droplevels()
table(dc$group, dc$year)
ctrl <- lapply(c(juvenile = "juvenile", adult = "adult"), function(resp) {
  d <- dc %>% filter(!is.na(.data[[resp]]))
  m <- glmmTMB(as.formula(paste(resp, "~ group + yearf + substrat + log_area + (1 | patch_id)")), family = nbinom2, data = d)
  list(m = m, em = as.data.frame(emmeans(m, ~ group, type = "response", at = list(log_area = log(50)))),
       contr = as.data.frame(contrast(emmeans(m, ~ group, type = "response", at = list(log_area = log(50))), "trt.vs.ctrl", ref = "Control"), infer = TRUE))
})
for (n in names(ctrl)) { cat("\n===== control model:", n, "\n"); print(ctrl[[n]]$em); print(ctrl[[n]]$contr) }

#===============================================================================
# 4. Save tables
#===============================================================================
coefs <- bind_rows(lapply(res, function(r) bind_rows(coef_tab(r$m, paste0("nb2_", r$resp)), coef_tab(r$m_off, paste0("nb2_", r$resp, "_offset")), coef_tab(r$m_int, paste0("nb2_", r$resp, "_x_year")),
                                                    coef_tab(r$m_hist, paste0("nb2_", r$resp, "_years_cleared")), coef_tab(r$m_veg, paste0("nb2_", r$resp, "_veg")))),
                   lapply(ctrl, function(x) coef_tab(x$m, "nb2_control")) %>% bind_rows(.id = "response"))
write.csv(coefs, file.path(out_dir, "model_coefficients_2025-2026.csv"), row.names = FALSE)
lrts <- bind_rows(lapply(res, function(r) data.frame(response = r$resp, term = names(r$lrt), p = r$lrt, row.names = NULL)))
write.csv(lrts, file.path(out_dir, "model_lrt_2025-2026.csv"), row.names = FALSE)
ems <- bind_rows(lapply(res, function(r) r$em %>% mutate(response = r$resp)))
write.csv(ems, file.path(out_dir, "model_emmeans_2025-2026.csv"), row.names = FALSE)

#===============================================================================
# 5. Plots
#===============================================================================
# raw densities
p_raw <- dm %>% pivot_longer(c(juvenile, adult), names_to = "stage", values_to = "n") %>% filter(!is.na(n)) %>%
  mutate(stage = factor(stage, levels = c("juvenile", "adult"), labels = c("Juveniles", "Adults"))) %>%
  ggplot(aes(x = Luket_prev, y = n / area_m2 + 0.001, colour = Luket_prev)) +
  geom_jitter(width = 0.2, alpha = 0.6, size = 1.8) +
  stat_summary(fun = median, geom = "crossbar", width = 0.5, colour = ink, linewidth = 0.4) +
  facet_grid(stage ~ yearf) + scale_colour_manual(values = luket_cols, guide = "none") +
  scale_y_log10(labels = label_comma()) +
  labs(title = "Observed spider density in survey polygons by lupin clearing the year before",
       subtitle = "Kregnesteigen, Storrønningen, Gravråk; points = polygons (+0.001), bar = median", x = "Cleared the year before", y = "Individuals per m² searched (log scale)") + theme_viz
ggsave(file.path(fig_dir, "spider_density_vs_luket_prev_raw.png"), p_raw, width = 10, height = 7, dpi = 200, bg = "white")

# model effect plot (main + by year) for both stages
pred <- bind_rows(lapply(res, function(r) bind_rows(r$em %>% mutate(yearf = "both years (main model)"), r$em_year %>% mutate(yearf = as.character(yearf))) %>% mutate(stage = r$resp))) %>%
  mutate(stage = factor(stage, levels = c("juvenile", "adult"), labels = c("Juveniles", "Adults")),
         yearf = factor(yearf, levels = c("both years (main model)", "2025", "2026")))
p_eff <- ggplot(pred, aes(x = Luket_prev, y = response, colour = Luket_prev)) +
  geom_pointrange(aes(ymin = asymp.LCL, ymax = asymp.UCL), linewidth = 0.8, size = 0.8) +
  facet_grid(stage ~ yearf, scales = "free_y") + scale_colour_manual(values = luket_cols, guide = "none") + scale_y_log10() +
  labs(title = "Predicted spider numbers by lupin clearing the year before", subtitle = "NB GLMM, mean ± 95 % CI for a 50 m² survey polygon, averaged over site and substrate",
       x = "Cleared the year before", y = "Individuals per 50 m² polygon (log scale)") + theme_viz
ggsave(file.path(fig_dir, "spider_density_vs_luket_prev_model.png"), p_eff, width = 10, height = 7, dpi = 200, bg = "white")

# control comparison
p_ctrl <- bind_rows(lapply(names(ctrl), function(n) ctrl[[n]]$em %>% mutate(stage = n))) %>%
  mutate(stage = factor(stage, levels = c("juvenile", "adult"), labels = c("Juveniles", "Adults"))) %>%
  ggplot(aes(x = group, y = response, colour = group)) +
  geom_pointrange(aes(ymin = asymp.LCL, ymax = asymp.UCL), linewidth = 0.8, size = 0.8) +
  facet_wrap(~ stage, scales = "free_y") + scale_colour_manual(values = c(Control = "#1baf7a", luket_cols), guide = "none") + scale_y_log10() +
  labs(title = "Spider numbers: Fornes control vs clearing status the year before at the effect sites", subtitle = "NB GLMM, 2025 + 2026, mean ± 95 % CI for a 50 m² polygon",
       x = NULL, y = "Individuals per 50 m² polygon (log scale)") + theme_viz
ggsave(file.path(fig_dir, "spider_density_control_vs_luket_prev.png"), p_ctrl, width = 9, height = 5, dpi = 200, bg = "white")
