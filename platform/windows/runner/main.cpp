// Pusula Browser — Windows giriş noktası (flutter create şablonundan, scripts/platform_hazirla.sh kopyalar).
// Ek olarak: tek pencere. Pusula zaten açıksa (ör. başka bir uygulamada bir bağlantıya
// tıklanınca) yeni pencere açılmaz; adres açık pencereye gönderilir ve orada yeni sekmede açılır.
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>
#include <vector>

#include "crash_log.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kMutexName[] = L"Local\\OATarayici_TekPencere";
constexpr const wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"Pusula Browser";

// Açık pencereyi bulup komut satırını ona gönderir. Gönderebildiyse true.
bool SendToRunningInstance(const std::vector<std::string>& args) {
  std::string joined;
  for (const auto& a : args) {
    if (!joined.empty()) joined += "\n";
    joined += a;
  }
  // İlk pencere henüz açılıyor olabilir: kısa bir süre bekle.
  for (int i = 0; i < 50; i++) {
    HWND hwnd = ::FindWindowW(kWindowClass, kWindowTitle);
    if (hwnd) {
      COPYDATASTRUCT cds;
      cds.dwData = kOACopyDataId;
      cds.cbData = static_cast<DWORD>(joined.size());
      cds.lpData = joined.empty() ? nullptr : const_cast<char*>(joined.data());
      DWORD_PTR res = 0;
      ::SendMessageTimeoutW(hwnd, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&cds),
                            SMTO_ABORTIFHUNG, 3000, &res);
      if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
      ::SetForegroundWindow(hwnd);
      return true;
    }
    ::Sleep(100);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();

  HANDLE mutex = ::CreateMutexW(nullptr, TRUE, kMutexName);
  if (mutex && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    if (SendToRunningInstance(command_line_arguments)) {
      ::CloseHandle(mutex);
      return EXIT_SUCCESS;
    }
    // Açık pencere bulunamadıysa normal şekilde açıl.
  }

  // Beklenmedik kapanmaların nedeni %LOCALAPPDATA%\OA Tarayici\cokme.txt dosyasına yazılır.
  InstallCrashLog();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1360, 860);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (mutex) ::CloseHandle(mutex);
  return EXIT_SUCCESS;
}
