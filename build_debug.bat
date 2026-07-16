@echo off
setlocal

echo Building Nova Assistant debug APK...
flutter build apk --debug --no-tree-shake-icons

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo APK location: build\app\outputs\flutter-apk\app-debug.apk
) else (
    echo.
    echo Build failed with error code %ERRORLEVEL%
)

endlocal
