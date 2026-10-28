#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

namespace {

// SS002 Section 5 (2026-10-28 #2 follow-up instruction) - Register a URL
// protocol under HKEY_CURRENT_USER\Software\Classes\io.spaceshift.app every
// time the app starts, pointing at the current executable path, so that the
// email confirmation link (io.spaceshift.app://login-callback?...) can be
// opened on Windows. This is a per-user (HKCU) registration that does not
// require administrator rights, so it is refreshed with the latest exe path
// on every run without needing an installer. If registration fails (for
// example in a restricted environment without registry write access), the
// app still starts normally - in that case only the automatic return from
// the email link on this machine will not work; signing in directly inside
// the app still works.
void RegisterUrlProtocolForCurrentUser() {
  wchar_t exe_path[MAX_PATH];
  DWORD len = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (len == 0 || len == MAX_PATH) {
    return;
  }

  const wchar_t* kProtocolKeyPath = L"Software\\Classes\\io.spaceshift.app";
  const std::wstring command = L"\"" + std::wstring(exe_path) + L"\" \"%1\"";

  HKEY protocol_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kProtocolKeyPath, 0, nullptr, 0,
                         KEY_WRITE, nullptr, &protocol_key, nullptr) != ERROR_SUCCESS) {
    return;
  }
  const wchar_t kEmptyValue[] = L"";
  ::RegSetValueExW(protocol_key, L"URL Protocol", 0, REG_SZ,
                    reinterpret_cast<const BYTE*>(kEmptyValue),
                    static_cast<DWORD>(sizeof(kEmptyValue)));
  ::RegCloseKey(protocol_key);

  const std::wstring kCommandKeyPath =
      std::wstring(kProtocolKeyPath) + L"\\shell\\open\\command";
  HKEY command_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, kCommandKeyPath.c_str(), 0, nullptr,
                         0, KEY_WRITE, nullptr, &command_key, nullptr) == ERROR_SUCCESS) {
    ::RegSetValueExW(command_key, nullptr, 0, REG_SZ,
                      reinterpret_cast<const BYTE*>(command.c_str()),
                      static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(command_key);
  }
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // SS002 Section 5 (2026-10-28 #2 follow-up instruction) - If a SPACE SHIFT
  // window is already running, forward the link the OS just handed us (for
  // example the email confirmation callback URL) to that window and exit
  // this process immediately - this follows the Windows guidance from the
  // installed app_links package (example/windows/runner/main.cpp) as-is.
  if (SendAppLinkToInstance()) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  RegisterUrlProtocolForCurrentUser();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ason_space", origin, size)) {
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
