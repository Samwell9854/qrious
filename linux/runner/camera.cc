#include "camera.h"

#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/video.h>

// How long "start" waits for a first picture before giving up.
static const guint kFirstFrameTimeoutSeconds = 5;

// What the GStreamer streaming thread and the main loop share: the latest frame,
// tightly packed RGBA. It is reference-counted because the appsink callbacks, the
// preview texture and idle callbacks queued on the main loop each outlive the
// camera's stop by an unknown moment. [owner] belongs to the main thread alone: the
// camera clears it on stop, which turns any idle still queued into a no-op.
typedef struct {
  gint ref_count;
  GMutex mutex;
  guint8* rgba;
  gsize capacity;
  guint width;
  guint height;
  // At most one idle is queued at a time; frames arriving meanwhile just replace
  // the stored one.
  gint idle_pending;
  QriousCamera* owner;
} Shared;

static Shared* shared_new(QriousCamera* owner) {
  Shared* shared = g_new0(Shared, 1);
  shared->ref_count = 1;
  g_mutex_init(&shared->mutex);
  shared->owner = owner;
  return shared;
}

static Shared* shared_ref(Shared* shared) {
  g_atomic_int_inc(&shared->ref_count);
  return shared;
}

static void shared_unref(gpointer data) {
  Shared* shared = static_cast<Shared*>(data);
  if (g_atomic_int_dec_and_test(&shared->ref_count)) {
    g_mutex_clear(&shared->mutex);
    g_free(shared->rgba);
    g_free(shared);
  }
}

// The preview: Flutter reads the latest frame from it on the raster thread.
G_DECLARE_FINAL_TYPE(QriousCameraTexture, qrious_camera_texture, QRIOUS,
                     CAMERA_TEXTURE, FlPixelBufferTexture)

struct _QriousCameraTexture {
  FlPixelBufferTexture parent_instance;
  Shared* shared;
  // The copy handed to Flutter, which must stay valid until the next call.
  guint8* pixels;
  gsize capacity;
};

G_DEFINE_TYPE(QriousCameraTexture, qrious_camera_texture,
              fl_pixel_buffer_texture_get_type())

static gboolean texture_copy_pixels(FlPixelBufferTexture* texture,
                                    const uint8_t** buffer, uint32_t* width,
                                    uint32_t* height, GError** error) {
  QriousCameraTexture* self = QRIOUS_CAMERA_TEXTURE(texture);
  Shared* shared = self->shared;
  g_mutex_lock(&shared->mutex);
  gsize size = static_cast<gsize>(shared->width) * shared->height * 4;
  if (size == 0) {
    g_mutex_unlock(&shared->mutex);
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_FAILED, "No frame yet");
    return FALSE;
  }
  if (self->capacity < size) {
    g_free(self->pixels);
    self->pixels = static_cast<guint8*>(g_malloc(size));
    self->capacity = size;
  }
  memcpy(self->pixels, shared->rgba, size);
  *width = shared->width;
  *height = shared->height;
  g_mutex_unlock(&shared->mutex);
  *buffer = self->pixels;
  return TRUE;
}

static void texture_finalize(GObject* object) {
  QriousCameraTexture* self = QRIOUS_CAMERA_TEXTURE(object);
  g_free(self->pixels);
  g_clear_pointer(&self->shared, shared_unref);
  G_OBJECT_CLASS(qrious_camera_texture_parent_class)->finalize(object);
}

static void qrious_camera_texture_class_init(QriousCameraTextureClass* klass) {
  FL_PIXEL_BUFFER_TEXTURE_CLASS(klass)->copy_pixels = texture_copy_pixels;
  G_OBJECT_CLASS(klass)->finalize = texture_finalize;
}

static void qrious_camera_texture_init(QriousCameraTexture* self) {}

struct _QriousCamera {
  FlTextureRegistrar* registrar;
  FlMethodChannel* channel;
  GstElement* pipeline;
  Shared* shared;
  QriousCameraTexture* texture;
  // The "start" call waiting for the first frame.
  FlMethodCall* pending;
  guint bus_watch;
  guint timeout;
};

static void respond_error(FlMethodCall* call, const gchar* code,
                          const gchar* message) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
  fl_method_call_respond(call, response, nullptr);
}

static void respond_success(FlMethodCall* call, FlValue* result) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  fl_method_call_respond(call, response, nullptr);
}

