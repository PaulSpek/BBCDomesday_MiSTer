[CmdletBinding()]
param(
    [string]$RemoteHost = '192.168.1.113',
    [string]$RemoteUser = 'Paul',
    [string]$RemoteRepo = 'D:\Users\Paul\Projects\BBCDomesday_MiSTer',
    [string]$Branch = 'domesday-main',
    [string]$IdentityFile = "$env:USERPROFILE\.ssh\id_ed25519_studeer",
    [string]$QuartusSh = 'D:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe',
    [switch]$NoFetch
)

$ErrorActionPreference = 'Stop'
$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
    throw "SSH private key not found: $IdentityFile"
}

function ConvertTo-SingleQuotedPowerShellLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

$repoLiteral = ConvertTo-SingleQuotedPowerShellLiteral $RemoteRepo
$branchLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Branch
$quartusLiteral = ConvertTo-SingleQuotedPowerShellLiteral $QuartusSh
$target = "${RemoteUser}@${RemoteHost}"
$sshArgs = @(
    '-i', $IdentityFile,
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    $target
)

$fetchScript = if ($NoFetch) {
    ''
} else {
    @"
if (-not (Test-Path -LiteralPath (Join-Path $repoLiteral '.git'))) {
    git clone --branch $branchLiteral 'https://github.com/PaulSpek/BBCDomesday_MiSTer.git' $repoLiteral
    if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
}
git -C $repoLiteral fetch origin
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
git -C $repoLiteral checkout $branchLiteral
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
git -C $repoLiteral pull --ff-only origin $branchLiteral
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@
}

$remoteScript = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
$fetchScript
if (-not (Test-Path -LiteralPath $quartusLiteral -PathType Leaf)) {
    throw 'Quartus executable not found.'
}
Set-Location -LiteralPath $repoLiteral
& $quartusLiteral --flow compile BBCMicro
if (`$LASTEXITCODE -ne 0) { exit `$LASTEXITCODE }
"@

$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($remoteScript))
& $ssh @sshArgs "powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand"
if ($LASTEXITCODE -ne 0) {
    throw "Remote Quartus build failed ($LASTEXITCODE)."
}

Write-Host "Remote build completed in $RemoteRepo"
