## common.R — shared by map_plateau.R (panel A) and map_shangrila.R (panel B):
## packages, paths, sites, palette, relief renderer, symbols, type sizes,
## furniture and export. Sourced by both scripts; not run on its own.

library(sf)
library(dplyr)
library(ggplot2)
library(terra)
library(tidyterra)
library(ggspatial)
sf::sf_use_s2(FALSE)
`%||%` <- function(a, b) if (is.null(a)) b else a

proj_dir   <- here::here()
output_dir <- if (exists("OUTPUT_DIR")) OUTPUT_DIR else file.path(proj_dir, "output", "maps")
cache_dir  <- file.path(proj_dir, "data", "cache", "plateau")
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)
dir.create(cache_dir,  showWarnings = FALSE, recursive = TRUE)

site_csv   <- file.path(proj_dir, "data", "sites.csv")

utm47 <- "EPSG:32647"             

## ---- relief --------------------------------------------------------------
sun_angle     <- 35               
sun_dirs      <- c(300, 337, 15)  
relief_hi     <- 0.42             
relief_lo     <- 0.38            
warm_gain     <- 0.10
cool_gain     <- 0.20
hyps_strength <- 0.72             

## ---- palette -------------------------------------------------------------
hyps_cols  <- c("#7E8E74", "#93A184", "#A9B195", "#BFBCA4",
                "#D1C9B3", "#DCD4C1", "#E6DECB")
hyps_knots <- c(0, 600, 1500, 2600, 3800, 4800, 6200)
paper_col  <- "#E9E4D8"
water_col  <- "#86A6BB"
label_col  <- "#332F29"
frame_col  <- "#202124"

## ---- type sizes (pt), shared by both panels ------------------------------
pt_label        <- 5.5
pt_axis         <- 5.5
pt_scale        <- 5.5
pt_north        <- 6.5
pt_legend       <- 5.5
pt_legend_title <- 6
label_size  <- pt_label / ggplot2::.pt
furniture_k <- 0.6

## ---- composite geometry --------------------------------------------------
comp_width_mm  <- 180
comp_gutter_mm <- 4
comp_height_mm <- 75.17

## ---- site classes --------------------------------------------------------
site_types <- data.frame(
  assemblage = c("Handaxe technology", "Denisovan", "Middle Paleolithic",
                 "Blade technology", "Microblade technology",
                 "Non-blade/microblade Upper Paleolithic"),
  type       = c("Handaxe site", "Denisovan site", "Middle Paleolithic site",
                 "Blade site", "Microblade site", "Other Upper Paleolithic site"),
  fill       = c("#D55E00", "#AA3377", "#0072B2", "#F0E442", "#7B4B2A", "#009E73"))
sym_size   <- if (exists("SYM_SIZE")) SYM_SIZE else 2.1   # geom_point size
sym_stroke <- 0.45
sym_diam_mm <- 2.05 * (sym_size * ggplot2::.pt + sym_stroke * ggplot2::.stroke / 2) /
                      (2.1      * ggplot2::.pt + sym_stroke * ggplot2::.stroke / 2)
pack_spacing <- if (exists("PACK_SPACING")) PACK_SPACING else 0.6

## ---- sites ---------------------------------------------------------------
parse_coord <- function(x) vapply(as.character(x), function(s) {
  n <- as.numeric(regmatches(s, gregexpr("[0-9]+(\\.[0-9]+)?", s))[[1]])
  sum(n / 60^(seq_along(n) - 1))
}, numeric(1), USE.NAMES = FALSE)

sites <- utils::read.csv(site_csv, colClasses = "character", check.names = FALSE,
                         fileEncoding = "UTF-8-BOM")
names(sites) <- trimws(names(sites))
sites <- sites |>
  transmute(site = trimws(ID), assemblage = trimws(Assemblage),
            lat = parse_coord(N), lon = parse_coord(E)) |>
  left_join(site_types[c("assemblage", "type")], by = "assemblage")
if (anyNA(sites$type)) stop("Assemblage not in site_types for: ",
                            paste(sites$site[is.na(sites$type)], collapse = ", "))
sites$type <- factor(sites$type, levels = site_types$type)
sites <- st_as_sf(sites, coords = c("lon", "lat"), crs = 4326, remove = FALSE)

