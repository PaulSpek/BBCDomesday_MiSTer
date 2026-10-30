# Plan: volledige Domesday LaserDisc-functionaliteit

Datum: 29 oktober 2026. Basis: core `_06`, broncode na `2bd42ef`.
Dit document beschrijft voorgenomen werk; een checklist is pas voltooid na
de genoemde verificatie. Bestaande diagnoses blijven in
`video-build-diagnosis.md`.

## Doel en afbakening

De BBC Master met 65C02-coprocessor moet de originele Domesday-software
kunnen uitvoeren en daarmee de geëmuleerde VP415 bedienen: beeld zoeken,
stilzetten, afspelen, audio horen, computerbeeld mengen en disczijde wisselen.
We implementeren eerst de bekende ontbrekende functies. Daarna gebruiken we
boottraces voor resterende afwijkingen. Gerichte moduletests horen bij iedere
implementatiestap en voorkomen dat een ontbrekende functie als voltooid geldt.

PVF blijft het bronarchief. De primaire MiSTer-route is de bestaande DDV-cache
met onafhankelijk decodeerbare baseline-JPEG-beelden en originele PCM-audio.
Directe H.264-decode op ARM of FPGA is geen afhankelijkheid van dit plan.
JPEG-conversie en RGB565-weergave zijn niet verliesvrij; geometrie,
beeldnummering en audio moeten wel behouden blijven. Geen nieuwe conversie
starten zonder vastgestelde noodzaak en gecontroleerde beschikbare ruimte.

## Vastgestelde uitgangspositie

| Onderdeel | Huidige toestand | Nog te bewijzen/voltooien |
|---|---|---|
| Master, Tube, VFS, SCSI lezen | Hardwaretests slagen; `_06` bereikt de startmelding | Volledige applicatieboot |
| PVF | Headerherkenning | Geen directe H.264-playback gepland |
| DDV | Header, index, JPEG-sectorstream en sequentiële frames aanwezig | Framekeuze vanuit player, pacing en foutafhandeling |
| JPEG/DDR | Decoder, RGB565-writer, drie buffers en regelreader aangesloten | Gecombineerde hardwarewerking en duurzame 25 fps |
| Compositie | Centrale 640x512 uitsnede, vaste hard-key | Alle VP-modi, enable, volledige registratie |
| Player | Enkele detectiequeries en vaste replies | Complete commandoverwerking en echte status |
| Audio | DDV bevat PCM; BBC-audio aangesloten | PCM-reader, buffering, synchronisatie, kanaalkeuze en mix |
| Discselectie | Eén apart gemount videobestand en VFS-image | Gekoppelde mediawissel en eject/flip |

`_06` heeft setup-WNS -2,702 ns en hold-WNS -0,124 ns. De fitter gebruikt
25.955/41.910 ALMs (62%), 536/553 RAM-blokken (97%) en 71/112 DSPs (63%).
De RAM-blokken vormen de scherpste capaciteitsgrens. De stresstest voltooide
256 loads; de exacte core/configuratie bij iedere nieuwe hardwaretest moet
worden genoteerd. Een geslaagde functionele test bewijst geen timing closure.

De startmelding bewijst vooruitgang voorbij de vroegere opstartfout. De
exacte huidige hangplaats is nog onbekend. Strings na de melding in INIT
bewijzen op zichzelf geen uitvoeringsvolgorde of sideways-RAM-fout.

## Architectuur en interfaces

De vier onderdelen krijgen expliciete grenzen:

1. `aiv_scsi_adapter`: bestaande SCSI-transportlaag; levert een compleet
   ontvangen F-code en leest een snapshot van maximaal 256 replybytes.
2. Nieuwe `vp415_player`: parser, spelerstatus, commando-ordering, beeldnummer,
   VP-modus, audio/video-enable en uitgestelde completion.
3. `domesday_bridge`: DDV-index, sectorarbitrage, JPEG-stream en PCM-stream.
   Ontvangt expliciet een gevraagde frame-index en request-id.
