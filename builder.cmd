@echo off
SETLOCAL EnableDelayedExpansion
    

SET SCRIPT_DIR=%~dp0
SET GLOBAL_ENV_FILE=%SCRIPT_DIR%.env
SET PROJECTS_DIR=%SCRIPT_DIR%projects
SET BUILD_OUTPUT_BASE=%SCRIPT_DIR%
SET CHANGELOG_CMD=%SCRIPT_DIR%changelog.cmd
SET VERSION_CMD=%SCRIPT_DIR%createversion.cmd

IF EXIST %GLOBAL_ENV_FILE% (
    FOR /F "tokens=1,2 delims==" %%A IN (%GLOBAL_ENV_FILE%) DO (
        SET %%A=%%B
    )
)

IF NOT EXIST %BUILD_OUTPUT_BASE% (
    MKDIR %BUILD_OUTPUT_BASE%
)

FOR %%F IN (%PROJECTS_DIR%\*.env) DO (
    SET ENV_FILE=%%~fF
    echo Processing project: !ENV_FILE!

    FOR /F "tokens=1,2 delims==" %%A IN (!ENV_FILE!) DO (
        SET %%A=%%B
    )


    IF NOT DEFINED PROJECT_PATH (
        echo ERROR: PROJECT_PATH not defined in !ENV_FILE!
        EXIT /B 1
    )

    IF NOT DEFINED GIT_REPO_URL (
        echo ERROR: GIT_REPO_URL not defined in !ENV_FILE!
        EXIT /B 1
    )

    IF NOT DEFINED BIN_FOLDER (
        echo ERROR: BIN_FOLDER not defined in !ENV_FILE!
        EXIT /B 1
    )

    IF DEFINED SSH_PRIVATE_KEY (
        SET GIT_SSH_COMMAND=ssh -i "!SSH_PRIVATE_KEY!"
    )

    IF NOT EXIST "!PROJECT_PATH!" (
        echo PROJECT_PATH does not exist. Cloning repository...
        git clone !GIT_REPO_URL! "!PROJECT_PATH!"
        IF %ERRORLEVEL% NEQ 0 (
            echo ERROR: Failed to clone repository from !GIT_REPO_URL!
            EXIT /B 1
        )
    )

    cd /d !PROJECT_PATH!
    IF %ERRORLEVEL% NEQ 0 (
        echo ERROR: Invalid PROJECT_PATH in !ENV_FILE!
        EXIT /B 1
    )

    git fetch --all

    FOR /F "tokens=*" %%b IN ('git branch -r ^| findstr /v "HEAD"') DO (
        SET BRANCH=%%~nb
        SET BUILD_BRANCH=0
        SET BUILD_OUTDIR=release
        SET DEV=1

        IF "!BRANCH!" == "main" (
            SET DEV=0
        )

        IF "!BRANCH!" == "master" (
            SET DEV=0
        )

        IF !DEV! EQU 1 (
            SET BUILD_OUTDIR=testing
        )

        IF "!INCLUDE_BRANCH!" == "*" SET BUILD_BRANCH=1
        FOR %%i IN (!INCLUDE_BRANCH!) DO (
            IF "%%i" == "!BRANCH!" SET BUILD_BRANCH=1
        )

        FOR %%e IN (!EXCLUDE_BRANCH!) DO (
            IF "%%e" == "!BRANCH!" SET BUILD_BRANCH=0
        )

        IF !BUILD_BRANCH! EQU 0 (
            echo Skipping branch: !BRANCH!
        ) ELSE (
            git reset --hard
            git checkout !BRANCH! || git checkout -b !BRANCH! %%b

            CALL :GET_LAST_RELEASE

            git pull origin !BRANCH!
            SET NEW_HEAD=
            FOR /F "tokens=*" %%h IN ('git rev-parse HEAD') DO SET NEW_HEAD=%%h

            SET SKIPBUILD=0

            IF "!LAST_HEAD!" == "!NEW_HEAD!" (
                echo No new changes in branch: !BRANCH!
                SET SKIPBUILD=1
            )

            IF !SKIPBUILD! EQU 0 (
                echo Building !PROJECT_NAME! branch: !BRANCH!
                CALL :BUILD_MSVC
            )
        )
    )
)

EXIT /B /0

:GET_LAST_RELEASE

SET LAST_BASE=%BUILD_OUTPUT_BASE%\!BUILD_OUTDIR!\!PROJECT_NAME!
iF !DEV! EQU 1 (
    SET LAST_BASE=%BUILD_OUTPUT_BASE%\!BUILD_OUTDIR!\!PROJECT_NAME!\!BRANCH!
)

CALL :GET_LAST_OUTPUT_PATH
CALL :GET_LAST_HEAD
CALL :GET_LAST_BUILD_OUTPUT_PATH

:GET_LAST_HEAD
SET LAST_HEAD=

