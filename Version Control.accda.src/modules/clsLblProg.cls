﻿VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsLblProg"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'---------------------------------------------------------------------------------------
' Module    : clsLblProg
' Author    : Adam Waller
' Date      : 5/20/2022
' Purpose   : Display a progress bar using three labels on a form
'---------------------------------------------------------------------------------------
Option Explicit


' Set the application name here to utilize the appropriate
' object types in early binding.
#Const APPLICATION_NAME = "Microsoft Access"

' Color constants
Private Const lngColorNavy As Long = 8388608    ' Default progress bar color (Navy Blue)
Private Const lngColorWhite As Long = 16777215  ' Caption over blue background (White)
Private Const lngColorBlack As Long = 0         ' Caption over grey background (Black)
Private Const lngColorGrey As Long = 12566463   ' Back label color (Grey)

' Public properties
Public Smooth As Boolean                ' Set to true for smooth updates < 1%
Public Max As Double                    ' Max total value of progress bar

' General style of progress bar
Public Enum eProgressBarStyle
    epbTraditional  ' Sunken style back label, inset bar
    epbModernFlat   ' Flat, equally sized progress bar, no border
End Enum

' Private properties
Private Type udtProg

    ' Application specific properties
    #If APPLICATION_NAME = "Microsoft Access" Then
        ' Use Access specific controls/sizing
        lblBack As Access.Label         ' Existing label for back
        lblFront As Access.Label        ' Label for moving bar
        lblCaption As Access.Label      ' Progress bar caption
    #Else
        ' Generic VBA objects
        lblBack As MSForms.Label        ' Existing label for back
        lblFront As MSForms.Label       ' Label created for front
        lblCaption As MSForms.Label     ' Label created for caption
    #End If

    ' Shared private properties
    dblValue As Double                  ' Current value of progress bar
    dblDisplayed As Double              ' Displayed value
    dblFullWidth As Double              ' Width of front label at 100%
    sngOffset As Single                 ' Offset for front label
    blnCaptionVisible As Boolean        ' Show/hide percent complete caption
    objParent As Object                 ' Parent object of back label (in MSForms 2.0)
    dteStartTime As Date                ' Time of first value change
    sngRepaintInterval As Single        ' Seconds between updates
End Type
Private this As udtProg


' Fires when the value of the progress bar changes.
' (This can be used to set a custom caption)
Public Event ProgressChange(dblValue As Double, intPercent As Integer)


'---------------------------------------------------------------------------------------
' Procedure : Initialize
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Initialize the progress bar before using it. Include a caption label
'           : if you want to display the percentage complete after updates.
'---------------------------------------------------------------------------------------
'
#If APPLICATION_NAME = "Microsoft Access" Then
    Public Sub Initialize(BackLabel As Label _
                        , FrontLabel As Label _
                        , Optional CaptionLabel As Label _
                        , Optional BarStyle As eProgressBarStyle = epbTraditional)
#Else
    Public Sub Initialize(BackLabel As MSForms.Label _
                        , Optional FrontLabel As MSForms.Label _
                        , Optional CaptionLabel As MSForms.Label _
                        , Optional BarStyle As eProgressBarStyle = epbTraditional)
