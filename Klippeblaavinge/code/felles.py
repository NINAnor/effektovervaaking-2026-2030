"""Shared functions for the Klippeblåvinge scripts: terrain, horizons, clear-sky
irradiation, LiDAR mosaics, AUC tests and figure style."""

import os

# A user-level PROJ_DATA/PROJ_LIB pointing elsewhere breaks CRS lookups; use
# the PROJ database bundled with pyproj/rasterio.
for _var in ("PROJ_DATA", "PROJ_LIB"):
    os.environ.pop(_var, None)

import hashlib
import time
import warnings
from pathlib import Path

import numpy as np
import pandas as pd
import pvlib
import rasterio
from rasterio.merge import merge as raster_merge
from scipy import ndimage

warnings.filterwarnings("ignore", message="Mean of empty slice")
warnings.filterwarnings("ignore", message="All-NaN slice encountered")
warnings.filterwarnings("ignore", category=RuntimeWarning, message="invalid value encountered")

# ------------------------------------------------------------------ helpers


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def radius_code(r):
    return f"{r:g}".replace(".", "p")


def file_signature(*paths):
    """Short hash of file names, sizes and modification times (cache keys)."""
    h = hashlib.sha1()
    for p in paths:
        st = Path(p).stat()
        h.update(f"{p}|{st.st_size}|{st.st_mtime_ns}".encode())
    return h.hexdigest()[:12]


def need(path, what):
    if not Path(path).exists():
        raise FileNotFoundError(f"{what} not found: {path}\nSee code/config.py for paths and environment variables.")


# --------------------------------------------------------- raster algorithms


def horn_gradients(z, res):
    """Horn (1981) gradients: dz/dx (+ rising east), dz/dy (+ rising north).
    Rows run north to south; NaN where any neighbour is NaN."""
    p = np.pad(z, 1, constant_values=np.nan)
    a, b, c = p[:-2, :-2], p[:-2, 1:-1], p[:-2, 2:]
    d, f = p[1:-1, :-2], p[1:-1, 2:]
    g, h, i = p[2:, :-2], p[2:, 1:-1], p[2:, 2:]
    dzdx = ((c + 2 * f + i) - (a + 2 * d + g)) / (8 * res)
    dzdy = ((a + 2 * b + c) - (g + 2 * h + i)) / (8 * res)
    return dzdx.astype(np.float32), dzdy.astype(np.float32)


def horn_slope_aspect(z, res):
    """Slope (deg) and aspect (deg clockwise from north, downslope direction)."""
    dzdx, dzdy = horn_gradients(z, res)
    grad = np.hypot(dzdx, dzdy)
    slope = np.degrees(np.arctan(grad))
    aspect = (np.degrees(np.arctan2(-dzdx, -dzdy)) + 360.0) % 360.0
    aspect[grad < 1e-6] = np.nan  # flat: aspect undefined
    return slope.astype(np.float32), aspect.astype(np.float32)


def block_mean(z, f, min_frac=0.5):
    """Block-average a grid by an integer factor; NaN where too few valid cells."""
    if f == 1:
        return z
    oh, ow = z.shape[0] // f, z.shape[1] // f
    b = z[:oh * f, :ow * f].reshape(oh, f, ow, f)
    cnt = np.isfinite(b).sum(axis=(1, 3))
    with np.errstate(invalid="ignore"):
        out = (np.nansum(b, axis=(1, 3)) / cnt).astype(np.float32)
    out[cnt < min_frac * f * f] = np.nan
    return out


def disk_mean(z, radius_cells):
    """Mean of valid cells within a circular window (NaN-aware)."""
    r = int(np.ceil(radius_cells))
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    k = (np.hypot(yy, xx) <= radius_cells).astype(np.float32)
    valid = np.isfinite(z).astype(np.float32)
    s = ndimage.convolve(np.nan_to_num(z), k, mode="constant")
    n = ndimage.convolve(valid, k, mode="constant")
    with np.errstate(invalid="ignore"):
        out = s / n
    out[n < 0.5 * k.sum()] = np.nan
    return out.astype(np.float32)