## ---- frames and data -----------------------------------------------------
make_frame <- function(frame_ll, crs, pad = 0.05) {
  n  <- 200
  xs <- seq(frame_ll[["xmin"]], frame_ll[["xmax"]], length.out = n)
  ys <- seq(frame_ll[["ymin"]], frame_ll[["ymax"]], length.out = n)
  ring <- cbind(c(xs, rep(frame_ll[["xmax"]], n), rev(xs), rep(frame_ll[["xmin"]], n)),
                c(rep(frame_ll[["ymin"]], n), ys, rep(frame_ll[["ymax"]], n), rev(ys)))
  bb <- st_polygon(list(rbind(ring, ring[1, ]))) |> st_sfc(crs = 4326) |>
    st_transform(crs) |> st_bbox()
  poly <- st_as_sfc(bb)
  dl <- st_segmentize(poly, diff(bb[c("xmin", "xmax")]) / 100) |>
    st_transform(4326) |> st_bbox()
  list(frame_ll = frame_ll, crs = crs, poly = poly,
       bbx = as.numeric(bb[c("xmin", "xmax", "ymin", "ymax")]),
       dl_bb = dl + c(-pad, -pad, pad, pad))
}

## Copernicus GLO-30 for a lon/lat box, read window-only from the AWS tiles
cop30_mosaic <- function(bb) {
  url <- function(lat, lon) sprintf(paste0(
    "/vsicurl/https://copernicus-dem-30m.s3.amazonaws.com/",
    "Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM/",
    "Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM.tif"),
    ifelse(lat < 0, "S", "N"), abs(lat), ifelse(lon < 0, "W", "E"), abs(lon),
    ifelse(lat < 0, "S", "N"), abs(lat), ifelse(lon < 0, "W", "E"), abs(lon))
  e <- terra::ext(bb[["xmin"]], bb[["xmax"]], bb[["ymin"]], bb[["ymax"]])
  g <- expand.grid(lat = floor(bb[["ymin"]]):floor(bb[["ymax"]]),
                   lon = floor(bb[["xmin"]]):floor(bb[["xmax"]]))
  tiles <- lapply(seq_len(nrow(g)), function(i)
    terra::crop(terra::rast(url(g$lat[i], g$lon[i])), e))
  if (length(tiles) == 1) tiles[[1]] else do.call(terra::merge, tiles)
}

## Copernicus GLO-90 for a frame, warped by GDAL straight onto its projected
cop90_warp <- function(fr, res, out) {
  lst <- file.path(cache_dir, "cop90_tileList.txt")
  if (!file.exists(lst))
    utils::download.file("https://copernicus-dem-90m.s3.amazonaws.com/tileList.txt",
                         lst, quiet = TRUE, mode = "wb")
  tiles <- trimws(readLines(lst))
  m   <- regmatches(tiles, regexec("_([NS])(\\d{2})_00_([EW])(\\d{3})_00_DEM$", tiles))
  ok  <- lengths(m) == 5
  lat <- ifelse(vapply(m[ok], `[`, "", 2) == "S", -1, 1) * as.numeric(vapply(m[ok], `[`, "", 3))
  lon <- ifelse(vapply(m[ok], `[`, "", 4) == "W", -1, 1) * as.numeric(vapply(m[ok], `[`, "", 5))
  bb  <- fr$dl_bb
  use <- tiles[ok][lat >= floor(bb[["ymin"]]) & lat <= floor(bb[["ymax"]]) &
                   lon >= floor(bb[["xmin"]]) & lon <= floor(bb[["xmax"]])]
  message(sprintf("Warping %d Copernicus GLO-90 tiles to a %g m grid ...", length(use), res))
  Sys.setenv(GDAL_DISABLE_READDIR_ON_OPEN = "EMPTY_DIR",
             CPL_VSIL_CURL_ALLOWED_EXTENSIONS = ".tif",
             GDAL_HTTP_MAX_RETRY = "5", GDAL_HTTP_RETRY_DELAY = "3")
  urls <- sprintf("/vsicurl/https://copernicus-dem-90m.s3.amazonaws.com/%s/%s.tif", use, use)
  sf::gdal_utils("warp", urls, out, quiet = TRUE, options = c(
    "-t_srs", fr$crs,
    "-te", fr$bbx[1], fr$bbx[3], fr$bbx[2], fr$bbx[4], "-tr", res, res,
    "-r", "average", "-multi", "-wo", "NUM_THREADS=ALL_CPUS",
    "-co", "COMPRESS=DEFLATE", "-co", "TILED=YES", "-overwrite"))
}