#End If

    Set this.lblBack = BackLabel

    #If APPLICATION_NAME = "Microsoft Access" Then
        this.sngOffset = 15
        ' Verify front label (not optional for Microsoft Access)
        If FrontLabel Is Nothing Then
            MsgBox "Missing required front label for progress bar" & vbCrLf & _
                "This parameter is required when using Microsoft Access.", vbExclamation
            Exit Sub
        End If
        ' Use existing controls
        Set this.lblFront = FrontLabel
        Set this.lblCaption = CaptionLabel
    #Else
        this.sngOffset = 1.5
        ' Create front controls dynamically
        Set this.objParent = GetParentFormName(BackLabel)
        Set this.lblFront = this.objParent.Controls.Add("forms.label.1", "", False)
        Set this.lblCaption = this.objParent.Controls.Add("forms.label.1", "", False)
        ' Refresh display of parent form
        this.objParent.Repaint
    #End If

    ' Set style-specific properties
    If BarStyle = epbTraditional Then
        this.lblBack.SpecialEffect = 2
    ElseIf BarStyle = epbModernFlat Then
        this.sngOffset = 0
        this.lblBack.SpecialEffect = 0
        this.lblBack.BackStyle = 1
        this.lblBack.BackColor = lngColorGrey
    End If

    ' Properties for back label
    SetVisibility this.lblBack, True

    ' Set properties for front label
    With this.lblFront
        this.dblFullWidth = this.lblBack.Width - (this.sngOffset * 2)
        .Left = this.lblBack.Left + this.sngOffset
        .Top = this.lblBack.Top + this.sngOffset
        .Width = 0
        .Height = this.lblBack.Height - (this.sngOffset * 2)
        .Caption = vbNullString
        .BackColor = lngColorNavy
        .BackStyle = 1      ' Opaque
        .SpecialEffect = 0  ' Flat
    End With

    ' Passing in a caption label is optional
    If Not this.lblCaption Is Nothing Then
        ' set properties for caption label
        this.blnCaptionVisible = True ' Turn this on as needed.
        With this.lblCaption
            .Top = this.lblBack.Top + (this.sngOffset * 1.33)
            .Left = this.lblBack.Left + (this.sngOffset * 2)
            .Width = this.lblBack.Width - (this.sngOffset * 4)
            .TextAlign = 2 'fmTextAlignCenter
            .BackStyle = 0 ' fmBackStyleTransparent
            .Caption = "0%"
            .ForeColor = lngColorBlack
        End With
    End If

    ' Set default repaint interval to once every second
    this.sngRepaintInterval = 1

    ' Update the display immediately
    UpdateDisplay True

End Sub



'---------------------------------------------------------------------------------------
' Procedure : BarColor & BackColor
' Author    : Adam Waller
' Date      : 5/31/2022
' Purpose   : Publicly expose some properties for ease of customization
'---------------------------------------------------------------------------------------
'
Public Property Get BarColor() As Long
    BarColor = this.lblFront.BackColor
End Property
Public Property Let BarColor(NewVal As Long)
    this.lblFront.BackColor = NewVal
End Property
Public Property Get BackColor() As Long
    BarColor = this.lblBack.BackColor
End Property
Public Property Let BackColor(NewVal As Long)
    this.lblBack.BackColor = NewVal
End Property


'---------------------------------------------------------------------------------------
' Procedure : CaptionVisible
' Author    : Adam Waller
' Date      : 5/31/2022
' Purpose   : Expose properties for caption visibility
'---------------------------------------------------------------------------------------
'
Public Property Get CaptionVisible() As Boolean
    CaptionVisible = this.blnCaptionVisible
End Property
Public Property Let CaptionVisible(NewVal As Boolean)
    With this
        If .blnCaptionVisible <> NewVal Then
            .blnCaptionVisible = NewVal
            If Not .lblCaption Is Nothing Then
                SetVisibility .lblCaption, .blnCaptionVisible
            Else
                ' If the control isn't present, it's never visible.
                .blnCaptionVisible = False
            End If
        End If
    End With
End Property


'---------------------------------------------------------------------------------------
' Procedure : SetRepaintInterval
' Author    : Adam Waller
' Date      : 6/3/2022
' Purpose   : Set how frequently to repaint the screen (DoEvents)
'---------------------------------------------------------------------------------------
'
Public Function SetRepaintInterval(sngSeconds As Single)
    this.sngRepaintInterval = sngSeconds
End Function


'---------------------------------------------------------------------------------------
' Procedure : Value
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Get the current value of the progress bar.
'---------------------------------------------------------------------------------------
'
Public Property Get Value() As Double
    Value = this.dblValue
End Property


'---------------------------------------------------------------------------------------
' Procedure : Value
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Set the value of the progress bar, adjusting to fit within Max
'---------------------------------------------------------------------------------------
'
Public Property Let Value(ByVal dblValue As Double)

    Dim dblChange As Double

    ' Don't allow value to exceed maximum value
    If dblValue > Me.Max Then
        this.dblValue = Me.Max
    ElseIf dblValue < 0 Then
        this.dblValue = 0
    Else
        ' Update value property
        this.dblValue = dblValue
    End If

    ' Record start time on first change
    If this.dteStartTime = 0 Then this.dteStartTime = Now

    ' Measure change from currently displayed value
    dblChange = Abs(this.dblValue - this.dblDisplayed)

    ' Set value and update display if needed.
    If dblChange > 0 And Me.Max > 0 Then
        ' See if we need to update the display
        ' (Normally updated every 1% or each increment if Smooth = True)
        If Me.Smooth Or ((dblChange / Me.Max) > 0.01) Then UpdateDisplay
    End If

