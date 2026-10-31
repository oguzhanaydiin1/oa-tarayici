#include "crash_log.h"

#include <windows.h>
#include <shlobj.h>

#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>

namespace {

wchar_t g_crash_path[MAX_PATH * 2] = {0};
wchar_t g_first_path[MAX_PATH * 2] = {0};
volatile LONG g_first_count = 0;
volatile LONG g_writing = 0;

// Adresin hangi dosyada (dll/exe) ve dosyanın başından ne kadar ileride olduğu.
void Describe(DWORD64 addr, char* out, size_t n) {
  HMODULE mod = nullptr;
  if (::GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           reinterpret_cast<LPCSTR>(addr), &mod) &&
      mod) {
    char full[MAX_PATH] = "?";
    ::GetModuleFileNameA(mod, full, MAX_PATH);
    const char* name = strrchr(full, '\\');
    name = name ? name + 1 : full;
    _snprintf_s(out, n, _TRUNCATE, "%s+0x%llx", name,
                static_cast<unsigned long long>(addr - reinterpret_cast<DWORD64>(mod)));
  } else {
    _snprintf_s(out, n, _TRUNCATE, "0x%llx", static_cast<unsigned long long>(addr));
  }
}

void Append(char* buf, size_t cap, size_t* len, const char* s) {
  size_t l = strlen(s);
  if (*len + l + 1 >= cap) return;
  memcpy(buf + *len, s, l);
  *len += l;
  buf[*len] = 0;
}

#if defined(_M_X64)
// Çağrı yığını (x64): her adımda dönüş adresini bulur.
void Walk(CONTEXT ctx, char* buf, size_t cap, size_t* len) {
  __try {
    for (int i = 0; i < 40 && ctx.Rip; i++) {
      char line[400];
      char d[360];
      Describe(ctx.Rip, d, sizeof d);
      _snprintf_s(line, sizeof line, _TRUNCATE, "  %s\r\n", d);
      Append(buf, cap, len, line);
      DWORD64 image_base = 0;
      PRUNTIME_FUNCTION fe = ::RtlLookupFunctionEntry(ctx.Rip, &image_base, nullptr);
      if (!fe) {
        ctx.Rip = *reinterpret_cast<DWORD64*>(ctx.Rsp);
        ctx.Rsp += 8;
      } else {
        PVOID handler_data = nullptr;
        DWORD64 establisher = 0;
        ::RtlVirtualUnwind(UNW_FLAG_NHANDLER, image_base, ctx.Rip, fe, &ctx,
                           &handler_data, &establisher, nullptr);
      }
    }
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    Append(buf, cap, len, "  (yığın burada okunamadı)\r\n");
  }
}
#endif

void Write(const wchar_t* path, const char* kind, DWORD code, const CONTEXT* ctx) {
  if (!path[0]) return;
  if (::InterlockedExchange(&g_writing, 1) == 1) return;
  static char buf[16384];
  size_t len = 0;
  buf[0] = 0;
  SYSTEMTIME t;
  ::GetLocalTime(&t);
  char line[512];
  _snprintf_s(line, sizeof line, _TRUNCATE,
              "%04d-%02d-%02d %02d:%02d:%02d\r\n%s\r\nkod: 0x%08lx\r\niş parçacığı: %lu\r\n",
              t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, kind,
              static_cast<unsigned long>(code), ::GetCurrentThreadId());
  Append(buf, sizeof buf, &len, line);
#if defined(_M_X64)
  if (ctx) {
    char d[360];
    Describe(ctx->Rip, d, sizeof d);
    _snprintf_s(line, sizeof line, _TRUNCATE, "yer: %s\r\nyığın:\r\n", d);
    Append(buf, sizeof buf, &len, line);
    Walk(*ctx, buf, sizeof buf, &len);
  }
#endif
  HANDLE f = ::CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f != INVALID_HANDLE_VALUE) {
    DWORD w = 0;
    ::WriteFile(f, buf, static_cast<DWORD>(len), &w, nullptr);
    ::FlushFileBuffers(f);
    ::CloseHandle(f);
  }
  ::InterlockedExchange(&g_writing, 0);
}

bool IsFatalCode(DWORD c) {
  switch (c) {
    case EXCEPTION_ACCESS_VIOLATION:
    case EXCEPTION_ILLEGAL_INSTRUCTION:
    case EXCEPTION_PRIV_INSTRUCTION:
    case EXCEPTION_STACK_OVERFLOW:
    case EXCEPTION_INT_DIVIDE_BY_ZERO:
    case EXCEPTION_IN_PAGE_ERROR:
    case 0xC0000374:  // yığın (heap) bozulması
    case 0xC0000409:  // güvenlik denetimi
      return true;
    default:
      return false;
  }
}

// İlk şans: başka bir bileşen kendi işleyicisini kursa da hata buradan geçer.
LONG CALLBACK FirstChance(EXCEPTION_POINTERS* ep) {
  if (ep && ep->ExceptionRecord && IsFatalCode(ep->ExceptionRecord->ExceptionCode) &&
      ::InterlockedIncrement(&g_first_count) <= 20) {
    Write(g_first_path, "ilk şans hatası (uygulama bunu yakalamış da olabilir)",
          ep->ExceptionRecord->ExceptionCode, ep->ContextRecord);
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

LONG WINAPI Unhandled(EXCEPTION_POINTERS* ep) {
  Write(g_crash_path, "yakalanmamış hata: uygulama kapandı",
        ep && ep->ExceptionRecord ? ep->ExceptionRecord->ExceptionCode : 0,
        ep ? ep->ContextRecord : nullptr);
  return EXCEPTION_CONTINUE_SEARCH;
}

void WriteHere(const char* kind) {
  CONTEXT ctx;
  ::RtlCaptureContext(&ctx);
  Write(g_crash_path, kind, 0, &ctx);
}

void OnAbort(int) { WriteHere("abort(): uygulama kendini durdurdu"); }

void OnTerminate() {
  WriteHere("std::terminate: yakalanmamış C++ hatası");
  std::abort();
}

void OnPureCall() { WriteHere("pure virtual call"); }

}  // namespace

void InstallCrashLog() {
  PWSTR base = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &base)) || !base) return;
  wchar_t dir[MAX_PATH * 2];
  _snwprintf_s(dir, _countof(dir), _TRUNCATE, L"%s\\OA Tarayici", base);
  ::CoTaskMemFree(base);
  ::CreateDirectoryW(dir, nullptr);
  _snwprintf_s(g_crash_path, _countof(g_crash_path), _TRUNCATE, L"%s\\cokme.txt", dir);
  _snwprintf_s(g_first_path, _countof(g_first_path), _TRUNCATE, L"%s\\son_hata.txt", dir);
  ::DeleteFileW(g_first_path);  // bu oturumun ilk şans kaydı temiz başlasın

  ::AddVectoredExceptionHandler(1, FirstChance);
  ::SetUnhandledExceptionFilter(Unhandled);
  signal(SIGABRT, OnAbort);
  std::set_terminate(OnTerminate);
  _set_purecall_handler(OnPureCall);
}
