@echo off
REM ---------------------------------------------------------------------------
REM Starts JBoss EAP 8.0 standalone (Jakarta EE 10).
REM The machine-wide JAVA_HOME points at JDK 8, which EAP 8 refuses to run on,
REM so JAVA_HOME is overridden here. Keep this window open while you work.
REM ---------------------------------------------------------------------------
setlocal
set "JAVA_HOME=C:\Program Files\Java\jdk-17.0.18"
set "JBOSS_HOME=D:\Download\jboss-eap-8.0.0\jboss-eap-8.0"

if not exist "%JAVA_HOME%\bin\java.exe" (
    echo [ERROR] JDK 17 not found at "%JAVA_HOME%"
    exit /b 1
)
if not exist "%JBOSS_HOME%\bin\standalone.bat" (
    echo [ERROR] JBoss EAP not found at "%JBOSS_HOME%"
    exit /b 1
)

echo Starting JBoss EAP 8.0 with JDK 17 ...
echo   http://localhost:8080/     (after deploy: /demoEJB-Stateless/)
echo   log: %JBOSS_HOME%\standalone\log\server.log
echo.
call "%JBOSS_HOME%\bin\standalone.bat" %*
