# Effektovervåking 2026–2030

Code, cleaned data and yearly result summaries for NINA's monitoring of the effects of management actions for threatened species and habitat types in Norway (*Overvåking av effekter av tiltak for trua arter og naturtyper*), funded by the Norwegian Environment Agency.

**Read the reports:** <https://ninanor.github.io/effektovervaaking-2026-2030/>

Each subproject has its own folder, with its report written in a Quarto document (`.qmd`) that follows the [ecRxiv](https://github.com/NINAnor/ecRxiv) custom template for this project. Each report is published in two ways:

- as a chapter in the repository's Quarto book (the website above), rebuilt automatically on every push to `main`
- as the subproject's `README.md`, shown on its folder page here on GitHub, rendered from the same `.qmd`

The reports can later be submitted to ecRxiv with minimal changes.

Previous years' code: [NINAnor/effektovervaaking](https://github.com/NINAnor/effektovervaaking).

## Subprojects

In the order they appear in the book.

| Folder | Species / habitat type | 2026 report |
|---|---|---|
| [Apen-grunnlendt-kalkmark](Apen-grunnlendt-kalkmark/) | Åpen grunnlendt kalkmark i boreonemoral sone | ✔ |
| [Dragehode](Dragehode/) | Dragehode (*Dracocephalum ruyschiana*) | ✔ |
| [Honningblom](Honningblom/) | Honningblom (*Herminium monorchis*) | ✔ |
| [Elvesandjeger](Elvesandjeger/) | Elvesandjeger (*Cicindela maritima*) | ✔ |
| [Stor-elvebreddedderkopp](Stor-elvebreddedderkopp/) | Stor elvebreddedderkopp (*Arctosa cinerea*) | ✔ |
| [Klippeblaavinge](Klippeblaavinge/) | Klippeblåvinge (*Scolitantides orion*) | ✔ |
| [Prikkrutevinge](Prikkrutevinge/) | Prikkrutevinge (*Melitaea cinxia*) | ✔ |
| [Tronderlav](Tronderlav/) | Trønderlav (*Erioderma pedicellatum*) | ✔ |
| [Rod-skogfrue](Rod-skogfrue/) | Rød skogfrue (*Cephalanthera rubra*) | ✔ |
| [Svartkurle](Svartkurle/) | Svartkurle (*Nigritella nigra*) | ✔ |
| [Trondertorvmose](Trondertorvmose/) | Trøndertorvmose (*Sphagnum troendelagicum*) | ✔ |
| [Askeglye](Askeglye/) | Askeglye (*Collema leptaleum*) | ✔ |
| [Stjernebonnelav](Stjernebonnelav/) | Stjernebønnelav (*Buellia asterella*) | ✔ |
| [Kystlynghei](Kystlynghei/) | Kystlynghei | ✔ separate repository (submodule) |
| [effektovervaking_forests](effektovervaking_forests/) | Olivinskog and kalklindeskog | ✔ separate repository (submodule) |
| [Eremitt](Eremitt/) | Eremitt (*Osmoderma eremita*) | not set up |

## Folder structure

```
Subproject/
├── Subproject.Rproj   # open this – here::here() then points to the subproject folder
├── pixi.toml          # the subproject's software environment (+ pixi.lock)
├── Subproject.qmd     # the report (ecRxiv template) – reads only data/ and img/
├── README.md          # rendered from Subproject.qmd – do not edit by hand
├── _common.R          # ecRxiv helper functions (badges, metadata) – do not edit
├── references.bib
├── code/              # preprocessing and analysis scripts: raw data on P: -> data/ and img/
├── data/              # cleaned data: master file, clearing/management data, analysis data (DwC where possible)
└── img/               # figures and photos used in the report
```

- **Raw data stay on P:** (`154027_effektovervaking_av_trua_arter_og_naturtyper_2024`). Only cleaned data go in `data/`.
- **Each subproject is free to organise `code/`** as it likes, as long as the cleaned data end up in `data/` and `code/README.md` explains the run order.
- **The `.qmd` reads only from `data/` and `img/`.** Anyone can then render it without access to P:, which ecRxiv requires.
- **No years in script names.** Git history keeps the old versions, so don't copy scripts each year.
- **Labels for figures and tables must be unique across the whole book**, for example `fig-kart-dragehode`, not `fig-kart`. Cross-references on the website resolve across all chapters, so a label used in two reports points to the wrong one.

A blank template for new subprojects is in [`templates/`](templates/).

## Software environment

Use the repository-root [Pixi](https://pixi.sh) environment to build the complete book. It contains the R, Quarto and package dependencies used by the report `.qmd` files; dependencies needed only for preprocessing are not required for this build.

Every subproject with a report also has its own Pixi environment, used to render that report's `README.md` and to work on it independently. [Klippeblaavinge](Klippeblaavinge/) is the exception to the usual setup: its default environment is the Python environment for the analyses in `code/`, and the report is rendered with the separate `report` environment (`pixi run -e report render`).

```bash
# once: install pixi (https://pixi.sh/latest/#installation), then from the subproject folder
cd Stor-elvebreddedderkopp
pixi install

# render the subproject report and its README.md
pixi run render

# or work interactively with that subproject's R / Quarto
pixi shell
```

Packages that are not on conda-forge (`anybadger`, used by ecRxiv's `_common.R`) are installed from a pinned public source archive by `code/install_github_deps.R` the first time `pixi run render` runs. To add an R package, run `pixi add r-<package>` (conda-forge names) in the subproject folder.

The repository root is a Quarto book (`_quarto.yml`, `index.qmd`) that renders the subproject `.qmd` reports directly and is published to GitHub Pages on every push to `main`. Kystlynghei and `effektovervaking_forests` are included as Git submodules. Clone with `git clone --recurse-submodules`, or initialize/update submodules with `git submodule update --init --recursive`. Published releases are also available under `/versions/<tag>/`; creating a release with the **Release Quarto book** workflow rebuilds Pages to include it. The shared Pixi environment is defined in the root `pixi.toml` and locked in `pixi.lock`. Add a report's `.qmd` to `chapters` in `_quarto.yml` when it should appear on the website. The website build does not run preprocessing or regenerate the subproject `README.md` files.

```bash
# from the repository root
pixi install --locked
pixi run render-site
```

## Troubleshooting

- **`ERROR: database is locked`** when installing or rendering from a clone on the P: drive: the drive may be causing compatibility or file-access issues. Clone the repository to a different storage location, such as your home folder, and try again. If the problem persists, use a VDI environment.
- **`Book chapter '…' not found`** when rendering a single subproject: rendering inside the repository uses the book configuration, which needs the submodules. Run `git submodule update --init --recursive` first.

## Each year

1. Run the preprocessing in `code/` on the new field data and management (e.g. clearing) data.
2. Replace the cleaned data files in `data/`. The reports find their files by pattern, so the year in the file name can change, but there must be exactly one file of each kind.
3. Render the report from the subproject folder with `pixi run render`, which also updates its `README.md`. Check that numbers in the result text still match the figures and tables.
4. Read through the interpretation in section 7, and update `yearLastUpdate`, `Version`, `VersionComment` and the Log in the `.qmd`.
5. Commit and push. The website is rebuilt automatically.

## Submitting to ecRxiv

The subproject folder already matches an ecRxiv indicator folder. To submit:

1. Fork the [ecRxiv `template` branch](https://github.com/NINAnor/ecRxiv/tree/template).
2. Copy over `_common.R`, `data/`, `img/` and `references.bib`.
3. Copy `Subproject.qmd`, renamed to `R/<indicatorID>.qmd` (and `references.bib` alongside it).
4. Open a pull request to the `submission` branch.

Leave the `code/` preprocessing behind.

Apply for an indicator ID early: [apply for ID](https://github.com/NINAnor/ecRxiv/issues/new?template=apply_for_ID.yml).
