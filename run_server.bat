@echo off
rem =========================================================================
rem  Faraon - multiplayer server (Windows, dev/test)
rem  Pouzitie:  run_server.bat [port]      (default port 9000)
rem  Klienti sa pripoja na  ws://IP-tohto-PC:port  (menu Hrat online -> dev).
rem  Podrobny navod: SERVER_SETUP.md
rem =========================================================================
setlocal
set PORT=%1
if "%PORT%"=="" set PORT=9000

rem Cesta ku Godot konzolovemu exe - uprav ak mas Godot inde,
rem alebo nastav premennu prostredia GODOT_EXE.
if "%GODOT_EXE%"=="" set GODOT_EXE=C:\Users\simon\Downloads\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe

if not exist "%GODOT_EXE%" (
    echo CHYBA: Godot exe nenajdeny: %GODOT_EXE%
    echo Nastav GODOT_EXE alebo uprav cestu v tomto skripte.
    exit /b 1
)

echo Spustam Faraon server na porte %PORT% ... (ukoncenie: Ctrl+C)
"%GODOT_EXE%" --headless --path "%~dp0." -- --server --port=%PORT%
