Attribute VB_Name = "Selections"
'***************************************************************************
'Selection Interface
'Copyright 2013-2017 by Tanner Helland
'Created: 21/June/13
'Last updated: 03/March/17
'Last update: large-scale overhaul to match new 7.0 features and changes in pdSelection.
'
'Selection tools have existed in PhotoDemon for awhile, but this module is the first to support Process varieties of
' selection operations - e.g. internal actions like "Process "Create Selection"".  Selection commands must be passed
' through the Process module so they can be recorded as macros, and as part of the program's Undo/Redo chain.  This
' module provides all selection-related functions that the Process module can call.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

Public Enum SelectionDialogType
    SEL_GROW = 0
    SEL_SHRINK = 1
    SEL_BORDER = 2
    SEL_FEATHER = 3
    SEL_SHARPEN = 4
End Enum

#If False Then
    Private Const SEL_GROW = 0, SEL_SHRINK = 1, SEL_BORDER = 2, SEL_FEATHER = 3, SEL_SHARPEN = 4
#End If

'This module caches the current selection mode and/or color, and the viewport pipeline retrieves these cached values as necessary
' during rendering.
Private m_CurSelectionMode As PD_SelectionRender, m_CurSelectionColor As Long

'Present a selection-related dialog box (grow, shrink, feather, etc).  This function will return a msgBoxResult value so
' the calling function knows how to proceed, and if the user successfully selected a value, it will be stored in the
' returnValue variable.
Public Function DisplaySelectionDialog(ByVal typeOfDialog As SelectionDialogType, ByRef ReturnValue As Double) As VbMsgBoxResult

    Load FormSelectionDialogs
    FormSelectionDialogs.ShowDialog typeOfDialog
    
    DisplaySelectionDialog = FormSelectionDialogs.DialogResult
    ReturnValue = FormSelectionDialogs.paramValue
    
    Unload FormSelectionDialogs
    Set FormSelectionDialogs = Nothing

End Function

'Create a new selection using the settings stored in a pdParamString-compatible string
Public Sub CreateNewSelection(ByVal paramString As String)
    
    'Use the passed parameter string to initialize the selection
    pdImages(g_CurrentImage).mainSelection.InitFromXML paramString
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).SetSelectionActive True
    
    'For lasso selections, mark the lasso as closed if the selection is being created anew
    If (pdImages(g_CurrentImage).mainSelection.GetSelectionShape() = ss_Lasso) Then pdImages(g_CurrentImage).mainSelection.SetLassoClosedState True
    
    'Synchronize all user-facing controls to match
    Selections.SyncTextToCurrentSelection g_CurrentImage
    
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Remove the current selection
Public Sub RemoveCurrentSelection()
    
    'Release the selection object and mark it as inactive
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).SetSelectionActive False
    
    'Reset any internal selection state trackers
    pdImages(g_CurrentImage).mainSelection.EraseCustomTrackers
    
    'Synchronize all user-facing controls to match
    SyncTextToCurrentSelection g_CurrentImage
        
    'Redraw the image (with selection removed)
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Create a new selection using the settings stored in a pdParamString-compatible string
Public Sub SelectWholeImage()
    
    'Unselect any existing selection
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).SetSelectionActive False
    
    'Create a new selection at the size of the image
    pdImages(g_CurrentImage).mainSelection.SelectAll
    
    'Lock in this selection
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).SetSelectionActive True
    
    'Synchronize all user-facing controls to match
    SyncTextToCurrentSelection g_CurrentImage
    
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Load a previously saved selection.  Note that this function also handles creation and display of the relevant common dialog.
Public Sub LoadSelectionFromFile(ByVal displayDialog As Boolean, Optional ByVal SelectionPath As String = "")

    If displayDialog Then
    
        'Disable user input until the dialog closes
        Interface.DisableUserInput
    
        'Simple open dialog
        Dim openDialog As pdOpenSaveDialog
        Set openDialog = New pdOpenSaveDialog
        
        Dim sFile As String
        
        Dim cdFilter As String
        cdFilter = g_Language.TranslateMessage("PhotoDemon Selection") & " (." & SELECTION_EXT & ")|*." & SELECTION_EXT & "|"
        cdFilter = cdFilter & g_Language.TranslateMessage("All files") & "|*.*"
        
        Dim cdTitle As String
        cdTitle = g_Language.TranslateMessage("Load a previously saved selection")
                
        If openDialog.GetOpenFileName(sFile, , True, False, cdFilter, 1, g_UserPreferences.GetSelectionPath, cdTitle, , GetModalOwner().hWnd) Then
            
            'Use a temporary selection object to validate the requested selection file
            Dim tmpSelection As pdSelection
            Set tmpSelection = New pdSelection
            tmpSelection.SetParentReference pdImages(g_CurrentImage)
            
            If tmpSelection.ReadSelectionFromFile(sFile, True) Then
                
                'Save the new directory as the default path for future usage
                g_UserPreferences.SetSelectionPath sFile
                
                'Call this function again, but with displayDialog set to FALSE and the path of the requested selection file
                Process "Load selection", False, sFile, UNDO_SELECTION
                    
            Else
                PDMsgBox "An error occurred while attempting to load %1.  Please verify that the file is a valid PhotoDemon selection file.", vbOKOnly + vbExclamation + vbApplicationModal, "Selection Error", sFile
            End If
            
            'Release the temporary selection object
            tmpSelection.SetParentReference Nothing
            Set tmpSelection = Nothing
            
        End If
        
        'Re-enable user input
        Interface.EnableUserInput
        
    Else
    
        Message "Loading selection..."
        pdImages(g_CurrentImage).mainSelection.ReadSelectionFromFile SelectionPath
        pdImages(g_CurrentImage).SetSelectionActive True
        
        'Synchronize all user-facing controls to match
        SyncTextToCurrentSelection g_CurrentImage
                
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
        Message "Selection loaded successfully"
    
    End If
        
End Sub

'Save the current selection to file.  Note that this function also handles creation and display of the relevant common dialog.
Public Sub SaveSelectionToFile()

    'Simple save dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    Dim sFile As String
    
    Dim cdFilter As String
    cdFilter = g_Language.TranslateMessage("PhotoDemon Selection") & " (." & SELECTION_EXT & ")|*." & SELECTION_EXT
    
    Dim cdTitle As String
    cdTitle = g_Language.TranslateMessage("Save the current selection")
        
    If saveDialog.GetSaveFileName(sFile, , True, cdFilter, 1, g_UserPreferences.GetSelectionPath, cdTitle, "." & SELECTION_EXT, GetModalOwner().hWnd) Then
        
        'Save the new directory as the default path for future usage
        g_UserPreferences.SetSelectionPath sFile
        
        'Write out the selection file
        Dim cmpLevel As Long
        cmpLevel = Compression.GetMaxCompressionLevel(PD_CE_Zstd)
        If pdImages(g_CurrentImage).mainSelection.WriteSelectionToFile(sFile, PD_CE_Zstd, cmpLevel, PD_CE_Zstd, cmpLevel) Then
            Message "Selection saved."
        Else
            Message "Unknown error occurred.  Selection was not saved.  Please try again."
        End If
        
    End If
        
End Sub