## DEM for a frame on a `res` m grid in its CRS, from elevatr (zoom `z`),
## GLO-30 or GLO-90. Cached under `tag`; rebuilt when the frame changes.
get_dem <- function(fr, z, res, tag, source = c("elevatr", "cop30", "cop90")) {
  source <- match.arg(source)
  key    <- list(frame_ll = fr$frame_ll, crs = fr$crs, z = z, res = res)
  ll_tif <- file.path(cache_dir, if (source == "cop30")
    sprintf("dem_%s_ll_cop30.tif", tag) else sprintf("dem_%s_ll_z%d.tif", tag, z))
  pj_tif <- file.path(cache_dir, sprintf("dem_%s_%dm.tif", tag, res))
  stale  <- function(f) !file.exists(f) || !file.exists(paste0(f, ".rds")) ||
    !identical(readRDS(paste0(f, ".rds"))$frame_ll, fr$frame_ll)
  if (source == "cop90") {
    if (stale(pj_tif)) {
      cop90_warp(fr, res, pj_tif)
      saveRDS(key, paste0(pj_tif, ".rds"))
    }
    dem <- terra::rast(pj_tif)
    names(dem) <- "elev"
    return(dem)
  }
  if (stale(ll_tif)) {
    if (source == "cop30") {
      message(sprintf("Reading Copernicus GLO-30 (%s) ...", tag))
      d <- cop30_mosaic(fr$dl_bb)
    } else {
      message(sprintf("Downloading DEM via elevatr (%s, z = %d) ...", tag, z))
      d <- elevatr::get_elev_raster(st_as_sf(st_as_sfc(fr$dl_bb)), z = z, clip = "bbox") |>
        terra::rast()
    }
    terra::writeRaster(d, ll_tif, overwrite = TRUE)
    saveRDS(key, paste0(ll_tif, ".rds"))
    unlink(pj_tif)
  }
  if (stale(pj_tif)) {
    message(sprintf("Projecting DEM to the %s grid (%d m) ...", tag, res))
    tmpl <- terra::rast(terra::ext(fr$bbx), resolution = res, crs = fr$crs)
    d <- terra::project(terra::rast(ll_tif), tmpl, method = "bilinear")
    terra::writeRaster(d, pj_tif, overwrite = TRUE)
    saveRDS(key, paste0(pj_tif, ".rds"))
  }
  dem <- terra::rast(pj_tif)
  names(dem) <- "elev"
  dem
}

## Natural Earth 10 m physical layer: cached, projected, clipped to the frame
ne_layer <- function(type, fr) {
  f <- file.path(cache_dir, paste0("ne10_", type, ".gpkg"))
  if (!file.exists(f)) {
    ok <- tryCatch({
      x <- rnaturalearth::ne_download(scale = 10, type = type, category = "physical",
                                      returnclass = "sf")
      x <- st_make_valid(x) |> st_crop(c(xmin = 60, ymin = 15, xmax = 120, ymax = 50))
      st_write(x, f, delete_dsn = TRUE, quiet = TRUE)
      TRUE
    }, error = function(e) { message("  ", type, " download failed: ", conditionMessage(e)); FALSE })
    if (!ok) return(NULL)
  }
  x <- suppressWarnings(st_read(f, quiet = TRUE) |> st_transform(fr$crs) |>
                          st_intersection(fr$poly))
  if (nrow(x) == 0) NULL else x
}

