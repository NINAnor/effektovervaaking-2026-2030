### Dataanalyser GRUK-effekt 2026 ###
## Tilpasset fra "4. GRUK_2025_analyser.R" (GRUK_effekt_2025)
##
## Hva er nytt i 2026-dataene (GRUK_effekt_data_2026.xlsx):
## - plots/species.long inneholder bare ruter der det er gjort ruteanalyser (Plot_analyses == "Yes").
##   I 2026 ble det bare gjort ruteanalyser på Fyrsteila, så rutefigurene for de andre lokalitetene
##   bygger på samme ruteanalyser som i 2025.
## - circles har nye tidspunkt fra 2026: Bleikøya Etter5, Husbergøya Etter3, Malmøya Etter4,
##   Nakholmen Etter3, Padda Etter6, Torvøya Etter6.
## - Ny lokalitet: Fyrsteila (bare ruter, ingen sirkler). Etter1 = 2025 (50 x 50 cm), Etter2 = 2026 (100 x 100 cm).
##   Fyrsteila analyseres i egne deler nederst i skriptet (bekjempelse og revegetering).

## laster biblioteker
library(sciplot)
library(tidyr)
library(dplyr)
library(readxl)
library(ggplot2)
library(stringr)
library(cowplot)

# defining a colour palette
nina.colours <- c("#004F71","#008C95","#E57200","#93328E","#7A9A01","#A2AAAD","#2DCCD3","#FFB25B")

## stier
prosjektmappe <- if (dir.exists("~/Mounts/P-Prosjekter2")) "~/Mounts/P-Prosjekter2" else "/data/P-Prosjekter2"
datamappe <- file.path(prosjektmappe, "154027_effektovervaking_av_trua_arter_og_naturtyper_2024/02 Apen grunnlendt kalkmark/Data")
datafil <- file.path(datamappe, "GRUK_effekt_data_2026.xlsx")
outputmappe <- file.path(prosjektmappe, "154027_effektovervaking_av_trua_arter_og_naturtyper_2024/02 Apen grunnlendt kalkmark/Analyser/GRUK_effekt_2026/Analyser_outputs")
dir.create(outputmappe, showWarnings = FALSE)

## henter inn data
## guess_max: noen kolonner i species.long er tomme i de første radene og blir ellers lest som logiske
gruk26_plots <- read_excel(datafil, sheet = "plots", guess_max = 10000)
gruk26_plotspecies <- read_excel(datafil, sheet = "species.long", guess_max = 10000)
gruk26_circles <- read_excel(datafil, sheet = "circles", guess_max = 10000)
gruk26_circlespecies <- read_excel(datafil, sheet = "species.circles", guess_max = 10000)

## henter inn lister over rødlistearter og habitatspesialister
artsliste_rl <- read_excel(file.path(datamappe, "GRUK_artslister.xlsx"),sheet="RL")
artsliste_hs <- read_excel(file.path(datamappe, "GRUK_artslister.xlsx"),sheet="HS")
artsliste_fa <- read_excel(file.path(datamappe, "GRUK_artslister.xlsx"),sheet="FA") # NB denne inneholder arter per 2023, og er ikke kompatibel med våre analyser... Vinterkarse, syrin osv.

## tar ut skogsrutene på Padda
## NB: Fyrsteila Etter1 (2025) mangler Plot.mapping.unit, så NA må beholdes eksplisitt (ellers forsvinner rutene)
gruk26_plots <- gruk26_plots %>%
  filter(is.na(Plot.mapping.unit) | !str_starts(Plot.mapping.unit, "T4"))

gruk26_circles <- gruk26_circles %>%
  filter(is.na(Circle.mapping.unit) | !str_starts(Circle.mapping.unit, "T4"))

## hjelpevariabler for sirklene (lå i KLADD-skriptet i 2025, men brukes i figurene under)
gruk26_circles <- gruk26_circles %>%
  mutate(utfordrende_arter = Circle.invasive.species + Circle.problematic.species,
         slitasje = Circle.erosion + Circle.vehicle.tracks,
         vedplanter = Circle.shrub.layer + Circle.woody.field.layer)

## for å svare på spørsmålet om effekter av tiltakene bruker vi følgende variabler

#### Naturmangfoldvariabler 
## 1. Antall arter
## 2. Antall habitatspesialister
## 3. Antall rødlistearter
## 4. Samlet mengde habitatspesialister
## 4. Samlet mengde rødlistearter


#### Påvirkningsvariabler
## 1. Antall fremmede arter 
##  a. i rutene
##  b. i sirklene
## 2. Dekning av fremmede arter 
##  a. i rutene
##  b. i sirklene
## 3. Dekning av vedplanter 
##  a. i sirklene
## 4. Dekning av slitasje og kjørespor 
##  a. i sirklene
## 5. Dekning av problemarter
##  a. i sirklene
##  b. som funksjon av 
##      i. tiltak
##      ii .slitasje og kjørespor


## beregner antall arter og mengde av artene per kombinasjon av rute og tidspunkt

## Antall arter
datspeciesnr <- gruk26_plotspecies %>%
  group_by(Rute,Tid_num) %>%
  summarise(nr_species = n_distinct(Latinsk_navn, na.rm=TRUE))

