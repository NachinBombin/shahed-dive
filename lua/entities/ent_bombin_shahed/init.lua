AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- ENGINE SOUND  (AN-71 method — entity-anchored, 3D positional)
-- ============================================================

local ENGINE_LOOP_SOUND = "shahed/eng_loop.wav"
local SHARD_MODEL       = "models/props_c17/FurnitureDrawer001a_Shard01.mdl"
local GRAVITY_MULT      = 1.1
local SHARD_LIFE        = 8

-- ============================================================
-- TUNING
-- ============================================================

ENT.WeaponWindow  = 8
ENT.FadeDuration  = 2.0

ENT.DIVE_Speed         = 1800
ENT.DIVE_TrackInterval = 0.1

util.AddNetworkString("bombin_shahed_damage_tier")

-- ============================================================
-- TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
	local frac = hp / maxHP
	if frac > 0.66 then return 0 end
	if frac > 0.33 then return 1 end
	if hp   > 0    then return 2 end
	return 3
end

local function BroadcastTier(ent, tier)
	net.Start("bombin_shahed_damage_tier")
		net.WriteUInt(ent:EntIndex(), 16)
		net.WriteUInt(tier, 2)
	net.Broadcast()
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
	print("[Bombin Shahed] " .. tostring(msg))
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
	self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
	self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
	self.Lifetime     = self:GetVar("Lifetime",     40)
	self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

	self.DIVE_ExplosionDamage = self:GetVar("DIVE_ExplosionDamage", 700)
	self.DIVE_ExplosionRadius = self:GetVar("DIVE_ExplosionRadius", 900)

	self.MaxHP = 200

	if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
	self.CallDir.z = 0
	self.CallDir:Normalize()

	local ground = self:FindGround(self.CenterPos)
	if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

	local altVariance = self.SkyHeightAdd * 0.25
	self.sky = ground + self.SkyHeightAdd + math.Rand(-altVariance, altVariance)

	self.DieTime   = CurTime() + self.Lifetime
	self.SpawnTime = CurTime()

	local baseRadius = self:GetVar("OrbitRadius", 2500)
	local baseSpeed  = self:GetVar("Speed",        250)
	self.OrbitRadius = baseRadius * math.Rand(0.82, 1.18)
	self.Speed       = baseSpeed  * math.Rand(0.85, 1.15)

	self.OrbitDir = (math.random(0, 1) == 0) and 1 or -1

	self.OrbitAngle    = math.Rand(0, math.pi * 2)
	self.OrbitAngSpeed = (self.Speed / self.OrbitRadius) * self.OrbitDir

	local entryRad    = self.OrbitAngle
	local entryOffset = Vector(math.cos(entryRad), math.sin(entryRad), 0)
	local spawnPos    = self.CenterPos + entryOffset * (self.OrbitRadius * 1.05)
	spawnPos.z        = self.sky

	if not util.IsInWorld(spawnPos) then
		spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
	end
	if not util.IsInWorld(spawnPos) then
		self:Debug("Spawn position out of world") self:Remove() return
	end

	self:SetModel("models/sw/avia/geran2/geran2.mdl")
	self:PhysicsInit(SOLID_VPHYSICS)
	self:SetMoveType(MOVETYPE_VPHYSICS)
	self:SetSolid(SOLID_VPHYSICS)
	self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
	self:SetPos(spawnPos)

	self:SetRenderMode(RENDERMODE_TRANSALPHA)
	self:SetColor(Color(255, 255, 255, 0))

	self:SetNWInt("HP",    self.MaxHP)
	self:SetNWInt("MaxHP", self.MaxHP)
	self:SetNWBool("Destroyed", false)

	local tangent = Vector(-entryOffset.y, entryOffset.x, 0) * self.OrbitDir
	local startAng = tangent:Angle()
	self:SetAngles(Angle(0, startAng.y, 0))
	self.ang = self:GetAngles()

	self.SmoothedRoll  = 0
	self.SmoothedPitch = 0
	self.PrevYaw       = self:GetAngles().y

	self.JitterPhase  = math.Rand(0, math.pi * 2)
	self.JitterPhase2 = math.Rand(0, math.pi * 2)
	self.JitterAmp1   = math.Rand(8,  18)
	self.JitterAmp2   = math.Rand(20, 45)
	self.JitterRate1  = math.Rand(0.030, 0.060)
	self.JitterRate2  = math.Rand(0.007, 0.015)

	self.AltDriftCurrent  = self.sky
	self.AltDriftTarget   = self.sky
	self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
	self.AltDriftRange    = 700
	self.AltDriftLerp     = 0.003

	self.BaseCenterPos = Vector(self.CenterPos.x, self.CenterPos.y, self.CenterPos.z)
	self.WanderPhaseX  = math.Rand(0, math.pi * 2)
	self.WanderPhaseY  = math.Rand(0, math.pi * 2)
	self.WanderAmp     = math.Rand(60, 160)
	self.WanderRateX   = math.Rand(0.004, 0.010)
	self.WanderRateY   = math.Rand(0.003, 0.009)

	self.PhysObj = self:GetPhysicsObject()
	if IsValid(self.PhysObj) then
		self.PhysObj:Wake()
		self.PhysObj:EnableGravity(false)
	end

	self.EngineLoop = CreateSound(self, ENGINE_LOOP_SOUND)
	if self.EngineLoop then
		self.EngineLoop:SetSoundLevel(75)
		self.EngineLoop:ChangePitch(85, 0)
		self.EngineLoop:ChangeVolume(1.0, 0)
		self.EngineLoop:Play()
	end

	self.CurrentWeapon   = nil
	self.WeaponWindowEnd = 0

	self.Diving        = false
	self.DiveTarget    = nil
	self.DiveTargetPos = nil
	self.DiveNextTrack = 0
	self.DiveExploded  = false
	self.DiveAimOffset = Vector(0,0,0)

	self.DiveWobblePhase = 0
	self.DiveWobbleAmp   = 180
	self.DiveWobbleSpeed = 4.5

	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveWobbleAmpV   = 130
	self.DiveWobbleSpeedV = 3.1

	self.DiveSpeedMin     = self.DIVE_Speed * 0.55
	self.DiveSpeedCurrent = self.DIVE_Speed * 0.55
	self.DiveSpeedLerp    = 0.018

	self.DivePitchTelegraph = 0

	-- Death tumble state
	self.Destroyed       = false
	self.DestroyedTime   = nil
	self.TumbleAngVel    = Vector(0,0,0)
	self.ExplodeTimer    = nil
	self.ExplodedAlready = false

	-- Damage tier (0=healthy, 1=light, 2=heavy, 3=dead)
	self.DamageTier = 0

	-- ----------------------------------------------------------------
	-- EVASION STATE
	-- Shared yaw bias accumulator used by BOTH sky and geometry probes.
	-- The sky system pushes this when HitSky fires;
	-- the obstacle system pushes this when HitWorld / brush fires.
	-- Both decay through separate per-tick multipliers so each system
	-- stays tuned independently while cooperating on OrbitAngSpeed.
	-- ----------------------------------------------------------------
	self.SkyYawBias      = 0
	self.SkyProbeDist    = math.max(1200, self.Speed * 6)
	self.SkyProbeLastHit = 0

	self.ObsLastEval   = 0
	self.ObsYawBias    = 0
	self.ObsAltBias    = 0
	self.ObsConsecHits = 0

	self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDir=" .. self.OrbitDir)