'Export the currently selected area as an image.  This is provided as a convenience to the user, so that they do not have to crop
' or copy-paste the selected area in order to save it.  The selected area is also checked for bit-depth; 24bpp is recommended as
' JPEG, while 32bpp is recommended as PNG (but the user can select any supported PD save format from the common dialog).
Public Function ExportSelectedAreaAsImage() As Boolean
    
    'If a selection is not active, it should be impossible to select this menu item.  Just in case, check for that state and exit if necessary.
    If Not pdImages(g_CurrentImage).IsSelectionActive Then
        Message "This action requires an active selection.  Please create a selection before continuing."
        ExportSelectedAreaAsImage = False
        Exit Function
    End If
    
    'Prepare a temporary pdImage object to house the current selection mask
    Dim tmpImage As pdImage
    Set tmpImage = New pdImage
    
    'Copy the current selection DIB into a temporary DIB.
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    pdImages(g_CurrentImage).RetrieveProcessedSelection tmpDIB, False, True
    
    'If the selected area has a blank alpha channel, convert it to 24bpp
    If Not DIB_Support.IsDIBAlphaBinary(tmpDIB, False) Then tmpDIB.ConvertTo24bpp
    
    'In the temporary pdImage object, create a blank layer; this will receive the processed DIB
    Dim newLayerID As Long
    newLayerID = tmpImage.CreateBlankLayer
    tmpImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, , tmpDIB
    tmpImage.UpdateSize
        
    'Give the selection a basic filename
    tmpImage.imgStorage.AddEntry "OriginalFileName", "PhotoDemon selection"
        
    'Get the last "save image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Paths", "Save Image", "")
    
    'By default, recommend JPEG for 24bpp selections, and PNG for 32bpp selections
    Dim saveFormat As Long
    If tmpDIB.GetDIBColorDepth = 24 Then
        saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_JPEG) + 1
    Else
        saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_PNG) + 1
    End If
    
    'Now it's time to prepare a standard Save Image common dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    'Provide a string to the common dialog; it will fill this with the user's chosen path + filename
    Dim sFile As String
    sFile = tempPathString & IncrementFilename(tempPathString, tmpImage.imgStorage.GetEntry_String("OriginalFileName", vbNullString), g_ImageFormats.GetOutputFormatExtension(saveFormat - 1))
    
    'Present a common dialog to the user
    If saveDialog.GetSaveFileName(sFile, , True, g_ImageFormats.GetCommonDialogOutputFormats, saveFormat, tempPathString, g_Language.TranslateMessage("Export selection as image"), g_ImageFormats.GetCommonDialogDefaultExtensions, FormMain.hWnd) Then
                
        'Store the selected file format to the image object
        tmpImage.SetCurrentFileFormat g_ImageFormats.GetOutputPDIF(saveFormat - 1)
                                
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        ExportSelectedAreaAsImage = PhotoDemon_SaveImage(tmpImage, sFile, True)
        
    Else
        ExportSelectedAreaAsImage = False
    End If
        
    'Release our temporary image
    Set tmpDIB = Nothing
    Set tmpImage = Nothing
    
End Function

'Export the current selection mask as an image.  PNG is recommended by default, but the user can choose from any of PD's available formats.
Public Function ExportSelectionMaskAsImage() As Boolean
    
    'If a selection is not active, it should be impossible to select this menu item.  Just in case, check for that state and exit if necessary.
    If Not pdImages(g_CurrentImage).IsSelectionActive Then
        Message "This action requires an active selection.  Please create a selection before continuing."
        ExportSelectionMaskAsImage = False
        Exit Function
    End If
    
    'Prepare a temporary pdImage object to house the current selection mask
    Dim tmpImage As pdImage
    Set tmpImage = New pdImage
    
    'Create a temporary DIB, then retrieve the current selection into it
    Dim tmpDIB As pdDIB
    Set tmpDIB = New pdDIB
    tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
    
    'Due to the way selections work, it's easier for us to forcibly up-sample the selection mask to 32bpp.  This prevents
    ' some issues with saving to exotic file formats.
    tmpDIB.ConvertTo32bpp
    
    'In the temporary pdImage object, create a blank layer; this will receive the processed DIB
    Dim newLayerID As Long
    newLayerID = tmpImage.CreateBlankLayer
    tmpImage.GetLayerByID(newLayerID).InitializeNewLayer PDL_IMAGE, , tmpDIB
    tmpImage.UpdateSize
    
    'Give the selection a basic filename
    tmpImage.imgStorage.AddEntry "OriginalFileName", g_Language.TranslateMessage("PhotoDemon selection")
        
    'Get the last "save image" path from the preferences file
    Dim tempPathString As String
    tempPathString = g_UserPreferences.GetPref_String("Paths", "Save Image", "")
    
    'By default, recommend PNG as the save format
    Dim saveFormat As Long
    saveFormat = g_ImageFormats.GetIndexOfOutputPDIF(PDIF_PNG) + 1
    
    'Provide a string to the common dialog; it will fill this with the user's chosen path + filename
    Dim sFile As String
    sFile = tempPathString & IncrementFilename(tempPathString, tmpImage.imgStorage.GetEntry_String("OriginalFileName", vbNullString), "png")
    
    'Now it's time to prepare a standard Save Image common dialog
    Dim saveDialog As pdOpenSaveDialog
    Set saveDialog = New pdOpenSaveDialog
    
    'Present a common dialog to the user
    If saveDialog.GetSaveFileName(sFile, , True, g_ImageFormats.GetCommonDialogOutputFormats, saveFormat, tempPathString, g_Language.TranslateMessage("Export selection as image"), g_ImageFormats.GetCommonDialogDefaultExtensions, FormMain.hWnd) Then
                
        'Store the selected file format to the image object
        tmpImage.SetCurrentFileFormat g_ImageFormats.GetOutputPDIF(saveFormat - 1)
                                
        'Transfer control to the core SaveImage routine, which will handle color depth analysis and actual saving
        ExportSelectionMaskAsImage = PhotoDemon_SaveImage(tmpImage, sFile, True)
        
    Else
        ExportSelectionMaskAsImage = False
    End If
    
    'Release our temporary image
    Set tmpImage = Nothing

End Function

'Use this to populate the text boxes on the main form with the current selection values.  Note that this does not cause a screen refresh, by design.
Public Sub SyncTextToCurrentSelection(ByVal formID As Long)

    Dim i As Long
    
    'Only synchronize the text boxes if a selection is active
    If Selections.SelectionsAllowed(False) Then
        
        pdImages(formID).mainSelection.SuspendAutoRefresh True
        
        'Selection coordinate toolboxes appear on three different selection subpanels: rect, ellipse, and line.
        ' To access their indicies properly, we must calculate an offset.
        Dim subpanelOffset As Long
        subpanelOffset = Selections.GetSelectionSubPanelFromSelectionShape(pdImages(formID)) * 4
        
        If Tool_Support.IsSelectionToolActive Then
        
            'Additional syncing is done if the selection is transformable; if it is not transformable, clear and lock the location text boxes
            If pdImages(formID).mainSelection.IsTransformable Then
                
                Dim tmpRectF As RECTF, tmpRectFRB As RECTF_RB
                
                'Different types of selections will display size and position differently
                Select Case pdImages(formID).mainSelection.GetSelectionShape
                    
                    'Rectangular and elliptical selections display left, top, width and height
                    Case ss_Rectangle, ss_Circle
                        tmpRectF = pdImages(formID).mainSelection.GetCornersLockedRect()
                        toolpanel_Selections.tudSel(subpanelOffset + 0).Value = tmpRectF.Left
                        toolpanel_Selections.tudSel(subpanelOffset + 1).Value = tmpRectF.Top
                        toolpanel_Selections.tudSel(subpanelOffset + 2).Value = tmpRectF.Width
                        toolpanel_Selections.tudSel(subpanelOffset + 3).Value = tmpRectF.Height
                        
                    'Line selections display x1, y1, x2, y2
                    Case ss_Line
                        tmpRectFRB = pdImages(formID).mainSelection.GetCornersUnlockedRect()
                        toolpanel_Selections.tudSel(subpanelOffset + 0).Value = tmpRectFRB.Left
                        toolpanel_Selections.tudSel(subpanelOffset + 1).Value = tmpRectFRB.Top
                        toolpanel_Selections.tudSel(subpanelOffset + 2).Value = tmpRectFRB.Right
                        toolpanel_Selections.tudSel(subpanelOffset + 3).Value = tmpRectFRB.Bottom
            
                End Select
                
            Else
            
                For i = 0 To toolpanel_Selections.tudSel.Count - 1
                    If (toolpanel_Selections.tudSel(i).Value <> 0) Then toolpanel_Selections.tudSel(i).Value = 0
                Next i
                
            End If
            
            'Next, sync all non-coordinate information
            If (pdImages(formID).mainSelection.GetSelectionShape <> ss_Raster) And (pdImages(formID).mainSelection.GetSelectionShape <> ss_Wand) Then
                toolpanel_Selections.cboSelArea(Selections.GetSelectionSubPanelFromSelectionShape(pdImages(formID))).ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Area)
                toolpanel_Selections.sltSelectionBorder(Selections.GetSelectionSubPanelFromSelectionShape(pdImages(formID))).Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_BorderWidth)
            End If
            
            If toolpanel_Selections.cboSelSmoothing.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Smoothing) Then toolpanel_Selections.cboSelSmoothing.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_Smoothing)
            If toolpanel_Selections.sltSelectionFeathering.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_FeatheringRadius) Then toolpanel_Selections.sltSelectionFeathering.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_FeatheringRadius)
            
            'Finally, sync any shape-specific information
            Select Case pdImages(formID).mainSelection.GetSelectionShape
            
                Case ss_Rectangle
                    If toolpanel_Selections.sltCornerRounding.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_RoundedCornerRadius) Then toolpanel_Selections.sltCornerRounding.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_RoundedCornerRadius)
                
                Case ss_Circle
                
                Case ss_Line
                    If toolpanel_Selections.sltSelectionLineWidth.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_LineWidth) Then toolpanel_Selections.sltSelectionLineWidth.Value = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_LineWidth)
                    
                Case ss_Lasso
                    If toolpanel_Selections.sltSmoothStroke.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_SmoothStroke) Then toolpanel_Selections.sltSmoothStroke.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_SmoothStroke)
                    
                Case ss_Polygon
                    If toolpanel_Selections.sltPolygonCurvature.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_PolygonCurvature) Then toolpanel_Selections.sltPolygonCurvature.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_PolygonCurvature)
                    
                Case ss_Wand
                    If toolpanel_Selections.btsWandArea.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSearchMode) Then toolpanel_Selections.btsWandArea.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSearchMode)
                    If toolpanel_Selections.btsWandMerge.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSampleMerged) Then toolpanel_Selections.btsWandMerge.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandSampleMerged)
                    If toolpanel_Selections.sltWandTolerance.Value <> pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_WandTolerance) Then toolpanel_Selections.sltWandTolerance.Value = pdImages(formID).mainSelection.GetSelectionProperty_Float(sp_WandTolerance)
                    If toolpanel_Selections.cboWandCompare.ListIndex <> pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandCompareMethod) Then toolpanel_Selections.cboWandCompare.ListIndex = pdImages(formID).mainSelection.GetSelectionProperty_Long(sp_WandCompareMethod)
            
            End Select
            
        End If
        
        pdImages(formID).mainSelection.SuspendAutoRefresh False
        
    Else
        
        SetUIGroupState PDUI_Selections, False
        SetUIGroupState PDUI_SelectionTransforms, False
        
        If Tool_Support.IsSelectionToolActive Then
            For i = 0 To toolpanel_Selections.tudSel.Count - 1
                If (toolpanel_Selections.tudSel(i).Value <> 0) Then toolpanel_Selections.tudSel(i).Value = 0
            Next i
        End If
        
    End If
    
