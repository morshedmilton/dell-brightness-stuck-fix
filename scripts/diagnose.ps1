<#
.SYNOPSIS
    Read-only diagnostic for "brightness does not change" on Dell laptops
    with NVIDIA Advanced Optimus (eDP MUX) - e.g. Dell G15 5530.

.DESCRIPTION
    Collects every data point needed to prove or disprove the NVPCF theory:

      1. Model / BIOS
      2. Display adapters + Windows error codes
      3. PnP display devices
      4. NVIDIA Platform Controllers and Framework (ACPI\NVDA0820\NPCF)
      5. WMI backlight state (and optional live write test)
      6. Installed NVIDIA components
      7. eDP MUX indicator in the Intel display driver key
      8. Display driver packages present in the driver store

    Writes nothing except an optional brightness value when -TestBrightness
    is used (restored to its original value afterwards).

.PARAMETER TestBrightness
    Also performs a live backlight write test (100 -> 50 -> original).
    Watch the screen while it runs.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\diagnose.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\diagnose.ps1 -TestBrightness
#>
[CmdletBinding()]
param(
    [switch]$TestBrightness
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=== ' + $Title + ' ' + ('=' * [Math]::Max(0, 60 - $Title.Length))) -ForegroundColor Cyan
}

function Write-Item {
    param([string]$Name, $Value)
    Write-Host ('  {0,-34} {1}' -f $Name, $Value)
}

# ---------------------------------------------------------------- 1. machine
Write-Section '1. MACHINE'
$cs   = Get-CimInstance Win32_ComputerSystem
$bios = Get-CimInstance Win32_BIOS
$os   = Get-CimInstance Win32_OperatingSystem
Write-Item 'Manufacturer / Model' ($cs.Manufacturer + ' ' + $cs.Model)
Write-Item 'BIOS'                 ($bios.SMBIOSBIOSVersion + '  (' + $bios.ReleaseDate + ')')
Write-Item 'Windows'              ($os.Caption + ' build ' + $os.BuildNumber)

# --------------------------------------------------------- 2. display adapters
Write-Section '2. DISPLAY ADAPTERS'
$vc = Get-CimInstance Win32_VideoController
foreach ($v in $vc) {
    Write-Host ('  ' + $v.Name) -ForegroundColor Yellow
    Write-Item '  status / code' ("{0} / {1}" -f $v.Status, $v.ConfigManagerErrorCode)
    Write-Item '  driver'        ("{0}  {1}" -f $v.DriverVersion, $v.DriverDate)
    Write-Item '  pnp id'        $v.PNPDeviceID
}
if (-not $vc) { Write-Host '  (none)' }

# ------------------------------------------------------------- 3. pnp display
Write-Section '3. PNP DISPLAY DEVICES  (Code 10 / CM_PROB_FAILED_START is the red flag)'
Get-PnpDevice -Class Display | ForEach-Object {
    Write-Host ('  {0,-10} {1}' -f $_.Status, $_.FriendlyName)
    Write-Item '  problem' ("{0} ({1})" -f $_.Problem, $_.ProblemDescription)
    Write-Item '  instance' $_.InstanceId
}

# ------------------------------------------------------------------ 4. NVPCF
Write-Section '4. NVIDIA PLATFORM CONTROLLERS AND FRAMEWORK  (the usual culprit)'
$npc = Get-PnpDevice -InstanceId 'ACPI\NVDA0820\NPCF'
if ($npc) {
    Write-Item 'status'   $npc.Status
    Write-Item 'problem'  ("{0} ({1})" -f $npc.Problem, $npc.ProblemDescription)
    if ($npc.Problem -eq 'CM_PROB_FAILED_INSTALL') {
        Write-Host '  -> BROKEN: this device is in failed-install state.' -ForegroundColor Red
        Write-Host '  -> On MUX / Advanced-Optimus laptops the backlight path runs through it.' -ForegroundColor Red
    } elseif ($npc.Status -eq 'OK') {
        Write-Host '  -> OK' -ForegroundColor Green
    }
} else {
    Write-Host '  device not present on this machine (no ACPI\NVDA0820 node)' -ForegroundColor DarkGray
}

