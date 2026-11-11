"""1. Plant table: one row per smørbukk with terrain, sun and neighbourhood
variables from the 2022 LiDAR.

Input (P:): smørbukk survey points, LiDAR DTM/DOM tiles, drone DSMs/orthophotos
(locality labels and change check).
Output: data/smorbukk_planter.csv (EPSG:25832, full GNSS precision); QA tables in WORK/qa.

Design: smørbukk mapped at Overberget and Borgerskansen in 2025 and at
Gyldenløve in 2026 are pooled; all plants were searched for eggs in 2026, so
the egg outcome comes from 2026 only. Egg records from 2025 count as host
plants in the neighbour counts but are not compared.
"""

import hashlib
import json

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from pyproj import Transformer
from scipy.spatial import cKDTree

import config as C
from felles import (horn_slope_aspect, load_lidar, log, need, plant_chm, plant_terrain, radius_code,
                    ray_distances, solar_exposure, sun_table, trace_horizons)

C.QA.mkdir(parents=True, exist_ok=True)
C.DATA.mkdir(parents=True, exist_ok=True)
need(C.SMORBUKK_SHP, "Smørbukk survey")
for k, s in C.SITES.items():
    need(s["dsm"], f"Drone DSM ({k})")
    need(s["ortho"], f"Orthophoto ({k})")

# ------------------------------------------------------------- read points
plants = gpd.read_file(C.SMORBUKK_SHP)
if plants.crs is None or not (plants.geom_type == "Point").all():
    raise ValueError("The survey layer must be points with a CRS.")
plants["plant_row_id"] = np.arange(1, len(plants) + 1)
plants["Year"] = plants["Year"].astype(str).str.strip().str.replace(r"\.0$", "", regex=True)
plants["Egg"] = pd.to_numeric(plants["Egg"], errors="coerce")
if plants["Egg"].isna().any() or not plants["Egg"].isin([0, 1]).all():
    raise ValueError("Egg must be 0 or 1 for every record.")
plants["Egg"] = plants["Egg"].astype(int)
plants = plants.set_geometry(gpd.points_from_xy(plants.geometry.x, plants.geometry.y, crs=plants.crs))
plants = plants.to_crs(C.WORKING_EPSG)
plants["x_m"], plants["y_m"] = plants.geometry.x, plants.geometry.y
log(f"Read {len(plants)} records ({(plants.Egg == 1).sum()} with eggs)")

# ---------------------------------------------- duplicates (agreed rules)
# Same year and identical coordinates (1 cm): Egg=1 + Egg=0 -> drop the Egg=0
# record; same egg status -> keep both; different years -> keep both.
q = C.DUPLICATE_ROUND_M
xy_key = (np.round(plants.x_m / q).astype(np.int64).astype(str) + "|"
          + np.round(plants.y_m / q).astype(np.int64).astype(str))
grp = plants.groupby(plants.Year + "|" + xy_key)["Egg"]
size = grp.transform("size")
remove = (size > 1) & (grp.transform("max") == 1) & (grp.transform("min") == 0) & (plants.Egg == 0)
plants.loc[size > 1].drop(columns="geometry").to_csv(C.QA / "duplikate_koordinater.csv", index=False)
plants, xy_key = plants.loc[~remove].copy(), xy_key[~remove]
log(f"Duplicates: {int((size > 1).sum())} rows share coordinates within a year; removed {int(remove.sum())}")

# -------------------------------------------------- host-plant neighbours
# Other smørbukk within r over all survey campaigns (each locality was mapped
# once). The 'unik' version counts identical 1 cm positions once.
xy = plants[["x_m", "y_m"]].to_numpy()
tree = cKDTree(xy)
keys = xy_key.to_numpy()
for r in C.RADII_M:
    nb = tree.query_ball_point(xy, r)
    plants[f"n_sedum_{radius_code(r)}m"] = [len(n) - 1 for n in nb]
    plants[f"n_sedum_unik_{radius_code(r)}m"] = [len(set(keys[n]) - {keys[i]}) for i, n in enumerate(nb)]

excluded = (plants.Egg == 1) & ~plants.Year.isin(C.EGG_YEARS)
plants.loc[excluded].drop(columns="geometry").to_csv(C.QA / "eggplanter_utenfor_eggaar.csv", index=False)
plants = plants.loc[~excluded].copy()
log(f"{int(excluded.sum())} egg records outside {C.EGG_YEARS} kept as neighbours only; "
    f"{len(plants)} plants analysed, {(plants.Egg == 1).sum()} with eggs")

