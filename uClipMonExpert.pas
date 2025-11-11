unit uClipMonExpert;

{=============================================================================================================
   www.GabrielMoraru.com
   2024
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   This IDE wizzard detects when a PAS file (full or partial path) appears into the clipboard.
   Is the file is found in a certain folder (provided by the user via an INI file) it opens that file in the IDE.
=============================================================================================================}

INTERFACE

USES
  Winapi.Windows, System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, System.Types,
  Vcl.Dialogs, Vcl.Clipbrd, Vcl.Menus, Vcl.Forms,
  ToolsAPI,
  uOpenFileIDE {this file can be found here: Github.com/GabrielOnDelphi/Delphi-LightSaber/tree/main/IDE%20Experts };

TYPE
  TFileFromClipboard = class(TInterfacedObject, IOTAWizard, IOTAIDENotifier)
  private
    FLastClipboardText: string;
    FNotifierIndex: Integer;
    FMenuItem: TMenuItem;
    procedure LoadSettings;
    function  TryExtractUnitName(const Path: string): string;
    function  SearchFileInPath(const FileName: string): string;
    function  IsFileExcluded(const FullPath: string): Boolean;
    procedure Log(const Msg: string);
  public
    MonitorForm: TObject; // TClipMonFrm - Reference to the hidden clipboard monitor form.
    // Settings
    Enabled: Boolean;
    LogActive: Boolean;
    ExcludeFolders: TStringList;
    SearchPath: string;
    DontOpenTwice: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure ProcessClipboard; // Called by TClipMonFrm.WMClipboardUpdate
    procedure ShowPluginOptions(Sender: TObject);
    procedure SaveSettings;
    // IOTAWizard
    function GetIDString: string;
    function GetName: string;
    function GetState: TWizardState;
    procedure Execute;
    // IOTAIDENotifier
    procedure FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
    procedure BeforeCompile(const Project: IOTAProject; var Cancel: Boolean); overload;
    procedure AfterCompile(Succeeded: Boolean); overload;
    // IOTANotifier
    procedure AfterSave;
    procedure BeforeSave;
    procedure Destroyed;
    procedure Modified;
  end;

procedure Register;

IMPLEMENTATION
USES uUtils, uClipMonForm;


{-------------------------------------------------------------------------------------------------------------
   CTOR
-------------------------------------------------------------------------------------------------------------}
procedure TFileFromClipboard.Log(const Msg: string);
begin
  if Assigned(MonitorForm)
  and LogActive
  then (MonitorForm as TClipMonFrm).Log.Lines.Add(Msg);
end;


constructor TFileFromClipboard.Create;
var NTAServices: INTAServices;
begin
  inherited Create;

  ExcludeFolders:= TStringList.Create;
  ExcludeFolders.Delimiter:= ';';   // necessary for DelimitedText only, not for CommaText
  FNotifierIndex:= -1;
  FMenuItem:= nil;
  Enabled:= True;
  DontOpenTwice:= FALSE;

  LoadSettings;

  // Create the dedicated hidden form. Pass a reference to ProcessClipboard as the callback TProc
  if Assigned(MonitorForm) then MonitorForm.Free;
  MonitorForm:= TClipMonFrm.Create(nil, Self); // Freed by: Destroy
  Log('Expert.Constructor');
  //(MonitorForm as TClipMonFrm).Show;

  // Add the menu item, using the Wizard object as the owner.
  if Supports(BorlandIDEServices, INTAServices, NTAServices) then
  begin
    // The wizard (which is an IOTAWizard) is the owner.
    FMenuItem := TMenuItem.Create(Application);
    FMenuItem.Caption := 'File From Clipboard';

    // The handler is an instance method of TFormSettings, which handles its own creation/destruction.
    FMenuItem.OnClick := ShowPluginOptions;

    // 'ToolsMenu' is the correct name for the top-level Tools menu.
    // The menu is now owned by the expert class and will be cleaned up in its destructor.
    NTAServices.AddActionMenu('ToolsMenu', nil, FMenuItem);
  end;

  // Initial check
  ProcessClipboard;
end;


destructor TFileFromClipboard.Destroy;
begin
  SaveSettings;

  FreeAndNil(MonitorForm);          // The TClipMonFrm destructor handles calling RemoveClipboardFormatListener(Handle)
  FreeAndNil(FMenuItem);            // Release the menu item. The IDE services might handle this, but it's safer to attempt to free it.
  FreeAndNil(ExcludeFolders);

  inherited;
end;



{-------------------------------------------------------------------------------------------------------------
   MAIN
-------------------------------------------------------------------------------------------------------------}
procedure TFileFromClipboard.Execute;
begin
  ProcessClipboard;
end;


procedure TFileFromClipboard.ProcessClipboard;
var
  ClipboardText, Line, FileName, FullPath, UnitName: string;
  Lines: TStringList;
  I: Integer;
