// ChuanyunGuard.exe - 穿云 system-proxy guardian (Windows).
//
// 穿云 runs its core inside Chuanyun.exe. In 系统代理 mode Windows (WinINet) points every app at
// 127.0.0.1:<mixed port>. If Chuanyun.exe dies (crash, GPU device loss after sleep, Go fatal
// error, task manager) or its core stops answering while that setting is still in place, the
// whole PC loses internet. This small helper fixes that without depending on the app:
//
//   ChuanyunGuard.exe save    <stateDir> <port>   remember the user's own proxy settings
//                                                 (before 穿云 switches the system proxy on)
//   ChuanyunGuard.exe restore <stateDir> <port> [why]  put them back when 穿云's proxy is set
//   ChuanyunGuard.exe status  <stateDir> <port>   one line: ours=0|1 flags=.. server=.. backup=0|1 restored=0|1
//   ChuanyunGuard.exe apply   <stateDir> <port> <flags> [server] [bypass]   (smoke tests)
//   ChuanyunGuard.exe watch   <stateDir> <port> <pid> [<exe to relaunch>]
//       waits for the app process <pid>; when it is gone and the system proxy still points at
//       穿云 the saved settings are restored at once (direct when nothing was saved). After a
//       crash exit code the app is relaunched (at most 3 times in 30 minutes) so it reconnects.
//       While the app runs, a system proxy that points at a port nobody answers on (SOCKS5
//       greeting, 3 checks 5 s apart) is restored as well.
//
// Exit codes: 0 done / ours, 1 nothing to do / not ours, 2 error.
// Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <wininet.h>
#include <shellapi.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cwctype>
#include <cwchar>
#include <string>
#include <vector>

namespace {

struct ProxyState {
  DWORD flags = PROXY_TYPE_DIRECT;
  std::wstring server;
  std::wstring bypass;
  std::wstring autoconfig;
  bool valid = false;
};

std::wstring g_stateDir;
int g_port = 12334;

std::string ToUtf8(const std::wstring& w) {
  if (w.empty()) return std::string();
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
  std::string s(n, '\0');
  WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr);
  return s;
}

std::wstring FromUtf8(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
  return w;
}

std::wstring PathIn(const wchar_t* name) {
  std::wstring p = g_stateDir;
  if (!p.empty() && p.back() != L'\\' && p.back() != L'/') p += L'\\';
  return p + name;
}

void Log(const std::string& line) {
  std::wstring path = PathIn(L"guard.log");
  WIN32_FILE_ATTRIBUTE_DATA attr;
  if (GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &attr) && attr.nFileSizeLow > 256 * 1024) {
    std::wstring old = PathIn(L"guard.old.log");
    MoveFileExW(path.c_str(), old.c_str(), MOVEFILE_REPLACE_EXISTING);
  }
  HANDLE f = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f == INVALID_HANDLE_VALUE) return;
  SYSTEMTIME t;
  GetLocalTime(&t);
  char head[64];
  snprintf(head, sizeof(head), "%04d-%02d-%02d %02d:%02d:%02d [pid %lu] ", t.wYear, t.wMonth, t.wDay, t.wHour,
           t.wMinute, t.wSecond, GetCurrentProcessId());
  std::string all = std::string(head) + line + "\r\n";
  DWORD written = 0;
  WriteFile(f, all.data(), (DWORD)all.size(), &written, nullptr);
  CloseHandle(f);
}

void Out(const std::string& s) {
  HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
  if (h == nullptr || h == INVALID_HANDLE_VALUE) return;
  std::string line = s + "\n";
  DWORD written = 0;
  WriteFile(h, line.data(), (DWORD)line.size(), &written, nullptr);
}

