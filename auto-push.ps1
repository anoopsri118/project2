param(
    [string]$RepoPath = $PSScriptRoot,
    [int]$QuietSeconds = 2
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GitExe {
    $candidates = @(
        "git",
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files\Git\bin\git.exe"
    )

    foreach ($candidate in $candidates) {
        try {
            if ($candidate -eq "git") {
                $resolved = (Get-Command git -ErrorAction Stop).Source
                if ($resolved) {
                    return $resolved
                }
            } elseif (Test-Path $candidate) {
                return $candidate
            }
        } catch {
        }
    }

    throw "Git executable not found."
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Args
    )

    & $script:GitExe -C $script:RepoPath @Args
    if ($LASTEXITCODE -ne 0) {
        throw "Git command failed: git $($Args -join ' ')"
    }
}

function Test-IgnoredPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $repoRoot = [System.IO.Path]::GetFullPath($script:RepoPath)

    $relativePath = $fullPath.Substring($repoRoot.Length).TrimStart('\')
    if (-not $relativePath) {
        return $true
    }

    $ignoredPrefixes = @(
        ".git\",
        "__pycache__\",
        ".pytest_cache\",
        ".venv\"
    )

    foreach ($prefix in $ignoredPrefixes) {
        if ($relativePath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

$script:RepoPath = [System.IO.Path]::GetFullPath($RepoPath)
$script:GitExe = Get-GitExe
$script:Pending = $false
$script:LastEventTime = Get-Date

Write-Host "Watching $script:RepoPath for changes..."
Write-Host "Press Ctrl+C to stop."

$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = $script:RepoPath
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true
$watcher.NotifyFilter = [System.IO.NotifyFilters]"FileName, DirectoryName, LastWrite"

$action = {
    $changedPath = $Event.SourceEventArgs.FullPath
    if (-not (Test-IgnoredPath -Path $changedPath)) {
        $script:Pending = $true
        $script:LastEventTime = Get-Date
    }
}

$subscriptions = @(
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $action,
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $action
)

try {
    while ($true) {
        Start-Sleep -Seconds 1

        if (-not $script:Pending) {
            continue
        }

        $elapsed = (Get-Date) - $script:LastEventTime
        if ($elapsed.TotalSeconds -lt $QuietSeconds) {
            continue
        }

        $script:Pending = $false

        try {
            Invoke-Git -Args @("add", "-A")

            & $script:GitExe -C $script:RepoPath diff --cached --quiet
            if ($LASTEXITCODE -eq 0) {
                continue
            }

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Invoke-Git -Args @("commit", "-m", "Auto update $timestamp")
            Invoke-Git -Args @("push")
            Write-Host "Pushed changes at $timestamp"
        } catch {
            Write-Warning $_
        }
    }
} finally {
    foreach ($subscription in $subscriptions) {
        Unregister-Event -SourceIdentifier $subscription.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $subscription.Id -Force -ErrorAction SilentlyContinue
    }

    $watcher.Dispose()
}
