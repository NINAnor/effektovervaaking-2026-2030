# Code – Dragehode

Preprocessing that turns the Survey123 field data and the basic monitoring data for dragehode into the files in [`../data/`](../data/) that the report ([`../Dragehode.qmd`](../Dragehode.qmd)) reads. These scripts are **not** part of the ecRxiv submission. The helper functions are in [`../Rsource/`](../Rsource/). `install_github_deps.R` is not preprocessing – it installs R packages that are not on conda-forge into the pixi environment (see [`../pixi.toml`](../pixi.toml)).

Render each script from the `Dragehode/` folder, for example `pixi run quarto render code/3_merging_data.qmd`. All paths use `here::here()`, so they point to the `Dragehode/` folder.

## Management experiment (skjøtselsforsøket, 2023–)

| Script | Does | Output |
|---|---|---|
| `1a_unpack_survey123.qmd` | Unpacks the Survey123 export (file geodatabase) and joins the main table and the repeat tables | `data/S123_<year>/Effekt_dragehode_<year>_processed/Effekt_dragehode_<year>_raw.xlsx` |
| `1b_standardize_table.qmd` | Standardises column names and structure | `…_export_dirty.xlsx` |
| `2_table_diagnostics_and_cleaning.qmd` | Data cleaning (test registrations, plot names, species names) and diagnostics | `…_processed/Exports/Effekt_dragehode_<year>_data_analyses.xlsx` and a diagnostics folder |
| `3_merging_data.qmd` | Adds this year's data to the cleaned data from earlier years | `data/Dragehode_2023_2026_analyses.xlsx` (read by the report) |
| `4_analyses_dragehode.qmd` | Ruben's analyses and figures (ANOVA, NMDS, PERMANOVA) | PNG figures in `img/` |

Scripts 1a, 1b and 2 were written by Ida M. Mienna (survey123-vegetation-data workflow). The raw Survey123 export is on P: (`03 Dragehode/Dracocephalum/Dragehode_<year>/Leveranse/`). Unzip the `.gdb` folder into `data/S123_<year>/` before running script 1a; `.gdb` folders are not committed (see `.gitignore`).

The report does its own analyses from `data/Dragehode_2023_2026_analyses.xlsx` (mixed models with plot as random effect). Script 4 is kept as Ruben's original analysis; its figures are not used in the report.

## Basic monitoring at Horgen (basisovervåking, 2017–)

| Script | Does | Output |
|---|---|---|
| `5_Horgen_population_monitoring.qmd` | Population estimates for the whole site (bootstrap) and a Bayesian trend model (`rstanarm`), Horgen only | `data/derived_data/Horgen/populasjonsestimater_Horgen.csv` and `trendoppsummering_Horgen.csv` (read by the report), intermediate files in `data/derived_data/` |

Input: `data/Dragehode_overvåking_DATA_<year>.xlsx` (sheets Lokalitetsdata, Transektdata, Rutedata and Artsdata) and `data/siriskuddogind.xlsx` (shoot-to-individual calibration for 2019–2020). Written by Olav Skarpaas, Matthew Grainger and Ruben Erik Roos, based on <https://ninanor.github.io/Dragehode/>.

## Each year

1. Put the new Survey123 export in `data/S123_<year>/` and run scripts 1a, 1b and 2 (update the file paths and the project name at the top of each script, and add new cleaning steps in script 2).
2. Run script 3 with the new year's export. Rename the output file if the years in the name change; the report reads `data/Dragehode_2023_2026_analyses.xlsx`.
3. Put the new basic monitoring workbook in `data/` and update `datafil` in script 5, then run it.
4. From the `Dragehode/` folder, run `pixi run render` (first time: `pixi install`).
5. Update the result text in sections 6 and 7, the summaries, the data-collection table in section 3.2 (mowing dates), and `yearLastUpdate`, `Version`, `VersionComment` and the Log in `Dragehode.qmd`.
