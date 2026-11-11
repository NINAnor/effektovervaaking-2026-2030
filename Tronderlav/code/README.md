# Code – Trønderlav

Data cleaning, microclimate figures and thallus growth analyses for the translocation experiment with trønderlav (*Erioderma pedicellatum*). The report ([`../Tronderlav.qmd`](../Tronderlav.qmd)) shows the figures in [`../img/`](../img/) made by scripts 02 and 03, and calculates the survival table from `data/Area_lichens_*.xlsx`. These scripts are **not** part of the ecRxiv submission. `install_github_deps.R` is not preprocessing – it installs R packages that are not on conda-forge into the pixi environment (see [`../pixi.toml`](../pixi.toml)).

All paths use `here::here()`, so they point to the `Tronderlav/` folder.

| Script | Does | Output |
|---|---|---|
| `01_Data cleaning.qmd` | Reads and cleans the climate logger files in `data/Raw_climate_data/` | `data/daily_data.csv`, `data/daily_data_lux.csv`, and `all_data` in memory |
| `02_Climate data and figures.qmd` | Microclimate figures and comparisons with Tegningfallet | PNG figures in `img/` (air temperature, humidity, light, comparisons) |
| `03_Thallus growth analyses.qmd` | Mixed models for thallus size (locality and environmental variables), survival | `img/thallus_growth_rates.png`, `img/thalli_sizes.png`, `img/thalli_survival.png` |

**Run 01 and 02 in the same R session.** Script 02 uses the object `all_data`, which script 01 creates but does not save, so script 02 fails when it is rendered on its own.

## Each year

1. Put the new logger files in `data/Raw_climate_data/` and add the new year's thallus areas to `data/Area_lichens_*.xlsx` (and pH/conductivity to `data/ph data.xlsx` if measured).
2. Run scripts 01 and 02 in one R session, then script 03 (update the file name of the thallus data if it changes).
3. From the `Tronderlav/` folder, run `pixi run render` (first time: `pixi install`).
4. Update the result text in sections 6 and 7, the summaries, and `yearLastUpdate`, `Version`, `VersionComment` and the Log in `Tronderlav.qmd`.
