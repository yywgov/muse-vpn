; 穿云 (Chuanyun) Windows installer - Inno Setup 6.
; Built by .github/workflows/muse-windows.yml:
;   ISCC /DAppVersion=1.1.0 /DSourceDir=<...\Release> /DOutputDir=<out> windows\packaging\inno\chuanyun.iss
; Part of 穿云, a fork of Hiddify (https://github.com/hiddify/hiddify-app), GPLv3.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\..\out"
#endif

[Setup]
AppId={{8F3C2A51-6B7E-4D2A-9C1F-3E5D7A9B0C11}
AppName=穿云
AppVersion={#AppVersion}
AppVerName=穿云 {#AppVersion}
AppPublisher=Chuanyun
AppPublisherURL=https://github.com/yywgov/muse-vpn
AppSupportURL=https://github.com/yywgov/muse-vpn
AppUpdatesURL=https://github.com/yywgov/muse-vpn/releases
DefaultDirName={autopf}\Chuanyun
DefaultGroupName=穿云
DisableProgramGroupPage=yes
DisableDirPage=auto
DisableReadyPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Chuanyun-Windows-x64-Setup
SetupIconFile=..\..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Chuanyun.exe
UninstallDisplayName=穿云
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Chuanyun
VersionInfoDescription=Chuanyun Setup
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ShowLanguageDialog=no
CloseApplications=yes
RestartApplications=no
UsedUserAreasWarning=no

[Languages]
#if FileExists(AddBackslash(CompilerPath) + "Languages\ChineseSimplified.isl")
Name: "chs"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
#else
Name: "chs"; MessagesFile: "ChineseSimplified.isl"
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\穿云"; Filename: "{app}\Chuanyun.exe"
Name: "{autodesktop}\穿云"; Filename: "{app}\Chuanyun.exe"; Tasks: desktopicon

[Run]
; normal install: the "运行 穿云" checkbox on the last page
Filename: "{app}\Chuanyun.exe"; Description: "{cm:LaunchProgram,穿云}"; Flags: nowait postinstall skipifsilent runasoriginaluser
; in-app update (Setup.exe /SILENT /RELAUNCH): start the new version again
Filename: "{app}\Chuanyun.exe"; Flags: nowait runasoriginaluser; Check: IsRelaunch

[UninstallDelete]
Type: filesandordirs; Name: "{app}"

[Code]
const
  InetKey = 'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  RunKey = 'Software\Microsoft\Windows\CurrentVersion\Run';

function IsRelaunch: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if CompareText(ParamStr(I), '/RELAUNCH') = 0 then
      Result := True;
end;

{ A killed 穿云 can't restore the system proxy: turn off a proxy that still points at it. }
procedure ClearStaleProxy;
var
  Server: String;
  Enabled: Cardinal;
begin
  if RegQueryDWordValue(HKCU, InetKey, 'ProxyEnable', Enabled) and (Enabled = 1) and
     RegQueryStringValue(HKCU, InetKey, 'ProxyServer', Server) and
     ((Pos('127.0.0.1:', Server) > 0) or (Pos('localhost:', Server) > 0)) then
    RegWriteDWordValue(HKCU, InetKey, 'ProxyEnable', 0);
end;

{ Closes a running 穿云 (and the CLI core) so its files can be replaced. }
procedure CloseChuanyun;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM Chuanyun.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM HiddifyCli.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(800);
  ClearStaleProxy;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  CloseChuanyun;
  Result := '';
end;

function InitializeUninstall: Boolean;
begin
  CloseChuanyun;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    { 开机自启 entry written by the app (launch_at_startup) }
    RegDeleteValue(HKCU, RunKey, 'Chuanyun');
    RegDeleteValue(HKCU, RunKey, '穿云');
  end;
end;
