[![Release](https://github.com/austinrobichaux18/Down-Bad/actions/workflows/release.yml/badge.svg?branch=main)](https://github.com/austinrobichaux18/Down-Bad/actions/workflows/release.yml)
<!--                           ^======[REPLACE THIS]======^                                                                          ^======[REPLACE THIS]======^  -->

<!-- 
# factorio-mod-template

A small Factorio Mod template which also contains GitHub Actions for automatic changelog generation, packaging and releasing to the [Factorio Mod Portal](https://mods.factorio.com)
Created by Fgardt: https://github.com/fgardt/factorio-mod-template
  -->
  
# Down Bad

A simple Factorio challenge mod where items are not allowed to move south.

Belts, inserters, loaders, and anything else that transfers items can only move them north, east, or west. If something tries to send an item south, it won't happen.

It turns out avoiding one direction makes factory design a lot harder than you'd expect.

## The rules

* **Belts, splitters, undergrounds, loaders, pumps and mining drills** can't face south. Place one facing south and it gets turned around.
* **Inserters** can't drop south of where they pick up.
* **Trains** run east-west only: straight horizontal rail is allowed; curves, diagonals and elevated rail are removed. Signals and stops work as normal.
* **Logistic bots** never deliver south. A requester or buffer chest (or rocket silo) only requests while it's level with or north of every chest in its network that could supply it. Build a provider north of it and it shuts off until that provider is gone. Buffer chests only count for requesters set to "request from buffer chests".
* **Optional:** turn off "Allow players to move down" in the map settings and you can't walk or drive south either.

### Known gaps

Bots still fly south in a few cases the mod can't control:

* Construction bots carrying building materials to ghosts.
* Personal logistics: bots delivering to your character or spidertron.
* Trash: bots taking unwanted items from players, spidertrons and active providers to storage chests.
* Roboports handing out repair packs.

Fluids flow through pipes in any direction; only pumps are restricted.

## Factorio Mod Portal

Preview images and downloads are available on the Factorio Mod Portal:
https://mods.factorio.com/mod/down-bad

## Compatibility

* Factorio 2.1, with or without Space Age.
## Bugs / Issues

None!

## Like my work? Support me!

* Tell your friends to try the mod.
* Leave a review on the Factorio Mod Portal if you enjoyed it.
* I don't make these for money, but if you'd like to support me, here's my [Venmo](https://account.venmo.com/u/Twiggy9858).