bool QueryWith(DWORD flagsOption, ProxyState& s) {
  INTERNET_PER_CONN_OPTIONW opts[4] = {};
  opts[0].dwOption = flagsOption;
  opts[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  opts[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  opts[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;  // LAN settings, the ones sing-box sets
  list.dwOptionCount = 4;
  list.pOptions = opts;
  DWORD size = sizeof(list);
  if (!InternetQueryOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size)) return false;
  s.flags = opts[0].Value.dwValue;
  for (int i = 1; i < 4; i++) {
    std::wstring v = opts[i].Value.pszValue ? opts[i].Value.pszValue : L"";
    if (opts[i].Value.pszValue) GlobalFree(opts[i].Value.pszValue);
    if (i == 1) s.server = v;
    if (i == 2) s.bypass = v;
    if (i == 3) s.autoconfig = v;
  }
  s.valid = true;
  return true;
}

bool Query(ProxyState& s) {
  // FLAGS_UI keeps "automatically detect settings" as the user set it (IE8+)
  return QueryWith(INTERNET_PER_CONN_FLAGS_UI, s) || QueryWith(INTERNET_PER_CONN_FLAGS, s);
}

bool ApplyWith(DWORD flagsOption, const ProxyState& s) {
  INTERNET_PER_CONN_OPTIONW opts[4] = {};
  std::wstring server = s.server, bypass = s.bypass, autoconfig = s.autoconfig;
  opts[0].dwOption = flagsOption;
  opts[0].Value.dwValue = s.flags;
  opts[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  opts[1].Value.pszValue = server.empty() ? nullptr : &server[0];
  opts[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  opts[2].Value.pszValue = bypass.empty() ? nullptr : &bypass[0];
  opts[3].dwOption = INTERNET_PER_CONN_AUTOCONFIG_URL;
  opts[3].Value.pszValue = autoconfig.empty() ? nullptr : &autoconfig[0];
  INTERNET_PER_CONN_OPTION_LISTW list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = nullptr;
  list.dwOptionCount = 4;
  list.pOptions = opts;
  if (!InternetSetOptionW(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, sizeof(list))) return false;
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  return true;
}

bool Apply(const ProxyState& s) {
  return ApplyWith(INTERNET_PER_CONN_FLAGS_UI, s) || ApplyWith(INTERNET_PER_CONN_FLAGS, s);
}

std::wstring Lower(std::wstring s) {
  for (auto& c : s) c = (wchar_t)towlower(c);
  return s;
}

bool HostPortIn(const std::wstring& server, const std::wstring& hostPort) {
  size_t pos = 0;
  while ((pos = server.find(hostPort, pos)) != std::wstring::npos) {
    size_t end = pos + hostPort.size();
    if (end >= server.size() || !iswdigit(server[end])) return true;
    pos = end;
  }
  return false;
}

bool PointsAtUs(const ProxyState& s, int port) {
  if (!(s.flags & PROXY_TYPE_PROXY)) return false;
  std::wstring server = Lower(s.server);
  std::wstring p = std::to_wstring(port);
  return HostPortIn(server, L"127.0.0.1:" + p) || HostPortIn(server, L"localhost:" + p) ||
         HostPortIn(server, L"[::1]:" + p);
}

bool Same(const ProxyState& a, const ProxyState& b) {
  return a.flags == b.flags && a.server == b.server && a.bypass == b.bypass && a.autoconfig == b.autoconfig;
}

bool IsDirectOnly(const ProxyState& s) {
  return !(s.flags & PROXY_TYPE_PROXY) && !(s.flags & PROXY_TYPE_AUTO_PROXY_URL);
}

std::string Describe(const ProxyState& s) {
  char head[48];
  snprintf(head, sizeof(head), "flags=0x%lx", s.flags);
  return std::string(head) + " server=" + ToUtf8(s.server) + " bypass=" + ToUtf8(s.bypass) +
         " pac=" + ToUtf8(s.autoconfig);
}

// ---- backup file: proxy-backup.txt, key=value lines (UTF-8) ----

bool ReadStateFile(const wchar_t* name, ProxyState& s) {
  std::wstring path = PathIn(name);
  HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f == INVALID_HANDLE_VALUE) return false;
  std::string data;
  char buf[4096];
  DWORD n = 0;
  while (ReadFile(f, buf, sizeof(buf), &n, nullptr) && n > 0) data.append(buf, n);
  CloseHandle(f);
  bool hasFlags = false;
  size_t start = 0;
  while (start < data.size()) {
    size_t end = data.find('\n', start);
    if (end == std::string::npos) end = data.size();
    std::string line = data.substr(start, end - start);
    if (!line.empty() && line.back() == '\r') line.pop_back();
    size_t eq = line.find('=');
    if (eq != std::string::npos) {
      std::string k = line.substr(0, eq), v = line.substr(eq + 1);
      if (k == "flags") {
        s.flags = (DWORD)strtoul(v.c_str(), nullptr, 0);
        hasFlags = true;
      } else if (k == "server") {
        s.server = FromUtf8(v);
      } else if (k == "bypass") {
        s.bypass = FromUtf8(v);
      } else if (k == "autoconfig") {
        s.autoconfig = FromUtf8(v);
      }
    }
    start = end + 1;
  }
  s.valid = hasFlags;
  return hasFlags;
}

bool WriteStateFile(const wchar_t* name, const ProxyState& s) {
  std::wstring path = PathIn(name);
  std::wstring tmp = path + L".tmp";
  char flags[32];
  snprintf(flags, sizeof(flags), "0x%lx", s.flags);
  std::string data = std::string("flags=") + flags + "\nserver=" + ToUtf8(s.server) + "\nbypass=" +
                     ToUtf8(s.bypass) + "\nautoconfig=" + ToUtf8(s.autoconfig) + "\n";
  HANDLE f = CreateFileW(tmp.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (f == INVALID_HANDLE_VALUE) return false;
  DWORD written = 0;
  BOOL ok = WriteFile(f, data.data(), (DWORD)data.size(), &written, nullptr);
  FlushFileBuffers(f);
  CloseHandle(f);
  if (!ok) return false;
  return MoveFileExW(tmp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
}

bool ReadBackup(ProxyState& s) { return ReadStateFile(L"proxy-backup.txt", s); }
bool WriteBackup(const ProxyState& s) { return WriteStateFile(L"proxy-backup.txt", s); }

// 穿云 1.2.2: what the guard itself last put back (proxy-restored.txt). `status` reports
// restored=1 while the current setting is still exactly that, so the app can tell "the guard
// restored the user's settings" (reconnect) from "the user changed the proxy" (leave it alone).
bool ReadRestored(ProxyState& s) { return ReadStateFile(L"proxy-restored.txt", s); }
void WriteRestored(const ProxyState& s) { WriteStateFile(L"proxy-restored.txt", s); }

// ---- commands ----

// Remembers the user's own settings. A backup that already exists belongs to the running session
// (sing-box blanks the proxy whenever the core restarts) and is kept; settings that point at
// 穿云 itself are never saved.
int Save() {
  ProxyState cur;
  if (!Query(cur)) {
    Log("save: query failed " + std::to_string(GetLastError()));
    return 2;
  }
  ProxyState existing;
  if (ReadBackup(existing)) {
    Out("kept " + Describe(existing));
    return 1;
  }
  if (PointsAtUs(cur, g_port)) {
    Out("ours, not saved");
    return 1;
  }
  if (!WriteBackup(cur)) {
    Log("save: write failed " + std::to_string(GetLastError()));
    return 2;
  }
  Log("save: " + Describe(cur));
  Out("saved " + Describe(cur));
  return 0;
}

// Puts the user's settings back when the system proxy still points at 穿云 (or was blanked by
// sing-box while a different setting had been saved). Without a backup: direct connection.
int Restore(const char* why) {
  ProxyState cur;
  if (!Query(cur)) {
    Log(std::string("restore(") + why + "): query failed " + std::to_string(GetLastError()));
    return 2;
  }
  ProxyState saved;
  bool hasSaved = ReadBackup(saved) && !PointsAtUs(saved, g_port);
  bool ours = PointsAtUs(cur, g_port);
  int rc = 1;
  // sing-box's ClearSystemProxy leaves "direct" and may blank the server / bypass / PAC fields:
  // when the current setting is direct and differs from the saved one, the saved one goes back
  bool blanked = hasSaved && IsDirectOnly(cur) && !Same(cur, saved);
  if (ours || blanked) {
    ProxyState target;
    if (hasSaved) target = saved;
    target.valid = true;
    if (Apply(target)) {
      WriteRestored(target);
      Log(std::string("restore(") + why + "): " + Describe(cur) + " -> " + Describe(target));
      Out("restored " + Describe(target));
      rc = 0;
    } else {
      Log(std::string("restore(") + why + "): apply failed " + std::to_string(GetLastError()));
      rc = 2;
    }
  } else {
    Out("not ours " + Describe(cur));
  }
  // 穿云 1.2.2: a restore in the middle of a recovery ("恢复失败") belongs to a session that is
  // still going: when nothing had to be restored the backup is kept, so the reconnect that
  // follows does not save whatever happens to be set at that moment as "the user's settings".
  bool sessionContinues = strcmp(why, "恢复失败") == 0;
  if (rc == 0 || (rc == 1 && !sessionContinues)) DeleteFileW(PathIn(L"proxy-backup.txt").c_str());
  return rc;
}

int Status() {
  ProxyState cur;
  if (!Query(cur)) return 2;
  ProxyState saved;
  bool hasSaved = ReadBackup(saved);
  bool ours = PointsAtUs(cur, g_port);
  ProxyState restored;
  bool byGuard = !ours && ReadRestored(restored) && Same(cur, restored);
  Out(std::string("ours=") + (ours ? "1" : "0") + " " + Describe(cur) + " backup=" + (hasSaved ? "1" : "0") +
      " restored=" + (byGuard ? "1" : "0"));
  return ours ? 0 : 1;
}

// SOCKS5 greeting to 127.0.0.1:port; the mixed inbound answers 05 00 without touching the network.
bool PortAnswers(int port) {
  SOCKET s = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if (s == INVALID_SOCKET) return true;  // can't tell: don't act
  DWORD tmo = 2000;
  setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, (const char*)&tmo, sizeof(tmo));
  setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, (const char*)&tmo, sizeof(tmo));
  u_long nb = 1;
  ioctlsocket(s, FIONBIO, &nb);
  sockaddr_in a = {};
  a.sin_family = AF_INET;
  a.sin_port = htons((u_short)port);
  inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
  bool ok = false;
  int r = connect(s, (sockaddr*)&a, sizeof(a));
  if (r == 0 || WSAGetLastError() == WSAEWOULDBLOCK) {
    fd_set w, e;
    FD_ZERO(&w);
    FD_ZERO(&e);
    FD_SET(s, &w);
    FD_SET(s, &e);
    timeval tv = {2, 0};
    if (select(0, nullptr, &w, &e, &tv) > 0 && FD_ISSET(s, &w)) {
      nb = 0;
      ioctlsocket(s, FIONBIO, &nb);
      const char hello[3] = {5, 1, 0};
      if (send(s, hello, 3, 0) == 3) {
        char resp[2] = {0, 0};
        int got = 0;
        while (got < 2) {
          int n = recv(s, resp + got, 2 - got, 0);
          if (n <= 0) break;
          got += n;
        }
        ok = got == 2 && resp[0] == 5;
      }
    }
  }
  closesocket(s);
  return ok;
}

bool IsCrashExit(DWORD code) {
  // 0 = 退出, 1 = taskkill / 结束任务 / installer; 0xFFFFFFFF = Kill(). Go fatal errors exit 2,
  // abort() 3, native crashes with an NTSTATUS (0xC0000005 ...).
  if (code == 2 || code == 3) return true;
  return code >= 0xC0000000u && code != 0xFFFFFFFFu;
}

bool RelaunchAllowed() {
  std::wstring path = PathIn(L"guard-relaunch.txt");
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  ULONGLONG wall = ((((ULONGLONG)ft.dwHighDateTime) << 32) | ft.dwLowDateTime) / 10000000ULL;
  std::vector<ULONGLONG> recent;
  HANDLE f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, 0, nullptr);
  if (f != INVALID_HANDLE_VALUE) {
    char buf[1024];
    DWORD n = 0;
    std::string data;
    while (ReadFile(f, buf, sizeof(buf), &n, nullptr) && n > 0) data.append(buf, n);
    CloseHandle(f);
    size_t start = 0;
    while (start < data.size()) {
      size_t end = data.find('\n', start);
      if (end == std::string::npos) end = data.size();
      ULONGLONG v = _strtoui64(data.substr(start, end - start).c_str(), nullptr, 10);
      if (v > 0 && wall - v < 30 * 60) recent.push_back(v);
      start = end + 1;
    }
  }
  if (recent.size() >= 3) return false;
  recent.push_back(wall);
  std::string out;
  for (auto v : recent) out += std::to_string(v) + "\n";
  f = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, 0, nullptr);
  if (f != INVALID_HANDLE_VALUE) {
    DWORD w = 0;
    WriteFile(f, out.data(), (DWORD)out.size(), &w, nullptr);
    CloseHandle(f);
  }
  return true;
}

void Relaunch(const std::wstring& exe) {
  if (exe.empty() || GetFileAttributesW(exe.c_str()) == INVALID_FILE_ATTRIBUTES) return;
  if (!RelaunchAllowed()) {
    Log("relaunch skipped: 3 relaunches in the last 30 minutes");
    return;
  }
  // the relaunched app reconnects (it was connected) and stays in the tray
  SetEnvironmentVariableW(L"CHUANYUN_RECOVERED", L"1");
  std::wstring dir = exe.substr(0, exe.find_last_of(L"\\/"));
  std::wstring cmd = L"\"" + exe + L"\"";
  STARTUPINFOW si = {};
  si.cb = sizeof(si);
  PROCESS_INFORMATION pi = {};
  if (CreateProcessW(exe.c_str(), &cmd[0], nullptr, nullptr, FALSE, 0, nullptr, dir.c_str(), &si, &pi)) {
    Log("relaunched app, pid " + std::to_string(pi.dwProcessId));
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
  } else {
    Log("relaunch failed " + std::to_string(GetLastError()));
  }
}

int Watch(DWORD pid, const std::wstring& exe) {
  HANDLE h = OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!h) {
    Log("watch: app " + std::to_string(pid) + " already gone");
    return Restore("app gone");
  }
  Log("watch: app pid " + std::to_string(pid) + ", port " + std::to_string(g_port));
  WSADATA wsa;
  WSAStartup(MAKEWORD(2, 2), &wsa);
  int fails = 0;
  for (;;) {
    DWORD r = WaitForSingleObject(h, 5000);
    if (r == WAIT_OBJECT_0) {
      DWORD code = 0;
      GetExitCodeProcess(h, &code);
      CloseHandle(h);
      ProxyState cur;
      bool ours = Query(cur) && PointsAtUs(cur, g_port);
      char line[96];
      snprintf(line, sizeof(line), "app exited, code 0x%lx (%lu), system proxy ours=%d", code, code, ours ? 1 : 0);
      Log(line);
      if (ours) {
        Restore("app exited");
        if (IsCrashExit(code)) Relaunch(exe);
      }
      return 0;
    }
    if (r != WAIT_TIMEOUT) {
      Log("watch: wait failed " + std::to_string(GetLastError()));
      CloseHandle(h);
      return 2;
    }
    ProxyState cur;
    if (!Query(cur) || !PointsAtUs(cur, g_port)) {
      fails = 0;
      continue;
    }
    if (PortAnswers(g_port)) {
      fails = 0;
      continue;
    }
    fails++;
    Log("system proxy points at 127.0.0.1:" + std::to_string(g_port) + " but nothing answers (" +
        std::to_string(fails) + "/3)");
    if (fails >= 3) {
      Restore("port dead");
      fails = 0;
    }
  }
}

}  // namespace