4. `domesday_video`: decode, DDR-bufferbeheer, zichtbare framebevestiging en
   compositie. Meldt decodefout en presentatie met dezelfde request-id terug.

SCSI-transportsucces betekent dat een commando is ontvangen. Een playerreply
zoals seek-completion volgt pas op het daarvoor vastgestelde completionmoment.
Het onderscheid wordt per commando uit Pi1MHz en de VP415-documentatie
overgenomen. BBC-buscycli wachten nooit op SD, Linux of JPEG-decode.

Sectorverzoeken krijgen één eigenaar per transactie. Headers/index/JPEG en
audio delen een scheduler die de bestaande hps_io-procedure respecteert.
Mediawissels krijgen een generatie-id, zodat oude SD- of decoderresultaten
niet in een nieuwe disc terechtkomen. Reset en nieuwe seek annuleren oude
requests op een gedefinieerde grens.

## Fase 0 — baseline, contracten en gedragstabel

- [ ] `_06`, bijbehorende rapporten, broncommit en mediahashes archiveren.
- [ ] Pi1MHz F-codeparser, player en tests inventariseren; per commando een
  tabel maken met syntax, statewijziging, reply, completion en foutgedrag.
- [ ] VP1–VP5, E0/E1 en audiokanaalgedrag rechtstreeks uit de referenties
  vastleggen; geen ontbrekend gedrag uit alleen commandonamen afleiden.
- [ ] DDV-startframe, index 0, disc picture number 1, eindframe en gebruikte
  conversieversie expliciet koppelen. Controleer ook de volledige DDV op MiSTer.
- [ ] Klokdomeinen en request/completion-interfaces vastleggen, inclusief
  gelijktijdige nieuwe seek, reset, unmount en laatste-frame-completion.
- [ ] Timingpaden van `_06` rangschikken en RAM-budget voor audio bepalen.

Oplevering: gedragstabel, interfacebeschrijving, baseline en resourceraming.
Acceptatie: geen ongedefinieerde nummering, completion of buffereigenaar.

## Fase 1 — F-codeparser en spelerstatus

- [ ] De huidige opslag van vier tekens vervangen door CR-begrensde parsing
  van de volledige commandosyntax binnen de 256-byte SCSI-payload.
- [ ] Parser bij voorkeur streamend uitvoeren met begrensde operandregisters;
  alleen noodzakelijke commandodata bewaren om extra RAM te beperken.
- [ ] Statusqueries implementeren uit echte state: geladen disc, beeldnummer,
  play/still, richting/snelheid, frame-lock, enables en VP-modus.
- [ ] Seek, still/stop, play, step, richting, snelheid en stopbeeld verwerken.
- [ ] Antwoordloze initialisatiecommando's en reply-levensduur exact modelleren.
- [ ] Directe en uitgestelde replies, herhaalde polls, nieuwe commando's tijdens
  pending acties en foutgevallen volgens de gedragstabel afhandelen.
- [ ] Bestaande Pi-menuqueries behouden en placeholders als zodanig vervangen.

Tests: uit Pi1MHz afgeleide invoer/uitvoervectoren, nul-padding, ontbrekende CR,
ongeldige cijfers, grenzen, 256 bytes, reset halverwege, opeenvolgende commands,
polls vóór/na completion en regressie van SCSI REQ/ACK/IRQ met de BBC-CPU-test.
Een gemodelleerde decoder levert instelbaar vertraagde of mislukte completions.

Acceptatie: alle ondersteunde commando's veranderen observeerbare state;
queries en completions komen overeen met de referentie. Nog geen claim dat
een echte DDV-seek of audioplayback werkt.

## Fase 2 — DDV random access en stilstaand beeld