## Channels traced from the DEM with WhiteboxTools, weighted by drainage area;
## `min_km2` is the smallest catchment kept, `smooth` the moving-average window.
## `dem_h` should extend well beyond the map.
dem_channels <- function(dem_h, tag, min_km2, smooth = 0) {
  src  <- terra::sources(dem_h)
  f    <- function(x) file.path(cache_dir, sprintf("_wbt_%s_%s", tag, x))
  f_br <- f("breached.tif"); f_ptr <- f("d8_pointer.tif"); f_acc <- f("d8_accum.tif")
  f_str <- f(sprintf("streams_%gkm2.tif", min_km2))
  f_shp <- f(sprintf("streams_%gkm2.shp", min_km2))
  cell_km2 <- prod(terra::res(dem_h)) / 1e6

  if (!file.exists(f_acc) || file.mtime(f_acc) < file.mtime(src)) {
    message("Solving drainage for ", tag, " ...")
    whitebox::wbt_breach_depressions_least_cost(dem = src, output = f_br,
                                                dist = 100, fill = TRUE)
    whitebox::wbt_d8_pointer(dem = f_br, output = f_ptr)
    whitebox::wbt_d8_flow_accumulation(input = f_br, output = f_acc, out_type = "cells")
    unlink(Sys.glob(f("streams_*")))
  }
  if (!file.exists(f_shp)) {
    whitebox::wbt_extract_streams(flow_accum = f_acc, output = f_str,
                                  threshold = ceiling(min_km2 / cell_km2))
    whitebox::wbt_raster_streams_to_vector(streams = f_str, d8_pntr = f_ptr, output = f_shp)
  }
  if (smooth > 0) {
    f_sm <- f(sprintf("streams_%gkm2_s%d.shp", min_km2, smooth))
    if (!file.exists(f_sm))
      whitebox::wbt_smooth_vectors(input = f_shp, output = f_sm, filter = smooth)
    f_shp <- f_sm
  }

  riv <- st_read(f_shp, quiet = TRUE)
  if (is.na(st_crs(riv))) st_crs(riv) <- st_crs(dem_h)
  riv <- st_transform(riv, utm47)
  acc <- terra::rast(f_acc)
  riv$acc_km2 <- terra::extract(acc, terra::vect(riv), fun = max, na.rm = TRUE)[, 2] * cell_km2
  riv |>
    filter(!is.na(acc_km2), acc_km2 >= min_km2) |>
    mutate(w = log10(acc_km2)) |>
    st_simplify(dTolerance = terra::res(dem_h)[1] * 0.8, preserveTopology = TRUE)
}

## ---- relief shading ------------------------------------------------------
blend_to <- function(cols, to, k) {
  a <- grDevices::col2rgb(cols) / 255; b <- as.numeric(grDevices::col2rgb(to)) / 255
  m <- a * k + b * (1 - k)
  grDevices::rgb(m[1, ], m[2, ], m[3, ])
}

rgb2hsl <- function(r, g, b) {
  mx <- pmax(r, g, b); mn <- pmin(r, g, b); l <- (mx + mn) / 2; d <- mx - mn
  s <- ifelse(d == 0, 0, d / (1 - abs(2 * l - 1)))
  h <- ifelse(d == 0, 0,
       ifelse(mx == r, ((g - b) / d) %% 6,
       ifelse(mx == g, ((b - r) / d) + 2, ((r - g) / d) + 4))) / 6
  list(h = h %% 1, s = s, l = l)
}
hsl2rgb <- function(h, s, l) {
  c <- (1 - abs(2 * l - 1)) * s; hp <- h * 6; x <- c * (1 - abs(hp %% 2 - 1))
  r <- g <- b <- numeric(length(h))
  i <- hp < 1;             r[i] <- c[i]; g[i] <- x[i]
  i <- hp >= 1 & hp < 2;   r[i] <- x[i]; g[i] <- c[i]
  i <- hp >= 2 & hp < 3;   g[i] <- c[i]; b[i] <- x[i]
  i <- hp >= 3 & hp < 4;   g[i] <- x[i]; b[i] <- c[i]
  i <- hp >= 4 & hp < 5;   r[i] <- x[i]; b[i] <- c[i]
  i <- hp >= 5;            r[i] <- c[i]; b[i] <- x[i]
  m <- l - c / 2; list(r = r + m, g = g + m, b = b + m)
}

## multi-azimuth hillshade, optionally averaged down, stretched 2-98 % to 0..1
hillshade01 <- function(dem, z_exag, aggregate = 1, despeckle = TRUE) {
  dem_x  <- dem * z_exag
  slope  <- terra::terrain(dem_x, "slope",  unit = "radians")
  aspect <- terra::terrain(dem_x, "aspect", unit = "radians")
  hl     <- lapply(sun_dirs,
                   function(d) terra::shade(slope, aspect, angle = sun_angle, direction = d))
  hill   <- terra::app(terra::rast(hl), mean)
  if (aggregate > 1) hill <- terra::aggregate(hill, aggregate, fun = "mean", na.rm = TRUE)
  if (despeckle) hill <- terra::focal(hill, w = 3, fun = "mean", na.rm = TRUE)
  hr <- as.numeric(stats::quantile(terra::values(hill, mat = FALSE),
                                   c(0.02, 0.98), na.rm = TRUE))
  (terra::clamp(hill, hr[1], hr[2]) - hr[1]) / (hr[2] - hr[1])
}

