# Development environment

## Primary remote access

Follow the local `REMOTE_ACCESS.md` instructions supplied with the workspace;
that file is intentionally not committed because it contains private network
and access metadata.
The passwordless Linux connection has been verified from this workstation with:

```powershell
$LinuxKey = "$env:USERPROFILE\.ssh\id_ed25519_linuxlaptopdell_v2"
ssh -i $LinuxKey -o BatchMode=yes paul@linuxlaptopdell `
  'printf "HOST=%s USER=%s\n" "$(hostname)" "$(whoami)"'
```

It reports `HOST=linuxlaptopdell USER=paul`. The fork is cloned there at
`/home/paul/Projects/Domesday`.

That Linux host currently has no Quartus, Icarus, Verilator or Yosys. It is
useful for Linux/Main_MiSTer builds and repository staging, but the BBC FPGA
RBF must be compiled on a machine with Quartus Lite 17.0.2.

## Known local configuration

The Arc project has an ignored machine-local configuration at:

`C:\Users\Dell\Projects\Arc\local.settings.ps1`

It records:

- remote Quartus host `192.168.1.113`, user `Paul`;
- Quartus 17.0.2 at `D:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe`;
- remote Arc repository `D:\Users\Paul\Projects\Archie_MiSTer`;
- MiSTer `192.168.1.147`, user `root`;
- RBF destination `/media/fat/_Computer/`;
- local PuTTY `plink.exe` and `pscp.exe` paths; and
- a pinned MiSTer SSH host key and password.

Do not commit the password or duplicate it into tracked files. A Domesday-specific `local.settings.ps1` should remain ignored and use the template below.

## Current state

On 2026-10-24:

- local `plink.exe` and `pscp.exe` exist;
- the Linux remote is reachable with the documented `_v2` OpenSSH key;
- the MiSTer target remains configured through Arc's local settings;
- no local Quartus installation is available to this project; and
- no baseline RBF build, fit report, or MiSTer runtime benchmark has yet been run.

## Suggested local settings shape

```powershell
$DomesdayRemoteBuild = @{
    RemoteUser = 'Paul'
    RemoteHost = '192.168.1.113'
    RemoteRepo = 'D:\Users\Paul\Projects\Domesday_MiSTer'
    QuartusSh  = 'D:\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe'
    Revision   = 'BBCMicro'
    LocalRbf   = 'C:\Users\Dell\Projects\Domesday\output_files\BBCMicro.rbf'
}

$DomesdayTransfer = @{
    MisterHost = '192.168.1.147'
    MisterUser = 'root'
    Password   = '<local secret>'
    HostKey    = '<pinned PuTTY host key>'
    MisterPath = '/media/fat/_Computer/'
    Pscp       = 'C:\Program Files\PuTTY\pscp.exe'
    Plink      = 'C:\Program Files\PuTTY\plink.exe'
}
```

## Build expectations

- Use Quartus Lite 17.0.2, matching MiSTer convention and the existing Beeb QSF, on the separate Quartus host.
- First build the unmodified/upgraded core and save `*.map.rpt`, `*.fit.rpt`, `*.sta.rpt`, and flow summary.
- Treat timing failure as a blocker before adding video logic.
- Use a distinct RBF name such as `BBCMicro_Domesday_YYYYMMDD.rbf` so the known-good BBC core is not overwritten.
- Keep deployment and test media separate; large media remains on the MiSTer SD card and outside Git.

