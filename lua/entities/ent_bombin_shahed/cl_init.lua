include("shared.lua")
include("cl_trailsystem.lua")

-- ================================================================
-- Shahed (Geran-2) — CLIENT
-- Health degradation FX: flames, sparks, smoke via particle system.
-- geran2.mdl is a large delta-wing body — offsets spread across
-- the wide wing span (~120u) and fuselage centerline.
-- ================================================================

-- ----------------------------------------------------------------
-- Particle precache
-- ----------------------------------------------------------------
game.AddParticles("particles/fire_01.pcf")
PrecacheParticleSystem("fire_medium_02")

-- ----------------------------------------------------------------
-- Damage tier FX config
-- Geran-2 has a wide delta wing — tier 1 fires at wing tips,
-- tier 2 adds fuselage center and nose attachment.
-- ----------------------------------------------------------------
local TIER_OFFSETS = {
	[1] = {
		-- port wing tip, starboard wing tip
		{ x =  70, y =  10, z = 0 },
		{ x = -70, y =  10, z = 0 },
	},
	[2] = {
		-- wing tips (same as tier 1)
		{ x =  70, y =  10, z = 0 },
		{ x = -70, y =  10, z = 0 },
		-- fuselage center
		{ x =   0, y =   0, z = 4 },
		-- nose section
		{ x =   0, y =  50, z = 4 },
	},
}

local TIER_BURST_DELAY = { [1] = 5.0, [2] = 2.5, [3] = 0.9 }
local TIER_BURST_COUNT = { [1] = 1,   [2] = 2,   [3] = 5   }

local ShahedStates = {}

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------
local function BurstAt(pos, tier)
	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(1)
	util.Effect("Explosion", ed)

	local sed = EffectData()
	sed:SetOrigin(pos)
	sed:SetScale(1)
	util.Effect("ManhackSparks", sed)

	if tier >= 2 then
		local eed = EffectData()
		eed:SetOrigin(pos)
		eed:SetScale(1)
		util.Effect("ElectricSpark", eed)
	end
end

local function SpawnBurstFX(ent, tier)
	if not IsValid(ent) then return end
	local count = TIER_BURST_COUNT[tier] or 1
	-- Shahed: scatter bursts across the wide wing span (right axis)
	local right = ent:GetRight()
	for i = 1, count do
		local offset = right * math.Rand(-70, 70)
		BurstAt(ent:GetPos() + offset, tier)
	end
end

local function ApplyFlameParticles(state, ent, tier)
	for _, p in ipairs(state.particles) do
		if IsValid(p) then p:StopEmission() end
	end
	state.particles = {}

	local offsets = TIER_OFFSETS[tier]
	if not offsets then return end

	for _, off in ipairs(offsets) do
		local p = CreateParticleSystem(ent, "fire_medium_02", PATTACH_ABSORIGIN_FOLLOW)
		if IsValid(p) then
			p:SetControlPoint(0, ent:GetPos() + ent:GetRight()   * off.x
				                             + ent:GetUp()      * off.z
				                             + ent:GetForward() * off.y)
			table.insert(state.particles, p)
		end
	end
end

-- ----------------------------------------------------------------
-- Net receiver
-- ----------------------------------------------------------------
net.Receive("bombin_shahed_damage_tier", function()
	local idx  = net.ReadUInt(16)
	local tier = net.ReadUInt(2)

	local ent = ents.GetByIndex(idx)

	if not IsValid(ent) then
		ShahedStates[idx] = ShahedStates[idx] or { tier = 0, particles = {}, nextBurst = 0, pendingTier = nil }
		ShahedStates[idx].pendingTier = tier
		return
	end

	local state = ShahedStates[idx] or { tier = 0, particles = {}, nextBurst = 0, pendingTier = nil }
	ShahedStates[idx] = state
	state.tier = tier

	ApplyFlameParticles(state, ent, tier)
end)

-- ----------------------------------------------------------------
-- Per-frame think: track particles, periodic bursts, cleanup
-- ----------------------------------------------------------------
hook.Add("Think", "bombin_shahed_damage_fx", function()
	local ct = CurTime()
	for idx, state in pairs(ShahedStates) do
		local ent = ents.GetByIndex(idx)

		if not IsValid(ent) then
			for _, p in ipairs(state.particles) do
				if IsValid(p) then p:StopEmission() end
			end
			ShahedStates[idx] = nil
			continue
		end

		-- Resolve deferred tier
		if state.pendingTier then
			state.tier = state.pendingTier
			state.pendingTier = nil
			ApplyFlameParticles(state, ent, state.tier)
		end

		if state.tier == 0 then continue end

		-- Update control points to follow the drone
		local offsets = TIER_OFFSETS[state.tier]
		if offsets then
			for i, p in ipairs(state.particles) do
				if IsValid(p) and offsets[i] then
					local off = offsets[i]
					p:SetControlPoint(0, ent:GetPos() + ent:GetRight()   * off.x
						                             + ent:GetUp()      * off.z
						                             + ent:GetForward() * off.y)
				end
			end
		end

		-- Periodic burst sparks
		local delay = TIER_BURST_DELAY[state.tier] or 5
		if ct >= state.nextBurst then
			SpawnBurstFX(ent, state.tier)
			state.nextBurst = ct + delay + math.Rand(-delay * 0.2, delay * 0.2)
		end
	end
end)

-- ----------------------------------------------------------------
-- Standard entity functions
-- ----------------------------------------------------------------
function ENT:Initialize()
end

function ENT:Draw()
	self:DrawModel()
end

function ENT:OnRemove()
	local state = ShahedStates[self:EntIndex()]
	if state then
		for _, p in ipairs(state.particles) do
			if IsValid(p) then p:StopEmission() end
		end
		ShahedStates[self:EntIndex()] = nil
	end
end