end

-- ============================================================
-- DEATH STATE
-- ============================================================

function ENT:IsDestroyed()
	return self.Destroyed == true
end

function ENT:SpawnDebrisShards()
	local count   = math.random(1, 2)
	local origin  = self:GetPos()
	local baseVel = self:GetVelocity()

	for i = 1, count do
		local shard = ents.Create("prop_physics")
		if not IsValid(shard) then continue end

		shard:SetModel(SHARD_MODEL)
		shard:SetPos(origin + Vector(math.Rand(-30,30), math.Rand(-30,30), math.Rand(-20,20)))
		shard:SetAngles(Angle(math.Rand(0,360), math.Rand(0,360), math.Rand(0,360)))
		shard:Spawn()
		shard:Activate()
		shard:SetColor(Color(15, 10, 10, 255))
		shard:SetMaterial("models/debug/debugwhite")

		local phys = shard:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetVelocity(baseVel * 0.3 + Vector(
				math.Rand(-300, 300),
				math.Rand(-300, 300),
				math.Rand(50,  250)
			))
			phys:AddAngleVelocity(Vector(
				math.Rand(-200, 200),
				math.Rand(-200, 200),
				math.Rand(-200, 200)
			))
		end

		shard:Ignite(SHARD_LIFE, 0)
		timer.Simple(SHARD_LIFE, function()
			if IsValid(shard) then shard:Remove() end
		end)
	end
