@echo off
setlocal

echo Building Nova Assistant release APK...
flutter build apk --release --no-tree-shake-icons

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful!
    echo APK location: build\app\outputs\flutter-apk\app-release.apk
) else (
    echo.
    echo Build failed with error code %ERRORLEVEL%
)

endlocal