def load_lidar(dtm_dir, dom_dir, box, cache_dir):
    """Mosaic the LiDAR DTM and DOM tiles over box (xmin, ymin, xmax, ymax in
    the tiles' CRS). Cached as .npz keyed on the tile files and the box.
    Returns dtm, dom, affine transform, CRS, cell size."""
    files = {"dtm": sorted(Path(dtm_dir).glob("*.tif")), "dom": sorted(Path(dom_dir).glob("*.tif"))}
    if not files["dtm"] or not files["dom"]:
        raise FileNotFoundError(f"No LiDAR tiles in {dtm_dir} / {dom_dir}")
    sig = hashlib.sha1((file_signature(*files["dtm"], *files["dom"])
                        + str(np.round(box, 1))).encode()).hexdigest()[:12]
    cache_dir.mkdir(parents=True, exist_ok=True)
    cfile = cache_dir / f"lidar_{sig}.npz"
    with rasterio.open(files["dtm"][0]) as r:
        crs, res = r.crs, float(r.res[0])
    if cfile.exists():
        c = np.load(cfile)
        return c["dtm"], c["dom"], rasterio.Affine(*c["transform"][:6]), crs, res
    grids = {}
    for name, fl in files.items():
        srcs = [rasterio.open(f) for f in fl]
        arr, tf = raster_merge(srcs, bounds=box, nodata=np.nan, dtype="float32")
        for s in srcs:
            s.close()
        a = arr[0]
        a[~np.isfinite(a) | (a < -1000)] = np.nan
        grids[name] = a
    np.savez_compressed(cfile, dtm=grids["dtm"], dom=grids["dom"], transform=np.array(tf))
    return grids["dtm"], grids["dom"], tf, crs, res


# --------------------------------------------------------- plant summaries


def _disk_offsets(row, col, res, k):
    offs = np.arange(-k, k + 1)
    r0, c0 = int(np.floor(row)), int(np.floor(col))
    dy = -((r0 + offs + 0.5) - row) * res   # north-positive offsets of cell centres
    dx = ((c0 + offs + 0.5) - col) * res
    DX, DY = np.meshgrid(dx, dy)
    return r0, c0, DX, DY


def plant_terrain(dtm, slope, aspect, transform, res, x, y, radii, plane_r, min_frac):
    """Per-plant disk summaries on an in-memory grid: valid fraction, mean
    slope, northness and eastness within each radius; a least-squares plane
    within plane_r (orientation for irradiation) and relative position
    (plane height minus mean ground within the larger radii)."""
    n = len(x)
    k = int(np.ceil(max(max(radii), plane_r) / res)) + 1
    padz, pads, pada = (np.pad(a, k, constant_values=np.nan) for a in (dtm, slope, aspect))
    col = (x - transform.c) / res
    row = (transform.f - y) / res
    out = {f"dem_fraction_{radius_code(r)}m": np.full(n, np.nan) for r in radii}
    for r in radii:
        for m in ("slope_deg", "northness", "eastness"):
            out[f"{m}_{radius_code(r)}m"] = np.full(n, np.nan)
    for key in ("plane_slope_deg", "plane_aspect_deg", "plane_z", "plane_fraction"):
        out[key] = np.full(n, np.nan)
    tpi_radii = [r for r in radii if r > plane_r]
    for r in tpi_radii:
        out[f"tpi_{radius_code(r)}m"] = np.full(n, np.nan)
    for j in range(n):
        r0, c0, DX, DY = _disk_offsets(row[j], col[j], res, k)
        if not (0 <= r0 < dtm.shape[0] and 0 <= c0 < dtm.shape[1]):
            continue
        rs, cs = slice(r0, r0 + 2 * k + 1), slice(c0, c0 + 2 * k + 1)
        zw, sw, aw = padz[rs, cs], pads[rs, cs], pada[rs, cs]
        dist = np.hypot(DX, DY)
        zvalid = np.isfinite(zw)
        means_z = {}
        for r in radii:
            disk = dist <= r
            code = radius_code(r)
            frac = zvalid[disk].mean()
            out[f"dem_fraction_{code}m"][j] = frac
            if frac < min_frac:
                continue
            asp = np.radians(aw[disk])
            out[f"slope_deg_{code}m"][j] = np.nanmean(sw[disk])
            out[f"northness_{code}m"][j] = np.nanmean(np.cos(asp))
            out[f"eastness_{code}m"][j] = np.nanmean(np.sin(asp))
            means_z[r] = np.nanmean(zw[disk])
        disk = (dist <= plane_r) & zvalid
        frac = disk.sum() / max(1, (dist <= plane_r).sum())
        out["plane_fraction"][j] = frac
        if frac >= min_frac and disk.sum() >= 6:
            A = np.column_stack([np.ones(disk.sum()), DX[disk], DY[disk]])
            (z0, bx, by), *_ = np.linalg.lstsq(A, zw[disk].astype(np.float64), rcond=None)
            out["plane_z"][j] = z0
            out["plane_slope_deg"][j] = np.degrees(np.arctan(np.hypot(bx, by)))
            out["plane_aspect_deg"][j] = (np.degrees(np.arctan2(-bx, -by)) + 360.0) % 360.0
            for r in tpi_radii:
                if r in means_z:
                    # + plant higher than its surroundings (ledge, ridge); - hollow, wall foot
                    out[f"tpi_{radius_code(r)}m"][j] = z0 - means_z[r]
    return pd.DataFrame(out)


