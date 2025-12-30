<#
Initialize a Git repository (if missing), create a branch and commit current changes.
Run this locally where `git` is installed.

Usage examples:
  # Default: init (if needed), create branch, add and commit
  pwsh -ExecutionPolicy Bypass -File .\scripts\git-init-and-commit.ps1

  # Provide custom commit message and user
  pwsh -ExecutionPolicy Bypass -File .\scripts\git-init-and-commit.ps1 -UserName "Paul" -UserEmail "paul@example.com" -CommitMessage "Upgrade to Corretto 21"

Parameters:
  -Branch: branch name to create/switch to (default: appmod/java-migration-20251230115806)
  -UserName / -UserEmail: git user config to set locally
  -CommitMessage: commit message
  -ForceInit: force `git init` even if .git exists
  -NoPush: skip pushing to remote
  -Remote: remote name to push to (default: origin)
#>
param(
    [string]$Branch = "appmod/java-migration-20251230115806",
    [string]$UserName = "auto-migration",
    [string]$UserEmail = "devnull@example.com",
    [string]$CommitMessage = "Code migration: target Java 21, add aeron-driver, add Corretto setup scripts, remove BOM from sources",
    [switch]$ForceInit,
    [switch]$NoPush,
    [string]$Remote = "origin"
)

function Write-Info { param($m) Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Write-Warn { param($m) Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Write-Err  { param($m) Write-Host "[ERROR] $m" -ForegroundColor Red }

# Check git availability
try {
    & git --version > $null 2>&1
} catch {
    Write-Err "git is not installed or not on PATH. Install Git and re-run this script locally."
    exit 1
}

$cwd = Get-Location
Write-Info "Working directory: $cwd"

# Initialize repo if needed
$gitDir = Join-Path $cwd ".git"
if (-not (Test-Path $gitDir) -or $ForceInit) {
    if (Test-Path $gitDir -and $ForceInit) {
        Write-Warn "Force init requested; existing .git will be reinitialized."
    }
    Write-Info "Initializing git repository..."
    git init
} else {
    Write-Info "Existing git repository detected."
}

# Configure local user
if ($UserName) { git config user.name "$UserName" }
if ($UserEmail) { git config user.email "$UserEmail" }

# Create or switch to branch
$existingBranch = $(git rev-parse --abbrev-ref HEAD 2>$null)
if ($existingBranch -ne $null -and $existingBranch -eq $Branch) {
    Write-Info "Already on branch $Branch"
} else {
    # If branch exists, checkout, else create
    $branchExists = (git show-ref --verify --quiet refs/heads/$Branch; if ($LASTEXITCODE -eq 0) { $true } else { $false })
    if ($branchExists) {
        Write-Info "Checking out existing branch $Branch"
        git checkout $Branch
    } else {
        Write-Info "Creating and switching to branch $Branch"
        git checkout -b $Branch
    }
}

# Stage and commit
Write-Info "Staging all changes..."
git add --all

# Determine if there is anything to commit
$changes = git status --porcelain
if ($changes -eq "") {
    Write-Info "No changes to commit."
} else {
    Write-Info "Committing changes..."
    git commit -m "$CommitMessage"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Commit failed. Inspect git status locally."
        exit 1
    }
    Write-Info "Commit created on branch $Branch."
}

# Optional push
if (-not $NoPush) {
    Write-Info "Attempting to push to remote '$Remote' (this may fail if no remote is configured)."
    git push -u $Remote $Branch 2>&1 | Write-Host
} else {
    Write-Info "Skipping push to remote (NoPush set)."
}

Write-Info "Git operation complete. Run 'git status' locally to verify."