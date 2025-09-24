@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Add Defender Exclusion (AppData + Fallback)

:: ------- Target (default = current user's AppData) -------
if "%~1"=="" ( set "TARGET=%USERPROFILE%\AppData" ) else ( set "TARGET=%~1" )

:: ------- Elevate (UAC) -------
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator privileges...
  powershell -NoProfile -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -ArgumentList @('%TARGET%') -Verb RunAs"
  exit /b
)

:: ------- Setup log on Desktop -------
set "LOG=%USERPROFILE%\Desktop\Defender_AddExclusion.log"
del "%LOG%" >nul 2>&1
call :log "=== Defender Exclusion Add %date% %time% ==="
call :log "Target: %TARGET%"
echo.

:: ------- Ensure target exists -------
if not exist "%TARGET%" (
  mkdir "%TARGET%" >nul 2>&1
  if exist "%TARGET%" ( call :log "Created folder: %TARGET%" ) else (
    call :log "ERROR: Folder does not exist and could not be created: %TARGET%"
    goto :done
  )
)

:: ------- Tamper Protection status (blocks scripts when True) -------
for /f "usebackq tokens=*" %%I in (`powershell -NoProfile -Command "(Get-MpComputerStatus).IsTamperProtected 2^>^$null"`) do set "TP=%%I"
if defined TP call :log "IsTamperProtected: %TP%"
if /I "%TP%"=="True" (
  call :log "Tamper Protection is ON -> scripted changes are blocked."
  start "" windowsdefender://exclusions
  echo.
  echo Tamper Protection is ON. Turn it OFF temporarily, then run this .bat again.
  goto :done
)

:: ------- Common policy lock (DisableLocalAdminMerge) -------
set "DLM=(not set)"
reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableLocalAdminMerge >nul 2>&1
if %errorlevel%==0 (
  for /f "tokens=3" %%V in ('reg query "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v DisableLocalAdminMerge ^| find /i "DisableLocalAdminMerge"') do set DLM=%%V
)
call :log "Policy DisableLocalAdminMerge: %DLM%"

:: ------- Try method #1: PowerShell Add-MpPreference -------
echo.
echo Trying PowerShell method...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Try { Add-MpPreference -ExclusionPath '%TARGET%' -ErrorAction Stop; Exit 0 } Catch { Write-Host $_.Exception.Message; Exit 1 }"
set "RC=%errorlevel%"
if "%RC%"=="0" (
  call :log "Add-MpPreference: SUCCESS"
  goto :verify
) else (
  call :log "Add-MpPreference: FAILED (code %RC%). Falling back to registry..."
)

:: ------- Method #2: Registry fallback -------
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /f >nul 2>&1
reg add "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" /v "%TARGET%" /t REG_DWORD /d 0 /f
set "RC=%errorlevel%"
if "%RC%"=="0" (
  call :log "Registry add: SUCCESS"
) else (
  call :log "Registry add: FAILED (code %RC%)"
  goto :done
)

:: ------- Verify (Defender list + registry) -------
:verify
echo.
echo Verifying...
powershell -NoProfile -Command "(Get-MpPreference).ExclusionPath 2>$null" | findstr /i /c:"%TARGET%" >nul
if %errorlevel%==0 (
  call :log "Verify via Get-MpPreference: FOUND"
) else (
  reg query "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths" | findstr /i /c:"%TARGET%" >nul
  if %errorlevel%==0 (
    call :log "Verify via registry: PRESENT (policy may ignore local list if DisableLocalAdminMerge=1)"
  ) else (
    call :log "Verify: NOT FOUND"
  )
)

:done
echo.
echo --- Summary (last lines) ---
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "Get-Content -Tail 14 -Path \"$env:USERPROFILE\Desktop\Defender_AddExclusion.log\" 2>$null"`) do echo %%L
echo.
if /I "%DLM%"=="0x1" (
  echo NOTE: A policy is blocking local exclusions (DisableLocalAdminMerge=1).
  echo Change via Group Policy / MDM to allow Local Admin Merge, then re-run.
  echo Path: Computer Config > Admin Templates > Windows Components > Microsoft Defender Antivirus
)
echo.
pause
exit /b

:log
echo %~1
>>"%LOG%" echo %~1
exit /b
