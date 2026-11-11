"""5. 3D figure of Gyldenløve: drone point cloud with smørbukk and egg plants.

Input (P:): Gyldenløve point cloud (Metashape, May 2026, LAZ with RGB), the
raw GNSS export of the 2026 smørbukk survey (heights), smørbukk survey points.
Output: img/figur_1_3d_gyldenlove.jpg.

The merged survey layer has no heights, so plant heights come from the raw
GNSS export (ellipsoidal heights), shifted by the median difference to the
point-cloud surface at the plants (constant to within a few cm). Plants on
steep faces are therefore placed correctly. Egg records without their own
GNSS height take the nearest GNSS point within 25 cm, else the cloud surface.
"""

import time

import geopandas as gpd
import laspy
import numpy as np
import pandas as pd
import pyvista as pv
from matplotlib.lines import Line2D
from scipy.spatial import cKDTree

import config as C
from felles import COL_EGG, TXT_DARK, TXT_LIGHT, figure_style, log, need

VIEW = {
    "keep_fraction": 0.35,     # share of the 56 M points rendered
    "cloud_margin_m": 10,
    "min_voxel_points": 20,    # noise filter: min points per 0.5 m voxel per 10 M points
    "gnss_match_m": 0.25,
    "surface_radius_m": 0.05,
    "bearing_deg": 160,        # camera seen from the plants: 160 = from the south-south-east
    "elevation_deg": 40,
    "view_angle_deg": 32,
    "crop_margin": 1.45,
    "crop_min_aspect": 1.35,
    "window": (3600, 2400),
    "point_size": 2.5,
    "plant_radius_m": 0.15,
    "egg_radius_m": 0.32,
    "pin_height_m": 3.5,
}
COL_PLANT = "#2E9BE6"          # saturated blue: does not read as a gap in the point cloud
plt = figure_style()
need(C.GYLDENLOVE_PC, "Gyldenløve point cloud")
need(C.GYLDENLOVE_GNSS, "Gyldenløve GNSS export")

with laspy.open(C.GYLDENLOVE_PC) as f:
    hdr = f.header
origin = np.array([np.floor(hdr.mins[0]), np.floor(hdr.mins[1]), 0.0])
plants = gpd.read_file(C.SMORBUKK_SHP).to_crs(C.WORKING_EPSG)
plants["Year"] = plants["Year"].astype(str).str.replace(r"\.0$", "", regex=True)
px, py = plants.geometry.x.to_numpy(), plants.geometry.y.to_numpy()
inside = (px >= hdr.mins[0]) & (px <= hdr.maxs[0]) & (py >= hdr.mins[1]) & (py <= hdr.maxs[1])
noegg = plants[inside & (plants.Egg == 0)].copy()
eggs = plants[inside & (plants.Egg == 1) & plants.Year.isin(C.EGG_YEARS)].copy()
m = VIEW["cloud_margin_m"]
allx, ally = np.r_[noegg.geometry.x, eggs.geometry.x], np.r_[noegg.geometry.y, eggs.geometry.y]
box = (allx.min() - m, ally.min() - m, allx.max() + m, ally.max() + m)

# ------------------------------------------------------------ point cloud
t0 = time.time()
rng = np.random.default_rng(2026)
parts = []
with laspy.open(C.GYLDENLOVE_PC) as f:
    for ch in f.chunk_iterator(5_000_000):
        x, y = np.asarray(ch.x), np.asarray(ch.y)
        k = (rng.random(len(ch)) < VIEW["keep_fraction"]) & (x >= box[0]) & (x <= box[2]) & (y >= box[1]) & (y <= box[3])
        parts.append((np.column_stack([x[k] - origin[0], y[k] - origin[1], np.asarray(ch.z)[k]]).astype(np.float32),
                      (np.column_stack([np.asarray(ch.red)[k], np.asarray(ch.green)[k],
                                        np.asarray(ch.blue)[k]]) >> 8).astype(np.uint8)))
xyz = np.concatenate([p[0] for p in parts])
rgb = np.concatenate([p[1] for p in parts])
del parts
vox = np.floor(xyz / 0.5).astype(np.int64)
_, inv, cnt = np.unique((vox[:, 0] * 4096 + vox[:, 1]) * 4096 + vox[:, 2], return_inverse=True, return_counts=True)
keep = cnt[inv] >= VIEW["min_voxel_points"] * len(xyz) / 1e7     # drop isolated noise
xyz, rgb = xyz[keep], rgb[keep]
lo, hi = np.percentile(rgb, [1, 99.5], axis=0)                     # mild contrast stretch
rgb = np.clip((rgb.astype(np.float32) - lo) / (hi - lo) * 255, 0, 255).astype(np.uint8)
log(f"Point cloud: {len(xyz):,} of {hdr.point_count:,} points in {time.time() - t0:.0f} s")

