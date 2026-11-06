# Effektovervåking 2026–2030

Code, cleaned data and yearly result summaries for NINA's monitoring of the effects of management actions for threatened species and habitat types in Norway (*Overvåking av effekter av tiltak for trua arter og naturtyper*), funded by the Norwegian Environment Agency.

Each subproject has its own folder, with its report authored in a Quarto document (`.qmd`) that follows the [ecRxiv](https://github.com/NINAnor/ecRxiv) custom template for this project. We no longer build a `README.md` from these reports. The reports are rendered as part of the repository's Quarto book and can later be submitted to ecRxiv with minimal changes.

Previous years' code: [NINAnor/effektovervaaking](https://github.com/NINAnor/effektovervaaking).

## Subprojects

| Folder | Species / habitat type | Status |
|---|---|---|
| [Apen-grunnlendt-kalkmark](Apen-grunnlendt-kalkmark/) | Åpen grunnlendt kalkmark i boreonemoral sone | not set up |
| [Dragehode](Dragehode/) | Dragehode (*Dracocephalum ruyschiana*) | report draft, mowing experiment 2023–2026 and basic monitoring at Horgen 2017–2026 |
| [Honningblom](Honningblom/) | Honningblom (*Herminium monorchis*) | not set up |
| [Elvesandjeger](Elvesandjeger/) | Elvesandjeger (*Cicindela maritima*) | report draft, data 2015–2026, effect of lupin clearing, climate and hydrology |
| [Stor-elvebreddedderkopp](Stor-elvebreddedderkopp/) | Stor elvebreddedderkopp (*Arctosa cinerea*) | report draft, data 2020–2026, effect of lupin clearing, climate and hydrology |
| [Kystlynghei](Kystlynghei/) | Kystlynghei | report draft, satellite monitoring of succession and management effects |
| [Klippeblaavinge](Klippeblaavinge/) | Klippeblåvinge (*Scolitantides orion*) | not set up |
| [Prikkrutevinge](Prikkrutevinge/) | Prikkrutevinge (*Melitaea cinxia*) | not set up |
| [Tronderlav](Tronderlav/) | Trønderlav (*Erioderma pedicellatum*) | not set up |
| [Trondertorvmose](Trondertorvmose/) | Trøndertorvmose (*Sphagnum troendelagicum*) | not set up |

## Folder structure

```
Subproject/
├── Subproject.Rproj   # open this – here::here() then points to the subproject folder
├── pixi.toml          # optional: a subproject-specific software environment (+ pixi.lock)
├── Subproject.qmd     # result summary (ecRxiv template) – reads only data/ and img/
├── _common.R          # ecRxiv helper functions (badges, metadata) – do not edit
├── references.bib
├── code/              # preprocessing: raw data on P: -> cleaned data in data/
├── data/              # cleaned data: master file, clearing/management data, analysis data (DwC where possible)
└── img/               # figures (written by the .qmd) and photos
```

- **Raw data stay on P:** (`154027_effektovervaking_av_trua_arter_og_naturtyper_2024`). Only cleaned data go in `data/`.
- **Each subproject is free to organise `code/`** as it likes, as long as the cleaned data end up in `data/` and `code/README.md` explains the run order.
- **The `.qmd` reads only from `data/` and `img/`.** Anyone can then render it without access to P:, which ecRxiv requires.
- **No years in script names.** Git history keeps the old versions, so don't copy scripts each year.

A blank template for new subprojects is in [`templates/`](templates/).

## Software environment

Use the repository-root [Pixi](https://pixi.sh) environment to build the complete book/report. It contains the R, Quarto and package dependencies used by the report `.qmd` files in the book; dependencies needed only for preprocessing are not required for this build. You do not need to install every tool used anywhere in a subproject's `code/` folder.

Each subproject can independently choose whether to maintain its own Pixi project. A separate environment is optional and useful when a subproject needs to be rendered or worked on independently; it is not required to build the whole book. The Elvedyr subprojects ([Elvesandjeger](Elvesandjeger/), [Stor-elvebreddedderkopp](Stor-elvebreddedderkopp/)) and [Dragehode](Dragehode/) currently have their own Pixi environments.

```bash
# once: install pixi (https://pixi.sh/latest/#installation), then from the subproject folder
cd Stor-elvebreddedderkopp
pixi install

# render the subproject report independently (when using its own Pixi environment)
pixi run render

# or work interactively with that subproject's R / Quarto
pixi shell
```

Packages that are not on conda-forge (`anybadger`, used by ecRxiv's `_common.R`) are installed from a pinned public source archive by `code/install_github_deps.R` the first time `pixi run render` runs. To add an R package, run `pixi add r-<package>` (conda-forge names) in the subproject folder.

The repository root is a Quarto book (`_quarto.yml`, `index.qmd`) that renders the subproject `.qmd` reports directly and is published to GitHub Pages on every push to `main`. Kystlynghei is included as a Git submodule. Its report links to the published report, and its methodology chapter is rendered directly from `Kystlynghei/report/kystlynghei_methods.qmd`. Clone with `git clone --recurse-submodules`, or initialize/update submodules with `git submodule update --init --recursive`. Published releases are also available under `/versions/<tag>/`; creating a release with the **Release Quarto book** workflow rebuilds Pages to include it. The shared Pixi environment is defined in the root `pixi.toml` and locked in `pixi.lock`. Add a report's `.qmd` to `chapters` in `_quarto.yml` when it should appear on the website. The website build does not run preprocessing or generate subproject `README.md` files.

```bash
# from the repository root
pixi install --locked
pixi run render-site
```

## Each year

1. Run the preprocessing in `code/` on the new field data and management (e.g. clearing) data.
2. Replace the cleaned data files in `data/`. The reports find their files by pattern, so the year in the file name can change, but there must be exactly one file of each kind.
3. Render the complete book from the repository root with `pixi run render-site`. This renders the reports from their `.qmd` sources; it does not generate `README.md` files. If a subproject has its own Pixi environment, you can also render that report independently from its folder.
4. Read through the interpretation in section 7, and update `yearLastUpdate`, `Version`, `VersionComment` and the Log in the `.qmd`.
5. Commit and push.

## Submitting to ecRxiv

The subproject folder already matches an ecRxiv indicator folder. To submit:

1. Fork the [ecRxiv `template` branch](https://github.com/NINAnor/ecRxiv/tree/template).
2. Copy over `_common.R`, `data/`, `img/` and `references.bib`.
3. Copy `Subproject.qmd`, renamed to `R/<indicatorID>.qmd` (and `references.bib` alongside it).
4. Open a pull request to the `submission` branch.

Leave the `code/` preprocessing behind.

Apply for an indicator ID early: [apply for ID](https://github.com/NINAnor/ecRxiv/issues/new?template=apply_for_ID.yml).
