#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayMessage = WM_APP + 21;
constexpr UINT kRestore = 1;
constexpr UINT kQuit = 2;
std::wstring StatusText(const std::string& state) {
  if (state == "recording") return L"LIVE - recording";
  if (state == "paused") return L"Paused";
  if (state == "saved") return L"Saved";
  if (state == "idle") return L"Ready";
  if (state == "stopping" || state == "storageStop") return L"Saving";
  if (state == "errorRecoverable") return L"Recording needs attention";
  if (state == "interrupted" || state == "userResumeRequired")
    return L"Interrupted - open Attenlume";
  return L"Recording in progress";
}
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}
FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  lifecycle_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.samlytics.attenlume/windows_lifecycle",
      &flutter::StandardMethodCodec::GetInstance());
  lifecycle_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "status") {
      const auto* map = call.arguments()
          ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (!map) { result->Error("arguments", "Missing status"); return; }
      auto held = map->find(flutter::EncodableValue("held"));
      auto state = map->find(flutter::EncodableValue("state"));
      if (held == map->end() || state == map->end() ||
          !std::holds_alternative<bool>(held->second) ||
          !std::holds_alternative<std::string>(state->second)) {
        result->Error("arguments", "Invalid status"); return;
      }
      recorder_held_ = std::get<bool>(held->second);
      status_ = StatusText(std::get<std::string>(state->second));
      bridge_ready_ = true;
      UpdateTray();
      result->Success();
    } else if (call.method_name() == "quit") {
      // Only Dart's verified save route can authorise window destruction.
      if (recorder_held_) {
        result->Error("recording_open", "Recording still needs saving");
        return;
      }
      allow_close_ = true;
      result->Success();
      PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else if (call.method_name() == "saveFailed") {
      ShutdownBlockReasonDestroy(GetHandle());
      EnableWindow(GetHandle(), TRUE);
      RestoreWindow();
      MessageBox(GetHandle(),
          L"Your recording could not be saved. Attenlume will stay open. "
          L"Check the recording screen and available storage, then try again. "
          L"Existing audio files have been kept.",
          L"Attenlume - recording needs attention", MB_OK | MB_ICONWARNING);
      result->Success();
    } else { result->NotImplemented(); }
  });
  taskbar_created_ = RegisterWindowMessage(L"TaskbarCreated");
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle();
  tray_.uID = 1;
  tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_.uCallbackMessage = kTrayMessage;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  UpdateTray();
  flutter_controller_->engine()->SetNextFrameCallback([this]() { Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::UpdateTray() {
  const auto tip = L"Attenlume - " + status_;
  wcsncpy_s(tray_.szTip, tip.c_str(), _TRUNCATE);
  if (tray_added_ && Shell_NotifyIcon(NIM_MODIFY, &tray_)) return;
  tray_added_ = Shell_NotifyIcon(NIM_ADD, &tray_) != FALSE;
  if (tray_added_) {
    tray_.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIcon(NIM_SETVERSION, &tray_);
  }
}

void FlutterWindow::RestoreWindow() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}

void FlutterWindow::RequestQuit() {
  if (!bridge_ready_ || !lifecycle_) {
    RestoreWindow();
    MessageBox(GetHandle(), L"Attenlume is starting. Please try again shortly.",
               L"Attenlume", MB_OK | MB_ICONINFORMATION);
    return;
  }
  EnableWindow(GetHandle(), FALSE);
  lifecycle_->InvokeMethod("saveAndQuit", nullptr);
}

void FlutterWindow::TrayMenu() {
  HMENU menu = CreatePopupMenu();
  if (!menu) { RestoreWindow(); return; }
  AppendMenu(menu, MF_STRING | MF_DISABLED, 0, status_.c_str());
  AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenu(menu, MF_STRING, kRestore, L"Open Attenlume");
  AppendMenu(menu, MF_STRING, kQuit,
             recorder_held_ ? L"Stop, save and quit" : L"Quit Attenlume");
  POINT point;
  GetCursorPos(&point);
  SetForegroundWindow(GetHandle());
  const auto action = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
                                    point.x, point.y, 0, GetHandle(), nullptr);
  DestroyMenu(menu);
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  if (action == kRestore) RestoreWindow();
  if (action == kQuit) RequestQuit();
}

void FlutterWindow::OnDestroy() {
  if (GetHandle()) ShutdownBlockReasonDestroy(GetHandle());
  if (tray_added_) Shell_NotifyIcon(NIM_DELETE, &tray_);
  tray_added_ = false;
  lifecycle_.reset();
  flutter_controller_.reset();
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Handle lifetime before plugins can consume close/shutdown messages.
  if (message == WM_CLOSE && !allow_close_) {
    if (recorder_held_) {
      const int choice = MessageBox(hwnd,
          L"A recording is still open. Keep recording minimises Attenlume; "
          L"the tray menu can reopen it.\n\n"
          L"Yes: stop, save and quit\nNo: keep recording\nCancel: stay here",
          L"Attenlume - save before closing", MB_YESNOCANCEL | MB_ICONQUESTION);
      if (choice == IDYES) RequestQuit();
      if (choice == IDNO) {
        // Always retain the taskbar button, even if Explorer/tray is unavailable.
        ShowWindow(hwnd, SW_MINIMIZE);
      }
    } else { RequestQuit(); }
    return 0;
  }
  if (message == WM_QUERYENDSESSION && !allow_close_) {
    // Never block the UI thread waiting on asynchronous encoder/file writes.
    // Cancel this shutdown attempt; save and quit, then the user can retry it.
    ShutdownBlockReasonCreate(hwnd,
        L"Attenlume is saving your recording. Retry shutdown after it closes.");
    if (bridge_ready_) RequestQuit();
    return FALSE;
  }
  if (message == taskbar_created_ && taskbar_created_ != 0) {
    tray_added_ = false;
    UpdateTray();
    return 0;
  }
  if (message == kTrayMessage) {
    const auto event = LOWORD(lparam);
    if (event == NIN_SELECT || event == NIN_KEYSELECT) RestoreWindow();
    if (event == WM_CONTEXTMENU) TrayMenu();
    return 0;
  }
  if (flutter_controller_) {
    auto result = flutter_controller_->HandleTopLevelWindowProc(
        hwnd, message, wparam, lparam);
    if (result) return *result;
    if (message == WM_FONTCHANGE)
      flutter_controller_->engine()->ReloadSystemFonts();
  }
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