# ------------------------------------------- localities and drone coverage
# Locality = drone tile containing the plant, else the nearest tile within
# LOCALITY_MAX_DIST_M. Rasters stay in their own CRS; points are transformed.
plants["site"] = None
plants["has_drone_dsm"] = False
plants["has_rgb"] = False
site_xy, dist = {}, []
for key, s in C.SITES.items():
    with rasterio.open(s["dsm"]) as r:
        x, y = Transformer.from_crs(plants.crs, r.crs, always_xy=True).transform(plants.x_m.to_numpy(),
                                                                                plants.y_m.to_numpy())
        b = r.bounds
        z0 = np.zeros_like(x)
        dist.append(np.hypot(np.maximum.reduce([b.left - x, z0, x - b.right]),
                             np.maximum.reduce([b.bottom - y, z0, y - b.top])))
        inside = (x >= b.left) & (x < b.right) & (y > b.bottom) & (y <= b.top) & plants.site.isna().to_numpy()
        vals = np.full(len(plants), np.nan)
        if inside.any():
            vals[inside] = [v[0] for v in r.sample(zip(x[inside], y[inside]))]
        valid = inside & np.isfinite(vals) & (vals != r.nodata)
    with rasterio.open(s["ortho"]) as r:
        rgb_ok = np.zeros(len(plants), dtype=bool)
        if inside.any():
            px = np.array(list(r.sample(zip(x[inside], y[inside]))))
            rgb_ok[inside] = px[:, 3] > 0 if r.count >= 4 else ~(px[:, :3] == (255 if r.nodata is None else r.nodata)).all(axis=1)
    plants.loc[inside, "site"] = key
    plants.loc[inside, "has_drone_dsm"] = valid[inside]
    plants.loc[inside, "has_rgb"] = rgb_ok[inside]
    site_xy[key] = (x, y)
dist = np.column_stack(dist)
outside = plants.site.isna().to_numpy()
near = dist.min(axis=1) <= C.LOCALITY_MAX_DIST_M
plants.loc[outside & near, "site"] = np.array(list(C.SITES))[dist.argmin(axis=1)][outside & near]
plants.loc[outside & ~near, "site"] = "Annen"
log("Localities: " + ", ".join(f"{k} {v}" for k, v in plants.site.value_counts().items()))

# ------------------------------------------------------ LiDAR terrain
with rasterio.open(next(C.LIDAR_DTM.glob("*.tif"))) as r:
    lcrs = r.crs
lx, ly = Transformer.from_crs(plants.crs, lcrs, always_xy=True).transform(plants.x_m.to_numpy(), plants.y_m.to_numpy())
lx, ly = np.asarray(lx), np.asarray(ly)
R = C.SOLAR["horizon_radius_m"] + 5
box = (np.floor(lx.min() - R), np.floor(ly.min() - R), np.ceil(lx.max() + R), np.ceil(ly.max() + R))
dtm, dom, tf, crs, res = load_lidar(C.LIDAR_DTM, C.LIDAR_DOM, box, C.CACHE)
slope, aspect = horn_slope_aspect(dtm, res)
terrain = plant_terrain(dtm, slope, aspect, tf, res, lx, ly, C.RADII_M, C.SOLAR["plane_radius_m"],
                        C.MIN_VALID_FRACTION)
terrain = terrain.join(plant_chm(dom - dtm, tf, res, lx, ly, C.RADII_M, C.CHM_THRESHOLD_M, C.MIN_VALID_FRACTION))
terrain.index = plants.index
plants = plants.join(terrain)
log(f"Terrain: LiDAR grid {dtm.shape[1]} x {dtm.shape[0]} at {res} m")

# Change check: drone DSM (2025/26, median within 25 cm) minus LiDAR DOM (2022)
# at each plant, after removing each locality's median difference (the drone
# models use different height references). Large values show site works,
# clearing, or steep faces where either model is unreliable.
plants["endring_drone_lidar_m"] = np.nan
for key, s in C.SITES.items():
    sel = ((plants.site == key) & plants.has_drone_dsm).to_numpy()
    if not sel.any():
        continue
    x, y = site_xy[key]
    with rasterio.open(s["dsm"]) as r:
        half = max(1, int(round(0.125 / r.res[0])))
        dz = np.pad(r.read(1).astype(np.float32), half, constant_values=np.nan)
        if r.nodata is not None:
            dz[dz == r.nodata] = np.nan
        zd = []
        for xi, yi in zip(x[sel], y[sel]):
            ri, ci = r.index(xi, yi)
            w = dz[ri:ri + 2 * half + 1, ci:ci + 2 * half + 1]
            zd.append(np.nanmedian(w) if np.isfinite(w).any() else np.nan)
    rr = np.floor((tf.f - ly[sel]) / res).astype(int)
    cc = np.floor((lx[sel] - tf.c) / res).astype(int)
    diff = np.array(zd) - dom[rr, cc]
    plants.loc[plants.index[sel], "endring_drone_lidar_m"] = diff - np.nanmedian(diff)