End Sub

'Given an (x, y) pair in IMAGE coordinate space (not screen or canvas space), return a constant if the point is a valid
' "point of interest" to this selection.  Standard UI mouse distances are allowed (meaning zoom is factored into the
' algorithm).
'
'The result of this function is typically passed to something like pdSelection.SetActiveSelectionPOI(), which will cache
' the point of interest and use it to interpret subsequent mouse events (e.g. click-dragging a selection to a new position).
'
'Note that only certain POIs are hard-coded.  Some selections (e.g. polygons) can return other values outside the enum,
' typically indices into an internal selection point array.
'
'This sub will return a constant correlating to the nearest selection point.  See the relevant enum for details.
Public Function IsCoordSelectionPOI(ByVal imgX As Double, ByVal imgY As Double, ByRef srcImage As pdImage) As PD_PointOfInterest
    
    'If the current selection is...
    ' 1) raster-type, or...
    ' 2) inactive...
    '...disallow POIs entirely.  (These types of selections do not support on-canvas interactions.)
    If (srcImage.mainSelection.GetSelectionShape = ss_Raster) Or (Not srcImage.IsSelectionActive) Then
        IsCoordSelectionPOI = poi_Undefined
        Exit Function
    End If
    
    'We're now going to compare the passed coordinate against a hard-coded list of "points of interest."  These POIs
    ' differ by selection type, as different selections allow for different levels of interaction.  (For example, a polygon
    ' selection behaves differently when a point is dragged, vs a rectangular selection.)
    
    'Regardless of selection type, start by establishing boundaries for the current selection.
    'Calculate points of interest for the current selection.  Individual selection types define what is considered a POI,
    ' but in most cases, corners or interior clicks tend to allow some kind of user interaction.
    Dim tmpRectF As RECTF
    If (srcImage.mainSelection.GetSelectionShape = ss_Rectangle) Or (srcImage.mainSelection.GetSelectionShape = ss_Circle) Then
        tmpRectF = srcImage.mainSelection.GetCornersLockedRect()
    Else
        tmpRectF = srcImage.mainSelection.GetBoundaryRect()
    End If
    
    'Adjust the mouseAccuracy value based on the current zoom value
    Dim mouseAccuracy As Double
    mouseAccuracy = g_MouseAccuracy * (1 / g_Zoom.GetZoomValue(srcImage.GetZoom))
        
    'Find the smallest distance for this mouse position
    Dim minDistance As Double
    minDistance = mouseAccuracy
    
    Dim closestPoint As Long
    closestPoint = poi_Undefined
    
    'Some selection types (lasso, polygon) must use a more complicated region for hit-testing.  GDI+ will be used for this.
    Dim gdipRegionHandle As Long, gdipHitCheck As Boolean
    
    'Other selection types will use a generic list of points (like the corners of the current selection)
    Dim poiListFloat() As POINTFLOAT
    
    'If we made it here, this mouse location is worth evaluating.  How we evaluate it depends on the shape of the current selection.
    Select Case srcImage.mainSelection.GetSelectionShape
    
        'Rectangular and elliptical selections have identical POIs: the corners, edges, and interior of the selection
        Case ss_Rectangle, ss_Circle
    
            'Corners get preference, so check them first.
            ReDim poiListFloat(0 To 3) As POINTFLOAT
            
            With tmpRectF
                poiListFloat(0).x = .Left
                poiListFloat(0).y = .Top
                poiListFloat(1).x = .Left + .Width
                poiListFloat(1).y = .Top
                poiListFloat(2).x = .Left + .Width
                poiListFloat(2).y = .Top + .Height
                poiListFloat(3).x = .Left
                poiListFloat(3).y = .Top + .Height
            End With
            
            'Used the generalized point comparison function to see if one of the points matches
            closestPoint = FindClosestPointInFloatArray(imgX, imgY, minDistance, poiListFloat)
            
            'Did one of the corner points match?  If so, map it to a valid constant and return.
            If (closestPoint <> poi_Undefined) Then
                
                If (closestPoint = 0) Then
                    IsCoordSelectionPOI = poi_CornerNW
                ElseIf (closestPoint = 1) Then
                    IsCoordSelectionPOI = poi_CornerNE
                ElseIf (closestPoint = 2) Then
                    IsCoordSelectionPOI = poi_CornerSE
                ElseIf (closestPoint = 3) Then
                    IsCoordSelectionPOI = poi_CornerSW
                End If
                
            Else
        
                'If we're at this line of code, a closest corner was not found.  Check edges next.
                ' (Unfortunately, we don't yet have a generalized function for edge checking, so this must be done manually.)
                '
                'Note that edge checks are a little weird currently, because we check one-dimensional distance between each
                ' side, and if that's a hit, we see if the point also lies between the bounds in the *other* direction.
                ' This allows the user to use the entire selection side to perform a stretch.
                Dim nDist As Double, eDist As Double, sDist As Double, wDist As Double
                
                With tmpRectF
                    nDist = DistanceOneDimension(imgY, .Top)
                    eDist = DistanceOneDimension(imgX, .Left + .Width)
                    sDist = DistanceOneDimension(imgY, .Top + .Height)
                    wDist = DistanceOneDimension(imgX, .Left)
                
                    If (nDist <= minDistance) Then
                        If (imgX > (.Left - minDistance)) And (imgX < (.Left + .Width + minDistance)) Then
                            minDistance = nDist
                            closestPoint = poi_EdgeN
                        End If
                    End If
                    
                    If (eDist <= minDistance) Then
                        If (imgY > (.Top - minDistance)) And (imgY < (.Top + .Height + minDistance)) Then
                            minDistance = eDist
                            closestPoint = poi_EdgeE
                        End If
                    End If
                    
                    If (sDist <= minDistance) Then
                        If (imgX > (.Left - minDistance)) And (imgX < (.Left + .Width + minDistance)) Then
                            minDistance = sDist
                            closestPoint = poi_EdgeS
                        End If
                    End If
                    
                    If (wDist <= minDistance) Then
                        If (imgY > (.Top - minDistance)) And (imgY < (.Top + .Height + minDistance)) Then
                            minDistance = wDist
                            closestPoint = poi_EdgeW
                        End If
                    End If
                
                End With
                
                'Was a close point found? If yes, then return that value.
                If (closestPoint <> poi_Undefined) Then
                    IsCoordSelectionPOI = closestPoint
                    
                Else
            
                    'If we're at this line of code, a closest edge was not found. Perform one final check to ensure that the mouse is within the
                    ' image's boundaries, and if it is, return the "move selection" ID, then exit.
                    If Math_Functions.IsPointInRectF(imgX, imgY, tmpRectF) Then
                        IsCoordSelectionPOI = poi_Interior
                    Else
                        IsCoordSelectionPOI = poi_Undefined
                    End If
                    
                End If
                
            End If
            
        Case ss_Line
    
            'Line selections are simple - we only care if the mouse is by (x1,y1) or (x2,y2)
            Dim xCoord As Double, yCoord As Double
            Dim firstDist As Double, secondDist As Double
            
            closestPoint = poi_Undefined
            
            srcImage.mainSelection.GetSelectionCoordinates 1, xCoord, yCoord
            firstDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
            
            srcImage.mainSelection.GetSelectionCoordinates 2, xCoord, yCoord
            secondDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
                        
            If (firstDist <= minDistance) Then closestPoint = 0
            If (secondDist <= minDistance) Then closestPoint = 1
            
            'Was a close point found? If yes, then return that value.
            IsCoordSelectionPOI = closestPoint
            Exit Function
        
        Case ss_Polygon
        
            'First, we want to check all polygon points for a hit.
            pdImages(g_CurrentImage).mainSelection.GetPolygonPoints poiListFloat()
            
            'Used the generalized point comparison function to see if one of the points matches
            closestPoint = FindClosestPointInFloatArray(imgX, imgY, minDistance, poiListFloat)
            
            'Was a close point found? If yes, then return that value
            If (closestPoint <> poi_Undefined) Then
                IsCoordSelectionPOI = closestPoint
                
            'If no polygon point was a hit, our final check is to see if the mouse lies within the polygon itself.  This will trigger
            ' a move transformation.
            Else
                
                'Create a GDI+ region from the current selection points
                gdipRegionHandle = pdImages(g_CurrentImage).mainSelection.GetGdipRegionForSelection()
                
                'Check the point for a hit
                gdipHitCheck = GDI_Plus.IsPointInGDIPlusRegion(imgX, imgY, gdipRegionHandle)
                
                'Release the GDI+ region
                GDI_Plus.ReleaseGDIPlusRegion gdipRegionHandle
                
                If gdipHitCheck Then IsCoordSelectionPOI = pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints Else IsCoordSelectionPOI = poi_Undefined
                
            End If
        
        Case ss_Lasso
            'Create a GDI+ region from the current selection points
            gdipRegionHandle = pdImages(g_CurrentImage).mainSelection.GetGdipRegionForSelection()
            
            'Check the point for a hit
            gdipHitCheck = GDI_Plus.IsPointInGDIPlusRegion(imgX, imgY, gdipRegionHandle)
            
            'Release the GDI+ region
            GDI_Plus.ReleaseGDIPlusRegion gdipRegionHandle
            
            If gdipHitCheck Then IsCoordSelectionPOI = 0 Else IsCoordSelectionPOI = poi_Undefined
        
        Case ss_Wand
            closestPoint = poi_Undefined
            
            srcImage.mainSelection.GetSelectionCoordinates 1, xCoord, yCoord
            firstDist = DistanceTwoPoints(imgX, imgY, xCoord, yCoord)
                        
            If (firstDist <= minDistance) Then closestPoint = 0
            
            'Was a close point found? If yes, then return that value.
            IsCoordSelectionPOI = closestPoint
            Exit Function
        
        Case Else
            IsCoordSelectionPOI = poi_Undefined
            Exit Function
            
    End Select