end

function ENT:SetDestroyed()
	if self.Destroyed then return end
	self.Destroyed = true
	self:SetNWBool("Destroyed", true)
	self.DestroyedTime = CurTime()

	BroadcastTier(self, 3)

	if IsValid(self.PhysObj) then
		self.TumbleAngVel = self.PhysObj:GetAngleVelocity() + Vector(
			math.Rand(-120, 120),
			math.Rand(-120, 120),
			math.Rand(-120, 120)
		)
		self.PhysObj:EnableGravity(true)
		self.PhysObj:AddAngleVelocity(self.TumbleAngVel)
	end

	self:Ignite(20, 0)
	self:SpawnDebrisShards()

	if self.EngineLoop then
		self.EngineLoop:ChangeVolume(0, 1.5)
		self.EngineLoop:ChangePitch(55, 2.5)
	end

	local altAboveGround = self:GetPos().z - (self.sky - self.SkyHeightAdd)
	local delay = math.Clamp(altAboveGround / 600, 3, 12)
	self.ExplodeTimer = CurTime() + delay

	if not self.Diving then
		self.CurrentWeapon = nil
	end

	self:Debug("DESTROYED -- boom in " .. math.Round(delay,1) .. "s")
end

-- ============================================================
-- DAMAGE
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
	if self.ExplodedAlready then return end
	if dmginfo:IsDamageType(DMG_CRUSH) then return end

	local hp = self:GetNWInt("HP", self.MaxHP or 200)
	hp = hp - dmginfo:GetDamage()
	self:SetNWInt("HP", hp)

	local newTier = CalcTier(math.max(hp, 0), self.MaxHP)
	if newTier ~= self.DamageTier then
		self.DamageTier = newTier
		BroadcastTier(self, newTier)
	end

	if hp <= 0 and not self:IsDestroyed() then
		self:Debug("Shot down!")
		self:SetDestroyed()
	end
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
	if not self.DieTime or not self.SpawnTime then
		self:NextThink(CurTime() + 0.1)
		return true
	end

	local ct = CurTime()
	if ct >= self.DieTime then self:Remove() return end

	if not IsValid(self.PhysObj) then
		self.PhysObj = self:GetPhysicsObject()
	end
	if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
		self.PhysObj:Wake()
	end

	-- Fade in/out (skip when destroyed)
	if not self:IsDestroyed() then
		local age  = ct - self.SpawnTime
		local left = self.DieTime - ct
		local alpha = 255
		if age < self.FadeDuration then
			alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
		elseif left < self.FadeDuration then
			alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
		end
		self:SetColor(Color(255, 255, 255, math.Round(alpha)))
	end

	if self:IsDestroyed() then
		if self.ExplodeTimer and ct >= self.ExplodeTimer then
			self:CrashExplode(self:GetPos())
			return true
		end
		self:NextThink(ct + 0.05)
		return true
	end

	if self.Diving then
		self:UpdateDive(ct)
	else
		self:HandleWeaponWindow(ct)
	end

	self:NextThink(ct)
	return true
end

-- ============================================================
-- EVASION PROBES
-- ============================================================
--
-- Two subsystems share the same per-tick update path:
--
--   1. EvaluateSkyProbes   — QuickTrace / HitSky only.
--      Handles skybox ceiling and sky-walls to the sides.
--
--   2. EvaluateObstacleProbes — TraceLine / MASK_SOLID_BRUSHONLY.
--      Handles buildings, displacement terrain, indoor ceilings,
--      large static props.
--
-- Both return (yawBiasDelta, altPush) and are merged into
-- separate accumulators (SkyYawBias, ObsYawBias, ObsAltBias)
-- before being summed into OrbitAngSpeed each tick.
-- ============================================================

