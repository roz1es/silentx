#define AppName "BrenksChat"
#define AppPublisher "BrenksChat"
#define AppExeName "BrenksChat.exe"
#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{A87210F1-273E-4C21-90BE-979CFB0E7931}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://brenkschat.ru
AppSupportURL=https://brenkschat.ru
AppUpdatesURL=https://brenkschat.ru/desktop/windows/latest.json
DefaultDirName={localappdata}\Programs\BrenksChat
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
PrivilegesRequired=lowest
OutputDir=..\..\release\windows
OutputBaseFilename=BrenksChatSetup-{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardImageFile=assets\wizard-sidebar.bmp
WizardSmallImageFile=assets\wizard-small.bmp
WindowVisible=no
CloseApplications=yes
RestartApplications=no
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
MinVersion=10.0

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Создать ярлык на рабочем столе"; GroupDescription: "Ярлыки:"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Запустить {#AppName}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\data"

[Code]
procedure InitializeWizard();
begin
  WizardForm.Caption := 'BrenksChat Setup';
  WizardForm.Color := $F6F7FB;
  WizardForm.InnerPage.Color := $F6F7FB;
  WizardForm.Bevel.Visible := False;
  WizardForm.WelcomeLabel1.Caption := 'BrenksChat';
  WizardForm.WelcomeLabel2.Caption :=
    'Desktop messenger installer.' + #13#10 +
    'The app connects to api.brenkschat.ru and works as a native desktop client.';
  WizardForm.FinishedHeadingLabel.Caption := 'BrenksChat installed';
  WizardForm.FinishedLabel.Caption :=
    'You can launch the app and sign in to your account.';
end;