## RGB raster (r, g, b) of the shaded relief: the hillshade moves the HSL
shade_relief <- function(dem, z_exag, cols = hyps_cols, knots = hyps_knots,
                         strength = hyps_strength, supersample = 1, despeckle = TRUE,
                         coarse_weight = 0, coarse_exag = z_exag) {
  hill <- hillshade01(dem, z_exag, aggregate = supersample, despeckle = despeckle)
  if (supersample > 1)
    dem <- terra::aggregate(dem, supersample, fun = "mean", na.rm = TRUE)
  if (supersample > 1 && coarse_weight > 0) {
    hill <- coarse_weight * hillshade01(dem, coarse_exag) + (1 - coarse_weight) * hill
    hr   <- as.numeric(stats::quantile(terra::values(hill, mat = FALSE),
                                       c(0.02, 0.98), na.rm = TRUE))
    hill <- (terra::clamp(hill, hr[1], hr[2]) - hr[1]) / (hr[2] - hr[1])
  }

  ev <- terra::values(dem)[, 1]
  u  <- stats::approx(knots, seq(0, 1, length.out = length(knots)),
                      xout = ev, rule = 2)$y
  ok <- !is.na(u)
  base_hex <- rep(NA_character_, length(u))
  base_hex[ok] <- scales::colour_ramp(cols)(u[ok])

  m   <- grDevices::col2rgb(ifelse(is.na(base_hex), "#000000", base_hex)) / 255
  pap <- as.numeric(grDevices::col2rgb(paper_col)) / 255
  m   <- m * strength + pap * (1 - strength)
  hsl <- rgb2hsl(m[1, ], m[2, ], m[3, ])
  hh  <- terra::values(hill)[, 1]; hh[is.na(hh)] <- 0.5
  tt  <- 2 * hh - 1                       # -1 full shadow ... +1 full light
  ## move by a share of the remaining headroom, so nothing clips
  Ln  <- hsl$l + ifelse(tt > 0, relief_hi * tt * (1 - hsl$l), relief_lo * tt * hsl$l)
  Ln  <- pmin(1, pmax(0, Ln))
  o   <- hsl2rgb(hsl$h, hsl$s, Ln)
  w_lit <- pmax(0, tt) * warm_gain
  w_shd <- pmax(0, -tt) * cool_gain
  warm  <- grDevices::col2rgb("#FFF4E2") / 255
  cool  <- grDevices::col2rgb("#4C5A6B") / 255
  keep  <- 1 - w_lit - w_shd
  RR <- (o$r * keep + warm[1] * w_lit + cool[1] * w_shd) * 255
  GG <- (o$g * keep + warm[2] * w_lit + cool[2] * w_shd) * 255
  BB <- (o$b * keep + warm[3] * w_lit + cool[3] * w_shd) * 255
  RR[!ok] <- NA; GG[!ok] <- NA; BB[!ok] <- NA
  shaded <- terra::rast(dem, nlyr = 3)
  terra::values(shaded) <- cbind(RR, GG, BB)
  shaded <- terra::clamp(shaded, 0, 255)
  names(shaded) <- c("r", "g", "b")
  shaded
}

## ---- axes ----------------------------------------------------------------
## degrees on the axes only, no graticule; latitudes on `lat_side`
grat_breaks <- function(fr, step) {
  b <- fr$dl_bb
  list(lon = round(seq(ceiling(b[["xmin"]] / step) * step, b[["xmax"]], by = step), 6),
       lat = round(seq(ceiling(b[["ymin"]] / step) * step, b[["ymax"]], by = step), 6))
}
map_coord <- function(fr, step, lat_side = c("left", "right")) {
  lat_side <- match.arg(lat_side)
  br <- grat_breaks(fr, step)
  list(coord_sf(crs = fr$crs, datum = 4326, xlim = fr$bbx[1:2], ylim = fr$bbx[3:4],
                expand = FALSE, label_axes = setNames(list("E", "N"), c("bottom", lat_side))),
       scale_x_continuous(breaks = br$lon),
       scale_y_continuous(breaks = br$lat, position = lat_side))
}

