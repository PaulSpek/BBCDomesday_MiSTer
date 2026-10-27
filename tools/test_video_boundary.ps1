[CmdletBinding()]
param([string]$ModelSim='C:\intelFPGA_lite\17.0\modelsim_ase\win32aloem')
$ErrorActionPreference='Stop'
Push-Location (Join-Path $PSScriptRoot '..\sim')
try {
 if (!(Test-Path work)) { & "$ModelSim/vlib.exe" work }
 & "$ModelSim/vcom.exe" -2008 ../rtl/mister_keyboard.vhd tb_keyboard_clock.vhd
 if ($LASTEXITCODE -ne 0) { throw 'Keyboard compilation failed' }
 $sources=@(Get-ChildItem ../rtl/domesday/ld/core_jpeg/*.v | ForEach-Object {$_.FullName})
 & "$ModelSim/vlog.exe" -sv @sources ../rtl/domesday/ld/jpeg_frame_decoder.v ../rtl/domesday/ld/fb_writer.v ../rtl/domesday/ld/ddram.sv ../rtl/domesday/ld/domesday_video.sv tb_domesday_field.sv
 if ($LASTEXITCODE -ne 0) { throw 'Video compilation failed' }
 foreach($top in 'tb_keyboard_clock','tb_domesday_field') {
  $output=& "$ModelSim/vsim.exe" -c -L altera_mf_ver $top -do 'set NumericStdNoWarnings 1; run -all; quit -f' 2>&1
  $output | Write-Output
  if ($LASTEXITCODE -ne 0 -or ($output -join "`n") -notmatch "PASS $top" -or ($output -join "`n") -match '\*\* (Fatal|Failure|Error):') { throw "Boundary regression failed: $top" }
 }
} finally { Pop-Location }
