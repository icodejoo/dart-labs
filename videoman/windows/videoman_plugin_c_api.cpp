#include "include/videoman/videoman_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "videoman_plugin.h"

void VideomanPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  videoman::VideomanPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
