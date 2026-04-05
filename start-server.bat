@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo Запуск backend (порт 3001)...
echo Остановка: Ctrl+C
echo.

call npm run dev -w server

echo.
pause
