"""4. Smørbukk with and without eggs (2026): all tested variables, with tests
within localities.

Input: data/smorbukk_planter.csv, data/vegetasjonsdekke_punkter.csv,
WORK/prediktorer_2m.tif (tree cover and NDVI at the plants, from 3_habitatmodell.py).
Output: data/egg_vs_ikke_egg.csv, data/egg_test_nokkeltall.csv,
img/figur_2_egg_variabler_rangert.png.

For each variable: medians, direction of the difference at each locality, an
AUC calculated within each locality and averaged (weighted by egg plants), a
two-sided permutation p-value with egg labels shuffled within localities, and
Benjamini-Hochberg q-values. Localities differ strongly in egg share, so
pooled tests would mix locality and habitat. Height above ground is re-tested
after removing its slope trend within each locality.
"""

import numpy as np
import pandas as pd
import rasterio
from pyproj import Transformer

import config as C
from felles import (COL_EGG, COL_NO, TXT_DARK, TXT_LIGHT, bh_adjust, figure_style, log, need, save_png,
                    strat_auc)

rng = np.random.default_rng(2026)
plt = figure_style()
SITES = list(C.SITE_LABELS.values())

plants = pd.read_csv(C.DATA / "smorbukk_planter.csv")
plants = plants[plants.site.isin(SITES)].copy()
veg = pd.read_csv(C.DATA / "vegetasjonsdekke_punkter.csv").dropna(subset=["plant_row_id"])
veg = veg.astype({"plant_row_id": int}).groupby("plant_row_id")[["veg_1m", "veg_5m"]].first() * 100
plants = plants.join(veg, on="plant_row_id")
need(C.WORK / "prediktorer_2m.tif", "Predictor raster (run 3_habitatmodell.py first)")
with rasterio.open(C.WORK / "prediktorer_2m.tif") as r:
    names = list(r.descriptions)
    x, y = Transformer.from_crs(C.WORKING_EPSG, r.crs, always_xy=True).transform(plants.x_m.to_numpy(),
                                                                                plants.y_m.to_numpy())
    vals = np.array(list(r.sample(zip(x, y))))
plants["tree_10m"] = vals[:, names.index("tree_10m")] * 100
plants["ndvi"] = vals[:, names.index("ndvi")]

VARS = [  # column, English label, unit, source and scale, Norwegian figure label
    ("slope_deg_1m", "Slope", "°", "LiDAR DTM 2022, within 1 m", "Helning innen 1 m (°)"),
    ("slope_deg_5m", "Slope", "°", "LiDAR DTM 2022, within 5 m", "Helning innen 5 m (°)"),
    ("northness_1m", "North-facing (−1 S … +1 N)", "", "LiDAR DTM 2022, within 1 m", "Nordvendthet (−1 sør … +1 nord)"),
    ("eastness_1m", "East-facing (−1 W … +1 E)", "", "LiDAR DTM 2022, within 1 m", "Østvendthet (−1 vest … +1 øst)"),
    ("tpi_5m", "Relative position (+ ledge, − hollow)", "m", "LiDAR DTM 2022, 1 m vs 5 m", "Relativ høyde innen 5 m (m)"),
    ("solar_kwh_m2_day", "Clear-sky irradiation, 15 May–30 Jun", "kWh/m²/day", "LiDAR 2022, horizons 500 m",
     "Solinnstråling (kWh/m²/døgn)"),
    ("sun_hours_day", "Direct sun", "h/day", "LiDAR 2022, horizons 500 m", "Direkte sol (timer/døgn)"),
    ("sun_hours_morning_day", "Direct sun before solar noon", "h/day", "LiDAR 2022, horizons 500 m",
     "Morgensol (timer/døgn)"),
    ("sky_view_factor", "Sky-view factor", "0–1", "LiDAR DOM 2022, plant plane", "Himmelsynsfaktor (0–1)"),
    ("chm_mean_1m", "Height above ground", "m", "LiDAR DOM − DTM 2022, within 1 m", "Høyde over terreng innen 1 m (m) †"),
    ("chm_cover_5m", "Share > 0.5 m above ground", "0–1", "LiDAR DOM − DTM 2022, within 5 m",
     "Andel > 0,5 m over terreng, 5 m †"),
    ("tree_10m", "Trees/tall structures (> 2 m)", "%", "LiDAR DOM − DTM 2022, within 10 m",
     "Trær/høye strukturer innen 10 m (%)"),
    ("veg_1m", "Vegetation cover", "%", "Drone orthophoto 2025/26, within 1 m", "Vegetasjonsdekke innen 1 m (%)"),
    ("veg_5m", "Vegetation cover", "%", "Drone orthophoto 2025/26, within 5 m", "Vegetasjonsdekke innen 5 m (%)"),
    ("ndvi", "NDVI", "", "PlanetScope Aug 2025, 3 m pixel", "NDVI (PlanetScope aug. 2025)"),
    ("n_sedum_5m", "Other smørbukk within 5 m", "count", "Mapped plants, all years", "Andre smørbukk innen 5 m (antall)"),
]

