<#
.SYNOPSIS
    Checks the tools for the DevOps learning project: installed? which version? new enough?

.DESCRIPTION
    Read-only. It only runs version commands (like "git --version") and, with -CheckUpdates,
    "winget upgrade" to LIST available updates. It never installs or changes anything.
    Works in Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
    .\Check-DevTools.ps1                 # quick check
    .\Check-DevTools.ps1 -CheckUpdates   # also list newer versions available via winget
#>
[CmdletBinding()]
param(
    [switch]$CheckUpdates
)

# ---------------------------------------------------------------------------
# 1. What we need: display name, command, version arguments, minimum version,
#    winget package ID, and when it's needed in the project
# ---------------------------------------------------------------------------
$tools = @(
    [PSCustomObject]@{ Name = 'Git';            Command = 'git';       Arguments = @('--version');          Min = '2.40'; WingetId = 'Git.Git';                    When = 'Now' }
    [PSCustomObject]@{ Name = 'Python';         Command = 'python';    Arguments = @('--version');          Min = '3.12'; WingetId = 'Python.Python.3.13';         When = 'Now' }
    [PSCustomObject]@{ Name = 'Docker CLI';     Command = 'docker';    Arguments = @('--version');          Min = '24.0'; WingetId = 'Docker.DockerDesktop';       When = 'Now' }
    [PSCustomObject]@{ Name = 'Docker Compose'; Command = 'docker';    Arguments = @('compose', 'version'); Min = '2.20'; WingetId = 'Docker.DockerDesktop';       When = 'Now' }
    [PSCustomObject]@{ Name = 'kubectl';        Command = 'kubectl';   Arguments = @('version', '--client'); Min = '1.29'; WingetId = 'Kubernetes.kubectl';        When = 'Now' }
    [PSCustomObject]@{ Name = 'kind';           Command = 'kind';      Arguments = @('version');            Min = '0.23'; WingetId = 'Kubernetes.kind';            When = 'Now' }
    [PSCustomObject]@{ Name = 'Helm';           Command = 'helm';      Arguments = @('version', '--short'); Min = '3.14'; WingetId = 'Helm.Helm';                  When = 'Now' }
    [PSCustomObject]@{ Name = 'Terraform';      Command = 'terraform'; Arguments = @('version');            Min = '1.6';  WingetId = 'Hashicorp.Terraform';        When = 'Now' }
    [PSCustomObject]@{ Name = 'PowerShell 7';   Command = 'pwsh';      Arguments = @('--version');          Min = '7.4';  WingetId = 'Microsoft.PowerShell';       When = 'Now' }
    [PSCustomObject]@{ Name = 'VS Code';        Command = 'code';      Arguments = @('--version');          Min = '1.90'; WingetId = 'Microsoft.VisualStudioCode'; When = 'Now' }
    [PSCustomObject]@{ Name = 'GitHub CLI';     Command = 'gh';        Arguments = @('--version');          Min = '2.40'; WingetId = 'GitHub.cli';                 When = 'Optional' }
    [PSCustomObject]@{ Name = 'Azure CLI';      Command = 'az';        Arguments = @('version');            Min = '2.60'; WingetId = 'Microsoft.AzureCLI';         When = 'Later' }
)

# VS Code extensions: display name -> accepted extension IDs (first one is the one we suggest)
$extensions = [ordered]@{
    'Python'         = @('ms-python.python')
    'Docker'         = @('ms-azuretools.vscode-docker', 'ms-azuretools.vscode-containers')
    'Terraform'      = @('hashicorp.terraform')
    'Kubernetes'     = @('ms-kubernetes-tools.vscode-kubernetes-tools')
    'GitHub Actions' = @('github.vscode-github-actions')
    'YAML'           = @('redhat.vscode-yaml')
}

# ---------------------------------------------------------------------------
# 2. Helper functions
# ---------------------------------------------------------------------------
function Get-ToolVersion {
    <# Runs the tool's version command and returns the first "x.y" or "x.y.z" it finds,
       or $null if the tool is missing or prints no version. #>
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        return $null
    }

    try {
        $output = & $Command @Arguments 2>&1 | Out-String
    }
    catch {
        return $null
    }

    # e.g. "git version 2.47.0.windows.1" -> "2.47.0"
    #      "kind v0.24.0 go1.22.6"        -> "0.24.0"
    if ($output -match '(\d+\.\d+(\.\d+)?)') {
        return $Matches[1]
    }
    return $null   # e.g. Windows' "python" shortcut that only points to the Microsoft Store
}