-- ---------- SKY constants ----------
local SKY_PROBE_DIST_H   = 1400
local SKY_PROBE_DIST_V   = 900
local SKY_YAW_BIAS_RATE  = 0.35
local SKY_YAW_BIAS_DECAY = 0.88
local SKY_ALT_PUSH       = 180
local SKY_ALT_RISE       = 120

-- ---------- OBSTACLE constants ----------
local OBS_DIST_FWD     = 900
local OBS_DIST_SIDE    = 700
local OBS_DIST_UP      = 500
local OBS_DIST_DOWN    = 300
local OBS_YAW_RATE     = 0.55
local OBS_ALT_PUSH_UP  = 250
local OBS_ALT_PUSH_DN  = 80
local OBS_YAW_DECAY    = 0.82
local OBS_ALT_DECAY    = 0.90
local OBS_EVAL_RATE    = 0.05   -- run probes at 20 Hz
local OBS_NEAR_FRAC    = 0.45   -- hits within 45% of probe dist -> double push
local OBS_ESCALATE_MAX = 4      -- consecutive hits before orbit-direction flip

local OBS_TRACE_MASK = MASK_SOLID_BRUSHONLY

function ENT:EvaluateSkyProbes(pos, flatFwd)
	local flatRight = Vector(-flatFwd.y, flatFwd.x, 0)

	local probes = {
		{ dir = flatFwd,                                             dist = SKY_PROBE_DIST_H, role = "fwd"   },
		{ dir = (flatFwd + flatRight * 0.7):GetNormalized(),         dist = SKY_PROBE_DIST_H, role = "right" },
		{ dir = (flatFwd - flatRight * 0.7):GetNormalized(),         dist = SKY_PROBE_DIST_H, role = "left"  },
		{ dir = Vector(flatFwd.x, flatFwd.y,  1):GetNormalized(),    dist = SKY_PROBE_DIST_V, role = "up"    },
		{ dir = Vector(flatFwd.x, flatFwd.y, -0.5):GetNormalized(),  dist = SKY_PROBE_DIST_V, role = "down"  },
	}

	local yawBias = 0
	local altPush = 0
	local anySky  = false

	for _, p in ipairs(probes) do
		local tr = util.QuickTrace(pos, p.dir * p.dist, self)
		if not tr.HitSky then continue end
		anySky = true

		if p.role == "fwd" then
			yawBias = yawBias + SKY_YAW_BIAS_RATE * 2.0 * self.OrbitDir
		elseif p.role == "right" then
			yawBias = yawBias - SKY_YAW_BIAS_RATE
		elseif p.role == "left" then
			yawBias = yawBias + SKY_YAW_BIAS_RATE
		elseif p.role == "up" then
			altPush = altPush - SKY_ALT_PUSH
		elseif p.role == "down" then
			altPush = altPush + SKY_ALT_RISE
		end
	end

	if anySky then self.SkyProbeLastHit = CurTime() end
	return yawBias, altPush
end

