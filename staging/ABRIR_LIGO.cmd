@echo off
cd /d "%~dp0.."
node tool/ligo/start-local.mjs
if errorlevel 1 pause
