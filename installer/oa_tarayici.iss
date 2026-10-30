; OA Tarayıcı — Windows kurulum programı (Inno Setup 6)
; Derleme: ISCC.exe /DAppVersion=0.6.0 installer\oa_tarayici.iss
; Yönetici izni istemez: kullanıcının kendi klasörüne kurulur.
; Tarayıcı olarak kaydeder: Ayarlar → Uygulamalar → Varsayılan uygulamalar'da "OA Tarayıcı" seçilebilir.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppExe "oa_tarayici.exe"

[Setup]
AppId={{5B0E2B3C-4F1A-4C7E-9A0F-0A1B2C3D4E5F}
AppName=OA Tarayıcı
AppVersion={#AppVersion}
AppVerName=OA Tarayıcı {#AppVersion}
AppPublisher=OA Labs
AppPublisherURL=https://oalabs.dev
AppSupportURL=https://oalabs.dev
DefaultDirName={localappdata}\Programs\OA Tarayici
DefaultGroupName=OA Tarayıcı
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=OA-Tarayici-Kurulum
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=OA Tarayıcı
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\OA Tarayıcı"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\OA Tarayıcı"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Bağlantı türü: http/https bu sınıfla açılır
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL"; ValueType: string; ValueData: "OA Tarayıcı bağlantısı"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML"; ValueType: string; ValueData: "OA Tarayıcı belgesi"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
; Tarayıcı kaydı
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici"; ValueType: string; ValueData: "OA Tarayıcı"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"""
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "OA Tarayıcı"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "OA Labs'in reklamsız, sade tarayıcısı"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\URLAssociations"; ValueType: string; ValueName: "http"; ValueData: "OATarayiciURL"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\URLAssociations"; ValueType: string; ValueName: "https"; ValueData: "OATarayiciURL"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\FileAssociations"; ValueType: string; ValueName: ".htm"; ValueData: "OATarayiciHTML"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\FileAssociations"; ValueType: string; ValueName: ".html"; ValueData: "OATarayiciHTML"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\StartMenu"; ValueType: string; ValueName: "StartMenuInternet"; ValueData: "OATarayici"
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "OA Tarayıcı"; ValueData: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,OA Tarayıcı}"; Flags: nowait postinstall