function Test-DockerEngine {
    <# Docker Desktop can be installed but not running. "docker info" fails if the engine is off. #>
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $false
    }
    $null = & docker info --format '{{.ServerVersion}}' 2>&1
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------------------
# 3. Check every tool
# ---------------------------------------------------------------------------
Write-Host "`nChecking tools (this can take a few seconds)...`n" -ForegroundColor Cyan

$results = @(foreach ($t in $tools) {
    $version = Get-ToolVersion -Command $t.Command -Arguments $t.Arguments

    if (-not $version) {
        $status = 'MISSING'
        $shown  = '-'
    }
    elseif ([version]$version -lt [version]$t.Min) {
        $status = 'TOO OLD'
        $shown  = $version
    }
    else {
        $status = 'OK'
        $shown  = $version
    }

    [PSCustomObject]@{
        Tool     = $t.Name
        Needed   = $t.When
        Version  = $shown
        Minimum  = $t.Min
        Status   = $status
        WingetId = $t.WingetId
    }
})

# Is the Docker engine actually running?
if (Test-DockerEngine) { $engineStatus = 'OK' } else { $engineStatus = 'NOT RUNNING' }
$results += [PSCustomObject]@{
    Tool     = 'Docker engine'
    Needed   = 'Now'
    Version  = '-'
    Minimum  = '-'
    Status   = $engineStatus
    WingetId = 'Docker.DockerDesktop'
}

# ---------------------------------------------------------------------------
# 4. Show the results, coloured by status
# ---------------------------------------------------------------------------
$format = '{0,-16} {1,-9} {2,-10} {3,-8} {4}'
Write-Host ($format -f 'Tool', 'Needed', 'Version', 'Minimum', 'Status')
Write-Host ($format -f '----', '------', '-------', '-------', '------')

foreach ($r in $results) {
    if ($r.Status -eq 'OK')          { $color = 'Green' }
    elseif ($r.Needed -ne 'Now')     { $color = 'DarkGray' }   # optional/later tools: no alarm
    elseif ($r.Status -eq 'MISSING') { $color = 'Red' }
    else                             { $color = 'Yellow' }

    Write-Host ($format -f $r.Tool, $r.Needed, $r.Version, $r.Minimum, $r.Status) -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# 5. Tell the user exactly what to run for anything needed now
# ---------------------------------------------------------------------------
$toFix = @($results | Where-Object { $_.Status -ne 'OK' -and $_.Needed -eq 'Now' })

if ($toFix.Count -gt 0) {
    Write-Host "`nTo fix what's needed now, run:" -ForegroundColor Cyan
    $commands = foreach ($r in $toFix) {
        switch ($r.Status) {
            'MISSING'     { "  winget install --id $($r.WingetId) -e" }
            'TOO OLD'     { "  winget upgrade --id $($r.WingetId) -e" }
            'NOT RUNNING' { "  Start Docker Desktop, wait for 'Engine running', then run this check again" }
        }
    }
    $commands | Select-Object -Unique | ForEach-Object { Write-Host $_ }
    Write-Host "`nAfter installing, open a NEW terminal so the new commands are found." -ForegroundColor DarkGray
}
else {
    Write-Host "`nEverything needed now is installed and new enough." -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 6. VS Code extensions
# ---------------------------------------------------------------------------
if (Get-Command code -ErrorAction SilentlyContinue) {
    $installedExtensions = & code --list-extensions 2>$null

    Write-Host "`nVS Code extensions:" -ForegroundColor Cyan
    foreach ($name in $extensions.Keys) {
        $ids   = $extensions[$name]
        $found = @($ids | Where-Object { $installedExtensions -contains $_ })

        if ($found.Count -gt 0) {
            Write-Host ('  {0,-16} OK' -f $name) -ForegroundColor Green
        }
        else {
            Write-Host ('  {0,-16} MISSING  ->  code --install-extension {1}' -f $name, $ids[0]) -ForegroundColor Yellow
        }
    }
}

# ---------------------------------------------------------------------------
# 7. Optional: list newer versions available via winget (read-only)
# ---------------------------------------------------------------------------
if ($CheckUpdates) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "`nLooking for newer versions with winget (nothing is installed)..." -ForegroundColor Cyan
        $upgradeList = winget upgrade 2>$null | Out-String
        $updates = @($tools.WingetId | Select-Object -Unique |
            Where-Object { $upgradeList -match [regex]::Escape($_) })

        if ($updates.Count -gt 0) {
            Write-Host 'Newer versions available. To update, run:' -ForegroundColor Yellow
            $updates | ForEach-Object { Write-Host "  winget upgrade --id $_ -e" }
        }
        else {
            Write-Host 'No updates found for these tools.' -ForegroundColor Green
        }
    }
    else {
        Write-Host "`nwinget not found, so the update check was skipped." -ForegroundColor DarkGray
    }
}

Write-Host ''
