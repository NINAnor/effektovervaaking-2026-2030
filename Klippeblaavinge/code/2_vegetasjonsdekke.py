"""2. Vegetation cover around the plants from the drone orthophotos, and how
well PlanetScope NDVI tracks it.

Input (P:): drone orthophotos (May 2025/2026), PlanetScope indices (Aug 2025),
data/smorbukk_planter.csv.
Output: data/vegetasjonsdekke_punkter.csv (plants and random points),
data/ndvi_vegetasjonsdekke_klasser.csv (NDVI classes), img/figur_5_vegetasjon_og_ndvi.png.
The pixel-level NDVI pairs stay in WORK/qa (PlanetScope licence).

Vegetation: orthophotos averaged to 10 cm. A pixel is vegetation if its
excess-green index (2g - r - b on chromatic coordinates) is above a per-site
Otsu threshold, OR it has a saturated yellow-green-brown colour (hue 35-170
deg, saturation above a per-site Otsu threshold: dry grass, moss, heather),
OR it is weakly green and moderately saturated. Grey/white rock and the
pink-red granite (hue < 35 deg) are not vegetation. Dark shadow pixels are
left out.
"""

import time

import matplotlib
import numpy as np
import pandas as pd
import rasterio
from pyproj import Transformer
from rasterio.enums import Resampling
from rasterio.warp import reproject
from scipy.signal import fftconvolve

import config as C
from felles import COL_BG, COL_EGG, COL_NO, TXT_DARK, TXT_LIGHT, figure_style, log, need, save_png

RES_M = 0.10
SHADOW_BRIGHTNESS = 0.12
N_RANDOM_PER_SITE = 2000
MIN_PS_COVERAGE = 0.8
rng = np.random.default_rng(7)
plt = figure_style()


def otsu(v, bins=256):
    hist, edges = np.histogram(v, bins=bins)
    mids = (edges[:-1] + edges[1:]) / 2
    w0 = np.cumsum(hist)
    w1 = w0[-1] - w0
    m0 = np.cumsum(hist * mids) / np.maximum(w0, 1)
    m1 = (np.sum(hist * mids) - np.cumsum(hist * mids)) / np.maximum(w1, 1)
    return mids[np.argmax(w0 * w1 * (m0 - m1) ** 2)]


def disk_share(veg, valid, radius_cells):
    """Share of vegetation among valid pixels within a disk."""
    r = int(np.ceil(radius_cells))
    yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
    k = (np.hypot(yy, xx) <= radius_cells).astype(np.float32)
    s = fftconvolve(np.where(valid, veg, 0).astype(np.float32), k, mode="same")
    n = fftconvolve(valid.astype(np.float32), k, mode="same")
    with np.errstate(invalid="ignore", divide="ignore"):
        out = s / n
    out[n < 0.5 * k.sum()] = np.nan
    return out


need(C.PLANETSCOPE, "PlanetScope indices")
plants = pd.read_csv(C.DATA / "smorbukk_planter.csv")
ps = rasterio.open(C.PLANETSCOPE)
ps_ndvi = ps.read([i + 1 for i, d in enumerate(ps.descriptions) if d and d.upper() == "NDVI"][0]).astype(np.float32)