End Property


'---------------------------------------------------------------------------------------
' Procedure : Increment
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Increment the progress bar by 1, or by a custom amount, if desired.
'           : Normally used without arguments.
'---------------------------------------------------------------------------------------
'
Public Sub Increment(Optional dblAmount As Double = 1)
    Me.Value = Me.Value + dblAmount
End Sub


'---------------------------------------------------------------------------------------
' Procedure : EstCompletionTime
' Author    : Adam Waller
' Date      : 4/21/2022
' Purpose   : Return an estimated completion time based on the start date and remaining
'           : segments. (Simple calculation assuming even increment intervals.)
'           : Note that the START time is set at the COMPLETION of the first segment,
'           : so the first segment is not included in the time calculation.
'---------------------------------------------------------------------------------------
'
Public Property Get EstCompletionTime() As Date

    Dim dblSeconds As Double
    Dim dblRemaining As Double

    If this.dteStartTime = 0 Then
        EstCompletionTime = Now
    Else
        With this
            ' Get elapsed seconds
            dblSeconds = DateDiff("s", .dteStartTime, Now)
            ' Calculate remaining seconds
            If .dblValue > 1 Then dblRemaining = (dblSeconds / (.dblValue - 1)) * (Me.Max - .dblValue)
            ' Convert to completion time
            EstCompletionTime = DateAdd("s", dblRemaining, Now)
        End With
    End If

End Property


'---------------------------------------------------------------------------------------
' Procedure : EstRemainingTime
' Author    : Adam Waller
' Date      : 4/21/2022
' Purpose   : Return a string value with the estimated hours/minutes/seconds remaining.
'           : Example return values: "73 seconds", "41 minutes", "80 hours"
'---------------------------------------------------------------------------------------
'
Public Property Get EstRemainingTime() As String

    Dim dblSeconds As Double

    dblSeconds = DateDiff("s", Now, Me.EstCompletionTime)
    If dblSeconds < 120 Then ' Less than two minutes
        EstRemainingTime = dblSeconds & " seconds"
    ElseIf dblSeconds < (60 * 120) Then ' Less than 2 hours
        EstRemainingTime = dblSeconds \ 60 & " minutes"
    Else
        EstRemainingTime = dblSeconds \ 3600 & " hours"
    End If

End Property