def plant_chm(chm, transform, res, x, y, radii, threshold, min_frac):
    """Height above ground (DOM - DTM) per plant disk: mean, max and share of
    cells above threshold. Picks up vegetation, walls and boulders, and on
    steep faces differences between the two LiDAR grids."""
    n = len(x)
    k = int(np.ceil(max(radii) / res)) + 1
    pad = np.pad(chm, k, constant_values=np.nan)
    col = (x - transform.c) / res
    row = (transform.f - y) / res
    out = {f"chm_{m}_{radius_code(r)}m": np.full(n, np.nan) for r in radii for m in ("mean", "max", "cover")}
    for j in range(n):
        r0, c0, DX, DY = _disk_offsets(row[j], col[j], res, k)
        if not (0 <= r0 < chm.shape[0] and 0 <= c0 < chm.shape[1]):
            continue
        w = pad[r0:r0 + 2 * k + 1, c0:c0 + 2 * k + 1]
        dist = np.hypot(DX, DY)
        for r in radii:
            v = w[dist <= r]
            v = v[np.isfinite(v)]
            if len(v) < min_frac * (dist <= r).sum():
                continue
            code = radius_code(r)
            out[f"chm_mean_{code}m"][j] = np.clip(v, 0, None).mean()
            out[f"chm_max_{code}m"][j] = v.max()
            out[f"chm_cover_{code}m"][j] = (v > threshold).mean()
    return pd.DataFrame(out)


# ------------------------------------------------------ horizons and sun


def ray_distances(d_min, d_max, res, growth=0.01):
    """Sample distances along a horizon ray: one cell apart near the observer,
    then growing by 1 % per step (angular error below ~0.6 degrees)."""
    d = [d_min]
    while d[-1] < d_max:
        d.append(d[-1] + max(res, growth * d[-1]))
    return np.array(d, dtype=np.float64)


def trace_horizons(dsm, res, row, col, z_obs, n_az, d, chunk=256):
    """Horizon elevation angle (rad) per observer and azimuth by ray-marching
    the surface model at distances d (m). Also returns the farthest valid
    sample distance per ray (reach, m)."""
    H, W = dsm.shape
    n = len(row)
    hor = np.full((n, n_az), np.nan, dtype=np.float32)
    reach = np.zeros((n, n_az), dtype=np.float32)
    for k in range(n_az):
        az = 2 * np.pi * k / n_az
        dr = -np.cos(az) * d / res
        dc = np.sin(az) * d / res
        for s0 in range(0, n, chunk):
            sl = slice(s0, min(n, s0 + chunk))
            rr = np.floor(row[sl, None] + dr[None, :]).astype(np.int64)
            cc = np.floor(col[sl, None] + dc[None, :]).astype(np.int64)
            ok = (rr >= 0) & (rr < H) & (cc >= 0) & (cc < W)
            z = np.full(rr.shape, np.nan, dtype=np.float32)
            z[ok] = dsm[rr[ok], cc[ok]]
            hor[sl, k] = np.nanmax(np.arctan2(z - z_obs[sl, None], d[None, :]), axis=1)
            fin = np.isfinite(z)
            reach[sl, k] = np.where(fin.any(axis=1), np.where(fin, d[None, :], 0).max(axis=1), 0)
    return hor, reach


