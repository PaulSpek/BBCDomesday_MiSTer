[CmdletBinding()]
param(
    [string]$RemoteHost = '192.168.1.113',
    [string]$RemoteUser = 'Paul',
    [string]$RemoteRepo = 'D:\Users\Paul\Projects\BBCDomesday_MiSTer',
    [string]$Branch = 'domesday-main',
    [string]$Revision = 'BBCMicro',
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
$revisionLiteral = ConvertTo-SingleQuotedPowerShellLiteral $Revision
$quartusLiteral = ConvertTo-SingleQuotedPowerShellLiteral $QuartusSh
$target = "${RemoteUser}@${RemoteHost}"
$sshArgs = @(
    '-i', $IdentityFile,
    '-o', 'BatchMode=yes',
    '-o', 'IdentitiesOnly=yes',
    '-o', 'StrictHostKeyChecking=yes',
    '-o', 'ServerAliveInterval=30',
    '-o', 'ServerAliveCountMax=3',
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

`$repo = $repoLiteral
`$revision = $revisionLiteral
`$quartus = $quartusLiteral
`$stateDirectory = Join-Path `$repo '.remote-build'
`$currentPath = Join-Path `$stateDirectory 'current.json'
`$quartusNames = 'quartus_sh','quartus_map','quartus_fit','quartus_asm','quartus_sta','quartus_cdb','quartus_syn','quartus_eda'
`$activeQuartus = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { `$quartusNames -contains `$_.ProcessName.ToLowerInvariant() })
if (`$activeQuartus) {
    `$description = (`$activeQuartus | ForEach-Object { "`$(`$_.ProcessName):`$(`$_.Id)" }) -join ', '
    throw "A Quartus build is already active: `$description"
}

New-Item -ItemType Directory -Path `$stateDirectory -Force | Out-Null
`$buildId = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
`$stdoutPath = Join-Path `$stateDirectory ("build-`$buildId.out.log")
`$stderrPath = Join-Path `$stateDirectory ("build-`$buildId.err.log")
`$completionPath = Join-Path `$stateDirectory ("build-`$buildId.complete.json")
`$workerPath = Join-Path `$stateDirectory 'quartus-worker.ps1'

`$workerSource = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]`$Repo,
    [Parameter(Mandatory)][string]`$Revision,
    [Parameter(Mandatory)][string]`$QuartusSh,
    [Parameter(Mandatory)][string]`$BuildId,
    [Parameter(Mandatory)][string]`$CompletionPath,
    [Parameter(Mandatory)][string]`$LogPath,
    [Parameter(Mandatory)][string]`$ErrorLogPath
)

`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
`$started = Get-Date
`$exitCode = 1
`$failure = `$null
try {
    Set-Location -LiteralPath `$Repo
    `$quartusParameters = @{
        FilePath               = `$QuartusSh
        ArgumentList           = @('--flow', 'compile', `$Revision)
        WorkingDirectory       = `$Repo
        RedirectStandardOutput = `$LogPath
        RedirectStandardError  = `$ErrorLogPath
        WindowStyle            = 'Hidden'
        Wait                   = `$true
        PassThru               = `$true
    }
    `$quartusProcess = Start-Process @quartusParameters
    # Quartus 17.0.2 can report a fatal fitter access violation but leave
    # quartus_sh and/or quartus_fit alive. Waiting only for the parent then
    # leaves the detached build in a permanent "Running" state. Inspect its
    # redirected log and terminate this build's process tree on that error.
    `$fatalPattern = '^\*\*\* Fatal Error:'
    while (-not `$quartusProcess.HasExited) {
        Start-Sleep -Seconds 5
        `$quartusProcess.Refresh()
        if (Test-Path -LiteralPath `$LogPath -PathType Leaf) {
            `$fatalMatch = Select-String -LiteralPath `$LogPath -Pattern `$fatalPattern -ErrorAction SilentlyContinue |
                Select-Object -Last 1
            if (`$fatalMatch) {
                `$failure = "Quartus fatal error: `$(`$fatalMatch.Line.Trim())"
                & taskkill.exe /PID `$quartusProcess.Id /T /F 2>`$null | Out-Null
                `$quartusProcess.WaitForExit()
                `$exitCode = 1
                break
            }
        }
    }
    if (`$quartusProcess.HasExited -and -not `$failure) {
        `$exitCode = [int]`$quartusProcess.ExitCode
    }
}
catch {
    `$failure = `$_.Exception.Message
    Write-Error -ErrorRecord `$_
    `$exitCode = 1
}
finally {
    `$completion = [pscustomobject]@{
        BuildId   = `$BuildId
        ExitCode  = `$exitCode
        Started   = `$started.ToString('o')
        Completed = (Get-Date).ToString('o')
        Failure   = `$failure
    }
    [IO.File]::WriteAllText(`$CompletionPath, (`$completion | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new(`$false))
}
exit `$exitCode
'@
[IO.File]::WriteAllText(`$workerPath, `$workerSource, [Text.UTF8Encoding]::new(`$false))