rows = []
for col, label, unit, src, _ in VARS:
    d = plants.dropna(subset=[col])
    v, egg, site = d[col].to_numpy(float), d.egg.to_numpy(), d.site.to_numpy()
    obs = strat_auc(v, egg, site)
    idx = [np.flatnonzero(site == s) for s in np.unique(site)]
    hits = 0
    for _ in range(C.N_PERMUTATIONS):
        e = egg.copy()
        for ix in idx:
            e[ix] = rng.permutation(e[ix])
        hits += abs(strat_auc(v, e, site) - 0.5) >= abs(obs - 0.5) - 1e-12
    signs = []
    for s in SITES:
        a, b = v[(site == s) & (egg == 1)], v[(site == s) & (egg == 0)]
        signs.append("·" if len(a) == 0 else ("+" if np.median(a) > np.median(b) else "−"))
    rows.append({"variable": col, "label": label, "unit": unit, "source": src,
                 "n_egg": int((egg == 1).sum()), "n_noegg": int((egg == 0).sum()),
                 "median_noegg": np.median(v[egg == 0]), "median_egg": np.median(v[egg == 1]),
                 "direction_O_B_G": " ".join(signs), "auc_within_localities": obs,
                 "p_perm": (hits + 1) / (C.N_PERMUTATIONS + 1)})
    log(f"{col}: AUC {obs:.3f}")
tab = pd.DataFrame(rows)
tab["q_bh"] = bh_adjust(tab.p_perm)
tab.to_csv(C.DATA / "egg_vs_ikke_egg.csv", index=False, float_format="%.4f")

# Height above ground follows slope on steep faces (grid interpolation):
# re-test after removing the slope trend within localities (decile medians).
d = plants.dropna(subset=["chm_mean_1m", "slope_deg_1m"]).copy()
rho = d[["chm_mean_1m", "slope_deg_1m"]].corr(method="spearman").iloc[0, 1]
d["chm_res"] = np.nan
for s, g in d.groupby("site"):
    bins = pd.qcut(g.slope_deg_1m, 10, duplicates="drop")
    d.loc[g.index, "chm_res"] = g.chm_mean_1m - g.groupby(bins, observed=True).chm_mean_1m.transform("median")
auc_res = strat_auc(d.chm_res.to_numpy(), d.egg.to_numpy(), d.site.to_numpy())
slope_bins = d.groupby(pd.cut(d.slope_deg_1m, [0, 15, 25, 35, 45, 90]), observed=True).chm_mean_1m.median()
pd.Series({"chm_slope_spearman": rho, "chm_auc_after_slope": auc_res,
           "chm_median_slope_under_15": slope_bins.iloc[0], "chm_median_slope_over_45": slope_bins.iloc[-1],
           "n_permutations": C.N_PERMUTATIONS}).rename("verdi").rename_axis("nokkeltall").to_csv(
    C.DATA / "egg_test_nokkeltall.csv", float_format="%.4f")
