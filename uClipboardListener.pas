unit uClipboardListener;

{=============================================================================================================
   www.GabrielMoraru.com
   2024
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   CLIPBOARD MONITORING
   --------------------
   This unit implements clipboard monitoring using a dedicated message-only window.

   Why not use a form's handle directly?
   -------------------------------------
   During IDE startup, the package's Register procedure is called multiple times, and the IDE
   destroys/recreates wizard instances. VCL form handles are also destroyed and recreated
   during this process. If we register the clipboard listener on a form's handle, it gets
   removed when VCL destroys the handle (~1 second after registration), leaving us with no
   active listener.

   Solution: TClipboardListener
   ----------------------------
   We use AllocateHWnd to create a dedicated message-only window that is independent of VCL's
   form handle management. This window:
   - Is created via InitClipboardListener when the wizard starts
   - Is destroyed via FreeClipboardListener when the wizard is destroyed
   - Receives WM_CLIPBOARDUPDATE messages reliably

   Note: We free the clipboard listener in the wizard's destructor, NOT in finalization.
   During finalization, VCL is partially destroyed and DeallocateHWnd causes crashes.
=============================================================================================================}

INTERFACE

USES
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  uClipMonExpert;

type
  TClipboardListener = class
  private
    FHandle: HWND;
    FExpert: TFileFromClipboard;
    procedure WndProc(var Msg: TMessage);
  public
    constructor Create;
    destructor Destroy; override;
    property Handle: HWND read FHandle;
    property Expert: TFileFromClipboard read FExpert write FExpert;
  end;

procedure InitClipboardListener(aExpert: TFileFromClipboard);
procedure FreeClipboardListener;

IMPLEMENTATION

USES uUtils;

var
  FClipboardListener: TClipboardListener = nil;


constructor TClipboardListener.Create;
var
  Success: BOOL;
begin
  inherited Create;
  DebugLog('TClipboardListener.Create: Allocating message window');
  FHandle := AllocateHWnd(WndProc);
  DebugLog('TClipboardListener.Create: Handle=' + IntToHex(FHandle, 8));

  Success := AddClipboardFormatListener(FHandle);
  DebugLog('TClipboardListener.Create: AddClipboardFormatListener=' + BoolToStr(Success, True));
  if not Success
  then DebugLog('TClipboardListener.Create: GetLastError=' + IntToStr(GetLastError));
end;


destructor TClipboardListener.Destroy;
begin
  DebugLog('TClipboardListener.Destroy');
  if FHandle <> 0 then
    begin
      RemoveClipboardFormatListener(FHandle);
      DeallocateHWnd(FHandle);
      FHandle := 0;
    end;
  inherited;
end;


procedure TClipboardListener.WndProc(var Msg: TMessage);
begin
  if Msg.Msg = WM_CLIPBOARDUPDATE
  then
    begin
      DebugLog('TClipboardListener: WM_CLIPBOARDUPDATE received');
      if Assigned(FExpert)
      then FExpert.ProcessClipboard;
      Msg.Result:= 0;
    end
  else
    Msg.Result:= DefWindowProc(FHandle, Msg.Msg, Msg.WParam, Msg.LParam);
end;


procedure InitClipboardListener(aExpert: TFileFromClipboard);
begin
  if FClipboardListener = nil then
    begin
      DebugLog('InitClipboardListener: Creating');
      FClipboardListener:= TClipboardListener.Create;
    end;
  FClipboardListener.Expert:= aExpert;
end;


procedure FreeClipboardListener;
begin
  DebugLog('FreeClipboardListener');
  FreeAndNil(FClipboardListener);
end;


initialization

finalization
  // Do NOT call FreeClipboardListener here.
  // During IDE shutdown, VCL is partially destroyed and DeallocateHWnd
  // triggers window messages that cause "Control has no parent" crashes.
  // The process is ending anyway - Windows will clean up the handle.

end.
