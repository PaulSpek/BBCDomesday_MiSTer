# 65C02 coprocessor RAM test ROM

`copro_ramtest.rom` is a combined BBC service/language ROM. Load it into an
OSD sideways-ROM slot and run `*CPURAMTEST`. With the 65C02 coprocessor active,
the host MOS copies the language ROM through the Tube and executes it in the
coprocessor, so the test measures copro RAM rather than BBC host RAM.

The ROM refuses destructive operation when its language image is not writable,
which protects a host-only run. On the copro it tests these ranges separately:

- `&0800-&7FFF`
- `&C000-&EFFF`
- `&F000-&F7FF`
- `&8000-&BFFF`, last, from a test stage relocated to `&0400`

Every range receives complete write/read passes with `&00`, `&FF`, `&55`,
`&AA`, and an address-derived pattern. The first mismatch in each range is
reported as `FAIL @aaaa E=ee G=gg`. Zero page, stack, relocated test workspace,
Tube registers and the Tube OS at `&F800-&FFFF` are not overwritten. The test
is destructive to copro user RAM. After the result, press a key to select
BASIC again.

MiSTer test copy:
`/media/fat/BBCMicro/Domesday/BeebVFS1/CPURAMTEST_1_0.rom`, SHA-256
`f2c61b12b4401f74b34e43b4a39aa908976923bbfd47ba79c5e6196c57dc1201`.

Build and validate from the repository root:

```powershell
python tools/build_copro_ramtest.py ../build/beebasm/bin/beebasm.exe
python tools/test_copro_ramtest.py --dependencies ../build/boot-analysis-deps
```
