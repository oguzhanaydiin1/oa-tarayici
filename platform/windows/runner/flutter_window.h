#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// İkinci açılışın komut satırını ilk pencereye taşıyan WM_COPYDATA mesajının kimliği ("OA").
constexpr ULONG_PTR kOACopyDataId = 0x4F41;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "oa/tek_pencere": ikinci açılıştan gelen adresler Dart'a buradan iletilir; Dart da tam ekranı
  // buradan ister ("tamEkran").
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> single_channel_;

  // Video tam ekranı: başlık çubuğu ve kenarlıklar kalkar, pencere bütün ekranı kaplar.
  void SetFullscreen(bool on);
  bool fullscreen_ = false;
  LONG saved_style_ = 0;
  WINDOWPLACEMENT saved_placement_{};
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