int APIENTRY wWinMain(HINSTANCE, HINSTANCE, LPWSTR, int) {
  int argc = 0;
  LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (!argv || argc < 4) {
    Out("usage: ChuanyunGuard save|restore|status|watch <stateDir> <port> [pid] [exe]");
    return 2;
  }
  std::wstring cmd = argv[1];
  g_stateDir = argv[2];
  CreateDirectoryW(g_stateDir.c_str(), nullptr);
  g_port = _wtoi(argv[3]);
  if (g_port <= 0 || g_port > 65535) g_port = 12334;
  int rc = 2;
  if (cmd == L"save") {
    rc = Save();
  } else if (cmd == L"restore") {
    std::string why = argc >= 5 ? ToUtf8(argv[4]) : std::string("app");
    rc = Restore(why.c_str());
  } else if (cmd == L"apply" && argc >= 5) {
    // smoke tests: put a known "user" setting in place (flags [server [bypass]])
    ProxyState st;
    st.flags = (DWORD)wcstoul(argv[4], nullptr, 0);
    if (argc >= 6) st.server = argv[5];
    if (argc >= 7) st.bypass = argv[6];
    st.valid = true;
    rc = Apply(st) ? 0 : 2;
    Out(rc == 0 ? "applied " + Describe(st) : "apply failed");
  } else if (cmd == L"status") {
    rc = Status();
  } else if (cmd == L"watch" && argc >= 5) {
    // one watcher per app instance: a second one for the same pid just exits
    std::wstring mutexName = L"Local\\ChuanyunGuard-" + std::wstring(argv[4]);
    HANDLE m = CreateMutexW(nullptr, TRUE, mutexName.c_str());
    if (m && GetLastError() == ERROR_ALREADY_EXISTS) {
      rc = 1;
    } else {
      rc = Watch((DWORD)_wtoi(argv[4]), argc >= 6 ? std::wstring(argv[5]) : std::wstring());
    }
  }
  LocalFree(argv);
  return rc;
}
