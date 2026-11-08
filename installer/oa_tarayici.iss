; Pusula Browser — Windows kurulum programı (Inno Setup 6)
; Derleme: ISCC.exe /DAppVersion=0.6.0 installer\oa_tarayici.iss
; Yönetici izni istemez: kullanıcının kendi klasörüne kurulur.
; Tarayıcı olarak kaydeder: Ayarlar → Uygulamalar → Varsayılan uygulamalar'da "Pusula Browser" seçilebilir.
; İç adlar (oa_tarayici.exe, OATarayici kayıt anahtarları, kurulum klasörü) eski kurulumların
; üstüne güncellenebilmek için değişmedi.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppExe "oa_tarayici.exe"

[Setup]
AppId={{5B0E2B3C-4F1A-4C7E-9A0F-0A1B2C3D4E5F}
AppName=Pusula Browser
AppVersion={#AppVersion}
AppVerName=Pusula Browser {#AppVersion}
AppPublisher=OA Labs
AppPublisherURL=https://oalabs.dev
AppSupportURL=https://oalabs.dev
DefaultDirName={code:PusulaDir}
UsePreviousAppDir=no
DirExistsWarning=no
DefaultGroupName=Pusula Browser
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=lowest
OutputDir=..\dist
OutputBaseFilename=Pusula-Kurulum
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName=Pusula Browser
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

[InstallDelete]
; Eski adla oluşturulmuş kısayollar
Type: files; Name: "{autoprograms}\OA Tarayıcı.lnk"
Type: files; Name: "{autodesktop}\OA Tarayıcı.lnk"

[Icons]
Name: "{autoprograms}\Pusula Browser"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\Pusula Browser"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
; Bağlantı türü: http/https bu sınıfla açılır
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL"; ValueType: string; ValueData: "Pusula Browser bağlantısı"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Classes\OATarayiciURL\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML"; ValueType: string; ValueData: "Pusula Browser belgesi"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Classes\OATarayiciHTML\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"" ""%1"""
; Tarayıcı kaydı
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici"; ValueType: string; ValueData: "Pusula Browser"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\DefaultIcon"; ValueType: string; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\shell\open\command"; ValueType: string; ValueData: """{app}\{#AppExe}"""
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "Pusula Browser"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "OA Labs'in reklamsız, sade tarayıcısı"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; ValueType: string; ValueName: "ApplicationIcon"; ValueData: "{app}\{#AppExe},0"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\URLAssociations"; ValueType: string; ValueName: "http"; ValueData: "OATarayiciURL"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\URLAssociations"; ValueType: string; ValueName: "https"; ValueData: "OATarayiciURL"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\FileAssociations"; ValueType: string; ValueName: ".htm"; ValueData: "OATarayiciHTML"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\FileAssociations"; ValueType: string; ValueName: ".html"; ValueData: "OATarayiciHTML"
Root: HKCU; Subkey: "Software\Clients\StartMenuInternet\OATarayici\Capabilities\StartMenu"; ValueType: string; ValueName: "StartMenuInternet"; ValueData: "OATarayici"
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: none; ValueName: "OA Tarayıcı"; Flags: deletevalue
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "Pusula Browser"; ValueData: "Software\Clients\StartMenuInternet\OATarayici\Capabilities"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,Pusula Browser}"; Flags: nowait postinstall

[Code]
// Kurulum klasörü: Pusula şu an açıksa (örn. zip'ten çıkarılıp bir klasörden çalıştırılıyorsa) o klasör
// güncellenir; yoksa önceki kurulumun klasörü; o da yoksa kullanıcının Programlar klasörü.
// (Eski sürümlerin güncelleyicisi /DIR vermiyordu; açık olan kopya güncellenmeden kalıyordu.)
function RunningDir(): String;
var
  Locator, Service, Procs, P: Variant;
  I: Integer;
begin
  Result := '';
  try
    Locator := CreateOleObject('WbemScripting.SWbemLocator');
    Service := Locator.ConnectServer('.', 'root\CIMV2');
    Procs := Service.ExecQuery('SELECT ExecutablePath FROM Win32_Process WHERE Name = ''{#AppExe}''');
    for I := 0 to Procs.Count - 1 do
    begin
      P := Procs.ItemIndex(I);
      if not VarIsNull(P.ExecutablePath) then
      begin
        Result := ExtractFileDir(P.ExecutablePath);
        Exit;
      end;
    end;
  except
    Result := '';
  end;
end;

function PusulaDir(Param: String): String;
begin
  Result := RunningDir();
  // Yönetici izni gerektiren klasörlere (Program Files) bu kurulum yazamaz
  if (Result <> '') and (Pos(LowerCase(ExpandConstant('{commonpf}')), LowerCase(Result)) = 1) then
    Result := '';
  if Result = '' then
    if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{5B0E2B3C-4F1A-4C7E-9A0F-0A1B2C3D4E5F}_is1',
      'Inno Setup: App Path', Result) then
      Result := '';
  if Result = '' then
    Result := ExpandConstant('{localappdata}\Programs\OA Tarayici');
end;