function ENT:EvaluateObstacleProbes(pos, flatFwd)
	local flatRight = Vector(-flatFwd.y, flatFwd.x, 0)

	local probes = {
		{ dir = flatFwd,                                              dist = OBS_DIST_FWD,        role = "fwd"      },
		{ dir = flatFwd,                                              dist = OBS_DIST_FWD * 0.4,  role = "fwd_near" },
		{ dir = (flatFwd + flatRight * 0.65):GetNormalized(),         dist = OBS_DIST_SIDE,       role = "right"    },
		{ dir = (flatFwd - flatRight * 0.65):GetNormalized(),         dist = OBS_DIST_SIDE,       role = "left"     },
		{ dir = Vector(flatFwd.x, flatFwd.y, 0.5):GetNormalized(),   dist = OBS_DIST_UP,         role = "up_fwd"   },
		{ dir = Vector(flatFwd.x, flatFwd.y, -0.4):GetNormalized(),  dist = OBS_DIST_DOWN,       role = "down_fwd" },
	}

	local yawBias = 0
	local altPush = 0
	local anyHit  = false

	for _, p in ipairs(probes) do
		local tr = util.TraceLine({
			start  = pos,
			endpos = pos + p.dir * p.dist,
			filter = self,
			mask   = OBS_TRACE_MASK,
		})

		if not tr.Hit or tr.HitSky then continue end

		anyHit = true
		local urgency = (tr.Fraction < OBS_NEAR_FRAC) and 2.0 or 1.0

		if p.role == "fwd" or p.role == "fwd_near" then
			local scale = (p.role == "fwd_near") and 1.5 or 1.0
			yawBias = yawBias + OBS_YAW_RATE * urgency * scale * self.OrbitDir
			altPush = altPush + OBS_ALT_PUSH_UP * urgency * scale

		elseif p.role == "right" then
			yawBias = yawBias - OBS_YAW_RATE * urgency

		elseif p.role == "left" then
			yawBias = yawBias + OBS_YAW_RATE * urgency

		elseif p.role == "up_fwd" then
			altPush = altPush - OBS_ALT_PUSH_DN * urgency
			yawBias = yawBias + OBS_YAW_RATE * 0.5 * urgency * self.OrbitDir

		elseif p.role == "down_fwd" then
			altPush = altPush + OBS_ALT_PUSH_UP * 0.6 * urgency
		end
	end

	if anyHit then
		self.ObsConsecHits = (self.ObsConsecHits or 0) + 1
		if self.ObsConsecHits >= OBS_ESCALATE_MAX then
			self.OrbitDir      = -self.OrbitDir
			yawBias            = yawBias + OBS_YAW_RATE * 4.0 * self.OrbitDir
			self.ObsConsecHits = 0
			self:Debug("Obstacle escalation — orbit reversed")
		end
	else
		self.ObsConsecHits = math.max(0, (self.ObsConsecHits or 0) - 1)
	end

	return yawBias, altPush
end

-- ============================================================
-- FLIGHT
-- ============================================================

