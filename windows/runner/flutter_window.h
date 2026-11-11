#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <windows.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

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
  // Adds/removes the notification-area icon and updates its hover tooltip.
  void AddTrayIcon();
  void RemoveTrayIcon();
  void UpdateTrayTooltip(const std::wstring& tooltip);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel used by Dart to change the window title or close behavior.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel_;

  // Whether WM_CLOSE hides the window to the notification area instead of
  // quitting. Dart can change this through the "setCloseBehavior" method.
  bool minimize_on_close_ = true;

  // Whether the notification-area icon should be visible. Dart can change this
  // through the "setTrayIconVisible" method.
  bool show_tray_icon_ = true;

  // Notification-area icon state.
  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_icon_added_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
