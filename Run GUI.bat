cd /d %~dp0
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "GUI.ps1"
