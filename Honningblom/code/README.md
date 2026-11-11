# Code – Honningblom

Preprocessing, figures and population estimates for honningblom (*Herminium monorchis*) on Hvaler. The report ([`../Honningblom.qmd`](../Honningblom.qmd)) does no analyses itself: it shows the figures in [`../img/`](../img/) made by scripts 5 and 6. These scripts are **not** part of the ecRxiv submission. Helper functions are in [`../Rsource/`](../Rsource/). `install_github_deps.R` is not preprocessing – it installs R packages that are not on conda-forge into the pixi environment (see [`../pixi.toml`](../pixi.toml)).

Render each script from the `Honningblom/` folder, for example `pixi run quarto render code/3_cleaning_and_merging_data.qmd`. All paths use `here::here()`, so they point to the `Honningblom/` folder.

| Script | Does | Output |
|---|---|---|
| `1a_from_survey123_to_dirty_table_2026.qmd` | Unpacks the Survey123 export for the plots (FGDB zip) | `data/S123_2026/Honningblom_2026_processed/Honningblom_2026_export_dirty.xlsx` |
| `1b_unpack_survey123_transect.qmd` | Unpacks the Survey123 export for the transects | `data/S123_2026/Honningblom_2026_transect_processed/Honningblom_2026_transect_raw.xlsx` |
| `1c_standardize_table_transect.qmd` | Standardises column names for the transect table | `…_transect_processed/Honningblom_2026_transect_transect_export_dirty.xlsx` |
| `2a_table_diagnostics_and_cleaning_2026.qmd` | Cleaning and diagnostics, plots | `data/S123_2026/Exports/Honningblom_2026_data_analyses.xlsx`, `data/S123_2026/Diagnostics/` |
| `2b_table_diagnostics_and_cleaning_transect.qmd` | Diagnostics, transects | `data/S123_2026/Exports/Honningblom_2026_transect_data_analyses.xlsx`, `data/S123_2026/Diagnostics/` |
| `3_cleaning_and_merging_data.qmd` | Adds the 2026 plot and transect data to the 2014–2025 masterfile | `data/Herminium_monorchis_masterfile_v_2026.xlsx` |
| `4_data_to_DwC.qmd` | Converts the 2026 data to Darwin Core (Event, Occurrence, MeasurementOrFact) | `data/Herminium_Monitoring_NINA_EventCore_2026.xlsx` |
| `5_Plot based counts.qmd` | Figures: individuals per plot per site, share of fertile individuals | `img/<site>_antall.jpg`, `img/Andel_fertile_per_lokalitet.jpg` |
| `6_Herminium_population_estimates.qmd` | Population estimates per site with bootstrap confidence intervals (functions by Bård Pedersen in `Rsource/Rfunctions_honningblom26.R`) | `data/Herminium_pop_2026.csv`, `data/pop2026.txt`, `img/Alle_lokaliteter.png` |

Scripts 1–2 were written by Ida M. Mienna (survey123-vegetation-data workflow). Scripts 1a/1b read the raw Survey123 exports (`S123_*_FGDB.zip`) from `data/S123_2026/`, and script 4 reads the DwC import template (`Herminium_Monitoring_NINA_EventCore_importskjema_2025.xlsx`) from `data/`. Zip files are not committed (see `.gitignore`).

Script 6 draws 2000 bootstrap samples per site without a fixed seed, so the confidence intervals (and `img/Alle_lokaliteter.png`) change slightly every time it is run. The point estimates do not change.

## Each year

1. Put the new Survey123 exports in `data/S123_<year>/` and run scripts 1a–2b (update the file paths and project name at the top of each script, and add new cleaning steps in 2a/2b).
2. Run script 3 to make the new masterfile, then scripts 5 and 6 (update the masterfile name in both), and script 4 for the DwC export.
3. From the `Honningblom/` folder, run `pixi run render` (first time: `pixi install`).
4. Update the result text in sections 6 and 7, the summaries, and `yearLastUpdate`, `Version`, `VersionComment` and the Log in `Honningblom.qmd`.
