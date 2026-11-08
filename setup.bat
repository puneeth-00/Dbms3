@echo off
echo ===================================================
echo   EduVerify - DBMS Project Setup
echo ===================================================
echo.

echo [1/3] Checking Node.js dependencies...
call npm install

echo.
echo [2/3] Initializing PostgreSQL Database (schema, triggers, procedures, seed data)...
call npm run init-db

echo.
echo [3/3] Setup complete!
echo To launch the application, run: npm start
echo or double click start.bat
echo ===================================================
pause
