source("R/solar_eqs.R")

# access keys/tokens ----

.flickr_key <- function(key = NULL) {
  if (is.null(key)) {
    key <- Sys.getenv("FLICKR_API_KEY")
  }
  if (key == "" || !(is.character(key) & length(key) == 1)) {
    stop("Flickr API key not set")
  }
  return(key)
}

.mapbox_token <- function(token = NULL) {
  if (is.null(token)) {
    token <- Sys.getenv("MAPBOX_PAT")
  }
  if (token == "" || !(is.character(token) & length(token) == 1)) {
    stop("Mapbox PAT not set")
  }
  return(token)
}

# flickr api handling ----

.flickr_api_call <- function(lat, long, key) {
  flickr_key <- .flickr_key(key)
  lat <- round(lat, 5)
  long <- round(long, 5)
  req_url <- paste0(
    "https://www.flickr.com/services/rest/?method=flickr.photos.search",
    "&api_key=",
    flickr_key,
    "&license=1%2C2%2C3%2C4%2C5%2C6%2C7%2C8%2C9%2C10%2C11%2C12%2C13%2C14%2C15%2C16",
    "&privacy_filter=1",
    "&safe_search=1",
    "&content_types=0",
    "&media=photos",
    "&lat=",
    lat,
    "&lon=",
    long,
    "&radius=0.1",
    "&per_page=250",
    "&page=1",
    "&extras=description%2Clicense%2Cdate_taken%2Cowner_name%2Ctags",
    "&format=json",
    "&nojsoncallback=1"
  )

  response <- jsonlite::fromJSON(req_url)

  if (response$stat == "fail") {
    message(
      "Flickr API fail. Code: ",
      response$code,
      ". Message: ",
      response$message
    )
    return(NULL)
  } else if (response$stat == "ok") {
    if (response$photos$total == 0) {
      return(NULL)
    } else if (length(response$photos$photo) == 0) {
      return(NULL)
    }
  }

  return(response)
}

.tidy_flickr_response <- function(response) {
  tibble::as_tibble(response$photos$photo) |>
    tidyr::unnest(description) |>
    dplyr::select(
      photo_id = id,
      photo_secret = secret,
      owner_id = owner,
      owner_name = ownername,
      server_id = server,
      date_taken = datetaken,
      title,
      description = `_content`,
      tags
    ) |>
    dplyr::mutate(
      across(c(owner_name, title, description, tags), stringr::str_squish),
      date_taken = lubridate::ymd_hms(date_taken),
      distance = dplyr::row_number()
    )
}

# photo scoring ----

.time_score <- function(df, lat, long) {
  df |>
    dplyr::mutate(
      key_times = purrr::pmap(
        .l = list(dt = date_taken, lat = lat, long = long),
        .f = time_calc
      )
    ) |>
    tidyr::unnest_wider(key_times) |>
    dplyr::mutate(
      time_score = dplyr::case_when(
        # golden hour gets weight of 2
        date_taken >= sunrise & date_taken <= golden_hour_am ~ 2,
        date_taken >= golden_hour_pm & date_taken <= sunset ~ 2,
        # twilight gets weight of 1
        date_taken >= twilight_am & date_taken <= sunrise ~ 1,
        date_taken >= sunset & date_taken <= twilight_pm ~ 1,
        # daylight gets weight of 1.5
        date_taken >= golden_hour_am & date_taken <= golden_hour_pm ~ 1.5,
        # night gets weight of 0.5
        date_taken <= twilight_am | date_taken >= twilight_pm ~ 0.5,
        # fallback
        TRUE ~ 1
      ),
      time_offset = Sys.Date() - as.Date(date_taken)
    ) |>
    dplyr::select(photo_id, owner_id, time_score, time_offset)
}

.canal_words <- c(
  # canal terminology
  "aqueduct",
  "bank",
  "barge",
  "beam",
  "boat",
  "bridge",
  "canal",
  "channel",
  "cut",
  "cruise",
  "cruising",
  "dinghy",
  "flight",
  "embankment",
  "gate",
  "gongoozl",
  "junction",
  "keeper",
  "lock",
  "marina",
  "mooring",
  "narrow",
  "nav",
  "paddle",
  "path",
  "piling",
  "pound",
  "quay",
  "quayside",
  "river",
  "sluice",
  "tow",
  "tunnel",
  "water",
  "weir",
  "winding",
  "windlass",
  # wildlife
  "badger",
  "bat",
  "bee",
  "bird",
  "butterfly",
  "coot",
  "comorant",
  "cow",
  "damselfly",
  "dormouse",
  "dragonfly",
  "duck",
  "fish",
  "frog",
  "fox",
  "goat",
  "goose",
  "grasshopper",
  "grass snake",
  "heron",
  "kestrel",
  "kingfisher",
  "mallard",
  "newt",
  "otter",
  "owl",
  "polecat",
  "sheep",
  "stoat",
  "swan",
  "vole",
  # landscape/heritage
  "cargo",
  "coal",
  "cottage",
  "industr",
  "glade",
  "heritage",
  "historic",
  "house",
  "lake",
  "landscape",
  "factory",
  "field",
  "flower",
  "forest",
  "meadow",
  "mill",
  "park",
  "pond",
  "pub",
  "pump",
  "reservoir",
  "textile",
  "transport",
  "tree",
  "warehouse",
  "wood"
)

