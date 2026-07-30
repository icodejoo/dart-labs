#include "include/fvideo/fvideo_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "fvideo_plugin.h"

void FvideoPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  fvideo::FvideoPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