function ENT:PhysicsUpdate(phys)
	if not self.DieTime or not self.sky then return end
	if CurTime() >= self.DieTime then self:Remove() return end

	-- Destroyed: tumble under gravity
	if self:IsDestroyed() then
		local dt = FrameTime()
		if dt <= 0 then dt = 0.01 end

		local angVel = phys:GetAngleVelocity()
		phys:AddAngleVelocity(angVel * 0.08 * dt * 60)

		local extraG = -600 * (GRAVITY_MULT - 1) * phys:GetMass()
		phys:ApplyForceCenter(Vector(0, 0, extraG))

		local pos  = self:GetPos()
		local vel  = phys:GetVelocity()
		local next = pos + vel * dt + Vector(0, 0, -24)
		local tr = util.TraceLine({
			start  = pos,
			endpos = next,
			filter = self,
			mask   = MASK_SOLID_BRUSHONLY,
		})
		if tr.Hit then self:CrashExplode(tr.HitPos) end
		return
	end

	if self.Diving then return end

	local pos = self:GetPos()
	local dt  = FrameTime()
	if dt <= 0 then dt = 0.01 end

	-- Wander center drift
	self.WanderPhaseX = self.WanderPhaseX + self.WanderRateX
	self.WanderPhaseY = self.WanderPhaseY + self.WanderRateY
	self.CenterPos = Vector(
		self.BaseCenterPos.x + math.sin(self.WanderPhaseX) * self.WanderAmp,
		self.BaseCenterPos.y + math.sin(self.WanderPhaseY) * self.WanderAmp,
		self.BaseCenterPos.z
	)

	-- ----------------------------------------------------------------
	-- EVASION EVALUATION (rate-limited to 20 Hz)
	-- ----------------------------------------------------------------
	local flatFwd = Angle(0, self.ang.y, 0):Forward()
	flatFwd.z = 0
	if flatFwd:LengthSqr() < 0.01 then flatFwd = Vector(1, 0, 0) end
	flatFwd:Normalize()

	local ct = CurTime()
	if ct - self.ObsLastEval >= OBS_EVAL_RATE then
		self.ObsLastEval = ct

		local skyYaw, skyAlt = self:EvaluateSkyProbes(pos, flatFwd)
		local obsYaw, obsAlt = self:EvaluateObstacleProbes(pos, flatFwd)

		self.SkyYawBias = self.SkyYawBias + skyYaw
		self.ObsYawBias = self.ObsYawBias + obsYaw
		self.ObsAltBias = self.ObsAltBias + obsAlt

		local totalAlt = skyAlt + obsAlt
		if totalAlt ~= 0 then
			self.AltDriftTarget = math.Clamp(
				self.AltDriftTarget + totalAlt,
				self.sky - self.AltDriftRange * 2,
				self.sky + self.AltDriftRange * 0.5
			)
			self.AltDriftCurrent = Lerp(self.AltDriftLerp * 10, self.AltDriftCurrent, self.AltDriftTarget)
		end
	end

	-- Per-tick decay
	self.SkyYawBias = self.SkyYawBias * SKY_YAW_BIAS_DECAY
	self.ObsYawBias = self.ObsYawBias * OBS_YAW_DECAY
	self.ObsAltBias = self.ObsAltBias * OBS_ALT_DECAY

	self.SkyYawBias = math.Clamp(self.SkyYawBias, -1.8, 1.8)
	self.ObsYawBias = math.Clamp(self.ObsYawBias, -2.5, 2.5)

	-- ---- Orbit integration with merged bias ----
	self.OrbitAngSpeed = (self.Speed / self.OrbitRadius) * self.OrbitDir
	                   + self.SkyYawBias
	                   + self.ObsYawBias
	self.OrbitAngle = self.OrbitAngle + self.OrbitAngSpeed * dt

	local desiredX = self.CenterPos.x + math.cos(self.OrbitAngle) * self.OrbitRadius
	local desiredY = self.CenterPos.y + math.sin(self.OrbitAngle) * self.OrbitRadius

	local tangentYaw    = math.deg(self.OrbitAngle) + 90 * self.OrbitDir
	local yawError      = math.NormalizeAngle(tangentYaw - self.ang.y)
	local yawCorrection = math.Clamp(yawError * 0.08, -0.6, 0.6)
	self.ang = self.ang + Angle(0, yawCorrection, 0)

	-- Jitter
	self.JitterPhase  = self.JitterPhase  + self.JitterRate1
	self.JitterPhase2 = self.JitterPhase2 + self.JitterRate2
	local jitter = math.sin(self.JitterPhase)  * self.JitterAmp1
	             + math.sin(self.JitterPhase2) * self.JitterAmp2

	-- Altitude drift
	if ct >= self.AltDriftNextPick then
		self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftNextPick = ct + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)
	local liveAlt = self.AltDriftCurrent + jitter

	-- Position correction toward orbit ring
	local posErr = Vector(desiredX - pos.x, desiredY - pos.y, 0)
	local vel    = self:GetForward() * self.Speed
	if posErr:LengthSqr() > 400 then
		vel = vel + posErr:GetNormalized() * 80
	end

	self:SetPos(Vector(pos.x, pos.y, liveAlt))

	-- Roll / pitch smoothing
	local rawYawDelta = math.NormalizeAngle(self.ang.y - (self.PrevYaw or self.ang.y))
	self.PrevYaw      = self.ang.y

	local targetRoll  = math.Clamp(rawYawDelta * -25, -30, 30)
	self.SmoothedRoll = Lerp(rawYawDelta ~= 0 and 0.15 or 0.05, self.SmoothedRoll, targetRoll)

	local physVel      = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
	local forwardSpeed = physVel:Dot(self:GetForward())
	local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
	local targetPitch  = math.Clamp(speedRatio * 10, -15, 15)
	self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, targetPitch)

	self.ang.p = self.SmoothedPitch
	self.ang.r = self.SmoothedRoll
	self:SetAngles(self.ang)

	if IsValid(phys) then
		phys:SetVelocity(vel)
	end

	if not self:IsInWorld() then
		-- Graceful recovery: re-center instead of removing
		self:Debug("Out of world — center recovery")
		local safePos = Vector(self.BaseCenterPos.x, self.BaseCenterPos.y, self.sky)
		self:SetPos(safePos)
		if IsValid(phys) then phys:SetVelocity(Vector(0,0,0)) end
		self.OrbitAngle = math.atan2(
			safePos.y - self.CenterPos.y,
			safePos.x - self.CenterPos.x
		)
	end
