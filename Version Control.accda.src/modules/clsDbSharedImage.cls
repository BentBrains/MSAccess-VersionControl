﻿VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "clsDbSharedImage"
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
Private m_FileList As Dictionary
Private m_Dbs As DAO.Database

' This is used to pass a reference to the record back
' into the class for loading the private variables
' with the actual file information.
Private m_Rst As DAO.Recordset

' File details used for exporting/importing
Private m_Name As String
Private m_FileName As String
Private m_Extension As String
Private m_FileData() As Byte

' This requires us to use all the public methods and properties of the implemented class
' which keeps all the component classes consistent in how they are used in the export
' and import process. The implemented functions should be kept private as they are called
' from the implementing class, not this class.
Implements IDbComponent


'---------------------------------------------------------------------------------------
' Procedure : Export
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Export the shared image as a json file with file details, and a copy
'           : of the binary image file saved as an image.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Export(Optional strAlternatePath As String)

    Dim strContent As String
    Dim strFile As String
    Dim dItem As Dictionary

    ' Build header file
    Set dItem = GetDictionary

    ' Save json file with header details
    strContent = GetSource
    WriteFile strContent, Nz2(strAlternatePath, IDbComponent_SourceFile)

    ' Save image file using extension from embedded file.
    strFile = IDbComponent_BaseFolder & FSO.GetBaseName(IDbComponent_SourceFile) & "." & FSO.GetExtensionName(m_FileName)

    ' Write binary content to file
    WriteBinaryFile strFile, StripOLEHeader(m_Extension, m_FileData)

    ' Update index after export
    VCSIndex.Update Me, IIf(strAlternatePath = vbNullString, eatExport, eatAltExport), _
        GetStringHash(strContent, True), GetSignatureHash

End Sub


'---------------------------------------------------------------------------------------
' Procedure : Import
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Import the individual database component from a file.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Import(strFile As String)

    Dim dFile As Dictionary
    Dim dItem As Dictionary
    Dim strTemp As String
    Dim strImageFile As String
    Dim strOriginalName As String
    Dim strBase As String
    Dim lngIndex As Long
    Dim proj As CurrentProject

    ' Only import files with the correct extension.
    If Not strFile Like "*.json" Then Exit Sub

    ' Read json header file
    Set dFile = ReadJsonFile(strFile)
    If Not dFile Is Nothing Then
        Set dItem = dFile("Items")
        ' Check for an existing file with the same name
        strOriginalName = IDbComponent_BaseFolder & dItem("FileName")
        strImageFile = IDbComponent_BaseFolder & FSO.GetBaseName(strFile) & "." & FSO.GetExtensionName(strOriginalName)
        If strOriginalName <> strImageFile Then
            If FSO.FileExists(strOriginalName) Then
                strTemp = IDbComponent_BaseFolder & FSO.GetTempName
                ' Rename to temp file
                Name strOriginalName As strTemp
            End If
            Name strImageFile As strOriginalName
        End If
        ' Rename image to original name
        ' Import as image, then rename back to image file name that matches json file.
        Set proj = CurrentProject
        With proj
            lngIndex = .Resources.Count
            ' Import using the original file name as the resource name so the
            ' embedded file has the correct name. (Ensuring that we are using a unique name)
            strBase = GetUnusedResourceName(FSO.GetBaseName(strOriginalName))
            .AddSharedImage strBase, strOriginalName
            If .Resources.Count = lngIndex + 1 Then
                ' Rename shared resource to saved name if different.
                If strBase <> dItem("Name") Then
                    .Resources(GetResourceIndexByName(strBase)).Name = dItem("Name")
                End If
            End If
        End With
        ' Restore temp file if needed
        If strTemp <> vbNullString Then
            Name strTemp As strImageFile
        Else
            ' Restore image file name if needed.
            If strOriginalName <> strImageFile Then Name strOriginalName As strImageFile
        End If

        ' Update index after import
        If LoadItem(dItem("Name")) Then
            VCSIndex.Update Me, eatExport, GetDictionaryHash(dItem)
        Else
            Log.Error eelError, "Unable to find shared image '" & dItem("Name") & "' after importing.", ModuleName(Me) & ".Import"
        End If
    End If

End Sub


'---------------------------------------------------------------------------------------
' Procedure : Merge
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Merge the source file into the existing database, updating or replacing
'           : any existing object.
'---------------------------------------------------------------------------------------
'
Private Sub IDbComponent_Merge(strFile As String)

    Dim strName As String

    ' Only import files with the correct extension.
    If Not strFile Like "*.json" Then Exit Sub

    ' Parse name from file name
    strName = GetObjectNameFromFileName(strFile)

    ' Remove the existing shared image, if it exists.
    RemoveIfExists strName

    ' Import if source file exists
    If FSO.FileExists(strFile) Then
        IDbComponent_Import strFile
    Else
        VCSIndex.Remove Me, strFile
    End If