'---------------------------------------------------------------------------------------
' Procedure : Clear
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Remove or hide front labels. (Will need to initialize again after this.)
'---------------------------------------------------------------------------------------
'
Public Sub Clear()
    Class_Terminate
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Reset
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Reset value back to zero. (Without changing Max)
'---------------------------------------------------------------------------------------
'
Public Sub Reset()
    this.dteStartTime = 0
    Me.Value = 0
    UpdateDisplay True
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Hide
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Hide the visible elements of the progress bar (but retain values)
'---------------------------------------------------------------------------------------
'
Public Sub Hide()
    SetVisibility this.lblBack, False
    SetVisibility this.lblFront, False
    SetVisibility this.lblCaption, False
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Update
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Update the display with an optional force parameter. (Normally updates
'           : every second to prevent a performance hit with frequent calls to the
'           : DoEvents function.)
'---------------------------------------------------------------------------------------
'
Public Sub UpdateDisplay(Optional blnForceUpdate As Boolean)

    Dim intPercent As Integer
    Dim dblWidth As Double

    Static sngLastUpdate As Single

    ' Set size and caption
    With this
        If Me.Max <= 0 Then
            intPercent = 0
            dblWidth = 0
        ElseIf .dblValue >= Me.Max Then
            intPercent = 100
            .dblValue = Me.Max
            dblWidth = .dblFullWidth
        Else
            intPercent = .dblValue * (100 / Me.Max)
            dblWidth = .dblValue * (.dblFullWidth / Me.Max)
        End If

        ' See if we have a label assigned
        If .lblFront Is Nothing Then
            #If APPLICATION_NAME = "Microsoft Access" Then
                ' Use system progress meter at bottom right of
                ' the Microsoft Access application window
                SysCmd acSysCmdInitMeter, "Working...", 100
                SysCmd acSysCmdUpdateMeter, intPercent
            #End If
        Else
            ' Adjust width of label to show progress
            .lblFront.Width = dblWidth
        End If

        ' Save currently displayed value
        .dblDisplayed = .dblValue

        ' Ensure controls are visible
        SetVisibility .lblBack, True
        SetVisibility .lblFront, True

        ' Set caption if we are using a caption
        If Not .lblCaption Is Nothing Then
            .lblCaption.Caption = intPercent & "%"
            SetVisibility .lblCaption, .blnCaptionVisible
            ' Verify caption color (black till 50%, then white)
            VerifyForeColor .lblCaption, IIf(intPercent > 50, lngColorWhite, lngColorBlack)
        End If
    End With

    ' Use DoEvents to repaint display
    If Me.Smooth Then
        ' Always update display
        RaiseEvent ProgressChange(this.dblValue, intPercent)
        DoEvents
    ElseIf (Abs(sngLastUpdate - Timer) > this.sngRepaintInterval) Or blnForceUpdate Then
        ' Update every second (or other specified interval),
        ' or when forcing an immediate update
        RaiseEvent ProgressChange(this.dblValue, intPercent)
        DoEvents
        sngLastUpdate = Timer
    End If

End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetParentFormName
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Return the name of the parent form
'---------------------------------------------------------------------------------------
'
Private Function GetParentFormName(ctlControl As Control) As String

    ' returns the name of the parent form
    Dim objParent As Object
    Dim lngRunCount As Long

    ' This is only used in other VBA applications, not Microsoft Access
    #If APPLICATION_NAME = "Microsoft Access" Then
        Exit Function
    #End If

    ' Walk up parent controls to find parent form.
    Set objParent = ctlControl
    Do While Not TypeName(objParent) = "UserForm" And lngRunCount < 100
        lngRunCount = lngRunCount + 1
        Set objParent = objParent.Parent
    Loop

    ' Now we should have the parent form
    GetParentFormName = objParent.Name

End Function


'---------------------------------------------------------------------------------------
' Procedure : SetVisibility
' Author    : Adam Waller
' Date      : 5/20/2022
' Purpose   : Set the visibility of the object if it exists and does not match the
'           : desired visibility setting.
'---------------------------------------------------------------------------------------
'
Private Sub SetVisibility(ctlObject As Control, blnVisible As Boolean)
    If Not ctlObject Is Nothing Then
        If ctlObject.Visible <> blnVisible Then ctlObject.Visible = blnVisible
    End If
End Sub


'---------------------------------------------------------------------------------------
' Procedure : VerifyForeColor
' Author    : Adam Waller
' Date      : 6/8/2022
' Purpose   : Sets the ForeColor property to match the desired value.
'---------------------------------------------------------------------------------------
'
Private Sub VerifyForeColor(ctlLabel As Control, lngForeColor As Long)
    If ctlLabel.ForeColor <> lngForeColor Then ctlLabel.ForeColor = lngForeColor
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Class_Terminate
' Author    : Adam Waller
' Date      : 2/17/2021
' Purpose   : Remove temporary controls, if applicable
'---------------------------------------------------------------------------------------
'
Private Sub Class_Terminate()

    ' Ignore any errors if object references are no longer valid
    On Error Resume Next
    #If APPLICATION_NAME = "Microsoft Access" Then
        ' Hide front controls
        Hide
        ' Remove any progress meter if not using labels
        If this.lblBack Is Nothing Then SysCmd acSysCmdRemoveMeter
    #Else
        ' Remove front controls
        SetVisibility this.lblBack, False
        this.objParent.Controls.Remove (this.lblFront.Name)
        this.objParent.Controls.Remove (this.lblCaption.Name)
    #End If

    ' Clear any remaining object references
    Set this.lblBack = Nothing
    Set this.lblFront = Nothing
    Set this.lblCaption = Nothing
    Set this.objParent = Nothing

    ' Clear any VBA errors
    If Err.Number <> 0 Then Err.Clear

End Sub