begin
  if NOT Enabled then
    begin
      Log('Expert disabled!');
      Exit;
    end;

  // Read clipboard
  Log('');
  if NOT Clipboard.HasFormat(CF_TEXT) then
    begin
      Log('The clipboard is not text!');
      Exit;
    end;
  try
    ClipboardText := Clipboard.AsText;
  except
    on E: EClipboardException do
      begin
        Log('Expert.EClipboardException!');
        Exit;                          // Silently handle access denied or other clipboard errors like "Cannot open clipboard: Access is denied"
      end;
  end;
  Log('First 512 chars in clipboard: '+ Copy(ClipboardText, 1, 512));

  // Don't open twice
  if DontOpenTwice then
    if ClipboardText = FLastClipboardText then Exit;
  FLastClipboardText:= ClipboardText;

  Lines:= TStringList.Create;
  try
    Lines.Text:= ClipboardText;
    for i:= 0 to Lines.Count - 1 do
    begin
      Line:= Trim(Lines[I]);
      if Line = '' then Continue;
      if Pos('.', Line) < 1 then
      begin
        Log('Text in clipbboard: Not a file.');
        Continue;
      end;

      // Replace / with \ to handle Linux-style paths
      Line:= StringReplace(Line, '/', '\', [rfReplaceAll]);    //Some platforms (like sonarcube) uses "Linux" paths, which will give this error: "Invalid characters in search pattern". Example:  MyProjects/Vcl.MyFile.pas

      // Handle full paths or unit names (e.g., c:\path\file.pas or MyBase.MyUnit.pas)
      UnitName:= TryExtractUnitName(Line);
      FileName:= ExtractFileName(UnitName);
      Log('Expert.ProcessClipboard.UnitName: '+ UnitName);

      if NOT IsDelphiFile(FileName) then
        begin
          Log('Text in clipbboard: Not a Dephi file: '+ FileName);
          Continue;
        end;

      // Check for exclusion before opening
      if IsFileExcluded(FullPath) then
        begin
          Continue; // Skip this path and go to the next line in the clipboard
        end;

      // Restore full file name
      if TFile.Exists(Line)
      then FullPath := Line
      else FullPath := SearchFileInPath(FileName);

      if FullPath <> '' then
      begin
        // CRITICAL: Schedule the OTA call (OpenFileInIDE) to run later when the IDE's main message loop is idle.
        TThread.Queue(nil,
          procedure
          begin
            VAR IDEPosition: RIDEPosition;
            IDEPosition.default(FullPath);
            OpenInIDEEditor(IDEPosition);
          end);

        Break; // Found the file, break the loop
      end;
    end;
  finally
    Lines.Free;
  end;
end;


{ Tries to figure out if the text in clipboard countains a valid PAS file }
function TFileFromClipboard.TryExtractUnitName(const Path: string): string;
var
  DotPos: Integer;
begin
  Result:= Trim(Path);
  DotPos:= LastDelimiter('.', Result);  // Look for the last dot before the extension

  // Check if there is an extension (e.g., .pas)
  if DotPos > 0
  then
    begin
      // Check if the character before the extension is a dot (part of the unit name)
      if (DotPos > 1) and (Result[DotPos - 1] = '.') then
      begin
        // Find the second-to-last dot to remove the module prefix (MyBase.)
        Result := Copy(Result, 1, DotPos - 2);
        DotPos := LastDelimiter('.', Result);

        if DotPos > 0
        then Result := Copy(Path, DotPos + 1, MaxInt);
      end;

      // If no module prefix is found, return the original string or just the filename
      if ExtractFileExt(Result) = ''
      then Result := Path
      else Result := ExtractFileName(Result);
    end
  else Result:= '';
end;


// Centralized logic for checking if a file path is excluded.
function TFileFromClipboard.IsFileExcluded(const FullPath: string): Boolean;
var
  ExcludePath2: string;
begin
  if FullPath = '' then Exit(False);

  // Check against exclude folders
  for var ExcludePath in ExcludeFolders do
    begin
      if ExcludePath = '' then Continue;

      // Ensure the exclusion path is lower-cased and has a trailing path delimiter
      // for accurate subfolder matching (e.g., 'c:\tools' must match 'c:\tools\subfolder').
      ExcludePath2:= LowerCase(IncludeTrailingPathDelimiter(ExcludePath));

      if Pos(ExcludePath2, LowerCase(FullPath)) > 0 then
      begin
        Log('Path excluded! ExcludePath: '+ExcludePath2+ #13 + 'Input file: '+ FullPath);
        Exit(True);
      end;
    end;

  Result:= FALSE;
end;


{ Here we check if the file in present in our searched folder }
function TFileFromClipboard.SearchFileInPath(const FileName: string): string;
var
  Files: TStringDynArray;
  I: Integer;
  FullPath: string;
begin
  Result := '';
  Log('SearchFileInPath: '+ FileName);

  if not TDirectory.Exists(SearchPath) then
    begin
      Log('"Search folder" not found!');
      Exit;
    end;

  // Search the our path for the FileName
  try
    Files := TDirectory.GetFiles(SearchPath, FileName, TSearchOption.soAllDirectories);
  except
    ShowMessage('SearchFileInPath exception');
    Exit; // Hide exceptions like "Invalid characters in search pattern"
  end;

  for I := 0 to High(Files) do
  begin
    FullPath:= Files[I];

    if not IsFileExcluded(FullPath)
    then Exit(FullPath);
    // If excluded, loop to the next file found
  end;
end;




function TFileFromClipboard.GetIDString: string;
begin
  Result:= 'FileFromClipboard.GabrielMoraru';
end;

function TFileFromClipboard.GetName: string;
begin
  Result:= 'File From Clipboard - GabrielMoraru.com';
end;

function TFileFromClipboard.GetState: TWizardState;
begin
  Result:= [wsEnabled];  //todo: use this instead of Enabled!
end;

procedure TFileFromClipboard.AfterSave;
begin
end;

procedure TFileFromClipboard.BeforeSave;
begin
end;

procedure TFileFromClipboard.Destroyed;
begin
end;

procedure TFileFromClipboard.Modified;
begin
end;

procedure TFileFromClipboard.AfterCompile(Succeeded: Boolean);
begin
  // AfterCompile is often used for initialization, but since we use the form's handle in the constructor, this is only used for an initial check if needed.
  // ProcessClipboard; Optional
end;

procedure TFileFromClipboard.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TFileFromClipboard.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
begin
end;




{-------------------------------------------------------------------------------------------------------------
   UTILS / SETTINGS
-------------------------------------------------------------------------------------------------------------}
function IsDelphiFile(const FileName: string): Boolean;
var Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FileName));
  Result := (Ext = '.pas') or (Ext = '.dfm') or (Ext = '.dpr')
         or (Ext = '.dpk') or (Ext = '.inc') or (Ext = '.dproj');
