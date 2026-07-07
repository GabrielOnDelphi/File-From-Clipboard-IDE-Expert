unit uClipMonExpert;

{=============================================================================================================
   www.GabrielMoraru.com
   2026.07.07
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   This IDE wizard detects when a PAS file (full or partial path) appears into the clipboard.
   If the file is found in a certain folder (provided by the user via an INI file) it opens that file in the IDE.

   CODE LINE JUMPING
   After opening/switching to a unit, the expert enters "waiting for code line" mode.
   If the next clipboard text matches a line of code in that unit, it jumps to that line.
   If the clipboard text doesn't match any line, it exits the mode and resumes
   normal unit-name matching. This supports the workflow of copying a unit name
   from an external tool (GitHub, SonarQube) followed by copying a line of code to jump to.
=============================================================================================================}

INTERFACE

USES
  Winapi.Windows, Winapi.MMSystem,
  System.SysUtils, System.Classes, System.IniFiles, System.IOUtils, System.Types, System.Math,
  Vcl.Dialogs, Vcl.Clipbrd, Vcl.Menus, Vcl.Forms,
  ToolsAPI,
  uOpenFileIDE {this file can be found here: Github.com/GabrielOnDelphi/Delphi-LightSaber/tree/main/IDE%20Experts };

TYPE
  TFileFromClipboard = class(TInterfacedObject, IOTAWizard, IOTAIDENotifier)
  private
    FLastOpenedFile: string;       // Full path of the last unit we opened/switched to
    FWaitingForCodeLine: Boolean;  // True = next clipboard might be a code line to jump to
    procedure LoadSettings;
    function  TryExtractUnitName(const Path: string): string;
    function  TryJumpToCodeLine(const ClipText: string): Boolean;
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
    MaxLinesToSearch: Integer;  // How many lines from clipboard to search (default 1)
    BeepOnOpen: Boolean;        // Play sound when opening a file
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
USES uUtils, uClipMonForm, uClipboardListener;

VAR
   { Singleton Tools-menu entry. The IDE creates several wizard instances during startup (Register is
     called multiple times); without a singleton each instance adds its own duplicate menu item.
     OnClick is re-pointed to the newest instance; freed only by the instance it currently serves
     (same owner-guard pattern as FClipboardListener in uClipboardListener.pas). }
   SharedMenuItem: TMenuItem = nil;
   SharedMenuOwner: TFileFromClipboard = nil;


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
  DebugLog('=== TFileFromClipboard.Create START ===');
  inherited Create;

  ExcludeFolders:= TStringList.Create;
  ExcludeFolders.Delimiter:= ';';        // necessary for DelimitedText only, not for CommaText
  ExcludeFolders.StrictDelimiter:= True; // Without this, DelimitedText also splits on SPACES: 'C:\Program Files\x' would become 'C:\Program' + 'Files\x'
  Enabled:= True;
  MaxLinesToSearch:= 1;
  BeepOnOpen:= True;
  FLastOpenedFile:= '';
  FWaitingForCodeLine:= False;

  LoadSettings;

  // Initialize clipboard listener (must be done before form creation)
  DebugLog('TFileFromClipboard.Create: Initializing clipboard listener');
  InitClipboardListener(Self);

  // Use the singleton form for settings UI
  DebugLog('TFileFromClipboard.Create: Getting singleton ClipMonForm');
  MonitorForm := ClipMonForm;
  (MonitorForm as TClipMonFrm).SetExpert(Self);
  DebugLog('TFileFromClipboard.Create: ClipMonForm configured');
  Log('Expert.Constructor');
  //(MonitorForm as TClipMonFrm).Show;

  // Tools menu entry: create the singleton once, then re-point it to this (newest) instance,
  // so the several wizard instances created at IDE startup never show duplicate entries.
  if Supports(BorlandIDEServices, INTAServices, NTAServices) then
  begin
    if SharedMenuItem = nil then
    begin
      SharedMenuItem:= TMenuItem.Create(Application);
      SharedMenuItem.Caption:= 'File From Clipboard';
      // 'ToolsMenu' is the correct name for the top-level Tools menu.
      NTAServices.AddActionMenu('ToolsMenu', nil, SharedMenuItem);
    end;
    SharedMenuItem.OnClick:= ShowPluginOptions;
    SharedMenuOwner:= Self;
  end;

  // Initial check
  ProcessClipboard;
  DebugLog('=== TFileFromClipboard.Create END ===');
