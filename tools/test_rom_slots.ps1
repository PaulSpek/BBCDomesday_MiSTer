[CmdletBinding()]
param([string]$ModelSim = 'C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..\sim')
try {
    if (-not (Test-Path work)) {
        & (Join-Path $ModelSim 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & (Join-Path $ModelSim 'vlog.exe') -sv ../rtl/domesday/sideways_rom_bank.sv tb_sideways_rom_bank.sv
    if ($LASTEXITCODE -ne 0) { throw 'ROM-loader compilation failed' }
    foreach ($top in 'tb_sideways_rom_bank') {
        $output = & (Join-Path $ModelSim 'vsim.exe') -c $top -do 'run -all; quit -f' 2>&1
        $code = $LASTEXITCODE
        $output | Write-Output
        if ($code -ne 0 -or ($output -join "`n") -notlike "*PASS $top*" -or ($output -join "`n") -match '\*\* Fatal:') {
            throw "ROM-loader regression failed: $top"
        }
    }
} finally { Pop-Location }