gruk26_plots <- gruk26_plots %>% 
  unique() %>%
  left_join(datspeciesnr)

## Antall rødlistearter og total abundanse av rødlistearter
rl_summary <- gruk26_plotspecies %>%
  semi_join(artsliste_rl, by = "Latinsk_navn") %>%   # beholder bare rødlistearter
  group_by(Rute, Tid_num) %>%                # grupper per rute og tid
  summarise(
    n_rl = n_distinct(Latinsk_navn),                 # antall unike rødlistearter
    abundans_rl = sum(Dekning, na.rm = TRUE),  # total abundans
    .groups = "drop"
  )

gruk26_plots <- gruk26_plots %>%
  left_join(rl_summary, by = c("Rute", "Tid_num"))

## Antall habitatspesialister og total abundanse av habitatspesialister
hs_summary <- gruk26_plotspecies %>%
  semi_join(artsliste_hs, by = "Latinsk_navn") %>%   # beholder bare habitatspesialister
  group_by(Rute, Tid_num) %>%                # grupper per rute og tid
  summarise(
    n_hs = n_distinct(Latinsk_navn),                 # antall unike habitatspesialister
    abundans_hs = sum(Dekning, na.rm = TRUE),  # total abundans
    .groups = "drop"
  )

gruk26_plots <- gruk26_plots %>%
  left_join(hs_summary, by = c("Rute", "Tid_num"))

## Antall fremmede arter og total abundanse. Denne lista inneholder fremmede arter jf. vår nedtrekksmeny i S123, dvs. fremmede arter etter Fremmedartslista 2018.
fa_summary <- gruk26_plotspecies %>%
  semi_join(artsliste_fa, by = "Latinsk_navn") %>%   # beholder bare fremmede arter
  group_by(Rute, Tid_num) %>%                # grupper per rute og tid
  summarise(
    n_fa = n_distinct(Latinsk_navn),                 # antall unike fremmede arter
    abundans_fa = sum(Dekning, na.rm = TRUE),  # total abundans
    .groups = "drop"
  )

gruk26_plots <- gruk26_plots %>%
  left_join(fa_summary, by = c("Rute", "Tid_num"))


## legger inn 0 i stedet for NA i de rutene hvor vi faktisk har ruteanalyser, men hvor arter (rødliste, hab.spes, fremmedarter) ikke forekommer
gruk26_plots <- gruk26_plots %>%
    mutate(
    n_rl = case_when(
      is.na(n_rl) & !is.na(nr_species) ~ 0,   # sett 0 når ingen RL-arter, men arter finnes
      TRUE ~ n_rl
    ),
    abundans_rl = case_when(
      is.na(abundans_rl) & !is.na(nr_species) ~ 0,  # samme logikk for abundans
      TRUE ~ abundans_rl
    ),
    n_hs = case_when(
      is.na(n_hs) & !is.na(nr_species) ~ 0,   # sett 0 når ingen HS-arter, men arter finnes
      TRUE ~ n_hs
    ),
    abundans_hs = case_when(
      is.na(abundans_hs) & !is.na(nr_species) ~ 0,  # samme logikk for abundans
      TRUE ~ abundans_hs
    ),
    n_fa = case_when(
      is.na(n_fa) & !is.na(nr_species) ~ 0,   # sett 0 når ingen RL-arter, men arter finnes
      TRUE ~ n_fa
    ),
    abundans_fa = case_when(
      is.na(abundans_fa) & !is.na(nr_species) ~ 0,  # samme logikk for abundans
      TRUE ~ abundans_fa
    )
  )


### Lager figurer for hver av påvirkningsfaktorene separat
### Dvs. ett sett av figurer for Bleikøya og Torvøya, der fokus er bekjempelse av gravbergknapp
### Og ett sett av figurer for Padda, Malmøya og Husbergøya, der fokus er bekjempelse av gjengroing

#### ---- Bekjempelse av gravbergknapp ---- 
## ## Henter ut lokalitetene Bleikøya, Nakholmen og Torvøya

gruk26_plots_gbk <- gruk26_plots %>%
  filter(Lokalitet == "Torvøya" | Lokalitet == "Bleikøya" | Lokalitet == "Nakholmen")

gruk26_circles_gbk <- gruk26_circles %>%
  filter(Lokalitet == "Torvøya" | Lokalitet == "Bleikøya"  | Lokalitet == "Nakholmen")

## splitter Torvøya i to dellokaliteter, S og N, fordi behandlingen der og overvåkingsfrekvensen varierer
## TorvøyaN er overvåket i 2022 (Før, Etter1), 2025 og 2026, så Etter5 -> Etter2 og Etter6 -> Etter3
gruk26_plots_gbk <- gruk26_plots_gbk %>%
  mutate(
    Lokalitet_ny = case_when(
      Lokalitet == "Torvøya" & str_starts(Rute, "TN") ~ "TorvøyaN",
      Lokalitet == "Torvøya" & str_starts(Rute, "TS") ~ "TorvøyaS",
      TRUE ~ Lokalitet
    )
  )