end

-- ============================================================
-- TARGET
-- ============================================================

function ENT:GetPrimaryTarget()
	local closest, closestDist = nil, math.huge
	for _, ply in ipairs(player.GetAll()) do
		if not IsValid(ply) or not ply:Alive() then continue end
		local d = ply:GetPos():DistToSqr(self.CenterPos)
		if d < closestDist then closestDist = d; closest = ply end
	end
	return closest
end

-- ============================================================
-- WEAPON WINDOW
-- ============================================================

function ENT:HandleWeaponWindow(ct)
	if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
		self:PickNewWeapon(ct)
	end
	if self.CurrentWeapon == "dive" then
		self:InitDive(ct)
	end
end

function ENT:PickNewWeapon(ct)
	local roll = math.random(1, 3)
	if roll == 1 then
		self.CurrentWeapon = "peaceful_1"
	elseif roll == 2 then
		self.CurrentWeapon = "peaceful_2"
	else
		self.CurrentWeapon = "dive"
	end
	self.WeaponWindowEnd = ct + self.WeaponWindow
	self:Debug("Behavior slot: " .. self.CurrentWeapon)
end

-- ============================================================
-- DIVE
-- ============================================================

function ENT:InitDive(ct)
	if self.Diving then return end

	if not self.DiveCommitTime then
		self.DiveCommitTime = ct + 1.0
		self:Debug("DIVE: locking target in 1s...")
		return
	end

	local commitFraction    = math.Clamp((ct - (self.DiveCommitTime - 1.0)) / 1.0, 0, 1)
	self.DivePitchTelegraph = commitFraction * -60
	self:SetAngles(Angle(self.DivePitchTelegraph, self.ang.y, self.SmoothedRoll))

	if ct < self.DiveCommitTime then return end

	local target = self:GetPrimaryTarget()
	if not IsValid(target) then
		self.CurrentWeapon      = nil
		self.DiveCommitTime     = nil
		self.DivePitchTelegraph = 0
		return
	end

	self.Diving             = true
	self.DiveTarget         = target
	self.DiveTargetPos      = target:GetPos()
	self.DiveNextTrack      = ct
	self.DiveExploded       = false
	self.DiveCommitTime     = nil
	self.DivePitchTelegraph = 0

	self.DiveWobblePhase  = 0
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveSpeedCurrent = self.DiveSpeedMin

	self.DiveAimOffset = Vector(
		math.Rand(-400, 400),
		math.Rand(-400, 400),
		0
	)

	self:SetCollisionGroup(COLLISION_GROUP_NONE)
	self:SetSolid(SOLID_VPHYSICS)
	if IsValid(self.PhysObj) then
		self.PhysObj:EnableGravity(false)
	end

	self:Debug("DIVE: committed — aim offset " .. tostring(self.DiveAimOffset))
end