## ---- sites + labels ------------------------------------------------------
## Sites as X/Y in `crs`. Sites closer than `diam_mm` on the page are packed into
## a hexagonal cluster (centre + six slots) around their true centre, each in
## the slot nearest its true bearing; `m_per_mm` is the panel scale.
site_xy <- function(x, crs, m_per_mm, diam_mm = pack_spacing * (sym_diam_mm + 0.15)) {
  x  <- st_transform(x, crs)
  xy <- st_coordinates(x)[, 1:2, drop = FALSE] / m_per_mm       # page mm
  slots <- rbind(c(0, 0), t(sapply(0:5, function(k) diam_mm * c(cos(k * pi / 3), sin(k * pi / 3)))))
  perms <- function(v, n) if (n == 0) list(integer(0)) else
    unlist(lapply(v, function(i) lapply(perms(setdiff(v, i), n - 1), function(q) c(i, q))),
           recursive = FALSE)
  pack <- function(m) {
    if (length(m) > nrow(slots)) stop("more than 7 symbols overlap in one group")
    c0  <- colMeans(xy[m, , drop = FALSE])
    rel <- sweep(xy[m, , drop = FALSE], 2, c0)
    best <- NULL; cost <- Inf
    for (q in perms(seq_len(nrow(slots)), length(m))) {
      s <- sweep(slots[q, , drop = FALSE], 2, colMeans(slots[q, , drop = FALSE]))
      k <- sum((s - rel)^2)
      if (k < cost - 1e-9) { cost <- k; best <- s }   # ties keep the first layout
    }
    sweep(best, 2, c0, "+")
  }
  linkage <- function(p, h) if (nrow(p) < 2) 1L else cutree(hclust(dist(p), "single"), h = h)
  groups <- linkage(xy, diam_mm)
  ## groups that come to touch once packed are merged and packed again
  for (iter in 1:10) {
    p <- xy
    for (g in unique(groups)) {
      m <- which(groups == g)
      if (length(m) > 1) p[m, ] <- pack(m)
    }
    touch  <- linkage(p, 0.95 * diam_mm)
    merged <- groups
    for (t in unique(touch)) {
      gs <- unique(merged[touch == t])
      if (length(gs) > 1) merged[merged %in% gs] <- min(gs)
    }
    if (identical(merged, groups)) break
    groups <- merged
  }
  shift <- sqrt(rowSums((p - xy)^2))
  if (any(shift > 0.01))
    message(sprintf("displaced for legibility: %s",
                    paste(sprintf("%s %.1f mm", x$site[shift > 0.01], shift[shift > 0.01]),
                          collapse = ", ")))
  st_drop_geometry(x) |> mutate(X = p[, 1] * m_per_mm, Y = p[, 2] * m_per_mm)
}

## drawn in reverse legend order, so the first-listed class lies on top
site_symbols <- function(d, legend = TRUE)
  list(
    geom_point(data = arrange(d, desc(type)), aes(X, Y, fill = type), shape = 21,
               colour = "black", size = sym_size, stroke = sym_stroke),
    scale_fill_manual(
      values = setNames(site_types$fill, site_types$type),
      breaks = site_types$type, limits = site_types$type, name = NULL,
      guide = if (legend) "legend" else "none"))

## `d` comes from site_xy(); `...` overrides the ggrepel settings
site_labels <- function(d, ...) {
  args <- modifyList(list(
    data = d, mapping = aes(X, Y, label = site),
    colour = label_col, size = label_size, fontface = "bold",
    bg.color = grDevices::adjustcolor("white", alpha.f = 0.8), bg.r = 0.13,
    seed = 42, max.overlaps = Inf, force = 6, force_pull = 0.5,
    point.size = sym_size * 1.2, box.padding = 0.3, point.padding = 0.15,
    min.segment.length = 0,
    segment.color = "grey35", segment.size = 0.22), list(...))
  do.call(ggrepel::geom_text_repel, args)
}

