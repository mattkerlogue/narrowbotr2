.d2r <- function(x) {
  x * pi / 180
}

.r2d <- function(x) {
  x * 180 / pi
}

.mins_to_dt <- function(dt, mins, tz = "Europe/London") {
  lubridate::make_datetime(
    year = 1900 + dt$year,
    month = dt$mon + 1,
    day = dt$mday,
    min = mins
  ) |>
    lubridate::with_tz(tzone = tz)
}

time_calc <- function(dt, lat, long) {
  dt <- as.POSIXlt(dt)
  lat_r <- .d2r(lat)
  long_r <- .d2r(long)

  # year fraction (in radians)
  days <- ifelse(lubridate::leap_year(dt), 366, 365)
  fy <- 2 * pi / days * (dt$yday)

  # equation of time
  eq_time <- 229.18 *
    (0.000075 +
      (0.001868 * cos(fy)) -
      (0.032077 * sin(fy)) -
      (0.014615 * cos(2 * fy)) -
      (0.040849 * sin(2 * fy)))

  # declination
  decl <- 0.006918 -
    (0.399912 * cos(fy)) +
    (0.070257 * sin(fy)) -
    (0.006758 * cos(2 * fy)) +
    (0.000907 * sin(2 * fy)) -
    (0.002697 * cos(3 * fy)) +
    (0.00148 * sin(3 * fy))

  # time offset (in degrees)
  time_offset <- eq_time + (4 * long) - (dt$gmtoff / 60)
  tst <- dt$hour + dt$min + (dt$sec / 60) + time_offset

  # calculation for specific time
  # # solar hour angle
  # solar_ha <- (tst/4) - 180

  # # zenith angle
  # solar_zenith <- acos(
  #   sin(lat) * sin(decl)) +
  #   (cos(lat) * cos(decl) * cos(solar_ha)
  # )

  # # solar azimuth
  # solar_azimuth <- acos(
  #   180 -
  #     (
  #       -1 * (sin(lat) * cos(solar_zenith) - sin(decl)) /
  #       (cos(lat) * sin(solar_zenith))
  #   )
  # )

  # hour angles
  sunrise_ha <- .r2d(acos(
    (cos(.d2r(90.833)) / (cos(lat_r) * cos(decl))) -
      (tan(lat_r) * tan(decl))
  ))

  twilight_ha <- .r2d(acos(
    (cos(.d2r(90.833 + 6)) / (cos(lat_r) * cos(decl))) -
      (tan(lat_r) * tan(decl))
  ))

  golden_ha <- .r2d(acos(
    (cos(.d2r(90.833 - 6)) / (cos(lat_r) * cos(decl))) -
      (tan(lat_r) * tan(decl))
  ))

  sunrise_mins <- round(720 - (4 * (long + sunrise_ha)) - eq_time)
  sunset_mins <- round(720 - (4 * (long - sunrise_ha)) - eq_time)
  noon_mins <- round(720 - (4 * long) - eq_time)
  twi_am_mins <- round(720 - (4 * (long + twilight_ha)) - eq_time)
  twi_pm_mins <- round(720 - (4 * (long - twilight_ha)) - eq_time)
  gh_am_mins <- round(720 - (4 * (long + golden_ha)) - eq_time)
  gh_pm_mins <- round(720 - (4 * (long - golden_ha)) - eq_time)

  local_times <- list(
    twilight_am = .mins_to_dt(dt, twi_am_mins),
    sunrise = .mins_to_dt(dt, sunrise_mins),
    golden_hour_am = .mins_to_dt(dt, gh_am_mins),
    solar_noon = .mins_to_dt(dt, noon_mins),
    golden_hour_pm = .mins_to_dt(dt, gh_pm_mins),
    sunset = .mins_to_dt(dt, sunset_mins),
    twilight_pm = .mins_to_dt(dt, twi_pm_mins)
  )

  return(local_times)
}
