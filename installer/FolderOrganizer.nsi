Unicode true
!include "MUI2.nsh"

Name "Folder Organizer"
OutFile "${SETUP_OUTPUT}"
InstallDir "$LOCALAPPDATA\Programs\Folder Organizer"
RequestExecutionLevel user
SetCompressor /SOLID lzma
VIProductVersion "${APP_VERSION}.0"
VIAddVersionKey "ProductName" "Folder Organizer"
VIAddVersionKey "FileDescription" "Folder Organizer Setup"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright 2026 Mahmodul Hasan Santo"

!define MUI_ABORTWARNING
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section "Folder Organizer" Main
    SetShellVarContext current
    SetOutPath "$INSTDIR"
    File "/oname=Folder Organizer.exe" "${APP_EXE}"
    WriteUninstaller "$INSTDIR\Uninstall.exe"
    CreateDirectory "$SMPROGRAMS\Folder Organizer"
    CreateShortcut "$SMPROGRAMS\Folder Organizer\Organize Desktop.lnk" "$INSTDIR\Folder Organizer.exe"
    CreateShortcut "$SMPROGRAMS\Folder Organizer\Organize Downloads.lnk" "$INSTDIR\Folder Organizer.exe" "--downloads"
    CreateShortcut "$SMPROGRAMS\Folder Organizer\Undo Desktop Sort.lnk" "$INSTDIR\Folder Organizer.exe" "--undo"
    CreateShortcut "$SMPROGRAMS\Folder Organizer\Undo Downloads Sort.lnk" "$INSTDIR\Folder Organizer.exe" "--downloads --undo"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "DisplayName" "Folder Organizer"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "DisplayVersion" "${APP_VERSION}"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "Publisher" "mhsanto"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "InstallLocation" "$INSTDIR"
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "UninstallString" '$\"$INSTDIR\Uninstall.exe$\"'
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "NoModify" 1
    WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer" "NoRepair" 1
SectionEnd

Section "Uninstall"
    SetShellVarContext current
    Delete "$SMPROGRAMS\Folder Organizer\Organize Desktop.lnk"
    Delete "$SMPROGRAMS\Folder Organizer\Organize Downloads.lnk"
    Delete "$SMPROGRAMS\Folder Organizer\Undo Desktop Sort.lnk"
    Delete "$SMPROGRAMS\Folder Organizer\Undo Downloads Sort.lnk"
    RMDir "$SMPROGRAMS\Folder Organizer"
    Delete "$INSTDIR\Folder Organizer.exe"
    Delete "$INSTDIR\Uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\mhsanto.FolderOrganizer"
SectionEnd