- [ ] Automatische frame-increment vervangen door requests vanuit de player.
- [ ] 64-bit indexberekeningen en bestandgrenzen handhaven; geen 4-GiB-afkapping.
- [ ] Frame-id van index via JPEG/DDR tot presentatie doorgeven.
- [ ] Seek annuleren/vervangen zonder deels gedecodeerde buffers te tonen.
- [ ] Schrijvende, complete en zichtbare DDR-buffer exclusief beheren.
- [ ] De vaste settle-wachttijd vervangen door bevestigde writer/DDR-drain.
- [ ] Decoderfouten, ongeldige geometrie, afgebroken sectorreads en unmount
  zichtbaar maken in playerstatus; het laatste complete beeld vasthouden.

Tests: eerste/laatste frame, willekeurige sprongen, heen/terug, grote offsets,
verkeerde index, ongeldige JPEG, SD-backpressure, reset en seeks tijdens decode.
Synthetische frames bevatten grote leesbare beeldnummers en registratiepatronen.

Acceptatie: een gevraagde picture number correspondeert met het getoonde
testbeeld; completion volgt het afgesproken moment. Geen tearing of oude
completion na een nieuwe request. Eerste hardware-RBF na fase 1+2.

## Fase 3 — playback, pacing en stapgedrag

- [ ] De 25-Hz mediatijd koppelen aan de PAL-weergave; field en frame scheiden.
  Header-fps controleren en niet iedere verticale flank als volgend frame tellen.
- [ ] Play, stop, één stap vooruit/achteruit, reverse en de door Pi1MHz
  ondersteunde snelheden verbinden met de planner.
- [ ] Stopbeeld en eind-van-disc afhandelen; voltooiing op werkelijke toestand.
- [ ] Decoder/SD mogen vooruit werken binnen exclusief bufferbeheer.
- [ ] Beleid voor late frames expliciet maken; geen stille versnelde playback.

Metingen: decode- en seekduur, SD-wachttijd, late frames, dropped frames en
zichtbaar beeldnummer. Gebruik een 60-secondenclip en daarna een volledige disc.
Acceptatie: 1500 bedoelde beelden in 60 s binnen PAL-kloknauwkeurigheid,
correct stopbeeld, deterministische steps en reverse, geen bufferbotsingen.
Performance-doel: ten minste 20% marge op het gemiddelde 40-ms-framebudget;
worst-case stalls apart rapporteren. Een grotere buffer maskeert geen tekort
aan duurzame bandbreedte.

## Fase 4 — volledige videocompositie

- [ ] VP-modus en video-enable vanuit player naar pixelmux brengen.
- [ ] VP1–VP5 volgens de vastgelegde waarheidstabel implementeren.
- [ ] RGB, blanking, sync en transparency door gelijke pipelinevertraging voeren.
- [ ] Eerst bestaande centrale uitsnede verifiëren, daarna volledige PAL-grid
  en overscan zonder de beeldnummering of DDV-geometrie te wijzigen.
- [ ] Interlacevelden correct op even/oneven bronregels registreren.

Tests: kleurvakken, zwart/transparant versus opaque, randen, éénpixelraster,
wisselende even/oneven lijnen en modewijziging tijdens playback. Controleer
HDMI en gebruikte directe video-uitgang afzonderlijk.
Acceptatie: iedere modus matcht de referentietabel; geen verschoven BBC-laag,
verkeerde fieldselectie, tearing of onbedoelde doorzichtige zwarte pixels.

## Fase 5 — PCM-audio en synchronisatie

- [ ] 48-kHz, 16-bit stereo-PCM uit de DDV-audiosectie lezen.
- [ ] Ringbuffer ontwerpen binnen de resterende RAM-capaciteit; zo nodig grote
  opslag in DDR met een kleine FPGA-FIFO, met gemeten DDR-arbitragekosten.
- [ ] Audio-low-watermark krijgt voorrang boven JPEG-prefetch; sectorswitches
  vinden uitsluitend tussen transacties plaats.
