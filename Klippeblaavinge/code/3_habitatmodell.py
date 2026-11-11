"""3. Habitat suitability for smørbukk, and egg-laying potential, across
Halden festning.

Input (P:): LiDAR DTM/DOM, PlanetScope NDVI (tested only), study area polygon,
smørbukk survey points, data/smorbukk_planter.csv.
Output: data/habitatmodell_variabler.csv, data/habitatmodell_validering.csv,
data/habitatmodell_nokkeltall.csv, data/habitat_hoy_sikkerhet.gpkg,
img/figur_3_smorbukk_mot_landskapet.png, img/figur_4_habitatkart_halden_festning.png;
rasters (habitatkart_2m.tif, prediktorer_2m.tif) in WORK.

Presence-background model: 2 m cells with mapped smørbukk against random
cells across the study area (what is available, not known absences).
Logistic regression with linear and squared standardised terms; the
background is down-weighted so both groups carry equal weight. Validation:
fit on two localities, test on the third. High confidence: all four model
versions (all data + each leave-one-locality-out model) call the cell
suitable, each with the threshold that keeps 90 % of its training smørbukk
cells. Egg-laying potential: suitability x scaled probability from a
logistic regression of eggs on plant-scale slope (the one consistent egg
signal, see 4_egg_test.py).
"""

import hashlib
import json
import time
import warnings

import geopandas as gpd
import matplotlib
import numpy as np
import pandas as pd
import rasterio
import statsmodels.api as sm
from matplotlib.colors import LinearSegmentedColormap, ListedColormap
from matplotlib.lines import Line2D
from matplotlib.patches import Patch, Rectangle
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.features import geometry_mask, shapes
from rasterio.warp import reproject
from shapely.geometry import shape

import config as C
from felles import (COL_BG, COL_EGG, COL_NO, TXT_DARK, TXT_LIGHT, TXT_MID, auc, block_mean, disk_mean,
                    figure_style, horn_gradients, load_lidar, log, need, ray_distances, save_png,
                    solar_exposure, sun_table, trace_horizons)

# Squared terms push predictions for extreme cells (water, roofs) to 0; the
# logistic link then overflows harmlessly.
warnings.filterwarnings("ignore", category=RuntimeWarning, message="overflow encountered in exp")
plt = figure_style()
Hab, SOL = C.HABITAT, C.SOLAR
RES = Hab["map_res_m"]
rng = np.random.default_rng(Hab["seed"])
t_start = time.time()

PRED = {  # code: (Norwegian label, unit)
    "slope_local": ("Helning, planteskala", "grader"),
    "slope_5m": ("Helning innen 5 m", "grader"),
    "tpi_5m": ("Relativ høyde innen 5 m", "m"),
    "solar": ("Solinnstråling, klarvær", "kWh/m²/døgn"),
    "sun_hours": ("Direkte sol", "timer/døgn"),
    "svf": ("Himmelsynsfaktor", "0–1"),
    "tree_10m": ("Trær/høye strukturer innen 10 m", "andel"),
    "chm": ("Høyde over terreng (usikker i bratt terreng)", "m"),
    "ndvi": ("NDVI (PlanetScope aug. 2025)", ""),
}
ASPECT = {"northness_5m": ("Nordvendthet innen 5 m", "−1 sør … +1 nord"),
          "eastness_5m": ("Østvendthet innen 5 m", "−1 vest … +1 øst")}
LABELS = {**PRED, **ASPECT}

for p, what in ((C.STUDY_AREA, "Study area"), (C.PLANETSCOPE, "PlanetScope"), (C.SMORBUKK_SHP, "Smørbukk survey")):
    need(p, what)
C.QA.mkdir(parents=True, exist_ok=True)

# --------------------------------------------------------------- map grid
with rasterio.open(next(C.LIDAR_DTM.glob("*.tif"))) as r:
    CRS, LRES = r.crs, r.res[0]
area = gpd.read_file(C.STUDY_AREA)
area = area[area.geometry.notna() & ~area.geometry.is_empty].to_crs(CRS)
sb = area.total_bounds
map_box = (np.floor((sb[0] - 20) / RES) * RES, np.floor((sb[1] - 20) / RES) * RES,
           np.ceil((sb[2] + 20) / RES) * RES, np.ceil((sb[3] + 20) / RES) * RES)
