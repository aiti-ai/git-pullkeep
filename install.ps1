# git-pullkeep installer for Windows (PowerShell 5.1+).
#   irm https://raw.githubusercontent.com/aiti-ai/git-pullkeep/main/install.ps1 | iex
# Env:
#   GIT_PULLKEEP_REPO   owner/repo (default: aiti-ai/git-pullkeep) or a raw base URL,
#   GIT_PULLKEEP_REF    branch or tag (default: main)
#   GIT_PULLKEEP_DIR    install directory (default: %USERPROFILE%\bin)
#
# Written in ASCII only: PowerShell 5.1 decodes .ps1 files as ANSI.

$ErrorActionPreference = 'Stop'

$repo = if ($env:GIT_PULLKEEP_REPO) { $env:GIT_PULLKEEP_REPO } else { 'aiti-ai/git-pullkeep' }
$ref = if ($env:GIT_PULLKEEP_REF) { $env:GIT_PULLKEEP_REF } else { 'main' }
$dir = if ($env:GIT_PULLKEEP_DIR) { $env:GIT_PULLKEEP_DIR } else { Join-Path $env:USERPROFILE 'bin' }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw 'git-pullkeep: git is required'
}

$url = if ($repo -match '^https?://') { "$($repo.TrimEnd('/'))/$ref/git-pullkeep" } else { "https://raw.githubusercontent.com/$repo/$ref/git-pullkeep" }
$dest = Join-Path $dir 'git-pullkeep'

New-Item -ItemType Directory -Force -Path $dir | Out-Null
Write-Host "downloading $url"
$raw = (Invoke-WebRequest -UseBasicParsing -Uri $url).Content

# The script must keep LF line endings: the shebang is executed by Git's bash.
$text = $raw -replace "`r`n", "`n"
if (-not $text.StartsWith('#!')) { throw 'git-pullkeep: download looks wrong' }
[System.IO.File]::WriteAllText($dest, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "installed: $dest"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $dir) {
  $newPath = if ([string]::IsNullOrEmpty($userPath)) { $dir } else { "$userPath;$dir" }
  [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  Write-Host "added to user PATH: $dir  (open a new terminal to pick it up)"
}

Write-Host ''
Write-Host 'verify with:  git help -a | findstr pullkeep'
Write-Host 'then in any repository:  git pullkeep --dry-run'