End Sub


'---------------------------------------------------------------------------------------
' Procedure : RemoveIfExists
' Author    : Adam Waller
' Date      : 2/7/2023
' Purpose   : Removes a shared resource if it exists
'---------------------------------------------------------------------------------------
'
Private Function RemoveIfExists(strName As String)

    Dim resImage As SharedResource

    Perf.OperationStart "Check/Remove Shared Resource"
    For Each resImage In CurrentProject.Resources
        If resImage.Type = acResourceImage Then
            If resImage.Name = strName Then
                resImage.Delete
                Exit For
            End If
        End If
    Next resImage
    Perf.OperationEnd

End Function


'---------------------------------------------------------------------------------------
' Procedure : LoadItem
' Author    : Adam Waller
' Date      : 11/1/2021
' Purpose   : Load a shared resource by name into this class so we can reconstruct the
'           : hash when updating the index after import.
'---------------------------------------------------------------------------------------
'
Private Function LoadItem(strName As String) As Boolean

    Dim rst As DAO.Recordset
    Dim strSql As String

    ' This system table should exist, but just in case...
    If TableExists("MSysResources") Then

        If m_Dbs Is Nothing Then Set m_Dbs = CurrentDb
        strSql = "SELECT * FROM MSysResources WHERE Type='img'"
        Set rst = m_Dbs.OpenRecordset(strSql, dbOpenSnapshot, dbOpenForwardOnly)
        With rst
            Do While Not .EOF
                If Nz(!Name) = strName Then
                    ' Set the DB object, reloading the properties
                    Set IDbComponent_DbObject = rst
                    Exit Do
                End If
                .MoveNext
            Loop
            .Close
        End With
        LoadItem = True
    End If

End Function


'---------------------------------------------------------------------------------------
' Procedure : GetSignatureHash
' Author    : Adam Waller
' Date      : 5/28/2021
' Purpose   : Return a simple hash that should give us a pretty good idea if the image
'           : has changed since it was last exported.
'---------------------------------------------------------------------------------------
'
Private Function GetSignatureHash() As String

    Dim dblCnt As Double
    Dim dblLen As Double
    Dim strData As String

    ' Get length (bytes) of file data
    If StrPtr(m_FileData) <> 0 Then dblLen = UBound(m_FileData)

    With New clsConcat
        ' Compile string with file information
        .Add m_Name, m_FileName, m_Extension, CStr(dblLen)
        ' Add in last 100 characters of file content (byte numbers)
        ' Since this is likely a compressed file format, we will probably
        ' see a change here if the contents were modified.
        If dblLen > 100 Then
            For dblCnt = dblLen To dblLen - 100 Step -1
                .Add CStr(m_FileData(dblCnt))
            Next dblCnt
        Else
            ' Convert byte array to string and include in hash.
            strData = m_FileData
            .Add strData
        End If
        ' Return hash of this string
        GetSignatureHash = GetStringHash(.GetStr)
    End With

End Function


'---------------------------------------------------------------------------------------
' Procedure : GetSource
' Author    : Adam Waller
' Date      : 2/14/2022
' Purpose   : Return the full content that will be saved to the source file.
'---------------------------------------------------------------------------------------
'
Private Function GetSource() As String
    GetSource = BuildJsonFile(TypeName(Me), GetDictionary, "Shared Image Gallery Item")
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetDictionary
' Author    : Adam Waller
' Date      : 11/1/2021
' Purpose   : Return a dictionary object representing the content for the json file.
'---------------------------------------------------------------------------------------
'
Private Function GetDictionary() As Dictionary
    Set GetDictionary = New Dictionary
    With GetDictionary
        .Add "Name", m_Name
        .Add "FileName", m_FileName
        .Add "Extension", m_Extension
        ' Store a hash of the binary image content, so we can verify
        ' that the file content itself has not changed.
        .Add "ContentHash", GetBytesHash(StripOLEHeader(m_Extension, m_FileData))
    End With
End Function


'---------------------------------------------------------------------------------------
' Procedure : GetResourceIndexByName
' Author    : Adam Waller
' Date      : 5/29/2020
' Purpose   : Return the index of the shared resource after locating by name.
'           : (This is needed because the new resource doesn't always have the
'           :  highest index.)
'---------------------------------------------------------------------------------------
'
Private Function GetResourceIndexByName(strName As String) As Long

    Dim lngIndex As Long
    Dim resShared As SharedResources

    Set resShared = CurrentProject.Resources
    For lngIndex = 0 To resShared.Count - 1
        If resShared(lngIndex).Name = strName Then
            GetResourceIndexByName = lngIndex
            Exit For
        End If
    Next lngIndex