R = SOL["horizon_radius_m"]
big_box = (map_box[0] - R, map_box[1] - R, map_box[2] + R, map_box[3] + R)
W, H = int(round((map_box[2] - map_box[0]) / RES)), int(round((map_box[3] - map_box[1]) / RES))
map_tf = rasterio.Affine(RES, 0, map_box[0], 0, -RES, map_box[3])
dtm, dom, big_tf, _, _ = load_lidar(C.LIDAR_DTM, C.LIDAR_DOM, big_box, C.CACHE)
f_map = int(round(RES / LRES))
r_off, c_off = int(round((big_tf.f - map_box[3]) / LRES)), int(round((map_box[0] - big_tf.c) / LRES))


def crop_fine(a):
    return a[r_off:r_off + H * f_map, c_off:c_off + W * f_map]


log(f"Map grid {W} x {H} cells at {RES:g} m")

# ------------------------------------------------------------ predictors
gx, gy = horn_gradients(crop_fine(dtm), LRES)
P = {"slope_local": block_mean(np.degrees(np.arctan(np.hypot(gx, gy))), f_map)}  # mean 25 cm slope per cell
mgx, mgy = block_mean(gx, f_map), block_mean(gy, f_map)                        # plane gradient per cell
del gx, gy
cell_slope = np.degrees(np.arctan(np.hypot(mgx, mgy)))
cell_aspect = (np.degrees(np.arctan2(-mgx, -mgy)) + 360) % 360
P["slope_5m"] = disk_mean(P["slope_local"], 5 / RES)
asp_rad = np.radians(np.where(np.hypot(mgx, mgy) < 0.02, np.nan, cell_aspect))
P["northness_5m"] = disk_mean(np.cos(asp_rad).astype(np.float32), 5 / RES)
P["eastness_5m"] = disk_mean(np.sin(asp_rad).astype(np.float32), 5 / RES)
z_cell = block_mean(crop_fine(dtm), f_map)
P["tpi_5m"] = z_cell - disk_mean(z_cell, 5 / RES)
chm_fine = crop_fine(dom) - crop_fine(dtm)
P["chm"] = np.clip(block_mean(chm_fine, f_map), 0, None)
P["tree_10m"] = disk_mean(block_mean((chm_fine > C.TREE_HEIGHT_M).astype(np.float32), f_map), 10 / RES)
del chm_fine
with rasterio.open(C.PLANETSCOPE) as r:
    band = [i + 1 for i, d in enumerate(r.descriptions) if d and d.upper() == "NDVI"][0]
    P["ndvi"] = np.full((H, W), np.nan, dtype=np.float32)
    reproject(rasterio.band(r, band), P["ndvi"], dst_transform=map_tf, dst_crs=CRS,
              resampling=Resampling.bilinear, dst_nodata=np.nan)

# Sun per cell: horizons on a 1 m DOM out to 500 m, observer 10 cm above the cell.
f1 = int(round(1.0 / LRES))
dom1, res1 = block_mean(dom, f1), LRES * f1
valid = np.isfinite(cell_slope) & np.isfinite(z_cell) & (z_cell >= Hab["min_ground_m"])
rr, cc = np.nonzero(valid)
skey = hashlib.sha1((json.dumps(SOL, sort_keys=True) + str(map_box) + f"{Hab['n_azimuths']}_{len(rr)}")
                    .encode()).hexdigest()[:12]
sfile = C.CACHE / f"sol_kart_{skey}.npz"
if sfile.exists():
    c = np.load(sfile)
    solar_v, hours_v, svf_v = c["solar"], c["hours"], c["svf"]
else:
    cx, cy = map_box[0] + (cc + 0.5) * RES, map_box[3] - (rr + 0.5) * RES
    lon, lat = Transformer.from_crs(CRS, 4326, always_xy=True).transform(np.mean(cx), np.mean(cy))
    d = ray_distances(RES, R, res1)
    log(f"Sun map: {len(rr):,} cells x {Hab['n_azimuths']} directions x {len(d)} steps (several minutes)")
    hor, _ = trace_horizons(dom1, res1, (big_tf.f - cy) / res1, (cx - big_tf.c) / res1,
                            z_cell[rr, cc] + SOL["observer_height_m"], Hab["n_azimuths"], d, chunk=4096)
    s = solar_exposure(cell_slope[rr, cc], np.nan_to_num(cell_aspect[rr, cc], nan=180.0), hor,
                       sun_table(lat, lon, SOL), SOL["albedo"], chunk=1000)
    solar_v, hours_v, svf_v = (s[k].to_numpy() for k in ("solar_kwh_m2_day", "sun_hours_day", "sky_view_factor"))
    np.savez_compressed(sfile, solar=solar_v, hours=hours_v, svf=svf_v)