code1 = radius_code(min(C.RADII_M))
plants["steep_face"] = (plants[f"slope_deg_{code1}m"] > C.STEEP_FACE_DEG).astype(float).where(
    plants[f"slope_deg_{code1}m"].notna())

# ------------------------------------------------------ sun and shading
sel = plants.plane_z.notna().to_numpy()
lon, lat = Transformer.from_crs(crs, 4326, always_xy=True).transform(lx.mean(), ly.mean())
sun = sun_table(lat, lon, C.SOLAR)
col = (lx[sel] - tf.c) / res
row = (tf.f - ly[sel]) / res
z_obs = plants.loc[sel, "plane_z"].to_numpy() + C.SOLAR["observer_height_m"]
d = ray_distances(C.SOLAR["plane_radius_m"], C.SOLAR["horizon_radius_m"], res)
hkey = hashlib.sha1(np.round(np.column_stack([col, row, z_obs]), 4).tobytes() + d.tobytes()
              + json.dumps(C.SOLAR, sort_keys=True).encode()).hexdigest()[:12]
hfile = C.CACHE / f"horisont_planter_{hkey}.npz"
if hfile.exists():
    c = np.load(hfile)
    hor, reach = c["hor"], c["reach"]
else:
    log(f"Tracing horizons for {sel.sum()} plants ({C.SOLAR['n_azimuths']} directions, {len(d)} steps)")
    hor, reach = trace_horizons(dom, res, row, col, z_obs, C.SOLAR["n_azimuths"], d)
    np.savez_compressed(hfile, hor=hor, reach=reach)
sol = solar_exposure(plants.loc[sel, "plane_slope_deg"].to_numpy(), plants.loc[sel, "plane_aspect_deg"].to_numpy(),
                     hor, sun, C.SOLAR["albedo"])
sol["horizon_reach_min_m"] = reach.min(axis=1)
sol["horizon_max_deg"] = np.degrees(np.nanmax(hor, axis=1))
sol.index = plants.index[sel]
plants = plants.join(sol)
az = np.arange(C.SOLAR["n_azimuths"]) * 360 / C.SOLAR["n_azimuths"]
pd.DataFrame({"plant_row_id": np.repeat(plants.loc[sel, "plant_row_id"].to_numpy(), len(az)),
              "azimut_grader": np.tile(az, sel.sum()), "horisont_grader": np.degrees(hor).ravel(),
              "rekkevidde_m": reach.ravel()}).to_csv(C.QA / "horisontprofiler.csv", index=False)
log(f"Sun: lat {lat:.4f}, lon {lon:.4f}; flat clear-sky reference {sun['flat_kwh'] / sun['n_days']:.2f} kWh/m2/day")

# ---------------------------------------------------------------- output
plants["site"] = plants.site.map(lambda s: C.SITE_LABELS.get(s, s))
cols = (["plant_row_id", "Year", "Egg", "site", "x_m", "y_m"]
        + [c for c in plants.columns if c.startswith("n_sedum_")]
        + [f"{m}_{radius_code(r)}m" for m in ("slope_deg", "northness", "eastness", "dem_fraction") for r in C.RADII_M]
        + ["tpi_5m", "plane_slope_deg", "plane_aspect_deg", "steep_face"]
        + [f"chm_{m}_{radius_code(r)}m" for m in ("mean", "max", "cover") for r in C.RADII_M]
        + ["solar_kwh_m2_day", "beam_kwh_m2_day", "solar_rel_flat_pct", "sun_hours_day", "sun_hours_morning_day",
           "sun_hours_afternoon_day", "sky_view_factor", "horizon_reach_min_m", "horizon_max_deg",
           "endring_drone_lidar_m", "has_drone_dsm", "has_rgb"])
out = plants[cols].rename(columns={"Year": "year", "Egg": "egg"})
out.to_csv(C.DATA / "smorbukk_planter.csv", index=False, float_format="%.4f")
log(f"Wrote data/smorbukk_planter.csv ({len(out)} plants, {out.egg.sum()} with eggs)")
