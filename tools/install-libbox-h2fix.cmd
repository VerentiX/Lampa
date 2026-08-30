@echo off
REM Replace locked libbox.aar after closing Android Studio (or File sync).
set LIBS=%~dp0..\android\app\libs
if not exist "%LIBS%\libbox.aar.new" if not exist "%LIBS%\libbox-h2fix.aar" (
  echo Missing libbox.aar.new / libbox-h2fix.aar
  exit /b 1
)
if exist "%LIBS%\libbox.aar.new" (
  copy /Y "%LIBS%\libbox.aar.new" "%LIBS%\libbox.aar"
) else (
  copy /Y "%LIBS%\libbox-h2fix.aar" "%LIBS%\libbox.aar"
)
echo OK: %LIBS%\libbox.aar
dir "%LIBS%\libbox.aar"