End Function

'Invert the current selection.  Note that this will make a transformable selection non-transformable - to maintain transformability, use
' the "exterior"/"interior" options on the main form.
' TODO: swap exterior/interior automatically, if a valid option
Public Sub InvertCurrentSelection()

    'Unselect any existing selection
    pdImages(g_CurrentImage).mainSelection.LockRelease
    pdImages(g_CurrentImage).SetSelectionActive False
        
    Message "Inverting selection..."
    
    'Point a standard 2D byte array at the selection mask
    Dim x As Long, y As Long
    Dim xStride As Long
    
    Dim selMaskData() As Byte
    Dim selMaskSA As SAFEARRAY2D
    PrepSafeArray selMaskSA, pdImages(g_CurrentImage).mainSelection.GetMaskDIB
    CopyMemory ByVal VarPtrArray(selMaskData()), VarPtr(selMaskSA), 4
    
    Dim maskWidth As Long, maskHeight As Long
    maskWidth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth - 1
    maskHeight = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight - 1
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    SetProgBarMax maskWidth
    Dim progBarCheck As Long
    progBarCheck = FindBestProgBarValue()
    
    Dim selMaskDepth As Long
    selMaskDepth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBColorDepth \ 8
    
    'After all that work, the Invert code itself is very small and unexciting!
    For x = 0 To maskWidth
        xStride = x * selMaskDepth
    For y = 0 To maskHeight
        selMaskData(xStride, y) = 255 - selMaskData(xStride, y)
        selMaskData(xStride + 1, y) = 255 - selMaskData(xStride + 1, y)
        selMaskData(xStride + 2, y) = 255 - selMaskData(xStride + 2, y)
    Next y
        If (x And progBarCheck) = 0 Then SetProgBarVal x
    Next x
    
    'Release our temporary byte array
    CopyMemory ByVal VarPtrArray(selMaskData), 0&, 4
    Erase selMaskData
    
    'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
    ' being non-transformable)
    pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
    
    SetProgBarVal 0
    ReleaseProgressBar
    Message "Selection inversion complete."
    
    'Lock in this selection
    pdImages(g_CurrentImage).mainSelection.LockIn
    pdImages(g_CurrentImage).SetSelectionActive True
        
    'Draw the new selection to the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'Feather the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub FeatherCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal featherRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retRadius As Double
        If DisplaySelectionDialog(SEL_FEATHER, retRadius) = vbOK Then
            Process "Feather selection", False, Str(retRadius), UNDO_SELECTION
        End If
        
    Else
    
        Message "Feathering selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).SetSelectionActive False
        
        'Use PD's built-in Gaussian blur function to apply the blur
        QuickBlurDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB, featherRadius, True
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).SetSelectionActive True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Feathering complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If

End Sub

'Sharpen (un-feather?) the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub SharpenCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal sharpenRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retRadius As Double
        If DisplaySelectionDialog(SEL_SHARPEN, retRadius) = vbOK Then
            Process "Sharpen selection", False, Str(retRadius), UNDO_SELECTION
        End If
        
    Else
    
        Message "Sharpening selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).SetSelectionActive False
        
       'Point an array at the current selection mask
        Dim selMaskData() As Byte
        Dim selMaskSA As SAFEARRAY2D
        
        'Create a second local array.  This will contain the a copy of the selection mask, and we will use it as our source reference
        ' (This is necessary to prevent blurred pixel values from spreading across the image as we go.)
        Dim srcDIB As pdDIB
        Set srcDIB = New pdDIB
        srcDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
                
        'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
        Dim x As Long, y As Long
        
        'Unsharp masking requires a gaussian blur DIB to operate.  Create one now.
        QuickBlurDIB srcDIB, sharpenRadius, True
        
        'Now that we have a gaussian DIB created in workingDIB, we can point arrays toward it and the source DIB
        PrepSafeArray selMaskSA, pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CopyMemory ByVal VarPtrArray(selMaskData()), VarPtr(selMaskSA), 4
        
        Dim srcImageData() As Byte
        Dim srcSA As SAFEARRAY2D
        PrepSafeArray srcSA, srcDIB
        CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
        'These values will help us access locations in the array more quickly.
        ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
        Dim xStride As Long, qvDepth As Long
        qvDepth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBColorDepth \ 8
        
        'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
        ' based on the size of the area to be processed.
        Dim progBarCheck As Long
        SetProgBarMax pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth
        progBarCheck = FindBestProgBarValue()
        
        'ScaleFactor is used to apply the unsharp mask.  Maximum strength can be any value, but PhotoDemon locks it at 10.
        Dim scaleFactor As Double, invScaleFactor As Double
        scaleFactor = sharpenRadius
        invScaleFactor = 1 - scaleFactor
        
        Dim iWidth As Long, iHeight As Long
        iWidth = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth - 1
        iHeight = pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight - 1
        
        Dim blendVal As Double
        
        'More color variables - in this case, sums for each color component
        Dim r As Long, g As Long, b As Long
        Dim r2 As Long, g2 As Long, b2 As Long
        Dim newR As Long, newG As Long, newB As Long
        Dim tLumDelta As Long
        
        'The final step of the smart blur function is to find edges, and replace them with the blurred data as necessary
        For x = 0 To iWidth
            xStride = x * qvDepth
        For y = 0 To iHeight
                
            'Retrieve the original image's pixels
            r = selMaskData(xStride + 2, y)
            g = selMaskData(xStride + 1, y)
            b = selMaskData(xStride, y)
            
            'Now, retrieve the gaussian pixels
            r2 = srcImageData(xStride + 2, y)
            g2 = srcImageData(xStride + 1, y)
            b2 = srcImageData(xStride, y)
            
            tLumDelta = Abs(GetLuminance(r, g, b) - GetLuminance(r2, g2, b2))
                
            newR = (scaleFactor * r) + (invScaleFactor * r2)
            If newR > 255 Then newR = 255
            If newR < 0 Then newR = 0
                
            newG = (scaleFactor * g) + (invScaleFactor * g2)
            If newG > 255 Then newG = 255
            If newG < 0 Then newG = 0
                
            newB = (scaleFactor * b) + (invScaleFactor * b2)
            If newB > 255 Then newB = 255
            If newB < 0 Then newB = 0
            
            blendVal = tLumDelta / 255
            
            newR = BlendColors(newR, r, blendVal)
            newG = BlendColors(newG, g, blendVal)
            newB = BlendColors(newB, b, blendVal)
            
            selMaskData(xStride + 2, y) = newR
            selMaskData(xStride + 1, y) = newG
            selMaskData(xStride, y) = newB
                    
        Next y
            If (x And progBarCheck) = 0 Then SetProgBarVal x
        Next x
        
        CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
        Erase srcImageData
        
        CopyMemory ByVal VarPtrArray(selMaskData), 0&, 4
        Erase selMaskData
        
        Set srcDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).SetSelectionActive True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Feathering complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If

