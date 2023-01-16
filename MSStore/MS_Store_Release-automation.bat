@echo off
setlocal
REM Arguments
REM
REM RelType     - If not provided, will be set to empty 
REM               empty is considered Final, and if Final is provided, the variable is set to empty
REM 
REM APPNAME     - default is kodi
REM APPVERSION  = default is 20.0
REM CODENAME    - default is Nexus
REM Testbuild   = Whether we download from Testbuild folder on mirrors
REM               default is no and will download from Release folder
REM Clean       - whether we clean (rmdir) the workdir
REM
REM Parameters
REM
REM workdir     - Directory to create folder structure
REM               if no path supplied, current location of the script is used as base
REM
REM Example run script
REM             Release-automation.bar /RelType=RC1 /Testbuild=ON c:\Test\RC3


REM Paramater and Named arg parsing from https://stackoverflow.com/a/58344976
set PARAM_0=0
:parameters_parse

set parameter=%~1
if "%parameter%"=="" goto parameters_parse_done
if "%parameter:~0,1%"=="/" (
    set ARG_%parameter:~1%=%~2
    shift
    shift
    goto parameters_parse
)
set /a PARAM_0=%PARAM_0%+1
set PARAM_%PARAM_0%="%~1"
shift
goto parameters_parse

:parameters_parse_done

IF "%PARAM_1%"=="" ( SET "workdir=%~dp0" ) ELSE ( SET "workdir=%PARAM_1%" )

IF "%PARAM_1%"=="" ( echo Wont clean workdir if not provided as a parameter ) else ( IF defined ARG_Clean rmdir /S /Q %workdir% && echo Cleaning %workdir% )

IF NOT EXIST %workdir% md %workdir%
set workdir_stripped=%workdir:"=%
IF NOT EXIST %workdir%\bundle-uwp md %workdir%\bundle-uwp
IF NOT EXIST %workdir%\bundle-bridge md %workdir%\bundle-bridge
IF NOT EXIST %workdir%\output-uwp md %workdir%\output-uwp
IF NOT EXIST %workdir%\install-bridge md %workdir%\install-bridge
IF NOT EXIST %workdir%\output-bridge md %workdir%\output-bridge
IF NOT EXIST %workdir%\store_submission md %workdir%\store_submission
IF NOT EXIST %workdir%\artifact md %workdir%\artifact

if "%ARG_APPNAME%" == "" SET "ARG_APPNAME=kodi"
if "%ARG_APPVERSION%" == "" SET "ARG_APPVERSION=20.0"
if "%ARG_CODENAME%" == "" SET "ARG_CODENAME=Nexus"
if "%ARG_UWP_ARCH%" == "" SET "ARG_UWP_ARCH=x64"
if "%ARG_BRIDGE_ARCH%" == "" SET "ARG_BRIDGE_ARCH=x86_x64"
if "%ARG_BUNDLE_EXTENSION%" == "" SET "ARG_BUNDLE_EXTENSION=appxbundle"

SET "uwpmisxname=%ARG_APPNAME%-%ARG_APPVERSION%-%ARG_CODENAME%_%ARG_APPVERSION%.0.0%ARG_ReleaseType%-%ARG_UWP_ARCH%"
SET "uwpbundlename=%ARG_APPNAME%-%ARG_APPVERSION%-%ARG_CODENAME%%ARG_ReleaseType%_%ARG_UWP_ARCH%"
SET "bridgeexename=%ARG_APPNAME%-%ARG_APPVERSION%-%ARG_CODENAME%%ARG_ReleaseType%"
SET "bridgebundlename=%ARG_APPNAME%-%ARG_APPVERSION%-%ARG_CODENAME%%ARG_ReleaseType%_%ARG_BRIDGE_ARCH%"

if defined ARG_Testbuild (SET "MIRROR_URL=http://mirrors.kodi.tv/test-builds/windows") else (SET "MIRROR_URL=http://mirrors.kodi.tv/releases/windows")
if defined ARG_Testbuild (SET "UWPMirrorFolder=uwp64") else (SET "UWPMirrorFolder=UWP")

REM goto patch_bridge_version
REM goto install_bridge

:download_UWP

REM goto package_UWP

REM Download UWP msix and appxsym 
bitsadmin.exe /transfer "Download UWP %ARG_UWP_ARCH% msix" /download /priority FOREGROUND %MIRROR_URL%/%UWPMirrorFolder%/%uwpmisxname%.msix %workdir%\bundle-uwp\%uwpbundlename%.msix
REM We cant have the appxsym in the bundle folder. save to output ready for zip with appxbundle
bitsadmin.exe /transfer "Download UWP %ARG_UWP_ARCH% appxsym" /download /priority FOREGROUND %MIRROR_URL%/%UWPMirrorFolder%/%uwpmisxname%.appxsym %workdir%\output-uwp\%uwpbundlename%.appxsym

REM goto end

:package_UWP

REM If testbuild, rename to match release naming scheme
REM maybe do this before download step?
REM if defined ARG_Testbuild (echo true) else (echo false)

IF NOT EXIST %workdir%\output-uwp\%uwpbundlename%.appxbundle makeappx.exe bundle /d %workdir%\bundle-uwp /p %workdir%\output-uwp\%uwpbundlename%.appxbundle

IF EXIST %workdir%\output-uwp\%uwpbundlename%.zip del %workdir%\output-uwp\%uwpbundlename%.zip
powershell Compress-Archive -LiteralPath '%workdir%\output-uwp\%uwpbundlename%.appxsym', '%workdir%\output-uwp\%uwpbundlename%.appxbundle' -DestinationPath "%workdir%\store_submission\%uwpbundlename%.zip"

