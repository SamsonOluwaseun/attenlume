//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <audio_decoder/audio_decoder_plugin_c_api.h>
#include <audioplayers_windows/audioplayers_windows_plugin.h>
#include <camera_windows/camera_windows.h>
#include <file_selector_windows/file_selector_windows.h>
#include <flutter_timezone/flutter_timezone_plugin_c_api.h>
#include <flutter_whisper_ggml/flutter_whisper_plugin_c_api.h>
#include <local_auth_windows/local_auth_plugin.h>
#include <record_windows/record_windows_plugin_c_api.h>
#include <share_plus/share_plus_windows_plugin_c_api.h>
#include <url_launcher_windows/url_launcher_windows.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  AudioDecoderPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioDecoderPluginCApi"));
  AudioplayersWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("AudioplayersWindowsPlugin"));
  CameraWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("CameraWindows"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  FlutterTimezonePluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterTimezonePluginCApi"));
  FlutterWhisperPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterWhisperPluginCApi"));
  LocalAuthPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("LocalAuthPlugin"));
  RecordWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("RecordWindowsPluginCApi"));
  SharePlusWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("SharePlusWindowsPluginCApi"));
  UrlLauncherWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("UrlLauncherWindows"));
}
