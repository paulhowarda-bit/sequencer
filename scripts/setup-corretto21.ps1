<#
PowerShell helper to install Amazon Corretto 21, set JAVA_HOME, update pom.xml, and optionally run mvn build.
Usage examples:
  # Run everything (will attempt install if run as admin)
  pwsh -ExecutionPolicy Bypass -File .\scripts\setup-corretto21.ps1 -InstallCorretto -SetEnvironment -UpdatePom -RunBuild

  # Only update pom.xml (no install)
  pwsh -ExecutionPolicy Bypass -File .\scripts\setup-corretto21.ps1 -UpdatePom

Notes:
- Installing Corretto requires admin privileges.
- The script backs up `pom.xml` to `pom.xml.bak` before editing.
- The installer URL uses Amazon Corretto's "latest" 64-bit Windows JDK 21 download page. Adjust `$InstallerUrl` if needed.
#>
param(
    [switch]$InstallCorretto,
    [switch]$SetEnvironment,
    [switch]$UpdatePom,
    [switch]$RunBuild,
    [string]$PomPath = "..\pom.xml",
    [string]$InstallerUrl = "https://corretto.aws/downloads/latest/amazon-corretto-21-x64-windows-jdk.msi"
)

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

Push-Location -Path (Split-Path -Path $PSScriptRoot -Parent) | Out-Null

# Resolve full path to pom
$scriptDir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$repoRoot = Resolve-Path -Path "$scriptDir\.." | Select-Object -ExpandProperty Path
$pomFullPath = Resolve-Path -Path (Join-Path $repoRoot $PomPath) -ErrorAction SilentlyContinue
if (-not $pomFullPath) { $pomFullPath = Join-Path $repoRoot $PomPath }

Write-Info "Repository root: $repoRoot"
Write-Info "POM path: $pomFullPath"