End Sub

'Grow the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub GrowCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal growSize As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_GROW, retSize) = vbOK Then
            Process "Grow selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Growing selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).SetSelectionActive False
        
        'Use PD's built-in Median function to dilate the selected area
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CreateMedianDIB growSize, 99, PDPRS_Circle, tmpDIB, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, False
        
        Set tmpDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).SetSelectionActive True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Shrink the current selection.  Note that this will make a transformable selection non-transformable.
Public Sub ShrinkCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal shrinkSize As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_SHRINK, retSize) = vbOK Then
            Process "Shrink selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Shrinking selection..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).SetSelectionActive False
        
        'Use PD's built-in Median function to erode the selected area
        Dim tmpDIB As pdDIB
        Set tmpDIB = New pdDIB
        tmpDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        CreateMedianDIB shrinkSize, 1, PDPRS_Circle, tmpDIB, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, False
        
        'Erase the temporary DIB
        Set tmpDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
        
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).SetSelectionActive True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Convert the current selection to border-type.  Note that this will make a transformable selection non-transformable.
Public Sub BorderCurrentSelection(ByVal ShowDialog As Boolean, Optional ByVal borderRadius As Double = 0#)

    'If a dialog has been requested, display one to the user.  Otherwise, proceed with the feathering.
    If ShowDialog Then
        
        Dim retSize As Double
        If DisplaySelectionDialog(SEL_BORDER, retSize) = vbOK Then
            Process "Border selection", False, Str(retSize), UNDO_SELECTION
        End If
        
    Else
    
        Message "Finding selection border..."
    
        'Unselect any existing selection
        pdImages(g_CurrentImage).mainSelection.LockRelease
        pdImages(g_CurrentImage).SetSelectionActive False
        
        'Bordering a selection requires two passes: a grow pass and a shrink pass.  The results of these two passes are then blended
        ' to create the final bordered selection.
        
        'Start by creating the grow and shrink DIBs using a median function.
        Dim growDIB As pdDIB
        Set growDIB = New pdDIB
        growDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        
        Dim shrinkDIB As pdDIB
        Set shrinkDIB = New pdDIB
        shrinkDIB.CreateFromExistingDIB pdImages(g_CurrentImage).mainSelection.GetMaskDIB
        
        'Use a median function to dilate and erode the existing mask
        CreateMedianDIB borderRadius, 1, PDPRS_Circle, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, shrinkDIB, False, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth * 2
        CreateMedianDIB borderRadius, 99, PDPRS_Circle, pdImages(g_CurrentImage).mainSelection.GetMaskDIB, growDIB, False, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth * 2, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth
        
        'Blend those two DIBs together, and use the difference between the two to calculate the new border area
        pdImages(g_CurrentImage).mainSelection.GetMaskDIB.CreateFromExistingDIB growDIB
        BitBlt pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBDC, 0, 0, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBWidth, pdImages(g_CurrentImage).mainSelection.GetMaskDIB.GetDIBHeight, shrinkDIB.GetDIBDC, 0, 0, vbSrcInvert
        
        'Erase the temporary DIBs
        Set growDIB = Nothing
        Set shrinkDIB = Nothing
        
        'Ask the selection to find new boundaries.  This will also set all relevant parameters for the modified selection (such as
        ' being non-transformable)
        pdImages(g_CurrentImage).mainSelection.FindNewBoundsManually
                
        'Lock in this selection
        pdImages(g_CurrentImage).mainSelection.LockIn
        pdImages(g_CurrentImage).SetSelectionActive True
                
        SetProgBarVal 0
        ReleaseProgressBar
        
        Message "Selection resize complete."
        
        'Draw the new selection to the screen
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
    
    End If
    
End Sub

'Erase the currently selected area (LAYER ONLY!).  Note that this will not modify the current selection in any way.
Public Sub EraseSelectedArea(ByVal targetLayerIndex As Long)

    pdImages(g_CurrentImage).EraseProcessedSelection targetLayerIndex
    
    'Redraw the active viewport
    Viewport_Engine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), FormMain.mainCanvas(0)

End Sub

'The selection engine integrates closely with tool selection (as it needs to know what kind of selection is being
' created/edited at any given time).  This function is called whenever the selection engine needs to correlate the
' current tool with a selection shape.  This allows us to easily switch between a rectangle and circle selection,
' for example, without forcing the user to recreate the selection from scratch.
Public Function GetSelectionShapeFromCurrentTool() As PD_SelectionShape

    Select Case g_CurrentTool
    
        Case SELECT_RECT
            GetSelectionShapeFromCurrentTool = ss_Rectangle
            
        Case SELECT_CIRC
            GetSelectionShapeFromCurrentTool = ss_Circle
        
        Case SELECT_LINE
            GetSelectionShapeFromCurrentTool = ss_Line
            
        Case SELECT_POLYGON
            GetSelectionShapeFromCurrentTool = ss_Polygon
            
        Case SELECT_LASSO
            GetSelectionShapeFromCurrentTool = ss_Lasso
            
        Case SELECT_WAND
            GetSelectionShapeFromCurrentTool = ss_Wand
            
        Case Else
            GetSelectionShapeFromCurrentTool = -1
    
    End Select
    
End Function

'The inverse of "getSelectionShapeFromCurrentTool", above
Public Function GetRelevantToolFromSelectShape() As PDTools

    If (g_OpenImageCount > 0) Then

        If (Not pdImages(g_CurrentImage).mainSelection Is Nothing) Then

            Select Case pdImages(g_CurrentImage).mainSelection.GetSelectionShape
            
                Case ss_Rectangle
                    GetRelevantToolFromSelectShape = SELECT_RECT
                    
                Case ss_Circle
                    GetRelevantToolFromSelectShape = SELECT_CIRC
                
                Case ss_Line
                    GetRelevantToolFromSelectShape = SELECT_LINE
                
                Case ss_Polygon
                    GetRelevantToolFromSelectShape = SELECT_POLYGON
                    
                Case ss_Lasso
                    GetRelevantToolFromSelectShape = SELECT_LASSO
                    
                Case ss_Wand
                    GetRelevantToolFromSelectShape = SELECT_WAND
                
                Case Else
                    GetRelevantToolFromSelectShape = -1
            
            End Select
            
        Else
            GetRelevantToolFromSelectShape = -1
        End If
            
    Else
        GetRelevantToolFromSelectShape = -1
    End If

End Function