gruk26_plots_gbk <- gruk26_plots_gbk %>%
  mutate(
    Tid = case_when(
      Lokalitet_ny == "TorvøyaN" & Tid == "Etter5" ~ "Etter2",
      Lokalitet_ny == "TorvøyaN" & Tid == "Etter6" ~ "Etter3",
    TRUE ~Tid),
    Tid_num = case_when(
      Lokalitet_ny == "TorvøyaN" & Tid_num == 5 ~2,
      Lokalitet_ny == "TorvøyaN" & Tid_num == 6 ~3,
      TRUE ~ Tid_num
    )
  )

gruk26_circles_gbk <- gruk26_circles_gbk %>%
  mutate(
    Lokalitet_ny = case_when(
      Lokalitet == "Torvøya" & str_starts(Rute, "TN") ~ "TorvøyaN",
      Lokalitet == "Torvøya" & str_starts(Rute, "TS") ~ "TorvøyaS",
      TRUE ~ Lokalitet
    )
  )

gruk26_circles_gbk <- gruk26_circles_gbk %>%
  mutate(
    Tid = case_when(
      Lokalitet_ny == "TorvøyaN" & Tid == "Etter5" ~ "Etter2",
      Lokalitet_ny == "TorvøyaN" & Tid == "Etter6" ~ "Etter3",
      TRUE ~Tid),
    Tid_num = case_when(
      Lokalitet_ny == "TorvøyaN" & Tid_num == 5 ~2,
      Lokalitet_ny == "TorvøyaN" & Tid_num == 6 ~3,
      TRUE ~ Tid_num
    )
  )


## summerer variablene per kombinasjon av rute og tid, gjennomsnitt og standardavvik, til figurer
gbk_summary_data <- gruk26_plots_gbk %>%
  group_by(Tid_num,Lokalitet_ny) %>%
  summarise(
    mean_n_rl = mean(n_rl, na.rm = TRUE),
    se_n_rl = se(n_rl, na.rm = TRUE),
    mean_ab_rl = mean(abundans_rl,na.rm=TRUE),
    se_ab_rl = se(abundans_rl, na.rm = TRUE),
    mean_n_hs = mean(n_hs, na.rm = TRUE),
    se_n_hs = se(n_hs, na.rm = TRUE),
    mean_ab_hs = mean(abundans_hs,na.rm=TRUE),
    se_ab_hs = se(abundans_hs, na.rm = TRUE),
    mean_n_fa = mean(n_fa, na.rm = TRUE),
    se_n_fa = se(n_fa, na.rm = TRUE),
    mean_ab_fa = mean(abundans_fa,na.rm=TRUE),
    se_ab_fa = se(abundans_fa, na.rm = TRUE),
    mean_n_sr = mean(nr_species, na.rm = TRUE),
    se_n_sr = se(nr_species, na.rm = TRUE),
    mean_dekning_felt = mean(Field.layer,na.rm=TRUE),
    se_dekning_felt = se(Field.layer, na.rm = TRUE)
  )

## figurer: antall arter og dekning av feltsjikt
gbk_ant_arter <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_n_sr, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_sr - se_n_sr, ymax = mean_n_sr + se_n_sr),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Artsrikdom") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_feltsjikt <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_dekning_felt, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_dekning_felt - se_dekning_felt, ymax = mean_dekning_felt + se_dekning_felt),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 100)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Feltsjikt") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_veg <- plot_grid(gbk_ant_arter,gbk_feltsjikt,ncol = 2)
ggsave("GBK_veg.jpeg", plot = gbk_veg, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av habitatspesialister
gbk_ant_hs <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_n_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_hs - se_n_hs, ymax = mean_n_hs + se_n_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 5)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_ab_hs <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_ab_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_hs - se_ab_hs, ymax = mean_ab_hs + se_ab_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_hs <- plot_grid(gbk_ant_hs,gbk_ab_hs,ncol = 2)
ggsave("GBK_HS.jpeg", plot = gbk_hs, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av rødlistearter
gbk_ant_rl <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_n_rl, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_rl - se_n_rl, ymax = mean_n_rl + se_n_rl),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 4)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall rødlistearter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_ab_rl <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_ab_rl, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_rl - se_ab_rl, ymax = mean_ab_rl + se_ab_rl),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning rødlistearter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_rl <- plot_grid(gbk_ant_rl,gbk_ab_rl,ncol = 2)
ggsave("GBK_RL.jpeg", plot = gbk_rl, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av fremmedarter i rutene
gbk_ant_fa <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_n_fa, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_fa - se_n_fa, ymax = mean_n_fa + se_n_fa),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 3)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_ab_fa <- ggplot(gbk_summary_data, aes(x = Lokalitet_ny, y = mean_ab_fa, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_fa - se_ab_fa, ymax = mean_ab_fa + se_ab_fa),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 70)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

gbk_fa <- plot_grid(gbk_ant_fa,gbk_ab_fa,ncol = 2)
ggsave("GBK_FA.jpeg", plot = gbk_fa, path = outputmappe, width = 10, height = 6, dpi = 300)


