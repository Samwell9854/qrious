#include "svg_raster.h"

#include <cairo.h>
#include <librsvg/rsvg.h>
#include <math.h>

// How long the longer side of the drawn image is, whatever size the SVG declares.
// Large enough that a code's modules stay several pixels wide even in a dense
// symbol, and small enough to decode quickly.
static const double kTargetLongSide = 1200.0;
static const double kMaxSide = 4096.0;
// Used when the SVG declares no usable size at all.
static const double kFallbackSide = 100.0;

static gboolean usable(double width, double height) {
  return isfinite(width) && width > 0 && isfinite(height) && height > 0;
}

// The size the document asks for, in any unit that keeps its aspect ratio. Most
// generators give width and height; some give percentages or nothing and only a
// viewBox, which librsvg cannot turn into pixels by itself.
static void document_size(RsvgHandle* handle, double* width, double* height) {
  if (rsvg_handle_get_intrinsic_size_in_pixels(handle, width, height) &&
      usable(*width, *height)) {
    return;
  }
  gboolean has_width, has_height, has_viewbox;
  RsvgLength length_width, length_height;
  RsvgRectangle viewbox;
  rsvg_handle_get_intrinsic_dimensions(handle, &has_width, &length_width,
                                       &has_height, &length_height,
                                       &has_viewbox, &viewbox);
  if (has_viewbox && usable(viewbox.width, viewbox.height)) {
    *width = viewbox.width;
    *height = viewbox.height;
    return;
  }
  *width = *height = kFallbackSide;
}

static cairo_status_t write_cb(void* closure, const unsigned char* data,
                               unsigned int length) {
  g_byte_array_append(static_cast<GByteArray*>(closure), data, length);
  return CAIRO_STATUS_SUCCESS;
}

GBytes* qrious_svg_to_png(GBytes* svg, GError** error) {
  gsize size = 0;
  const guint8* data = static_cast<const guint8*>(g_bytes_get_data(svg, &size));
  RsvgHandle* handle = rsvg_handle_new_from_data(data, size, error);
  if (handle == nullptr) {
    return nullptr;
  }

  double width, height;
  document_size(handle, &width, &height);
  double scale = kTargetLongSide / (width > height ? width : height);
  int pixels_wide = static_cast<int>(fmin(fmax(round(width * scale), 1), kMaxSide));
  int pixels_high = static_cast<int>(fmin(fmax(round(height * scale), 1), kMaxSide));

  cairo_surface_t* surface =
      cairo_image_surface_create(CAIRO_FORMAT_ARGB32, pixels_wide, pixels_high);
  cairo_t* cr = cairo_create(surface);
  GBytes* result = nullptr;
  if (cairo_status(cr) != CAIRO_STATUS_SUCCESS) {
    g_set_error(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                "Could not allocate a %dx%d image", pixels_wide, pixels_high);
  } else {
    // White first: an SVG code is often black on a transparent canvas, and the
    // decoder needs the contrast a flattened image gives it.
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    RsvgRectangle viewport = {0, 0, static_cast<double>(pixels_wide),
                              static_cast<double>(pixels_high)};
    if (rsvg_handle_render_document(handle, cr, &viewport, error)) {
      GByteArray* png = g_byte_array_new();
      if (cairo_surface_write_to_png_stream(surface, write_cb, png) ==
          CAIRO_STATUS_SUCCESS) {
        result = g_byte_array_free_to_bytes(png);
      } else {
        g_byte_array_free(png, TRUE);
        g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED,
                            "Could not encode the image as PNG");
      }
    }
  }
  cairo_destroy(cr);
  cairo_surface_destroy(surface);
  g_object_unref(handle);
  return result;
}
