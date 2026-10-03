#include "session_end.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace {

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_channel;
bool g_notified = false;

}  // namespace

void RegisterSessionEndChannel(flutter::BinaryMessenger* messenger) {
  g_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "umbra_tags/session",
      &flutter::StandardMethodCodec::GetInstance());
}

void NotifySessionEnding() {
  if (!g_channel || g_notified) return;
  g_notified = true;
  g_channel->InvokeMethod("endSession", nullptr);
}