### i sirklene
## summerer variablene per kombinasjon av sirkel og tid, gjennomsnitt og standardavvik, til figurer
gbk_summary_data_circles <- gruk26_circles_gbk %>%
  group_by(Tid_num,Lokalitet_ny) %>%
  summarise(
    mean_utfordrende_arter = mean(utfordrende_arter, na.rm = TRUE),
    se_utfordrende_arter = se(utfordrende_arter, na.rm = TRUE),
    mean_slitasje = mean(slitasje,na.rm=TRUE),
    se_slitasje = se(slitasje, na.rm = TRUE),
    mean_vedplanter = mean(vedplanter,na.rm=TRUE),
    se_vedplanter = se(vedplanter, na.rm = TRUE),
    mean_fremmede = mean(Circle.invasive.species,na.rm=TRUE),
    se_fremmede = se(Circle.invasive.species, na.rm = TRUE),
    mean_problem = mean(Circle.problematic.species,na.rm=TRUE),
    se_problem = se(Circle.problematic.species, na.rm = TRUE))

# figur: dekning av fremmedarter i sirklene
gbk_ab_fa_c <- ggplot(gbk_summary_data_circles, aes(x = Lokalitet_ny, y = mean_fremmede, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_fremmede - se_fremmede, ymax = mean_fremmede + se_fremmede),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 75)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Dekning fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

# figur: dekning av problemarter i sirklene
gbk_problem_c <- ggplot(gbk_summary_data_circles, aes(x = Lokalitet_ny, y = mean_problem, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_problem - se_problem, ymax = mean_problem + se_problem),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 5)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet_ny, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning problemarter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )


gbk_fa_c <- plot_grid(gbk_ab_fa_c,gbk_problem_c,ncol = 2)
ggsave("GBK_FA.SIRKLER.jpeg", plot = gbk_fa_c, path = outputmappe, width = 10, height = 6, dpi = 300)



#### ---- Bekjempelse av gjengroing ---- #### 
## Henter ut lokalitetene Malmøya, Padda og Husbergøya
gruk26_plots_busk <- gruk26_plots %>%
  filter(Lokalitet == "Malmøya" | Lokalitet == "Padda" | Lokalitet == "Husbergøya")

gruk26_circles_busk <- gruk26_circles %>%
  filter(Lokalitet == "Malmøya" | Lokalitet == "Padda" | Lokalitet == "Husbergøya")

## summerer variablene per kombinasjon av rute og tid, gjennomsnitt og standardavvik, til figurer
busk_summary_data <- gruk26_plots_busk %>%
  group_by(Tid_num,Lokalitet) %>%
  summarise(
    mean_n_rl = mean(n_rl, na.rm = TRUE),
    se_n_rl = se(n_rl, na.rm = TRUE),
    mean_ab_rl = mean(abundans_rl,na.rm=TRUE),
    se_ab_rl = se(abundans_rl, na.rm = TRUE),
    mean_n_hs = mean(n_hs, na.rm = TRUE),
    se_n_hs = se(n_hs, na.rm = TRUE),
    mean_ab_hs = mean(abundans_hs,na.rm=TRUE),
    se_ab_hs = se(abundans_hs, na.rm = TRUE),
    mean_n_fa = mean(n_fa, na.rm = TRUE),
    se_n_fa = se(n_fa, na.rm = TRUE),
    mean_ab_fa = mean(abundans_fa,na.rm=TRUE),
    se_ab_fa = se(abundans_fa, na.rm = TRUE),
    mean_n_sr = mean(nr_species, na.rm = TRUE),
    se_n_sr = se(nr_species, na.rm = TRUE),
    mean_dekning_felt = mean(Field.layer,na.rm=TRUE),
    se_dekning_felt = se(Field.layer, na.rm = TRUE)
  )


## figurer: antall arter og dekning av feltsjikt
busk_ant_arter <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_n_sr, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_sr - se_n_sr, ymax = mean_n_sr + se_n_sr),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Artsrikdom") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_feltsjikt <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_dekning_felt, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_dekning_felt - se_dekning_felt, ymax = mean_dekning_felt + se_dekning_felt),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 100)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Feltsjikt") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_veg <- plot_grid(busk_ant_arter,busk_feltsjikt,ncol = 2)
ggsave("BUSK_veg.jpeg", plot = busk_veg, path = outputmappe, width = 10, height = 6, dpi = 300)


# figurer: antall og dekning av habitatspesialister
busk_ant_hs <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_n_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_hs - se_n_hs, ymax = mean_n_hs + se_n_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 5)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_ab_hs <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_ab_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_hs - se_ab_hs, ymax = mean_ab_hs + se_ab_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 50)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_hs <- plot_grid(busk_ant_hs,busk_ab_hs,ncol = 2)
ggsave("BUSK_HS.jpeg", plot = busk_hs, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av rødlistearter
busk_ant_rl <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_n_rl, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_rl - se_n_rl, ymax = mean_n_rl + se_n_rl),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 4)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall rødlistearter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_ab_rl <- ggplot(busk_summary_data, aes(x = Lokalitet, y = mean_ab_rl, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_rl - se_ab_rl, ymax = mean_ab_rl + se_ab_rl),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 30)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning rødlistearter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

busk_rl <- plot_grid(busk_ant_rl,busk_ab_rl,ncol = 2)
ggsave("BUSK_RL.jpeg", plot = busk_rl, path = outputmappe, width = 10, height = 6, dpi = 300)


