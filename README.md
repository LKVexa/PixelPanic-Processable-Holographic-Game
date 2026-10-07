# Pixel Panic Hologram 0.4.4 — HARD MODE

This release makes Pixel Panic materially harder **inside the TIFF/GIF-carried game program**. The C# harness, `.cmd` bootstrap, WebView2 adapter architecture, and generic virtual-console substrate are inherited unchanged from 0.4.3.

## Harder campaign

The five-minute active-simulation head start and automatic quota-based progression are retained.

| Level | Quota | Gold available | Spare | Jellyfish | Move period |
|---:|---:|---:|---:|---:|---:|
| 1 | 20 | 75 | 55 | 3 | 840 ms |
| 2 | 24 | 74 | 50 | 3 | 790 ms |
| 3 | 28 | 73 | 45 | 4 | 740 ms |
| 4 | 32 | 72 | 40 | 4 | 690 ms |
| 5 | 36 | 71 | 35 | 5 | 640 ms |
| 6 | 40 | 70 | 30 | 5 | 590 ms |
| 7 | 44 | 69 | 25 | 6 | 540 ms |
| 8 | 48 | 68 | 20 | 6 | 490 ms |
| 9 | 52 | 67 | 15 | 7 | 440 ms |
| 10 | 56 | 66 | 10 | 7 | 390 ms |
| 11 | 60 | 65 | 5 | 8 | 340 ms |
| 12 | 64 | 64 | 0 | 8 | 290 ms |

Additional changes:

- rock probability rises from 32% to 54%;
- soil, rock, and gold take more mining hits as levels rise;
- jellyfish pursue more directly (10% random wandering);
- post-hit invulnerability falls from 3.0 s toward 1.9 s;
- reveal radius drops from 5 cells to 4 on levels 7–12;
- cavern dimensions grow from 43×33 to 49×37;
- level 12 contains 64 coins and requires **all 64**.

The completion rule is unchanged: `COINS >= QUOTA` awards the diamond and automatically advances after the transition. You never need to wait for jellyfish release or manually mine the diamond.

## TIFF/GIF authority

The game rules, PP32 interpreter, recompiled HARD MODE bytecode, execution schedule, checkpoint, save writers, HERMIT terminal, UI, image bridge, source/compiler, dependency manifest, and HARD MODE specification are stored inside each cartridge.

Payload: **{len(new_payload):,} bytes**  
Image-carried modules: **{len(new_inventory)}**  
Immutable application identity: `{approval}`

The external boundary remains limited to `BOOT.cmd` / setup and verify commands, the C# image/virtual-console harness, PowerShell helpers, WebView2/.NET/WPF, and physical machine I/O.

## Run

Extract to a fresh writable directory. On Windows:

```text
SETUP.cmd
VERIFY.cmd
BOOT.cmd
```

`VERIFY.cmd` should pass before `BOOT.cmd`. If the WebView2 SDK adapter is absent, setup can provision the pinned Microsoft.Web.WebView2 1.0.4191.47 adapter.

## Save compatibility

New saves created by 0.4.4 retain the HARD MODE program and modules. Older TIFF/GIF saves retain their older embedded game code; loading an older image does not silently rewrite it into HARD MODE.

## Validation

The rebuilt image was executed through the actual image-recovered PP32 Wasm guest. Tests passed for the 12-level difficulty curve, quota progression, five-minute release boundary, 1,200 generated level/seed maps, final-level 64/64 completion, all three starting carrier formats, and guest-created TIFF/GIF/BigTIFF save/reopen continuity. Native Windows WPF/WebView2 execution still requires validation on Windows.
