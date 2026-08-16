# AdjustableScope

Adjustable Scope is a mod for Project Silverfish. This mod adds scope zoom controls, target zeroing

## Installation

1. Get UE4SS. <https://github.com/UE4SS-RE/RE-UE4SS/releases/tag/experimental-latest> UE4ss installation: <https://github.com/UE4SS-RE/RE-UE4SS#basic-installation>
2. Copy the `AdjustableScope` folder into `Project Silverfish/SilverFish/Binaries/Win64/ue4ss/Mods/`.
3. Make sure the `enabled.txt` file exists in the `AdjustableScope` folder.
4. Start the game. UE4SS loads the mod automatically.

## Keybinds

Change keybinds in `config.ini`:

- **Zoom In / Out**: `+` / `-` (`OEM_PLUS` / `OEM_MINUS`)
- **Zero Up / Down**: `Page Up` / `Page Down` (`PAGE_UP` / `PAGE_DOWN`)
- **Dual Up / Down**: `Mouse 5` / `Mouse 4` (`XBUTTON_TWO` / `XBUTTON_ONE`, toggle mode with `Caps Lock`)
- **Reset**: `F1`

## Configuration

Open `config.ini` to change settings:

- `Debug`: Set to `true` to enable debug log messages in console.
- `SaveStateOnADS`: Set to `true` to save zoom and zeroing state after you exit ADS.
- `UseSteppedZoom`: Set to `true` for preset zoom stages or `false` for smooth zoom.
- `ZoomStages`: Define custom zoom multipliers for weapon magnification levels.
