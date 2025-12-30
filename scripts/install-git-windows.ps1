<#
Installs Git for Windows (silent), updates PATH, and verifies availability of `git` in the terminal.

Usage (run as Administrator to update machine PATH and install):
  # Run normally (will attempt to install if git missing)
  powershell -ExecutionPolicy Bypass -File .\scripts\install-git-windows.ps1

  # Provide custom installer URL or skip install and only update PATH
  powershell -ExecutionPolicy Bypass -File .\scripts\install-git-windows.ps1 -InstallerUrl "https://..." -NoInstall

Notes:
- This script downloads the official Git for Windows installer from the latest release redirect.
- Installing and updating the system PATH requires Administrator rights. If not run as admin the script will set the user PATH instead.
- Test after running in a new shell: `git --version`
#>
param(
    [string]$InstallerUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-64-bit.exe",
    [switch]$NoInstall,
    [switch]$NoPathUpdate
)

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

# 1) Quick check
try { $gv = & git --version 2>$null; if ($LASTEXITCODE -eq 0) { Write-Info "git already available: $gv"; exit 0 } } catch { }

# 2) Install Git (unless NoInstall)
if (-not $NoInstall) {
    if (-not (Test-IsAdmin)) {
        Write-Warn "This script is not running as Administrator. Installing system-wide requires admin rights."
        Write-Warn "You can re-run as admin, or the script will attempt a user-level PATH update after download/install if possible."
    }

    $installerPath = Join-Path $env:TEMP "git-for-windows-installer.exe"
    Write-Info "Downloading Git installer from: $InstallerUrl"
    try {
        Invoke-WebRequest -Uri $InstallerUrl -OutFile $installerPath -UseBasicParsing -ErrorAction Stop
        Write-Info "Downloaded installer to $installerPath"
    } catch {
        Write-Err "Failed to download Git installer: $_"
        exit 1
    }

    # Run NSIS installer silently (common flags)
    Write-Info "Running installer (silent). This may take a minute..."
    $args = '/VERYSILENT','/NORESTART'
    $proc = Start-Process -FilePath $installerPath -ArgumentList $args -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Warn "Installer exited with code $($proc.ExitCode). You may need to run the installer interactively."
    } else {
        Write-Info "Installer finished successfully."
    }
} else {
    Write-Info "Skipping Git installer (NoInstall set)."
}

# 3) Locate installed git
$gitCandidates = @()
# Common locations
$gitCandidates += "${env:ProgramFiles}\Git\cmd\git.exe"
$gitCandidates += "${env:ProgramFiles(x86)}\Git\cmd\git.exe"
$gitCandidates += "${env:ProgramFiles}\Git\bin\git.exe"
$gitCandidates += "${env:ProgramFiles(x86)}\Git\bin\git.exe"

# search Program Files if not found
foreach ($c in $gitCandidates) { if (Test-Path $c) { $gitPath = $c; break } }
if (-not $gitPath) {
    $pf = @(${env:ProgramFiles}, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    foreach ($root in $pf) {
        try {
            $dirs = Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'Git' }
            foreach ($d in $dirs) {
                $try = Join-Path $d.FullName 'cmd\git.exe'
                if (Test-Path $try) { $gitPath = $try; break }
            }
            if ($gitPath) { break }
        } catch { }
    }
}

if ($gitPath) { Write-Info "Detected git at: $gitPath" } else { Write-Warn "Could not auto-detect git installation path. You may need to install Git manually and run this script again to update PATH." }

# 4) Update PATH (system if admin, user otherwise), unless disabled
if (-not $NoPathUpdate -and $gitPath) {
    $gitCmdDir = Split-Path -Parent $gitPath
    $target = if (Test-IsAdmin) { 'Machine' } else { 'User' }
    Write-Info "Updating $target PATH to include: $gitCmdDir"
    try {
        $current = [Environment]::GetEnvironmentVariable('Path',$target)
        if ($current -notmatch [regex]::Escape($gitCmdDir)) {
            $new = "$gitCmdDir;$current"
            [Environment]::SetEnvironmentVariable('Path',$new,$target)
            Write-Info "PATH updated for $target. New shells will pick this up."
        } else {
            Write-Info "PATH already contains $gitCmdDir"
        }
    } catch {
        Write-Err "Failed to update PATH: $_"
    }
}

# 5) Verify git availability in a new shell message
try {
    $gv2 = & "$gitPath" --version 2>$null
    if ($gv2) { Write-Info "Verified git executable: $gv2" }
} catch {
    Write-Warn "Could not execute git directly. Open a new terminal session or restart the machine/IDE to pick up PATH changes."
}

Write-Info "Done. If git is still not available in your terminal, start a new terminal or reboot."