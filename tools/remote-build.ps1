[CmdletBinding()]
param(
    [string]$RemoteHost = '192.168.1.113',
    [string]$RemoteUser = 'Paul',
    [string]$RemoteRepo = 'D:\Users\Paul\Projects\BBCDomesday_MiSTer',
    [string]$Branch = 'domesday-main',
    [string]$HostKey = '',
    [string]$QuartusSh = 'D:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe',
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'
$plink = (Get-Command plink.exe -ErrorAction Stop).Source

if ([string]::IsNullOrWhiteSpace($HostKey)) {
    throw 'Pass -HostKey with the verified SSH host key. Do not disable host-key checking.'
}

$target = "${RemoteUser}@${RemoteHost}"
$plinkArgs = @('-batch', '-agent', '-hostkey', $HostKey, $target)

if (-not $NoFetch) {
    $clone = "if not exist `"$RemoteRepo\.git`" git clone --branch $Branch https://github.com/PaulSpek/BBCDomesday_MiSTer.git `"$RemoteRepo`""
    & $plink @plinkArgs $clone
    if ($LASTEXITCODE -ne 0) { throw "Remote clone/update failed ($LASTEXITCODE). Configure SSH authentication and Git on the build host." }
}

$build = "git -C `"$RemoteRepo`" fetch origin ^& git -C `"$RemoteRepo`" checkout $Branch ^& git -C `"$RemoteRepo`" pull --ff-only origin $Branch ^& `"$QuartusSh`" --flow compile BBCMicro"
& $plink @plinkArgs $build
if ($LASTEXITCODE -ne 0) { throw "Remote Quartus build failed ($LASTEXITCODE)." }

Write-Host "Remote build completed in $RemoteRepo"