# ---------------------------------------------------------- plant heights
gnss = pd.read_csv(C.GYLDENLOVE_GNSS, encoding="utf-8-sig")
gtree = cKDTree(gnss[["X", "Y"]].to_numpy())
ctree2d = cKDTree(xyz[:, :2].astype(np.float64))


def surface_z(x, y, r):
    idx = ctree2d.query_ball_point(np.column_stack([x - origin[0], y - origin[1]]), r)
    return np.array([np.median(xyz[i, 2]) if len(i) else np.nan for i in idx])


def gnss_z(df, max_d):
    d, i = gtree.query(np.column_stack([df.geometry.x, df.geometry.y]))
    return np.where(d <= max_d, gnss["Z"].to_numpy()[i], np.nan)


noegg["z_gnss"], eggs["z_gnss"] = gnss_z(noegg, 0.02), gnss_z(eggs, VIEW["gnss_match_m"])
for df in (noegg, eggs):
    df["z_surf"] = surface_z(df.geometry.x, df.geometry.y, VIEW["surface_radius_m"])
offset = np.nanmedian(noegg.z_gnss - noegg.z_surf)
for df in (noegg, eggs):
    df["z_plot"] = np.where(np.isfinite(df.z_gnss), df.z_gnss - offset, df.z_surf)
    miss = df.z_plot.isna()
    if miss.any():
        df.loc[miss, "z_plot"] = surface_z(df.loc[miss].geometry.x, df.loc[miss].geometry.y, 0.25)
log(f"GNSS height - point-cloud height: median {offset:.3f} m")


def local(df):
    df = df[df.z_plot.notna()]
    return np.column_stack([df.geometry.x - origin[0], df.geometry.y - origin[1], df.z_plot]).astype(np.float32)


def on_cloud(pts, max_d=0.3):
    """Plants with cloud surface within max_d; others would float in empty space."""
    d, _ = cKDTree(xyz).query(pts, distance_upper_bound=max_d)
    return np.isfinite(d)


P_ALL, E_ALL = local(noegg), local(eggs)
p_pts, e_pts = P_ALL[on_cloud(P_ALL)], E_ALL[on_cloud(E_ALL)]
n_hidden = len(P_ALL) + len(E_ALL) - len(p_pts) - len(e_pts)

# ----------------------------------------------------------------- render
pv.OFF_SCREEN = True
allp = np.vstack([p_pts, e_pts])
lo_p, hi_p = np.percentile(allp, [2, 98], axis=0)
centre = np.array([(lo_p[0] + hi_p[0]) / 2, (lo_p[1] + hi_p[1]) / 2, np.median(allp[:, 2])])
span = (hi_p[:2] - lo_p[:2]).max()
b, e = np.radians(VIEW["bearing_deg"]), np.radians(VIEW["elevation_deg"])
dist = span / np.tan(np.radians(VIEW["view_angle_deg"]) / 2) * 0.5
cam = centre + dist * np.array([np.sin(b) * np.cos(e), np.cos(b) * np.cos(e), np.sin(e)])

cloud = pv.PolyData(xyz)
cloud["rgb"] = rgb
pl = pv.Plotter(off_screen=True, window_size=VIEW["window"])
pl.set_background("white")
pl.add_points(cloud, scalars="rgb", rgb=True, point_size=VIEW["point_size"], render_points_as_spheres=False)
sph = pv.Sphere(radius=1.0, theta_resolution=20, phi_resolution=20)
pr, er = VIEW["plant_radius_m"], VIEW["egg_radius_m"]
pl.add_mesh(pv.PolyData(p_pts + np.array([0, 0, pr * 0.6], dtype=np.float32)).glyph(geom=sph, scale=False,
                                                                                      orient=False, factor=pr),
            color=COL_PLANT, smooth_shading=True, ambient=0.35, diffuse=0.75, specular=0.2)
elift = np.array([0, 0, er * 0.6], dtype=np.float32)
pl.add_mesh(pv.PolyData(e_pts + elift).glyph(geom=sph, scale=False, orient=False, factor=er),
            color="#F07A2E", smooth_shading=True, ambient=0.35, diffuse=0.75, specular=0.3)
