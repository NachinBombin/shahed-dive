ENT.Type           = "anim"
ENT.Base           = "base_entity"
ENT.PrintName      = "Bombin Shahed-136"
ENT.Author         = "NachinBombin"
ENT.Information    = "Autonomous Shahed-136 / Geran-2 loiter munition. Orbits the target area then dives."
ENT.Category       = "Bombin Support"

ENT.Spawnable      = false
ENT.AdminSpawnable = false

-- NOTE: RENDERGROUP_OPAQUE removed intentionally.
-- The JASSM/SCALP pattern does not force opaque render group;
-- leaving it at the default (RENDERGROUP_BOTH) lets the engine
-- pick the correct pass and avoids black-model issues with
-- bodygroup swaps and translucent material slots.
