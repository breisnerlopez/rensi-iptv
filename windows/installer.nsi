; NSIS Installer Script for Rensi IPTV
; This script creates a Windows installer that installs the application
; to Program Files and creates shortcuts.

;--------------------------------
; Includes

; Internal Flutter binary name (set in windows/CMakeLists.txt). Keeping it
; stable avoids touching the C++/CMake bits — only the user-facing strings
; change with the rebrand.
!define APP_EXE "iptv_player.exe"

!include "MUI2.nsh"
!include "FileFunc.nsh"

;--------------------------------
; General

Name "Rensi IPTV"
OutFile "rensi-iptv-windows-setup.exe"
Unicode True

InstallDir "$PROGRAMFILES64\Rensi IPTV"

InstallDirRegKey HKCU "Software\Rensi IPTV" ""

RequestExecutionLevel admin

; Version information
VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "Rensi IPTV"
VIAddVersionKey "Comments" "A modern IPTV player application"
VIAddVersionKey "CompanyName" "Rensi IPTV"
VIAddVersionKey "LegalCopyright" "Copyright © 2026 Breisner López"
VIAddVersionKey "FileDescription" "Rensi IPTV Installer"
VIAddVersionKey "FileVersion" "1.0.0.0"
VIAddVersionKey "ProductVersion" "1.0.0.0"

;--------------------------------
; Interface Settings

!define MUI_ABORTWARNING
!define MUI_ICON "${NSISDIR}\Contrib\Graphics\Icons\modern-install.ico"
!define MUI_UNICON "${NSISDIR}\Contrib\Graphics\Icons\modern-uninstall.ico"

;--------------------------------
; Pages

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_LICENSE "license.txt"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------
; Languages

!insertmacro MUI_LANGUAGE "English"

;--------------------------------
; Installer Sections

Section "Rensi IPTV" SecMain

  SectionIn RO

  SetOutPath "$INSTDIR"

  ; Copy all files from the build directory. In CI we are in windows/ so the
  ; build folder lives one level up. The .pdb and any previously generated
  ; installer artifacts are excluded.
  File /r /x "*.pdb" /x "rensi-iptv-windows-*" "..\build\windows\x64\runner\Release\*"

  WriteRegStr HKCU "Software\Rensi IPTV" "" $INSTDIR

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "DisplayName" "Rensi IPTV"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "DisplayIcon" "$INSTDIR\${APP_EXE}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "Publisher" "Rensi IPTV"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                   "DisplayVersion" "1.0.0"
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                     "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV" \
                     "NoRepair" 1

SectionEnd

Section "Start Menu Shortcuts" SecStartMenu

  CreateDirectory "$SMPROGRAMS\Rensi IPTV"
  CreateShortcut "$SMPROGRAMS\Rensi IPTV\Rensi IPTV.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0
  CreateShortcut "$SMPROGRAMS\Rensi IPTV\Uninstall.lnk" "$INSTDIR\Uninstall.exe"

SectionEnd

Section "Desktop Shortcut" SecDesktop

  CreateShortcut "$DESKTOP\Rensi IPTV.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${APP_EXE}" 0

SectionEnd

;--------------------------------
; Descriptions

LangString DESC_SecMain ${LANG_ENGLISH} "Install Rensi IPTV application files."
LangString DESC_SecStartMenu ${LANG_ENGLISH} "Create Start Menu shortcuts."
LangString DESC_SecDesktop ${LANG_ENGLISH} "Create a desktop shortcut."

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} $(DESC_SecMain)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} $(DESC_SecStartMenu)
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} $(DESC_SecDesktop)
!insertmacro MUI_FUNCTION_DESCRIPTION_END

;--------------------------------
; Uninstaller Section

Section "Uninstall"

  Delete "$INSTDIR\Uninstall.exe"
  RMDir /r "$INSTDIR"

  Delete "$SMPROGRAMS\Rensi IPTV\Rensi IPTV.lnk"
  Delete "$SMPROGRAMS\Rensi IPTV\Uninstall.lnk"
  RMDir "$SMPROGRAMS\Rensi IPTV"
  Delete "$DESKTOP\Rensi IPTV.lnk"

  DeleteRegKey /ifempty HKCU "Software\Rensi IPTV"
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Rensi IPTV"

SectionEnd
