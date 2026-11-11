# Klippeblåvinge – analysis scripts

Python scripts for the egg microhabitat analysis (smørbukk with and without
eggs of *Scolitantides orion*, 2026) and the habitat suitability model for
Halden festning. Raw data stay on P:. The scripts write cleaned tables to
`../data/` and figures to `../img/`. Caches and QA files go to a work folder on P:.

## Running

The environment is defined in `../pixi.toml`. From `Klippeblaavinge/`:

```sh
pixi run analyse          # everything, in order
pixi run planter          # or one step at a time (dependencies run first)
```

Or run a single script directly: `cd code; pixi run python 3_habitatmodell.py`.

| Script | Does | Writes |
|---|---|---|
| `1_planter.py` | Survey points → duplicate QA, neighbour counts, locality, LiDAR 2022 terrain (slope, aspect, relative height, height above ground), horizons to 500 m and clear-sky solar exposure 15 May–30 June per plant | `data/smorbukk_planter.csv` |
| `2_vegetasjonsdekke.py` | Vegetation cover around plants and random points from the drone orthophotos; comparison with PlanetScope NDVI | `data/vegetasjonsdekke_punkter.csv`, `data/ndvi_vegetasjonsdekke_klasser.csv`, `img/figur_5_…` |
| `3_habitatmodell.py` | 2 m predictor grid for Halden festning, presence-background habitat model, leave-one-locality-out validation, high-confidence habitat and egg-laying potential | `data/habitatmodell_*.csv`, `data/habitat_hoy_sikkerhet.gpkg`, `img/figur_3_…`, `img/figur_4_…` |
| `4_egg_test.py` | 16 variables tested for egg vs no egg within localities (AUC, permutation test, Benjamini–Hochberg) | `data/egg_vs_ikke_egg.csv`, `data/egg_test_nokkeltall.csv`, `img/figur_2_…` |
| `5_figur_3d_gyldenlove.py` | 3D view of Gyldenløve from the drone point cloud, with plants | `img/figur_1_3d_gyldenlove.jpg` |

`config.py` holds all paths and settings. `felles.py` holds shared functions
(terrain, horizons, solar, statistics, figure style).

Script 4 needs the predictor raster written by script 3. Script 1 takes a few
minutes. Script 3 takes about 5 minutes, mostly for the sun map. Both cache
intermediate results in the work folder.

## Input data (on P:)

| Data | Path in `config.py` |
|---|---|
| Smørbukk GNSS survey 2025–2026 with egg status | `SMORBUKK_SHP` |
| Drone DSMs and orthophotos (Overberget, Borgerskansen 2025; Gyldenløve 2026) | `SITES` |
| Gyldenløve drone point cloud and GNSS export (script 5) | `GYLDENLOVE_PC`, `GYLDENLOVE_GNSS` |
| National LiDAR 2022 DTM/DOM (Viken laser – Østfold 5 pkt, 0.25 m) | `LIDAR` |
| PlanetScope indices, August 2025 | `PLANETSCOPE` |
| Study area outline, Halden festning | `STUDY_AREA` |

PlanetScope imagery is under licence and is not stored in the repository.

To run with data somewhere else, set these environment variables:

- `KLIPPEBLAAVINGE_P`: project folder (default `P:/156004_06_effektovervaking_2026_2030_klippeblavinge`)
- `KLIPPEBLAAVINGE_WORK`: cache/QA folder (default `<P>/output_klippeblavinge_python`)
- `KLIPPEBLAAVINGE_GYLDENLOVE_PC`, `KLIPPEBLAAVINGE_GYLDENLOVE_GNSS`: point cloud and GNSS export for script 5
- `KLIPPEBLAAVINGE_LIDAR`, `KLIPPEBLAAVINGE_PLANETSCOPE`, `KLIPPEBLAAVINGE_STUDY_AREA`: override single inputs (see `config.py`)
- `KLIPPEBLAAVINGE_N_PERM`: permutations in script 4 (default 9999)

## Methods in brief

- Slope and aspect: Horn (1981), averaged within 1 and 5 m of each plant.
- Solar exposure: sun positions and Ineichen clear-sky irradiance from pvlib.
  Diffuse light uses Hay–Davies. Horizons are ray-traced over the LiDAR DOM in
  72 directions to 500 m, and sky-view factor follows Dozier & Frew (1990).
  Values are on a plane fitted to the terrain within 1 m of each plant.
- Vegetation cover: excess green or saturated yellow-brown pixels with Otsu thresholds; shadows excluded.
- Egg vs no egg: AUC within locality, weighted by egg plants; egg labels permuted within locality.
- Habitat model: logistic presence-background GLM (linear + squared terms).
  "High confidence" means the full model and all three leave-one-locality-out
  models agree.

Height above ground (DOM − DTM) increases with slope because the LiDAR models
diverge on steep faces. It is reported but not interpreted as plant height.