for k, v in (("solar", solar_v), ("sun_hours", hours_v), ("svf", svf_v)):
    P[k] = np.full((H, W), np.nan, dtype=np.float32)
    P[k][rr, cc] = v
in_area = ~geometry_mask(area.geometry, out_shape=(H, W), transform=map_tf)
valid &= in_area
for k in P:
    P[k][~valid] = np.nan
area_km2 = valid.sum() * RES ** 2 / 1e6
log(f"Predictors ready; study area {area_km2:.2f} km² with LiDAR")
with rasterio.open(C.WORK / "prediktorer_2m.tif", "w", driver="GTiff", height=H, width=W, count=len(LABELS),
                   dtype="float32", crs=CRS, transform=map_tf, nodata=np.nan, compress="lzw") as dst:
    for i, k in enumerate(LABELS, start=1):
        dst.write(P[k], i)
        dst.set_band_description(i, k)

# --------------------------------------------------------------- samples
plants = pd.read_csv(C.DATA / "smorbukk_planter.csv")
pts = gpd.read_file(C.SMORBUKK_SHP).to_crs(CRS)        # every smørbukk record, incl. 2025 egg records


def cell_of(x, y):
    c = np.floor((np.asarray(x) - map_box[0]) / RES).astype(int)
    r = np.floor((map_box[3] - np.asarray(y)) / RES).astype(int)
    return r, c, (r >= 0) & (r < H) & (c >= 0) & (c < W)


pr, pc, pok = cell_of(pts.geometry.x, pts.geometry.y)
pres_cells = np.unique(np.ravel_multi_index((pr[pok], pc[pok]), (H, W)))
pres_cells = pres_cells[valid.ravel()[pres_cells]]
tr = Transformer.from_crs(C.WORKING_EPSG, CRS, always_xy=True)
lx, ly = tr.transform(plants.x_m.to_numpy(), plants.y_m.to_numpy())
lr, lc, lok = cell_of(lx, ly)
cell_site = pd.Series(plants.site.to_numpy()[lok], index=np.ravel_multi_index((lr[lok], lc[lok]), (H, W)))
cell_site = cell_site[~cell_site.index.duplicated()]
valid_idx = np.flatnonzero(valid.ravel())
bg_cells = rng.choice(valid_idx, size=min(Hab["n_background"], len(valid_idx)), replace=False)

codes = [k for k in PRED if k not in Hab["exclude_from_model"]]          # model predictors
extra = [k for k in LABELS if k not in codes]                            # described and tested only
Xall = np.column_stack([P[k].ravel() for k in codes])
pres = pd.DataFrame(Xall[pres_cells], columns=codes).assign(cell=pres_cells).dropna()
bg = pd.DataFrame(Xall[bg_cells], columns=codes).assign(cell=bg_cells).dropna()
pres["site"] = cell_site.reindex(pres.cell).fillna("Annen").to_numpy()
for k in extra:
    pres[k] = P[k].ravel()[pres.cell.to_numpy()]
    bg[k] = P[k].ravel()[bg.cell.to_numpy()]
mu, sd = bg[codes + extra].mean(), bg[codes + extra].std()
log(f"Samples: {len(pres)} smørbukk cells, {len(bg)} background cells")


def design(df, cols=None):
    cols = cols or codes
    z = (df[cols] - mu[cols]) / sd[cols]
    return sm.add_constant(pd.concat([z, (z ** 2).add_suffix("_2")], axis=1), has_constant="add")


def fit(p, b, cols=None):
    y = np.r_[np.ones(len(p)), np.zeros(len(b))]
    w = np.r_[np.ones(len(p)), np.full(len(b), len(p) / len(b))]
    return sm.GLM(y, design(pd.concat([p, b]), cols), family=sm.families.Binomial(), freq_weights=w).fit()


