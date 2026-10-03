#ifndef RUNNER_SESSION_END_H_
#define RUNNER_SESSION_END_H_

#include <flutter/binary_messenger.h>

// Registers the "umbra_tags/session" channel used to tell Dart that Windows
// is ending the session or an installer is closing the app (Restart Manager),
// so it quits for real instead of minimizing to the tray.
void RegisterSessionEndChannel(flutter::BinaryMessenger* messenger);

// Sends "endSession" to Dart once.
void NotifySessionEnding();

#endif  // RUNNER_SESSION_END_H_
