.place_name <- function(feature_type, name, waterway) {
  if (feature_type == "canal_km") {
    place_name <- c("💧", name)
  } else if (is.na(waterway)) {
    place_name <- c("📍", name)
  } else {
    place_name <- c("📍", paste(name, waterway, sep = ", "))
  }
  paste0(place_name, collapse = ": ")
}

.osm_link <- function(osm_shortlink) {
  if (missing(osm_shortlink)) {
    stop("shortlink not provided")
  }

  osm_url <- paste0(
    "https://www.osm.org/go/",
    osm_shortlink,
    "?m"
  )

  paste0(c("🗺️", osm_url), collapse = ": ")
}


.flickr_shortlink <- function(photo_id) {
  num <- as.numeric(photo_id)
  alphabet <- c(as.character(1:9), letters, LETTERS)
  alphabet <- alphabet[!(alphabet %in% c("l", "I", "O"))]

  bc <- length(alphabet)

  enc <- character()

  while (num > bc) {
    div <- num %/% bc
    mod <- num %% bc
    enc <- c(alphabet[mod + 1], enc)
    num <- div
  }
  enc <- c(alphabet[num + 1], enc)

  shortlink <- paste0(
    "https://flic.kr/p/",
    paste0(enc, collapse = "")
  )

  return(shortlink)
}

.flickr_credit <- function(owner_name, photo_id) {
  photo_url <- .flickr_shortlink(photo_id)
  paste0(
    c("📸", paste("Photo by", owner_name, "on Flickr", photo_url)),
    collapse = ": "
  )
}

.convert_flickr_tags <- function(tags) {
  tags <- unique(unlist(strsplit(tags, " ")))
  canal_tags <- character()
  for (i in seq_along(tags)) {
    flags <- purrr::map_lgl(.x = .canal_words, .f = ~ grepl(.x, tags[i]))
    if (sum(flags) > 0) {
      canal_tags <- c(canal_tags, tags[i])
    }
  }
  canal_tags <- paste0("#", canal_tags)
  return(canal_tags)
}

.post_tags <- function(wales, photo_source, flickr_tags = NULL) {
  tags <- c("#canal", "#narrowboat")
  if (wales) {
    tags <- c(tags, "#wales", "#uk")
  } else {
    tags <- c(tags, "#england", "#uk")
  }
  if (photo_source == "flickr") {
    if (!is.null(flickr_tags)) {
      flickr_tags <- .convert_flickr_tags(flickr_tags)
      tags <- c(tags, flickr_tags)
    }
  } else if (photo_source == "mapbox") {
    tags <- c(tags, "#aerialphoto #aerialphotography #satelliteview")
  }
  return(tags)
}

create_post <- function(place) {
  post <- list()

  # get place name and osm link
  post$place_name <- .place_name(place$feature_type, place$name, place$waterway)
  post$osm_link <- .osm_link(place$osm_shortlink)

  # add flickr credit if relevant
  if (place$photo_source == "flickr") {
    post$flickr_credit <- .flickr_credit(
      place$flickr_info$owner_name,
      place$flickr_info$photo_id
    )
  }

  # estimate length of post (pad for emoji calcs and whitespace)
  post_chars <- length(unname(unlist(lapply(post, strsplit, "")))) +
    (length(post) * 2)

  # generate tags
  tags <- .post_tags(
    place$in_wales,
    place$photo_source,
    place$flickr_info$tags
  )

  # estimate length of tags, cut off tags that pass the 300 character bluesky
  # limit
  tag_length <- post_chars + 2 + cumsum(nchar(tags) + 1)
  included_tags <- tags[tag_length < 300]

  # add tags to post
  # prepend additional character return to taglist
  post$tags <- paste0("\n", paste0(included_tags, collapse = " "))

  return(post)
}
