# Map of Archaeological Sites and Study Area

***From "Southeastern Tibetan Plateau: A Nexus for High-Altitude Hominin Adaptation and Dispersal"***

This repository contains the R code used to create the site map for this paper. Panel **A** shows Paleolithic sites across the central and eastern Tibetan Plateau and its eastern margin, while panel **B** provides a detailed view of the Shangri-La area. Both panels are shaded-relief maps created using `ggplot2` and `terra`.

![The final figure](figures/site_map.jpg)

*The final figure. Arrows, place and river names, the globe locator, and zoom lines were added in Adobe Illustrator.*

## Contents

```         
R/
  common.R          shared by both panels: palette, relief renderer, site symbols and
                    their packing, type sizes, map furniture, page fitting, layer export
  map_plateau.R     panel A: the Tibetan Plateau (Copernicus GLO-90)
  map_shangrila.R   panel B: the Shangri-La (Copernicus GLO-30)
data/
  sites.csv         the sites: name, age (ka), coordinates as published, assemblage
assets/
  globe_locator.png
figures/            images used in this README
```

## Running

Install the packages once. WhiteboxTools traces the drainage in panel B:

``` r
install.packages(c("sf", "terra", "tidyterra", "ggplot2", "ggspatial", "ggrepel",
                   "dplyr", "scales", "here", "ragg", "png",
                   "rnaturalearth", "rnaturalearthdata", "whitebox"))
whitebox::install_whitebox()
```

Open `SETP_site_map.Rproj`, or start R in the repository root, and run:

``` r
source("R/map_plateau.R")                     # panel A, quick preview (200 dpi)
PREVIEW <- FALSE; source("R/map_plateau.R")   # panel A, final (600 dpi)
source("R/map_shangrila.R")                   # panel B, final (600 dpi)
```

The first run downloads its data and caches it in `data/cache/` (about 190 MB), which takes a while. Panel A reads the Copernicus GLO-90 tiles over HTTP, and GDAL warps them straight onto a 375 m grid. Panel B reads a few GLO-30 tiles, and the Natural Earth rivers and lakes are downloaded once. After that, each script takes about a minute or two.

Output, in `output/maps/`:

| File | Content |
|------------------------------------|------------------------------------|
| `map_plateau_sites_preview.png` | panel A, preview |
| `map_plateau_sites.png` / `.pdf` | panel A, complete |
| `map_inset_shangrila.png` / `.pdf` | panel B, complete |
| `map_<panel>_layer_base` / `_points` / `_labels` (`.png` / `.pdf`) | each panel as three registered layers (see below) |
| `map_plateau_legend.png`, `_north_arrow.png`, `_scalebar.png` | panel A's furniture as trimmed, transparent PNGs |

## Style notes

![Script output](figures/script_output.jpg)

*The two panels as the scripts write them, placed edge to edge at 100 % (180 × 75 mm), before any hand editing.*

### Colours

| Role | Hex |
|------------------------------------|------------------------------------|
| Hypsometric ramp, low → high | `#7E8E74` `#93A184` `#A9B195` `#BFBCA4` `#D1C9B3` `#DCD4C1` `#E6DECB` |
| Paper | `#E9E4D8` |
| Water | `#86A6BB` |
| Text | `#332F29` |
| Frame | `#202124` |

Each site is drawn as a black-ringed circle, and the fill shows only its assemblage class:

| Class                        | Fill      |
|------------------------------|-----------|
| Handaxe site                 | `#D55E00` |
| Denisovan site               | `#AA3377` |
| Middle Paleolithic site      | `#0072B2` |
| Blade site                   | `#F0E442` |
| Microblade site              | `#7B4B2A` |
| Other Upper Paleolithic site | `#009E73` |

## Data

- **Elevation.** Copernicus DEM GLO-90 (panel A) and GLO-30 (panel B), read from the AWS Open Data buckets. *Produced using Copernicus WorldDEM-30 and WorldDEM-90 © DLR e.V. 2010–2014 and © Airbus Defence and Space GmbH 2014–2018 provided under COPERNICUS by the European Union and ESA; all rights reserved.*
- **Rivers, lakes and land.** [Natural Earth](https://www.naturalearthdata.com/) (public domain). The drainage in panel B is traced from GLO-30 with [WhiteboxTools](https://www.whiteboxgeo.com/).

## Adapting it

- **Another region:** change `frame_ll` and `map_crs` at the top of the panel script. Check `hyps_knots` in `common.R` if the elevation range is very different.
- **Other sites:** edit `data/sites.csv`, and change `site_types` in `common.R` for different classes or colours.
- **Another figure size:** change `comp_width_mm`, `comp_height_mm` and the `pt_*` type sizes in `common.R`.
- **What is drawn:** toggles near the top of `map_plateau.R` control the labels, rivers, lakes, plateau outline and on-map legend, north arrow and scale bar.

## License

- The code is released under the [MIT License](LICENSE).

- The Copernicus DEM and Natural Earth data remain under their own terms.
