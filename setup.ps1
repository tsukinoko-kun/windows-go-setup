#requires -Version 5.1
# Run: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
[CmdletBinding()]
param(
    [string]$Msys2Root
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$step = 'Checking Windows requirements'
$workDirectory = $null

function Invoke-Native {
    param([string]$FilePath, [string[]]$ArgumentList)

    & $FilePath @ArgumentList | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "'$FilePath $($ArgumentList -join ' ')' failed with exit code $LASTEXITCODE. See the command output above."
    }
}

function Install-Exe {
    param([string]$FilePath, [string]$Arguments)

    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Installer '$FilePath' failed with exit code $($process.ExitCode). See the output and logs in '$workDirectory'."
    }
}

function Get-InstallDirectory {
    param([string]$DisplayName)

    $keys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -match $DisplayName -and $_.InstallLocation } |
        Select-Object -First 1 -ExpandProperty InstallLocation
}

function Find-Executable {
    param([string]$Name, [string[]]$Candidates)

    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
}

function Test-PathEntry {
    param([string]$PathValue, [string]$Directory)

    $Directory = [Environment]::ExpandEnvironmentVariables($Directory.Trim().Trim('"')).TrimEnd('\')
    foreach ($entry in ($PathValue -split ';')) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"')).TrimEnd('\')
        if ($expanded -ieq $Directory) { return $true }
    }
    return $false
}

function Update-SessionPath {
    foreach ($scope in @('Machine', 'User')) {
        foreach ($entry in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            if ($entry -and -not (Test-PathEntry $env:Path $entry)) {
                $env:Path = $env:Path.TrimEnd(';') + ';' + [Environment]::ExpandEnvironmentVariables($entry)
            }
        }
    }
}

function Add-UserPath {
    param([string]$Directory)

    $userPath = [string][Environment]::GetEnvironmentVariable('Path', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if (-not (Test-PathEntry "$machinePath;$userPath" $Directory)) {
        $newPath = ($userPath.TrimEnd(';') + ';' + $Directory).TrimStart(';')
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "Added to user PATH: $Directory"
    }
    if (-not (Test-PathEntry $env:Path $Directory)) {
        $env:Path = $env:Path.TrimEnd(';') + ';' + $Directory
    }
}

function Get-Installer {
    param([string]$Url, [string]$FileName, [string]$Sha256)

    $destination = Join-Path $workDirectory $FileName
    Write-Host "Downloading $FileName..."
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $destination
    }
    catch {
        throw "Download failed from '$Url': $($_.Exception.Message)"
    }
    if ($Sha256) {
        if ($Sha256 -notmatch '^[a-fA-F0-9]{64}$') { throw "Invalid SHA-256 checksum for $FileName." }
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ine $Sha256) {
            throw "SHA-256 verification failed for $FileName. The installer will not run."
        }
    }
    else {
        $signature = Get-AuthenticodeSignature -LiteralPath $destination
        if ($signature.Status -ne 'Valid') {
            throw "Signature verification failed for ${FileName}: $($signature.StatusMessage). The installer will not run."
        }
    }
    return $destination
}

