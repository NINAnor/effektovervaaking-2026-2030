# Code – Elvesandjeger

Preprocessing that turns the raw field data on P: into the master file used by the report.
These scripts are **not** part of the ecRxiv submission.

| Script | Reads (P:) | Writes |
|---|---|---|
| `6_elvesandjeger_master_and_rebuild_heatmaps.R` | `05 Elvedyr/Data/Elvesandjeger/elvesandjeger_obs_2015-2025.csv`, `.../2026/Elvesandjeger.shp` | `elvesandjeger_obs_2015-2026_master.csv` (+ shapefile and August density rasters) on P: |

Copied unchanged from `05 Elvedyr/Scripts/2026/`. It still uses `setwd()` to the P: data folder.

## Each year

1. Add the new year's field data on P: and run the script(s) above.
2. Copy the new `*_master.csv` into [`../data/`](../data/) and delete the old one (the report expects exactly one `*_master.csv`).
3. From the `Elvesandjeger/` folder run `quarto render Elvesandjeger.qmd` – this updates `README.md` (shown on GitHub) and `Elvesandjeger.html` (for ecRxiv).
4. In the YAML of `Elvesandjeger.qmd`, update `yearLastUpdate`, `Version` and `VersionComment`, and add a line to the Log.