static void ensure_gst_init() {
  static gsize initialized = 0;
  if (g_once_init_enter(&initialized)) {
    gst_init(nullptr, nullptr);
    g_once_init_leave(&initialized, 1);
  }
}

static void answer_list(FlMethodCall* call) {
  ensure_gst_init();
  g_autoptr(GstElementFactory) v4l2src = gst_element_factory_find("v4l2src");
  if (v4l2src == nullptr) {
    respond_error(call, "missing-plugin", "GStreamer has no v4l2src element");
    return;
  }
  g_autoptr(FlValue) list = fl_value_new_list();
  // The V4L2 provider by name, not a GstDeviceMonitor: the PipeWire provider would
  // list the same cameras as nodes that cannot be captured from reliably.
  g_autoptr(GstDeviceProvider) provider =
      gst_device_provider_factory_get_by_name("v4l2deviceprovider");
  if (provider != nullptr) {
    GList* devices = gst_device_provider_get_devices(provider);
    for (GList* it = devices; it != nullptr; it = it->next) {
      GstDevice* device = GST_DEVICE(it->data);
      if (!gst_device_has_classes(device, "Video/Source")) {
        continue;
      }
      GstStructure* props = gst_device_get_properties(device);
      const gchar* path = nullptr;
      if (props != nullptr) {
        path = gst_structure_get_string(props, "device.path");
        if (path == nullptr) {
          path = gst_structure_get_string(props, "api.v4l2.path");
        }
      }
      if (path != nullptr) {
        g_autofree gchar* name = gst_device_get_display_name(device);
        FlValue* entry = fl_value_new_map();
        fl_value_set_string_take(entry, "id", fl_value_new_string(path));
        fl_value_set_string_take(entry, "name", fl_value_new_string(name));
        fl_value_append_take(list, entry);
      }
      if (props != nullptr) {
        gst_structure_free(props);
      }
    }
    g_list_free_full(devices, g_object_unref);
  }
  respond_success(call, list);
}

void qrious_camera_stop(QriousCamera* self) {
  if (self->bus_watch != 0) {
    g_source_remove(self->bus_watch);
    self->bus_watch = 0;
  }
  if (self->timeout != 0) {
    g_source_remove(self->timeout);
    self->timeout = 0;
  }
  if (self->pipeline != nullptr) {
    gst_element_set_state(self->pipeline, GST_STATE_NULL);
    g_clear_object(&self->pipeline);
  }
  // Idles already queued find no owner and do nothing.
  if (self->shared != nullptr) {
    self->shared->owner = nullptr;
    g_clear_pointer(&self->shared, shared_unref);
  }
  if (self->texture != nullptr) {
    fl_texture_registrar_unregister_texture(self->registrar,
                                            FL_TEXTURE(self->texture));
    g_clear_object(&self->texture);
  }
  if (self->pending != nullptr) {
    respond_error(self->pending, "failed", "The camera was stopped");
    g_clear_object(&self->pending);
  }
}

// Ends a capture that ended by itself: before the first frame it fails the pending
// "start", afterwards Dart hears of it on "error".
static void fail(QriousCamera* self, const gchar* code, const gchar* message) {
  g_autoptr(FlMethodCall) pending = self->pending;
  self->pending = nullptr;
  qrious_camera_stop(self);
  if (pending != nullptr) {
    respond_error(pending, code, message);
  } else {
    g_autoptr(FlValue) text = fl_value_new_string(message);
    fl_method_channel_invoke_method(self->channel, "error", text, nullptr,
                                    nullptr, nullptr);
  }
}

static gboolean timeout_cb(gpointer user_data) {
  QriousCamera* self = static_cast<QriousCamera*>(user_data);
  self->timeout = 0;
  fail(self, "failed", "The camera sent no picture");
  return G_SOURCE_REMOVE;
}