### i sirklene
## summerer variablene per kombinasjon av sirkel og tid, gjennomsnitt og standardavvik, til figurer
busk_summary_data_circles <- gruk26_circles_busk %>%
  group_by(Tid_num,Lokalitet) %>%
  summarise(
    mean_utfordrende_arter = mean(utfordrende_arter, na.rm = TRUE),
    se_utfordrende_arter = se(utfordrende_arter, na.rm = TRUE),
    mean_slitasje = mean(slitasje,na.rm=TRUE),
    se_slitasje = se(slitasje, na.rm = TRUE),
    mean_vedplanter = mean(vedplanter,na.rm=TRUE),
    se_vedplanter = se(vedplanter, na.rm = TRUE),
    mean_fremmede = mean(Circle.invasive.species,na.rm=TRUE),
    se_fremmede = se(Circle.invasive.species, na.rm = TRUE),
    mean_problem = mean(Circle.problematic.species,na.rm=TRUE),
    se_problem = se(Circle.problematic.species, na.rm = TRUE))

## figur: dekning av fremmedarter i sirklene
busk_ab_fa_c <- ggplot(busk_summary_data_circles, aes(x = Lokalitet, y = mean_fremmede, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_fremmede - se_fremmede, ymax = mean_fremmede + se_fremmede),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Dekning fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

## figur: dekning av vedplanter i sirklene
busk_vedplanter_c <- ggplot(busk_summary_data_circles, aes(x = Lokalitet, y = mean_vedplanter, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_vedplanter - se_vedplanter, ymax = mean_vedplanter + se_vedplanter),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 75)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning vedplanter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            
    axis.text.x = element_blank(),          
    axis.ticks.x = element_blank()
  )


busk_vedplanter_figur <- plot_grid(busk_vedplanter_c,busk_ab_fa_c,ncol = 2)
ggsave("BUSK.SIRKLER.jpeg", plot = busk_vedplanter_figur, path = outputmappe, width = 10, height = 6, dpi = 300)


## figur: dekning av problemarter i sirklene
busk_problem_c <- ggplot(busk_summary_data_circles, aes(x = Lokalitet, y = mean_problem, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_problem - se_problem, ymax = mean_problem + se_problem),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 50)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Lokalitet", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Lokalitet, nrow = 1, scales = "free_x", strip.position = "bottom") +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning problemarter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            
    axis.text.x = element_blank(),          
    axis.ticks.x = element_blank()
  )


#### ---- Padda: utfordrende arter og luking ---- ####
## Her har vi bare data over tid fra Padda
## Henter ut T2-data fra Padda fra sirkeldatasettet
Pfiltered_data <- gruk26_circles %>%
  filter(
    Lokalitet == "Padda",
    !str_starts(Circle.mapping.unit, "T4"))

## summerer variablene per kombinasjon av sirkel og tid, gjennomsnitt og standardavvik, til figurer
Psummary_data <- Pfiltered_data %>%
  group_by(Tid_num,Circle.weeding) %>%
  summarise(
    mean_utfordrende = mean(utfordrende_arter, na.rm = TRUE),
    se_utfordrende = se(utfordrende_arter, na.rm = TRUE),
    mean_slitasje = mean(slitasje, na.rm = TRUE),
    se_slitasje = se(slitasje, na.rm = TRUE)
  )

## i datasettet er tid0 = før tiltak, forsommer 2022, 
## tid1 = etter tiltak, høst22, tid2 = forsommer 2023 (etter tiltak, før luking), 
## tid3 = høst 2023 (delvis luket), tid4 = forsommer 2024 (delvis luket), tid5 = sensommer 2025 (luket), tid6 = 2026 (6 av 9 sirkler luket)

## figur: dekning av utfordrende arter (fremmede + problem) som funksjon av luking og tid
## synliggjør betydningen av å luke for å unngå etablering av problemarter
Psummary_data$Circle.weeding <- ifelse(
  is.na(Psummary_data$Circle.weeding),
  "Nei",                         # <-- NA blir "Nei"
  ifelse(Psummary_data$Circle.weeding == 1, "Ja", "Nei")
)

Psummary_data$Circle.weeding <- factor(
  Psummary_data$Circle.weeding,
  levels = c("Nei", "Ja")
)


utfordrende_Padda <- ggplot(Psummary_data, aes(x = Tid_num, y = mean_utfordrende, fill = as.factor(Circle.weeding))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_utfordrende - se_utfordrende, ymax = mean_utfordrende + se_utfordrende),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  scale_x_continuous(breaks = 0:6) +  
  expand_limits(y = c(0, 50)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Tidspunkt etter tiltak", y = "Dekning utfordrende arter i sirkel (%)", fill = "Luking") +
  scale_fill_manual(values = nina.colours) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))

ggsave("Padda_utfordrende.jpeg", plot = utfordrende_Padda, path = outputmappe, width = 10, height = 6, dpi = 300)

## Modellene for slitasje og utfordrende arter (tidsforskyvning t+1 og t+2) er ikke kjørt i år,
## se "4. GRUK_2025_analyser.R" for koden.


