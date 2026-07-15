param(
    [string]$RemoteUser = "Paul",
    [string]$RemoteHost = "192.168.1.113",
    [string]$RemoteRepo = "D:\Users\Paul\Documents\Exidy Sorcerer",
    [string]$RemoteModelSim = "D:\intelFPGA_lite\17.0\modelsim_ase\win32aloem",
    [string]$DreamMonitor = "D:\Users\Paul\Sorcerer\DreamDisk\Monitor\scuamon64_v34_dreamdisk.rom",
    [string]$DreamDisk = "D:\Users\Paul\Sorcerer\DreamDisk\DSK\sorcerer_dreamdisk_master.dsk",
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
    [switch]$NoSync,
    [switch]$NoFetch
)

$ErrorActionPreference = "Stop"

function Run-Logged {
    param([string[]]$Command)
    Write-Host "> $($Command -join ' ')"
    & $Command[0] @($Command | Select-Object -Skip 1)
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE" }
}

function ConvertTo-PowerShellEncodedCommand {
    param([string]$Command)
    [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$bootRom = Join-Path $repoRoot "roms\sorcerer_boot.rom"

foreach ($path in @($bootRom, $DreamMonitor, $DreamDisk)) {
    if (!(Test-Path -LiteralPath $path)) { throw "Required simulation input not found: $path" }
}

$remoteInputDir = Join-Path $RemoteRepo "sim\inputs"
$prepareCommand = @"
`$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path '$RemoteRepo', (Join-Path '$RemoteRepo' 'rtl'), (Join-Path '$RemoteRepo' 'scripts'), (Join-Path '$RemoteRepo' 'roms'), (Join-Path '$RemoteRepo' 'sim'), '$remoteInputDir' | Out-Null
"@
$encodedPrepare = ConvertTo-PowerShellEncodedCommand $prepareCommand
& ssh "${RemoteUser}@${RemoteHost}" powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedPrepare
if ($LASTEXITCODE -ne 0) { throw "Unable to prepare remote simulation directories" }

if (!$NoSync) {
    Push-Location $repoRoot
    try {
        Run-Logged @("scp", "rtl\gen_uart.v", "rtl\sorcerer.v", "${RemoteUser}@${RemoteHost}:$RemoteRepo/rtl/")
        Run-Logged @("scp", "-r", "rtl\T80", "${RemoteUser}@${RemoteHost}:$RemoteRepo/rtl/")
        Run-Logged @("scp", "sim\tb_dreamdisk.sv", "${RemoteUser}@${RemoteHost}:$RemoteRepo/sim/")
        Run-Logged @("scp", "scripts\run_dreamdisk_sim.ps1", "${RemoteUser}@${RemoteHost}:$RemoteRepo/scripts/")
        Run-Logged @("scp", $bootRom, "${RemoteUser}@${RemoteHost}:$RemoteRepo/roms/sorcerer_boot.rom")
        Run-Logged @("scp", $DreamMonitor, "${RemoteUser}@${RemoteHost}:$RemoteRepo/sim/inputs/dream_monitor.rom")
        Run-Logged @("scp", $DreamDisk, "${RemoteUser}@${RemoteHost}:$RemoteRepo/sim/inputs/dreamdisk_master.dsk")
    } finally {
        Pop-Location
    }
}

$switchArgs = @()
foreach ($name in @('ContinueAfterPrompt','Dd32DirectedPreflight','Dd34LastTxnPreflight','SlowPostPromptFdc','SlowCallerReturnPath','SlowCallerInjectError','ValidWritePreflight','WriteSectorPreflight','HardwareMemoryLayout')) {
    if (Get-Variable -Name $name -ValueOnly) { $switchArgs += "-$name" }
}
$switchText = $switchArgs -join ' '
$remoteScript = Join-Path $RemoteRepo "scripts\run_dreamdisk_sim.ps1"
$remoteBoot = Join-Path $RemoteRepo "roms\sorcerer_boot.rom"
$remoteMonitor = Join-Path $remoteInputDir "dream_monitor.rom"
$remoteDisk = Join-Path $remoteInputDir "dreamdisk_master.dsk"
$remoteCommand = @"
`$ErrorActionPreference = 'Stop'
& '$remoteScript' $switchText -SlowWorkspace0e $SlowWorkspace0e -ModelSim '$RemoteModelSim' -BootRom '$remoteBoot' -DreamMonitor '$remoteMonitor' -DreamDisk '$remoteDisk'
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
Get-Content -LiteralPath (Join-Path '$RemoteRepo' 'sim\dreamdisk_transcript.log') -Tail 12
"@
$encodedRun = ConvertTo-PowerShellEncodedCommand $remoteCommand
& ssh "${RemoteUser}@${RemoteHost}" powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedRun
if ($LASTEXITCODE -ne 0) { throw "Remote simulation failed with exit code $LASTEXITCODE" }

if (!$NoFetch) {
    Run-Logged @("scp", "${RemoteUser}@${RemoteHost}:$RemoteRepo/sim/dreamdisk_transcript.log", (Join-Path $repoRoot "sim\dreamdisk_remote_transcript.log"))
    Run-Logged @("scp", "${RemoteUser}@${RemoteHost}:$RemoteRepo/sim/dreamdisk_summary.log", (Join-Path $repoRoot "sim\dreamdisk_remote_summary.log"))
    Write-Host "Fetched remote simulation logs to sim\dreamdisk_remote_*.log"
}
