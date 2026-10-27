; Nashi per-user Windows installer (NSIS).
;
; Build from the repository root:
;   makensis /DNASHI_VERSION=0.7.10 windows/installer/windows-setup.nsi
; Optional defines:
;   /DNASHI_PAYLOAD=build/windows/Nashi   published dotnet output (default)
;   /DNASHI_OUT=build/Nashi-Setup.exe     override the output file
;
; Installs per-user into %LOCALAPPDATA%\Programs\Nashi without administrator
; rights, registers the Applications uninstall entry under HKCU and marks the
; install with HKCU\Software\Nashi\InstallMode=setup so the in-app updater
; reruns Setup instead of the portable folder swap. User data under
; %LOCALAPPDATA%\Nashi is never read or removed by this installer.

Unicode true
ManifestDPIAware true
RequestExecutionLevel user
SetCompressor /SOLID lzma

!define AppName "Nashi"
!define Publisher "orkunisitmak"
!define Homepage "https://github.com/orkunisitmak/nashi-app"
!define RegPath "Software\Nashi"
!define UnregPath "Software\Microsoft\Windows\CurrentVersion\Uninstall\Nashi"

!ifndef NASHI_VERSION
  !define NASHI_VERSION "0.0.0"
!endif
!ifndef NASHI_PAYLOAD
  !define NASHI_PAYLOAD "build\windows\Nashi"
!endif
!ifndef NASHI_OUT
  !define NASHI_OUT "build\Nashi-Setup-${NASHI_VERSION}-x64.exe"
!endif

Name "${AppName} ${NASHI_VERSION}"
BrandingText "${Homepage}"
OutFile "${NASHI_OUT}"
InstallDir "$LOCALAPPDATA\Programs\Nashi"
InstallDirRegKey HKCU "${RegPath}" InstallPath
VIProductVersion "${NASHI_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "${AppName}"
VIAddVersionKey /LANG=1033 "FileVersion" "${NASHI_VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductVersion" "${NASHI_VERSION}"
VIAddVersionKey /LANG=1033 "Publisher" "${Publisher}"
VIAddVersionKey /LANG=1033 "LegalCopyright" "MIT License"

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\Nashi.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Nashi"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Turkish"

Section "${AppName} application" SecApp
  SectionIn RO
  SetShellVarContext current
  Call CloseRunningApp
  Call CleanPreviousInstall
  SetOutPath "$INSTDIR"
  File /r /x "*.pdb" "${NASHI_PAYLOAD}\*.*"
  WriteUninstaller "$INSTDIR\uninst.exe"
  WriteRegStr HKCU "${RegPath}" "InstallMode" "setup"
  WriteRegStr HKCU "${RegPath}" "InstallPath" "$INSTDIR"
  WriteRegStr HKCU "${UnregPath}" "DisplayName" "${AppName}"
  WriteRegStr HKCU "${UnregPath}" "DisplayVersion" "${NASHI_VERSION}"
  WriteRegStr HKCU "${UnregPath}" "Publisher" "${Publisher}"
  WriteRegStr HKCU "${UnregPath}" "DisplayIcon" "$INSTDIR\Nashi.exe"
  WriteRegStr HKCU "${UnregPath}" "UninstallString" '"$INSTDIR\uninst.exe"'
  WriteRegStr HKCU "${UnregPath}" "QuietUninstallString" '"$INSTDIR\uninst.exe" /S'
  WriteRegStr HKCU "${UnregPath}" "URLInfoAbout" "${Homepage}"
  WriteRegDWORD HKCU "${UnregPath}" "NoModify" 1
  WriteRegDWORD HKCU "${UnregPath}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UnregPath}" "EstimatedSize" $0
  CreateShortcut "$SMPROGRAMS\${AppName}.lnk" "$INSTDIR\Nashi.exe"
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  SetShellVarContext current
  CreateShortcut "$DESKTOP\${AppName}.lnk" "$INSTDIR\Nashi.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Call un.CloseRunningApp
  Delete "$SMPROGRAMS\${AppName}.lnk"
  Delete "$DESKTOP\${AppName}.lnk"
  RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UnregPath}"
  DeleteRegKey HKCU "${RegPath}"
  ; User data under %LOCALAPPDATA%\Nashi (Library, imports, preferences) is
  ; intentionally preserved across uninstall.
SectionEnd

; A running Nashi locks its files. Renaming the executable can only succeed
; once the process has exited, so the rename doubles as the exit wait.
Function CloseRunningApp
  ${IfNot} ${FileExists} "$INSTDIR\Nashi.exe"
    Return
  ${EndIf}
  Push $0
  StrCpy $0 0
  ${Do}
    ClearErrors
    Rename "$INSTDIR\Nashi.exe" "$INSTDIR\Nashi.exe.retired"
    ${IfNot} ${Errors}
      Pop $0
      Return
    ${EndIf}
    Sleep 500
    IntOp $0 $0 + 1
    ${If} $0 > 120
      ${If} ${Silent}
        SetErrorLevel 3
        Quit
      ${Else}
        MessageBox MB_ICONEXCLAMATION "Nashi is still running. Close it and try again."
        Abort
      ${EndIf}
    ${EndIf}
  ${Loop}
FunctionEnd

; Only wipe a folder that is recognizably a previous Nashi install, so a
; user-chosen directory that contains unrelated files is never cleared.
Function CleanPreviousInstall
  ${If} ${FileExists} "$INSTDIR\Nashi.exe.retired"
  ${OrIf} ${FileExists} "$INSTDIR\Nashi.exe"
  ${OrIf} ${FileExists} "$INSTDIR\uninst.exe"
    RMDir /r "$INSTDIR"
  ${EndIf}
FunctionEnd

; Silent installs relaunch Nashi unless /nolaunch is passed; the in-app
; updater relies on this to reopen the app after a silent update.
Function .onInstSuccess
  ${If} ${Silent}
    ${IfNot} ${FileExists} "$INSTDIR\Nashi.exe"
      Return
    ${EndIf}
    ${GetOptions} $CMDLINE "/nolaunch" $R0
    ${IfNot} ${Errors}
      Return
    ${EndIf}
    Exec '"$INSTDIR\Nashi.exe"'
  ${EndIf}
FunctionEnd

; The uninstaller must also close a running Nashi before removing files.
Function un.CloseRunningApp
  ${IfNot} ${FileExists} "$INSTDIR\Nashi.exe"
    Return
  ${EndIf}
  Push $0
  StrCpy $0 0
  ${Do}
    ClearErrors
    Rename "$INSTDIR\Nashi.exe" "$INSTDIR\Nashi.exe.retired"
    ${IfNot} ${Errors}
      Pop $0
      Return
    ${EndIf}
    Sleep 500
    IntOp $0 $0 + 1
    ${If} $0 > 120
      MessageBox MB_ICONEXCLAMATION "Nashi is still running. Close it and try again."
      Abort
    ${EndIf}
  ${Loop}
FunctionEnd
