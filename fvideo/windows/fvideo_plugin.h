#ifndef FLUTTER_PLUGIN_FVIDEO_PLUGIN_H_
#define FLUTTER_PLUGIN_FVIDEO_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace fvideo {

class FvideoPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  FvideoPlugin();

  virtual ~FvideoPlugin();

  // Disallow copy and assign.
  FvideoPlugin(const FvideoPlugin&) = delete;
  FvideoPlugin& operator=(const FvideoPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace fvideo

#endif  // FLUTTER_PLUGIN_FVIDEO_PLUGIN_H_
