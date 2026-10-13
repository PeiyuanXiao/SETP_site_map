## map_plateau.R — panel A: the sites on the central and eastern Tibetan Plateau
## over shaded relief (Copernicus GLO-90, Natural Earth rivers and lakes), with
## no political boundaries. Rendered at its printed size (~101 mm wide).
##   PREVIEW <- TRUE   quick 200 dpi PNG
##   PREVIEW <- FALSE  600 dpi PNG + PDF, and the layers for Illustrator

source(here::here("R", "common.R"))

PREVIEW <- if (exists("PREVIEW", inherits = FALSE)) PREVIEW else TRUE

## ---- display toggles -----------------------------------------------------
show_site_labels  <- TRUE
show_rivers       <- TRUE
show_lakes        <- TRUE
show_tp_line      <- FALSE   # plateau outline: data/DBATP/, not included (see README)
## legend, north arrow and scale bar are placed by hand: written as separate PNGs
show_legend       <- FALSE
show_north_arrow  <- FALSE
show_scale_bar    <- FALSE
export_furniture  <- TRUE
scale_width_hint  <- 0.18      # -> a 400 km bar
fade_outside      <- FALSE     # lighten the ground outside the plateau outline
fade_alpha        <- 0.22
tp_col            <- "#3A332B"
tp_boundary_pattern <- "(?i)(tpboundary|tp_boundary|plateau|dbatp|qzgy).*\\.(shp|gpkg|geojson)$"

## ---- frame + projection --------------------------------------------------
## Albers equal-area conic centred on 96 E
frame_ll <- c(xmin = 84.0, xmax = 109.0, ymin = 22.5, ymax = 39.5)
map_crs  <- "+proj=aea +lat_0=0 +lon_0=96 +lat_1=27 +lat_2=37 +datum=WGS84 +units=m +no_defs"
fr <- make_frame(frame_ll, map_crs, pad = 1)

dem_res     <- 375                          # m, the grid the relief is shaded on
supersample <- 3                            # averaged to ~1.1 km, one pixel at 600 dpi
preview_dpi <- if (exists("PREVIEW_DPI")) PREVIEW_DPI else 200
z_exag      <- 2.0
grat_step   <- 5

m_per_mm <- approx_m_per_mm(fr)

## ---- layers --------------------------------------------------------------
dem <- get_dem(fr, z = NA, res = dem_res, tag = "plateau_cop90", source = "cop90")
if (PREVIEW) dem <- terra::aggregate(dem, 2, fun = "mean", na.rm = TRUE)
## half the shading from the fine grid (detail), half from the averaged grid
## (the broad modelling of the ranges)
shaded <- shade_relief(dem, z_exag, supersample = supersample, despeckle = FALSE,
                       coarse_weight = 0.5, coarse_exag = 3)

land <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") |>
  st_make_valid() |> st_crop(fr$dl_bb) |> st_union() |> st_transform(map_crs)
ocean <- st_difference(fr$poly, land)
if (length(ocean) && as.numeric(sum(st_area(ocean))) < 1) ocean <- NULL

rivers <- if (show_rivers) ne_layer("rivers_lake_centerlines", fr) else NULL
lakes  <- if (show_lakes)  ne_layer("lakes", fr) else NULL
if (!is.null(rivers)) rivers$w <- 10 - pmin(as.numeric(rivers$scalerank), 9)

tp_line <- outside <- NULL
if (show_tp_line || fade_outside) {
  tp_file <- list.files(file.path(proj_dir, "data"), pattern = tp_boundary_pattern,
                        recursive = TRUE, full.names = TRUE)[1]
  if (is.na(tp_file)) stop("No plateau boundary file under data/.")
  message("Plateau outline: ", tp_file)
  tp <- st_read(tp_file, quiet = TRUE) |> st_make_valid() |> st_union() |>
    st_transform(map_crs)
  tp_is_line <- all(st_geometry_type(tp) %in% c("LINESTRING", "MULTILINESTRING"))
  tp_line <- (if (tp_is_line) tp else st_cast(st_boundary(tp), "MULTILINESTRING")) |>
    st_intersection(fr$poly)
  if (fade_outside && !tp_is_line) outside <- st_difference(fr$poly, tp)
}

## ---- build map -----------------------------------------------------------
sxy <- site_xy(sites, map_crs, m_per_mm)

base_layers <- list(
  tidyterra::geom_spatraster_rgb(data = shaded, maxcell = 2e7),
  if (!is.null(outside)) geom_sf(data = outside, fill = "white", colour = NA,
                                alpha = fade_alpha),
  if (!is.null(ocean)) geom_sf(data = ocean, fill = water_col, colour = NA),
  if (!is.null(lakes)) geom_sf(data = lakes, fill = water_col, colour = NA, alpha = 0.95),
  if (!is.null(rivers))
    list(geom_sf(data = rivers, aes(linewidth = w), colour = water_col,
                 alpha = 0.9, lineend = "round"),
         scale_linewidth_continuous(range = c(0.12, 0.5), guide = "none")),
  ## outline over a pale halo
  if (!is.null(tp_line))
    list(geom_sf(data = tp_line, colour = grDevices::adjustcolor("white", alpha.f = 0.55),
                 linewidth = 1.0, lineend = "round"),
         geom_sf(data = tp_line, colour = tp_col, linewidth = 0.42, lineend = "round")),
  map_furniture(width_hint = scale_width_hint, scale_loc = "bl", arrow_loc = "bl",
                scale = show_scale_bar, arrow = show_north_arrow))

## coord, scales and theme, shared by the sheet and its layers
sheet_frame <- list(map_coord(fr, grat_step), labs(x = NULL, y = NULL),
                    theme_sheet(gutter_side = "right"))

p <- ggplot() + base_layers + site_symbols(sxy)

if (show_site_labels)
  p <- p + site_labels(sxy)

p <- p +
  sheet_frame +
  theme(
    legend.position        = "inside",
    legend.position.inside = c(0.012, 0.985),
    legend.justification   = c(0, 1),
    legend.background = element_rect(
      fill = grDevices::adjustcolor("white", alpha.f = 0.8), colour = NA),
    legend.margin     = margin(2.5, 4, 2.5, 3),
    legend.text       = element_text(size = pt_legend, face = "bold", margin = margin(l = 2)),
    legend.key        = element_blank(),
    legend.key.size   = unit(7, "pt"),
    legend.key.spacing.y = unit(0.3, "pt"))

## the legend is taken from the finished plot, then (by default) off the sheet
legend_on_sheet <- legend_grob(p)
if (!show_legend) p <- p + theme(legend.position = "none")

## ---- export --------------------------------------------------------------
fit      <- fit_sheet(p, fr)
map_stem <- file.path(output_dir, "map_plateau_sites")

if (PREVIEW) {
  save_sheet(fit, paste0(map_stem, "_preview.png"), dpi = preview_dpi)
} else {
  save_sheet(fit, paste0(map_stem, ".png"))
  save_sheet(fit, paste0(map_stem, ".pdf"))
}

if (!PREVIEW) export_layers(base_layers, sxy, sheet_frame, fr,
                            file.path(output_dir, "map_plateau_layer"))

## legend, north arrow and scale bar (true to scale at the printed panel width)
if (export_furniture) {
  furn_stem <- file.path(output_dir, "map_plateau_")
  save_element(legend_on_sheet, paste0(furn_stem, "legend.png"))
  save_element(needle_grob(), paste0(furn_stem, "north_arrow.png"))
  save_element(scalebar_grob(fr, fit$panel[["w"]], scale_width_hint),
               paste0(furn_stem, "scalebar.png"))
}
