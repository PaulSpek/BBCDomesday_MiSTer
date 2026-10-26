[CmdletBinding()]
param(
    [string]$ModelSim = 'C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem',
    [string]$BeebAsm = ''
)
$ErrorActionPreference = 'Stop'
$BeebAsm = if ([string]::IsNullOrWhiteSpace($BeebAsm)) {
    Join-Path $PSScriptRoot '..\..\build\beebasm\bin\beebasm.exe'
} else { $BeebAsm }
$core = Split-Path $PSScriptRoot -Parent
& python (Join-Path $PSScriptRoot 'build_scsi_diag.py') $BeebAsm
if ($LASTEXITCODE -ne 0) { throw 'ROM assembly failed' }
Push-Location (Join-Path $core 'sim')
try {
    if (-not (Test-Path 'work')) {
        & (Join-Path $ModelSim 'vlib.exe') work
        if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    }
    & (Join-Path $ModelSim 'vcom.exe') -2008 ../rtl/AlanD/R65Cx2.vhd bbc_scsi_cpu_timing.vhd
    if ($LASTEXITCODE -ne 0) { throw 'VHDL compilation failed' }
    & (Join-Path $ModelSim 'vlog.exe') -sv ../rtl/domesday/aiv_scsi_adapter.sv tb_aiv_scsi_cpu.sv
    if ($LASTEXITCODE -ne 0) { throw 'SystemVerilog compilation failed' }
    $cases = @(
        @{ Arguments = @('-gLEGACY_STROBE=1'); Marker = 'REPRODUCED legacy:' },
        @{ Arguments = @('-gINITIAL_PHASE=0'); Marker = 'PASS tb_aiv_scsi_cpu phase=0' },
        @{ Arguments = @('-gINITIAL_PHASE=1'); Marker = 'PASS tb_aiv_scsi_cpu phase=1' },
        @{ Arguments = @('-gINITIAL_PHASE=7'); Marker = 'PASS tb_aiv_scsi_cpu phase=7' },
        @{ Arguments = @('-gINITIAL_PHASE=15'); Marker = 'PASS tb_aiv_scsi_cpu phase=15' }
    )
    $caseIndex = 0
    foreach ($case in $cases) {
        $arguments = $case.Arguments
        # The production CPU has uninitialized registers until its reset
        # sequence completes. Suppress numeric_std startup warnings only.
        $output = & (Join-Path $ModelSim 'vsim.exe') -c -l "cpu-case-$caseIndex.log" tb_aiv_scsi_cpu @arguments -do 'set NumericStdNoWarnings 1; run -all; quit -f' 2>&1
        $code = $LASTEXITCODE
        $output | Write-Output
        if ($code -ne 0 -or ($output -join "`n") -notlike "*$($case.Marker)*" -or ($output -join "`n") -match '\*\* Fatal:') {
            throw "CPU bus regression failed: $arguments"
        }
        $caseIndex++
    }
} finally { Pop-Location }