IF NOT DEFINED LAST_OUTPUT_PATH (
    EXIT /B 0
)

SET HEAD_FILE="!LAST_OUTPUT_PATH!\HEAD"

FOR /F "delims=" %%A IN ('TYPE !HEAD_FILE!') DO (
        CALL :TRIM_INPUT %%A LAST_HEAD
        EXIT /B 0
)
EXIT /B 0

:GET_LAST_OUTPUT_PATH
SET LAST_OUTPUT_PATH=

FOR /F "delims=" %%D IN ('DIR /B /AD /O-D "!LAST_BASE!\*"') DO (
    IF EXIST !LAST_BASE!\%%D\HEAD (
        SET LAST_OUTPUT_PATH=!LAST_BASE!\%%D
        EXIT /B 0
    )
)
EXIT /B 0

:GET_LAST_BUILD_OUTPUT_PATH
SET LAST_BUILD_OUTPUT_PATH=

FOR /F "delims=" %%D IN ('DIR /B /AD /O-D "!LAST_BASE!\*"') DO (
    IF EXIST !LAST_BASE!\%%D\version.txt (
        SET LAST_BUILD_OUTPUT_PATH=!LAST_BASE!\%%D
        EXIT /B 0
    )
)
EXIT /B 0



:SET_OUTPUT_PATH
SET BUILD_COUNT=1

FOR /f %%a in ('powershell -Command "Get-date -format yyMMdd"') do set DATE_TAG=%%a

FOR /L %%I IN (2,1,99) DO (
    SET CUR_VERSION=v!DATE_TAG!-!BUILD_COUNT!
    SET OUTPUT_PATH=%BUILD_OUTPUT_BASE%\!BUILD_OUTDIR!\!PROJECT_NAME!\!CUR_VERSION!

    IF !DEV! EQU 1 (
        SET OUTPUT_PATH=%BUILD_OUTPUT_BASE%\!BUILD_OUTDIR!\!PROJECT_NAME!\!BRANCH!\!CUR_VERSION!
    )

    IF NOT EXIST "!OUTPUT_PATH!" (
        EXIT /B 0
    )

    SET /A BUILD_COUNT+=1
)
EXIT /B 0

:BUILD_MSVC
IF DEFINED PRE_BUILD_CMD (
    CALL "!PRE_BUILD_CMD:\"=!"
)

CALL :SET_OUTPUT_PATH

SET BUILD_VERSION=!CUR_VERSION!
IF !DEV! == 1 (
    SET HEAD_HASH=!NEW_HEAD:~0,8!
    SET BUILD_VERSION="!BUILD_VERSION:\"=! (!HEAD_HASH:\"=!)"
)

CALL %VERSION_CMD% !BUILD_VERSION:\"=! "!VERSION_FILE:\"=!"

CALL "!MSVC_BAT!" !ARCH!

SET BUILD_OUTPUT=%TMP%\~%RANDOM%.tmp
CALL "!MSBUILD!" !PROJECT_SOLUTION! /p:Configuration=!BUILD_CONFIG! /m > !BUILD_OUTPUT! 2>&1

IF %ERRORLEVEL% NEQ 0 (
    echo Build failed for branch: !BRANCH! in project: !PROJECT_NAME!, output: !BUILD_OUTPUT!
    TYPE %BUILD_OUTPUT%

    mkdir "!OUTPUT_PATH!"
    copy "!BUILD_OUTPUT!" "!OUTPUT_PATH!\error.log"
    echo !NEW_HEAD! > "!OUTPUT_PATH!\HEAD"

) ELSE (
    mkdir "!OUTPUT_PATH!"
    copy "!BUILD_OUTPUT!" "!OUTPUT_PATH!\build.log"
    echo !NEW_HEAD! > "!OUTPUT_PATH!\HEAD"

    xcopy /E /Y "!PROJECT_PATH!\!BIN_FOLDER!\*" "!OUTPUT_PATH!"

    copy "!VERSION_FILE:\"=!" "!OUTPUT_PATH!"

    FOR %%e IN (!EXTRA_DIRS!) DO (
        SET EXTRA=%~dp0\%%~e
        xcopy /E /Y "!EXTRA!\*" "!OUTPUT_PATH!"
    )
    

    CALL "%CHANGELOG_CMD%" "!LAST_BUILD_OUTPUT_PATH!\version.txt" "!CUR_VERSION!" "!OUTPUT_PATH!\version.txt" !PROJECT_PATH!

    IF DEFINED POST_BUILD_CMD (
        CALL "!POST_BUILD_CMD:"=!"
    )

    echo Build successful. Outputs copied to "!OUTPUT_PATH!"
)
EXIT /B 0

:TRIM_INPUT
set "str1=%~1"
FOR /F "tokens=* delims=" %%A IN ("!str1!") DO SET str2=%%A

SET %~2=!str2!