end;


function AppDataFolder(AppName: string; ForceDir: Boolean = FALSE): string;
begin
  Assert(AppName > '', 'AppName is empty!');
  Assert(System.IOUtils.TPath.HasValidFileNameChars(AppName, FALSE), 'Invalid chars in AppName: '+ AppName);

  Result := IncludeTrailingPathDelimiter(TPath.Combine(TPath.GetHomePath, AppName));

  if ForceDir
  then ForceDirectories(Result);
end;


function GetIniPath: string;
begin
  Result:= AppDataFolder('FileFromClipboard', TRUE) + 'FileFromClipboard.ini';
end;




{ INI file is located in c:\Users\USERNAME\AppData\Roaming\FileFromClipboard\FileFromClipboard.ini }
procedure TFileFromClipboard.LoadSettings;
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath:= GetIniPath;
  Log('Expert.LoadSettings');
  Ini:= TIniFile.Create(IniPath);
  try
    // Search folder
    SearchPath:= Ini.ReadString('ExpertSettings', 'SearchPath', 'C:\Projects\');
    SearchPath:= IncludeTrailingPathDelimiter(SearchPath);

    // Excluded folders
    ExcludeFolders.Clear;
    ExcludeFolders.DelimitedText:= Ini.ReadString('ExpertSettings', 'ExcludeFolders', 'External;C:\Projects\3rd_party');

    // Plugin
    Enabled  := Ini.ReadBool('ExpertSettings', 'Enabled', True);
    LogActive:= Ini.ReadBool('ExpertSettings', 'LogActive', False);
  finally
    Ini.Free;
  end;
end;


procedure TFileFromClipboard.SaveSettings;
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath:= GetIniPath;
  Log('Expert.SaveSettings - IniPath: '+ IniPath);
  Ini:= TIniFile.Create(IniPath);
  try
    Ini.WriteString('ExpertSettings', 'SearchPath', SearchPath);
    Ini.WriteString('ExpertSettings', 'ExcludeFolders', ExcludeFolders.DelimitedText);
    Ini.WriteBool  ('ExpertSettings', 'Enabled', Enabled);
    Ini.WriteBool  ('ExpertSettings', 'LogActive', LogActive);
  finally
    Ini.Free;
  end;
end;



// Show form
procedure TFileFromClipboard.ShowPluginOptions(Sender: TObject);
begin
  // if not Assigned(FormSettings) then FormSettings:= TFormSettings.Create(Application, Self);
  (MonitorForm as TClipMonFrm).Show;
end;


procedure Register;
begin
  var Wizard:= TFileFromClipboard.Create;
  RegisterPackageWizard(Wizard as IOTAWizard);
end;


end.

