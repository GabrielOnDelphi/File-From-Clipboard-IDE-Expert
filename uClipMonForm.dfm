object ClipMonFrm: TClipMonFrm
  Left = 0
  Top = 0
  AlphaBlend = True
  AlphaBlendValue = 240
  BorderIcons = [biSystemMenu, biMinimize]
  Caption = 'Monitor'
  ClientHeight = 345
  ClientWidth = 384
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  RoundedCorners = rcOn
  ScreenSnap = True
  ShowHint = True
  SnapBuffer = 4
  OnClose = FormClose
  TextHeight = 15
  object Panel2: TPanel
    Left = 0
    Top = 312
    Width = 384
    Height = 33
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 0
    DesignSize = (
      384
      33)
    object btnApply: TButton
      Left = 216
      Top = 6
      Width = 75
      Height = 25
      Anchors = [akTop, akRight]
      Caption = 'OK'
      Default = True
      ModalResult = 1
      TabOrder = 0
      OnClick = btnApplyClick
    end
    object btnCancel: TButton
      Left = 303
      Top = 6
      Width = 75
      Height = 25
      Hint = 'Close without saving.'
      Anchors = [akTop, akRight]
      Cancel = True
      Caption = 'Cancel'
      ModalResult = 2
      TabOrder = 1
      OnClick = btnCancelClick
    end
  end
  object PageControl1: TPageControl
    Left = 0
    Top = 0
    Width = 384
    Height = 312
    ActivePage = TabSheet2
    Align = alClient
    TabOrder = 1
    object TabSheet2: TTabSheet
      Caption = 'Settings'
      ImageIndex = 1
      DesignSize = (
        376
        282)
      object chkEnable: TCheckBox
        Left = 15
        Top = 15
        Width = 165
        Height = 16
        Hint = 'Activate the plugin'
        Caption = 'Monitor clipboard'
        Checked = True
        State = cbChecked
        TabOrder = 0
      end
      object edtSearchPath: TLabeledEdit
        Left = 15
        Top = 72
        Width = 342
        Height = 23
        Hint = 
          'Open the file ONLY if it is in this folder (for the moment only ' +
          'one folder is accepted. sorry)'
        Anchors = [akLeft, akTop, akRight]
        EditLabel.Width = 62
        EditLabel.Height = 15
        EditLabel.Caption = 'Search path'
        TabOrder = 1
        Text = ''
        TextHint = 'C:\MyProjects'
      end
      object edtExcluded: TLabeledEdit
        Left = 15
        Top = 122
        Width = 342
        Height = 23
        Hint =
          'Files found in these folders will not be open in the IDE.'#13#10'Multi' +
          'ple paths allowed.'
        Anchors = [akLeft, akTop, akRight]
        EditLabel.Width = 87
        EditLabel.Height = 15
        EditLabel.Caption = 'Excluded folders'
        TabOrder = 2
        Text = ''
        TextHint = 'bin;C:\MyProjects\3rd_party'
      end
      object lblMaxLines: TLabel
        Left = 15
        Top = 165
        Width = 135
        Height = 15
        Caption = 'Max lines to search'
        FocusControl = spnMaxLines
      end
      object spnMaxLines: TSpinEdit
        Left = 15
        Top = 183
        Width = 60
        Height = 24
        Hint =
          'Only search the first N lines of clipboard text for filenames (d' +
          'efault: 1)'
        MaxValue = 100
        MinValue = 1
        TabOrder = 3
        Value = 1
      end
      object chkBeepOnOpen: TCheckBox
        Left = 15
        Top = 220
        Width = 200
        Height = 17
        Hint = 'Play a sound when a file is opened or switched to'
        Caption = 'Beep when opening file'
        Checked = True
        State = cbChecked
        TabOrder = 4
      end
    end
    object tabLog: TTabSheet
      Caption = 'Log'
      object Log: TMemo
        AlignWithMargins = True
        Left = 3
        Top = 19
        Width = 370
        Height = 260
        Align = alClient
        ScrollBars = ssVertical
        TabOrder = 0
        WordWrap = False
      end
      object chkActivateLog: TCheckBox
        Left = 0
        Top = 0
        Width = 376
        Height = 16
        Align = alTop
        Caption = 'Activate log'
        Checked = True
        State = cbChecked
        TabOrder = 1
        OnClick = chkActivateLogClick
      end
    end
  end
end