'All selection tools share the same main panel on the options toolbox, but they have different subpanels that contain their
' specific parameters.  Use this function to correlate the two.
Public Function GetSelectionSubPanelFromCurrentTool() As Long

    Select Case g_CurrentTool
    
        Case SELECT_RECT
            GetSelectionSubPanelFromCurrentTool = 0
            
        Case SELECT_CIRC
            GetSelectionSubPanelFromCurrentTool = 1
        
        Case SELECT_LINE
            GetSelectionSubPanelFromCurrentTool = 2
            
        Case SELECT_POLYGON
            GetSelectionSubPanelFromCurrentTool = 3
            
        Case SELECT_LASSO
            GetSelectionSubPanelFromCurrentTool = 4
            
        Case SELECT_WAND
            GetSelectionSubPanelFromCurrentTool = 5
        
        Case Else
            GetSelectionSubPanelFromCurrentTool = -1
    
    End Select
    
End Function

Public Function GetSelectionSubPanelFromSelectionShape(ByRef srcImage As pdImage) As Long

    Select Case srcImage.mainSelection.GetSelectionShape
    
        Case ss_Rectangle
            GetSelectionSubPanelFromSelectionShape = 0
            
        Case ss_Circle
            GetSelectionSubPanelFromSelectionShape = 1
        
        Case ss_Line
            GetSelectionSubPanelFromSelectionShape = 2
            
        Case ss_Polygon
            GetSelectionSubPanelFromSelectionShape = 3
            
        Case ss_Lasso
            GetSelectionSubPanelFromSelectionShape = 4
            
        Case ss_Wand
            GetSelectionSubPanelFromSelectionShape = 5
        
        Case Else
            'Debug.Print "WARNING!  Selections.getSelectionSubPanelFromSelectionShape() was called, despite a selection not being active!"
            GetSelectionSubPanelFromSelectionShape = -1
    
    End Select
    
End Function

'Selections can be initiated several different ways.  To cut down on duplicated code, all new selection instances are referred
' to this function.  Initial X/Y values are required.
Public Sub InitSelectionByPoint(ByVal x As Double, ByVal y As Double)

    'Activate the attached image's primary selection
    pdImages(g_CurrentImage).SetSelectionActive True
    pdImages(g_CurrentImage).mainSelection.LockRelease
    
    'Reflect all current selection tool settings to the active selection object
    Dim curShape As PD_SelectionShape
    curShape = Selections.GetSelectionShapeFromCurrentTool()
    With pdImages(g_CurrentImage).mainSelection
        .SetSelectionShape curShape
        If (curShape <> ss_Wand) Then .SetSelectionProperty sp_Area, toolpanel_Selections.cboSelArea(Selections.GetSelectionSubPanelFromCurrentTool).ListIndex
        .SetSelectionProperty sp_Smoothing, toolpanel_Selections.cboSelSmoothing.ListIndex
        .SetSelectionProperty sp_FeatheringRadius, toolpanel_Selections.sltSelectionFeathering.Value
        If (curShape <> ss_Wand) Then .SetSelectionProperty sp_BorderWidth, toolpanel_Selections.sltSelectionBorder(Selections.GetSelectionSubPanelFromCurrentTool).Value
        .SetSelectionProperty sp_RoundedCornerRadius, toolpanel_Selections.sltCornerRounding.Value
        .SetSelectionProperty sp_LineWidth, toolpanel_Selections.sltSelectionLineWidth.Value
        If (curShape = ss_Polygon) Then .SetSelectionProperty sp_PolygonCurvature, toolpanel_Selections.sltPolygonCurvature.Value
        If (curShape = ss_Lasso) Then .SetSelectionProperty sp_SmoothStroke, toolpanel_Selections.sltSmoothStroke.Value
        If (curShape = ss_Wand) Then
            .SetSelectionProperty sp_WandTolerance, toolpanel_Selections.sltWandTolerance.Value
            .SetSelectionProperty sp_WandSampleMerged, toolpanel_Selections.btsWandMerge.ListIndex
            .SetSelectionProperty sp_WandSearchMode, toolpanel_Selections.btsWandArea.ListIndex
            .SetSelectionProperty sp_WandCompareMethod, toolpanel_Selections.cboWandCompare.ListIndex
        End If
    End With
    
    'Set the first two coordinates of this selection to this mouseclick's location
    pdImages(g_CurrentImage).mainSelection.SetInitialCoordinates x, y
    SyncTextToCurrentSelection g_CurrentImage
    pdImages(g_CurrentImage).mainSelection.RequestNewMask
    
    'Make the selection tools visible
    SetUIGroupState PDUI_Selections, True
    SetUIGroupState PDUI_SelectionTransforms, True
    
    'Redraw the screen
    Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), FormMain.mainCanvas(0)
                        
End Sub

'Are selections currently allowed?  Program states like "no open images" prevent selections from ever being created, and individual
' functions can use this function to determine it.  Passing TRUE for the transformableMatters param will add a check for an existing,
' transformable-type selection (squares, etc) to the evaluation list.
Public Function SelectionsAllowed(ByVal transformableMatters As Boolean) As Boolean

    If (g_OpenImageCount > 0) Then
        If pdImages(g_CurrentImage).IsSelectionActive And (Not pdImages(g_CurrentImage).mainSelection Is Nothing) Then
            If (Not pdImages(g_CurrentImage).mainSelection.GetAutoRefreshSuspend()) Then
                If transformableMatters Then
                    SelectionsAllowed = pdImages(g_CurrentImage).mainSelection.IsTransformable
                Else
                    SelectionsAllowed = True
                End If
            Else
                SelectionsAllowed = False
            End If
        Else
            SelectionsAllowed = False
        End If
    Else
        SelectionsAllowed = False
    End If
    
End Function

'Whenever a selection render setting changes (like switching between outline and highlight mode), you must call this function
' so that we can cache the new render settings.
Public Sub NotifySelectionRenderChange()
    m_CurSelectionMode = toolpanel_Selections.cboSelRender.ListIndex
    m_CurSelectionColor = toolpanel_Selections.csSelectionHighlight.Color
End Sub

Public Function GetSelectionRenderMode() As PD_SelectionRender
    GetSelectionRenderMode = m_CurSelectionMode
End Function

Public Function GetSelectionRenderColor() As Long
    GetSelectionRenderColor = m_CurSelectionColor
End Function

'Keypresses on a source canvas are passed here.  The caller doesn't need pass anything except relevant keycodes, and a reference
' to itself (so we can relay canvas modifications).
Public Sub NotifySelectionKeyDown(ByRef srcCanvas As pdCanvas, ByVal Shift As ShiftConstants, ByVal vkCode As Long, ByRef markEventHandled As Boolean)

    'Handle arrow keys first
    If (vkCode = VK_UP) Or (vkCode = VK_DOWN) Or (vkCode = VK_LEFT) Or (vkCode = VK_RIGHT) Then

        'If a selection is active, nudge it using the arrow keys
        If (pdImages(g_CurrentImage).IsSelectionActive And (pdImages(g_CurrentImage).mainSelection.GetSelectionShape <> ss_Raster)) Then
            
            Dim canvasUpdateRequired As Boolean
            canvasUpdateRequired = False
            
            'Suspend automatic redraws until all arrow keys have been processed
            srcCanvas.SetRedrawSuspension True
            
            'If scrollbars are visible, nudge the canvas in the direction of the arrows.
            If srcCanvas.GetScrollVisibility(PD_VERTICAL) Then
                If (vkCode = VK_UP) Or (vkCode = VK_DOWN) Then canvasUpdateRequired = True
                If (vkCode = VK_UP) Then srcCanvas.SetScrollValue PD_VERTICAL, srcCanvas.GetScrollValue(PD_VERTICAL) - 1
                If (vkCode = VK_DOWN) Then srcCanvas.SetScrollValue PD_VERTICAL, srcCanvas.GetScrollValue(PD_VERTICAL) + 1
            End If
            
            If srcCanvas.GetScrollVisibility(PD_HORIZONTAL) Then
                If (vkCode = VK_LEFT) Or (vkCode = VK_RIGHT) Then canvasUpdateRequired = True
                If (vkCode = VK_LEFT) Then srcCanvas.SetScrollValue PD_HORIZONTAL, srcCanvas.GetScrollValue(PD_HORIZONTAL) - 1
                If (vkCode = VK_RIGHT) Then srcCanvas.SetScrollValue PD_HORIZONTAL, srcCanvas.GetScrollValue(PD_HORIZONTAL) + 1
            End If
            
            'Re-enable automatic redraws
            srcCanvas.SetRedrawSuspension False
            
            'Redraw the viewport if necessary
            If canvasUpdateRequired Then
                markEventHandled = True
                Viewport_Engine.Stage2_CompositeAllLayers pdImages(g_CurrentImage), srcCanvas
            End If
            
        End If
    
    'Handle non-arrow keys here.  (Note: most non-arrow keys are not meant to work with key-repeating,
    ' so they are handled in the KeyUp event instead.)
    Else
        
    End If
    
