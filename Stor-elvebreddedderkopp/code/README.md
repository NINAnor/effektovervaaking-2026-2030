# Code – Stor elvebreddedderkopp

Preprocessing that turns the raw field data on P: into the master file used by the report.
These scripts are **not** part of the ecRxiv submission.

| Script | Reads (P:) | Writes |
|---|---|---|
| `9_elvebreddedderkopp_master_and_heatmaps.R` | `05 Elvedyr/Data/Elevebreddedderkopp/elvesbreddedderkopp_obs_2020-2024.csv`, `.../2026/EFFEKT_-_Elvebreddedderkopp_2024-2026.gpkg` | `elvebreddedderkopp_obs_2020-2026_master.csv` (+ shapefile and September density rasters) on P: |

Copied unchanged from `05 Elvedyr/Scripts/2026/`. It still uses `setwd()` to the P: data folder.

## Each year

1. Add the new year's field data on P: and run the script(s) above.
2. Copy the new `*_master.csv` into [`../data/`](../data/) and delete the old one (the report expects exactly one `*_master.csv`).
3. From the `Stor-elvebreddedderkopp/` folder run `quarto render Stor-elvebreddedderkopp.qmd` – this updates `README.md` (shown on GitHub) and the `.html` (for ecRxiv).
4. In the YAML of `Stor-elvebreddedderkopp.qmd`, update `yearLastUpdate`, `Version` and `VersionComment`, and add a line to the Log.
