﻿VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsDbNavPaneGroup"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'---------------------------------------------------------------------------------------
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This class extends the IDbComponent class to perform the specific
'           : operations required by this particular object type.
'           : (I.e. The specific way you export or import this component.)
'---------------------------------------------------------------------------------------
Option Compare Database
Option Explicit

Private m_Items(True To False) As Dictionary
Private m_dItems As Dictionary

' This requires us to use all the public methods and properties of the implemented class
' which keeps all the component classes consistent in how they are used in the export
' and import process. The implemented functions should be kept private as they are called
' from the implementing class, not this class.
Implements IDbComponent


'---------------------------------------------------------------------------------------
' Procedure : Export
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Export the individual database component (table, form, query, etc...)
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Export(Optional strAlternatePath As String)
    Dim strContent As String
    strContent = GetSource
    WriteFile strContent, Nz2(strAlternatePath, IDbComponent_SourceFile)
    VCSIndex.Update Me, IIf(strAlternatePath = vbNullString, eatExport, eatAltExport), GetStringHash(strContent, True)
End Sub


'---------------------------------------------------------------------------------------
' Procedure : Import
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Import the individual database component from a file.
'           : Here we are writing information directly to the system tables since
'           : Microsoft Access does not provide a way to do this programatically.
'           : Helpful links: https://stackoverflow.com/questions/26523619
'           : and https://stackoverflow.com/questions/27366038
'           : https://support.microsoft.com/en-us/office/customize-the-navigation-pane-ccfb0ee7-d72f-4923-b4fb-ed6c15484244
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Import(strFile As String)

    Dim dFile As Dictionary
    Dim intGroup As Integer
    Dim intCategory As Integer
    Dim dGroup As Dictionary
    Dim dCategory As Dictionary
    Dim lngGroupID As Long
    Dim lngCategoryID As Long
    Dim intObject As Integer
    Dim dObject As Dictionary
    Dim lngObjectID As Long
    Dim lngLinkID As Long

    ' Only import files with the correct extension.
    If Not strFile Like "*.json" Then Exit Sub

    Set dFile = ReadJsonFile(strFile)
    If Not dFile Is Nothing Then

        ' Upgrade from any previous formats
        Set m_dItems = dFile

        ' Remove any existing custom groups (Some may be automatically created with a new database)
        ClearExistingNavGroups

        ' Import custom navigation categories/groups
        If m_dItems("Items").Exists("Categories") Then

            ' Loop through custom categories
            For intCategory = 1 To m_dItems("Items")("Categories").Count
                Set dCategory = m_dItems("Items")("Categories")(intCategory)
                ' Check for existing category with this name
                lngCategoryID = Nz(DLookup("Id", "MSysNavPaneGroupCategories", "Type=4 and Name=""" & dCategory("Name") & """"), 0)
                If lngCategoryID = 0 Then
                    ' Add additional field values and create record
                    dCategory.Add "Type", 4
                    lngCategoryID = LoadRecord("MSysNavPaneGroupCategories", dCategory)
                End If
                ' Make sure we got a category record
                If lngCategoryID = 0 Then
                    Log.Error eelError, _
                        "Could not create custom category record for " & dCategory("Name") & " in MSysNavPaneGroupCategories.", _
                        ModuleName(Me) & ".Import"
                    Exit Sub
                End If

                ' Loop through groups in category
                For intGroup = 1 To m_dItems("Items")("Categories")(intCategory)("Groups").Count
                    Set dGroup = m_dItems("Items")("Categories")(intCategory)("Groups")(intGroup)
                    ' Add additional field values for new record
                    dGroup.Add "GroupCategoryID", lngCategoryID
                    dGroup.Add "Object Type Group", -1
                    dGroup.Add "ObjectID", 0
                    ' Check for existing group with this name. (Such as Unassigned Objects)
                    lngGroupID = Nz(DLookup("Id", "MSysNavPaneGroups", "GroupCategoryID=" & lngCategoryID & " AND Name=""" & dGroup("Name") & """"), 0)
                    If lngGroupID = 0 Then lngGroupID = LoadRecord("MSysNavPaneGroups", dGroup)
                    For intObject = 1 To dGroup("Objects").Count
                        Set dObject = dGroup("Objects")(intObject)
                        lngObjectID = Nz(DLookup("Id", "MSysObjects", "Name=""" & dObject("Name") & """ AND Type=" & dObject("Type")), 0)
                        If lngObjectID <> 0 Then
                            dObject.Add "ObjectID", lngObjectID
                            dObject.Add "GroupID", lngGroupID
                            ' Change name to the name defined in this group. (Could be different from the object name)
                            dObject("Name") = dObject("NameInGroup")
                            ' Should not already be a link, but just in case...
                            lngLinkID = Nz(DLookup("Id", "MSysNavPaneGroupToObjects", "ObjectID=" & lngObjectID & " AND GroupID = " & lngGroupID), 0)
                            If lngLinkID = 0 Then lngLinkID = LoadRecord("MSysNavPaneGroupToObjects", dObject)
                        End If
                    Next intObject
                Next intGroup
            Next intCategory
        End If
    End If

    ' Update index
    VCSIndex.Update Me, eatImport, GetDictionaryHash(GetDictionary(False))

End Sub


'---------------------------------------------------------------------------------------
' Procedure : ClearExistingNavGroups
' Author    : Adam Waller
' Date      : 2/22/2021
' Purpose   : Clears existing custom groups/categories (Used before importing)
'---------------------------------------------------------------------------------------
'
Private Sub ClearExistingNavGroups()

    Dim dbs As DAO.Database
    Dim rst As DAO.Recordset
    Dim strSql As String

    If DebugMode(True) Then On Error GoTo 0 Else On Error Resume Next

    ' Get SQL for query of NavPaneGroup objects
    Set dbs = CodeDb
    strSql = dbs.QueryDefs("qryNavPaneGroups").SQL

    ' Look up list of custom categories
    Set dbs = CurrentDb
    Set rst = dbs.OpenRecordset(strSql, dbOpenSnapshot)

    With rst
        Do While Not .EOF
            ' Remove records from three tables
            If Nz(!LinkID, 0) <> 0 Then dbs.Execute "delete from MSysNavPaneGroupToObjects where id=" & Nz(!LinkID, 0), dbFailOnError
            If Nz(!GroupID, 0) <> 0 Then dbs.Execute "delete from MSysNavPaneGroups where id=" & Nz(!GroupID, 0), dbFailOnError
            If Nz(!CategoryID, 0) <> 0 Then dbs.Execute "delete from MSysNavPaneGroupCategories where id=" & Nz(!CategoryID, 0), dbFailOnError
            .MoveNext
        Loop
        .Close
    End With

    CatchAny eelError, "Error clearing existing navigation pane groups.", ModuleName(Me) & ".ClearExisting"

End Sub


'---------------------------------------------------------------------------------------
' Procedure : Merge
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Merge the source file into the existing database, updating or replacing
'           : any existing object.
'           : NOTE: This REPLACES any existing pane groups, it does not attempt to
'           : merge changes between the source file and the existing groups.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Merge(strFile As String)

    ' Clear any existing customizations
    ClearExistingNavGroups

    If FSO.FileExists(strFile) Then
        IDbComponent_Import (strFile)
    Else
        ' Remove from index when source file is removed
        VCSIndex.Remove Me, strFile
    End If

End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetSource
' Author    : Adam Waller
' Date      : 2/23/2022
' Purpose   : Return the full content that will be saved to the source file.
'---------------------------------------------------------------------------------------
'
Private Function GetSource() As String
    GetSource = BuildJsonFile(TypeName(Me), GetDictionary, "Navigation Pane Custom Groups")
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetDictionary
' Author    : Adam Waller
' Date      : 5/28/2021
' Purpose   : Return a dictionary of the navigation pane groups
'---------------------------------------------------------------------------------------
'
Private Function GetDictionary(Optional blnUseCache As Boolean) As Dictionary

    Dim dbs As DAO.Database
    Dim rst As DAO.Recordset
    Dim strSql As String
    Dim strCategory As String
    Dim strGroup As String
    Dim colCategories As Collection
    Dim colGroups As Collection
    Dim dCategory As Dictionary
    Dim dGroup As Dictionary
    Dim colObjects As Collection
    Dim dObject As Dictionary
    Dim dItems As Dictionary

    ' Check cache parameter
    If blnUseCache And Not m_dItems Is Nothing Then
        ' Return cached dictionary
        Set GetDictionary = m_dItems
        Exit Function
    End If

    ' Load query SQL from saved query in add-in database
    Set dbs = CodeDb
    strSql = dbs.QueryDefs("qryNavPaneGroups").SQL

    ' Open query in the current db
    Set dbs = CurrentDb
    Set rst = dbs.OpenRecordset(strSql)
    Set dItems = New Dictionary
    Set colCategories = New Collection

    ' Loop through records
    With rst
        Do While Not .EOF

            ' Check for change in group name.
            If Nz(!GroupName) <> strGroup Then
                ' Finish recording any previous group
                If strGroup <> vbNullString Then
                    dGroup.Add "Objects", colObjects
                    colGroups.Add dGroup
                End If
                ' Set up new group
                Set colObjects = New Collection
                Set dGroup = New Dictionary
                strGroup = Nz(!GroupName)
                dGroup.Add "Name", strGroup
                dGroup.Add "Flags", Nz(!GroupFlags, 0)
                dGroup.Add "Position", Nz(!GroupPosition, 0)
            End If

            ' Check for change in category name
            If Nz(!CategoryName) <> strCategory Then
                ' Finish recording any previous category
                If strCategory <> vbNullString Then
                    dCategory.Add "Groups", colGroups
                    colCategories.Add dCategory
                End If
                ' Set up new category
                'Set colCategories = New Collection
                Set colGroups = New Collection
                strCategory = Nz(!CategoryName)
                Set dCategory = New Dictionary
                dCategory.Add "Name", strCategory
                dCategory.Add "Flags", Nz(!CategoryFlags, 0)
                dCategory.Add "Position", Nz(!CategoryPosition, 0)
            End If

            ' Add any item listed in this group
            If Nz(!ObjectName) = vbNullString Then
                ' Saved group with no items.
            ElseIf Left(Nz(!ObjectName), 1) = "~" Then
                ' Skip temporary placeholder after deletion.
            Else
                Set dObject = New Dictionary
                dObject.Add "Name", Nz(!ObjectName)
                dObject.Add "Type", Nz(!ObjectType, 0)
                dObject.Add "Flags", Nz(!ObjectFlags, 0)
                dObject.Add "Icon", Nz(!ObjectIcon, 0)
                dObject.Add "Position", Nz(!ObjectPosition, 0)
                dObject.Add "NameInGroup", Nz(!NameInGroup)
                colObjects.Add dObject
            End If

            ' Move to next record.
            .MoveNext
        Loop
        .Close
        ' Close out last group and category, and add items
        ' to output dictionary
        If strGroup <> vbNullString Then
            dGroup.Add "Objects", colObjects
            colGroups.Add dGroup
        End If
        If strCategory <> vbNullString Then
            dCategory.Add "Groups", colGroups
            colCategories.Add dCategory
            dItems.Add "Categories", colCategories
        End If
    End With

    ' Return dictionary
    Set GetDictionary = dItems

End Function


'---------------------------------------------------------------------------------------
' Procedure : LoadRecord
' Author    : Adam Waller
' Date      : 5/12/2020
' Purpose   : Loads a new record into the specified table and returns the ID
'---------------------------------------------------------------------------------------
'
Private Function LoadRecord(strTable As String, dCols As Dictionary) As Long

    Dim dbs As DAO.Database
    Dim rst As DAO.Recordset
    Dim fld As DAO.Field

    Set dbs = CurrentDb
    Set rst = dbs.OpenRecordset(strTable)
    With rst
        .AddNew
            For Each fld In .Fields
                ' Load field value in matching column
                If dCols.Exists(fld.Name) Then fld.Value = dCols(fld.Name)
            Next fld
        .Update
        .Bookmark = .LastModified
        ' Return ID from new record.
        LoadRecord = Nz(!ID, 0)
        .Close
    End With

    Set rst = Nothing
    Set dbs = Nothing

End Function


'---------------------------------------------------------------------------------------
' Procedure : IDbComponent_MoveSource
' Author    : Adam Waller
' Date      : 9/10/2022
' Purpose   : Move the component's source file(s) from one folder to another
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_MoveSource(strFromFolder As String, strToFolder As String)
    MoveFileIfExists strFromFolder & FSO.GetFileName(IDbComponent_SourceFile), strToFolder
End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetAllFromDB
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a collection of class objects represented by this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetAllFromDB(Optional blnModifiedOnly As Boolean = False) As Dictionary

    Dim cGroup As IDbComponent
    Dim varCategory As Variant
    Dim dCategory As Dictionary
    Dim varGroup As Variant
    Dim strKey As String

    ' Build collection if not already cached
    If m_Items(blnModifiedOnly) Is Nothing Then

        Set m_Items(blnModifiedOnly) = New Dictionary
        Set m_dItems = GetDictionary

        ' Only need to iterate through the groups if we need to get a count.
        If Not blnModifiedOnly Or IDbComponent_IsModified Then

            ' Loop through dictionary to build count of custom groups
            ' (Not counting individual objects within groups)
            If m_dItems.Exists("Categories") Then
                For Each varCategory In m_dItems("Categories")
                    Set dCategory = varCategory
                    If dCategory.Exists("Groups") Then
                        For Each varGroup In dCategory("Groups")
                            Set cGroup = New clsDbNavPaneGroup
                            strKey = varCategory("Name") & ":" & varGroup("Name")
                            If Not m_Items(blnModifiedOnly).Exists(strKey) Then
                                m_Items(blnModifiedOnly).Add strKey, cGroup
                            End If
                        Next varGroup
                    End If
                Next varCategory
            End If
        End If
    End If

    ' Return cached collection
    Set IDbComponent_GetAllFromDB = m_Items(blnModifiedOnly)

End Function


'---------------------------------------------------------------------------------------
' Procedure : GetFileList
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a list of file names to import for this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetFileList() As Dictionary
    Set IDbComponent_GetFileList = New Dictionary
    If FSO.FileExists(IDbComponent_SourceFile) Then IDbComponent_GetFileList.Add IDbComponent_SourceFile, vbNullString
End Function


'---------------------------------------------------------------------------------------
' Procedure : IsModified
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Returns true if the object in the database has been modified since
'           : the last export of the object.
'---------------------------------------------------------------------------------------
'
Public Function IDbComponent_IsModified() As Boolean
    IDbComponent_IsModified = VCSIndex.Item(Me).FileHash <> GetStringHash(GetSource, True)
End Function


'---------------------------------------------------------------------------------------
' Procedure : DateModified
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : The date/time the object was modified. (If possible to retrieve)
'           : If the modified date cannot be determined (such as application
'           : properties) then this function will return 0.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_DateModified() As Date
    IDbComponent_DateModified = 0
End Function


'---------------------------------------------------------------------------------------
' Procedure : Category
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a category name for this type. (I.e. forms, queries, macros)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Category() As String
    IDbComponent_Category = "Nav Pane Groups"
End Property


'---------------------------------------------------------------------------------------
' Procedure : BaseFolder
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the base folder for import/export of this component.
'---------------------------------------------------------------------------------------
Private Property Get IDbComponent_BaseFolder() As String
    IDbComponent_BaseFolder = Options.GetExportFolder
End Property


'---------------------------------------------------------------------------------------
' Procedure : FileExtensions
' Author    : Adam Waller
' Date      : 12/1/2023
' Purpose   : A collection of the file extensions used in source files for this
'           : component type.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_FileExtensions() As Collection
    Set IDbComponent_FileExtensions = New Collection
    IDbComponent_FileExtensions.Add "json"
End Property


'---------------------------------------------------------------------------------------
' Procedure : Name
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a name to reference the object for use in logs and screen output.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Name() As String
    IDbComponent_Name = "Groups"
End Property


'---------------------------------------------------------------------------------------
' Procedure : SourceFile
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the full path of the source file for the current object.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SourceFile() As String
    IDbComponent_SourceFile = IDbComponent_BaseFolder & "nav-pane-groups.json"
End Property


'---------------------------------------------------------------------------------------
' Procedure : Count
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a count of how many items are in this category.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Count(Optional blnModifiedOnly As Boolean = False) As Long
    IDbComponent_Count = IDbComponent_GetAllFromDB(blnModifiedOnly).Count
End Property


'---------------------------------------------------------------------------------------
' Procedure : QuickCount
' Author    : Adam Waller
' Date      : 6/14/2022
' Purpose   : Return a cached, non-iterative approximate count of database objects
'           : for use with progress indicators when scanning for changes. Single file
'           : objects like database properties can simply return 1.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_QuickCount() As Long
    ' No simple way to pull this without queries
    IDbComponent_QuickCount = 1
End Property


'---------------------------------------------------------------------------------------
' Procedure : ComponentType
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : The type of component represented by this class.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_ComponentType() As eDatabaseComponentType
    IDbComponent_ComponentType = edbNavPaneGroup
End Property


'---------------------------------------------------------------------------------------
' Procedure : DbObject
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This represents the database object we are dealing with.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_DbObject() As Object
    Set IDbComponent_DbObject = Nothing
End Property
Private Property Set IDbComponent_DbObject(ByVal RHS As Object)
End Property


'---------------------------------------------------------------------------------------
' Procedure : SingleFile
' Author    : Adam Waller
' Date      : 4/24/2020
' Purpose   : Returns true if the export of all items is done as a single file instead
'           : of individual files for each component. (I.e. properties, references)
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SingleFile() As Boolean
    IDbComponent_SingleFile = True
End Property


'---------------------------------------------------------------------------------------
' Procedure : Parent
' Author    : Adam Waller
' Date      : 4/24/2020
' Purpose   : Return a reference to this class as an IDbComponent. This allows you
'           : to reference the public methods of the parent class without needing
'           : to create a new class object.
'---------------------------------------------------------------------------------------
'
Public Property Get Parent() As IDbComponent
    Set Parent = Me
End Property
