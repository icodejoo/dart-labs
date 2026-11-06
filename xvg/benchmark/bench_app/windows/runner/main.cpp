#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Quiet by default so benchmark/test runs never steal the user's desktop
  // focus; set XVG_WIN_INTERACTIVE=1 to get the original 1280x720 window back.
  // 默认安静：基准/测试不得抢用户桌面焦点；手工调试时设
  // XVG_WIN_INTERACTIVE=1 恢复原来的 1280x720 普通窗口。
  wchar_t interactive_flag[8] = {0};
  const bool interactive =
      ::GetEnvironmentVariableW(L"XVG_WIN_INTERACTIVE", interactive_flag,
                                8) > 0 &&
      interactive_flag[0] == L'1';
  window.SetQuiet(!interactive);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(interactive ? 1280 : 640, interactive ? 720 : 360);
  if (!window.Create(L"bench_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
