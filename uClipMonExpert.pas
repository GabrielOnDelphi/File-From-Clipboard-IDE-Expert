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
  Vcl.Dialogs, Vcl.Clipbrd,
  ToolsAPI, uClipMonForm;

TYPE
  TFileFromClipboard = class(TInterfacedObject, IOTAWizard, IOTAIDENotifier)
  private
    FLastClipboardText: string;
    FSearchPath: string;
    FExcludeFolders: TStringList;
    FNotifierIndex: Integer;
    FMonitorForm: TClipMonFrm; // Reference to the hidden form
    procedure LoadSettings;
    function  TryExtractUnitName(const Path: string): string;
    function  IsDelphiFile(const FileName: string): Boolean;
    function  SearchFileInPath(const FileName: string): string;
    procedure OpenFileInIDE(const FullPath: string);
    procedure ProcessClipboard;
  public
    constructor Create;
    destructor Destroy; override;
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

implementation


{-------------------------------------------------------------------------------------------------------------
   CTOR
-------------------------------------------------------------------------------------------------------------}
constructor TFileFromClipboard.Create;
begin
  inherited Create;
  FExcludeFolders := TStringList.Create;
  FExcludeFolders.Delimiter := ';';
  FNotifierIndex := -1;
  LoadSettings;

  // Create the dedicated hidden form. Pass a reference to ProcessClipboard as the callback TProc
  FMonitorForm := TClipMonFrm.Create(nil, ProcessClipboard); // Freed by: Destroy

  // Initial check
  ProcessClipboard;
end;


destructor TFileFromClipboard.Destroy;
begin
  // The TClipMonFrm destructor handles calling RemoveClipboardFormatListener(Handle)
  if Assigned(FMonitorForm) then FMonitorForm.Free;

  FExcludeFolders.Free;
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
  //showmessage('Entered ProcessClipboard'); // DEBUG

  if not Clipboard.HasFormat(CF_TEXT) then Exit;
  try
    ClipboardText := Clipboard.AsText;
  except
    on E: EClipboardException do
      Exit; // Silently handle access denied or other clipboard errors like "Cannot open clipboard: Access is denied"
  end;

  if ClipboardText = FLastClipboardText then Exit;
  FLastClipboardText := ClipboardText;

  Lines:= TStringList.Create;
  try
    Lines.Text := ClipboardText;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if Line = '' then Continue;

      // Replace / with \ to handle Linux-style paths
      Line := StringReplace(Line, '/', '\', [rfReplaceAll]);    //Some platforms (like sonarcube) uses "Linux" paths, which will give this error: "Invalid characters in search pattern". Example:  MyProjects/Vcl.MyFile.pas

      // Handle full paths or unit names (e.g., c:\path\file.pas or MyBase.MyUnit.pas)
      UnitName := TryExtractUnitName(Line);
      FileName := ExtractFileName(UnitName);

      if not IsDelphiFile(FileName) then Continue;

      // Find the file path
      if TFile.Exists(Line)
      then FullPath := Line
      else FullPath := SearchFileInPath(FileName);

      if FullPath <> '' then
      begin
        // CRITICAL: Schedule the OTA call (OpenFileInIDE) to run later when the IDE's main message loop is idle.
        TThread.Queue(nil,
          procedure
          begin
            OpenFileInIDE(FullPath);
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
  Result := Trim(Path);
  DotPos := LastDelimiter('.', Result);  // Look for the last dot before the extension

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



{ Here we check if the file in present in our searched folder }
function TFileFromClipboard.SearchFileInPath(const FileName: string): string;
var
  Files: TStringDynArray;
  I: Integer;
  FullPath: string;
  Excluded: Boolean;
begin
  Result := '';
  if not TDirectory.Exists(FSearchPath) then Exit;

  // Search the our path for the FileName
  try
    Files := TDirectory.GetFiles(FSearchPath, FileName, TSearchOption.soAllDirectories);
  except
    Exit; // Hide exceptions like "Invalid characters in search pattern"
  end;

  for I := 0 to High(Files) do
  begin
    FullPath := Files[I];
    Excluded := False;

    // Check against exclude folders
    for var ExcludePath in FExcludeFolders do
      if Pos(LowerCase(IncludeTrailingPathDelimiter(ExcludePath)), LowerCase(FullPath)) > 0 then
      begin
        Excluded := True;
        Break;
      end;

    if not Excluded
    then Exit(FullPath);
  end;
end;


procedure TFileFromClipboard.OpenFileInIDE(const FullPath: string);
var
  Module: IOTAModule;
  ActionServices: IOTAActionServices;
  ModuleServices: IOTAModuleServices;
begin
  if BorlandIDEServices = nil then
    begin
      ShowMessage('BorlandIDEServices not supported!');
      Exit;
    end;

  if not Supports(BorlandIDEServices, IOTAActionServices, ActionServices) then
    begin
      ShowMessage('IOTAActionServices module not supported!');
      Exit;
    end;

  // Open the file
  if not ActionServices.OpenFile(FullPath) then
    begin
      ShowMessage('Failed to open file in IDE: ' + FullPath);
      Exit;
    end;

  // Bring the editor to front
  if Supports(BorlandIDEServices, IOTAModuleServices, ModuleServices) then
    begin
      Module:= ModuleServices.FindModule(FullPath);
      if Assigned(Module)
      then Module.Show
      else ShowMessage('Error finding module after opening file: ' + FullPath);
    end;
end;







function TFileFromClipboard.GetIDString: string;
begin
  Result := 'FileFromClipboard.GabrielMoraru';
end;

function TFileFromClipboard.GetName: string;
begin
  Result := 'File From Clipboard - GabrielMoraru.com';
end;

function TFileFromClipboard.GetState: TWizardState;
begin
  Result := [wsEnabled];
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
function TFileFromClipboard.IsDelphiFile(const FileName: string): Boolean;
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


procedure TFileFromClipboard.LoadSettings;
var
  Ini: TIniFile;
  IniPath: string;
begin
  IniPath := AppDataFolder('GabrielM_FileFromClipboard', TRUE) + 'FileFromClipboard.ini';
  if not TFile.Exists(IniPath) then
  begin
    Ini := TIniFile.Create(IniPath);
    try
      Ini.WriteString('Settings', 'SearchPath', 'C:\Projects\');
      Ini.WriteString('Settings', 'ExcludeFolders', 'bin;.git;win32;win64;c:\Projects\3rdParty\');
    finally
      Ini.Free;
    end;
  end;

  Ini := TIniFile.Create(IniPath);
  try
    FSearchPath := Ini.ReadString('Settings', 'SearchPath', 'C:\MyProjects\');
    FSearchPath := IncludeTrailingPathDelimiter(FSearchPath);
    FExcludeFolders.DelimitedText := Ini.ReadString('Settings', 'ExcludeFolders', '');
  finally
    Ini.Free;
  end;
end;




procedure Register;
begin
  RegisterPackageWizard(TFileFromClipboard.Create as IOTAWizard);
end;

end.
