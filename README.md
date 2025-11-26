# AseGit
AseGit is a lightweight version-control helper for Aseprite. It creates simple, local snapshots of your sprite file, records metadata (message, tag, timestamp, edits and session time), and provides a small UI inside Aseprite for browsing, visual diffing, and reloading past snapshots.
![]()


## Features
- Lightweight local snapshot storage (saved in a `.asegit` folder next to your sprite).
- Commit snapshots with messages and optional tags.
- Auto-commit support (configurable interval).
- Visual side-by-side diffs between the current sprite and saved snapshots.
- Load a snapshot or add it as a reference layer.
- Compact history viewer with timestamps, edit counts, and duration tracking.

## Requirements
- Aseprite version with the Lua scripting API (recent versions).

## Installation
1. Copy `AseGit.lua` into your Aseprite scripts folder (typically `%APPDATA%\\Aseprite\\scripts` on Windows, or the `scripts/` directory inside your Aseprite installation).
2. Restart Aseprite or reload scripts (F5).
3. Open a sprite, then run the `AseGit` script from the `File > Scripts` menu.

Note: The script requires that the sprite has been saved at least once (it stores snapshots next to the sprite file).

## Usage
1. Open the sprite you want to track and run the script.
2. The main AseGit dialog shows statistics (session time and total time) and a History section.
3. Commit manually by entering a Message then pressing `Commit`. The Tag is optional.
4. To view older snapshots, select an entry in the history list and use `Visual Diff` to compare or `Load File` to open the snapshot in Aseprite.
5. Use `Add as Ref Layer` to insert a selected snapshot into a new semi-transparent layer in the current sprite.

## Settings
- Section visibility toggles (Statistics, Commit, History).
- Individual toggles for tag/message entry and action buttons.
- Auto-commit enable/disable and interval setting (minimum recommended 60 seconds).

### Auto-commit
- Open Settings (⚙️). Enable `Auto Commit` and set the interval (in seconds). Auto-commits will be labeled with the `AUTO` tag.

## Storage
- Snapshots are saved as `.aseprite` files into a per-sprite directory: `.asegit/<spriteTitle>_data/` next to your sprite file.
- A small JSON log (`asegit_log.json`) stores commit metadata.

## Troubleshooting
- If the script says "Please save your file at least once", save the sprite to disk and re-run the script.
- If the JSON API is missing, update Aseprite to a newer version that includes the new `app.json` module.

## Contributing
- Suggestions, bug reports and patches are welcome.
