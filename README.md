# narrobotR (v2)

**narowbotR** (pronounced "narrow-bot-er")[^nb] is a
[Mastodon](https://mastodon.social/@narrowbotr) and
[Bluesky](https://bsky.app/profile/narrowbotr.bsky.social) bot written in
[R](https://r-project.org)and powered by Github Actions that posts a random
location on the [Canal & River Trust](https://canalrivertrust.org.uk) (CRT)
network. Where possible it sources a photo of the location from
[Flickr](https://www.flickr.com), if a Flickr photo is not available it will
post an aerial photograph sourced from [Mapbox](https://www.mapbox.com).

## Background

This is the second edition of the bot. The first version of the bot originally
ran on Twitter (now X) from April 2020 but this was discontinued in April 2023
following changes to Twitter's terms of service. The bot also ran on Mastodon
from November 2022 and on Bluesky from December 2024. In May 2025, the first
edition of the bot suffered from repeated failures of the Github Action to post
content to Bluesky. Despite numerous attempts to identify the source of the
failure, this was unsuccessful and so the bot was taken offline.

This second edition is a fresh recreation of the bot, with some adjustments to
the code, and rebuilding of the database. The original bot's code
remains available in the original
[narrowbotR](https://www.github.com/mattkerlogue/narrowbotR) repo.

## CRT locations

The bot selects locations from a database of places derived from the Canal &
River Trust's open data feeds. There are 17,144 points included in the dataset
representing 14 different types of feature within the English and Welsh canal
network. The first edition of the bot used only point based data feeds, in this
second edition the "canals by km" feed has also been used to include sections
of canal. For these canal sections the centroid of each segment has been
included in the data. This should allow for potential photographs on or by canal
towpaths that are not otherwise near a feature such as a lock or a bridge.

Some 40% of the features in the database are bridges while locks, which are
synonymous with canals only account for 10% of places. Similarly culverts,
which are often hidden from direct view, account for 17% of the places included
in the dataset but boat lifts, dry docks, lakes, slipways, tunnel portals and
wharves all account for only around 2% in total. These features are more likely
to give rise to options for interesting photography than features such as
culverts and weirs (most weirs on the CRT network, like culverts are often
out of direct view). While bridges may give rise to photographic options due to
their large presence in the dataset these have been down-weighted, as have
the centroids of canal sections. Within the bridges set of features, bridges
identified as "pipe bridges" (i.e. those containing services such as mains
water or sewerage) have been further down-weighted than bridges carrying roads,
track, footpaths or railways.

In the weighted dataset, locks and bridges each now have around a 1 in 3 chance
of being selected and all features have at least a 0.5% chance of being picked.
As a result, in a given year the bot might reasonably be expected to select the
[Anderton Boat Lift](https://en.wikipedia.org/wiki/Anderton_Boat_Lift) around 7
times, whereas in the unweighted dataset it was likely to be selected only once
every 11 years. The table below shows the raw and weighted counts and
percentages of features in the database, it also includes a count of the likely
sightings of different feature types in a given year (assuming 365 days and
four posts per day).

| Feature type | Raw # | Raw % | Weighted # | Weighted % | Likely sightings |
| :----------- | ----: | ----: | ---------: | ---------: | ---------------: |
| lock | 1,722 | 10.0% | 3,444 | 33.0% | 481 |
| bridge | 6,916 | 40.3% | 3,330 | 31.9% | 465 |
| canal_km | 3,173 | 18.5% | 794 | 7.6% | 111 |
| aqueduct | 330 | 1.9% | 660 | 6.3% | 92 |
| winding_hole | 533 | 3.1% | 533 | 5.1% | 74 |
| tunnel_portal | 103 | 0.6% | 412 | 3.9% | 58 |
| wharf | 75 | 0.4% | 300 | 2.9% | 42 |
| dry_dock | 68 | 0.4% | 272 | 2.6% | 38 |
| pumping_station | 88 | 0.5% | 176 | 1.7% | 25 |
| weir | 1,108 | 6.5% | 166 | 1.6% | 23 |
| culvert | 2,960 | 17.3% | 148 | 1.4% | 21 |
| slipway | 57 | 0.3% | 114 | 1.1% | 16 |
| boat_lift | 1 | 0.0% | 50 | 0.5% | 7 |
| lake_pond_fishery | 10 | 0.1% | 50 | 0.5% | 7 |

## Workflow

The narrowbotR runs via Github Actions four times per day. The bot's workflow
is as follows:

1. Select a place at random from the locations database.
2. Use the Flickr API to identify nearby photos (if any).
     a. If Flickr photos exist then give each photo a score and select the
        highest scoring photo.
     b. If no Flickr photos exist then generate a satellite image of the place
        from the Mapbox API.
3. Download the photo from Flickr/Mapbox.
4. Construct the text of the post:
     a. The place name (including if available the waterway name).
     b. A link to the location on OpenStreetMap.
     c. If a Flickr photo, attribution and a link to the Flickr photo page.
     d. Tags including the base tags of #canal, #narrowboat, either of #england
        or #wales depending on location, and # uk. For flickr photos any tags
        included by the Flickr user will be appended and for mapbox photos a
        set of tags indicating it is arial photography. Additional tags are
        limited to ensure total post length does not go over 300 characters.
5. Attempt to post on Mastodon and Bluesky.

### CRT locations database

The database of CRT locations is derived from the CRT open data feeds (see
[feeds.csv](data/feeds.csv)). The database is generated offline since it would
be computationally expensive to recreate each time the bot is run, and
unnecessary since there is only limited change in the CRT's features over time.

The database combines locations provided from point data as well as including
the centroids computed from line segments representing 1 kilometre stretches of
canal and waterway centrelines. The feature sub-type is also included included
in the database (e.g. to identify which bridges are road bridges vs railway
bridges), at present this is only used for weighting purposes.

#### Welsh marker

Around 4% of the places in the database are located within Wales, however this
is not marked in the CRT data feeds (the canal segments data feed includes a
region marker but Wales is part of a combined region with South West England).

In constructing the database a marker for places in Wales is included so that
a #wales hashtag can be included in posts rather than #england.

## Flickr photo scoring

The bot tries to source photos from the Flickr API that are within a 100 metre
radius of the selected location's latitude and longitude. Only photos that have
some form of publicly reusable license are selected (i.e. excluding photos that
are set to "All rights reserved").

The bot calculates each score using four measures:

* `time_score`: photos taken within "golden hour" are given a score of 2, those
  in standard daylight a score of 1.5, those during twilight a score of 1, and
  those at night a score of 0.5.
* `recency_score`: photos are given a score between 1 and 2 depending on how
  recently the photo has been taken, with more recent photos given precedence
  over older photos.
* `distance_score`: no location information is returned from the Flickr API
  search, however based on testing of the API it appears that photos are
  returned sorted by distance. A pseudo-score of between 1 and 2 is generated
  based on the photo's position in the search results, with the first photo
  getting a score of 2 and the last photo getting a score of 1, all other photos
  are scaled evenly based on their position in the results list.
* `word_score`: the photo's title, description and tags are assessed for their
  use of 94 words that relate to either canals/waterways, wildlife and other
  landscape terms. The word score also ranges from 1 to 2, but is squared to
  increase its effect in the final calculations.

### Golden hour and solar calculations

The previous version of the narrowbotR used the `{suncalc}` package to determine
times such as sunrise, sunset and the morning and evening golden hours. To
reduce dependencies these are now calculated within the repo based on
formulae published by the US National Oceanic and Atmospheric Administration
(see [`solareqns.PDF`](ref/solareqns.PDF)[^1]).

[^1]: The NOAA host an [online calculator](https://gml.noaa.gov/grad/solcalc/),
      included within the calcuator's
      [links page](https://gml.noaa.gov/grad/solcalc/sollinks.html) is a
      [PDF](https://gml.noaa.gov/grad/solcalc/solareqns.PDF) providing formulae
      for general calculation of sunset and sunrise. As the calculator is no
      longer actively maintained the PDF has been downloaded and stored in the
      `ref` folder of this repo.

There are several definitions of
["golden hour"](https://en.wikipedia.org/wiki/Golden_hour_(photography)), the
time immediately after sunrise or immediately before sunset where, due to the
angle of the sun, natural light is more red and creates golden hues. As a
result "golden hour" is often a prized time for photography.
For the narrowbotR, the opposite of the
[civil twilight](https://en.wikipedia.org/wiki/Twilight) period has been used,
i.e. when the sun is within 6º of the horizon.

### Wordlist

The bot checks Flickr photos for the usage of the following words in the title,
description or tags.

#### Canal related terms

| | | | | |
| --- | --- | --- | --- | --- |
| aqueduct | bank | barge | beam | boat |
| bridge | canal | channel | cut | cruise |
| cruising | dinghy | flight | embankment | gate |
| gongoozl | junction | keeper | lock | marina |
| mooring | narrow | nav | paddle | path |
| piling | pound | quay | quayside | river |
| sluice | tow | tunnel | water | weir |
| winding | windlass |

#### Wildlife related terms

| | | | | |
| --- | --- | --- | --- | --- |
| badger | bat | bee | bird | butterfly |
| coot | comorant | cow | damselfly | dormouse |
| dragonfly | duck | fish | frog | fox |
| goat | goose | grasshopper | grass snake | heron |
| kestrel | kingfisher | mallard | newt | otter |
| owl | polecat | sheep | stoat | swan |
| vole |

#### Landscape and heritage related terms

| | | | | |
| --- | --- | --- | --- | --- |
| cargo | coal | cottage | industr | glade |
| heritage | historic | house | lake | landscape |
| factory | field | flower | forest | meadow |
| mill | park | pond | pub | pump |
| reservoir | textile | transport | tree | warehouse |
| wood |

## License

The code in this repository is licensed under the MIT License, this covers all
R scripts in the R folder, the Github Actions workflows and the supporting
documentation in this README.

The original location data is source from
[Canal & River Trust's Open Data](https://data-canalrivertrust.opendata.arcgis.com)
service. Different data feeds are subject to different license conditions, with
one of three different licenses applying. The `feeds.csv` file provides the
license conditions for each individual feed:

* The Open Government Licence (OGL): https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/
* The Canal & River Trust's Data License (CRTDL)
  ([PDF][CTRL_pdf], [web][CRTDL_web])
* The Ordnance Survey's INSPIRE License (INSPIRE) ([PDF][INSPIRE_pdf], [web][INSPIRE_web])

As far as is known, any data requiring the Ordnance Survey INSPIRE license is
not used by the bot.

The source data remains copyright of the Canal & River Trust: © Canal & River
Trust copyright and database rights reserved 2026.

[CTRL_pdf]: ref/Canal_River_Trust_Data_Licence.pdf
[CRTDL_web]: https://canalrivertrust.maps.arcgis.com/sharing/rest/content/items/f8387b382d2c4a549debedb154338a08/data
[INSPIRE_pdf]: ref/24599-inspire-end-user-licence.pdf
[INSPIRE_web]: https://canalrivertrust.maps.arcgis.com/sharing/rest/content/items/5bb28b960089489d8a88a28f52996237/data