#### ---- Fyrsteila: bekjempelse av gravbergknapp ---- ####
## Ny lokalitet i datasettet. Ingen før-data og ingen sirkler, bare ruter i 2025 (Etter1) og 2026 (Etter2).
## NB: rutestørrelsen er endret fra 50 x 50 cm i 2025 til 100 x 100 cm i 2026. Antall arter er derfor ikke
## direkte sammenlignbart mellom årene (større rute gir flere arter). Dekning (%) er mer sammenlignbart.
## NB: feltsjikt ble ikke registrert i 2025, så feltsjikt er ikke med her.
## Kontrollrutene (C_) og S_6 ble bare analysert i 2025, D2-rutene bare i 2026.

## hovedbehandling ut fra rutenavnet (L = fjerning av vegetasjonsmatter, ikke luking, jf. skript 3)
gruk26_plots_fyr <- gruk26_plots %>%
  filter(Lokalitet == "Fyrsteila") %>%
  mutate(
    Behandling = case_when(
      str_starts(Rute, "D") ~ "Duk",
      str_starts(Rute, "LS") ~ "Fjerning + sprøyting",
      str_starts(Rute, "L_") ~ "Fjerning",
      str_starts(Rute, "SR") ~ "Sprøyting + raking",
      str_starts(Rute, "S_") ~ "Sprøyting",
      str_starts(Rute, "C") ~ "Kontroll"
    ),
    Behandling = factor(Behandling, levels = c("Kontroll", "Duk", "Fjerning", "Fjerning + sprøyting", "Sprøyting", "Sprøyting + raking"))
  )

## dekning av gravbergknapp per rute og tid (0 der ruta er analysert, men arten ikke er registrert)
gbk_dekning <- gruk26_plotspecies %>%
  filter(Latinsk_navn == "Phedimus_spurius") %>%
  group_by(Rute, Tid_num) %>%
  summarise(dekning_gbk = sum(Dekning, na.rm = TRUE), .groups = "drop")

gruk26_plots_fyr <- gruk26_plots_fyr %>%
  left_join(gbk_dekning, by = c("Rute", "Tid_num")) %>%
  mutate(dekning_gbk = case_when(
    is.na(dekning_gbk) & !is.na(nr_species) ~ 0,
    TRUE ~ dekning_gbk
  ))

## Lag variabel for revegeteringsbehandling
fyr_2026 <- gruk26_plots_fyr %>%
  filter(Tid_num == 2) %>%
  mutate(
    Revegetering = case_when(
      Plot.seeding == 0 & Plot.revegetation == 0 ~ "Ingen",
      Plot.seeding == 1 & Plot.revegetation == 0 ~ "Såing",
      Plot.seeding == 0 & Plot.revegetation == 1 ~ "Utplanting",
      Plot.seeding == 1 & Plot.revegetation == 1 ~ "Såing + utplanting",
      TRUE ~ NA_character_
    ),
    Revegetering = factor(
      Revegetering,
      levels = c("Ingen", "Såing", "Utplanting", "Såing + utplanting")
    )
  )

## summerer variablene per kombinasjon av behandling og tid, gjennomsnitt og standardfeil, til figurer
fyr_summary_data <- gruk26_plots_fyr %>%
  group_by(Tid_num,Behandling) %>%
  summarise(
    n_ruter = n(),
    mean_n_sr = mean(nr_species, na.rm = TRUE),
    se_n_sr = se(nr_species, na.rm = TRUE),
    mean_gbk = mean(dekning_gbk, na.rm = TRUE),
    se_gbk = se(dekning_gbk, na.rm = TRUE),
    mean_n_hs = mean(n_hs, na.rm = TRUE),
    se_n_hs = se(n_hs, na.rm = TRUE),
    mean_ab_hs = mean(abundans_hs,na.rm=TRUE),
    se_ab_hs = se(abundans_hs, na.rm = TRUE),
    mean_n_rl = mean(n_rl, na.rm = TRUE),
    se_n_rl = se(n_rl, na.rm = TRUE),
    mean_ab_rl = mean(abundans_rl,na.rm=TRUE),
    se_ab_rl = se(abundans_rl, na.rm = TRUE),
    mean_n_fa = mean(n_fa, na.rm = TRUE),
    se_n_fa = se(n_fa, na.rm = TRUE),
    mean_ab_fa = mean(abundans_fa,na.rm=TRUE),
    se_ab_fa = se(abundans_fa, na.rm = TRUE),
    .groups = "drop"
  )

## figurer: dekning av gravbergknapp og antall arter
fyr_gbk <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_gbk, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_gbk - se_gbk, ymax = mean_gbk + se_gbk),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Dekning gravbergknapp") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_ant_arter <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_n_sr, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_sr - se_n_sr, ymax = mean_n_sr + se_n_sr),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Artsrikdom (NB: ulik rutestørrelse)") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_veg <- plot_grid(fyr_gbk,fyr_ant_arter,ncol = 2)
ggsave("FYR_veg.jpeg", plot = fyr_veg, path = outputmappe, width = 12, height = 6, dpi = 300)


