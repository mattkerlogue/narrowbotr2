# OSM javascript

The `osm_shortlink.js` script is used by the
[`build_database.R`](../build_database.R) script to compute the OpenStreetMap
(OSM) shortlinks for each place in the database of CRT locations.

The files `_shortlink.js` and `_utils.js` are copies of the javascript source
code from Open Street Map's openstreetmap-ng repository, they were downloaded
on 19 July 2026 (commit
[06252e9](https://github.com/openstreetmap-ng/openstreetmap-ng/commit/06252e9b307a6a8d1a8514e9cb083685ab73ba77)).

`osm_shortlink.js` is a modification of the `_shortlink.js` code to directly
include the `mod()` function into the same script. This is necessary to allow
the script to run using the [{V8}] package, which provides a Javascript engine
within R environments.

## License

The OSM javascript code is released under the GNU Affero General Public License
v3.0. The code in `osm_shortlink.js` is a direct derivative of the original code
for use solely within this repository, it is not covered by this repository's
MIT License. If you wish to reuse the OSM code in your own project please
consult the OSM github repository directly:
https://github.com/openstreetmap-ng/openstreetmap-ng/