def evaluate(p, b, cols):
    """AUC with all data and with each locality held out."""
    m = fit(p, b, cols)
    out = {"auc_alle": auc(m.predict(design(p, cols)), m.predict(design(b, cols)))}
    for s in sites:
        ms = fit(p[p.site != s], b, cols)
        out[f"auc_uten_{s}"] = auc(ms.predict(design(p[p.site == s], cols)), ms.predict(design(b, cols)))
    return out, m


sites = [s for s in C.SITE_LABELS.values() if (pres.site == s).sum() >= 20]
validation = {}
validation["Endelig modell"], model = evaluate(pres, bg, codes)
lolo_models = {s: fit(pres[pres.site != s], bg) for s in sites}
cols_asp = codes + list(ASPECT)
pa, ba = pres.dropna(subset=cols_asp), bg.dropna(subset=cols_asp)
validation["+ aspekt"], _ = evaluate(pa, ba, cols_asp)
cols_n = codes + ["ndvi"]
pn, bn = pres.dropna(subset=cols_n), bg.dropna(subset=cols_n)
validation["+ NDVI (PlanetScope-området)"], _ = evaluate(pn, bn, cols_n)
validation["Uten NDVI (samme område)"], _ = evaluate(pn, bn, codes)
for k, v in validation.items():
    log(f"{k}: " + ", ".join(f"{a} {b:.3f}" for a, b in v.items()))

uni = pd.DataFrame({"variabel": codes + extra, "i_modell": [k in codes for k in codes + extra],
                    "auc_alene": [auc(pres[k].dropna(), bg[k].dropna()) for k in codes + extra],
                    "median_smorbukk": [pres[k].median() for k in codes + extra],
                    "q05_smorbukk": [pres[k].quantile(0.05) for k in codes + extra],
                    "q95_smorbukk": [pres[k].quantile(0.95) for k in codes + extra],
                    "median_landskap": [bg[k].median() for k in codes + extra]})
uni["styrke"] = (uni.auc_alene - 0.5).abs() * 2
uni = uni.sort_values("styrke", ascending=False)
uni.insert(1, "navn", [LABELS[k][0] for k in uni.variabel])
uni.insert(2, "enhet", [LABELS[k][1] for k in uni.variabel])
uni.to_csv(C.DATA / "habitatmodell_variabler.csv", index=False, float_format="%.4f")

# ---------------------------------------------------- suitability and egg layer
ok_rows = np.isfinite(Xall).all(axis=1)
Xm = pd.DataFrame(Xall[ok_rows], columns=codes)
suit = np.full(H * W, np.nan, dtype=np.float32)
suit[ok_rows] = model.predict(design(Xm))
suit = suit.reshape(H, W)
agree = np.zeros(H * W, dtype=np.float32)
for s, m in [("alle", model)] + list(lolo_models.items()):
    train = pres if s == "alle" else pres[pres.site != s]
    pm = np.full(H * W, np.nan)
    pm[ok_rows] = m.predict(design(Xm))
    agree += (pm >= np.nanquantile(m.predict(design(train)), 0.10)).astype(np.float32)
n_models = 1 + len(lolo_models)
high = (agree.reshape(H, W) == n_models).astype(np.float32)
high[~valid] = np.nan

eg = plants.copy()
eg["slope_local"] = P["slope_local"][lr.clip(0, H - 1), lc.clip(0, W - 1)]
eg = eg[lok & eg.slope_local.notna()]
Xe = sm.add_constant((eg[["slope_local"]] - mu["slope_local"]) / sd["slope_local"])
egg_model = sm.GLM(eg.egg.to_numpy(), Xe, family=sm.families.Binomial()).fit()
egg_auc = auc(egg_model.predict(Xe)[eg.egg == 1], egg_model.predict(Xe)[eg.egg == 0])
validation["Eggmodell (helning på planteskala)"] = {"auc_alle": egg_auc}
egg_rel = np.full(H * W, np.nan, dtype=np.float32)
egg_rel[ok_rows] = egg_model.predict(sm.add_constant((Xm[["slope_local"]] - mu["slope_local"]) / sd["slope_local"],
                                                     has_constant="add"))
egg_rel = egg_rel.reshape(H, W)
egg_pot = np.clip(suit * egg_rel / np.nanpercentile(egg_rel, 99), 0, 1)