static gboolean bus_cb(GstBus* bus, GstMessage* message, gpointer user_data) {
  QriousCamera* self = static_cast<QriousCamera*>(user_data);
  GstMessageType type = GST_MESSAGE_TYPE(message);
  if (type != GST_MESSAGE_ERROR && type != GST_MESSAGE_EOS) {
    return G_SOURCE_CONTINUE;
  }
  g_autofree gchar* text = nullptr;
  const gchar* code = "failed";
  if (type == GST_MESSAGE_ERROR) {
    g_autoptr(GError) error = nullptr;
    gst_message_parse_error(message, &error, nullptr);
    text = g_strdup(error != nullptr ? error->message : "Unknown error");
    if (error != nullptr &&
        ((error->domain == GST_RESOURCE_ERROR &&
          error->code == GST_RESOURCE_ERROR_BUSY) ||
         g_strstr_len(error->message, -1, "busy") != nullptr ||
         g_strstr_len(error->message, -1, "EBUSY") != nullptr)) {
      code = "busy";
    }
  } else {
    text = g_strdup("The camera stopped sending pictures");
  }
  // stop() would remove this very source; it is removed by the return value.
  self->bus_watch = 0;
  fail(self, code, text);
  return G_SOURCE_REMOVE;
}

// On the main loop, after a frame arrived: answers a waiting "start" and tells
// Flutter the preview has a new picture.
static gboolean frame_idle(gpointer data) {
  Shared* shared = static_cast<Shared*>(data);
  g_atomic_int_set(&shared->idle_pending, 0);
  QriousCamera* self = shared->owner;
  if (self == nullptr) {
    return G_SOURCE_REMOVE;
  }
  if (self->texture == nullptr) {
    QriousCameraTexture* texture = QRIOUS_CAMERA_TEXTURE(
        g_object_new(qrious_camera_texture_get_type(), nullptr));
    texture->shared = shared_ref(shared);
    self->texture = texture;
    fl_texture_registrar_register_texture(self->registrar, FL_TEXTURE(texture));
  }
  if (self->pending != nullptr) {
    if (self->timeout != 0) {
      g_source_remove(self->timeout);
      self->timeout = 0;
    }
    g_mutex_lock(&shared->mutex);
    gint64 width = shared->width;
    gint64 height = shared->height;
    g_mutex_unlock(&shared->mutex);
    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(
        result, "textureId",
        fl_value_new_int(fl_texture_get_id(FL_TEXTURE(self->texture))));
    fl_value_set_string_take(result, "width", fl_value_new_int(width));
    fl_value_set_string_take(result, "height", fl_value_new_int(height));
    g_autoptr(FlMethodCall) pending = self->pending;
    self->pending = nullptr;
    respond_success(pending, result);
  }
  fl_texture_registrar_mark_texture_frame_available(self->registrar,
                                                    FL_TEXTURE(self->texture));
  return G_SOURCE_REMOVE;
}

// Runs on a GStreamer streaming thread: nothing of Flutter's may be touched here.
static GstFlowReturn new_sample_cb(GstAppSink* sink, gpointer user_data) {
  Shared* shared = static_cast<Shared*>(user_data);
  GstSample* sample = gst_app_sink_pull_sample(sink);
  if (sample == nullptr) {
    return GST_FLOW_EOS;
  }
  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstVideoInfo info;
  GstVideoFrame frame;
  if (buffer != nullptr &&
      gst_video_info_from_caps(&info, gst_sample_get_caps(sample)) &&
      gst_video_frame_map(&frame, &info, buffer, GST_MAP_READ)) {
    guint width = GST_VIDEO_FRAME_WIDTH(&frame);
    guint height = GST_VIDEO_FRAME_HEIGHT(&frame);
    gsize stride = GST_VIDEO_FRAME_PLANE_STRIDE(&frame, 0);
    const guint8* src =
        static_cast<const guint8*>(GST_VIDEO_FRAME_PLANE_DATA(&frame, 0));
    gsize size = static_cast<gsize>(width) * height * 4;
    g_mutex_lock(&shared->mutex);
    if (shared->capacity < size) {
      g_free(shared->rgba);
      shared->rgba = static_cast<guint8*>(g_malloc(size));
      shared->capacity = size;
    }
    for (guint row = 0; row < height; row++) {
      memcpy(shared->rgba + static_cast<gsize>(row) * width * 4,
             src + row * stride, static_cast<gsize>(width) * 4);
    }
    shared->width = width;
    shared->height = height;
    g_mutex_unlock(&shared->mutex);
    gst_video_frame_unmap(&frame);
    if (g_atomic_int_compare_and_exchange(&shared->idle_pending, 0, 1)) {
      g_idle_add_full(G_PRIORITY_DEFAULT, frame_idle, shared_ref(shared),
                      shared_unref);
    }
  }
  gst_sample_unref(sample);
  return GST_FLOW_OK;
}

