[CmdletBinding()]
param([string]$ModelSim='C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..\sim')
try {
    if (!(Test-Path work)) { & "$ModelSim/vlib.exe" work }
    & "$ModelSim/vlog.exe" -sv ../rtl/domesday/bbc_external_ram.sv tb_bbc_external_ram.sv
    if ($LASTEXITCODE -ne 0) { throw 'RAM compilation failed' }
    $output=& "$ModelSim/vsim.exe" -c tb_bbc_external_ram -do 'run -all; quit -f' 2>&1
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch 'PASS tb_bbc_external_ram' -or ($output -join "`n") -match '\*\* (Fatal|Error):') {
        throw 'External RAM regression failed'
    }
} finally { Pop-Location }
