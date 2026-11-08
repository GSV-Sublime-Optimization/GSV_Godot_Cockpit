@echo off
rem One unattended dispatcher pass (reconcile, then assign --max 3 --bridge). NOT registered by default.
rem To run it every 30 minutes as the logged-on user (who holds the gh login and the xanadu SSH key):
rem   schtasks /Create /TN "GSV\colony-autodispatch" /SC MINUTE /MO 30 /TR "C:\Users\Public\colony\mindview\autodispatch.cmd" /RL LIMITED /F
rem To stop it:   schtasks /Delete /TN "GSV\colony-autodispatch" /F
rem To run once:  schtasks /Run /TN "GSV\colony-autodispatch"
setlocal
set PYTHONIOENCODING=utf-8
set PY=C:\Users\ekene\AppData\Local\Python\pythoncore-3.14-64\python.exe
set HERE=%~dp0
"%PY%" "%HERE%autodispatch.py" >> "%HERE%autodispatch.log" 2>&1
exit /b %ERRORLEVEL%