- [ ] Seek/stop/reset flushen audio gecontroleerd; request-generaties bewaken.
- [ ] Audio-enables, kanaalselectie en BBC/PCM-mix met saturatie implementeren.
- [ ] CLK_AUDIO-overgang met veilige FIFO/handshake en resetdiscipline uitvoeren.
- [ ] A/V koppelen aan dezelfde mediatijd, inclusief het referentiegedrag bij
  still, reverse en variabele snelheid.

Tests: links/rechts verschillende tonen, impuls met zichtbaar frame-event,
seek tijdens audio, SD-stalls en FIFO-grenzen. Meet underruns/overruns en drift.
Acceptatie: geen underruns tijdens minimaal 10 minuten normale playback,
geen kanaalverwisseling/clipping en geen oplopende A/V-drift; initiële
syncfout maximaal één videoframe, verder aanscherpen op basis van metingen.

## Fase 6 — discselectie, eject en mediarelaties

- [ ] Paarvorming van VFS-image en DDV beschrijven; videobestand alleen bewijst
  niet dat de juiste LV-ROM-data is gemount.
- [ ] FC41/jukeboxselectie en directoryqueries verbinden met werkelijk
  beschikbare media, titel en discstatus.
- [ ] Eject/flip, standby, missing-disc en re-insert-polling uit Pi1MHz porteren.
- [ ] Gekoppelde wissel van data en video atomair maken; oude caches invalideren.

Afhankelijkheid: stock hps_io opent niet automatisch een willekeurig sibling-
bestand op basis van een FPGA-pad. Eerst vaststellen of vooraf gemounte slots
voldoende zijn. Anders een concrete Main/service-uitbreiding of handmatige
wisselprocedure ontwerpen en die beperking expliciet documenteren.
Acceptatie: twee disczijden met verschillende data én zichtbare testbeelden
wisselen correct; ontbrekende media leidt tot de juiste status en herstelpad.

## Fase 7 — integratie en resterende bootdiagnose

- [ ] Originele BeebVFS1 starten met Master, copro, VFS en interlaceconfiguratie.
- [ ] Daarna oorspronkelijke Domesday-volumes testen op navigatie, fotozoekactie,
  overlay, audio/video, stop en discwissel.
- [ ] Bij een hang de laatst ontvangen opdracht, state, pending request en
  completion uitlezen; alleen dan een gericht !BOOT-checkpoint toevoegen.
- [ ] Vergelijken met Pi1MHz en de 26-10-referentie waar functionaliteit overlapt.

Acceptatie: de software komt voorbij de startmelding en een vooraf beschreven
gebruikersroute werkt met echte media. Een eventuele volgende hang is gekoppeld
aan een concrete aanroep/state; geen generieke SUCCESS-replies toevoegen om
de boot voorbij een onbekende toestand te duwen.

## Verificatie, builds en aflevering

Iedere fase levert broncode, betekenisvolle simulaties en een korte status-
update in dit document op. Tests omvatten parser, SCSI+CPU, mediareader,
decode/bufferbeheer, compositie en audio; modules worden ook gecombineerd
getest omdat afzonderlijke PASS-resultaten integratieproblemen kunnen missen.

Quartus draait op STUDEER met de bestaande losgekoppelde buildhelper en de
vastgelegde één-processorconfiguratie. Plan minimaal 30 minuten per volledige
build. Combineer wijzigingen per hardwaremijlpaal: seek/still, playback en
compositie, audio, daarna discwissel/integratie. Als timing of capaciteit eerder
onzeker wordt, eerst analyse/synthese uitvoeren en het ontwerp bijstellen.

Timingwerk is een doorlopende afhankelijkheid. Voor iedere build alle clock-
domains en setup/hold analyseren, kritieke paden controleren en vergelijken.
Doel voor een betrouwbare release: niet-negatieve setup- en hold-slack op
alle vereiste analyses, geen onverklaarde unconstrained paths, passend
RAM/DSP/ALM-gebruik. Geen false paths toevoegen om echte problemen te verbergen.
Negatieve slack betekent expliciet experimenteel, ook als een boot slaagt.

