# Pixel Panic Hologram 0.4.4 — HARD MODE audit

**Decision:** HARD MODE is compiled into the image-carried game program. No difficulty logic was added to the external C# harness.

## Image changes

The PP32 game source stored in `source/game.ppl.py` was revised and recompiled to `program.ppbc`. The zero-import `runtime.wasm`, eight-record schedule, save checkpoint profile, HERMIT terminal, hologram bridge, and external C# harness architecture remain in the same roles.

- Payload: **424,127 bytes**
- Modules: **29**
- Payload SHA-256: `3a94f9a13b65985c5afbcb1164e4e486f8b3e36d8131f1092c0856d22381531d`
- Immutable application identity: `326a7fafa1bc6184702ad6780826aa2ffc3afb04b7acc0c06cb38909497edad2`

All three carriers independently recover this same payload and identity.

## Rule changes

- Quota: `20 + 4*(level-1)` → 20 .. 64.
- Supply: `75 - (level-1)` → 75 .. 64.
- Final spare-coins margin: 0 on level 12.
- Jellyfish: 3 .. 8.
- Jellyfish period: 840 ms .. 290 ms.
- Rock probability: 32% .. 54%.
- Harder soil/rock/gold mining.
- More direct ghost pursuit.
- Shorter collision protection.
- Reveal radius reduced on levels 7–12.
- Larger caverns.

Unchanged required behavior:

- 300,000 ms active head start.
- `COINS >= QUOTA` completes the cavern.
- Diamond is awarded as the completion reward.
- Automatic next-cavern progression.
- Level 12 ends the campaign.
- Three hearts per cavern.

## Executed checks

The actual image-recovered PP32 Wasm guest passed **6 gameplay/difficulty groups plus 6 format/save checks, with 0 failures**. These included 1,200 generated level/seed maps and all 12 progression states. TIFF, GIF, and BigTIFF independently recover the same 424,127-byte payload, and guest-created TIFF/GIF/BigTIFF saves reopened with matching state.

This is software page-driven execution, not a claim of physical optical computation. The native Windows WPF/WebView2 launch path was not executed in this Linux build environment.
