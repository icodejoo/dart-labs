#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  if (LuckdrawTestWindow()) {
    test_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
        flutter_controller_->engine()->messenger(), "luckdraw/test_window",
        &flutter::StandardMethodCodec::GetInstance());
    test_channel_->SetMethodCallHandler(
        [this](const auto& call, auto result) {
          if (call.method_name() == "resize") {
            const auto* width = std::get_if<int32_t>(call.arguments());
            if (!width || *width < 240 || *width > 480) {
              result->Error("invalid_size", "测试窗口宽度须在 240 到 480 之间");
              return;
            }
            SetWindowPos(GetHandle(), nullptr, 0, 0, *width, 720,
                         SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
          } else if (call.method_name() != "inspect") {
            result->NotImplemented();
            return;
          }
          RECT frame;
          GetWindowRect(GetHandle(), &frame);
          flutter::EncodableMap state;
          state[flutter::EncodableValue("width")] =
              flutter::EncodableValue(static_cast<int32_t>(frame.right - frame.left));
          state[flutter::EncodableValue("height")] =
              flutter::EncodableValue(static_cast<int32_t>(frame.bottom - frame.top));
          state[flutter::EncodableValue("foreground")] =
              flutter::EncodableValue(GetForegroundWindow() == GetHandle());
          result->Success(flutter::EncodableValue(state));
        });
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  test_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
