// 穿云 1.6.0 C8 - 复制终端代理命令: the line to paste into a terminal so command-line tools
// (git, curl, pip, npm…) go through 穿云's local proxy port. Tray submenu + global hotkey.
// Part of 穿云 (GPLv3).

/// The terminals the command is written for.
enum MuseShellKind {
  cmd('CMD'),
  powershell('PowerShell'),
  bash('Bash / WSL');

  const MuseShellKind(this.title);

  final String title;

  static MuseShellKind fromKey(String? key) =>
      MuseShellKind.values.where((e) => e.name == key).firstOrNull ?? MuseShellKind.powershell;
}

const _noProxy = 'localhost,127.0.0.1,::1';

/// `set http_proxy=…` (CMD) / `$env:http_proxy="…"` (PowerShell) / `export …` (Bash) for the mixed
/// port [port] on this computer.
String museProxyEnvCommand(MuseShellKind kind, int port, {String host = '127.0.0.1'}) {
  final url = 'http://$host:$port';
  return switch (kind) {
    MuseShellKind.cmd => 'set http_proxy=$url & set https_proxy=$url & set no_proxy=$_noProxy',
    MuseShellKind.powershell => '\$env:http_proxy="$url"; \$env:https_proxy="$url"; \$env:no_proxy="$_noProxy"',
    MuseShellKind.bash => 'export http_proxy=$url https_proxy=$url no_proxy=$_noProxy',
  };
}
