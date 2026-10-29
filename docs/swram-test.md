# BBC Master sideways-RAM test ROM

`swram_test.rom` is a separate service ROM providing `*SWRAMTEST`. Its test
engine is copied to host RAM at `&2000` before any sideways bank is selected,
so the service ROM can safely page out while the engine writes the complete
`&8000-&BFFF` window in writable banks 4, 5, 6 and 7.

Each bank is tested with `&00`, `&FF`, `&55`, `&AA` and a bank/address-derived
pattern. A final isolation pass fills every bank with a distinct signature and
then revisits them, detecting bank-selection aliasing that an isolated
write/read test would miss. The first mismatch is reported as
`FAIL @aaaa E=ee G=gg`.

The test destroys the contents of sideways RAM banks 4-7 and uses host RAM at
`&2000` for its relocated engine. Run it after a fresh core load and reset the
core before other work. The original ROM slot is restored before every output
operation and before returning to the MOS.

MiSTer test copy:
`/media/fat/BBCMicro/Domesday/BeebVFS1/SWRAMTEST_1_0.rom`, SHA-256
`ed6ca5585b4c56184d3837b5b2ea1ce738a1e4f2d1da12863929fec7320eda7d`.

Build and validate:

```powershell
python tools/build_swram_test.py ../build/beebasm/bin/beebasm.exe
python tools/test_swram_test.py --dependencies ../build/boot-analysis-deps
```
