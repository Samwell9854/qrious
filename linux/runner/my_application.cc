#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <math.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* window_channel;
  // Whether the window was already full screen when Dart asked for it, so that
  // leaving the full-screen code does not also undo the user's own choice.
  gboolean was_full_screen;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Whether the desktop is GNOME, the one desktop whose apps draw their own title
// bar. XDG_CURRENT_DESKTOP is a colon-separated list, e.g. "ubuntu:GNOME".
static gboolean is_gnome_desktop() {
  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  if (desktop == nullptr) {
    return FALSE;
  }
  g_auto(GStrv) names = g_strsplit(desktop, ":", -1);
  for (gchar** name = names; *name != nullptr; name++) {
    if (g_strcmp0(*name, "GNOME") == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean is_full_screen(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  return gdk_window != nullptr &&
         (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_FULLSCREEN) != 0;
}

// Millimetres per logical pixel on the monitor showing the window, or 0 when the
// monitor does not report its physical size. GTK's logical pixels are Flutter's,
// so no scale factor is involved. Diagonals rather than widths, because they are
// the same whichever way a monitor is rotated, while whether the millimetres
// follow a rotation is up to the backend.
static double millimetres_per_pixel(GtkWindow* window) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (gdk_window == nullptr) {
    return 0;
  }
  GdkMonitor* monitor = gdk_display_get_monitor_at_window(
      gdk_window_get_display(gdk_window), gdk_window);
  if (monitor == nullptr) {
    return 0;
  }
  GdkRectangle geometry;
  gdk_monitor_get_geometry(monitor, &geometry);
  int width_mm = gdk_monitor_get_width_mm(monitor);
  int height_mm = gdk_monitor_get_height_mm(monitor);
  if (width_mm <= 0 || height_mm <= 0 || geometry.width <= 0 ||
      geometry.height <= 0) {
    return 0;
  }
  return hypot(width_mm, height_mm) / hypot(geometry.width, geometry.height);
}

// Answers the "qrious/window" channel, for what Flutter has no desktop call for:
// setFullScreen(bool) takes the whole screen for the full-screen code and gives
// it back afterwards (lib/full_screen.dart); millimetresPerPixel says how large a
// pixel is, to judge whether a code is dense (lib/pixel_size.dart).
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  FlValue* args = fl_method_call_get_args(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "millimetresPerPixel") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_float(millimetres_per_pixel(self->window));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else if (g_strcmp0(method, "setFullScreen") != 0) {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  } else if (fl_value_get_type(args) != FL_VALUE_TYPE_BOOL) {
    response = FL_METHOD_RESPONSE(fl_method_error_response_new(
        "bad-args", "setFullScreen takes a bool", nullptr));
  } else {
    if (fl_value_get_bool(args)) {
      self->was_full_screen = is_full_screen(self->window);
      gtk_window_fullscreen(self->window);
    } else if (!self->was_full_screen) {
      gtk_window_unfullscreen(self->window);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  }

  fl_method_call_respond(method_call, response, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // A GTK header bar only on GNOME, where it is the native style. The template
  // also used one on every Wayland session, which on KDE and others replaced the
  // compositor's own title bar with a taller one that carries no app icon.
  // Without a header bar, GTK asks the compositor to draw the decorations.
  if (is_gnome_desktop()) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Qrious");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Qrious");
  }

  gtk_window_set_default_size(window, 1280, 720);
  // Resolves against the hicolor theme, so it only takes effect once the icons
  // from linux/icons/ are installed under /usr/share/icons.
  gtk_window_set_icon_name(window, APPLICATION_ID);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  self->window = window;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "qrious/window",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
