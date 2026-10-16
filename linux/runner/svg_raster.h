#ifndef RUNNER_SVG_RASTER_H_
#define RUNNER_SVG_RASTER_H_

#include <glib.h>

// Draws the SVG document in [svg] to a PNG: opaque white background, the long side
// about 1200 pixels (each side at most 4096). Returns the PNG bytes, to be released
// with g_bytes_unref, or nullptr with [error] set when the SVG cannot be read or
// drawn.
GBytes* qrious_svg_to_png(GBytes* svg, GError** error);

#endif  // RUNNER_SVG_RASTER_H_
