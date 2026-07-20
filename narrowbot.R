# setup ----

source("R/photo_functions.R")
source("R/create_post.R")
source("R/mastodon_token.R")
all_points <- readRDS("data/all_points.RDS")

# select location ----

place <- all_points |> dplyr::filter(grepl("Lock 29.*Devizes", name))

place <- all_points |> dplyr::filter(grepl("Buller's Weir", name))

place <- all_points |>
  dplyr::sample_n(size = 1, weight = wt)

place <- as.list(place)

# get photo ----

flickr_photo_info <- get_flickr_photo(place$lat, place$long)
mapbox_photo_url <- mapbox_url(place$lat, place$long)

place$photo_file <- tempfile(fileext = ".jpg")

place$photo_download <- download_photo(
  flickr_photo_info$image_url,
  mapbox_photo_url,
  place$photo_file
)

place$photo_source <- NULL
if (grepl("flickr", place$photo_download)) {
  place$photo_source <- "flickr"
  place$flickr_info <- flickr_photo_info
  place$photo_alt <- flickr_alt_text(
    place$flickr_info$title,
    place$flickr_info$owner_name,
    place$name,
    place$waterway
  )
} else if (grepl("mapbox", place$photo_download)) {
  place$photo_source <- "mapbox"
  place$photo_alt <- mapbox_alt_text(place$name, place$waterway)
}

# create post body ----
post <- create_post(place)

post_body <- paste0(post, collapse = "\n")

# mastodon token ----
toot_token <- mastodon_token(access_token = Sys.getenv("MASTODON_TOKEN"))

safely_toot <- purrr::possibly(rtoot::post_toot, otherwise = "toot_error")
safely_bsky <- purrr::possibly(bskyr::bs_post, otherwise = "bsky_error")

if (Sys.getenv("NARROWBOTR_TEST") == "true") {
  message("Test mode, will not post to Bluesky or Mastodon")
} else {
  toot_out <- safely_toot(
    status = post_body,
    media = place$photo_file,
    alt_text = place$photo_alt,
    token = toot_token
  )

  bsky_out <- safely_bsky(
    text = post_body,
    images = place$photo_file,
    images_alt = place$photo_alt
  )

  if (is.character(toot_out) && is.character(bsky_out)) {
    stop("bot error - did not post to mastodon or bsky")
  }

  if (is.character(toot_out) && toot_out == "toot_error") {
    warning("Toot unsuccessful")
  }

  if (is.character(bsky_out) && bsky_out == "bsky_error") {
    warning("bsky post unsuccessful")
  }
}

# show post content for GH actions
Sys.sleep(1)
cat(post_body)