## figurer: antall og dekning av habitatspesialister
fyr_ant_hs <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_n_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_hs - se_n_hs, ymax = mean_n_hs + se_n_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 5)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_ab_hs <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_ab_hs, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_hs - se_ab_hs, ymax = mean_ab_hs + se_ab_hs),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_hs <- plot_grid(fyr_ant_hs,fyr_ab_hs,ncol = 2)
ggsave("FYR_HS.jpeg", plot = fyr_hs, path = outputmappe, width = 12, height = 6, dpi = 300)


## figurer: antall og dekning av fremmedarter (gravbergknapp er med i fremmedartslista)
fyr_ant_fa <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_n_fa, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_n_fa - se_n_fa, ymax = mean_n_fa + se_n_fa),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 3)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Antall", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  guides(fill = "none")+
  labs(title = "Antall fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_ab_fa <- ggplot(fyr_summary_data, aes(x = Behandling, y = mean_ab_fa, fill = as.factor(Tid_num))) +
  geom_col(position = position_dodge(width = 0.9), width = 0.7) +  # Creates grouped bars
  geom_errorbar(
    aes(ymin = mean_ab_fa - se_ab_fa, ymax = mean_ab_fa + se_ab_fa),
    width = 0.2,
    position = position_dodge(width = 0.9)
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  labs(x = "Behandling", y = "Dekning (%)", fill = "Tid") +
  scale_fill_manual(values = nina.colours) +
  facet_wrap(~ Behandling, nrow = 1, scales = "free_x", strip.position = "bottom", labeller = label_wrap_gen(width = 12)) +
  theme_bw() +
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  theme(legend.text = element_text(size=12))+
  theme(legend.title = element_text(size=14))+
  labs(title = "Dekning fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))+
  theme(
    strip.placement = "outside",            # legg stripene utenfor panelet
    axis.text.x = element_blank(),          # fjern dupliserte x-etiketter
    axis.ticks.x = element_blank()
  )

fyr_fa <- plot_grid(fyr_ant_fa,fyr_ab_fa,ncol = 2)
ggsave("FYR_FA.jpeg", plot = fyr_fa, path = outputmappe, width = 12, height = 6, dpi = 300)


#### ---- Fyrsteila: revegetering, 2026 ---- ####
## Bare 2026-data (Etter2), fordi ruta ble økt til 100 x 100 cm for å fange opp utplantingen bedre.
## fyr_2026 med variabelen Revegetering lages etter gruk26_plots_fyr over.
## Tynt datasett: to ruter per kombinasjon av bekjempelse og revegetering, tre for Duk (D1 + D2)
## og én for Sprøyting + Utplanting (S_6 ble ikke analysert i 2026).
## NB: revegeteringen er kodet ulikt i 2025 og 2026 for 26 av 35 ruter som finnes begge år. Her brukes 2026-kodingen.
## Koblingen plotnummer -> Rute for 2025 (rute_lookup_2025 i skript 3) bør sjekkes mot feltnotater.

## summerer variablene per revegeteringsmetode, gjennomsnitt og standardfeil, til figurer
fyr_reveg_summary_data <- fyr_2026 %>%
  group_by(Revegetering) %>%
  summarise(
    n_ruter = n(),
    mean_n_sr = mean(nr_species, na.rm = TRUE),
    se_n_sr = se(nr_species, na.rm = TRUE),
    mean_gbk = mean(dekning_gbk, na.rm = TRUE),
    se_gbk = se(dekning_gbk, na.rm = TRUE),
    mean_n_hs = mean(n_hs, na.rm = TRUE),
    se_n_hs = se(n_hs, na.rm = TRUE),
    mean_ab_hs = mean(abundans_hs,na.rm=TRUE),
    se_ab_hs = se(abundans_hs, na.rm = TRUE),
    mean_n_fa = mean(n_fa, na.rm = TRUE),
    se_n_fa = se(n_fa, na.rm = TRUE),
    mean_ab_fa = mean(abundans_fa,na.rm=TRUE),
    se_ab_fa = se(abundans_fa, na.rm = TRUE),
    .groups = "drop"
  )

## figurer: dekning av gravbergknapp og antall arter
fyr_reveg_gbk <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_gbk, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_gbk - se_gbk, ymax = mean_gbk + se_gbk),
    width = 0.2
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Dekning (%)") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Dekning gravbergknapp") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_ant_arter <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_n_sr, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_n_sr - se_n_sr, ymax = mean_n_sr + se_n_sr),
    width = 0.2
  ) +
  expand_limits(y = c(0, 20)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Antall") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Artsrikdom") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_veg <- plot_grid(fyr_reveg_gbk,fyr_reveg_ant_arter,ncol = 2)
ggsave("FYR_REVEG_veg.jpeg", plot = fyr_reveg_veg, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av habitatspesialister
fyr_reveg_ant_hs <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_n_hs, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_n_hs - se_n_hs, ymax = mean_n_hs + se_n_hs),
    width = 0.2
  ) +
  expand_limits(y = c(0, 5)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Antall") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Antall habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_ab_hs <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_ab_hs, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_ab_hs - se_ab_hs, ymax = mean_ab_hs + se_ab_hs),
    width = 0.2
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Dekning (%)") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Dekning habitatspesialister") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_hs <- plot_grid(fyr_reveg_ant_hs,fyr_reveg_ab_hs,ncol = 2)
ggsave("FYR_REVEG_HS.jpeg", plot = fyr_reveg_hs, path = outputmappe, width = 10, height = 6, dpi = 300)