end;


destructor TFileFromClipboard.Destroy;
begin
  DebugLog('TFileFromClipboard.Destroy: START');

  // Save only if this instance is the one bound to the settings form (the one the user could have edited).
  // The IDE creates several wizard instances during startup (Register is called multiple times);
  // a stale instance destroyed later must not overwrite the INI with the old values it loaded at startup.
  // Also guards against a partially-constructed object (constructor failed before creating the form/ExcludeFolders).
  if (MonitorForm <> nil) and (MonitorForm as TClipMonFrm).BoundTo(Self)
  then SaveSettings;

  // CRITICAL: Free the clipboard listener NOW, not in finalization!
  // During package reinstall, the old AllocateHWnd window survives but its WndProc
  // code gets unloaded. If we don't free it here, the orphan window receives
  // WM_CLIPBOARDUPDATE and tries to execute unloaded code → CRASH.
  // Freed only if the listener still serves THIS instance (see FreeClipboardListener).
  FreeClipboardListener(Self);

  // Do NOT free MonitorForm - it's a singleton that must persist for IDE lifetime
  // The form will be freed in the finalization section
  if MonitorForm <> nil
  then (MonitorForm as TClipMonFrm).DetachExpert(Self);  // Otherwise the form would keep a dangling pointer to this destroyed instance
  MonitorForm := nil;
  // Release the menu item only if it still serves THIS instance (same guard as FreeClipboardListener):
  // an old instance destroyed by the IDE must not remove the menu the newest instance still uses.
  if SharedMenuOwner = Self then
  begin
    FreeAndNil(SharedMenuItem);
    SharedMenuOwner:= nil;
  end;
  FreeAndNil(ExcludeFolders);
  DebugLog('TFileFromClipboard.Destroy: END');

  inherited;
end;



{-------------------------------------------------------------------------------------------------------------
   MAIN
-------------------------------------------------------------------------------------------------------------}
procedure TFileFromClipboard.Execute;
begin
  //ProcessClipboard;
end;


{ Checks if ClipText is a line of code in FLastOpenedFile.
  If found, jumps to that line and returns True (stay in waiting state).
  If not found, returns False (caller should exit waiting state). }
function TFileFromClipboard.TryJumpToCodeLine(const ClipText: string): Boolean;
var
  Lines: TStringList;
  SearchLine, TargetFile: string;
  LineNum, i: Integer;
  DoBeep: Boolean;
begin
  Result:= False;
  if FLastOpenedFile = '' then Exit;

  // Extract first non-empty line from clipboard
  Lines:= TStringList.Create;
  try
    Lines.Text:= ClipText;
    SearchLine:= '';
    for i:= 0 to Lines.Count - 1 do
    begin
      SearchLine:= Trim(Lines[i]);
      if SearchLine <> '' then Break;
    end;
  finally
    FreeAndNil(Lines);
  end;

  if SearchLine = '' then Exit;

  // Search for this line in the last opened file
  LineNum:= FindLineInFile(FLastOpenedFile, SearchLine);
  if LineNum < 0 then
  begin
    Log('  Code line not found in ' + ExtractFileName(FLastOpenedFile) + ': ' + Copy(SearchLine, 1, 80));
    Exit;
  end;

  Log('  Jumping to line ' + IntToStr(LineNum) + ' in ' + ExtractFileName(FLastOpenedFile));
  DebugLog('TryJumpToCodeLine: Found at line ' + IntToStr(LineNum));

  // Capture locals, not fields: the deferred closure must not touch Self,
  // because the IDE can destroy this wizard instance before the queued call runs.
  TargetFile:= FLastOpenedFile;
  DoBeep    := BeepOnOpen;

  // TThread.Queue executes IMMEDIATELY when called from the main thread (verified in System.Classes).
  // ForceQueue truly defers the OTA call until the IDE's message loop is idle.
  TThread.ForceQueue(nil,
    procedure
    begin
      if GotoLineInOpenFile(TargetFile, LineNum)
      and DoBeep
      then PlaySound('SystemAsterisk', 0, SND_ALIAS or SND_ASYNC);
    end);

  Result:= True;
