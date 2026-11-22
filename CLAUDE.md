# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Factorio challenge mod "Down Bad": items (and optionally players) may never move south. Targets Factorio 2.1 (`factorio_version` in [info.json](info.json)). Lua 5.2, no build step: the repo folder *is* the mod, loaded from `%APPDATA%\Factorio\mods\down-bad`.

## Layout

- [settings.lua](settings.lua): one runtime-global setting, `down-bad-allow-players-move-down`.
- [control.lua](control.lua): all runtime logic. No data stage (no prototypes).
- [locale/en/](locale/en/): `settings.cfg` (setting text), `locale.cfg` (join messages), `lore.cfg` (99 `down-bad-lore.N` lines picked at random; keep the count in sync with `math.random(1, 99)` in control.lua).

## How control.lua works

Player-facing rules and known gaps are in [README.md](README.md#the-rules); open work and design decisions in [docs/queue.md](docs/queue.md). Keep both in sync.

- `direction_correction(entity, player_index)` runs on every build event (player, robot, space platform, script, clone) and on player rotate/flip. `player_index` is nil for non-player builds. Ghosts are handled via `ghost_type` / `ghost_prototype`.
  - `entity_not_allowed_south` types facing south get one `entity.rotate()` (2×1 entities and loaders flip 180°, loaders also swap input/output); still south → `remove_entity`.
  - Inserters: custom-vector inserters get pickup/drop swapped if pickup is north and drop south; others are rotated.
  - Rails: `rail_track_types` other than east-facing `straight-rail` are removed.
  - `remove_entity` mines back to the player, or for robot/script builds mines into a temp inventory and spills it.
- `squash_undo_actions` merges the mod's own rotate/mine into the player's build undo step, so one Ctrl+Z undoes both.
- Logistics rule (`update_requesters`, every 180 ticks): requesters are registered in `storage.requesters` on build (and by a scan in `on_init`/`on_configuration_changed`), start disabled, and are enabled only if not south of the northernmost supply source in their network. Gotchas found by testing: disabled points vanish from `network.requester_points` and their `logistic_network` goes invalid (hence the registry and `find_logistic_network_by_position`); requester chests also have a provider point (trash) that must not count as a source.
- Player movement: when the setting is off, `push_back_south_step` moves the character (or driven car/spidertron) back to the last per-surface y (`storage.player_positions[player][surface]`), keeping sideways movement only if `find_non_colliding_position` finds a spot (plain `teleport` happily lands inside walls). Respawn and surface change reset tracking; remote view and trains are ignored.

## Testing

`bash tests/run.sh` (exit 0 = pass; `FACTORIO=<exe>` overrides the default `D:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe`). It appends [tests/test.lua](tests/test.lua) to control.lua in a scratch mod dir, so tests call the mod's locals directly, then creates a save and runs 10 ticks headless. Event wiring and anything needing a real player (undo merging, GUI) isn't covered; check those in-game.

API docs for the installed version are in `<Factorio>/doc-html/`, and API changes per version are in `<Factorio>/data/changelog.txt`.

## Releasing

Pushing to `main` releases automatically ([.github/workflows/release.yml](.github/workflows/release.yml), semantic-release + `semantic-release-factorio`): it bumps `info.json`, writes `changelog.txt`, tags, and uploads to the Factorio Mod Portal. Never edit the version or changelog.txt by hand. The commit type picks the bump ([.releaserc](.releaserc)): `feat` = minor; `fix`, `info`, `compat`, `locale`, `balance`, `perf`, `control`, `other` and others = patch; breaking = major. Types not listed there (`docs`, `chore`, `ci`) don't release.