## figurer: antall og dekning av fremmedarter
fyr_reveg_ant_fa <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_n_fa, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_n_fa - se_n_fa, ymax = mean_n_fa + se_n_fa),
    width = 0.2
  ) +
  expand_limits(y = c(0, 3)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Antall") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Antall fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_ab_fa <- ggplot(fyr_reveg_summary_data, aes(x = Revegetering, y = mean_ab_fa, fill = Revegetering)) +
  geom_col(width = 0.7) +
  geom_errorbar(
    aes(ymin = mean_ab_fa - se_ab_fa, ymax = mean_ab_fa + se_ab_fa),
    width = 0.2
  ) +
  expand_limits(y = c(0, 25)) +  # minimum y-akse; utvides automatisk hvis data er høyere
  scale_x_discrete(labels = function(x) str_wrap(x, width = 10)) +
  labs(x = "Revegetering", y = "Dekning (%)") +
  scale_fill_manual(values = nina.colours) +
  theme_bw() +
  theme(axis.text.x = element_text(size=12))+
  theme(axis.text.y = element_text(angle = 0, hjust = 1,size=12))+
  theme(axis.title = element_text(size=16))+
  guides(fill = "none")+
  labs(title = "Dekning fremmede arter") + 
  theme(plot.title = element_text(hjust = 0.5,size = 14,face = "bold"))

fyr_reveg_fa <- plot_grid(fyr_reveg_ant_fa,fyr_reveg_ab_fa,ncol = 2)
ggsave("FYR_REVEG_FA.jpeg", plot = fyr_reveg_fa, path = outputmappe, width = 10, height = 6, dpi = 300)


## tabell: variablene for hver kombinasjon av bekjempelse og revegetering
## arket "Tabell" viser gjennomsnitt ± standardfeil, arket "Tall" har de samme tallene i egne kolonner
fyr_kombinasjoner <- fyr_2026 %>%
  group_by(Behandling, Revegetering) %>%
  summarise(
    n_ruter = n(),
    across(
      c(dekning_gbk, nr_species, Field.layer, n_hs, abundans_hs, n_rl, abundans_rl, n_fa, abundans_fa),
      list(mean = ~ mean(.x, na.rm = TRUE), se = ~ se(.x, na.rm = TRUE))
    ),
    .groups = "drop"
  )

## viser bare gjennomsnittet der det er én rute (standardfeil finnes ikke da)
snitt_se <- function(snitt, se) {
  tekst <- ifelse(is.na(se), sprintf("%.1f", snitt), sprintf("%.1f ± %.1f", snitt, se))
  str_replace_all(tekst, "\\.", ",")
}

fyr_kombinasjoner_tabell <- fyr_kombinasjoner %>%
  transmute(
    Bekjempelse = Behandling,
    Revegetering,
    `Antall ruter` = n_ruter,
    `Gravbergknapp, dekning (%)` = snitt_se(dekning_gbk_mean, dekning_gbk_se),
    `Antall arter` = snitt_se(nr_species_mean, nr_species_se),
    `Feltsjikt, dekning (%)` = snitt_se(Field.layer_mean, Field.layer_se),
    `Habitatspesialister, antall` = snitt_se(n_hs_mean, n_hs_se),
    `Habitatspesialister, dekning (%)` = snitt_se(abundans_hs_mean, abundans_hs_se),
    `Rødlistearter, antall` = snitt_se(n_rl_mean, n_rl_se),
    `Rødlistearter, dekning (%)` = snitt_se(abundans_rl_mean, abundans_rl_se),
    `Fremmede arter, antall` = snitt_se(n_fa_mean, n_fa_se),
    `Fremmede arter, dekning (%)` = snitt_se(abundans_fa_mean, abundans_fa_se)
  )

openxlsx::write.xlsx(
  list(Tabell = fyr_kombinasjoner_tabell, Tall = fyr_kombinasjoner),
  file.path(outputmappe, "FYR_kombinasjoner_2026.xlsx"),
  overwrite = TRUE
)


#### ---- Lagrer oppsummeringstabeller ---- ####
## gjennomsnitt og standardfeil bak figurene
write.csv(gbk_summary_data, file.path(outputmappe, "GBK_ruter_oppsummering.csv"), row.names = FALSE)
write.csv(gbk_summary_data_circles, file.path(outputmappe, "GBK_sirkler_oppsummering.csv"), row.names = FALSE)
write.csv(busk_summary_data, file.path(outputmappe, "BUSK_ruter_oppsummering.csv"), row.names = FALSE)
write.csv(busk_summary_data_circles, file.path(outputmappe, "BUSK_sirkler_oppsummering.csv"), row.names = FALSE)
write.csv(Psummary_data, file.path(outputmappe, "Padda_sirkler_oppsummering.csv"), row.names = FALSE)
write.csv(fyr_summary_data, file.path(outputmappe, "FYR_ruter_oppsummering.csv"), row.names = FALSE)
write.csv(fyr_reveg_summary_data, file.path(outputmappe, "FYR_revegetering_oppsummering.csv"), row.names = FALSE)
