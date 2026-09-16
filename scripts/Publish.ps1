#Requires -Version 5.1
<#
.SYNOPSIS
    Pushes the refs that carry the process to the remote.

.DESCRIPTION
    A land publishes on its own, so this exists for the case where that push was the thing that
    failed: the merge is already on the integration branch and only the remote is behind. Run it
    again once the remote is reachable, or after fetching and reconciling whatever it rejected.

    It is also the honest answer to "is anything unpublished?", because it is the same ref list the
    land uses -- the integration branch, the primary checkout's branch, and every lane's, read from
    process.json rather than named anywhere.

    Nothing here forces. A rejection means the remote moved, and the fix is to fetch, reconcile,
    re-verify and publish again.

.PARAMETER Root
    The repository. Defaults to the git root of the current directory.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'lib/Common.ps1')

$RepoRoot = Resolve-RepoRoot $Root
if (-not $RepoRoot) { Write-Host 'REFUSED: not a git repository.' -ForegroundColor Red; exit 2 }

$Process = Read-ProcessConfig $RepoRoot
if (-not $Process) { Write-Host 'REFUSED: no process.json. Run /reach:adopt first.' -ForegroundColor Red; exit 2 }

$integration = Get-Integration $Process
if (-not $integration.Publish) {
    # Asked for by name, so the setting is reported rather than obeyed silently -- someone running
    # this wants to know why nothing moved.
    Write-Host "REFUSED: integration.publish is false in process.json, so this repository does not publish." -ForegroundColor Red
    exit 2
}

exit (Invoke-ReachPublish -RepoRoot $RepoRoot -Process $Process)
