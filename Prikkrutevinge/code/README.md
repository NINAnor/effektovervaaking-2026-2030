# Prikkrutevinge – skript

Kvalitetssikring, DarwinCore og analyser for effektovervåkingen av prikkrutevinge
(*Melitaea cinxia*) på Rauer, Telefonstolpen (RT) og Utedassen (RU), 2022–2026.

Skriptene leser bare fra `../data/` og skriver alle resultater til `../img/`.
Åpne `Prikkrutevinge.Rproj`, så peker `here::here()` på `Prikkrutevinge/`.

## Kjøring

Kjør skriptene i rekkefølge 01–08, med «Render» i RStudio, `quarto render <fil>.qmd`
eller «Run All». Hvert skript leser inn `00_felles.qmd` selv. Senere skript leser
resultatene (`.rds`/`.xlsx` i `img/`) fra de tidligere.

| Skript | Gjør | Skriver til `img/` |
|---|---|---|
| `00_felles.qmd` | Pakker, filstier og hjelpefunksjoner. Kjøres ikke alene. | – |
| `01_rosetter_blomstrende_skudd.qmd` | Kontroll av smalkjemperosetter og blomstrende skudd i DwC 2022–2025 mot den rensede fila. Endrer ingen data. | `01_rosetter_blomstrende_skudd_2022_2025.xlsx` |
| `02_skjotsel.qmd` | Skjøtselstabell: behandlet ja/nei (Plot_management) og antall ganger slått per rute og sirkel, 2022–2026 | `02_skjotsel_2022_2026.xlsx/.rds` |
| `03_rettelser.qmd` | Rettet kopi av 2026-dataene fra Survey123 | `03_Effekt_Prikk_2026_rettet.xlsx/.rds` |
| `04_dwc.qmd` | DarwinCore Sampling Event for 2026 (event + measurementOrFact) | `04_DwC_Melitaea_cinxia_2026.xlsx` |
| `05_oppdater_dwc_tidligere_aar.qmd` | Rettet DwC for 2022–2025 (event-ID-er, Plot_management, Østfold, occurrence med 0 %) med endringslogg | `05_Monitoring_Melitaea_cinxia_2022_2025_rettet.xlsx/.rds`, `05_occurrence_0_prosent_oversikt.xlsx` |
| `06_eventid_oversikt.qmd` | Oversikt over hvilke event-ID-er som ble endret i 05 | `06_eventid_oversikt.xlsx` |
| `07_sammenslatt.qmd` | Sammenslått analysedatasett 2022–2026 (ruter, sirkler, arter) | `07_sammenslatt_2022_2026.xlsx/.rds` |
| `08_analyser.qmd` | Analyser som tidligere år: spinnruter mot overvåkingsruter, endring over år, skjøtsel, NMDS, larvespinn, DHARMa-diagnostikk | `08_analyser_2022_2026.xlsx`, `08_nmds.rds`, `08_figurer/` |

## Inndata (`../data/`)

| Fil | Innhold |
|---|---|
| `Monitoring_Melitaea_cinxia_2025.xlsx` | Publisert DwC 2022–2025. Skal ikke overskrives; rettelsene havner i en ny fil (05). |
| `Effekt_prikkrutevinge_2025_cleaned.xlsx` | Renset datasett 2022–2025 |
| `Management plots 2022-2026_v2.xlsx` | Skjøtsel per rute og år (Ruben) |
| `Effekt_Prikk_2026_data_analyses_renamed_sheets.xlsx` | Survey123-eksport 2026 |
| `Effekt_prikkrutevinge_2024_export_dirty.xlsx` | Rådata 2024 (brukes bare i 01) |

## Pakker

readxl, dplyr, tidyr, stringr, openxlsx, here og knitr. 08 trenger i tillegg ggplot2,
lme4, lmerTest, DHARMa, vegan og ggrepel.

## Neste år

- Ruben legger inn en ny kolonne `management_<år>` i skjøtselsfila. Registreringene
  gjøres før årets tiltak, så kolonnen for år Å brukes fra registreringen i Å+1.
- 03 og 04 er skrevet for 2026-dataene, men 04 kan brukes som mal for DwC.
  De gamle DwC-skriptene fra 2022–2025 (prosjekt 154027) bør ikke brukes. Det er
  der de gjentatte rosettradene og arter med 0 % merket «present» kom fra.
- Bakgrunn for valgene (svar fra Ruben og Marianne, november 2026) står i
  sesjonssammendraget på P:, `156004_07_effektovervaking_2026_2030_prikkrutevinge/Analyser/2026/claude/`.
