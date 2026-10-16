# Effektovervåking 2026–2030

Code, cleaned data and yearly result summaries for NINA's monitoring of the effects of management actions for threatened species and habitat types in Norway (*Overvåking av effekter av tiltak for trua arter og naturtyper*), funded by the Norwegian Environment Agency.

Each subproject has its own folder. The folder's front page (`README.md`) is the subproject's result summary. It is generated from a Quarto document that follows the [ecRxiv](https://github.com/NINAnor/ecRxiv) custom template for this project, so it can later be submitted to ecRxiv with minimal changes.

Previous years' code: [NINAnor/effektovervaaking](https://github.com/NINAnor/effektovervaaking).

## Subprojects

| Folder | Species / habitat type | Status |
|---|---|---|
| [Apen-grunnlendt-kalkmark](Apen-grunnlendt-kalkmark/) | Åpen grunnlendt kalkmark i boreonemoral sone | not set up |
| [Dragehode](Dragehode/) | Dragehode (*Dracocephalum ruyschiana*) | not set up |
| [Honningblom](Honningblom/) | Honningblom (*Herminium monorchis*) | not set up |
| [Elvesandjeger](Elvesandjeger/) | Elvesandjeger (*Cicindela maritima*) | report draft, data 2015–2026 |
| [Stor-elvebreddedderkopp](Stor-elvebreddedderkopp/) | Stor elvebreddedderkopp (*Arctosa cinerea*) | report draft, data 2020–2026 |
| [Klippeblaavinge](Klippeblaavinge/) | Klippeblåvinge (*Scolitantides orion*) | not set up |
| [Prikkrutevinge](Prikkrutevinge/) | Prikkrutevinge (*Melitaea cinxia*) | not set up |
| [Tronderlav](Tronderlav/) | Trønderlav (*Erioderma pedicellatum*) | not set up |
| [Trondertorvmose](Trondertorvmose/) | Trøndertorvmose (*Sphagnum troendelagicum*) | not set up |

## Folder structure

```
Subproject/
├── Subproject.Rproj   # open this – here::here() then points to the subproject folder
├── Subproject.qmd     # result summary (ecRxiv template) – reads only data/ and img/
├── README.md          # generated from Subproject.qmd – do not edit by hand
├── _common.R          # ecRxiv helper functions (badges, metadata) – do not edit
├── references.bib
├── code/              # preprocessing: raw data on P: -> cleaned data in data/
├── data/              # cleaned data (master file, Darwin Core where possible)
└── img/               # figures (written by the .qmd) and photos
```

- **Raw data stay on P:** (`154027_effektovervaking_av_trua_arter_og_naturtyper_2024`). Only cleaned data go in `data/`.
- **Each subproject is free to organise `code/`** as it likes, as long as the cleaned data end up in `data/` and `code/README.md` explains the run order.
- **The `.qmd` reads only from `data/` and `img/`.** Anyone can then render it without access to P:, which ecRxiv requires.
- **No years in script names.** Git history keeps the old versions, so don't copy scripts each year.

A blank template for new subprojects is in [`templates/`](templates/).

## Each year

1. Run the preprocessing in `code/` on the new field data.
2. Replace the master/cleaned data file in `data/`.
3. Open the subproject's `.Rproj` and run `quarto render Subproject.qmd` in the terminal (renders both `README.md` and the `.html`).
4. Update `yearLastUpdate`, `Version`, `VersionComment` and the Log in the `.qmd`.
5. Commit and push.

Rendering requires the R packages `here`, `tidyverse`, `kableExtra`, `yaml`, `conflicted`, `dplyr` ≥ 1.2 and `anybadger` ≥ 0.1.1 (`remotes::install_github("lmeninato/anybadger")`).

## Submitting to ecRxiv

The subproject folder already matches an ecRxiv indicator folder. To submit:

1. Fork the [ecRxiv `template` branch](https://github.com/NINAnor/ecRxiv/tree/template).
2. Copy over `_common.R`, `data/`, `img/` and `references.bib`.
3. Copy `Subproject.qmd`, renamed to `R/<indicatorID>.qmd` (and `references.bib` alongside it).
4. Open a pull request to the `submission` branch.

Leave the `code/` preprocessing behind.

Apply for an indicator ID early: [apply for ID](https://github.com/NINAnor/ecRxiv/issues/new?template=apply_for_ID.yml).
