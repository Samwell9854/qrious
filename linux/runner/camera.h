#ifndef RUNNER_CAMERA_H_
#define RUNNER_CAMERA_H_

#include <flutter_linux/flutter_linux.h>

// The webcam, captured with GStreamer and answering the "qrious/camera" channel
// (lib/webcam.dart has the method table and the error codes).
typedef struct _QriousCamera QriousCamera;

// [registrar] gets the preview texture; [channel] is where "error" is sent when
// capture stops by itself. Both must outlive the camera.
QriousCamera* qrious_camera_new(FlTextureRegistrar* registrar,
                                FlMethodChannel* channel);

// Answers [method_call], now or, for "start", once the first frame has arrived.
void qrious_camera_handle(QriousCamera* self, FlMethodCall* method_call);

// Stops capturing and releases the device and the texture. Safe when idle.
void qrious_camera_stop(QriousCamera* self);

// Stops, then frees. Call before the channel and the registrar go away.
void qrious_camera_free(QriousCamera* self);

#endif  // RUNNER_CAMERA_H_
