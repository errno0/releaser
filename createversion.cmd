@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

SET VERSION="%~1"
SET VERSION_FILE="%~2"

if exist %VERSION_FILE% (                                                                  
    del %VERSION_FILE%
)

echo #ifndef CURRENTVERSION_H >> %VERSION_FILE%                                        
echo #define CURRENTVERSION_H >> %VERSION_FILE%                                        
echo #define CURRENTVERSION %VERSION% >> %VERSION_FILE% 
echo #endif // CURRENTVERSION_H >> %VERSION_FILE%