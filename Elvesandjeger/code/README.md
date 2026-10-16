# Code – Elvesandjeger

Preprocessing that turns the raw field data and the lupin clearing data on P: into the files in [`../data/`](../data/) that the report reads. These scripts are **not** part of the ecRxiv submission. They read from and write to `05 Elvedyr/Data` on P:.

| Script | Does | Output used by the report |
|---|---|---|
| `1_lupinluking_overlay_2025_2026.R` | Combines this year's lupin clearing polygons from MidNat with last year's, so the clearing history follows the new geometry | – |
| `2_lupinluking_merge_polygons.R` | Merges/deletes small pieces identified in GIS | – |
| `3_lupinluking_snap_clean.R` | Topological cleaning; one block of `Luket`/`Antall` per year | `Lupinluking_2025_2026_clean.shp` (on P:) |
| `6_elvesandjeger_master_and_rebuild_heatmaps.R` | Master observation file with all years (+ density rasters) | `elvesandjeger_obs_2015-2026_master.csv` |
| `7_elvesandjeger_clearing_effect_2026.R` | Clearing per site and per polygon, and links each survey polygon to the clearing polygon it overlaps most | `lupin_clearing_by_site_2020-2026.csv`, `lupin_clearing_polygon_panel_2020-2026.csv`, `elvesandjeger_2026_analysis_data.csv` |

Scripts 1–3 and 7 also produce the clearing data used by [Stor-elvebreddedderkopp](../../Stor-elvebreddedderkopp/).

## Each year

1. Put the new field data, the MidNat clearing polygons and the NVE/MET series on P:, and run scripts 1–3, 6, 7 and 8 (update the years in them).
2. Replace the files in [`../data/`](../data/) with the new ones and delete the old ones. The report finds them by pattern (`*_master.csv`, `lupin_clearing_by_site_*.csv`, `lupin_clearing_polygon_panel_*.csv`, `*_analysis_data.csv`, `daily_climate_hydrology_*.csv`, `climate_hydrology_yearly_*.csv`), so there must be exactly one of each.
   - The analysis data must contain the columns `Luket_yy` for the year before the survey, `years_cleared_*` and `lupins*_per_m2`. The report picks up the right year automatically.
3. Copy `lupin_clearing_by_site_*.csv` to `../../Stor-elvebreddedderkopp/data/` as well.
4. From the repo root, run `pixi run render-elvesandjeger`.
5. Read through section 7 (interpretation) and update `yearLastUpdate`, `Version`, `VersionComment` and the Log in `Elvesandjeger.qmd`.

## Climate and hydrology

`8_elvesandjeger_climate_hydrology_2026.R` combines discharge and water level at Gaulfoss (NVE 122.9.0), precipitation and snow at Leinstrand (MET SN67150) and temperature at E6 Kvål (MET SN67175) into `daily_climate_hydrology_*.csv` and `climate_hydrology_yearly_*.csv`. Each year: download the new NVE and MET series to `05 Elvedyr/Data`, run script 8, and replace both files in [`../data/`](../data/). Copy the daily file to `../../Stor-elvebreddedderkopp/data/` as well. The reports compute the exposure before each visit and the exploratory models themselves, so the other outputs of script 8 are not needed.
