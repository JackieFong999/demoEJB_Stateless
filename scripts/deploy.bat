@echo off
REM ---------------------------------------------------------------------------
REM Builds the WAR and hot-deploys it into JBoss EAP 8.0, then verifies the
REM endpoint with curl. The server (start-server.bat) must be running.
REM ---------------------------------------------------------------------------
setlocal
set "JAVA_HOME=C:\Program Files\Java\jdk-17.0.18"
set "MAVEN_HOME=D:\APPS_EJB_20261119\tools\apache-maven-3.9.16"
set "DEPLOY=D:\Download\jboss-eap-8.0.0\jboss-eap-8.0\standalone\deployments"
set "URL=http://localhost:8080/demoEJB-Stateless/api/checkout?price=100"

cd /d "%~dp0.."

echo === Building ===
call "%MAVEN_HOME%\bin\mvn.cmd" -B -ntp clean package
if errorlevel 1 (
    echo [ERROR] build failed
    exit /b 1
)

echo.
echo === Deploying to %DEPLOY% ===
REM Do NOT delete the .deployed marker: the scanner treats marker removal as an
REM undeploy command. Instead let the scanner see the changed WAR (scan-interval
REM is 5s), then wait for real content.
copy /y "target\demoEJB-Stateless.war" "%DEPLOY%\" >nul
if errorlevel 1 (
    echo [ERROR] copy failed - is the server running?
    exit /b 1
)

echo Waiting for the deployment scanner ...
REM 7s delay without depending on a console: `ping -n 8` = 7 waits ~1s apart.
REM (timeout.exe fails when stdin is redirected, GNU timeout from git-bash rejects /t.)
ping -n 8 127.0.0.1 >nul

:test
echo.
echo === Smoke test: %URL% ===
REM The .deployed marker appears before the web context is re-registered; in that
REM ~1s gap JBoss answers HTTP 200 with an EMPTY body. So poll for real content.
set "BODY="
for /L %%i in (1,1,30) do (
    for /f "delims=" %%b in ('curl -s "%URL%"') do set "BODY=%%b"
    if defined BODY goto :got
    ping -n 2 127.0.0.1 >nul
)
:got
echo %BODY%
if not defined BODY echo [WARN] no response body after 30s - check server.log
echo.
echo Open http://localhost:8080/demoEJB-Stateless/ for the UI.