.canal_regex <- paste0(sort(.canal_words), collapse = "|")

.word_score <- function(df) {
  df |>
    dplyr::select(photo_id, owner_id, title, description, tags) |>
    tidyr::pivot_longer(cols = c(-photo_id, -owner_id), names_to = "field") |>
    dplyr::mutate(
      value = stringr::str_squish(gsub("[^A-z]", " ", value))
    ) |>
    tidyr::separate_longer_delim(value, " ") |>
    dplyr::filter(value != "") |>
    dplyr::distinct(photo_id, owner_id, value) |>
    dplyr::mutate(
      canal_word = purrr::map_lgl(
        .x = tolower(value),
        .f = ~ grepl(.canal_regex, .x)
      )
    ) |>
    dplyr::summarise(
      word_count = sum(canal_word),
      .by = c(photo_id, owner_id)
    )
}

.score_photos <- function(df, lat, long) {
  df |>
    dplyr::left_join(
      .time_score(df, lat, long),
      by = c("photo_id", "owner_id")
    ) |>
    dplyr::left_join(.word_score(df), by = c("photo_id", "owner_id")) |>
    dplyr::mutate(
      time_offset2 = sqrt(as.integer(time_offset)),
      recency_score = ((max(time_offset2) - time_offset2) /
        (max(time_offset2) - min(time_offset2))) +
        1,
      distance_score = ((max(distance) - distance) / (max(distance) - 1)) + 1,
      word_score = ((word_count - min(word_count)) /
        (max(word_count) - min(word_count))) +
        1,
      final_score = time_score * recency_score * distance_score * (word_score^2)
    )
}

# flickr location ----

get_flickr_photo <- function(lat, long, key = NULL) {
  if (missing(lat)) {
    stop("latitude (`lat`) not set")
  }

  if (missing(long)) {
    stop("longitude (`long`) not set")
  }

  flickr_response <- .flickr_api_call(lat, long, key)

  if (is.null(flickr_response)) {
    return(NULL)
  }

  photos_df <- .tidy_flickr_response(flickr_response)

  scored_photos_df <- .score_photos(photos_df, lat, long)

  selected_photo_df <- scored_photos_df |>
    dplyr::slice_max(final_score, n = 1)

  photo <- as.list(selected_photo_df)

  photo$photo_url <- paste(
    "https://www.flickr.com/photos",
    photo$owner_id,
    photo$photo_id,
    sep = "/"
  )

  photo$image_url <- paste(
    "https://live.staticflickr.com",
    photo$server_id,
    paste(photo$photo_id, photo$photo_secret, "b.jpg", sep = "_"),
    sep = "/"
  )

  return(photo)
}

# alt text ----
flickr_alt_text <- function(photo_title, flickr_user, location, waterway) {
  if (!is.null(waterway)) {
    if (waterway != location) {
      location <- paste(location, waterway, sep = ", ")
    }
  }

  paste0(
    "A photo located near ",
    location,
    " titled \"",
    photo_title,
    "\" taken by ",
    flickr_user,
    " on Flickr."
  )
}

mapbox_alt_text <- function(location, waterway) {
  if (!is.null(waterway)) {
    if (waterway != location) {
      location <- paste(location, waterway, sep = ", ")
    }
  }

  paste0(
    "A satellite image of the area containing ",
    location,
    ". Provided by Mapbox."
  )
}

# mapbox url ----

mapbox_url <- function(lat, long, token = NULL) {
  if (missing(lat)) {
    stop("latitude (`lat`) not set")
  }

  if (missing(long)) {
    stop("longitude (`long`) not set")
  }
  lat <- round(lat, 5)
  long <- round(long, 5)

  mapbox_token <- .mapbox_token(token)

  mapbox_url <- paste(
    "https://api.mapbox.com/styles/v1/mapbox/satellite-v9/static",
    paste(place$long, place$lat, 17, sep = ","),
    paste0("500x500@2x?access_token=", mapbox_token),
    sep = "/"
  )
}

# download photo ----
.safe_download <- function(url, dest) {
  tryCatch(
    error = function(cnd) {
      NULL
    },
    {
      download.file(url, dest, quiet = TRUE)
      url
    }
  )
}

download_photo <- function(flickr_url = NULL, mapbox_url = NULL, dest = NULL) {
  if (is.null(flickr_url) & is.null(mapbox_url)) {
    stop("No photo URLs provided")
  }

  if (is.null(dest)) {
    stop("No download location set")
  }

  res <- NULL

  if (!is.null(flickr_url)) {
    res <- .safe_download(flickr_url, dest)
  }

  if (is.null(res) & !is.null(mapbox_url)) {
    res <- .safe_download(mapbox_url, dest)
  }

  if (is.null(res)) {
    stop("Failed to download a photo from Flickr or Mapbox")
  }

  return(res)
}
