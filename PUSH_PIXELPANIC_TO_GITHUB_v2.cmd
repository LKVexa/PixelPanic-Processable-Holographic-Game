@echo off
setlocal EnableExtensions EnableDelayedExpansion
title Pixel Panic - Push to GitHub

rem ============================================================
rem Pixel Panic Processable Holographic Game
rem Repository publisher for:
rem https://github.com/LKVexa/PixelPanic-Processable-Holographic-Game
rem
rem This revision:
rem   - configures Git author identity LOCALLY for this repo
rem   - does not modify global Git identity
rem   - adds explicit line-ending rules
rem   - safely resumes an already initialized/staged repository
rem ============================================================

cd /d "%~dp0" || (
    echo ERROR: Could not enter repository directory.
    pause
    exit /b 1
)

set "REPO_URL=https://github.com/LKVexa/PixelPanic-Processable-Holographic-Game.git"
set "BRANCH=main"

echo.
echo ============================================================
echo Pixel Panic - GitHub Publisher
echo ============================================================
echo Local repository:
echo   %CD%
echo.
echo GitHub repository:
echo   %REPO_URL%
echo.

where git >nul 2>&1
if errorlevel 1 (
    echo ERROR: Git for Windows was not found in PATH.
    echo Install Git for Windows and try again.
    echo https://git-scm.com/download/win
    pause
    exit /b 2
)

git --version
if errorlevel 1 goto :fail

rem ------------------------------------------------------------
rem Repository-local author identity.
rem Do NOT change global Git settings.
rem ------------------------------------------------------------
set "GIT_NAME="
for /f "delims=" %%A in ('git config --local user.name 2^>nul') do set "GIT_NAME=%%A"

if not defined GIT_NAME (
    echo.
    set /p "GIT_NAME=Git author name [LKVexa]: "
    if not defined GIT_NAME set "GIT_NAME=LKVexa"
    git config --local user.name "!GIT_NAME!"
    if errorlevel 1 goto :fail
)

set "GIT_EMAIL="
for /f "delims=" %%A in ('git config --local user.email 2^>nul') do set "GIT_EMAIL=%%A"

if not defined GIT_EMAIL (
    echo.
    echo Git requires an author email for commits.
    echo You may use:
    echo   - the email associated with your GitHub account, or
    echo   - your GitHub no-reply email if you prefer not to publish a personal address.
    echo.
    set /p "GIT_EMAIL=Git author email: "
    if not defined GIT_EMAIL (
        echo ERROR: An author email is required.
        goto :fail
    )
    git config --local user.email "!GIT_EMAIL!"
    if errorlevel 1 goto :fail
)

echo.
echo Repository-local Git identity:
echo   Name : !GIT_NAME!
echo   Email: !GIT_EMAIL!
echo.

rem ------------------------------------------------------------
rem Explicit line-ending and binary rules.
rem This prevents Git from treating TIFF/GIF cartridges as text and
rem keeps Windows launch scripts in CRLF form.
rem ------------------------------------------------------------
> ".gitattributes" (
    echo * text=auto
    echo.
    echo *.cmd text eol=crlf
    echo *.bat text eol=crlf
    echo *.ps1 text eol=crlf
    echo *.cs text eol=crlf
    echo *.txt text eol=crlf
    echo.
    echo *.md text eol=lf
    echo *.json text eol=lf
    echo *.yml text eol=lf
    echo *.yaml text eol=lf
    echo.
    echo *.tif binary
    echo *.tiff binary
    echo *.gif binary
    echo *.png binary
    echo *.jpg binary
    echo *.jpeg binary
    echo *.dll binary
    echo *.exe binary
    echo *.wasm binary
    echo *.bin binary
)

rem ------------------------------------------------------------
rem Protect machine-local/generated files from accidental upload.
rem ------------------------------------------------------------
if not exist ".gitignore" (
    >".gitignore" echo # Pixel Panic local/generated exclusions
)

findstr /x /c:"# BEGIN PIXEL PANIC LOCAL EXCLUDES" ".gitignore" >nul 2>&1
if errorlevel 1 (
    >>".gitignore" echo.
    >>".gitignore" echo # BEGIN PIXEL PANIC LOCAL EXCLUDES
    >>".gitignore" echo runtime/webview2-sdk/
    >>".gitignore" echo runtime/cache/
    >>".gitignore" echo workspace/
    >>".gitignore" echo saves/
    >>".gitignore" echo native/bin/
    >>".gitignore" echo native/obj/
    >>".gitignore" echo .vs/
    >>".gitignore" echo *.user
    >>".gitignore" echo *.tmp
    >>".gitignore" echo *.log
    >>".gitignore" echo # END PIXEL PANIC LOCAL EXCLUDES
)

if not exist ".git" (
    echo Initializing Git repository...
    git init
    if errorlevel 1 goto :fail

    rem Reapply local identity because git init was just created.
    git config --local user.name "!GIT_NAME!"
    git config --local user.email "!GIT_EMAIL!"
)

echo Setting branch to %BRANCH%...
git branch -M %BRANCH%
if errorlevel 1 goto :fail

git remote get-url origin >nul 2>&1
if errorlevel 1 (
    echo Adding GitHub origin...
    git remote add origin "%REPO_URL%"
    if errorlevel 1 goto :fail
) else (
    echo Setting GitHub origin...
    git remote set-url origin "%REPO_URL%"
    if errorlevel 1 goto :fail
)

echo.
echo Remote configuration:
git remote -v
echo.

echo Restaging repository files using the explicit line-ending rules...
git add --renormalize .
git add -A
if errorlevel 1 goto :fail

echo.
echo Files staged for commit:
git status --short
echo.

git diff --cached --quiet
if errorlevel 1 (
    set "COMMIT_MESSAGE="
    set /p "COMMIT_MESSAGE=Commit message [Pixel Panic Hologram release]: "
    if not defined COMMIT_MESSAGE set "COMMIT_MESSAGE=Pixel Panic Hologram release"

    echo.
    echo Creating commit...
    git commit -m "!COMMIT_MESSAGE!"
    if errorlevel 1 goto :commitfail
) else (
    echo No new changes to commit.
)

echo.
echo Pushing %BRANCH% to GitHub...
git push -u origin %BRANCH%
if errorlevel 1 (
    echo.
    echo ERROR: GitHub push failed.
    echo.
    echo Common causes:
    echo   - Git Credential Manager needs you to sign in.
    echo   - The remote contains commits not present locally.
    echo   - A security product blocked Git.
    echo.
    echo Current remote:
    git remote -v
    goto :fail
)

echo.
echo ============================================================
echo SUCCESS
echo Pixel Panic was pushed to:
echo https://github.com/LKVexa/PixelPanic-Processable-Holographic-Game
echo ============================================================
echo.
pause
exit /b 0

:commitfail
echo.
echo ERROR: Git commit failed.
echo.
echo Current repository-local identity:
git config --local --get user.name
git config --local --get user.email
echo.
goto :fail

:fail
echo.
echo ============================================================
echo PUSH DID NOT COMPLETE
echo No project files were deleted.
echo ============================================================
echo.
pause
exit /b 10
