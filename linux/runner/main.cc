#include "my_application.h"

int main(int argc, char** argv) {
  // Open and Save go through the XDG desktop portal, so the dialog is the desktop's
  // own (KDE's or GNOME's) rather than GTK's. Unsandboxed, GTK3 draws its own, and on
  // KDE/Wayland its filter dropdown renders as a one-line popup and logs a pixman
  // "Invalid rectangle" error. GTK falls back to its own dialog when no portal is
  // running. Only dialogs made with GtkFileChooserNative are affected, which is what
  // file_selector uses. A value the user already set wins (overwrite is FALSE), and
  // this must run before anything initialises GTK.
  g_setenv("GTK_USE_PORTAL", "1", FALSE);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
