# Beschikbare Domesday-media

## Pi1MHzPublic

Een gedeelde bron met Pi1MHz VFS/LV-ROM-media is bereikbaar vanaf de
ontwikkel-pc via:

```text
G:\.shortcut-targets-by-id\1WZSoOqHtDxWy7fonrKCQZNgRJZ3HNLDx\Pi1MHzPublic
```

Dit is de bron voor de daadwerkelijke Domesday data-volumes. Een volume met
`scsi0.dat` bevat het read-only LV-ROM/VFS-bestandssysteem; `video.pvf` is de
bijbehorende LaserDisc-video. De DDV-cache wordt afgeleid van de PVF en is
niet de bron van de BBC-applicatiegegevens.

| Directory | LV-ROM | Video | Inhoud |
|---|---:|---:|---|
| `BeebVFS0` | `scsi0.dat` (9,472 bytes) | nee | Menu Disc |
| `BeebVFS1` | `scsi0.dat` (276,355,072 bytes) | ja | Domesday Community Disc — South |
| `BeebVFS2` | `scsi0.dat` (272,515,072 bytes) | ja | Domesday Community Disc — North |
| `BeebVFS3` | `scsi0.dat` (250,869,760 bytes) | ja | Domesday National Disc — Side A |
| `BeebVFS5` | `scsi0.dat` (331,714,560 bytes) | ja | Volcanoes |

Voor de eerste end-to-end bring-up is `BeebVFS0` (menu) plus `BeebVFS1`
(Community South) de aanbevolen combinatie. Gebruik deze bron alleen als
lokale testmedia; de bestanden zijn niet onderdeel van de Git-repository en
moeten niet zonder een afzonderlijke rechtencontrole worden gepubliceerd.