# 1) Install Corretto 21 (if requested)
if ($InstallCorretto) {
    if (-not (Test-IsAdmin)) {
        Write-Warn "Installation requires administrator privileges. Please re-run this script as Administrator to install Corretto. Skipping install."
    } else {
        $msiPath = Join-Path $env:TEMP "amazon-corretto-21.msi"
        Write-Info "Downloading Corretto 21 from: $InstallerUrl"
        try {
            Invoke-WebRequest -Uri $InstallerUrl -OutFile $msiPath -UseBasicParsing -ErrorAction Stop
            Write-Info "Downloaded installer to $msiPath"
        } catch {
            Write-Err "Failed to download installer: $_"
            exit 1
        }

        Write-Info "Running MSI installer (silent)..."
        $args = "/i `"$msiPath`" /qn /norestart"
        $proc = Start-Process -FilePath msiexec.exe -ArgumentList $args -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            Write-Err "msiexec returned exit code $($proc.ExitCode). Check installer logs or run installer interactively."
            exit 1
        }
        Write-Info "Installer finished."

        # Attempt to discover installed Corretto path
        $possibleRoots = @(
            "$env:ProgramFiles\Amazon Corretto",
            "$env:ProgramFiles(x86)\Amazon Corretto",
            "$env:ProgramFiles\Amazon Corretto\jdk-21*",
            "$env:ProgramFiles\Amazon Corretto\jdk-21*.*",
            "$env:ProgramFiles\Amazon Corretto\jdk-*21*"
        )
        $jdkPath = $null
        foreach ($r in $possibleRoots) {
            $candidates = Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "21" } | Select-Object -First 1
            if ($candidates) { $jdkPath = $candidates.FullName; break }
        }
        if (-not $jdkPath) {
            # Try registry lookup
            try {
                $reg = Get-ChildItem -Path HKLM:\SOFTWARE\JavaSoft\JDK -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                if ($reg) {
                    $jdkPath = (Get-ItemProperty -Path $reg.PSPath -Name JavaHome -ErrorAction SilentlyContinue).JavaHome
                }
            } catch { }
        }

        if ($jdkPath) { Write-Info "Detected JDK path: $jdkPath" } else { Write-Warn "Could not detect Corretto installation path automatically. You may need to set JAVA_HOME manually." }

        if ($SetEnvironment -and $jdkPath) {
            Write-Info "Setting system JAVA_HOME to $jdkPath and adding bin to Machine PATH"
            try {
                [Environment]::SetEnvironmentVariable('JAVA_HOME',$jdkPath,'Machine')
                $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
                $javaBin = Join-Path $jdkPath 'bin'
                if ($machinePath -notmatch [regex]::Escape($javaBin)) {
                    [Environment]::SetEnvironmentVariable('Path', "$javaBin;$machinePath",'Machine')
                }
                Write-Info "Environment variables updated. You may need to restart shells/IDE to pick up changes."
            } catch {
                Write-Err "Failed to set system environment variables: $_"
            }
        }
    }
}

# 2) If user asked only to set environment (without installing), try to detect JDK and set env
if ($SetEnvironment -and -not $InstallCorretto) {
    # attempt to find any JDK 21 in Program Files
    $jdkPath = Get-ChildItem -Path "$env:ProgramFiles\*" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'corretto|jdk' } | ForEach-Object { Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue } | Where-Object { $_.Name -match '^jdk-?21' } | Select-Object -First 1
    if ($jdkPath) { $jdkPath = $jdkPath.FullName }
    if ($jdkPath) {
        Write-Info "Detected JDK path: $jdkPath"
        try {
            [Environment]::SetEnvironmentVariable('JAVA_HOME',$jdkPath,'Machine')
            $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
            $javaBin = Join-Path $jdkPath 'bin'
            if ($machinePath -notmatch [regex]::Escape($javaBin)) {
                [Environment]::SetEnvironmentVariable('Path', "$javaBin;$machinePath",'Machine')
            }
            Write-Info "Environment variables updated. You may need to restart shells/IDE to pick up changes."
        } catch {
            Write-Err "Failed to set system environment variables: $_"
        }
    } else {
        Write-Warn "Couldn't auto-detect a JDK 21 installation. If you installed Corretto elsewhere, set JAVA_HOME manually."
    }
}

# 3) Update pom.xml to target Java 21 (if requested)
if ($UpdatePom) {
    if (-not (Test-Path $pomFullPath)) {
        Write-Err "pom.xml not found at $pomFullPath. Skipping pom update."
    } else {
        $bak = "$pomFullPath.bak"
        Copy-Item -Path $pomFullPath -Destination $bak -Force
        Write-Info "Backed up original pom.xml to $bak"

        $content = Get-Content -Raw -Path $pomFullPath

        # Ensure <properties> contains maven.compiler.release and java.version
        if ($content -match '<maven.compiler.release>') {
            $content = [regex]::Replace($content, '<maven\.compiler\.release>\s*\d+\s*</maven\.compiler\.release>', "<maven.compiler.release>21</maven.compiler.release>", 'IgnoreCase')
        } else {
            if ($content -match '<properties\s*>') {
                $content = [regex]::Replace($content, '(?i)(<properties\s*>)(.*?)', "`$1`n    <maven.compiler.release>21</maven.compiler.release>`n    <java.version>21</java.version>`n`$2", 'Singleline')
            } else {
                # insert properties after <project> or after <modelVersion>
                if ($content -match '(?i)</modelVersion>') {
                    $content = [regex]::Replace($content, '(?i)(</modelVersion>\s*)', "`$1`n  <properties>`n    <maven.compiler.release>21</maven.compiler.release>`n    <java.version>21</java.version>`n  </properties>`n", 'Singleline')
                } else {
                    # fallback: prepend properties near top
                    $content = [regex]::Replace($content, '(?i)(<project[^>]*>)', "`$1`n  <properties>`n    <maven.compiler.release>21</maven.compiler.release>`n    <java.version>21</java.version>`n  </properties>`n", 'Singleline')
                }
            }
        }

        # Ensure maven-compiler-plugin is configured with <release>21
        if ($content -match '(?is)<artifactId>maven-compiler-plugin</artifactId>') {
            # If plugin has <configuration> with <release>, replace it; else add <configuration><release>21</release></configuration>
            if ($content -match '(?is)<artifactId>maven-compiler-plugin</artifactId>.*?<configuration>.*?<release>') {
                $content = [regex]::Replace($content, '(?is)(<artifactId>maven-compiler-plugin</artifactId>.*?<configuration>.*?<release>)(.*?)(</release>.*?)', '`${1}21${3}')
            } else {
                $content = [regex]::Replace($content, '(?is)(<artifactId>maven-compiler-plugin</artifactId>)(.*?</plugin>)', "`$1`n$2`n    <configuration>`n      <release>21</release>`n    </configuration>`n  ", 'Singleline')
            }
        } else {
            # Add compiler plugin into <build><plugins> or create build/plugins
            $pluginSnippet = @"
    <plugin>
      <groupId>org.apache.maven.plugins</groupId>
      <artifactId>maven-compiler-plugin</artifactId>
      <version>3.11.0</version>
      <configuration>
        <release>21</release>
      </configuration>
    </plugin>
"@
            if ($content -match '(?i)</plugins>') {
                $content = [regex]::Replace($content, '(?i)(</plugins>)', "$pluginSnippet`n$1", 'Singleline')
            } elseif ($content -match '(?i)</build>') {
                $content = [regex]::Replace($content, '(?i)(</build>)', "  <plugins>`n$pluginSnippet  </plugins>`n$1", 'Singleline')
            } else {
                # create build/plugins block before </project>
                $content = [regex]::Replace($content, '(?i)(</project>)', "  <build>`n    <plugins>`n$pluginSnippet    </plugins>`n  </build>`n`$1", 'Singleline')
            }
        }

        Set-Content -Path $pomFullPath -Value $content -Force
        Write-Info "Updated pom.xml to target Java 21 (backup at $bak)."
    }
}

# 4) Run Maven build (if requested)
if ($RunBuild) {
    # Ensure java is available
    try {
        $javaVer = & java -version 2>&1
        Write-Info "java -version: $($javaVer -join ' | ')"
    } catch {
        Write-Warn "`java` not found on PATH. If you set JAVA_HOME above, please open a new shell or restart your IDE. Skipping build."
        $RunBuild = $false
    }
}

if ($RunBuild) {
    try {
        Write-Info "Running 'mvn -v' to show Maven environment"
        & mvn -v
    } catch {
        Write-Warn "`mvn` not found on PATH. Ensure Maven is installed or use Maven Wrapper (./mvnw). Skipping build."
        $RunBuild = $false
    }
}

if ($RunBuild) {
    Write-Info "Executing mvn clean install"
    $startInfo = @{ FilePath = 'mvn'; ArgumentList = 'clean','install'; WorkingDirectory = $repoRoot }
    $proc = Start-Process -FilePath mvn -ArgumentList 'clean','install' -WorkingDirectory $repoRoot -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Err "Maven build failed with exit code $($proc.ExitCode). Inspect output for details."
        exit $proc.ExitCode
    } else {
        Write-Info "Maven build completed successfully."
    }
}

Pop-Location | Out-Null
Write-Info "Script finished."