End Sub

Public Sub NotifySelectionKeyUp(ByRef srcCanvas As pdCanvas, ByVal Shift As ShiftConstants, ByVal vkCode As Long, ByRef markEventHandled As Boolean)

    'Delete key: if a selection is active, erase the selected area
    If (vkCode = VK_DELETE) And pdImages(g_CurrentImage).IsSelectionActive Then
        markEventHandled = True
        Process "Erase selected area", False, BuildParams(pdImages(g_CurrentImage).GetActiveLayerIndex), UNDO_LAYER
    End If
    
    'Escape key: if a selection is active, clear it
    If (vkCode = VK_ESCAPE) And pdImages(g_CurrentImage).IsSelectionActive Then
        markEventHandled = True
        Process "Remove selection", , , UNDO_SELECTION
    End If
    
    'Backspace key: for lasso and polygon selections, retreat back one or more coordinates, giving the user a chance to
    ' correct any potential mistakes.
    If ((g_CurrentTool = SELECT_LASSO) Or (g_CurrentTool = SELECT_POLYGON)) And (vkCode = VK_BACK) And pdImages(g_CurrentImage).IsSelectionActive And (Not pdImages(g_CurrentImage).mainSelection.IsLockedIn) Then
        
        markEventHandled = True
        
        'Polygons: do not allow point removal if the polygon has already been successfully closed.
        If (g_CurrentTool = SELECT_POLYGON) Then
            If (Not pdImages(g_CurrentImage).mainSelection.GetPolygonClosedState) Then pdImages(g_CurrentImage).mainSelection.RemoveLastPolygonPoint
        
        'Lassos: do not allow point removal if the lasso has already been successfully closed.
        Else
        
            If (Not pdImages(g_CurrentImage).mainSelection.GetLassoClosedState) Then
        
                'Ask the selection object to retreat its position
                Dim newImageX As Double, newImageY As Double
                pdImages(g_CurrentImage).mainSelection.RetreatLassoPosition newImageX, newImageY
                
                'The returned coordinates will be in image coordinates.  Convert them to viewport coordinates.
                Dim newCanvasX As Double, newCanvasY As Double
                Drawing.ConvertImageCoordsToCanvasCoords srcCanvas, pdImages(g_CurrentImage), newImageX, newImageY, newCanvasX, newCanvasY
                
                'Finally, convert the canvas coordinates to screen coordinates, and move the cursor accordingly
                srcCanvas.SetCursorToCanvasPosition newCanvasX, newCanvasY
                
            End If
            
        End If
        
        'Redraw the screen to reflect this new change.
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
    
    End If
                
End Sub

Public Sub NotifySelectionMouseDown(ByVal srcCanvas As pdCanvas, ByVal imgX As Single, ByVal imgY As Single)
    
    'Because the wand tool is extremely simple, handle it specially
    If (g_CurrentTool = SELECT_WAND) Then
    
        'Magic wand selections never transform - they only generate anew
        Selections.InitSelectionByPoint imgX, imgY
        Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
        
    Else
        
        'Check to see if a selection is already active.  If it is, see if the user is allowed to transform it.
        If pdImages(g_CurrentImage).IsSelectionActive Then
        
            'Check the mouse coordinates of this click.
            Dim sCheck As PD_PointOfInterest
            sCheck = Selections.IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
            
            'If a point of interest was clicked, initiate a transform
            If (sCheck <> poi_Undefined) And (pdImages(g_CurrentImage).mainSelection.GetSelectionShape <> ss_Polygon) And (pdImages(g_CurrentImage).mainSelection.GetSelectionShape <> ss_Raster) Then
                
                'Initialize a selection transformation
                pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI sCheck
                pdImages(g_CurrentImage).mainSelection.SetInitialTransformCoordinates imgX, imgY
                                
            'If a point of interest was *not* clicked, erase any existing selection and start a new one
            Else
                
                'Polygon selections require special handling, because they don't operate on the "mouse up = complete" assumption.
                ' They are completed when the user re-clicks the first point.  Any clicks prior to that point are treated as
                ' an instruction to add a new points.
                If (g_CurrentTool = SELECT_POLYGON) Then
                    
                    'First, see if the selection is locked in.  If it is, treat this is a regular transformation.
                    If pdImages(g_CurrentImage).mainSelection.IsLockedIn Then
                        pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI sCheck
                        pdImages(g_CurrentImage).mainSelection.SetInitialTransformCoordinates imgX, imgY
                    
                    'Selection is not locked in, meaning the user is still constructing it.
                    Else
                    
                        'If the user clicked on the initial polygon point, attempt to close the polygon
                        If (sCheck = 0) And (pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints > 2) Then
                            pdImages(g_CurrentImage).mainSelection.SetPolygonClosedState True
                            pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI 0
                        
                        'The user did not click the initial polygon point, meaning we should add this coordinate as a new polygon point.
                        Else
                            
                            'Remove the current transformation mode (if any)
                            pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI poi_Undefined
                            pdImages(g_CurrentImage).mainSelection.OverrideTransformMode False
                            
                            'Add the new point
                            If (pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints = 0) Then
                                Selections.InitSelectionByPoint imgX, imgY
                            Else
                                
                                If (sCheck = poi_Undefined) Or (sCheck = pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints) Then
                                    pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                                    pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints - 1
                                Else
                                    pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI sCheck
                                End If
                                
                            End If
                            
                            'Reinstate transformation mode, using the index of the new point as the transform ID
                            pdImages(g_CurrentImage).mainSelection.SetInitialTransformCoordinates imgX, imgY
                            pdImages(g_CurrentImage).mainSelection.OverrideTransformMode True
                            
                            'Redraw the screen
                            Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
                            
                        End If
                    
                    End If
                    
                Else
                    Selections.InitSelectionByPoint imgX, imgY
                End If
                
            End If
        
        'If a selection is not active, start a new one
        Else
            
            Selections.InitSelectionByPoint imgX, imgY
            
            'Polygon selections require special handling, as usual.  After creating the initial point, we want to immediately initiate
            ' transform mode, because dragging the mouse will simply move the newly created point.
            If (g_CurrentTool = SELECT_POLYGON) Then
                pdImages(g_CurrentImage).mainSelection.SetActiveSelectionPOI pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints - 1
                pdImages(g_CurrentImage).mainSelection.OverrideTransformMode True
            End If
            
        End If
        
    End If
    
End Sub

Public Sub NotifySelectionMouseMove(ByVal srcCanvas As pdCanvas, ByVal Shift As ShiftConstants, ByVal imgX As Single, ByVal imgY As Single, ByVal numOfCanvasMoveEvents As Long)
    
    'Basic selection tools
    Select Case g_CurrentTool
        
        Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_POLYGON

            'First, check to see if a selection is both active and transformable.
            If pdImages(g_CurrentImage).IsSelectionActive And (pdImages(g_CurrentImage).mainSelection.GetSelectionShape <> ss_Raster) Then
                
                'If the SHIFT key is down, notify the selection engine that a square shape is requested
                pdImages(g_CurrentImage).mainSelection.RequestSquare (Shift And vbShiftMask)
                
                'Pass new points to the active selection
                pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                Selections.SyncTextToCurrentSelection g_CurrentImage
                                    
            End If
            
            'Force a redraw of the viewport
            If (numOfCanvasMoveEvents > 1) Then Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
        
        'Lasso selections are handled specially, because mouse move events control the drawing of the lasso
        Case SELECT_LASSO
        
            'First, check to see if a selection is active
            If pdImages(g_CurrentImage).IsSelectionActive Then
                
                'Pass new points to the active selection
                pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                                    
            End If
            
            'To spare the debug logger from receiving too many events, forcibly prevent logging of this message
            ' while in debug mode.
            #If DEBUGMODE = 1 Then
                Message "Release the mouse button to complete the lasso selection", "DONOTLOG"
            #Else
                Message "Release the mouse button to complete the lasso selection"
            #End If
            
            'Force a redraw of the viewport
            If (numOfCanvasMoveEvents > 1) Then Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
        
        'Wand selections are easier than other selection types, because they don't support any special transforms
        Case SELECT_WAND
            If pdImages(g_CurrentImage).IsSelectionActive Then
                pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
            End If
    
    End Select
    
