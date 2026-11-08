#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

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
  single_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "oa/tek_pencere",
      &flutter::StandardMethodCodec::GetInstance());
  single_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "tamEkran") {
          const auto* on = std::get_if<bool>(call.arguments());
          SetFullscreen(on != nullptr && *on);
          result->Success();
        } else if (call.method_name() == "cik") {
          // Güncelleme kurulurken: oturum Dart tarafında kaydedildi, süreç hemen kapanır.
          SavePlacement();
          result->Success();
          ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->RestorePlacementAndShow();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

namespace {
constexpr const wchar_t kPlacementKey[] = L"Software\\OATarayici";
constexpr const wchar_t kPlacementValue[] = L"Pencere";
}  // namespace

void FlutterWindow::SavePlacement() {
  HWND hwnd = GetHandle();
  if (!hwnd) return;
  // Küçük video penceresi (her zaman üstte) kaydedilmez; normal boyut korunur.
  if (::GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOPMOST) return;
  WINDOWPLACEMENT wp{};
  wp.length = sizeof(wp);
  if (fullscreen_) {
    wp = saved_placement_;
  } else if (!::GetWindowPlacement(hwnd, &wp)) {
    return;
  }
  if (wp.showCmd == SW_SHOWMINIMIZED || wp.showCmd == SW_MINIMIZE) {
    wp.showCmd = (wp.flags & WPF_RESTORETOMAXIMIZED) ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  }
  ::RegSetKeyValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue, REG_BINARY, &wp,
                    sizeof(wp));
}

void FlutterWindow::RestorePlacementAndShow() {
  HWND hwnd = GetHandle();
  WINDOWPLACEMENT wp{};
  DWORD size = sizeof(wp);
  if (hwnd &&
      ::RegGetValueW(HKEY_CURRENT_USER, kPlacementKey, kPlacementValue, RRF_RT_REG_BINARY,
                     nullptr, &wp, &size) == ERROR_SUCCESS &&
      size == sizeof(wp) && wp.length == sizeof(wp)) {
    RECT r = wp.rcNormalPosition;
    // Ekran çıkarıldıysa (ikinci monitör) pencere görünmez yerde açılmasın
    if (r.right - r.left >= 300 && r.bottom - r.top >= 200 &&
        ::MonitorFromRect(&r, MONITOR_DEFAULTTONULL) != nullptr) {
      wp.flags = 0;
      if (wp.showCmd != SW_SHOWMAXIMIZED) wp.showCmd = SW_SHOWNORMAL;
      ::SetWindowPlacement(hwnd, &wp);
      return;
    }
  }
  Show();
}

void FlutterWindow::SetFullscreen(bool on) {
  HWND hwnd = GetHandle();
  if (!hwnd || on == fullscreen_) return;
  if (on) {
    saved_style_ = ::GetWindowLong(hwnd, GWL_STYLE);
    saved_placement_.length = sizeof(WINDOWPLACEMENT);
    ::GetWindowPlacement(hwnd, &saved_placement_);
    MONITORINFO mi{};
    mi.cbSize = sizeof(mi);
    ::GetMonitorInfo(::MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &mi);
    ::SetWindowLong(hwnd, GWL_STYLE, saved_style_ & ~WS_OVERLAPPEDWINDOW);
    ::SetWindowPos(hwnd, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top,
                   mi.rcMonitor.right - mi.rcMonitor.left,
                   mi.rcMonitor.bottom - mi.rcMonitor.top,
                   SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ::SetWindowLong(hwnd, GWL_STYLE, saved_style_);
    ::SetWindowPlacement(hwnd, &saved_placement_);
    ::SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  fullscreen_ = on;
}

void FlutterWindow::OnDestroy() {
  single_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // İkinci açılıştan gelen komut satırı (UTF-8, satır satır).
  if (message == WM_COPYDATA) {
    auto cds = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (cds && cds->dwData == kOACopyDataId) {
      std::string args;
      if (cds->lpData && cds->cbData > 0) {
        args.assign(static_cast<const char*>(cds->lpData), cds->cbData);
      }
      if (single_channel_) {
        single_channel_->InvokeMethod(
            "ac", std::make_unique<flutter::EncodableValue>(args));
      }
      return TRUE;
    }
  }

  if (message == WM_CLOSE) SavePlacement();

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
