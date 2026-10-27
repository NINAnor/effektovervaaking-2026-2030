# Code – Stor elvebreddedderkopp

Preprocessing that turns the raw field data on P: into the files in [`../data/`](../data/) that the report reads. These scripts are **not** part of the ecRxiv submission. `install_github_deps.R` is not preprocessing – it installs GitHub-only R packages into the pixi environment (see [`../pixi.toml`](../pixi.toml)). They read from and write to `05 Elvedyr/Data` on P:.

| Script | Does | Output used by the report |
|---|---|---|
| `9_elvebreddedderkopp_master_and_heatmaps.R` | Master observation file with all years (+ density rasters) | `elvebreddedderkopp_obs_2020-2026_master.csv` |
| `10_elvebreddedderkopp_clearing_effect.R` | Links each September survey polygon to the clearing polygon it overlaps most, with clearing status the year before | `elvebreddedderkopp_2025-2026_analysis_data.csv` |

The lupin clearing data (`Lupinluking_2025_2026_clean.shp` and `lupin_clearing_by_site_*.csv`) are made by scripts 1–3 and 7 in [`Elvesandjeger/code/`](../../Elvesandjeger/code/) – run those first.

## Each year

1. Put the new field data on P:, run the clearing scripts in `Elvesandjeger/code/`, then scripts 9 and 10 here (update the years in them).
2. Replace the four files in [`../data/`](../data/) (master, clearing by site, analysis data, daily climate) with the new ones and delete the old ones. The report finds them by pattern (`*_master.csv`, `lupin_clearing_by_site_*.csv`, `*_analysis_data.csv`, `daily_climate_hydrology_*.csv`), so there must be exactly one of each.
3. From the `Stor-elvebreddedderkopp/` folder, run `pixi run render` (first time: `pixi install`).
4. Read through section 7 (interpretation) and update `yearLastUpdate`, `Version`, `VersionComment` and the Log in `Stor-elvebreddedderkopp.qmd`.

## Climate and hydrology

`daily_climate_hydrology_*.csv` in [`../data/`](../data/) is made by script 8 in [`Elvesandjeger/code/`](../../Elvesandjeger/code/) – replace it each year together with the Elvesandjeger copy. The report computes the exposure before each September visit and the exploratory models itself (as script 11 on P: did), so no other climate files are needed.

## Site map (section 3.1)

`make_map_data.R` builds everything the site map needs: `data/kart_elvedyr.gpkg` (Norway outline, Gaula from NVE Elvenett, a convex hull per site around the lupin clearing polygons and around the spider survey polygons, and the square frame per site), `data/ortofoto_<site>.jpg` (Norge i bilder orthophoto for each frame, from the open Geonorge WMS) and `img/foto_<site>.jpg` (the site photos by Arne Endre Laugsand, turned upright). It reads from P: and the R: drive (`/data/R/GeoSpatialData`), and downloads the orthophotos from the internet. Rerun it when the clearing polygons, the spider polygons or the photos change: `pixi run Rscript code/make_map_data.R`.

## Font

The figures use Aptos when it is installed, and otherwise fall back to the default sans-serif font. Aptos comes with Microsoft 365. On the NINA RStudio server it is installed per user in `~/.local/share/fonts/Aptos` (download: Microsoft Aptos Fonts from download.microsoft.com). The font files are not part of the repo because their licence does not allow redistribution.