End Sub

Public Sub NotifySelectionMouseUp(ByVal srcCanvas As pdCanvas, ByVal Shift As ShiftConstants, ByVal imgX As Single, ByVal imgY As Single, ByVal clickEventAlsoFiring As Boolean, ByVal wasSelectionActiveBeforeMouseEvents As Boolean)
    
    Dim eraseThisSelection As Boolean
    
    Select Case g_CurrentTool
    
        'Most selection tools are handled identically
        Case SELECT_RECT, SELECT_CIRC, SELECT_LINE, SELECT_LASSO
        
            'If a selection was being drawn, lock it into place
            If pdImages(g_CurrentImage).IsSelectionActive Then
                
                'Check to see if this mouse location is the same as the initial mouse press. If it is, and that particular
                ' point falls outside the selection, clear the selection from the image.
                Dim selBounds As RECTF
                selBounds = pdImages(g_CurrentImage).mainSelection.GetCornersLockedRect
                
                eraseThisSelection = ((clickEventAlsoFiring) And (IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage)) = -1))
                If (Not eraseThisSelection) Then eraseThisSelection = ((selBounds.Width <= 0) And (selBounds.Height <= 0))
                
                If eraseThisSelection Then
                    Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                    
                'The mouse is being released after a significant move event, or on a point of interest to the current selection.
                Else
                
                    'If the selection is not raster-type, pass these final mouse coordinates to it
                    If (pdImages(g_CurrentImage).mainSelection.GetSelectionShape <> ss_Raster) Then
                        pdImages(g_CurrentImage).mainSelection.RequestSquare (Shift And vbShiftMask)
                        pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                        SyncTextToCurrentSelection g_CurrentImage
                    End If
                
                    'Check to see if all selection coordinates are invalid (e.g. off-image).  If they are, forget about this selection.
                    If pdImages(g_CurrentImage).mainSelection.AreAllCoordinatesInvalid Then
                        Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                    Else
                        
                        'Depending on the type of transformation that may or may not have been applied, call the appropriate processor function.
                        ' This is required to add the current selection event to the Undo/Redo chain.
                        If (g_CurrentTool = SELECT_LASSO) Then
                        
                            'Creating a new selection
                            If (pdImages(g_CurrentImage).mainSelection.GetActiveSelectionPOI = poi_Undefined) Then
                                Process "Create selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            
                            'Moving an existing selection
                            Else
                                Process "Move selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            End If
                        
                        'All other selection types use identical transform identifiers
                        Else
                        
                            Dim transformType As PD_PointOfInterest
                            transformType = pdImages(g_CurrentImage).mainSelection.GetActiveSelectionPOI
                            
                            'Creating a new selection
                            If (transformType = poi_Undefined) Then
                                Process "Create selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            
                            'Moving an existing selection
                            ElseIf (transformType = 8) Then
                                Process "Move selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                                
                            'Anything else is assumed to be resizing an existing selection
                            Else
                                Process "Resize selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                                        
                            End If
                        
                        End If
                        
                    End If
                    
                End If
                
                'Creating a brand new selection always necessitates a redraw of the current canvas
                Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
                
            'If the selection is not active, make sure it stays that way
            Else
                pdImages(g_CurrentImage).mainSelection.LockRelease
            End If
            
            'Synchronize the selection text box values with the final selection
            Selections.SyncTextToCurrentSelection g_CurrentImage
            
        
        'As usual, polygon selections have some special considerations.
        Case SELECT_POLYGON
        
            'If a selection was being drawn, lock it into place
            If pdImages(g_CurrentImage).IsSelectionActive Then
            
                'Check to see if the selection is already locked in.  If it is, we need to check for an "erase selection" click.
                eraseThisSelection = pdImages(g_CurrentImage).mainSelection.GetPolygonClosedState And clickEventAlsoFiring
                eraseThisSelection = eraseThisSelection And (IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage)) = -1)
                
                If eraseThisSelection Then
                    Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                
                Else
                    
                    'If the polygon is already closed, we want to lock in the newly modified polygon
                    If pdImages(g_CurrentImage).mainSelection.GetPolygonClosedState Then
                        
                        'Polygons use a different transform numbering convention than other selection tools, because the number
                        ' of points involved aren't fixed.
                        Dim polyPoint As Long
                        polyPoint = Selections.IsCoordSelectionPOI(imgX, imgY, pdImages(g_CurrentImage))
                        
                        'Move selection
                        If (polyPoint = pdImages(g_CurrentImage).mainSelection.GetNumOfPolygonPoints) Then
                            Process "Move selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                        
                        'Create OR resize, depending on whether the initial point is being clicked for the first time, or whether
                        ' it's being click-moved
                        ElseIf (polyPoint = 0) Then
                            If clickEventAlsoFiring Then
                                Process "Create selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            Else
                                Process "Resize selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            End If
                                
                        'No point of interest means this click lies off-image; this could be a "clear selection" event (if a Click
                        ' event is also firing), or a "move polygon point" event (if the user dragged a point off-image).
                        ElseIf (polyPoint = -1) Then
                            
                            'If the user has clicked a blank spot unrelated to the selection, we want to remove the active selection
                            If clickEventAlsoFiring Then
                                Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                                
                            'If they haven't clicked, this could simply indicate that they dragged a polygon point off the polygon
                            ' and into some new region of the image.
                            Else
                                pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                                Process "Resize selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                            End If
                            
                        'Anything else is a resize
                        Else
                            Process "Resize selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                        End If
                        
                        'After all that work, we want to perform one final check to see if all selection coordinates are invalid
                        ' (e.g. if they all lie off-image, which can happen if the user drags all polygon points off-image).
                        ' If they are, we're going to erase this selection, as it's invalid.
                        eraseThisSelection = pdImages(g_CurrentImage).mainSelection.IsLockedIn And pdImages(g_CurrentImage).mainSelection.AreAllCoordinatesInvalid
                        If eraseThisSelection Then Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                        
                    'If the polygon is *not* closed, we want to add this as a new polygon point
                    Else
                    
                        'Pass these final mouse coordinates to the selection engine
                        pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                        
                        'To spare the debug logger from receiving too many events, forcibly prevent logging of this message
                        ' while in debug mode.
                        If (Not wasSelectionActiveBeforeMouseEvents) Then
                            #If DEBUGMODE = 1 Then
                                Message "Click on the first point to complete the polygon selection", "DONOTLOG"
                            #Else
                                Message "Click on the first point to complete the polygon selection"
                            #End If
                        End If
                        
                    End If
                
                'End erase vs create check
                End If
                
                'After all selection settings have been applied, forcibly redraw the source canvas
                Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
            
            '(Failsafe check) - if a selection is not active, make sure it stays that way
            Else
                pdImages(g_CurrentImage).mainSelection.LockRelease
            End If
            
        'Magic wand selections are actually the easiest to handle, as they don't really support post-creation transforms
        Case SELECT_WAND
            
            'Failsafe check for active selections
            If pdImages(g_CurrentImage).IsSelectionActive Then
                
                'Supply the final coordinates to the selection engine (as the user may be dragging around the active point)
                pdImages(g_CurrentImage).mainSelection.SetAdditionalCoordinates imgX, imgY
                
                'Check to see if all selection coordinates are invalid (e.g. off-image).
                ' - If they are, forget about this selection.
                ' - If they are not, commit this selection permanently
                eraseThisSelection = pdImages(g_CurrentImage).mainSelection.AreAllCoordinatesInvalid
                If eraseThisSelection Then
                    Process "Remove selection", , , IIf(wasSelectionActiveBeforeMouseEvents, UNDO_SELECTION, UNDO_NOTHING), g_CurrentTool
                Else
                    Process "Create selection", , pdImages(g_CurrentImage).mainSelection.GetSelectionAsXML, UNDO_SELECTION, g_CurrentTool
                End If
                
                'Force a redraw of the screen
                Viewport_Engine.Stage4_CompositeCanvas pdImages(g_CurrentImage), srcCanvas
                
            'Failsafe check for inactive selections
            Else
                pdImages(g_CurrentImage).mainSelection.LockRelease
            End If
            
    End Select
    
End Sub