# --------------------------------------------------------------- 5. backlight
Write-Section '5. BACKLIGHT (WMI / ACPI)'
$mon = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness
if ($mon) {
    Write-Item 'instance'          $mon.InstanceName
    Write-Item 'current brightness' $mon.CurrentBrightness
    Write-Item 'supported levels'   $mon.Level.Count
    $meth = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightnessMethods
    Write-Item 'write method'       ($(if ($meth) { 'present' } else { 'MISSING' }))
} else {
    Write-Host '  no WmiMonitorBrightness instance - driver exposes no backlight control'
}

if ($TestBrightness -and $meth) {
    Write-Host ''
    Write-Host '  live write test - WATCH THE SCREEN' -ForegroundColor Yellow
    $original = $mon.CurrentBrightness
    foreach ($v in @(100, 50)) {
        Invoke-CimMethod -InputObject $meth -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $v } | Out-Null
        Start-Sleep -Milliseconds 1200
        $read = (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness).CurrentBrightness
        Write-Host ('    set {0,3}%  ->  read back {1,3}%' -f $v, $read)
    }
    Invoke-CimMethod -InputObject $meth -MethodName WmiSetBrightness -Arguments @{ Timeout = 1; Brightness = $original } | Out-Null
    Write-Host ''
    Write-Host '  If the number changes but the screen does NOT, the ACPI path is a dead end'
    Write-Host '  and the panel backlight is owned by the other GPU path (NVPCF).'
    Write-Host ('  restored to ' + $original + '%')
}

# ------------------------------------------------------- 6. installed nvidia
Write-Section '6. INSTALLED NVIDIA COMPONENTS'
Write-Host '  (a "Platform Controllers and Framework" entry here while ACPI\NVDA0820 is'
Write-Host '   in failed-install state is the classic half-installed signature)'
$paths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$found = Get-ItemProperty $paths | Where-Object { $_.DisplayName -match 'NVIDIA' } |
         Select-Object DisplayName, DisplayVersion
if ($found) { $found | Format-Table -AutoSize | Out-String -Width 120 | Write-Host } else { Write-Host '  none' }

$svc = Get-Service -Name 'NVDisplay.ContainerLocalSystem'
Write-Item 'NVDisplay service' ($(if ($svc) { $svc.Status } else { 'NOT PRESENT' }))

# ---------------------------------------------------------------- 7. eDP MUX
Write-Section '7. eDP MUX INDICATOR (Intel display driver key)'
$cls = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$muxFound = $false
Get-ChildItem $cls | ForEach-Object {
    $p = Get-ItemProperty $_.PSPath
    if ($p.DriverDesc -match 'Intel') {
        $mux = $p.ParadeMuxEdpLinkRateDataReloadTrigger
        Write-Item ('key ' + $_.PSChildName) $p.DriverDesc
        Write-Item '  ParadeMux...ReloadTrigger' $(if ($null -ne $mux) { $mux } else { '(absent)' })
        if ($null -ne $mux) { $muxFound = $true }
    }
}
if ($muxFound) {
    Write-Host '  -> MUX hardware present: brightness ownership can move between GPUs.' -ForegroundColor Yellow
} else {
    Write-Host '  -> no MUX hint found (this guide is still worth trying, but root cause may differ)' -ForegroundColor DarkGray
}

# ------------------------------------------------------ 8. driver store state
Write-Section '8. DISPLAY-CLASS DRIVERS WINDOWS HAS BOUND'
Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" |
    Select-Object DeviceName, DriverProviderName, DriverVersion, InfName |
    Format-Table -AutoSize | Out-String -Width 130 | Write-Host

Write-Host ''
Write-Host 'Done. Read section 3, 4 and 5 together - that is the whole diagnosis.' -ForegroundColor Cyan