try {
    $windowsBuild = if ($env:OS -eq 'Windows_NT') {
        [int](Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').CurrentBuildNumber
    } else { 0 }
    if ($windowsBuild -lt 18362) {
        throw 'This setup requires Windows 10 version 1903 or newer, or Windows 11.'
    }
    if (-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This setup requires an Intel/AMD 64-bit PC and 64-bit Windows PowerShell. ARM and 32-bit Windows are not supported.'
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $workDirectory = Join-Path $env:TEMP ('student-setup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $workDirectory | Out-Null
    Start-Transcript -Path (Join-Path $workDirectory 'setup.log') | Out-Null
    Write-Host "Setup logs: $workDirectory"
    Update-SessionPath

    $step = 'Installing MSYS2'
    if (-not $Msys2Root) { $Msys2Root = Get-InstallDirectory '^MSYS2\b' }
    if (-not $Msys2Root) { $Msys2Root = "$env:SystemDrive\msys64" }
    $Msys2Root = $Msys2Root.Replace('/', '\').TrimEnd('\')
    if ($Msys2Root -notmatch '^[A-Za-z]:\\[\x21-\x7e]+$' -or $Msys2Root -match '[;"<>|?*]') {
        throw "MSYS2 needs a local, ASCII-only path without spaces, such as C:\msys64. Got '$Msys2Root'."
    }
    $bash = Join-Path $Msys2Root 'usr\bin\bash.exe'
    $pacman = Join-Path $Msys2Root 'usr\bin\pacman.exe'
    if (Test-Path -LiteralPath $bash -PathType Leaf) {
        Write-Host "Skipping MSYS2, already installed at $Msys2Root."
    }
    else {
        if (Test-Path -LiteralPath $Msys2Root) {
            throw "'$Msys2Root' already exists but does not contain MSYS2. Choose another path with -Msys2Root; setup will not overwrite it."
        }
        $page = Invoke-WebRequest -UseBasicParsing -Uri 'https://www.msys2.org/'
        $link = [regex]::Match($page.Content, 'https://github\.com/msys2/msys2-installer/releases/download/[0-9-]+/msys2-x86_64-[0-9]+\.exe')
        if (-not $link.Success) { throw 'Could not find the stable MSYS2 installer on https://www.msys2.org/.' }
        $checksumFile = Join-Path $workDirectory 'msys2.exe.sha256'
        Invoke-WebRequest -UseBasicParsing -Uri ($link.Value + '.sha256') -OutFile $checksumFile
        $checksum = ((Get-Content -LiteralPath $checksumFile -Raw).Trim() -split '\s+')[0]
        $installer = Get-Installer $link.Value 'msys2.exe' $checksum
        Install-Exe $installer ('in --confirm-command --accept-messages --root "' + $Msys2Root.Replace('\', '/') + '"')
    }
    if (-not (Test-Path -LiteralPath $pacman -PathType Leaf)) {
        throw "MSYS2 is incomplete: '$pacman' is missing. Repair MSYS2 before rerunning setup."
    }

    $step = 'Installing UCRT64 GCC'
    $gccDirectory = Join-Path $Msys2Root 'ucrt64\bin'
    $gcc = Join-Path $gccDirectory 'gcc.exe'
    if (Test-Path -LiteralPath $gcc -PathType Leaf) {
        Write-Host 'Skipping UCRT64 GCC, already installed.'
    }
    else {
        Write-Host 'Updating MSYS2 and installing UCRT64 GCC. Close any other MSYS2 terminals first.'
        Invoke-Native $bash @('--login', '-c', 'true')
        # Repair certificates left by updates run without the MSYS2 PATH.
        Invoke-Native $bash @('--login', '-c', 'update-ca-trust')
        # Each login shell supplies the MSYS2 PATH required by package scripts.
        # Core updates can close MSYS2 shells, so finish in a fresh process.
        Invoke-Native $bash @('--login', '-c', 'pacman --noconfirm -Syu')
        Invoke-Native $bash @('--login', '-c', 'pacman --noconfirm -Syu')
        Invoke-Native $bash @('--login', '-c', 'pacman --noconfirm -S --needed mingw-w64-ucrt-x86_64-gcc')
    }
    Add-UserPath $gccDirectory
    Invoke-Native $gcc @('--version')

    $step = 'Installing Go for Windows'
    $goDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Go'
    $go = Find-Executable 'go.exe' @((Join-Path $goDirectory 'bin\go.exe'), "$env:ProgramFiles\Go\bin\go.exe", "$env:SystemDrive\Go\bin\go.exe")
    if ($go) {
        Write-Host "Skipping Go, already installed at $go."
    }
    else {
        if (Test-Path -LiteralPath $goDirectory) {
            throw "'$goDirectory' already exists but does not contain bin\go.exe. Move or repair it before rerunning setup; setup will not overwrite it."
        }
        $releases = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json'
        $release = $releases | Where-Object { $_.stable } | Select-Object -First 1
        $package = $release.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' } | Select-Object -First 1
        if (-not $package) { throw 'Could not find the stable Windows x64 ZIP in the Go download feed.' }
        $archive = Get-Installer ('https://go.dev/dl/' + $package.filename) 'go.zip' $package.sha256
        Write-Host "Extracting Go to $goDirectory. This may take a few minutes."
        Expand-Archive -LiteralPath $archive -DestinationPath $workDirectory
        $extractedGo = Join-Path $workDirectory 'go'
        if (-not (Test-Path -LiteralPath (Join-Path $extractedGo 'bin\go.exe') -PathType Leaf)) {
            throw "Go archive was extracted, but bin\go.exe was not found in '$extractedGo'."
        }
        New-Item -ItemType Directory -Path (Split-Path -Parent $goDirectory) -Force | Out-Null
        Move-Item -LiteralPath $extractedGo -Destination $goDirectory
        $go = Join-Path $goDirectory 'bin\go.exe'
    }
    Add-UserPath (Split-Path -Parent $go)
    Invoke-Native $go @('version')

    $step = 'Installing Git for Windows'
    $gitDirectory = Get-InstallDirectory '^Git$'
    $git = Find-Executable 'git.exe' @("$gitDirectory\cmd\git.exe", "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe", "$env:ProgramFiles\Git\cmd\git.exe")
    $gitVersion = if ($git) { & $git --version }
    if ($git -and $LASTEXITCODE -eq 0 -and $gitVersion -match '\.windows\.') {
        Write-Host "Skipping Git for Windows, already installed at $git. Existing Git settings are unchanged."
    }
    else {
        $tag = (Invoke-WebRequest -UseBasicParsing -Uri 'https://gitforwindows.org/latest-tag.txt').Content.Trim()
        if ($tag -notmatch '^v(?<version>\d+\.\d+\.\d+)\.windows\.(?<patch>\d+)$') {
            throw "Unrecognized Git for Windows release tag '$tag'."
        }
        $version = $Matches.version
        if ($Matches.patch -ne '1') { $version += '.' + $Matches.patch }
        $url = "https://github.com/git-for-windows/git/releases/download/$tag/Git-$version-64-bit.exe"
        $installer = Get-Installer $url 'git.exe'
        $gitDirectory = "$env:LOCALAPPDATA\Programs\Git"
        $log = Join-Path $workDirectory 'git-install.log'
        Install-Exe $installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$gitDirectory`" /o:PathOption=Cmd /o:CRLFOption=CRLFCommitAsIs /LOG=`"$log`""
        $git = Join-Path $gitDirectory 'cmd\git.exe'
        Update-SessionPath
    }
    Invoke-Native $git @('--version')

    $step = 'Installing gopls via Go'
    $goEnvironment = & $go env -json GOBIN GOPATH GOOS GOARCH
    if ($LASTEXITCODE -ne 0) { throw "Could not read Go's environment, exit code $LASTEXITCODE." }
    $goEnvironment = $goEnvironment | ConvertFrom-Json
    $goBin = $goEnvironment.GOBIN
    if (-not $goBin) { $goBin = Join-Path (($goEnvironment.GOPATH -split ';')[0]) 'bin' }
    $gopls = Find-Executable 'gopls.exe' @((Join-Path $goBin 'gopls.exe'))
    if ($gopls) {
        Write-Host "Skipping gopls, already installed at $gopls."
    }
    else {
        if ($goEnvironment.GOOS -ne 'windows' -or $goEnvironment.GOARCH -ne 'amd64') {
            throw 'Go is configured for cross-compilation. Set GOOS=windows and GOARCH=amd64 before installing gopls.'
        }
        Invoke-Native $go @('install', 'golang.org/x/tools/gopls@latest')
        $gopls = Join-Path $goBin 'gopls.exe'
        if (-not (Test-Path -LiteralPath $gopls -PathType Leaf)) {
            throw "Go install finished, but '$gopls' was not created. Check GOBIN and GOPATH."
        }
    }
    Add-UserPath (Split-Path -Parent $gopls)
    Invoke-Native $gopls @('version')

    $step = 'Installing Zed'
    $zedDirectory = Get-InstallDirectory '^Zed$'
    $zed = Find-Executable 'zed.exe' @("$zedDirectory\Zed.exe", "$env:LOCALAPPDATA\Programs\Zed\Zed.exe", "$env:ProgramFiles\Zed\Zed.exe")
    if ($zed) {
        Write-Host "Skipping Zed, already installed at $zed."
    }
    else {
        $installer = Get-Installer 'https://zed.dev/api/releases/stable/latest/Zed-x86_64.exe' 'zed.exe'
        $zedDirectory = "$env:LOCALAPPDATA\Programs\Zed"
        $log = Join-Path $workDirectory 'zed-install.log'
        Install-Exe $installer "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR=`"$zedDirectory`" /MERGETASKS=addtopath /LOG=`"$log`""
        if (-not (Test-Path -LiteralPath (Join-Path $zedDirectory 'Zed.exe') -PathType Leaf)) {
            throw "Zed installer finished, but Zed.exe was not found. Installer log: $log"
        }
    }

    $step = 'Finishing setup'
    Get-ChildItem -LiteralPath $workDirectory -File |
        Where-Object { $_.Extension -in @('.exe', '.zip') } |
        Remove-Item -Force
    Write-Host ''
    Write-Host 'Setup complete. Open a new terminal and restart Zed to use the updated PATH.' -ForegroundColor Green
    Write-Host "Logs: $workDirectory"
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Host ''
    Write-Host "ERROR while ${step}: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Setup stopped. Fix the problem and rerun this script; completed installations will be skipped.'
    if ($workDirectory) {
        Write-Host "Logs and downloaded installers: $workDirectory"
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    }
    exit 1
}