function Quote-ProcessArgument([string]`$Value) {
    return '"' + `$Value.Replace('"', '\"') + '"'
}

`$workerArguments = @(
    '-NoLogo',
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy', 'Bypass',
    '-File', (Quote-ProcessArgument `$workerPath),
    '-Repo', (Quote-ProcessArgument `$repo),
    '-Revision', (Quote-ProcessArgument `$revision),
    '-QuartusSh', (Quote-ProcessArgument `$quartus),
    '-BuildId', (Quote-ProcessArgument `$buildId),
    '-CompletionPath', (Quote-ProcessArgument `$completionPath),
    '-LogPath', (Quote-ProcessArgument `$stdoutPath),
    '-ErrorLogPath', (Quote-ProcessArgument `$stderrPath)
)
`$commandLine = 'powershell.exe ' + (`$workerArguments -join ' ')
`$creation = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
    CommandLine      = `$commandLine
    CurrentDirectory = `$repo
}
if ([int]`$creation.ReturnValue -ne 0 -or -not `$creation.ProcessId) {
    throw "Detached worker could not be created (WMI return code `$(`$creation.ReturnValue))."
}

`$started = Get-Date
`$current = [pscustomobject]@{
    BuildId        = `$buildId
    Pid            = [int]`$creation.ProcessId
    Started        = `$started.ToString('o')
    StartedTicks   = `$started.Ticks
    Revision       = `$revision
    LogPath        = `$stdoutPath
    ErrorLogPath   = `$stderrPath
    CompletionPath = `$completionPath
}
`$temporaryCurrentPath = `$currentPath + '.tmp'
[IO.File]::WriteAllText(`$temporaryCurrentPath, (`$current | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new(`$false))
Move-Item -LiteralPath `$temporaryCurrentPath -Destination `$currentPath -Force
`$current | ConvertTo-Json -Compress
"@

$launchName = 'domesday-launch-' + [guid]::NewGuid().ToString('N') + '.ps1'
$launchNameLiteral = ConvertTo-SingleQuotedPowerShellLiteral $launchName
$receiveScript = @"
`$path = Join-Path ([IO.Path]::GetTempPath()) $launchNameLiteral
[IO.File]::WriteAllText(`$path, [Console]::In.ReadToEnd(), [Text.UTF8Encoding]::new(`$false))
"@
$encodedReceive = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($receiveScript))
$remoteScript | & $ssh @sshArgs "powershell.exe -NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedReceive"
if ($LASTEXITCODE -ne 0) {
    throw "Uploading remote build launcher failed ($LASTEXITCODE)."
}

$runScript = @"
`$path = Join-Path ([IO.Path]::GetTempPath()) $launchNameLiteral
try { & `$path } finally { Remove-Item -LiteralPath `$path -Force -ErrorAction SilentlyContinue }
"@
$encodedRun = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runScript))
$output = & $ssh @sshArgs "powershell.exe -NoLogo -NoProfile -NonInteractive -OutputFormat Text -EncodedCommand $encodedRun"
if ($LASTEXITCODE -ne 0) {
    throw "Remote Quartus build launch failed ($LASTEXITCODE)."
}

$json = @($output | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_.StartsWith('{') }) | Select-Object -Last 1
if (-not $json) {
    throw 'Remote build launch returned no build metadata.'
}
$metadata = $json | ConvertFrom-Json

Write-Host "Remote build gestart en losgekoppeld op $target"
Write-Host "Build-ID : $($metadata.BuildId)"
Write-Host "Proces-ID: $($metadata.Pid)"
Write-Host "Log      : $($metadata.LogPath)"
Write-Host "Fouten   : $($metadata.ErrorLogPath)"
Write-Host 'Volg de build met scripts\remote-quartus-status.ps1.'
