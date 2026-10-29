# VP415 behaviour map

Reference: `references/Pi1MHz/src/BeebSCSI/fcode.c` and
`references/Pi1MHz/src/videoplayer.c`, inspected 29 October 2026. Picture
numbers are one based; DDV index entries are zero based, therefore picture
`n` selects DDV entry `n-1`.

| F-code | Pi1MHz meaning/reply | Current FPGA implementation |
|---|---|---|
| `?P` | Player state `P.....CR` | Dynamic media, seek and audio bits |
| `?F` | Current `FnnnnnCR`, or `XCR` | Dynamic visible picture number |
| `VPX` | Last selected VP mode | Dynamic `VP1`–`VP5` reply |
| `VP1`–`VP5` | Select video/computer mix | Player state and pixel mixer connected |
| `E0/E1` | Disable/enable player video | Connected to pixel mixer |
| `A0/A1`, `B0/B1` | Audio channel control | State/replies implemented; PCM path pending |
| `FnnnnnR/Q` | Seek and still | Random DDV index request; `A0` reply |
| `FnnnnnN` | Seek and play forward | Random DDV request then sequential requests; `A1` |
| `FnnnnnS` | Stop at picture | `A2` withheld until target frame is presented |
| `FnnnnnI` | Load information register | Seek plus `A3`; register semantics need expansion |
| `L/M` | Step forward/back | One random DDV request and still |
| `N/O` | Normal forward/reverse | Sequential requests in selected direction |
| `U/V`, `W/Z` | Slow/fast forward/reverse | Direction works; exact speed pacing pending |
| `SxxxF/S` | Program speed register | Syntax/state extension pending |
| `*`, `/` | Halt/pause | Halts; pause also mutes both channels |
| `+yy/-yy` | Instant relative jump | Implemented with bounds |
| `,1` | Load/standby query | `SCR` reply retained |
| `I0/J0/$0` | Initialisation, no reply | Accepted as empty reply |
| `?T1/?V1/?Y1` | Pi1MHz menu extensions | Existing single mounted-video entry retained |
| `'` | Eject/disc flip | Pending coupled-media work |

The SCSI transport always consumes exactly 256 command bytes. Only the first
sixteen bytes are retained as registers, because all supported VP415 commands
terminate within that bound. The reply is represented by state and generated
from its byte index, avoiding another 256-byte FPGA RAM.

## Completion contract

- SCSI status acknowledges transport only.
- Normal seek replies match Pi1MHz's immediate acknowledgements.
- `F...S` is special: the reply remains an empty `CR` until the requested
  decoded frame has actually been adopted at vertical blank, then becomes
  `A2 CR`.
- A frame request remains asserted until `domesday_bridge` accepts it.
- A player picture number changes only on the visible-frame indication from
  `domesday_video`, not when an index or JPEG has merely been read.

