# Find existing git.exe under common locations and update PATH (Machine if admin, otherwise User).
$paths = @()
if ($env:ProgramFiles) { $paths += $env:ProgramFiles }
if ($env:ProgramFiles_x86) { $paths += $env:ProgramFiles_x86 }
if ($env:LocalAppData) { $paths += $env:LocalAppData }
$paths += 'C:\Program Files'
$paths += 'C:\Program Files (x86)'

$found = $null
foreach ($p in $paths) {
    if (-not $p) { continue }
    $c1 = Join-Path $p 'Git\cmd\git.exe'
    $c2 = Join-Path $p 'Git\bin\git.exe'
    if (Test-Path $c1) { $found = $c1; break }
    if (Test-Path $c2) { $found = $c2; break }
}

if (-not $found) {
    foreach ($root in $paths) {
        if (-not (Test-Path $root)) { continue }
        try {
            $candidates = Get-ChildItem -Path $root -Directory -Filter '*Git*' -ErrorAction SilentlyContinue
            foreach ($d in $candidates) {
                $try1 = Join-Path $d.FullName 'cmd\git.exe'
                $try2 = Join-Path $d.FullName 'bin\git.exe'
                if (Test-Path $try1) { $found = $try1; break }
                if (Test-Path $try2) { $found = $try2; break }
            }
            if ($found) { break }
        } catch {}
    }
}

if ($found) {
    Write-Host "FOUND: $found"
    $gitCmdDir = Split-Path -Parent $found
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $scope = if ($isAdmin) { 'Machine' } else { 'User' }
    Write-Host "Updating $scope PATH to include: $gitCmdDir"
    try {
        $current = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ($current -notmatch [regex]::Escape($gitCmdDir)) {
            $new = "$gitCmdDir;$current"
            [Environment]::SetEnvironmentVariable('Path', $new, $scope)
            Write-Host 'PATH updated'
        } else {
            Write-Host 'PATH already contains git dir'
        }
    } catch {
        Write-Host "Failed to update PATH: $_" -ForegroundColor Red
        exit 1
    }
    Write-Host 'Done. Open a new terminal and run "git --version" to verify.'
} else {
    Write-Host 'No git executable found in common locations.' -ForegroundColor Yellow
    Write-Host 'If git is installed in a custom location, run: (set $p to the folder containing git.exe)'
    Write-Host '  [Environment]::SetEnvironmentVariable("Path", "$p;" + [Environment]::GetEnvironmentVariable("Path","User"), "User")'
}