## ---- furniture -----------------------------------------------------------
## geometry scales with `k`; type is set in points
north_needle <- function(k = furniture_k) grid::gTree(children = grid::gList(
  grid::linesGrob(
    x = grid::unit(c(0.5, 0.5), "npc"), y = grid::unit(c(0.0, 0.66), "npc"),
    arrow = grid::arrow(type = "closed", angle = 20, length = grid::unit(3.2 * k, "mm")),
    gp = grid::gpar(col = label_col, fill = label_col, lwd = 2.0 * k, lineend = "butt")),
  grid::textGrob("N", x = 0.5, y = 0.90,
                 gp = grid::gpar(col = label_col, fontsize = pt_north, fontface = "bold"))))

## scale bar and north arrow on the panel; at the same location, the needle
## stands above the bar
map_furniture <- function(width_hint, scale_loc = "bl", arrow_loc = "tl", k = furniture_k,
                          scale = TRUE, arrow = TRUE) {
  arrow_pad_y <- if (arrow_loc == scale_loc) (0.45 + 0.26) * k + 0.25 else 0.35 * k  # cm
  list(if (scale) annotation_scale(
         location = scale_loc, style = "ticks", width_hint = width_hint,
         height = unit(0.26 * k, "cm"), line_width = 1.5 * k, tick_height = 0.8,
         text_cex = pt_scale / 12, text_col = label_col, line_col = label_col,
         text_face = "bold", text_family = "",
         pad_x = unit(0.45 * k, "cm"), pad_y = unit(0.45 * k, "cm")),
       if (arrow) annotation_north_arrow(
         location = arrow_loc, which_north = "true",
         height = unit(1.2 * k, "cm"), width = unit(0.7 * k, "cm"),
         pad_x = unit(0.45 * k, "cm"), pad_y = unit(arrow_pad_y, "cm"),
         style = north_needle(k)))
}

## ---- furniture as separate files -----------------------------------------
## a grob on a transparent 600 dpi canvas, trimmed to its ink
save_element <- function(grob, file, canvas_mm = c(150, 80), pad_mm = 0.3, dpi = 600) {
  tmp <- tempfile(fileext = ".png")
  ragg::agg_png(tmp, width = canvas_mm[1], height = canvas_mm[2], units = "mm",
                res = dpi, background = "transparent")
  grid::grid.draw(grob)
  grDevices::dev.off()
  img <- png::readPNG(tmp)
  unlink(tmp)
  ink <- img[, , 4] > 0
  pad <- round(pad_mm / 25.4 * dpi)
  r <- pmin(pmax(range(which(rowSums(ink) > 0)) + c(-pad, pad), 1), nrow(ink))
  c <- pmin(pmax(range(which(colSums(ink) > 0)) + c(-pad, pad), 1), ncol(ink))
  png::writePNG(img[r[1]:r[2], c[1]:c[2], ], file, dpi = dpi)
  message(sprintf("-> %s  (%.1f x %.1f mm)", file, (diff(c) + 1) / dpi * 25.4,
                  (diff(r) + 1) / dpi * 25.4))
}

## the plot's own legend, as it would sit on the sheet
legend_grob <- function(p) {
  g <- ggplotGrob(p)
  g$grobs[[which(g$layout$name == "guide-box-inside")]]
}

needle_grob <- function(k = furniture_k)
  grid::grobTree(north_needle(k), vp = grid::viewport(
    width = unit(0.7 * k, "cm"), height = unit(1.2 * k, "cm")))

## the scale bar as annotation_scale() computes it (ggspatial internals), true
## to scale at the printed panel width `panel_w_mm`
scalebar_grob <- function(fr, panel_w_mm, width_hint, k = furniture_k) {
  params <- ggspatial:::scalebar_params(
    sf_bbox = setNames(fr$bbx, c("xmin", "xmax", "ymin", "ymax")),
    widthhint = width_hint, unitcategory = "metric", sf_crs = sf::st_crs(fr$crs))
  grid::grobTree(
    ggspatial:::scalebar_grobs(
      params, style = "ticks", location = "bl",
      line_width = 1.5 * k, line_col = label_col, height = unit(0.26 * k, "cm"),
      pad_x = unit(2, "mm"), pad_y = unit(2, "mm"), tick_height = 0.8,
      text_cex = pt_scale / 12, text_col = label_col, text_face = "bold", text_family = ""),
    vp = grid::viewport(x = 0, y = 0, just = c(0, 0),
                        width = unit(panel_w_mm, "mm"), height = unit(20, "mm")))
}

