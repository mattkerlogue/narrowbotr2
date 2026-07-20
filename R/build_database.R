# setup ----

# helper function to extract coordinates as a tibble
.tbl_coords <- function(x) {
  sf::st_coordinates(x) |>
    tibble::as_tibble()
}

# add coordinates as separate columns from a tibble with sf geometry
add_coords <- function(df) {
  coords <- purrr::map(df$geometry, .tbl_coords) |>
    purrr::list_rbind() |>
    dplyr::rename(lat = Y, long = X)
  df |>
    dplyr::bind_cols(coords)
}

# get the wales boundaries
wales_sf <- readr::read_rds("data/wales_sf.RDS")

# get the list of CRT feeds
feeds <- readr::read_csv("data/feeds.csv")

# points ----

# get the geojson for each feed
feed_points <- feeds |>
  dplyr::filter(geo_type == "point") |>
  dplyr::mutate(point = purrr::map(.x = feed_url, .f = ~ sf::read_sf(.x))) |>
  dplyr::select(feature_type, point)

# unnest the point data
points_raw <- feed_points |>
  tidyr::unnest(point)

# readr::write_rds(points_raw, "data/.points_raw.RDS")
# points_raw <- readr::read_rds("data/.points_raw.RDS")

# lines to centroids ----

feed_lines <- feeds |>
  dplyr::filter(feature_type == "canal_km") |>
  dplyr::mutate(line = purrr::map(.x = feed_url, .f = ~ sf::read_sf(.x))) |>
  dplyr::select(feature_type, line)
# there are three `feature_type` with `geo_type == "line"`:
#   - the "canal_nav" `feature_type` is a collection of all line segments
#     associated with a specific waterway, e.g. all segments of the Ashby canal
#   - the "canal_km" `feature_type` is a collection of line segments
#     representing the centreline of all waterways split into individual single
#     kilometer lengths
#   - "tunnel" `feature_type` is a collection of line segments representing a
#     straight line between two tunnel portals
# only "canal_km" is used since the centroids of the "canal_nav" will represent
# the centroid of an entire waterway, which may not be located near any canal.
# while many tunnels are generally straight some are not, moreover since we are
# interested in canal features, photos located near the tunnel centroid are
# likely to be of above ground structures.

lines_raw <- feed_lines |>
  tidyr::unnest(line)

# readr::write_rds(lines_raw, "data/.lines_raw.RDS")
# lines_raw <- readr::read_rds("data/.lines_raw.RDS")

lines_centroids <- lines_raw |>
  sf::st_as_sf() |>
  dplyr::mutate(
    centroid = sf::st_centroid(geometry)
  ) |>
  sf::st_drop_geometry() |>
  dplyr::rename(geometry = centroid) |>
  sf::st_as_sf()

# polygons to centroids ----

# polygons are excluded as embankment and planning buffer duplicate other
# locations.
# docks are excluded as they are subject to the Ordnance Survey INSPIRE licence
# which does not permit re-sharing of data.

# feed_poly <- feeds |>
#   dplyr::filter(feature_type == "dock") |>
#   dplyr::mutate(poly = purrr::map(.x = feed_url, .f = ~ sf::read_sf(.x))) |>
#   dplyr::select(feature_type, poly)
# there are three `feature_type` with `geo_type == "polygon"`:
#   - the "dock" `feature_type` is a collection of polygons representing the
#     shape of docks interacting with the CRT network that are in water,
#     including both those actively in use (e.g. the Sharpness Dock on
#     the Gloucester and Sharpness Canal) or not in use (e.g. Middle Brank Dock
#     in London, next to Canary Wharf tube station)
#   - the "embankment" `feature_type` is a collection of polygons representing
#     areas of earthwork embankments besides sections of a waterway
#   - "planning_buffer" `feature_type` is a collection of polygons representing
#     areas besides waterways and waterway features where the canal and river
#     trust should be consulted in respect of planning applications
# only the "dock" `feature_type` is used since the "embankments" feature type
# likely duplicates locations already included in either point data or the
# "canal_km" data, similarly since the "planning_buffer" is a buffer around
# existing waterways and waterway features it duplicates data already provides
# by the other `feature_type` categories.

# poly_raw <- feed_poly |>
#   tidyr::unnest(poly)

# # readr::write_rds(poly_raw, "data/.poly_raw.RDS")
# # poly_raw <- readr::read_rds("data/.poly_raw.RDS")

# poly_centroids <- poly_raw |>
#   sf::st_as_sf() |>
#   dplyr::mutate(
#     centroid = sf::st_centroid(geometry)
#   ) |>
#   sf::st_drop_geometry() |>
#   dplyr::rename(geometry = centroid) |>
#   sf::st_as_sf()