def sun_table(lat, lon, sol):
    """Sun positions and clear-sky irradiance (Ineichen, Linke turbidity
    climatology) for the period, sun above the horizontal only."""
    tz = sol["tz"]
    step = pd.Timedelta(minutes=sol["step_min"])
    times = pd.date_range(pd.Timestamp(sol["start"], tz=tz),
                          pd.Timestamp(sol["end"], tz=tz) + pd.Timedelta(days=1) - step, freq=step) + step / 2
    loc = pvlib.location.Location(lat, lon, tz=tz, altitude=sol["site_altitude_m"])
    sp = loc.get_solarposition(times)
    cs = loc.get_clearsky(times, model="ineichen", solar_position=sp)
    extra = pvlib.irradiance.get_extra_radiation(times)
    up = sp["apparent_elevation"].to_numpy() > 0
    return {
        "alt": np.radians(sp["apparent_elevation"].to_numpy()[up]),
        "az": np.radians(sp["azimuth"].to_numpy()[up]),
        "dni": cs["dni"].to_numpy()[up],
        "dhi": cs["dhi"].to_numpy()[up],
        "ghi": cs["ghi"].to_numpy()[up],
        "dni_extra": extra.to_numpy()[up],
        "dt_h": sol["step_min"] / 60.0,
        "n_days": (pd.Timestamp(sol["end"]) - pd.Timestamp(sol["start"])).days + 1,
        "flat_kwh": cs["ghi"].to_numpy()[up].sum() * sol["step_min"] / 60.0 / 1000.0,
    }