rows, pairs, examples = [], [], {}
for key, site in C.SITES.items():
    t0 = time.time()
    need(site["ortho"], f"Orthophoto ({key})")
    with rasterio.open(site["ortho"]) as r:
        f = max(1, int(round(RES_M / r.res[0])))
        shape = (r.height // f, r.width // f)
        nb = min(r.count, 4)
        a = r.read(list(range(1, nb + 1)), out_shape=(nb,) + shape, resampling=Resampling.average).astype(np.float32)
        tf = r.transform * r.transform.scale(r.width / shape[1], r.height / shape[0])
        crs = r.crs
    rgb = a[:3]
    mask = ((a[3] > 0) if nb == 4 else ~(rgb == 255).all(axis=0)) & (rgb.sum(axis=0) > 0)
    tot = rgb.sum(axis=0)
    with np.errstate(invalid="ignore", divide="ignore"):
        exg = (2 * rgb[1] - rgb[0] - rgb[2]) / tot
        mx, mn = rgb.max(axis=0), rgb.min(axis=0)
        sat = np.where(mx > 0, (mx - mn) / mx, 0)
    hue = (np.degrees(np.arctan2(np.sqrt(3) * (rgb[1] - rgb[2]), 2 * rgb[0] - rgb[1] - rgb[2])) + 360) % 360
    valid = mask & np.isfinite(exg) & (tot / (3 * 255) >= SHADOW_BRIGHTNESS)
    thr, thr_sat = otsu(exg[valid]), otsu(sat[valid])
    veg = valid & ((exg > thr) | ((sat > thr_sat) & (hue > 35) & (hue < 170)) | ((exg > 0.02) & (sat > 0.18)))
    res = abs(tf.a)
    shares = {rad: disk_share(veg, valid, rad / res) for rad in C.RADII_M}
    H, W = veg.shape

    def sample(x, y):
        c = np.floor((x - tf.c) / res).astype(int)
        rr = np.floor((tf.f - y) / res).astype(int)
        ok = (rr >= 0) & (rr < H) & (c >= 0) & (c < W)
        out = {}
        for rad, sh in shares.items():
            v = np.full(len(x), np.nan)
            v[ok] = sh[rr[ok], c[ok]]
            out[rad] = v
        return out, ok

    sub = plants[plants.site == site["label"]]
    px, py = (np.asarray(v) for v in Transformer.from_crs(C.WORKING_EPSG, crs, always_xy=True)
              .transform(sub.x_m.to_numpy(), sub.y_m.to_numpy()))
    vals, ok = sample(px, py)
    rows.append(pd.DataFrame({"site": site["label"], "plant_row_id": sub.plant_row_id.to_numpy(),
                              "gruppe": np.where(sub.egg == 1, "Med egg", "Uten egg"),
                              **{f"veg_{r}m": vals[r] for r in C.RADII_M}})[ok])
    vr, vc = np.nonzero(valid)
    pick = rng.choice(len(vr), size=N_RANDOM_PER_SITE, replace=False)
    vals_r, _ = sample(tf.c + (vc[pick] + 0.5) * res, tf.f - (vr[pick] + 0.5) * res)
    rows.append(pd.DataFrame({"site": site["label"], "plant_row_id": pd.NA, "gruppe": "Tilfeldige punkt",
                              **{f"veg_{r}m": vals_r[r] for r in C.RADII_M}}))

    # Vegetation share averaged into each PlanetScope pixel (>= 80 % drone coverage).
    dst_v = np.full(ps_ndvi.shape, np.nan, dtype=np.float32)
    dst_c = np.zeros(ps_ndvi.shape, dtype=np.float32)
    reproject(np.where(valid, veg, np.nan).astype(np.float32), dst_v, src_transform=tf, src_crs=crs,
              dst_transform=ps.transform, dst_crs=ps.crs, resampling=Resampling.average,
              src_nodata=np.nan, dst_nodata=np.nan)
    reproject(np.where(mask, valid, 0).astype(np.float32), dst_c, src_transform=tf, src_crs=crs,
              dst_transform=ps.transform, dst_crs=ps.crs, resampling=Resampling.average)
    good = np.isfinite(dst_v) & (dst_c >= MIN_PS_COVERAGE) & np.isfinite(ps_ndvi)
    pairs.append(pd.DataFrame({"site": site["label"], "veg_andel": dst_v[good], "ndvi": ps_ndvi[good]}))

    if len(sub):  # 24 x 24 m example around the median plant
        r0 = max(0, int((tf.f - np.median(py)) / res) - 120)
        c0 = max(0, int((np.median(px) - tf.c) / res) - 120)
        crop = (slice(r0, r0 + 240), slice(c0, c0 + 240))
        examples[key] = (np.clip(np.moveaxis(rgb[:, crop[0], crop[1]], 0, -1) / 255 * 1.15, 0, 1),
                         veg[crop], valid[crop])
    log(f"{site['label']}: thresholds ExG {thr:.3f} / saturation {thr_sat:.3f}; vegetation share "
        f"{veg[valid].mean():.2f}; {ok.sum()} plants ({time.time() - t0:.0f} s)")

df = pd.concat(rows, ignore_index=True)
df.to_csv(C.DATA / "vegetasjonsdekke_punkter.csv", index=False, float_format="%.4f")
pairs = pd.concat(pairs, ignore_index=True)
C.QA.mkdir(parents=True, exist_ok=True)
pairs.to_csv(C.QA / "ndvi_mot_vegetasjonsdekke_piksler.csv", index=False)
r_all = pairs[["ndvi", "veg_andel"]].corr(method="spearman").iloc[0, 1]
bins = np.arange(0.5, 0.91, 0.05)
bstat = pairs.groupby(pd.cut(pairs.ndvi, bins), observed=True).veg_andel.describe()[["count", "25%", "50%", "75%"]]
bstat = bstat[bstat["count"] >= 50]
bstat.index = [f"{iv.left:.2f}-{iv.right:.2f}" for iv in bstat.index]
bstat.rename_axis("ndvi_klasse").rename(columns={"count": "n_piksler", "25%": "veg_q25", "50%": "veg_median",
                                                 "75%": "veg_q75"}).to_csv(C.DATA / "ndvi_vegetasjonsdekke_klasser.csv",
                                                                          float_format="%.3f")
log(f"NDVI vs drone vegetation share: Spearman r = {r_all:.2f} (n = {len(pairs)} pixels)")

# ------------------------------------------------------------------ figure
fig = plt.figure(figsize=(12.5, 4.4), layout="constrained")
gs = fig.add_gridspec(1, 3, width_ratios=[0.8, 1.25, 1])
axa = fig.add_subplot(gs[0])
ex = "Gyldenlove" if "Gyldenlove" in examples else next(iter(examples))
img, vg, vd = examples[ex]
over = np.zeros(vg.shape + (4,))
over[vg] = (0.15, 0.75, 0.25, 0.55)
over[~vd] = (0.1, 0.1, 0.3, 0.35)
axa.imshow(img)
axa.imshow(over)
axa.set_xticks([])
axa.set_yticks([])
axa.set_title(f"a  Vegetasjon fra droneortofoto\n{C.SITE_LABELS[ex]}, 24 × 24 m utsnitt", loc="left",
              fontsize=10, fontweight="bold", color=TXT_DARK)
axa.text(0.01, -0.06, "Grønt: vegetasjon (grønn eller gul-brun farge). Mørkeblått: skygge, utelatt.",
         transform=axa.transAxes, fontsize=8, color=TXT_LIGHT, va="top")

axb = fig.add_subplot(gs[1])
groups = [("Tilfeldige punkt", COL_BG), ("Uten egg", COL_NO), ("Med egg", COL_EGG)]
labels = list(C.SITE_LABELS.values())
for j, s in enumerate(labels):
    for gi, (g, col) in enumerate(groups):
        v = df.loc[(df.site == s) & (df.gruppe == g), "veg_1m"].dropna()
        if len(v):
            bp = axb.boxplot([v], positions=[j + (gi - 1) * 0.26], widths=0.22, showfliers=False,
                             patch_artist=True, medianprops=dict(color="#1B3341", linewidth=1.5))
            bp["boxes"][0].set_facecolor(matplotlib.colors.to_rgba(col, 0.55))
            bp["boxes"][0].set_edgecolor("#263D4C")
axb.set_xticks(range(len(labels)), labels)
axb.set_ylabel("Andel vegetasjon innen 1 m")
axb.set_ylim(-0.02, 1.02)
for g, col in groups:
    axb.bar(0, 0, color=matplotlib.colors.to_rgba(col, 0.55), label=g if g == "Tilfeldige punkt" else f"Smørbukk {g.lower()}")
axb.legend(frameon=False, fontsize=8, loc="upper left", ncol=3, bbox_to_anchor=(0, 1.1))
axb.set_title("b  Smørbukk står på mer bart berg", loc="left", fontsize=10, fontweight="bold", color=TXT_DARK, pad=22)

axc = fig.add_subplot(gs[2])
for s, col in zip(labels, ["#2F6B55", "#8A6A2B", "#5B4E8C"]):
    d = pairs[pairs.site == s]
    axc.scatter(d.ndvi, d.veg_andel, s=4, alpha=0.35, color=col, linewidths=0, label=s)
bx = [float(i.split("-")[0]) + 0.025 for i in bstat.index]
axc.fill_between(bx, bstat["25%"], bstat["75%"], color="#1B3341", alpha=0.15, linewidth=0)
axc.plot(bx, bstat["50%"], color="#1B3341", linewidth=2, marker="o", markersize=4, label="Median (kvartiler)")
axc.set_xlabel("PlanetScope NDVI (aug. 2025, 3 m)")
axc.set_ylabel("Andel vegetasjon i pikselen (drone)")
axc.set_title(f"c  NDVI og vegetasjonsdekke (Spearman r = {r_all:.2f})".replace(".", ","), loc="left", fontsize=10,
              fontweight="bold", color=TXT_DARK)
axc.legend(frameon=False, fontsize=8, markerscale=3, loc="upper left")
fig.suptitle("Bart berg mot vegetasjon rundt smørbukk – og koblingen til PlanetScope NDVI", x=0.01, ha="left",
             fontsize=12.5, fontweight="bold", color=TXT_DARK)
save_png(fig, C.IMG / "figur_5_vegetasjon_og_ndvi.png")