for p in e_pts:
    top = p + np.array([0, 0, VIEW["pin_height_m"]], dtype=np.float32)
    pl.add_mesh(pv.Tube(pointa=p + elift, pointb=top, radius=er * 0.18), color="#F07A2E", ambient=0.4)
    pl.add_mesh(pv.Sphere(radius=er * 0.8, center=top), color="#F07A2E", smooth_shading=True, ambient=0.4)
pl.enable_eye_dome_lighting()
pl.camera.position, pl.camera.focal_point, pl.camera.up = tuple(cam), tuple(centre), (0, 0, 1)
pl.camera.view_angle = VIEW["view_angle_deg"]
pl.enable_anti_aliasing("ssaa")
img = pl.screenshot(return_img=True)

# Crop around the plants (outermost 1 % ignored; every egg plant and pin kept).
ren = pl.renderer
sx = img.shape[1] / ren.GetSize()[0]
proj = []
for p in np.vstack([allp, e_pts + np.array([0, 0, VIEW["pin_height_m"]], dtype=np.float32)]):
    ren.SetWorldPoint(float(p[0]), float(p[1]), float(p[2]), 1.0)
    ren.WorldToDisplay()
    dx, dy, _ = ren.GetDisplayPoint()
    proj.append((img.shape[0] - dy * sx, dx * sx))
pl.close()
proj = np.array(proj)
h, w = img.shape[:2]
n_pl = len(allp)
eproj = np.vstack([proj[len(p_pts):n_pl], proj[n_pl:]])
r_lo, r_hi = np.percentile(proj[:n_pl, 0], [1, 99])
c_lo, c_hi = np.percentile(proj[:n_pl, 1], [1, 99])
r_lo, r_hi = min(r_lo, eproj[:, 0].min()), max(r_hi, eproj[:, 0].max())
c_lo, c_hi = min(c_lo, eproj[:, 1].min()), max(c_hi, eproj[:, 1].max())
rc, cc = (r_lo + r_hi) / 2, (c_lo + c_hi) / 2
hr = min((r_hi - r_lo) / 2 * VIEW["crop_margin"], rc, h - rc)
hc = min(max((c_hi - c_lo) / 2 * VIEW["crop_margin"], hr * VIEW["crop_min_aspect"]), cc, w - cc)
img = img[int(rc - hr):int(rc + hr), int(cc - hc):int(cc + hc)]

# ----------------------------------------------------------------- figure
h, w = img.shape[:2]
H = 12 * h / w + 2.0
fig = plt.figure(figsize=(12, H))
ax = fig.add_axes([0, 1.1 / H, 1, 12 * h / w / H])
ax.imshow(img)
ax.axis("off")
fig.text(0.01, 1 - 0.15 / H, "Gyldenløve i 3D: smørbukk og egg av klippeblåvinge", fontsize=15, fontweight="bold",
         color=TXT_DARK, va="top")
fig.text(0.01, 1 - 0.52 / H, f"Sett fra sør-sørøst · smørbukk med og uten egg {C.EGG_YEARS[0]}", fontsize=10.5,
         color="#4B5F6A", va="top")
fig.legend(handles=[Line2D([], [], marker="o", linestyle="", markersize=7, markerfacecolor=COL_PLANT,
                           markeredgecolor="#2B5A73", label=f"Smørbukk uten egg (n = {len(p_pts)})"),
                    Line2D([], [], marker="o", linestyle="", markersize=11, markerfacecolor=COL_EGG,
                           markeredgecolor="#7A3410", label=f"Smørbukk med egg {C.EGG_YEARS[0]} (n = {len(e_pts)})")],
           loc="lower left", bbox_to_anchor=(0.01, 0.4 / H), ncol=2, frameon=False, fontsize=10)
fig.text(0.01, 0.12 / H, f"Fargelagt punktsky fra dronefotogrammetri (Gyldenløve, mai 2026), "
         f"{VIEW['keep_fraction'] * 100:.0f} % av punktene vist. Plantehøyder fra GNSS-innmåling, justert til "
         "punktskyen. Planter med egg er markert med nål. Skrå 3D-visning: ingen fast målestokk."
         + (f" {n_hidden} planter utenfor punktskyen er ikke vist." if n_hidden else ""),
         fontsize=8.5, color=TXT_LIGHT, va="bottom", wrap=True)
out = C.IMG / "figur_1_3d_gyldenlove.jpg"
fig.savefig(out, dpi=200, facecolor="white", pil_kwargs={"quality": 88})
plt.close(fig)
log(f"Saved {out.name}: {len(p_pts)} plants without eggs, {len(e_pts)} with eggs, {n_hidden} outside the cloud")
