#define AppVersion "0.1.0"
[Setup]
AppId={{7F052738-70B9-4362-80FB-AEC19AF7DE75}
AppName=Fenru
AppVersion={#AppVersion}
AppVerName=Fenru {#AppVersion} alpha.7
AppPublisher=vividhyeok
AppPublisherURL=https://github.com/vividhyeok/fenru
DefaultDirName={localappdata}\Programs\Fenru
DefaultGroupName=Fenru
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Fenru-Windows-x64-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\fenru.exe
[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Fenru"; Filename: "{app}\fenru.exe"
Name: "{autodesktop}\Fenru"; Filename: "{app}\fenru.exe"; Tasks: desktopicon
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Run]
Filename: "{app}\fenru.exe"; Description: "Open Fenru"; Flags: nowait postinstall skipifsilent
