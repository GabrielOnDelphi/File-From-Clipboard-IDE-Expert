unit uClipMonForm;

{=============================================================================================================
   www.GabrielMoraru.com
   2026.07.06
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   Settings form for the File From Clipboard IDE expert.
   This form is used only for the settings UI, not for clipboard message handling.
   See uClipboardListener.pas for the clipboard monitoring implementation.
=============================================================================================================}

INTERFACE

USES
  Winapi.Windows, System.SysUtils, System.Classes, System.IniFiles,
  Vcl.Controls, Vcl.Forms, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Samples.Spin,
  uClipMonExpert, Vcl.Mask;

TYPE
  TClipMonFrm = class(TForm)
    btnApply: TButton;
    btnCancel: TButton;
    chkEnable: TCheckBox;
    edtExcluded: TLabeledEdit;
    edtSearchPath: TLabeledEdit;
    Log: TMemo;
    PageControl1: TPageControl;
    Panel2: TPanel;
    tabLog: TTabSheet;
    TabSheet2: TTabSheet;
    chkActivateLog: TCheckBox;
    spnMaxLines: TSpinEdit;
    lblMaxLines: TLabel;
    chkBeepOnOpen: TCheckBox;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnApplyClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure chkActivateLogClick(Sender: TObject);
  private
    procedure SaveFormPos;
    procedure LoadFormPos;
  protected
    Expert: TFileFromClipboard;
  public
    procedure SetExpert(aExpert: TFileFromClipboard);
    procedure DetachExpert(aExpert: TFileFromClipboard);        // Clears Expert, but only if it still points to aExpert
    function  BoundTo(aExpert: TFileFromClipboard): Boolean;    // True if this form is currently bound to aExpert
  end;

function ClipMonForm: TClipMonFrm;

IMPLEMENTATION {$R *.dfm}

USES
  uUtils;

var
  FClipMonForm: TClipMonFrm = nil;


function ClipMonForm: TClipMonFrm;
begin
  if FClipMonForm = nil then
  begin
    DebugLog('ClipMonForm: Creating singleton');
    FClipMonForm := TClipMonFrm.Create(nil);
  end;
  Result := FClipMonForm;
end;


procedure TClipMonFrm.SetExpert(aExpert: TFileFromClipboard);
begin
  DebugLog('TClipMonFrm.SetExpert');
  Expert := aExpert;
  if Expert = nil then Exit;

  // Form properties
  Caption := 'Gabriel Moraru - Clipboard Monitor Expert';
  LoadFormPos;

  // Load settings from expert
  chkEnable.Checked      := Expert.Enabled;
  edtSearchPath.Text     := Expert.SearchPath;
  edtExcluded.Text       := Expert.ExcludeFolders.DelimitedText;
  chkActivateLog.Checked := Expert.LogActive;
  spnMaxLines.Value      := Expert.MaxLinesToSearch;
  chkBeepOnOpen.Checked  := Expert.BeepOnOpen;
end;


{ Called from the wizard's destructor. The IDE creates/destroys several wizard instances
  during startup; this form is a session-long singleton, so a destroyed wizard must remove
  its (now dangling) pointer - but only if a newer instance has not already taken over. }
procedure TClipMonFrm.DetachExpert(aExpert: TFileFromClipboard);
begin
  if Expert = aExpert then
    begin
      DebugLog('TClipMonFrm.DetachExpert');
      Expert := nil;
    end;
end;


function TClipMonFrm.BoundTo(aExpert: TFileFromClipboard): Boolean;
begin
  Result := (Expert = aExpert) and (aExpert <> nil);
end;


procedure TClipMonFrm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveFormPos;
  Action := TCloseAction.caHide;
end;


procedure TClipMonFrm.btnApplyClick(Sender: TObject);
begin
  if Expert = nil then    // The wizard that was bound to this form is already destroyed
    begin
      Close;
      EXIT;
    end;

  Expert.Enabled         := chkEnable.Checked;
  Expert.SearchPath      := edtSearchPath.Text;
  Expert.ExcludeFolders.DelimitedText := edtExcluded.Text;
  Expert.LogActive       := chkActivateLog.Checked;
  Expert.MaxLinesToSearch:= spnMaxLines.Value;
  Expert.BeepOnOpen      := chkBeepOnOpen.Checked;
  Expert.SaveSettings;
  Close;
end;


procedure TClipMonFrm.btnCancelClick(Sender: TObject);
begin
  Close;
end;


procedure TClipMonFrm.chkActivateLogClick(Sender: TObject);
begin
  if Expert = nil then EXIT;   // The wizard that was bound to this form is already destroyed
  Expert.LogActive := chkActivateLog.Checked;
end;


procedure TClipMonFrm.SaveFormPos;
var Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    Ini.WriteInteger('FrmMonitor', 'Left', Left);
    Ini.WriteInteger('FrmMonitor', 'Top', Top);
  finally
    Ini.Free;
  end;
end;


procedure TClipMonFrm.LoadFormPos;
var Ini: TIniFile;
begin
  Ini := TIniFile.Create(GetIniPath);
  try
    Left := Ini.ReadInteger('FrmMonitor', 'Left', 10);
    Top  := Ini.ReadInteger('FrmMonitor', 'Top', 10);
  finally
    Ini.Free;
  end;
end;




initialization

finalization
  FreeAndNil(FClipMonForm);

end.