Elke RBF krijgt de volgende beschikbare suffix via het transferscript
(`_07` als dat nummer nog vrij is). Bewaar `_06` en de werkende referentie.
Noteer broncommit, build-id, Quartus-versie, start/eindtijd, resources,
timingrapporten, SHA-256, gebruikte media en hardwaretestresultaten.

## Eerste uitvoeringspakket

Begin met fase 0 en 1: gedragstabel, interfaces, complete parser en playerstate,
met gerichte regressies tegen Pi1MHz. Sluit daarna fase 2 aan op de bestaande
DDV/JPEG-keten. Dit levert de eerste nieuwe RBF op waarmee SCSITEST/LDVTEST
een echt gekozen beeldnummer en seek-completion kunnen verifiëren.
De overige fasen blijven onderdeel van dit plan; één geslaagde seek maakt
de video-implementatie nog niet compleet.

## Uitvoeringsstatus 29 oktober 2026

Het eerste pakket is in uitvoering op basis van `2bd42ef`:

- [x] Gedrag en picture/DDV-nummering vastgelegd in `vp415-behaviour.md`.
- [x] Complete 256-byte SCSI-overdracht naar een begrensde, CR-georiënteerde
  playerparser gebracht; de oude vierbytebeslissing is niet meer de replybron.
- [x] Dynamische `?P`, `?F` en `VPX`, basis transportcommando's, seek/still,
  step en directe/uitgestelde acknowledgement geïmplementeerd.
- [x] Playerrequests met valid/ack aan de 64-bit DDV-indexreader gekoppeld;
  automatische frame-increment uit de bridge verwijderd.
- [x] Picture number verandert pas na de zichtbare vblank-handoff.
- [x] VP1–VP5 en E0/E1 naar de bestaande pixelpipeline geleid.
- [x] Module-, SCSI-transport-, DDV-index-, raster- en echte 65C02-bustests
  slagen in ModelSim, inclusief alle geteste klokfasen en 6,5-ns skew.
- [ ] Exacte 25-Hz pacing en speedregisters.
- [ ] Geannuleerde/overschreven seeks met request-id en decoderfoutstatus.
- [ ] PCM-audiopad en gekoppelde discwissel.
- [ ] Quartus-build, timingrapport en MiSTer-hardwaretest van deze mijlpaal.

De eerste Quartus-pass van `74d1ee4` fit succesvol, maar rapporteerde
setup-WNS -79,259 ns doordat de vijf cijfers van `?F` met hardwaredeling en
modulo werden gevormd. Die RBF wordt niet uitgerold. De formatter is daarna
vervangen door een seriële 17-cycli double-dabble omzetter; een nieuwe build
moet bevestigen dat dit kunstmatige kritieke pad verdwenen is.

De vervolgpass van `a9bcea5` verbeterde dit tot setup-WNS -18,661 ns en
hold-WNS -0,364 ns, nog steeds ongeschikt voor hardwaretest. De resterende
commit-time parser vormde een F-codegetal met maximaal zes achter elkaar
gesynthetiseerde `waarde*10+cijfer`-stappen. Deze wordt daarom vervangen door
één shift/add-stap per ontvangen FC40-byte, ruim vóór command completion.

De parserpass van `6447041` bracht setup-WNS terug tot -3,784 ns en
hold-WNS tot +0,087 ns. Een gedetailleerd TimeQuest-padrapport wees daarna
alle dertig slechtste setuppaden aan als `current_picture` naar `frame_index`
in `vp415_player`: operandberekening, bereikbegrenzing en de omzetting van een
één-gebaseerd beeldnummer naar een nul-gebaseerde index stonden nog in één
96-MHz klokpad. De volgende pass registreert deze drie bewerkingen afzonderlijk.
De extra twee klokken zijn verwaarloosbaar ten opzichte van SCSI-overdracht en
JPEG-decode. Player-, adapter- en echte 65C02-busregressies blijven slagen.
