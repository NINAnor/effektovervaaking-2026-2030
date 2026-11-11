"""Paths and settings shared by the Klippeblåvinge scripts.

Raw data stay on P:. Set the environment variables below to run elsewhere
(for example with a local copy of the data). Cleaned outputs are written to
the subproject's data/ and img/ folders; caches and QA files go to WORK.
"""

import os
from pathlib import Path

# ---------------------------------------------------------------- locations
SUBPROJECT = Path(__file__).resolve().parents[1]
DATA = SUBPROJECT / "data"
IMG = SUBPROJECT / "img"

P = Path(os.environ.get("KLIPPEBLAAVINGE_P", "P:/156004_06_effektovervaking_2026_2030_klippeblavinge"))
WORK = Path(os.environ.get("KLIPPEBLAAVINGE_WORK", P / "output_klippeblavinge_python"))
CACHE = WORK / "cache"
QA = WORK / "qa"

# Smørbukk survey: one point per plant (Year, Egg). GNSS, full precision.
SMORBUKK_SHP = P / "GPSData/smorbukk25_26_withEggs.shp"

# Drone surveys (May 2025: Overberget, Borgerskansen; May 2026: Gyldenløve).
# Keys are used in file names; labels in figures and data.
DRONE = P / "HaldenDroneData"
SITES = {
    "Overberget": {"label": "Overberget",
                   "dsm": DRONE / "EastSite-15-05-2025-dsm.tif",
                   "ortho": DRONE / "EastSite-15-05-2025-ortho.tif"},
    "Borgerskansen": {"label": "Borgerskansen",
                      "dsm": DRONE / "Northwall-15-05-2025-dsm.tif",
                      "ortho": DRONE / "NorthWall-15-05-2025-orthophoto.tif"},
    "Gyldenlove": {"label": "Gyldenløve",
                   "dsm": DRONE / "GyldenloveDEM.tif",
                   "ortho": DRONE / "GyldenloveOrtho.tif"},
}
SITE_LABELS = {k: v["label"] for k, v in SITES.items()}

# Gyldenløve drone point cloud (Metashape, May 2026) and the raw GNSS export
# of the 2026 smørbukk survey (heights are needed to place plants in 3D).
GYLDENLOVE_PC = Path(os.environ.get("KLIPPEBLAAVINGE_GYLDENLOVE_PC",
                                    DRONE / "Gyldenlove_2026/HaldenNewSiteFestningPC.laz"))
GYLDENLOVE_GNSS = Path(os.environ.get("KLIPPEBLAAVINGE_GYLDENLOVE_GNSS",
                                      DRONE / "Gyldenlove_2026/Punkt.csv"))

# National airborne LiDAR (Viken laser - Østfold 5pkt del2, flown 16 April
# 2022), gridded DTM and DOM tiles at 0.25 m from hoydedata.no.
LIDAR = Path(os.environ.get(
    "KLIPPEBLAAVINGE_LIDAR",
    P / "Analysis/eksport_1771282_20261014/Viken laser - Østfold 5pkt del2 2022/data"))
LIDAR_DTM = LIDAR / "dtm"
LIDAR_DOM = LIDAR / "dom"

# PlanetScope indices (August 2025, ~3 m). Licensed imagery: never copied to data/.
PLANETSCOPE = Path(os.environ.get("KLIPPEBLAAVINGE_PLANETSCOPE", P / "Analysis/PS_Indices_Aug2025.tif"))

# Study area: Halden festning.
STUDY_AREA = Path(os.environ.get(
    "KLIPPEBLAAVINGE_STUDY_AREA",
    "P:/154027_effektovervaking_av_trua_arter_og_naturtyper_2024/06 Klippeblåvinge/DroneOrthomosaics/haldenArea.shp"))

# ---------------------------------------------------------------- settings
WORKING_EPSG = 25832
EGG_YEARS = ["2026"]            # egg outcome; egg records from other years count only as host plants
DUPLICATE_ROUND_M = 0.01        # same-year records at identical 1 cm coordinates are duplicates
RADII_M = [1, 5]                # plant-scale summaries
MIN_VALID_FRACTION = 0.75       # share of valid cells needed within a disk
STEEP_FACE_DEG = 60             # flag: 2.5D models unreliable above this slope
LOCALITY_MAX_DIST_M = 150       # plants outside a drone tile take the nearest locality within this distance
CHM_THRESHOLD_M = 0.5           # DOM - DTM above this = raised structure
TREE_HEIGHT_M = 2.0             # DOM - DTM above this = trees, buildings, tall walls

SOLAR = {
    "start": "2025-05-15",      # flight and egg-laying period
    "end": "2025-06-30",
    "step_min": 10,
    "tz": "Europe/Oslo",
    "site_altitude_m": 60,
    "albedo": 0.20,
    "n_azimuths": 72,           # plants (the habitat map uses 36)
    "plane_radius_m": 1.0,      # plane fitted to the DTM within this radius
    "observer_height_m": 0.10,
    "horizon_radius_m": 500,
}

HABITAT = {
    "map_res_m": 2.0,
    "n_azimuths": 36,
    "min_ground_m": 2.0,        # cells with DTM below this are treated as water
    "n_background": 20000,
    "seed": 2026,
    "survey_buffer_m": 4.0,
    # Tested but not used in the model: NDVI (does not cover the whole area,
    # adds nothing) and height above ground (follows slope on steep faces).
    "exclude_from_model": ["ndvi", "chm"],
}

N_PERMUTATIONS = int(os.environ.get("KLIPPEBLAAVINGE_N_PERM", 9999))
