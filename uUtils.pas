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


function IsDelphiFile(const FileName: string): Boolean;
function AppDataFolder(AppName: string; ForceDir: Boolean = FALSE): string;
function GetIniPath: string;


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


end.

