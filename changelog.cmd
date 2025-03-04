@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

SET OLD_VERSION_FILE="%~1"
SET NEW_VERSION="%~2"
SET NEW_VERSION_FILE="%~3"
SET PROJECT_DIR="%~4"

SET LAST_HEAD=
SET CHANGELOG=

CALL :READ_LAST_VERSION
CALL :GENERATE_CHANGELOG
CALL :READ_CURRENT_HEAD

(
    ECHO %NEW_VERSION:"=%, %CURRENT_HEAD%
    ECHO.
    ECHO %CHANGELOG%
    ECHO.
    IF EXIST %OLD_VERSION_FILE% TYPE %OLD_VERSION_FILE%
) > "%NEW_VERSION_FILE:"=%"

ECHO New version created: %NEW_VERSION%
ECHO Changelog:
ECHO %CHANGELOG%

:READ_LAST_VERSION

IF EXIST %OLD_VERSION_FILE% (
    FOR /F "tokens=1,2 delims=," %%A IN ('FINDSTR /B v2 %OLD_VERSION_FILE%') DO (
        SET LAST_HEAD=%%~B
        EXIT /B 0
    )
) ELSE (
    SET LAST_HEAD=
)
EXIT /B 0

:GENERATE_CHANGELOG
SET CHANGELOG=
PUSHD %PROJECT_DIR%
IF NOT DEFINED LAST_HEAD (
    FOR /F "delims=" %%C IN ('git log -n 1 --pretty^=format:"  - %%s"') DO (
        CALL :CLEAN_CL "%%C" CL
        SET CHANGELOG=!CL!
    )
) ELSE (
    FOR /F "delims=" %%C IN ('git log !LAST_HEAD!..HEAD --pretty^=format:"  - %%s"') DO (
        CALL :CLEAN_CL "%%C" CL
        SET CHANGELOG=!CHANGELOG!!CL!^&echo.
    )
)
POPD
EXIT /B 0

:READ_CURRENT_HEAD
PUSHD %PROJECT_DIR%
FOR /F "delims=" %%G IN ('git rev-parse HEAD') DO (
    SET CURRENT_HEAD=%%G
    POPD
    EXIT /B 0
)
POPD

ENDLOCAL
EXIT /B 0

:CLEAN_CL
set "str1=%~1"

for %%a in ( ! @ $ % ^^ ^&  + \ / ^< ^>  . '  [ ] { }  ` ^| ^"  ) do (
   set "str1=!str1:%%a=!"
)

set "str1=!str1:(=!"
set "str1=!str1:)=!"
set "str1=!str1:;=!"
set "str1=!str1:,=!"
set "str1=!str1:^^=!"
set "str1=!str1:^~=!"

SET %~2=!str1!

EXIT /B 0