def solar_exposure(slope_deg, aspect_deg, hor, sun, albedo, chunk=400):
    """Clear-sky irradiation on tilted planes with terrain shading.

    Beam: DNI x cos(incidence), zero when the sun is below the traced horizon
    in its azimuth or behind the plane. Diffuse: Hay-Davies (circumsolar part
    shaded like the beam, isotropic part scaled by the sky-view factor).
    Reflected: isotropic, albedo x GHI x (1 - SVF). Sky-view factor on the
    tilted plane after Dozier & Frew (1990), with the effective horizon in
    each direction = max(terrain horizon, the plane's own horizon, 0)."""
    n, n_az = hor.shape
    S = np.radians(np.clip(slope_deg, 0, 89.9))[:, None]
    A = np.radians(aspect_deg)[:, None]
    phi = (2 * np.pi * np.arange(n_az) / n_az)[None, :]
    plane = -np.arctan(np.tan(S) * np.cos(phi - A))
    Hz = np.pi / 2 - np.maximum(np.maximum(np.nan_to_num(hor, nan=0.0), 0.0), plane)
    svf = (np.cos(S) * np.sin(Hz) ** 2 + np.sin(S) * np.cos(phi - A) * (Hz - np.sin(Hz) * np.cos(Hz))).mean(axis=1)

    pos = sun["az"] / (2 * np.pi / n_az)
    i0 = np.floor(pos).astype(int) % n_az
    i1 = (i0 + 1) % n_az
    w = (pos - np.floor(pos))[None, :]
    hz = np.nan_to_num(hor, nan=-np.pi / 2)
    sin_alt, cos_alt = np.sin(sun["alt"]), np.cos(sun["alt"])
    ai = np.clip(sun["dni"] / sun["dni_extra"], 0, 1)
    morning = sun["az"] < np.pi
    dt = sun["dt_h"]
    res = {k: np.full(n, np.nan) for k in ("total", "beam", "hours", "morning", "afternoon")}
    for s0 in range(0, n, chunk):
        sl = slice(s0, min(n, s0 + chunk))
        lit = sun["alt"][None, :] > (hz[sl][:, i0] * (1 - w) + hz[sl][:, i1] * w)
        cos_i = np.clip(np.cos(S[sl]) * sin_alt[None, :]
                        + np.sin(S[sl]) * cos_alt[None, :] * np.cos(sun["az"][None, :] - A[sl]), 0, None)
        direct = lit & (cos_i > 0)
        beam = sun["dni"][None, :] * cos_i * lit
        rb = cos_i / np.maximum(sin_alt, 0.01745)[None, :]
        diffuse = sun["dhi"][None, :] * (ai[None, :] * rb * lit + (1 - ai[None, :]) * svf[sl, None])
        refl = albedo * sun["ghi"][None, :] * (1 - svf[sl, None])
        res["total"][sl] = (beam + diffuse + refl).sum(axis=1) * dt / 1000
        res["beam"][sl] = beam.sum(axis=1) * dt / 1000
        res["hours"][sl] = direct.sum(axis=1) * dt
        res["morning"][sl] = (direct & morning[None, :]).sum(axis=1) * dt
        res["afternoon"][sl] = (direct & ~morning[None, :]).sum(axis=1) * dt
    nd = sun["n_days"]
    return pd.DataFrame({
        "solar_kwh_m2_day": res["total"] / nd,
        "beam_kwh_m2_day": res["beam"] / nd,
        "solar_rel_flat_pct": 100 * res["total"] / sun["flat_kwh"],
        "sun_hours_day": res["hours"] / nd,
        "sun_hours_morning_day": res["morning"] / nd,
        "sun_hours_afternoon_day": res["afternoon"] / nd,
        "sky_view_factor": svf,
    })


# ------------------------------------------------------------- statistics


def auc(pos, neg):
    """Area under the ROC curve (Mann-Whitney identity); 0.5 = no difference."""
    pos, neg = np.asarray(pos, dtype=float), np.asarray(neg, dtype=float)
    if len(pos) == 0 or len(neg) == 0:
        return np.nan
    ranks = pd.Series(np.r_[pos, neg]).rank().to_numpy()
    return (ranks[:len(pos)].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg))


def strat_auc(v, egg, site):
    """AUC within each locality, averaged with the number of egg plants as weight."""
    tot, w = 0.0, 0
    for s in np.unique(site):
        m = site == s
        a = auc(v[m & (egg == 1)], v[m & (egg == 0)])
        n1 = int((m & (egg == 1)).sum())
        if np.isfinite(a) and n1:
            tot += a * n1
            w += n1
    return tot / w if w else np.nan


def bh_adjust(p):
    """Benjamini-Hochberg adjusted p-values (q)."""
    p = np.asarray(p, dtype=float)
    m = len(p)
    order = np.argsort(p)
    q = np.empty(m)
    prev = 1.0
    for rank, i in enumerate(order[::-1], start=1):
        prev = min(prev, p[i] * m / (m - rank + 1))
        q[i] = prev
    return q


# ------------------------------------------------------------ figure style

COL_NO = "#316987"      # smørbukk without eggs
COL_EGG = "#CF642F"     # smørbukk with eggs
COL_BG = "#B9B2A3"      # landscape / random points
TXT_DARK, TXT_MID, TXT_LIGHT = "#193447", "#4B5F6A", "#657783"
FIG_DPI = 200


def figure_style():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.family": "sans-serif", "font.size": 10, "axes.edgecolor": "#B8C4CA",
                         "axes.spines.top": False, "axes.spines.right": False, "pdf.fonttype": 42,
                         "figure.facecolor": "white", "axes.facecolor": "white"})
    return plt


def save_png(fig, path):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=FIG_DPI, bbox_inches="tight", facecolor="white")
    import matplotlib.pyplot as plt
    plt.close(fig)
    log(f"Saved {path.name}")
