param(
    [switch]$ContinueAfterPrompt,
    [switch]$Dd32DirectedPreflight,
    [switch]$Dd34LastTxnPreflight,
    [switch]$SlowPostPromptFdc,
    [switch]$SlowCallerReturnPath,
    [switch]$SlowCallerInjectError,
    [switch]$ValidWritePreflight,
    [switch]$WriteSectorPreflight,
    [switch]$HardwareMemoryLayout,
    [ValidateRange(0, 255)]
    [int]$SlowWorkspace0e = 0,
    [string]$ModelSim,
    [string]$BootRom,
    [string]$DreamMonitor,
    [string]$DreamDisk
)

$ErrorActionPreference = "Stop"

$repo = Split-Path -Parent $PSScriptRoot
$simRoot = Join-Path $repo "sim"
$work = Join-Path $simRoot "work"

if (!$ModelSim) { $ModelSim = "D:\intelFPGA_lite\17.0\modelsim_ase\win32aloem" }
if (!$BootRom) { $BootRom = Join-Path $repo "roms\sorcerer_boot.rom" }
if (!$DreamMonitor) { $DreamMonitor = "D:\Users\Paul\Sorcerer\DreamDisk\Monitor\scuamon64_v34_dreamdisk.rom" }
if (!$DreamDisk) { $DreamDisk = "D:\Users\Paul\Sorcerer\DreamDisk\DSK\sorcerer_dreamdisk_master.dsk" }

if (!(Test-Path $ModelSim)) {
    throw "ModelSim not found at $ModelSim"
}
if (!(Test-Path $BootRom)) {
    throw "Boot ROM bundle not found at $BootRom"
}
if (!(Test-Path $DreamMonitor)) {
    throw "DreamDisk monitor ROM not found at $DreamMonitor"
}
if (!(Test-Path $DreamDisk)) {
    throw "DreamDisk image not found at $DreamDisk"
}

function Export-MemHex {
    param(
        [Parameter(Mandatory=$true)][string]$InputPath,
        [Parameter(Mandatory=$true)][string]$OutputPath
    )

    $bytes = [System.IO.File]::ReadAllBytes($InputPath)
    $lines = New-Object string[] $bytes.Length
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        $lines[$i] = $bytes[$i].ToString("X2")
    }
    [System.IO.File]::WriteAllLines($OutputPath, $lines)
}

Push-Location $simRoot
try {
    Export-MemHex -InputPath $BootRom -OutputPath (Join-Path $simRoot "boot_rom.mem")
    Export-MemHex -InputPath $DreamMonitor -OutputPath (Join-Path $simRoot "dream_monitor.mem")
    Copy-Item -LiteralPath $DreamDisk -Destination (Join-Path $simRoot "dreamdisk_master.dskbin") -Force

    if (Test-Path $work) {
        $resolvedWork = (Resolve-Path -LiteralPath $work).Path
        $resolvedSimRoot = (Resolve-Path -LiteralPath $simRoot).Path
        if (!$resolvedWork.StartsWith($resolvedSimRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove work directory outside sim root: $resolvedWork"
        }
        Remove-Item -Recurse -Force $work
    }

    & "$ModelSim\vlib.exe" work
    if ($LASTEXITCODE -ne 0) { throw "vlib failed with exit code $LASTEXITCODE" }

    & "$ModelSim\vcom.exe" `
        "..\rtl\T80\T80_Pack.vhd" `
        "..\rtl\T80\T80_ALU.vhd" `
        "..\rtl\T80\T80_MCode.vhd" `
        "..\rtl\T80\T80_Reg.vhd" `
        "..\rtl\T80\T80.vhd" `
        "..\rtl\T80\T80s.vhd"
    if ($LASTEXITCODE -ne 0) { throw "vcom failed with exit code $LASTEXITCODE" }

    & "$ModelSim\vlog.exe" -sv -permissive -suppress 2388 "..\rtl\gen_uart.v" "..\rtl\sorcerer.v"
    if ($LASTEXITCODE -ne 0) { throw "vlog RTL failed with exit code $LASTEXITCODE" }

    & "$ModelSim\vlog.exe" -sv "tb_dreamdisk.sv"
    if ($LASTEXITCODE -ne 0) { throw "vlog failed with exit code $LASTEXITCODE" }

    $vsimArgs = @("-batch", "-quiet", "-nostdout", "-l", "dreamdisk_transcript.log")
    if ($ContinueAfterPrompt) { $vsimArgs += "-gCONTINUE_AFTER_PROMPT=1" }
    if ($Dd32DirectedPreflight) { $vsimArgs += "-gDD32_DIRECTED_PREFLIGHT=1" }
    if ($Dd34LastTxnPreflight) { $vsimArgs += "-gDD34_LAST_TXN_PREFLIGHT=1" }
    if ($SlowPostPromptFdc -or $SlowCallerReturnPath) {
        $vsimArgs += "-gSLOW_POST_PROMPT_FDC=1"
        $workspace0e = if ($SlowCallerReturnPath) { 8 } else { $SlowWorkspace0e }
        $vsimArgs += "-gSLOW_WORKSPACE_0E=$workspace0e"
    }
    if ($SlowCallerReturnPath) { $vsimArgs += "-gSLOW_CALLER_RETURN_PATH=1" }
    if ($SlowCallerInjectError) { $vsimArgs += "-gSLOW_CALLER_INJECT_ERROR=1" }
    if ($ValidWritePreflight) { $vsimArgs += "-gVALID_WRITE_PREFLIGHT=1" }
    if ($WriteSectorPreflight) { $vsimArgs += "-gWRITE_SECTOR_PREFLIGHT=1" }
    if ($HardwareMemoryLayout) {
        $vsimArgs += "-gSIM_RAM_TOP_EXCLUSIVE=49152"
        $vsimArgs += "-gMAME_MEMORY_LAYOUT=0"
    }
    $vsimArgs += @("tb_dreamdisk", "-do", "set NumericStdNoWarnings 1; run -all; quit -f")
    & "$ModelSim\vsim.exe" @vsimArgs
    if ($LASTEXITCODE -ne 0) { throw "vsim failed with exit code $LASTEXITCODE" }
    if (Select-String -Path (Join-Path $simRoot "dreamdisk_transcript.log") -SimpleMatch "# ** Fatal:" -Quiet) {
        throw "ModelSim reported a fatal assertion; see sim/dreamdisk_transcript.log"
    }
} finally {
    Pop-Location
}
