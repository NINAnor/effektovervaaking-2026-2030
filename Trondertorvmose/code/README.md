# Kode – Trøndertorvmose

Skript fra Fia Bengtsson for å lage Darwin Core-filer (Event, Occurrence, MeasurementOrFact) fra fastrutene som ble etablert i 2026 (Henningslettet, Korsmyra og Kaldal). Kopiert uendret fra `P:/154027_…/09 Trøndertorvmose/Effektovervåkning Kod Darwincore` 25. nov. 2026.

| Skript | Hva det gjør | Leser | Skriver |
|---|---|---|---|
| `Event_DarwinCore.R` | Lager Event-arket (én rad per rute) | `Vegetasjonsanalyser_overvåking_data COPY.xlsx` (ark «Lokaliteter») | `Event2.xlsx` |
| `Occurrence_DarwinCore.R` | Beregner frekvens per art og rute, kobler på navnevask, lager Occurrence (inkl. dekning av trøndertorvmose) og MeasurementOrFact (torvdybde) | `Vegetasjonsanalyser_overvåking_data COPY.xlsx`, `name_search_20_11_2026.xlsx`, `Event.xlsx` | `Frekvens_2026.xlsx`, (`EventCore_Troender2026_all species data.xlsx`, utkommentert) |

Merk: `Occurrence_DarwinCore.R` bruker objektet `Lokaliteter` fra `Event_DarwinCore.R`, så kjør `Event_DarwinCore.R` først i samme R-økt. Filstiene i skriptene peker til Fias egen PC; alle filene ligger i [`../data/`](../data/).

Datafilene i `data/`:

- `Vegetasjonsanalyser_overvåking_data.xlsx` og `Metadata trøndertorvmose.docx` – fra `09 Trøndertorvmose/Data`
- `Vegetasjonsanalyser_overvåking_data COPY.xlsx` – kopien skriptene leser (ikke identisk med filen over)
- `name_search_20_11_2026.xlsx` – resultat fra navnevask (Artsdatabanken)
- `Event.xlsx`, `Event2.xlsx`, `Frekvens_2026.xlsx` – mellomresultater
- `EventCore_Troender2026_all species data.xlsx`, `EventCore_Troender2026_troendelagicum_data.xlsx` – ferdige Darwin Core-filer
- `NINA_EventCore_importskjema_20201124 TRØNDER.xlsx` – NINAs importskjema
