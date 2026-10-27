[CmdletBinding()]
param([string]$ModelSim='C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..\sim')
try {
    if (-not (Test-Path work)) { & (Join-Path $ModelSim 'vlib.exe') work }
    $jpeg=Join-Path $PSScriptRoot '..\rtl\domesday\ld\core_jpeg'
    & (Join-Path $ModelSim 'vlog.exe') -sv "$jpeg/jpeg_color_pipeline.v" "$jpeg/jpeg_output.v" "$jpeg/jpeg_output_y_ram.v" "$jpeg/jpeg_output_cx_ram.v" "$jpeg/jpeg_output_fifo.v" tb_jpeg_color_pipeline.sv tb_jpeg_output_pipeline.sv
    if ($LASTEXITCODE -ne 0) { throw 'JPEG color compilation failed' }
    foreach($top in 'tb_jpeg_color_pipeline','tb_jpeg_output_pipeline') {
        $output=& (Join-Path $ModelSim 'vsim.exe') -c -L altera_mf_ver $top -do 'run -all; quit -f' 2>&1
        $output | Write-Output
        if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch "PASS $top" -or ($output -join "`n") -match '\*\* Fatal:') {
            throw "JPEG color regression failed: $top"
        }
    }
} finally { Pop-Location }