## the side facing the other panel gets half the gutter as its margin
theme_sheet <- function(gutter_side = c("right", "left"), axis_size = pt_axis) {
  gutter_side <- match.arg(gutter_side)
  m <- c(t = 1.5, r = 1.2, b = 1.2, l = 1.2)                       # mm
  m[[substr(gutter_side, 1, 1)]] <- comp_gutter_mm / 2
  theme_minimal(base_size = 9) +
  theme(
    panel.border      = element_rect(color = frame_col, fill = NA, linewidth = 0.5),
    panel.grid        = element_blank(),
    panel.background  = element_rect(color = NA, fill = "white"),
    plot.background   = element_rect(color = NA, fill = "white"),
    axis.ticks        = element_line(color = frame_col, linewidth = 0.3),
    axis.ticks.length = unit(2, "pt"),
    axis.text         = element_text(color = "#303238", size = axis_size),
    legend.position   = "none",
    plot.margin       = margin(m[["t"]], m[["r"]], m[["b"]], m[["l"]], unit = "mm"))
}

## ---- page fit + export ---------------------------------------------------
## Fit a plot to `height_mm`: everything outside the panel is measured with the
## device's font metrics, the panel takes the rest, and the width follows.
fit_sheet <- function(p, fr, height_mm = comp_height_mm) {
  g   <- ggplotGrob(p)
  pan <- g$layout[grepl("^panel", g$layout$name), ]
  tmp <- tempfile(fileext = ".png")
  ragg::agg_png(tmp, width = 100, height = 100, units = "mm", res = 72)
  on.exit({ grDevices::dev.off(); unlink(tmp) })
  fixed_h <- sum(grid::convertHeight(g$heights[-pan$t], "mm", valueOnly = TRUE))
  fixed_w <- sum(grid::convertWidth(g$widths[-pan$l], "mm", valueOnly = TRUE))
  ph <- height_mm - fixed_h
  pw <- ph * diff(fr$bbx[1:2]) / diff(fr$bbx[3:4])
  g$heights[pan$t] <- grid::unit(ph, "mm")
  g$widths[pan$l]  <- grid::unit(pw, "mm")
  list(grob = g, width = fixed_w + pw, height = height_mm, panel = c(w = pw, h = ph))
}

save_sheet <- function(fit, file, dpi = 600, bg = "white") {
  ggsave(file, fit$grob, width = fit$width, height = fit$height, units = "mm", dpi = dpi,
         device = if (grepl("\\.pdf$", file)) cairo_pdf else ragg::agg_png, bg = bg)
  message(sprintf("-> %s  (%.1f x %.1f mm; panel %.1f x %.1f mm)", file, fit$width,
                  fit$height, fit$panel[["w"]], fit$panel[["h"]]))
}

## ---- layers for Illustrator ----------------------------------------------
## <stem>_base (relief, water, axes, frame), <stem>_points and <stem>_labels
## (transparent; names without halo or leader lines), all on the same page, so
## they register when placed at (0, 0) at 100 %. PNG and PDF each.
overlay_theme <- function()
  theme(panel.background = element_blank(), plot.background = element_blank(),
        panel.border = element_rect(colour = NA, fill = NA),
        axis.text = element_text(colour = NA), axis.ticks = element_line(colour = NA),
        legend.position = "none")

export_layers <- function(base, sxy, frame, fr, stem, dpi = 600) {
  sheets <- list(
    base   = ggplot() + base + frame + theme(legend.position = "none"),
    points = ggplot() + site_symbols(sxy, legend = FALSE) + frame + overlay_theme(),
    labels = ggplot() +
      site_labels(sxy, bg.color = NA, bg.r = 0, segment.color = NA, min.segment.length = Inf,
                  force = 1.5, force_pull = 2, box.padding = 0.15) +
      frame + overlay_theme())
  for (nm in names(sheets)) {
    fit <- fit_sheet(sheets[[nm]], fr)
    bg  <- if (nm == "base") "white" else "transparent"
    save_sheet(fit, sprintf("%s_%s.png", stem, nm), dpi = dpi, bg = bg)
    save_sheet(fit, sprintf("%s_%s.pdf", stem, nm), bg = bg)
  }
}

## panel scale before the plot exists: page height less ~6 mm of margins and axes
approx_m_per_mm <- function(fr, height_mm = comp_height_mm)
  diff(fr$bbx[3:4]) / (height_mm - 6)
