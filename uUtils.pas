unit uUtils;

{=============================================================================================================
   www.GabrielMoraru.com
   2024
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   General purpose function needed in order to keep this IDE expert separated from LightSaber
--------------------------------------------------------------------------------------------------------------}

INTERFACE

USES
  System.SysUtils, System.Classes, System.IOUtils, System.Types;

const
  // Set to True to enable debug logging to %APPDATA%\FileFromClipboard\debug.log
  DEBUG_LOG_ENABLED = False;

function IsDelphiFile(const FileName: string): Boolean;
function AppDataFolder(AppName: string; ForceDir: Boolean = FALSE): string;
function GetIniPath: string;
procedure DebugLog(const Msg: string);


implementation


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


procedure DebugLog(const Msg: string);
var
  F: TextFile;
  LogPath: string;
begin
  if not DEBUG_LOG_ENABLED then Exit;

  LogPath := AppDataFolder('FileFromClipboard', TRUE) + 'debug.log';
  AssignFile(F, LogPath);
  try
    if FileExists(LogPath) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' | ' + Msg);
    finally
      CloseFile(F);
    end;
  except
    // Silently ignore logging errors
  end;
end;


end.

