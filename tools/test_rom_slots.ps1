[CmdletBinding()]
param([string]$ModelSim = 'C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem', [switch]$Hardware)
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..\sim')
try {
    if (-not (Test-Path work)) {
        & (Join-Path $ModelSim 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    $defines = @()
    if (-not $Hardware) { $defines += '+define+DOMESDAY_BEHAVIORAL_ROM' }
    & (Join-Path $ModelSim 'vlog.exe') -sv @defines ../rtl/domesday/sideways_rom_bank.sv ../rtl/domesday/packed_bbc_rom.sv tb_sideways_rom_bank.sv tb_packed_bbc_rom.sv
    if ($LASTEXITCODE -ne 0) { throw 'ROM-loader compilation failed' }
    $workPath = (Resolve-Path work).Path
    Set-Location ..
    foreach ($top in 'tb_sideways_rom_bank','tb_packed_bbc_rom') {
        $output = & (Join-Path $ModelSim 'vsim.exe') -c -lib $workPath -L altera_mf_ver $top -do 'run -all; quit -f' 2>&1
        $code = $LASTEXITCODE
        $output | Write-Output
        if ($code -ne 0 -or ($output -join "`n") -notlike "*PASS $top*" -or ($output -join "`n") -match '\*\* Fatal:|ERROR: cannot read') {
            throw "ROM-loader regression failed: $top"
        }
    }
} finally { Pop-Location }
