#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <propkey.h>
#include <propvarutil.h>
#include <shlguid.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// App User Model ID shared with the local_notifier setup (appName) so that the
// toast path and the taskbar grouping resolve to the same registration.
constexpr const wchar_t kAppUserModelId[] = L"neu_better_pro";

// Returns the full path of the running executable.
std::wstring CurrentExecutablePath() {
  wchar_t buffer[MAX_PATH] = {0};
  const DWORD written = ::GetModuleFileNameW(nullptr, buffer, MAX_PATH);
  return std::wstring(buffer, written);
}

// Ensures a Start Menu shortcut exists whose target is this executable, whose
// icon is this executable's embedded app icon, and whose AppUserModelID matches
// kAppUserModelId. Windows resolves a taskbar button's icon from the AUMID
// registration; a stale or missing shortcut (for example one left pointing at
// another exe with no icon) makes the taskbar fall back to a generic blank
// document icon even though the window's own WM_SETICON is correct. This must
// run before any window is shown.
void EnsureStartMenuShortcut() {
  const std::wstring exe_path = CurrentExecutablePath();
  if (exe_path.empty()) {
    return;
  }

  wchar_t appdata[MAX_PATH] = {0};
  const DWORD appdata_len =
      ::GetEnvironmentVariableW(L"APPDATA", appdata, MAX_PATH);
  if (appdata_len == 0 || appdata_len >= MAX_PATH) {
    return;
  }

  const std::wstring link_path = std::wstring(appdata) +
      L"\\Microsoft\\Windows\\Start Menu\\Programs\\neu_better_pro.lnk";

  std::wstring working_dir = exe_path;
  const size_t slash = working_dir.find_last_of(L"\\/");
  if (slash != std::wstring::npos) {
    working_dir.erase(slash);
  }

  IShellLinkW* shell_link = nullptr;
  HRESULT hr = ::CoCreateInstance(
      CLSID_ShellLink, nullptr, CLSCTX_INPROC_SERVER, IID_IShellLinkW,
      reinterpret_cast<void**>(&shell_link));
  if (FAILED(hr) || shell_link == nullptr) {
    return;
  }

  shell_link->SetPath(exe_path.c_str());
  shell_link->SetArguments(L"");
  shell_link->SetWorkingDirectory(working_dir.c_str());
  // Use the exe's own embedded app icon (frame 0) so the taskbar shows the
  // project logo rather than a blank document glyph.
  shell_link->SetIconLocation(exe_path.c_str(), 0);
  shell_link->SetDescription(L"NEU Better");

  IPropertyStore* property_store = nullptr;
  hr = shell_link->QueryInterface(IID_IPropertyStore,
                                  reinterpret_cast<void**>(&property_store));
  if (SUCCEEDED(hr) && property_store != nullptr) {
    PROPVARIANT prop;
    ::PropVariantInit(&prop);
    if (SUCCEEDED(::InitPropVariantFromString(kAppUserModelId, &prop))) {
      property_store->SetValue(PKEY_AppUserModel_ID, prop);
      property_store->Commit();
    }
    ::PropVariantClear(&prop);
    property_store->Release();
  }

  IPersistFile* persist_file = nullptr;
  hr = shell_link->QueryInterface(IID_IPersistFile,
                                  reinterpret_cast<void**>(&persist_file));
  if (SUCCEEDED(hr) && persist_file != nullptr) {
    persist_file->Save(link_path.c_str(), TRUE);
    persist_file->Release();
  }

  shell_link->Release();
}

}  // namespace

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

  // Register a stable AppUserModelID and a matching Start Menu shortcut before
  // any window exists. This is what lets the taskbar button show the app's own
  // icon (instead of a generic blank document) and is also required for Windows
  // toast notifications to be delivered.
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
  EnsureStartMenuShortcut();

  flutter::DartProject project(L"data");

  // This machine carries several virtual display adapters (Sunlogin/Oray,
  // ToDesk, MuMu, GameViewer) that DXGI can enumerate before the real GPU;
  // when the engine picks one of them, frames render into an adapter that
  // never reaches the physical screen and the window stays blank. Request the
  // high-performance (discrete) adapter explicitly.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);

  // Default window size in logical (DPI-independent) pixels.
  double logical_width = 1280.0;
  double logical_height = 800.0;
  double origin_x = 10.0;
  double origin_y = 10.0;

  // Center the window inside the primary monitor's work area. Work-area and
  // window metrics are physical pixels here, so divide back by the DPI scale
  // before handing the (logical) origin/size to Win32Window::Create, which
  // multiplies them by that same scale factor.
  RECT work_area = {0, 0, 0, 0};
  if (::SystemParametersInfoW(SPI_GETWORKAREA, 0, &work_area, 0)) {
    const int work_width = work_area.right - work_area.left;
    const int work_height = work_area.bottom - work_area.top;
    if (work_width > 0 && work_height > 0) {
      UINT dpi = ::GetDpiForSystem();
      if (dpi == 0) {
        dpi = 96;
      }
      const double scale = dpi / 96.0;

      // Do not exceed the work area (leave a small margin on small screens).
      const int margin = static_cast<int>(40 * scale);
      int window_px_w = static_cast<int>(logical_width * scale);
      int window_px_h = static_cast<int>(logical_height * scale);
      if (window_px_w > work_width - margin) {
        window_px_w = work_width - margin;
      }
      if (window_px_h > work_height - margin) {
        window_px_h = work_height - margin;
      }
      if (window_px_w > 0 && window_px_h > 0) {
        logical_width = window_px_w / scale;
        logical_height = window_px_h / scale;
        const int centered_px_x =
            work_area.left + (work_width - window_px_w) / 2;
        const int centered_px_y =
            work_area.top + (work_height - window_px_h) / 2;
        origin_x = centered_px_x / scale;
        origin_y = centered_px_y / scale;
      }
    }
  }

  Win32Window::Point origin(static_cast<unsigned int>(origin_x),
                            static_cast<unsigned int>(origin_y));
  Win32Window::Size size(static_cast<unsigned int>(logical_width),
                         static_cast<unsigned int>(logical_height));
  if (!window.Create(L"NEU Better", origin, size)) {
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
