param(
    [string]$RepoPath = $PSScriptRoot,
    [int]$PollSeconds = 3
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

    $output = & $script:GitExe -C $script:RepoPath @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }

    return $output
}

$script:RepoPath = [System.IO.Path]::GetFullPath($RepoPath)
$script:GitExe = Get-GitExe

Write-Host "Watching $script:RepoPath for git changes every $PollSeconds seconds..."
Write-Host "Press Ctrl+C to stop."

while ($true) {
    Start-Sleep -Seconds $PollSeconds

    try {
        $status = Invoke-Git -Args @("status", "--porcelain")
        if (-not $status) {
            continue
        }

        Invoke-Git -Args @("add", "-A") | Out-Null

        & $script:GitExe -C $script:RepoPath diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            continue
        }

        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Invoke-Git -Args @("commit", "-m", "Auto update $timestamp") | Out-Null
        Invoke-Git -Args @("push") | Out-Null
        Write-Host "Pushed changes at $timestamp"
    } catch {
        Write-Warning $_
    }
}
