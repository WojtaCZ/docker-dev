<#
.SYNOPSIS
    WSL shim: delegates to scripts/dev-up.sh running inside WSL2.

.DESCRIPTION
    USB probe passthrough requires Linux device nodes, so the real work happens in
    WSL2. Attach the probe to WSL first with usbipd:

        usbipd list
        usbipd bind   --busid <busid>
        usbipd attach --wsl --busid <busid>

    Then run this script. /dev/bus/usb, /dev/input and /dev/snd are bind-mounted
    live with wildcard device-cgroup rules, so probes and input/MIDI devices attached
    to WSL AFTER the container is running are picked up with no restart. Flat nodes
    (/dev/ttyACM*, /dev/ttyUSB*, /dev/hidraw*) are mknod'd in by scripts/dev-attach.sh
    (once at start; run it again after a replug). usbipd attach is still needed once
    per device per WSL boot; that step is what gets it into WSL's kernel at all and is
    outside the container's control.

    The project is mounted at /workspaces/<name>-<hash> inside the container.

.EXAMPLE
    .\scripts\dev-up.ps1
    .\scripts\dev-up.ps1 -Workspace C:\code\firmware -Rebuild
    .\scripts\dev-up.ps1 -Doctor
    .\scripts\dev-up.ps1 -Ports "3000 8080" -NoTrail
#>
[CmdletBinding()]
param(
    [string]$Workspace = (Get-Location).Path,
    [string]$Image,
    [string]$Container,
    [switch]$NoBuild,
    [switch]$NoPull,
    [switch]$Rebuild,
    [switch]$NoCacheVolumes,
    [switch]$SkipUpdate,
    [switch]$Doctor,
    [switch]$NoTrail,
    [switch]$NoServices,
    [switch]$NoClipboard,
    [string]$Probe,
    [string]$Ports,
    [string]$PortRange,
    [string]$Assets,
    [string]$StateDir,
    [string]$TelinkSdk,
    [string]$CubeClt,
    [string]$CubeWba
)

$ErrorActionPreference = "Stop"

$env:DEV_NO_BUILD         = if ($NoBuild)         { "1" } else { "0" }
$env:DEV_NO_PULL          = if ($NoPull)          { "1" } else { "0" }
$env:DEV_REBUILD          = if ($Rebuild)         { "1" } else { "0" }
$env:DEV_NO_CACHE_VOLUMES = if ($NoCacheVolumes)  { "1" } else { "0" }
$env:DEV_SKIP_UPDATE      = if ($SkipUpdate)      { "1" } else { "0" }
$env:DEV_DOCTOR           = if ($Doctor)          { "1" } else { "0" }
$env:DEV_NO_SERVICES      = if ($NoServices)      { "1" } else { "0" }
$env:DEV_TRAIL            = if ($NoTrail)         { "0" } else { "1" }
$env:DEV_CLIPBOARD        = if ($NoClipboard)     { "0" } else { "1" }
if ($Image)     { $env:DEV_IMAGE      = $Image }
if ($Container) { $env:DEV_CONTAINER  = $Container }
if ($Probe)     { $env:DEV_PROBE      = $Probe }
if ($Ports)     { $env:DEV_PORTS      = $Ports }
if ($PortRange) { $env:DEV_PORT_RANGE = $PortRange }
if ($Assets)    { $env:DEV_ASSETS     = $Assets }
if ($StateDir)  { $env:DEV_STATE_DIR  = $StateDir }
if ($TelinkSdk) { $env:DEV_TELINK_SDK = $TelinkSdk }
if ($CubeClt)   { $env:DEV_CUBECLT    = $CubeClt }
if ($CubeWba)   { $env:DEV_CUBEWBA    = $CubeWba }

# WSLENV makes these visible to the Linux side of the call.
$env:WSLENV = "DEV_NO_BUILD:DEV_NO_PULL:DEV_REBUILD:DEV_NO_CACHE_VOLUMES:" +
              "DEV_SKIP_UPDATE:DEV_DOCTOR:DEV_NO_SERVICES:DEV_TRAIL:DEV_CLIPBOARD:" +
              "DEV_IMAGE:DEV_CONTAINER:DEV_PROBE:DEV_PORTS:DEV_PORT_RANGE:DEV_ASSETS:DEV_STATE_DIR:" +
              "DEV_TELINK_SDK:DEV_CUBECLT:DEV_CUBEWBA"

$wslWorkspace = wsl --exec wslpath -a $Workspace
if ($LASTEXITCODE -ne 0) { throw "could not translate '$Workspace' to a WSL path" }

wsl --cd "$PSScriptRoot/.." -- bash scripts/dev-up.sh $wslWorkspace
