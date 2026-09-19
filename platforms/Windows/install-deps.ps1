<#
.SYNOPSIS
    Installs the Windows runtime DLLs (SDL2, audio codecs, curl, zlib) needed to
    build and run Carnifex Engine.

.DESCRIPTION
    Headers and import libraries for these dependencies live under
    platforms/Windows/, but the DLLs are not versioned (*.dll is gitignored).
    This script extracts them from the IronWail commit in this repository's
    history that still ships them, so they always match the bundled headers.
    DLLs that are already present are kept unless -Force is given.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File platforms\Windows\install-deps.ps1
#>
param(
    # Commit that still contains Windows/<dependency>/*.dll. Detected automatically when omitted.
    [string]$SourceCommit,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$depDirs = 'Windows/SDL2', 'Windows/codecs', 'Windows/curl', 'Windows/zlib'

$repoRoot = git -C $PSScriptRoot rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0) { throw "Not inside a git repository: $PSScriptRoot" }
$repoRoot = $repoRoot.Trim()

if (-not $SourceCommit) {
    # The DLLs were dropped from version control during the Carnifex reorganization;
    # the parent of that commit still has them.
    $deleteCommit = git -C $repoRoot log -1 --diff-filter=D --format=%H HEAD -- Windows/SDL2/lib64/SDL2.dll
    if (-not $deleteCommit) {
        throw 'Could not find the DLLs in the git history (shallow clone?). Run "git fetch --unshallow" or pass -SourceCommit.'
    }
    $SourceCommit = "$($deleteCommit.Trim())^"
}

$dlls = @(git -C $repoRoot ls-tree -r --name-only $SourceCommit -- $depDirs | Where-Object { $_ -like '*.dll' })
if ($dlls.Count -eq 0) { throw "No DLLs found in $SourceCommit" }

$pending = @($dlls | Where-Object { $Force -or -not (Test-Path (Join-Path $repoRoot "platforms/$_")) })
if ($pending.Count -eq 0) {
    Write-Host "All $($dlls.Count) Windows DLLs are already installed."
    return
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("carnifex-deps-" + [guid]::NewGuid())
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'deps.zip'
    git -C $repoRoot archive --format=zip -o $zip $SourceCommit -- $pending
    if ($LASTEXITCODE -ne 0) { throw 'git archive failed' }
    Expand-Archive -Path $zip -DestinationPath $tmp

    foreach ($path in $pending) {
        $dest = Join-Path $repoRoot "platforms/$path"
        New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
        Copy-Item -Force (Join-Path $tmp $path) $dest
        Write-Host "installed platforms/$path"
    }
} finally {
    Remove-Item -Recurse -Force $tmp
}

Write-Host "$($pending.Count) DLL(s) installed from $SourceCommit."
