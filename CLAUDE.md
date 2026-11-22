# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Factorio challenge mod "Down Bad": items (and optionally players) may never move south. Targets Factorio 2.1 (`factorio_version` in [info.json](info.json)). Lua 5.2, no build step: the repo folder *is* the mod, loaded from `%APPDATA%\Factorio\mods\down-bad`.

## Layout

- [settings.lua](settings.lua): one runtime-global setting, `down-bad-allow-players-move-down`.
- [control.lua](control.lua): all runtime logic. No data stage (no prototypes).
- [locale/en/](locale/en/): `settings.cfg` (setting text), `locale.cfg` (join messages), `lore.cfg` (99 `down-bad-lore.N` lines picked at random; keep the count in sync with `math.random(1, 99)` in control.lua).

## How control.lua works

- `direction_correction(entity, player_index)` runs on `on_built_entity`, `on_player_rotated_entity` and `on_player_flipped_entity`. Ghosts are handled via `ghost_type` / `ghost_prototype`.
  - Belts, undergrounds, splitters, pumps, drills (`entity_not_allowed_south`) facing south get rotated once with `entity.rotate{by_player=...}`; still south → `error()`.
  - Inserters: custom-vector inserters get pickup/drop swapped if they go straight top→bottom; others are rotated until not dropping south.
  - Rails: only east/west straight rails survive; everything else is mined back to the player.
  - Requester points are disabled on everything except characters, spidertrons, landing pads and platform hubs (bots can't be stopped flying south, so requests are cut instead). Cars also lose logistic sections.
- `squash_undo_actions` merges the mod's own rotate/mine into the player's build undo step, so one Ctrl+Z undoes both.
- Player movement: when the setting is off, `on_player_changed_position` teleports the player back to their last per-surface y (`storage.player_positions[player][surface]`), with smoke and a 1% chance of a lore line.

## Testing

No automated tests. Headless smoke check that the mod loads and runs on the installed game (`D:\SteamLibrary\steamapps\common\Factorio`), using a scratch mod dir holding a copy of this mod:

```
factorio.exe --mod-directory <scratch>/mods --create <scratch>/t.zip
factorio.exe --mod-directory <scratch>/mods --benchmark <scratch>/t.zip --benchmark-ticks 60 --disable-audio
```

This doesn't fire build/rotate events; those need an in-game check. API docs for the installed version are in `<Factorio>/doc-html/`, and the API changes per version are in `<Factorio>/data/changelog.txt`.

## Releasing

Pushing to `main` releases automatically ([.github/workflows/release.yml](.github/workflows/release.yml), semantic-release + `semantic-release-factorio`): it bumps `info.json`, writes `changelog.txt`, tags, and uploads to the Factorio Mod Portal. Never edit the version or changelog.txt by hand. The commit type picks the bump ([.releaserc](.releaserc)): `feat` = minor; `fix`, `info`, `compat`, `locale`, `balance`, `perf`, `control`, `other` and others = patch; breaking = major. Types not listed there (`docs`, `chore`, `ci`) don't release.
