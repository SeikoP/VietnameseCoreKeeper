# Vietnamese Core Keeper project design

## Goal

Move the current Vietnamese localization and native-matched font fix out of the game installation into a Git repository that is easy to edit, test, deploy locally, package, and publish to mod.io.

## Repository layout

```text
VietnameseCoreKeeper/
  Localization/Localization.csv
  Scripts/VietnameseFontFix.cs
  ModManifest.json
  README.md
  LICENSE
  tests/Test-Mod.ps1
  tools/Deploy.ps1
  tools/Package.ps1
  releases/                 # ignored by Git
```

The repository root is also the mod root. This keeps the generated ZIP compatible with Core Keeper without an extra directory layer.

## Source and deployment

The repository becomes the only editable source. `tools/Deploy.ps1` copies only the manifest, localization file, and font script into `CoreKeeper_Data/StreamingAssets/Mods/VietnameseCoreKeeper`. It never edits the repository from the game directory and never deletes unrelated mods.

The previous manually installed `VietnameseFontFix` folder is retained as a backup until subscription testing succeeds.

## Testing and packaging

`tests/Test-Mod.ps1` validates the manifest, declared files, TSV header, duplicate localization keys, required Vietnamese glyph text, and forbidden release files. `tools/Package.ps1` runs that test and creates a ZIP containing exactly the three runtime files.

Runtime acceptance requires a clean Core Keeper launch with the mod loaded, localization loaded, Vietnamese glyph installation logged, and no `Font8L missing glyph`, compilation, or load errors.

## mod.io subscription test

Use the OAuth token already stored by Core Keeper; no credentials are committed. Temporarily move the manually deployed mod out of the active mod directory, subscribe to mod `6372484`, wait for mod.io to download file `8199705`, restart Core Keeper, and verify the downloaded mod and runtime log. Leave the user subscribed when successful and restore the local copy only if the subscription path fails.

## Git and publishing

Initialize the repository on branch `main`. Ignore generated releases, local deployment settings, logs, backups, editor files, and credentials. GitHub remote creation and pushing are separate actions because no repository name or visibility was requested.
