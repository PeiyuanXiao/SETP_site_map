## map_shangrila.R — panel B: the Shangri-La sites on shaded relief (Copernicus
## GLO-30 on a 20 m UTM 47N grid) with channels traced from the DEM. Rendered
## at its printed size (~79 mm wide), 600 dpi PNG + PDF and layers.

source(here::here("R", "common.R"))

fr <- make_frame(c(xmin = 99.62, xmax = 99.86, ymin = 27.69, ymax = 27.91), utm47)
## a wider frame for solving the drainage
fh <- make_frame(c(xmin = 99.50, xmax = 99.98, ymin = 27.58, ymax = 28.02), utm47)

dem_res    <- 20                  # m
z_exag     <- 1.8
grat_step  <- 0.05
river_km2  <- 20                  # smallest catchment drawn
river_smooth <- 9                 # moving-average window along each channel
river_lw   <- c(0.12, 0.5)        # mm, as panel A's rivers
scale_hint <- 0.22
m_per_mm   <- approx_m_per_mm(fr)

## ---- local knots ---------------------------------------------------------
## The ground here spans only 3250-4480 m, so panel A's colours are laid on
## local knots: a colour here is a different elevation than in panel A.
local_knots    <- c(3250, 3300, 3400, 3550, 3750, 3950, 4450)
stopifnot(length(local_knots) == length(hyps_cols))
show_elev_legend <- FALSE
elev_breaks    <- c(3300, 3600, 3900, 4200)

## ---- layers --------------------------------------------------------------
dem_h  <- get_dem(fh, z = NA, res = dem_res, tag = "shangrila_cop30", source = "cop30")
dem    <- terra::crop(dem_h, terra::ext(fr$bbx))
shaded <- shade_relief(dem, z_exag, knots = local_knots)

rivers <- dem_channels(dem_h, "shangrila_cop30", river_km2, smooth = river_smooth) |>
  st_intersection(fr$poly)
message(sprintf("shangrila: %d channels (>= %g km2); elevation %.0f-%.0f m",
                nrow(rivers), river_km2,
                terra::minmax(dem)[1], terra::minmax(dem)[2]))

ss <- sites[lengths(st_intersects(st_transform(sites, utm47), fr$poly)) > 0, ]

## ---- build map -----------------------------------------------------------
sxy <- site_xy(ss, utm47, m_per_mm)
p <- ggplot()

## optional elevation colourbar, from a coarse DEM hidden under the relief
if (show_elev_legend) {
  p <- p +
    tidyterra::geom_spatraster(data = terra::aggregate(dem, 8, fun = "mean", na.rm = TRUE),
                               maxcell = 5e5) +
    scale_fill_gradientn(
      colours = blend_to(hyps_cols, paper_col, hyps_strength),
      values = scales::rescale(local_knots), limits = range(local_knots),
      breaks = elev_breaks, oob = scales::squish, na.value = NA,
      name = "Elevation (m)",
      guide = guide_colourbar(
        theme = theme(legend.key.width  = unit(2.2, "mm"),
                      legend.key.height = unit(14, "mm"),
                      legend.ticks = element_blank(),
                      legend.frame = element_rect(colour = "grey45", linewidth = 0.2)))) +
    ggnewscale::new_scale_fill()
}

base_layers <- list(
  tidyterra::geom_spatraster_rgb(data = shaded, maxcell = 2e7),
  geom_sf(data = rivers, aes(linewidth = w), colour = water_col, alpha = 0.9,
          lineend = "round"),
  scale_linewidth_continuous(range = river_lw, guide = "none"),
  map_furniture(width_hint = scale_hint))

## coord, scales and theme, shared by the sheet and its layers; latitudes on
## the right, away from the gutter
sheet_frame <- list(map_coord(fr, grat_step, lat_side = "right"), labs(x = NULL, y = NULL),
                    theme_sheet(gutter_side = "left"))

p <- p + base_layers +
  site_symbols(sxy, legend = FALSE) +
  site_labels(sxy) +
  sheet_frame +
  theme(
    legend.position        = if (show_elev_legend) "inside" else "none",
    legend.position.inside = c(0.985, 0.02),
    legend.justification   = c(1, 0),
    legend.background = element_rect(fill = grDevices::adjustcolor("white", alpha.f = 0.8),
                                     colour = NA),
    legend.margin     = margin(2.5, 3, 2.5, 3),
    legend.title      = element_text(size = pt_legend_title),
    legend.text       = element_text(size = pt_legend))

## ---- export --------------------------------------------------------------
fit <- fit_sheet(p, fr)
save_sheet(fit, file.path(output_dir, "map_inset_shangrila.png"))
save_sheet(fit, file.path(output_dir, "map_inset_shangrila.pdf"))

export_layers(base_layers, sxy, sheet_frame, fr, file.path(output_dir, "map_shangrila_layer"))
