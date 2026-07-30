#ifndef FLUTTER_PLUGIN_VIDEOMAN_PLUGIN_H_
#define FLUTTER_PLUGIN_VIDEOMAN_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>

namespace videoman {

class VideomanPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  VideomanPlugin();

  virtual ~VideomanPlugin();

  // Disallow copy and assign.
  VideomanPlugin(const VideomanPlugin&) = delete;
  VideomanPlugin& operator=(const VideomanPlugin&) = delete;

  // Called when a method is called on this plugin's channel from Dart.
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

}  // namespace videoman

#endif  // FLUTTER_PLUGIN_VIDEOMAN_PLUGIN_H_
