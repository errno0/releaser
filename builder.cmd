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
        mkdir "!PROJECT_PATH!"
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
        echo %%b
        SET BRANCH=%%~nb
        SET BUILD_BRANCH=0
        SET OUTDIR=release
        SET DEV=1

        IF "!BRANCH!" == "main" (
            SET DEV=0
        )

        IF "!BRANCH!" == "master" (
            SET DEV=0
        )

        IF !DEV! EQU 1 (
            SET OUTDIR=testing
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
            git checkout !BRANCH! || git checkout -b !BRANCH! %%b

            FOR /F "tokens=*" %%h IN ('git rev-parse HEAD') DO SET CURRENT_HEAD=%%h

            git pull origin !BRANCH!
            SET NEW_HEAD=
            FOR /F "tokens=*" %%h IN ('git rev-parse HEAD') DO SET NEW_HEAD=%%h

            SET SKIPBUILD=0

            IF "!CURRENT_HEAD!" == "!NEW_HEAD!" (
                echo No new changes in branch: !BRANCH!
                SET SKIPBUILD=1
            )

            CALL :GET_LAST_RELEASE
            IF NOT DEFINED LAST_OUTPUT_PATH (
                echo "No last build found"
                SET SKIPBUILD=0
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
SET LAST_BASE=%BUILD_OUTPUT_BASE%\!OUTDIR!\!PROJECT_NAME!
iF !DEV! EQU 1 (
    SET LAST_BASE=%BUILD_OUTPUT_BASE%\!OUTDIR!\!PROJECT_NAME!\!BRANCH!
)

FOR /F "delims=" %%D IN ('DIR /B /AD /O-D "!LAST_BASE!\*"') DO (
    SET LAST_OUTPUT_PATH=!LAST_BASE!\%%D
    EXIT /B 0
)
EXIT /B 0


:SET_OUTPUT_PATH
SET BUILD_COUNT=1
SET DATE_TAG=%DATE:~12,2%%DATE:~7,2%%DATE:~4,2%

FOR /L %%I IN (2,1,99) DO (
    SET CUR_VERSION=v!DATE_TAG!-!BUILD_COUNT!
    SET OUTPUT_PATH=%BUILD_OUTPUT_BASE%\!OUTDIR!\!PROJECT_NAME!\!CUR_VERSION!

    IF !DEV! EQU 1 (
        SET OUTPUT_PATH=%BUILD_OUTPUT_BASE%\!OUTDIR!\!PROJECT_NAME!\!BRANCH!\!CUR_VERSION!
        
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

CALL :GET_LAST_RELEASE
CALL :SET_OUTPUT_PATH

SET BUILD_VERSION=!CUR_VERSION!
IF !DEV! == 1 (
    SET HEAD_HASH=!NEW_HEAD:~0,8!
    SET BUILD_VERSION=!BUILD_VERSION! (!HEAD_HASH!)
)

echo %VERSION_CMD% !BUILD_VERSION! !VERSION_FILE!
CALL %VERSION_CMD% !BUILD_VERSION! !VERSION_FILE!

CALL "!MSVC_BAT!" !ARCH!
msbuild !PROJECT_SOLUTION! /p:Configuration=!BUILD_CONFIG! /m
IF %ERRORLEVEL% NEQ 0 (
    echo Build failed for branch: !BRANCH! in project: !PROJECT_NAME!
) ELSE (
    
    mkdir "!OUTPUT_PATH!"

    xcopy /E /Y "!PROJECT_PATH!\!BIN_FOLDER!\*" "!OUTPUT_PATH!"

    FOR %%e IN (!EXTRA_DIRS!) DO (
        SET EXTRA=%~dp0\%%~e
        xcopy /E /Y "!EXTRA!\*" "!OUTPUT_PATH!"
    )
    
    copy NUL "!OUTPUT_PATH!\!NEW_HEAD!"

    echo "%CHANGELOG_CMD%" "!LAST_OUTPUT_PATH!\version.txt" "!CUR_VERSION!" "!OUTPUT_PATH!\version.txt" !PROJECT_PATH!
    CALL "%CHANGELOG_CMD%" "!LAST_OUTPUT_PATH!\version.txt" "!CUR_VERSION!" "!OUTPUT_PATH!\version.txt" !PROJECT_PATH!

    IF DEFINED POST_BUILD_CMD (
        CALL "!POST_BUILD_CMD:"=!"
    )

    echo Build successful. Outputs copied to "!OUTPUT_PATH!"
)
EXIT /B 0