val = pd.DataFrame(validation).T.rename_axis("modell")
val.to_csv(C.DATA / "habitatmodell_validering.csv", float_format="%.3f")
high_ha = np.nansum(high == 1) * RES ** 2 / 1e4
key_numbers = {
    "studieomraade_km2": area_km2, "smorbukk_celler": len(pres), "bakgrunn_celler": len(bg),
    "hoy_sikkerhet_ha": high_ha, "hoy_sikkerhet_andel": float(np.nanmean(high[valid] == 1)),
    "smorbukk_i_hoy_sikkerhet_andel": float(np.mean(high.ravel()[pres.cell.to_numpy()] == 1)),
    "eggmodell_koef_helning_per_sd": float(egg_model.params["slope_local"]),
    "n_modeller": n_models,
}
pd.Series(key_numbers).rename("verdi").rename_axis("nokkeltall").to_csv(C.DATA / "habitatmodell_nokkeltall.csv",
                                                                         float_format="%.4f")
log(f"High confidence: {high_ha:.1f} ha ({key_numbers['hoy_sikkerhet_andel'] * 100:.1f} %), "
    f"{key_numbers['smorbukk_i_hoy_sikkerhet_andel'] * 100:.0f} % of smørbukk cells inside")

# Rasters for QGIS stay in WORK; the high-confidence habitat goes to data/ as polygons.
with rasterio.open(C.WORK / "habitatkart_2m.tif", "w", driver="GTiff", height=H, width=W, count=3, dtype="float32",
                   crs=CRS, transform=map_tf, nodata=np.nan, compress="lzw") as dst:
    for i, (a, nm) in enumerate(((suit, "smorbukk_egnethet"), (high, "egnet_hoy_sikkerhet"),
                                 (np.where(high == 1, egg_pot, np.nan), "eggleggingspotensial")), start=1):
        dst.write(a.astype(np.float32), i)
        dst.set_band_description(i, nm)
pot_hi = np.where(high == 1, egg_pot, np.nan)
pot_class = np.where(high == 1, np.digitize(np.nan_to_num(pot_hi / np.nanmax(pot_hi)), [1 / 3, 2 / 3]) + 1, 0)
polys = [{"geometry": shape(g), "eggpotensial_klasse": int(v)}
         for g, v in shapes(pot_class.astype(np.int16), mask=pot_class > 0, transform=map_tf)]
hab = gpd.GeoDataFrame(polys, crs=CRS).dissolve(by="eggpotensial_klasse").reset_index()
hab["eggpotensial"] = hab.eggpotensial_klasse.map({1: "lav", 2: "middels", 3: "høy"})
hab["areal_m2"] = hab.area.round(0)
hab.to_crs(C.WORKING_EPSG).to_file(C.DATA / "habitat_hoy_sikkerhet.gpkg", layer="habitat_hoy_sikkerhet")

# ---------------------------------------------- figure 3: smørbukk vs landscape
order = uni.variabel.tolist()
nr = int(np.ceil(len(order) / 4))
fig, axes = plt.subplots(nr, 4, figsize=(13, 2.75 * nr + 0.9))
for ax in axes.ravel()[len(order):]:
    ax.set_visible(False)
egg_vals = eg.assign(cell=np.ravel_multi_index((lr[eg.index], lc[eg.index]), (H, W)))
for ax, k in zip(axes.ravel(), order):
    b_k, p_k = bg[k].dropna(), pres[k].dropna()
    lo, hi = np.nanpercentile(np.r_[b_k, p_k], [0.5, 99.5])
    bins = np.linspace(lo, hi, 40)
    ax.hist(b_k.clip(lo, hi), bins=bins, density=True, color=COL_BG, alpha=0.7, label="Landskapet (tilfeldige celler)")
    ax.hist(p_k.clip(lo, hi), bins=bins, density=True, histtype="step", linewidth=1.8, color=COL_NO, label="Smørbukk")
    ev = pd.Series(P[k].ravel()[egg_vals.loc[egg_vals.egg == 1, "cell"].to_numpy()]).dropna().clip(lo, hi)
    ax.plot(ev, np.zeros(len(ev)), "|", color=COL_EGG, markersize=10, markeredgewidth=1.4, label="Planter med egg 2026")
    lab, unit = LABELS[k]
    ax.set_title(lab + ("" if k in codes else " *"), loc="left", fontsize=10, fontweight="bold", color=TXT_DARK)
    ax.text(0.98, 0.95, f"AUC {uni.set_index('variabel').loc[k, 'auc_alene']:.2f}".replace(".", ","),
            transform=ax.transAxes, ha="right", va="top", fontsize=8.5, color=TXT_MID)
    ax.set_xlabel(unit, fontsize=8.5, color=TXT_MID)
    ax.set_yticks([])
    ax.spines["left"].set_visible(False)