static void answer_start(QriousCamera* self, FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_STRING) {
    respond_error(call, "bad-args", "start takes a device path");
    return;
  }
  ensure_gst_init();
  qrious_camera_stop(self);

  // The device path is set as a property afterwards rather than formatted into the
  // description, so nothing in it can be read as pipeline syntax.
  g_autoptr(GError) error = nullptr;
  GstElement* pipeline = gst_parse_launch(
      "v4l2src name=src "
      "! video/x-raw,width=[320,1920],height=[240,1080];"
      "image/jpeg,width=[320,1920],height=[240,1080] "
      "! decodebin ! videoconvert ! videoscale "
      "! video/x-raw,format=RGBA,pixel-aspect-ratio=1/1 "
      "! appsink name=sink max-buffers=1 drop=true sync=false",
      &error);
  if (pipeline == nullptr) {
    respond_error(call, "failed",
                  error != nullptr ? error->message : "No pipeline");
    return;
  }
  // gst_parse_launch hands back a floating reference; own it, so the unref in stop
  // does not finalize a floating object.
  gst_object_ref_sink(pipeline);
  g_autoptr(GstElement) src = gst_bin_get_by_name(GST_BIN(pipeline), "src");
  g_autoptr(GstElement) sink = gst_bin_get_by_name(GST_BIN(pipeline), "sink");
  g_object_set(src, "device", fl_value_get_string(args), nullptr);

  self->pipeline = pipeline;
  self->shared = shared_new(self);
  GstAppSinkCallbacks callbacks = {};
  callbacks.new_sample = new_sample_cb;
  gst_app_sink_set_callbacks(GST_APP_SINK(sink), &callbacks,
                             shared_ref(self->shared), shared_unref);

  g_autoptr(GstBus) bus = gst_element_get_bus(pipeline);
  self->bus_watch = gst_bus_add_watch(bus, bus_cb, self);
  self->timeout = g_timeout_add_seconds(kFirstFrameTimeoutSeconds, timeout_cb,
                                        self);
  self->pending = FL_METHOD_CALL(g_object_ref(call));
  if (gst_element_set_state(pipeline, GST_STATE_PLAYING) ==
      GST_STATE_CHANGE_FAILURE) {
    // Usually the bus says why; this is for when it has not yet.
    fail(self, "failed", "The camera could not be started");
  }
}

static void answer_frame(QriousCamera* self, FlMethodCall* call) {
  Shared* shared = self->shared;
  if (shared == nullptr) {
    respond_success(call, nullptr);
    return;
  }
  g_mutex_lock(&shared->mutex);
  gsize pixels = static_cast<gsize>(shared->width) * shared->height;
  if (pixels == 0) {
    g_mutex_unlock(&shared->mutex);
    respond_success(call, nullptr);
    return;
  }
  g_autofree guint8* luma = static_cast<guint8*>(g_malloc(pixels));
  const guint8* rgba = shared->rgba;
  for (gsize i = 0; i < pixels; i++, rgba += 4) {
    luma[i] = (77 * rgba[0] + 150 * rgba[1] + 29 * rgba[2]) >> 8;
  }
  gint64 width = shared->width;
  gint64 height = shared->height;
  g_mutex_unlock(&shared->mutex);
  g_autoptr(FlValue) result = fl_value_new_map();
  fl_value_set_string_take(result, "width", fl_value_new_int(width));
  fl_value_set_string_take(result, "height", fl_value_new_int(height));
  fl_value_set_string_take(result, "luma",
                           fl_value_new_uint8_list(luma, pixels));
  respond_success(call, result);
}

void qrious_camera_handle(QriousCamera* self, FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "list") == 0) {
    answer_list(method_call);
  } else if (g_strcmp0(method, "start") == 0) {
    answer_start(self, method_call);
  } else if (g_strcmp0(method, "frame") == 0) {
    answer_frame(self, method_call);
  } else if (g_strcmp0(method, "stop") == 0) {
    qrious_camera_stop(self);
    respond_success(method_call, nullptr);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

QriousCamera* qrious_camera_new(FlTextureRegistrar* registrar,
                                FlMethodChannel* channel) {
  QriousCamera* self = g_new0(QriousCamera, 1);
  self->registrar = FL_TEXTURE_REGISTRAR(g_object_ref(registrar));
  self->channel = channel;
  return self;
}

void qrious_camera_free(QriousCamera* self) {
  qrious_camera_stop(self);
  g_clear_object(&self->registrar);
  g_free(self);
}