end;


// Why is this called twice?
procedure TFileFromClipboard.ProcessClipboard;
var
  ClipboardText, Line, FileName, FullPath, UnitName: string;
  Lines: TStringList;
  I: Integer;
  DoBeep: Boolean;
begin
  DebugLog('ProcessClipboard: START');
  if NOT Enabled then
    begin
      Log('Expert disabled!');
      DebugLog('ProcessClipboard: Expert disabled');
      Exit;
    end;

  // Read clipboard - check for both ANSI and Unicode text formats
  Log('');
  if NOT (Clipboard.HasFormat(CF_TEXT) OR Clipboard.HasFormat(CF_UNICODETEXT)) then
    begin
      Log('The clipboard is not text!');
      DebugLog('ProcessClipboard: Clipboard is not text (no CF_TEXT or CF_UNICODETEXT)');
      Exit;
    end;
  try
    ClipboardText := Clipboard.AsText;
  except
    on E: EClipboardException do
      begin
        Log('Expert.EClipboardException!');
        DebugLog('ProcessClipboard: EClipboardException - ' + E.Message);
        Exit;                          // Silently handle access denied or other clipboard errors like "Cannot open clipboard: Access is denied"
      end;
  end;

  DebugLog('ProcessClipboard: ClipboardText length=' + IntToStr(Length(ClipboardText)));
  DebugLog('ProcessClipboard: First 200 chars: ' + Copy(ClipboardText, 1, 200));
  Log('ProcessClipboard');
  Log('  First 512 chars: '+ Copy(ClipboardText, 1, 512));

  // STATE: If we recently opened a unit, check if the clipboard is a code line in that unit
  if FWaitingForCodeLine then
  begin
    if TryJumpToCodeLine(ClipboardText)
    then Exit;  // Successfully jumped to the line, stay in waiting state
    // Not a code line in the unit - exit waiting state, fall through to unit matching
    FWaitingForCodeLine:= False;
    Log('  Code-line matching deactivated. Resuming unit matching.');
  end;

  Lines:= TStringList.Create;
  try
    Lines.Text:= ClipboardText;
    // Only search the first MaxLinesToSearch lines (user configurable, default 1)
    for i:= 0 to Min(Lines.Count - 1, MaxLinesToSearch - 1) do
    begin
      Line:= Trim(Lines[I]);
      if Line = '' then Continue;

      if Pos('.', Line) < 1 then
      begin
        Log('  Text in clipboard: Not a file.');
        Continue;
      end;

      // Replace / with \ to handle Linux-style paths (SonarQube uses Linux paths)
      Line:= StringReplace(Line, '/', '\', [rfReplaceAll]);

      // Handle full paths or unit names (e.g., c:\path\file.pas or MyBase.MyUnit.pas)
      UnitName:= TryExtractUnitName(Line);
      FileName:= ExtractFileName(UnitName);
      Log('  UnitName: '+ UnitName);

      if NOT IsDelphiFile(FileName) then
        begin
          Log('  Text in clipboard: Not a Delphi file: '+ FileName);
          Continue;
        end;

      // Resolve full file path
      if TFile.Exists(Line)
      then FullPath := Line
      else FullPath := SearchFileInPath(FileName);

      // Check for exclusion (must be AFTER FullPath is assigned)
      if IsFileExcluded(FullPath) then
        Continue;

      if FullPath <> '' then
      begin
        // Enter "waiting for code line" state: next clipboard might be a line to jump to
        FLastOpenedFile:= FullPath;
        FWaitingForCodeLine:= True;
        Log('  Code-line matching active for: ' + ExtractFileName(FullPath));

        // Local copy: the deferred closure must not touch Self (the IDE can destroy this wizard instance before the queued call runs)
        DoBeep:= BeepOnOpen;

        // CRITICAL: Schedule the OTA call (OpenFileInIDE) to run later when the IDE's main message loop is idle.
        // TThread.Queue executes IMMEDIATELY when called from the main thread (verified in System.Classes), so ForceQueue is required for real deferral.
        TThread.ForceQueue(nil,
          procedure
          begin
            // Check if file is already open - if so, just switch to it without changing cursor
            if NOT SwitchToOpenFile(FullPath) then
              begin
                // File not already open, open it
                VAR IDEPosition: RIDEPosition;
                IDEPosition.default(FullPath);
                OpenInIDEEditor(IDEPosition);
              end;

            // Beep to notify user that file was opened/switched
            if DoBeep
            then PlaySound('SystemAsterisk', 0, SND_ALIAS or SND_ASYNC);
          end);

        Break; // Found the file, break the loop
      end;
    end;
  finally
    FreeAndNil(Lines);
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
      if Trim(ExcludePath) = '' then Continue;

      // Ensure the exclusion path is lower-cased and has a trailing path delimiter
      // for accurate subfolder matching (e.g., 'c:\tools' must match 'c:\tools\subfolder').
      // Trim first: with StrictDelimiter=True (see ctor) TStringList no longer trims whitespace
      // around each delimited item, so a user-typed 'A; B' keeps the leading space on 'B',
      // which would otherwise never match any real path.
      ExcludePath2:= LowerCase(IncludeTrailingPathDelimiter(Trim(ExcludePath)));

      if Pos(ExcludePath2, LowerCase(FullPath)) > 0 then
      begin
        Log('Path excluded!'
               + #13 + ' ExcludePath: '+ExcludePath2
               + #13 + ' Input file: '+ FullPath);
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
    // Hide exceptions like EInOutArgumentException "Invalid characters in search pattern".
    // No dialog here: any app copying text such as 'my"file.pas' to the clipboard would pop a modal in the IDE,
    // and ShowMessage pumps messages (re-entrancy into ProcessClipboard). Log and bail out instead.
    on E: Exception do
      begin
        Log('SearchFileInPath: ' + E.ClassName + ': ' + E.Message);
        DebugLog('SearchFileInPath: ' + E.ClassName + ': ' + E.Message);
        Exit;
      end;
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
  // Return wsEnabled based on the Enabled setting so IDE reflects the wizard state
  if Enabled
  then Result:= [wsEnabled]
  else Result:= [];
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
end;

procedure TFileFromClipboard.BeforeCompile(const Project: IOTAProject; var Cancel: Boolean);
begin
end;

procedure TFileFromClipboard.FileNotification(NotifyCode: TOTAFileNotification; const FileName: string; var Cancel: Boolean);
begin
end;




{-------------------------------------------------------------------------------------------------------------
   SETTINGS
   INI file is located in: %APPDATA%\FileFromClipboard\FileFromClipboard.ini
-------------------------------------------------------------------------------------------------------------}
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
    MaxLinesToSearch:= Ini.ReadInteger('ExpertSettings', 'MaxLinesToSearch', 1);
    BeepOnOpen:= Ini.ReadBool('ExpertSettings', 'BeepOnOpen', True);
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
    Ini.WriteString ('ExpertSettings', 'SearchPath', SearchPath);
    Ini.WriteString ('ExpertSettings', 'ExcludeFolders', ExcludeFolders.DelimitedText);
    Ini.WriteBool   ('ExpertSettings', 'Enabled', Enabled);
    Ini.WriteBool   ('ExpertSettings', 'LogActive', LogActive);
    Ini.WriteInteger('ExpertSettings', 'MaxLinesToSearch', MaxLinesToSearch);
    Ini.WriteBool   ('ExpertSettings', 'BeepOnOpen', BeepOnOpen);
  finally
    Ini.Free;
  end;
end;



// Show form
procedure TFileFromClipboard.ShowPluginOptions(Sender: TObject);
begin
  // Re-bind first: the singleton form could still point to an older wizard instance
  // that the IDE has already destroyed (Register is called multiple times at startup).
  ClipMonForm.SetExpert(Self);
  ClipMonForm.Show;
end;


procedure Register;
begin
  DebugLog('=== Register procedure START ===');
  var Wizard:= TFileFromClipboard.Create;
  DebugLog('Register: Wizard created, calling RegisterPackageWizard');
  RegisterPackageWizard(Wizard as IOTAWizard);
  DebugLog('=== Register procedure END ===');
end;


end.