handles, labels_ = axes.ravel()[0].get_legend_handles_labels()
fig.legend(handles, labels_, loc="lower center", ncol=3, frameon=False, bbox_to_anchor=(0.5, -0.03))
fig.suptitle("Hvor vokser smørbukk, sammenliknet med landskapet rundt?", x=0.01, y=0.995, ha="left",
             fontsize=14, fontweight="bold", color=TXT_DARK)
fig.text(0.01, 0.945, "2 m-celler med kartlagt smørbukk mot tilfeldige celler på Halden festning · LiDAR 2022, "
         "PlanetScope aug. 2025 · ordnet etter hvor godt variabelen alene skiller (AUC) · * ikke i modellen",
         fontsize=9.5, color=TXT_MID)
fig.tight_layout(rect=(0, 0.02, 1, 0.93))
save_png(fig, C.IMG / "figur_3_smorbukk_mot_landskapet.png")

# ----------------------------------------------------- figure 4: habitat map
gxm, gym = np.gradient(z_cell, RES)
slope_r = np.arctan(np.hypot(gxm, gym))
hs = np.clip(np.cos(np.radians(45)) * np.cos(slope_r)
             + np.sin(np.radians(45)) * np.sin(slope_r) * np.cos(np.radians(315) - np.arctan2(-gxm, gym)), 0, 1)
ext = (map_box[0], map_box[2], map_box[1], map_box[3])
ab = area.total_bounds
view = (ab[0] - 15, ab[2] + 15, ab[1] - 15, ab[3] + 15)
hs_area = np.where(in_area, hs, np.nan)
COL_HAB = "#2E8B57"
pot_cmap = LinearSegmentedColormap.from_list("pot", ["#EEE6F6", "#B79AD6", "#7A4FB0", "#3B1A6E"])
egg_high = np.where(high == 1, egg_pot / np.nanmax(egg_pot[high == 1]), np.nan)
px_all, py_all = pts.geometry.x.to_numpy(), pts.geometry.y.to_numpy()
e = plants[plants.egg == 1]
ex, ey = tr.transform(e.x_m.to_numpy(), e.y_m.to_numpy())
egg_kw = dict(s=34, facecolor="#FF8A1F", edgecolor="black", linewidth=0.8, zorder=6)


def base_map(ax, xlim, ylim, sb):
    ax.imshow(hs, extent=ext, cmap="Greys_r", vmin=-0.6, vmax=1.6, interpolation="bilinear", alpha=0.35)
    ax.imshow(hs_area, extent=ext, cmap="Greys_r", vmin=-0.2, vmax=1.1, interpolation="bilinear")
    area.boundary.plot(ax=ax, color="#3A4A52", linewidth=1.0, linestyle="--")
    ax.set_xlim(*xlim)
    ax.set_ylim(*ylim)
    ax.set_aspect("equal")
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_xlabel("")
    ax.set_ylabel("")
    x0, y0 = xlim[0] + 0.05 * (xlim[1] - xlim[0]), ylim[0] + 0.05 * (ylim[1] - ylim[0])
    ax.plot([x0, x0 + sb], [y0, y0], color="black", linewidth=3)
    ax.text(x0 + sb / 2, y0 + 0.02 * (ylim[1] - ylim[0]), f"{sb} m", ha="center", fontsize=8)


zooms = {}
for s in C.SITE_LABELS.values():
    sel = (plants.site == s).to_numpy()
    zx, zy = np.asarray(lx)[sel], np.asarray(ly)[sel]
    cx, cy = np.median(zx), np.median(zy)
    half = max(np.percentile(np.abs(zx - cx), 98), np.percentile(np.abs(zy - cy), 98)) + 12
    zooms[s] = ((cx - half, cx + half), (cy - half, cy + half))
