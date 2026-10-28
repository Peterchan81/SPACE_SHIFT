#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"
#include "app_links/app_links_plugin_c_api.h"

namespace {

// SS002 §5(2026-10-28 #2 후속 지시) — 이메일 인증 메일의 콜백 링크
// (io.spaceshift.app://login-callback?...)를 Windows에서 열 수 있도록,
// 앱이 뜰 때마다 현재 실행 파일 경로로
// HKEY_CURRENT_USER\Software\Classes\io.spaceshift.app 아래에 URL
// 프로토콜을 등록한다. 관리자 권한이 필요 없는 사용자별(HKCU) 등록이라
// 설치 프로그램 없이도 매 실행마다 최신 exe 경로로 갱신된다. 등록에
// 실패해도(레지스트리 쓰기 권한이 없는 제한된 환경 등) 앱 실행 자체는
// 막지 않는다 — 그 경우 이 기기에서 메일 링크로 자동 복귀만 되지 않을
// 뿐, 앱에서 직접 로그인은 그대로 가능하다.
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
  // SS002 §5(2026-10-28 #2 후속 지시) — 이미 떠 있는 SPACE SHIFT 창이 있으면
  // 이번에 OS가 넘긴 링크(인증 메일의 콜백 URL 등)를 그 창으로 보내고 이번
  // 프로세스는 바로 종료한다 — 설치된 app_links 패키지의 Windows 안내
  // (example/windows/runner/main.cpp)를 그대로 따른다.
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
