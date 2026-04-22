# shahed-dive

Garry's Mod addon — **Shahed-136 / Geran-2** loiter munition.

Part of the **Bombin Support** family, sister addon to [learn-dive](https://github.com/NachinBombin/learn-dive) (TB-2).

## Behaviour

- Combine soldiers (`npc_combine_s`, `npc_metropolice`, `npc_combine_elite`) throw a blue flare call when they have a player enemy in range.
- After a configurable delay the Shahed-136 model spawns, climbs to altitude and orbits the call position.
- After a random window it pitches its nose down and dives at the nearest player with a **700 damage / 900 HU radius** warhead — roughly twice the TB-2 yield.
- Can be shot down (200 HP).

## Required model

```
models/sw/avia/geran2/geran2.mdl
```

Install the matching model pack before using this addon.

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `npc_bombinshahed_enabled` | 1 | Enable NPC calls |
| `npc_bombinshahed_chance` | 0.12 | Probability per check |
| `npc_bombinshahed_interval` | 12 | Seconds between checks |
| `npc_bombinshahed_cooldown` | 50 | Per-NPC cooldown |
| `npc_bombinshahed_min_dist` | 400 | Min call distance |
| `npc_bombinshahed_max_dist` | 3000 | Max call distance |
| `npc_bombinshahed_delay` | 5 | Flare → arrival delay |
| `npc_bombinshahed_lifetime` | 40 | Munition lifetime (s) |
| `npc_bombinshahed_speed` | 250 | Orbit speed HU/s |
| `npc_bombinshahed_radius` | 2500 | Orbit radius HU |
| `npc_bombinshahed_height` | 2500 | Altitude HU |
| `npc_bombinshahed_dive_damage` | **700** | Explosion damage |
| `npc_bombinshahed_dive_radius` | **900** | Explosion radius HU |
| `npc_bombinshahed_announce` | 0 | Debug prints |

## Menu

Spawnmenu → **Bombin Support** → **Shahed-136**

Or run `bombin_spawnshahed` in console for a manual test spawn.

## Credits

NachinBombin
