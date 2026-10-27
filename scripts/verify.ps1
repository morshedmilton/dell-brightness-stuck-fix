<#
.SYNOPSIS
    Post-fix verification for the Dell brightness issue.

.DESCRIPTION
    Runs after installing the Dell NVIDIA driver package. Prints PASS / FAIL
    for every condition that must hold for the backlight path to work.

    Exit code 0 = all checks passed, 1 = something is still broken.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\verify.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'
$fail = 0

function Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        Write-Host ('  [PASS] ' + $Name) -ForegroundColor Green
    } else {
        Write-Host ('  [FAIL] ' + $Name) -ForegroundColor Red
        $script:fail++
    }
    if ($Detail) { Write-Host ('         ' + $Detail) -ForegroundColor DarkGray }
}

Write-Host ''
Write-Host 'Brightness fix - verification' -ForegroundColor Cyan
Write-Host ('=' * 46)

# --- 1. no display adapter in an error state -------------------------------
$adapters = Get-CimInstance Win32_VideoController
$bad      = @($adapters | Where-Object { $_.ConfigManagerErrorCode -ne 0 })
Check 'No display adapter reports an error code' ($bad.Count -eq 0) `
      (@($adapters | ForEach-Object { $_.Name + ' -> ' + $(if ($_.ConfigManagerErrorCode -eq 0) { 'OK' } else { 'code ' + $_.ConfigManagerErrorCode }) }) -join ' | ')

# --- 2. NVIDIA adapter is present and healthy -----------------------------
$nv = $adapters | Where-Object { $_.Name -match 'NVIDIA' }
Check 'NVIDIA GPU is bound to a real driver' ($null -ne $nv -and $nv.DriverVersion -notmatch '^10\.0\.') `
      (@($(if ($nv) { $nv.Name + ' | driver ' + $nv.DriverVersion } else { 'no NVIDIA adapter enumerated' })) -join '')

# --- 3. no "Microsoft Basic Display Adapter" left behind ------------------
$basic = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'Basic Display' }
Check 'No "Microsoft Basic Display Adapter" remains' ($null -eq $basic) `
      (@($basic | ForEach-Object { $_.FriendlyName + ' (' + $_.Problem + ')' }) -join ', ')

# --- 4. NVPCF -------------------------------------------------------------
$npc = Get-PnpDevice -InstanceId 'ACPI\NVDA0820\NPCF'
if ($npc) {
    Check 'NVPCF device installed and started' ($npc.Problem -eq 'CM_PROB_NONE') `
          ('status ' + $npc.Status + ' / problem ' + $npc.Problem)
} else {
    Write-Host '  [SKIP] NVPCF device not present on this machine' -ForegroundColor DarkGray
}

# --- 5. NVIDIA display container service ---------------------------------
$svc = Get-Service -Name 'NVDisplay.ContainerLocalSystem'
Check 'NVDisplay.ContainerLocalSystem is running' ($svc -and $svc.Status -eq 'Running') `
      $(if ($svc) { 'status ' + $svc.Status } else { 'service missing' })

# --- 6. backlight interface exists and responds ---------------------------
$mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness
Check 'Backlight interface exposed (WmiMonitorBrightness)' ($null -ne $mon) `
      $(if ($mon) { 'current = ' + $mon.CurrentBrightness + '%' } else { 'no instance' })

if ($mon) {
    $before = $mon.CurrentBrightness
    $meth   = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods
    $t1 = [int]([Math]::Max(1, [Math]::Min(99, $before - 20)))
    Invoke-CimMethod -InputObject $meth -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $t1 } | Out-Null
    Start-Sleep -Milliseconds 900
    $after = (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness).CurrentBrightness
    Invoke-CimMethod -InputObject $meth -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $before } | Out-Null
    Check 'ACPI accepts a brightness change' ($after -eq $t1) `
          ('wrote ' + $t1 + '%, read back ' + $after + '%  ->  now confirm the SCREEN actually dimmed')
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'ALL CHECKS PASSED - now move the brightness slider and watch the panel.' -ForegroundColor Green
    exit 0
} else {
    Write-Host ($fail.ToString() + ' check(s) failed - do not stop here.') -ForegroundColor Red
    exit 1
}