End Function


'---------------------------------------------------------------------------------------
' Procedure : GetUnusedResourceName
' Author    : Adam Waller
' Date      : 2/7/2023
' Purpose   : Return the original name if possible, or a similar name that does not
'           : conflict with any existing resource names.
'---------------------------------------------------------------------------------------
'
Private Function GetUnusedResourceName(strName As String) As String

    Dim strSql As String
    Dim strTest As String
    Dim lngCnt As Long
    Dim rst As DAO.Recordset

    Perf.OperationStart "Get Unused Resource Name"

    ' Use a dictionary to easily test if a name is in use.
    With New Dictionary

        ' Build dictionary of existing items
        ' (Reading directly from the table is MUCH faster than iterating through
        '  the CurrentProject.Resources object model.)
        If TableExists("MSysResources") Then
            If m_Dbs Is Nothing Then Set m_Dbs = CurrentDb
            strSql = "SELECT * FROM MSysResources WHERE Type='img'"
            Set rst = m_Dbs.OpenRecordset(strSql, dbOpenSnapshot, dbOpenForwardOnly)
            Do While Not rst.EOF
                If Not .Exists(Nz(rst!Name)) Then .Add Nz(rst!Name), vbNullString
                rst.MoveNext
            Loop
            rst.Close
        End If

        ' Start with the initial name
        strTest = strName

        ' Loop through name alternatives to find an unused one.
        ' (Typically we would only have to do one or two iterations)
        For lngCnt = 1 To 100
            If Not .Exists(strTest) Then
                ' Found an unused name
                Exit For
            End If
            ' Build an alternate name with a numerical prefix for the next test.
            strTest = lngCnt & "_" & strName
        Next lngCnt
    End With

    Perf.OperationEnd

    ' Return the tested and available name
    GetUnusedResourceName = strTest

End Function


'---------------------------------------------------------------------------------------
' Procedure : StripOLEHeader
' Author    : Adam Waller
' Date      : 5/12/2020
' Purpose   : Strip out the OLE header so we can save the raw binary image as a
'           : readable file. (First 20 bytes (10 chars) of the data)
'           : Tested with jpg, gif, png, tiff
'---------------------------------------------------------------------------------------
'
Private Function StripOLEHeader(strExt As String, bteData() As Byte) As Byte()

    Dim strData As String

    ' Convert to string
    strData = bteData

    ' Strip off header, and convert back to byte array
    StripOLEHeader = Mid$(strData, 8 + Len(strExt))

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
    ' Move actual image file
    MoveFileIfExists strFromFolder & _
        FSO.GetBaseName(IDbComponent_SourceFile) & "." & FSO.GetExtensionName(m_FileName), strToFolder
End Sub


'---------------------------------------------------------------------------------------
' Procedure : GetAllFromDB
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a collection of class objects represented by this component type.
'---------------------------------------------------------------------------------------
'
Private Function IDbComponent_GetAllFromDB(Optional blnModifiedOnly As Boolean = False) As Dictionary

    Dim cImg As IDbComponent
    Dim rst As DAO.Recordset
    Dim strSql As String
    Dim blnAdd As Boolean

    ' Build collection if not already cached
    If m_Items(blnModifiedOnly) Is Nothing Then
        Set m_Items(blnModifiedOnly) = New Dictionary

        ' This system table should exist, but just in case...
        If TableExists("MSysResources") Then

            Set m_Dbs = CurrentDb
            ' We will use an explicit ordering because it can potentially contain duplicate entries due to the fact
            ' that the Name column is not unique or a primary key. Any duplicate images are useless and will be
            ' skipped but to ensure we provide a consistent result, we need to make sure we keep the image with the
            ' lowest ID and discard any duplicate images with a higher Id.
            strSql = "SELECT * FROM MSysResources WHERE Type='img' ORDER BY Id;"
            Set rst = m_Dbs.OpenRecordset(strSql, dbOpenSnapshot, dbOpenForwardOnly)
            With rst
                Do While Not .EOF
                    Set cImg = New clsDbSharedImage
                    ' Also sets reference to OLE object recordset2
                    Set cImg.DbObject = rst
                    blnAdd = True
                    If blnModifiedOnly Then blnAdd = cImg.IsModified
                    If blnAdd Then
                        If m_Items(blnModifiedOnly).Exists(cImg.SourceFile) Then
                            ' This is a duplicate image. We won't add it to the list but we need to issue a warning in log.
                            Log.Error eelWarning, "Duplicate record found for '" & cImg.Name & "' at ID " & rst.Fields("ID").Value & ". This record will not be exported as this is likely an error and not available for use via Access.", ModuleName(Me) & ".GetAllFromDB"
                        Else
                            m_Items(blnModifiedOnly).Add cImg.SourceFile, cImg
                        End If
                    End If
                    .MoveNext
                Loop
                .Close
            End With
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
    If m_FileList Is Nothing Then Set m_FileList = GetFilePathsInFolder(IDbComponent_BaseFolder, "*.json")
    Set IDbComponent_GetFileList = m_FileList
