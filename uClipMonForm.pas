unit uClipMonForm;

{=============================================================================================================
   www.GabrielMoraru.com
   2024
   Github.com/GabrielOnDelphi/Delphi-LightSaber/blob/main/System/Copyright.txt
--------------------------------------------------------------------------------------------------------------
   This form is needed in order to receive the WMClipboardUpdate message from the OS.
   It also acts as a log (for debugging purposes).

   This form is not freed when we close it.
=============================================================================================================}

INTERFACE

USES
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.IniFiles,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Mask,
  uClipMonExpert;

TYPE
  TClipMonFrm = class(TForm)
    btnApply: TButton;
    btnCancel: TButton;
    chkActivateLog: TCheckBox;
    chkEnable: TCheckBox;
    edtExcluded: TLabeledEdit;
    edtSearchPath: TLabeledEdit;
    Log: TMemo;
    PageControl1: TPageControl;
    Panel2: TPanel;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure btnApplyClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
  private
    procedure SaveFormPos;
    procedure LoadFormPos;
  protected
    Expert: TFileFromClipboard;
    procedure WMClipboardUpdate(var Msg: TMessage); message WM_CLIPBOARDUPDATE;
  public
    constructor Create(AOwner: TComponent; aExpert: TFileFromClipboard); reintroduce;
    destructor Destroy; override;
  end;

IMPLEMENTATION {$R *.dfm}
USES uUtils;


constructor TClipMonFrm.Create(AOwner: TComponent; aExpert: TFileFromClipboard);
begin
  inherited Create(AOwner);
  Expert:= aExpert;
  if aExpert = nil then
    begin
      ShowMessage('TClipMonFrm.Create - Expert is nil!');
      Exit;
    end;

  // Form properties
  Caption := 'Gabriel Moraru - Clipboard Monitor Expert';
  Visible := False;
  LoadFormPos;

  // Get settings from the expert
  chkEnable.Checked     := Expert.Enabled;
  edtSearchPath.Text    := Expert.SearchPath;
  edtExcluded.Text      := Expert.ExcludeFolders.DelimitedText;
  chkActivateLog.Checked:= Expert.LogActive;

  // Add clipboard listener using this form's handle
  Winapi.Windows.AddClipboardFormatListener(Handle);
end;


procedure TClipMonFrm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveFormPos;
  Action:= TCloseAction.caHide;
  // Pass settings to the expert
  //btnApplyClick(Sender);
end;


destructor TClipMonFrm.Destroy;
begin
  SaveFormPos;
  RemoveClipboardFormatListener(Handle);
  inherited;
end;

//todo: force save expert here!
procedure TClipMonFrm.btnApplyClick(Sender: TObject);
begin
  // Pass settings to the expert (it will save these)
  Expert.Enabled:= chkEnable.Checked;
  Expert.SearchPath:= edtSearchPath.Text;
  Expert.ExcludeFolders.DelimitedText:= edtExcluded.Text;
  Expert.LogActive:= chkActivateLog.Checked;
  (Expert as TFileFromClipboard).SaveSettings;
end;


procedure TClipMonFrm.btnCancelClick(Sender: TObject);
begin
  Close;
end;


procedure TClipMonFrm.WMClipboardUpdate(var Msg: TMessage);
begin
  // The message comes in on the main VCL thread, so a TThread.Queue is not strictly necessary here, but we'll use it in the Expert to be safe when accessing IDE services.
  (Expert as TFileFromClipboard).ProcessClipboard;
end;




procedure TClipMonFrm.SaveFormPos;
var Ini: TIniFile;
begin
  Ini:= TIniFile.Create(GetIniPath);
  try
    Ini.WriteInteger('FrmMonitor', 'Left', Left);
    Ini.WriteInteger('FrmMonitor', 'Top',  Top);
  finally
    Ini.Free;
  end;
end;

procedure TClipMonFrm.LoadFormPos;
var Ini: TIniFile;
begin
  Ini:= TIniFile.Create(GetIniPath);
  try
    Left := Ini.ReadInteger('FrmMonitor', 'Left', 10);
    Top  := Ini.ReadInteger('FrmMonitor', 'Top',  10);
  finally
    Ini.Free;
  end;
end;


end.