IF EXIST %workdir%\store_submission\%uwpbundlename%.appxupload del %workdir%\store_submission\%uwpbundlename%.appxupload
rename "%workdir%\store_submission\%uwpbundlename%.zip" "%uwpbundlename%.appxupload"

:download_bridge

REM Download Desktop x86 and x64 executables
SET dl_arch=x86
bitsadmin.exe /transfer "Download Desktop %dl_arch% exe" /download /priority FOREGROUND %MIRROR_URL%/win32/%bridgeexename%-%dl_arch%.exe %workdir%\artifact\%bridgeexename%-%dl_arch%.exe
bitsadmin.exe /transfer "Download Desktop %dl_arch% pdb" /download /priority FOREGROUND %MIRROR_URL%/win32/%bridgeexename%-%dl_arch%.pdb %workdir%\artifact\%bridgeexename%-%dl_arch%.pdb

SET dl_arch=x64
bitsadmin.exe /transfer "Download Desktop %dl_arch% exe" /download /priority FOREGROUND %MIRROR_URL%/win64/%bridgeexename%-%dl_arch%.exe %workdir%\artifact\%bridgeexename%-%dl_arch%.exe
bitsadmin.exe /transfer "Download Desktop %dl_arch% pdb" /download /priority FOREGROUND %MIRROR_URL%/win64/%bridgeexename%-%dl_arch%.pdb %workdir%\artifact\%bridgeexename%-%dl_arch%.pdb

:install_bridge

echo Installing Desktop apps

SET dl_arch=x86
%workdir%\artifact\%bridgeexename%-%dl_arch%.exe /S /D=%workdir_stripped%\install-bridge\%dl_arch%

SET dl_arch=x64
%workdir%\artifact\%bridgeexename%-%dl_arch%.exe /S /D=%workdir_stripped%\install-bridge\%dl_arch%

:patch_bridge_version

SET dl_arch=x86

powershell $m = (get-content %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml -raw) -match 'Version=\"(\d+)\.(\d+)\.(\d+)\.?(\d?)\"' ; $patch_version = [int]$Matches[3] ; if ($patch_version -gt 900) { $patch_version = $patch_version + 50 } else { $patch_version = $patch_version + 500 } ; (get-content %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml -raw) -replace 'Version=\"(\d+)\.(\d+)\.(\d+)(\.?\d?)\"', \"Version=\"\"`$1.`$2.$patch_version`$4\"\"\" > %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest2.xml
del %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml
rename "%workdir_stripped%\install-bridge\%dl_arch%\AppxManifest2.xml" AppxManifest.xml

SET dl_arch=x64

powershell $m = (get-content %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml -raw) -match 'Version=\"(\d+)\.(\d+)\.(\d+)\.?(\d?)\"' ; $patch_version = [int]$Matches[3] ; if ($patch_version -gt 900) { $patch_version = $patch_version + 50 } else { $patch_version = $patch_version + 500 } ; (get-content %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml -raw) -replace 'Version=\"(\d+)\.(\d+)\.(\d+)(\.?\d?)\"', \"Version=\"\"`$1.`$2.$patch_version`$4\"\"\" > %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest2.xml
del %workdir_stripped%\install-bridge\%dl_arch%\AppxManifest.xml
rename "%workdir_stripped%\install-bridge\%dl_arch%\AppxManifest2.xml" AppxManifest.xml

REM goto end

:bundle_bridge

SET dl_arch=x86
makeappx pack /d %workdir_stripped%\install-bridge\%dl_arch% /p %workdir%\bundle-bridge\%bridgeexename%-%dl_arch%.appx

SET dl_arch=x64
makeappx pack /d %workdir_stripped%\install-bridge\%dl_arch% /p %workdir%\bundle-bridge\%bridgeexename%-%dl_arch%.appx

makeappx bundle /d %workdir%\bundle-bridge /p %workdir%\output-bridge\%bridgebundlename%.appxbundle

rem goto end

:package_syms


SET dl_arch=x86

IF EXIST %workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip del %workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip
powershell Compress-Archive -LiteralPath '%workdir%\artifact\%bridgeexename%-%dl_arch%.pdb' -DestinationPath "%workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip"

IF EXIST %workdir%\output-bridge\%bridgeexename%-%dl_arch%.appxsym del %workdir%\output-bridge\%bridgeexename%-%dl_arch%.appxsym
rename "%workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip" "%bridgeexename%-%dl_arch%.appxsym"

SET dl_arch=x64

IF EXIST %workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip del %workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip
powershell Compress-Archive -LiteralPath '%workdir%\artifact\%bridgeexename%-%dl_arch%.pdb' -DestinationPath "%workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip"

IF EXIST %workdir%\output-bridge\%bridgeexename%-%dl_arch%.appxsym del %workdir%\output-bridge\%bridgeexename%-%dl_arch%.appxsym
rename "%workdir%\output-bridge\%bridgeexename%-%dl_arch%.zip" "%bridgeexename%-%dl_arch%.appxsym"

:package_bridge

IF EXIST %workdir%\output-bridge\%bridgebundlename%.zip del %workdir%\output-uwp\%bridgebundlename%.zip
powershell Compress-Archive -LiteralPath '%workdir%\output-bridge\%bridgeexename%-x86.appxsym', '%workdir%\output-bridge\%bridgeexename%-x64.appxsym', '%workdir%\output-bridge\%bridgebundlename%.appxbundle' -DestinationPath "%workdir%\store_submission\%bridgebundlename%.zip"

IF EXIST %workdir%\store_submission\%bridgebundlename%.appxupload del %workdir%\store_submission\%bridgebundlename%.appxupload
rename "%workdir%\store_submission\%bridgebundlename%.zip" "%bridgebundlename%.appxupload"

:end
endlocal
