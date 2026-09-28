@echo off
rem ============================================================
rem  SECRET FOLDER 설치 관리자
rem  이 파일을 더블클릭하면 설치/삭제 창이 열립니다.
rem ============================================================
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0SecretFolder-Setup.ps1"