function ENT:UpdateDive(ct)
	if self.DiveExploded then return end

	if ct >= self.DiveNextTrack then
		if not self:IsDestroyed() then
			if IsValid(self.DiveTarget) and self.DiveTarget:Alive() then
				self.DiveTargetPos = self.DiveTarget:GetPos() + Vector(
					math.Rand(-120,120), math.Rand(-120,120), 0)
			end
		end
		self.DiveNextTrack = ct + self.DIVE_TrackInterval
	end

	if not self.DiveTargetPos then self:Remove() return end

	local aimPos = self.DiveTargetPos + self.DiveAimOffset
	local myPos  = self:GetPos()
	local dir    = aimPos - myPos
	local dist   = dir:Length()

	if dist < 120 then
		if self:IsDestroyed() then
			self:CrashExplode(myPos)
		else
			self:DiveExplode(myPos)
		end
		return
	end

	dir:Normalize()

	if self:IsDestroyed() then return end

	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()
	self.DiveWobblePhase  = self.DiveWobblePhase  + self.DiveWobbleSpeed  * dt
	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt

	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1, 0, 0) end
	flatRight:Normalize()
	local worldUp = Vector(0, 0, 1)
	local upPerp  = worldUp - dir * dir:Dot(worldUp)
	if upPerp:LengthSqr() < 0.01 then upPerp = Vector(0, 1, 0) end
	upPerp:Normalize()

	local wobbleScale = math.Clamp(dist / 400, 0, 1)
	local wobbleVel =
		flatRight * math.sin(self.DiveWobblePhase)  * self.DiveWobbleAmp  * wobbleScale +
		upPerp    * math.sin(self.DiveWobblePhaseV) * self.DiveWobbleAmpV * wobbleScale

	local totalVel = dir * self.DiveSpeedCurrent + wobbleVel

	if totalVel:LengthSqr() > 0.01 then
		local faceAng = totalVel:GetNormalized():Angle()
		faceAng.r = 0
		self:SetAngles(faceAng)
		self.ang = faceAng
	end

	local nextPos = myPos + totalVel * dt
	local tr = util.TraceLine({
		start  = myPos,
		endpos = nextPos,
		filter = self,
		mask   = MASK_SOLID,
	})
	if tr.Hit then self:DiveExplode(tr.HitPos) return end

	if IsValid(self.PhysObj) then
		self.PhysObj:SetVelocity(totalVel)
	end
end

-- ============================================================
-- EXPLOSIONS
-- ============================================================

function ENT:DiveExplode(pos)
	if self.DiveExploded then return end
	self.DiveExploded    = true
	self.ExplodedAlready = true
	self:Debug("DIVE: exploding at " .. tostring(pos))

	local ed1 = EffectData()
	ed1:SetOrigin(pos)
	ed1:SetScale(8) ed1:SetMagnitude(8) ed1:SetRadius(800)
	util.Effect("HelicopterMegaBomb", ed1, true, true)

	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetScale(6) ed2:SetMagnitude(6) ed2:SetRadius(700)
	util.Effect("500lb_air", ed2, true, true)

	local ed3 = EffectData()
	ed3:SetOrigin(pos + Vector(0,0,80))
	ed3:SetScale(5) ed3:SetMagnitude(5) ed3:SetRadius(600)
	util.Effect("500lb_air", ed3, true, true)

	local ed4 = EffectData()
	ed4:SetOrigin(pos + Vector(0,0,-20))
	ed4:SetScale(4) ed4:SetMagnitude(4) ed4:SetRadius(500)
	util.Effect("HelicopterMegaBomb", ed4, true, true)

	sound.Play("weapon_AWP.Single",               pos,                155, 55, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos,                150, 80, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos + Vector(0,0,50), 145, 95, 0.8)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius, self.DIVE_ExplosionDamage)
	self:Remove()
end

function ENT:CrashExplode(pos)
	if self.ExplodedAlready then return end
	self.ExplodedAlready = true
	self:Debug("CRASH: exploding at " .. tostring(pos))

	local ed = EffectData()
	ed:SetOrigin(pos)
	ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
	util.Effect("HelicopterMegaBomb", ed, true, true)

	local ed2 = EffectData()
	ed2:SetOrigin(pos)
	ed2:SetScale(3) ed2:SetMagnitude(3) ed2:SetRadius(300)
	util.Effect("500lb_air", ed2, true, true)

	sound.Play("ambient/explosions/explode_8.wav", pos, 140, 78, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos, 135, 92, 0.7)

	local crashDmg = self.DIVE_ExplosionDamage * 0.3
	local crashRad = self.DIVE_ExplosionRadius * 0.6
	util.BlastDamage(self, self, pos, crashRad, crashDmg)
	self:Remove()
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
	local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
	local endPos     = Vector(centerPos.x, centerPos.y, -16384)
	local filterList = { self }
	local maxIter    = 0
	while maxIter < 100 do
		local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
		if tr.HitWorld then return tr.HitPos.z end
		if IsValid(tr.Entity) then
			table.insert(filterList, tr.Entity)
		else
			break
		end
		maxIter = maxIter + 1
	end
	return -1
end

function ENT:OnRemove()
	if self.EngineLoop then self.EngineLoop:Stop() end
end