log(f"Height above ground vs slope: rho {rho:.2f}; AUC after removing slope trend {auc_res:.2f}")

# ------------------------------------------------------------------ figure
nor = {v[0]: v[4] for v in VARS}
ranked = tab.assign(strength=(tab.auc_within_localities - 0.5).abs()).sort_values("strength", ascending=False)
nrow = int(np.ceil(len(ranked) / 4))
fig, axes = plt.subplots(nrow, 4, figsize=(13, 3.15 * nrow + 0.9), layout="constrained")
jit = np.random.default_rng(1)
for ax, (_, row) in zip(axes.ravel(), ranked.iterrows()):
    for j, s in enumerate(SITES):
        for egg, off, c in ((0, -0.17, COL_NO), (1, 0.17, COL_EGG)):
            v = plants.loc[(plants.site == s) & (plants.egg == egg), row.variable].dropna()
            if len(v):
                ax.scatter(j + off + jit.uniform(-0.07, 0.07, len(v)), v, s=2.5 if egg == 0 else 11, color=c,
                           alpha=0.22 if egg == 0 else 0.9, linewidths=0, zorder=2 + egg)
                ax.plot([j + off - 0.11, j + off + 0.11], [v.median()] * 2, color="#1B3341", linewidth=2, zorder=4)
    ax.set_xticks(range(len(SITES)), SITES, fontsize=8)
    sig = row.q_bh < 0.05
    ax.set_title(f"{nor[row.variable]}\n", loc="left", fontsize=9.5, fontweight="bold", color=TXT_DARK)
    q_txt = "<0,001" if row.q_bh < 0.001 else f"{row.q_bh:.2f}".replace(".", ",")
    ax.text(0.0, 1.02, f"AUC {row.auc_within_localities:.2f}".replace(".", ",") + f" · q {q_txt}" + (" *" if sig else ""),
            transform=ax.transAxes, ha="left", va="bottom", fontsize=8.5, color=COL_EGG if sig else TXT_LIGHT,
            fontweight="bold" if sig else "normal")
    ax.tick_params(axis="y", labelsize=8)
    if sig:
        for sp in ("left", "bottom"):
            ax.spines[sp].set_color(COL_EGG)
            ax.spines[sp].set_linewidth(1.3)
for ax in axes.ravel()[len(ranked):]:
    ax.set_visible(False)
axes.ravel()[0].scatter([], [], s=12, color=COL_NO, label="Uten egg")
axes.ravel()[0].scatter([], [], s=12, color=COL_EGG, label="Med egg 2026")
axes.ravel()[0].legend(frameon=False, fontsize=8, loc="lower right")
fig.suptitle("Smørbukk med og uten egg av klippeblåvinge: alle testede variabler, rangert etter forskjell",
             x=0.01, ha="left", fontsize=13, fontweight="bold", color=TXT_DARK)
fig.text(0.01, -0.03, "Punkter: planter per lokalitet; strek: median. AUC beregnet innen lokalitet (0,5 = ingen "
         "forskjell; >0,5 = høyere verdier ved egg-planter). q: permutasjonstest innen lokalitet, korrigert for "
         f"{len(tab)} tester (Benjamini–Hochberg); * = q < 0,05. † Høyde over terreng følger helningen (usikkerhet i "
         "LiDAR-modellene i bratt terreng); uten helningseffekten forsvinner forskjellen (AUC "
         + f"{auc_res:.2f}".replace(".", ",") + ").", fontsize=8.5, color=TXT_LIGHT, wrap=True)
save_png(fig, C.IMG / "figur_2_egg_variabler_rangert.png")
