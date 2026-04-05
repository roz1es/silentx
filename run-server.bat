@echo off
cd /d %~dp0server
set "NODE_ENV=production"
node dist\index.js
lt --port 3001
pause