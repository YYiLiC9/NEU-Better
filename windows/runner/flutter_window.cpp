#include "flutter_window.h"

#include <cwchar>
#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "flutter/method_channel.h"
#include "flutter/standard_method_codec.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;

// Tray right-click menu command identifiers.
constexpr UINT kTrayShowCommand = 1001;
constexpr UINT kTrayExitCommand = 1002;

// Menu labels. Written as \u escapes (show / exit) so they render correctly
// regardless of the source file's encoding under MSVC.
constexpr const wchar_t kTrayShowLabel[] = L"\u663e\u793a";
constexpr const wchar_t kTrayExitLabel[] = L"\u9000\u51fa";

// Loads the app icon as an HICON of the requested size. LoadImageW can fail
// (return null) when the ICO lacks a matching frame, so fall back to the
// default full-size icon before giving up.
HICON LoadAppIcon(int width, int height) {
  HICON icon = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      width, height, LR_DEFAULTCOLOR | LR_SHARED));
  if (icon == nullptr) {
    icon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  }
  return icon;
}

// Converts a UTF-8 string into a UTF-16 wide string for Win32 APIs.
std::wstring Utf8ToWide(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }

  const int size = MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                       static_cast<int>(utf8.size()), nullptr,
                                       0);
  if (size <= 0) {
    return std::wstring();
  }

  std::wstring wide(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      wide.data(), size);
  return wide;
}

}  // namespace

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

  // Expose a small window-control API to Dart.
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "neu_better/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setTitle") {
          const auto* title = std::get_if<std::string>(call.arguments());
          if (title == nullptr) {
            result->Error("invalid_arguments", "setTitle expects a string");
            return;
          }
          const std::wstring wide_title = Utf8ToWide(*title);
          SetWindowTextW(GetHandle(), wide_title.c_str());
          result->Success();
          return;
        }

        if (call.method_name() == "setTrayTooltip") {
          const auto* tooltip = std::get_if<std::string>(call.arguments());
          if (tooltip == nullptr) {
            result->Error("invalid_arguments",
                          "setTrayTooltip expects a string");
            return;
          }
          UpdateTrayTooltip(Utf8ToWide(*tooltip));
          result->Success();
          return;
        }

        if (call.method_name() == "setCloseBehavior") {
          const auto* minimize = std::get_if<bool>(call.arguments());
          if (minimize == nullptr) {
            result->Error("invalid_arguments",
                          "setCloseBehavior expects a bool");
            return;
          }
          minimize_on_close_ = *minimize;
          result->Success();
          return;
        }

        if (call.method_name() == "setTrayIconVisible") {
          const auto* visible = std::get_if<bool>(call.arguments());
          if (visible == nullptr) {
            result->Error("invalid_arguments",
                          "setTrayIconVisible expects a bool");
            return;
          }
          show_tray_icon_ = *visible;
          if (show_tray_icon_) {
            AddTrayIcon();
          } else {
            RemoveTrayIcon();
          }
          result->Success();
          return;
        }

        result->NotImplemented();
      });

  AddTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::AddTrayIcon() {
  if (tray_icon_added_ || !show_tray_icon_) {
    return;
  }

  tray_icon_data_.cbSize = sizeof(tray_icon_data_);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon = LoadAppIcon(16, 16);
  if (tray_icon_data_.hIcon == nullptr) {
    // Retry once with the 32x32 frame; the tray scales it down.
    tray_icon_data_.hIcon = LoadAppIcon(32, 32);
  }
  // Short, stable tooltip; Dart replaces it with a concise electricity hint
  // (e.g. "dorm power 49 kWh") once the prefs are loaded.
  wcsncpy_s(tray_icon_data_.szTip, 128, L"NEU Better", _TRUNCATE);
  // Clear any phantom entry left by a force-killed instance or a failed
  // add before registering; NIM_DELETE on a missing entry is a no-op.
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) != FALSE;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) {
    return;
  }
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

void FlutterWindow::UpdateTrayTooltip(const std::wstring& tooltip) {
  wcsncpy_s(tray_icon_data_.szTip, 128, tooltip.c_str(), _TRUNCATE);
  if (tray_icon_added_) {
    tray_icon_data_.uFlags = NIF_TIP;
    Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_);
  }
}

void FlutterWindow::ShowTrayMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) {
    return;
  }
  AppendMenuW(menu, MF_STRING, kTrayShowCommand, kTrayShowLabel);
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, kTrayExitLabel);

  POINT cursor;
  GetCursorPos(&cursor);
  // SetForegroundWindow is required so the popup dismisses when the user
  // clicks elsewhere (standard Win32 tray-menu workaround).
  SetForegroundWindow(hwnd);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON, cursor.x, cursor.y,
      0, hwnd, nullptr);
  PostMessage(hwnd, WM_NULL, 0, 0);
  DestroyMenu(menu);

  if (command == kTrayShowCommand) {
    ShowWindow(hwnd, SW_RESTORE);
    SetForegroundWindow(hwnd);
  } else if (command == kTrayExitCommand) {
    // Quit even when the close button would normally hide to the tray: clear
    // the minimize flag and post WM_CLOSE so the normal teardown runs.
    minimize_on_close_ = false;
    PostMessage(hwnd, WM_CLOSE, 0, 0);
  }
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon();
  window_channel_ = nullptr;

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // explorer.exe rebuilds the taskbar (after a restart or a crash) and
  // broadcasts TaskbarCreated, which invalidates the old tray icon.
  // Re-add it so the tray entry self-heals.
  static const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
  if (message == kTaskbarCreated) {
    if (tray_icon_added_) {
      RemoveTrayIcon();
    }
    AddTrayIcon();
    // Fall through so Flutter plugins can react to the message too.
  }

  // Clicking the notification-area icon restores the main window; right-click
  // opens the tray menu (show / exit).
  if (message == kTrayCallbackMessage) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu(hwnd);
    }
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  // Closing the window hides it to the notification area instead of quitting
  // while that behavior is enabled (the default; Dart may change it at runtime).
  if (message == WM_CLOSE && minimize_on_close_) {
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
