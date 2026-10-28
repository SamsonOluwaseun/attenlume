; Attenlume Windows installer (Inno Setup 6). Built by tool\build_windows_installer.ps1:
;   ISCC.exe /DAppVersion=0.1.4 /DSourceDir=<release folder> /DOutputDir=<out> attenlume.iss
;
; Installs for the current user only (no administrator rights), into the same
; folder as the earlier test package, so it replaces it cleanly. Recordings and
; settings live in %LOCALAPPDATA%\Samlytics\Attenlume and are never removed by
; the installer or the uninstaller.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

#define AppName "Attenlume"
#define AppPublisher "Samlytics Data Services"
#define AppUrl "https://github.com/SamsonOluwaseun/attenlume"
#define RepoRoot AddBackslash(SourcePath) + "..\.."

[Setup]
AppId={{6D4B1E2A-3F7C-4C1B-9A55-2E8B7F0C1A44}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
AppUpdatesURL={#AppUrl}/releases/latest
DefaultDirName={localappdata}\Programs\Attenlume
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutputDir}
OutputBaseFilename=attenlume-windows-setup
SetupIconFile={#RepoRoot}\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\attenlume.exe
UninstallDisplayName={#AppName}
LicenseFile={#RepoRoot}\LICENSE
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This will install [name/ver] on your computer.%n%nYour recordings, photos and notes are kept when you update or uninstall.

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[InstallDelete]
; Clear files from an older build so nothing stale is left beside the new one.
Type: filesandordirs; Name: "{app}\data"
Type: files; Name: "{app}\*.dll"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\attenlume.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\attenlume.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\attenlume.exe"; Description: "Open {#AppName} now"; Flags: nowait postinstall skipifsilent