# combine points

combined_points <- points_raw |>
  dplyr::transmute(
    feature_type,
    location_id = sap_func_loc,
    uid = globalid,
    name = sap_description,
    obj_type_code = sap_object_type,
    waterway = waterway_name,
    width = NA_character_,
    geometry
  ) |>
  dplyr::bind_rows(
    lines_centroids |>
      dplyr::mutate(
        obj_type_code = dplyr::case_when(
          sapnavstatus == "Fully Navigable" ~ "900",
          sapnavstatus == "Partially Navigable" ~ "901",
          sapnavstatus == "Piped" ~ "902",
          sapnavstatus == "Unavailable for Navigation" ~ "903",
          sapnavstatus == "Dry" ~ "904",
          is.na(sapnavstatus) ~ "905"
        ),
        sapwidth = dplyr::if_else(
          sapwidth == "N/A" | sapwidth == "Unknown",
          NA_character_,
          sapwidth
        )
      ) |>
      dplyr::transmute(
        feature_type,
        location_id = functionallocation,
        uid = globalid,
        name = name,
        obj_type_code,
        waterway = name,
        width = sapwidth,
        geometry
      )
    # ,
    # poly_centroids |>
    #   dplyr::transmute(
    #     feature_type,
    #     location_id = SAP_FUNC_LOC,
    #     uid = uuid::UUIDgenerate(n = nrow(poly_raw)),
    #     name = SAP_DESCRIPTION,
    #     obj_type_code = "999",
    #     waterway = NA_character_,
    #     width = NA_character_,
    #     geometry
    #   )
  )

# readr::write_rds(combined_points, "data/.combined_points.RDS")
# combined_points <- readr::read_rds("data/.combined_points.RDS")

# features ----

# there are 32 combinations of `feature_type` (the name of the CRT data feed)
# and `obj_type_code` (an internal CRT code for type of object). there is
# no public documentation for `sap_object_type` (from which `obj_type_code` is
# derived). `feature_types.csv` has been written manually to provide meta data
# about the different types of objects.
#
# there is notable variation in the number of different types of feature,
# there are 2,960 points relating to culverts which while important might not
# be photogenic whereas there is only 1 boat lift and only 30 docks. a weighting
# variable has been manually added to `feature_types.csv` to adjust the
# relative chance of different types of feature being sampled, entities such as
# culverts and weirs have been down-weighted while locks, aqueducts, and
# tunnel portals have been up-weighted. bridges have also been down-weighted
# since they account for 40% of the original points. in the resulting weighting
# schema locks and bridges have around a one-third chance of selection, canal
# lengths, aqueducts and winding holes have a chance of between 5 and 7.5%,
# while other features range have chances ranging from 0.5% to 4%. the anderton
# boat lift now has a 0.5% chance of being selected compared with 0.006% in an
# unweighted sample, while the chance of a culvert being selected has reduced
# from 17.2% to 1.4%.

# code to create base version of `feature_types.csv`
# combined_points |>
#   dplyr::count(feature_type, obj_type_code) |>
#   dplyr::arrange(feature_type, obj_type_code) |>
#   dplyr::mutate(
#     feature_label = NA_character_,
#     in_use = NA,
#     .before = n
#   ) |>
#   dplyr::mutate(wt = NA_integer_) |>
#   readr::write_excel_csv("data/feature_types.csv")

feature_types <- readr::read_csv("data/feature_types.csv")

# wales ----
# identify whether points are in wales or not (for use in hashtags)
in_wales <- sf::st_covered_by(combined_points$geometry, wales_sf)

# create selection database
all_points <- combined_points |>
  dplyr::left_join(feature_types, by = c("feature_type", "obj_type_code")) |>
  dplyr::select(-n) |>
  dplyr::mutate(
    in_wales = tidyr::replace_na(as.logical(in_wales), FALSE)
  ) |>
  sf::st_as_sf() |>
  add_coords() |>
  sf::st_drop_geometry()

# add osm shortcode ----
# openstreetmap provides a method for using shortlinks to reduce the length of
# URLS, these are composed of the base URL for OSM plus an 8 character code.
# OSM's implementation is in Javascript modules, to minimise dependencies in
# the live app, the shortlinks are generated in bulk as part of the database

jsv8 <- V8::new_context()

jsv8$source("R/osm_js/osm_shortlink.js")

all_points_wosm <- all_points |>
  dplyr::mutate(
    osm_shortlink = purrr::map2_chr(
      .x = long,
      .y = lat,
      .f = ~ jsv8$call("shortLinkEncode", .x, .y, 17)
    )
  )

# write out dataset ----

readr::write_rds(all_points_wosm, "data/all_points.RDS", compress = "bz2")