asp = (view[3] - view[2]) / (view[1] - view[0])
fig = plt.figure(figsize=(13, 6.5 * asp + 4.9), layout="constrained")
gs_m = fig.add_gridspec(2, 3, height_ratios=[6.5 * asp, 4.0])
gtop = gs_m[0, :].subgridspec(1, 2)
axA, axB = fig.add_subplot(gtop[0]), fig.add_subplot(gtop[1])
for ax in (axA, axB):
    base_map(ax, view[:2], view[2:], 100)
axA.imshow(np.ma.masked_where(high != 1, high), extent=ext, cmap=ListedColormap([COL_HAB]), alpha=0.85,
           interpolation="nearest")
axA.scatter(px_all, py_all, s=3, color="black", linewidths=0, zorder=5)
axA.scatter(ex, ey, **egg_kw)
for s, (xl, yl) in zooms.items():
    axA.add_patch(Rectangle((xl[0], yl[0]), xl[1] - xl[0], yl[1] - yl[0], fill=False, edgecolor="#123B52",
                            linewidth=1.2))
    axA.text(xl[0], yl[1] + 6, s, fontsize=8.5, fontweight="bold", color="#123B52")
axA.set_title("a  Egnet for smørbukk (høy sikkerhet)", loc="left", fontsize=12, fontweight="bold", color=TXT_DARK)
axA.legend(handles=[Patch(color=COL_HAB, alpha=0.85, label=f"Egnet – alle {n_models} modeller enige"),
                    Line2D([], [], marker="o", linestyle="", markersize=3, color="black", label="Kartlagt smørbukk"),
                    Line2D([], [], marker="o", linestyle="", markersize=7, markerfacecolor="#FF8A1F",
                           markeredgecolor="black", label="Planter med egg 2026")],
           loc="upper left", fontsize=8, frameon=True, framealpha=0.92)
im = axB.imshow(np.ma.masked_invalid(egg_high), extent=ext, cmap=pot_cmap, vmin=0, vmax=1, alpha=0.95,
                interpolation="nearest")
axB.scatter(ex, ey, **egg_kw)
axB.set_title("b  Potensial for egglegging innenfor egnet areal", loc="left", fontsize=12, fontweight="bold",
              color=TXT_DARK)
cb = fig.colorbar(im, cax=axB.inset_axes([0.58, 0.06, 0.38, 0.03]), orientation="horizontal")
cb.set_label("Relativt potensial (0–1)", fontsize=8.5)
cb.ax.tick_params(labelsize=8)
for j, (s, (xl, yl)) in enumerate(zooms.items()):
    ax = fig.add_subplot(gs_m[1, j])
    base_map(ax, xl, yl, 10)
    ax.imshow(np.ma.masked_invalid(egg_high), extent=ext, cmap=pot_cmap, vmin=0, vmax=1, alpha=0.9,
              interpolation="nearest")
    ax.contour(np.where(high == 1, 1.0, 0.0), levels=[0.5], extent=(ext[0], ext[1], ext[3], ext[2]),
               colors=[COL_HAB], linewidths=0.9)
    ax.scatter(px_all, py_all, s=6, color="black", linewidths=0, zorder=5)
    ax.scatter(ex, ey, **{**egg_kw, "s": 46})
    ax.set_title(f"{'cde'[j]}  {s}", loc="left", fontsize=11, fontweight="bold", color=TXT_DARK)
fig.suptitle("Mulige leveområder for smørbukk og klippeblåvinge på Halden festning", x=0.01, ha="left",
             fontsize=14, fontweight="bold", color=TXT_DARK)
lolo_txt = ", ".join(f"{validation['Endelig modell'][f'auc_uten_{s}']:.2f}" for s in sites)
fig.text(0.01, -0.03, f"Modell: kartlagt smørbukk mot tilfeldige celler på Halden festning (stiplet; AUC "
         f"{validation['Endelig modell']['auc_alle']:.2f}, testet på utelatt lokalitet {lolo_txt}). Høy sikkerhet: "
         "modellen med alle data og de tre modellene uten hver lokalitet er enige. Egglegging (lilla): egnethet × "
         "eggmodell (helning på planteskala). c–e: utsnitt; grønn linje = grense for egnet areal. Relativ egnethet, "
         "ikke sannsynlighet for forekomst; LiDAR 2022 er før senere terrengarbeid.", fontsize=8.5, color=TXT_LIGHT,
         wrap=True)
save_png(fig, C.IMG / "figur_4_habitatkart_halden_festning.png")
log(f"Done in {time.time() - t_start:.0f} s")