End Function


'---------------------------------------------------------------------------------------
' Procedure : IsModified
' Author    : Adam Waller
' Date      : 11/21/2020
' Purpose   : Returns true if the object in the database has been modified since
'           : the last export of the object.
'           : Compare the index hash to the existing database content
'---------------------------------------------------------------------------------------
'
Public Function IDbComponent_IsModified() As Boolean

    ' Check file hash of definition
    With VCSIndex.Item(Me)
        If .FileHash <> GetStringHash(GetSource, True) Then
            ' Definition file is different
            IDbComponent_IsModified = True
        Else
            ' Check signature of actual image content
            IDbComponent_IsModified = (.OtherHash <> GetSignatureHash)
        End If
    End With

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
    IDbComponent_Category = "Shared Images"
End Property


'---------------------------------------------------------------------------------------
' Procedure : BaseFolder
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the base folder for import/export of this component.
'---------------------------------------------------------------------------------------
Private Property Get IDbComponent_BaseFolder() As String
    IDbComponent_BaseFolder = Options.GetExportFolder & "images" & PathSep
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
    With IDbComponent_FileExtensions
        .Add "json"
        .Add "jpg"
        .Add "jpeg"
        .Add "jpe"
        .Add "gif"
        .Add "png"
        .Add "ico"
    End With
End Property


'---------------------------------------------------------------------------------------
' Procedure : Name
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return a name to reference the object for use in logs and screen output.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_Name() As String
    IDbComponent_Name = m_Name
End Property


'---------------------------------------------------------------------------------------
' Procedure : SourceFile
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : Return the full path of the source file for the current object.
'           : In this case, we are building the name to include the info needed to
'           : recreate the record in the MSysResource table.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_SourceFile() As String
    IDbComponent_SourceFile = IDbComponent_BaseFolder & GetSafeFileName(m_Name) & ".json"
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
    IDbComponent_ComponentType = edbSharedImage
End Property


'---------------------------------------------------------------------------------------
' Procedure : DbObject
' Author    : Adam Waller
' Date      : 4/23/2020
' Purpose   : This represents the database object we are dealing with.
'---------------------------------------------------------------------------------------
'
Private Property Get IDbComponent_DbObject() As Object
    ' Not used
    Set IDbComponent_DbObject = Nothing
End Property


'---------------------------------------------------------------------------------------
' Procedure : IDbComponent_DbObject
' Author    : Adam Waller
' Date      : 5/11/2020
' Purpose   : Load in the class values from the recordset
'---------------------------------------------------------------------------------------
'
Private Property Set IDbComponent_DbObject(ByVal RHS As Object)

    ' IMPORTANT: These variables must be declared as the
    ' generic parent classes to avoid problems in newer
    ' releases of Microsoft Access. (See issue #341)
    Dim fld2 As DAO.Field       ' Field2
    Dim rst2 As DAO.Recordset   ' Recordset2

    Set m_Rst = RHS

    ' Load in the object details.
    m_Name = Nz(m_Rst!Name)
    m_Extension = Nz(m_Rst!Extension)
    '@Ignore SetAssignmentWithIncompatibleObjectType
    Set fld2 = m_Rst!Data
    Set rst2 = fld2.Value
    m_FileName = Nz(rst2.Fields("FileName"))
    m_FileData = rst2.Fields("FileData")

    ' Clear the object references
    Set rst2 = Nothing
    Set fld2 = Nothing
    Set m_Rst = Nothing

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
    IDbComponent_SingleFile = False
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


'---------------------------------------------------------------------------------------
' Procedure : Class_Terminate
' Author    : Adam Waller
' Date      : 5/13/2020
' Purpose   : Clear reference to database object.
'---------------------------------------------------------------------------------------
'
Private Sub Class_Terminate()
    Set m_Dbs = Nothing
End Sub
