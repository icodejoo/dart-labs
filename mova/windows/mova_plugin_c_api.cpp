#include "include/mova/mova_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "mova_plugin.h"

void MovaPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  mova::MovaPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
