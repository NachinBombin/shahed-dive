AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- PASS SOUNDS & ENGINE
-- ============================================================

local PASS_SOUNDS = {
	"lvs_darklord/rotors/rotor_loop_close.wav",
	"lvs_darklord/rotors/rotor_loop_dist.wav",
}

local ENGINE_START_SOUND = "lvs_darklord/mi_engine/mi24_engine_start_exterior.wav"
local ENGINE_LOOP_SOUND  = "^lvs_darklord/rotors/rotor_loop_close.wav"
local ENGINE_DIST_SOUND  = "^lvs_darklord/rotors/rotor_loop_dist.wav"

-- ============================================================
-- TUNING
-- ============================================================

ENT.WeaponWindow  = 8
ENT.FadeDuration  = 2.0

ENT.DIVE_Speed         = 1800
ENT.DIVE_TrackInterval = 0.1

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
	self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
	self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
	self.Lifetime     = self:GetVar("Lifetime",     40)
	self.Speed        = self:GetVar("Speed",        250)
	self.OrbitRadius  = self:GetVar("OrbitRadius",  2500)
	self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

	self.DIVE_ExplosionDamage = self:GetVar("DIVE_ExplosionDamage", 700)
	self.DIVE_ExplosionRadius = self:GetVar("DIVE_ExplosionRadius", 900)

	self.MaxHP = 200

	if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
	self.CallDir.z = 0
	self.CallDir:Normalize()

	local ground = self:FindGround(self.CenterPos)
	if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

	self.sky       = ground + self.SkyHeightAdd
	self.DieTime   = CurTime() + self.Lifetime
	self.SpawnTime = CurTime()

	local spawnPos = self.CenterPos - self.CallDir * 2000
	spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
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

	local ang = self.CallDir:Angle()
	self:SetAngles(Angle(0, ang.y + 70, 0))
	self.ang = self:GetAngles()

	-- Roll & Pitch state
	self.SmoothedRoll  = 0
	self.SmoothedPitch = 0
	self.PrevYaw       = self:GetAngles().y

	-- Wind jitter
	self.JitterPhase     = math.Rand(0, math.pi * 2)
	self.JitterAmplitude = 12

	-- Altitude drift
	self.AltDriftCurrent  = self.sky
	self.AltDriftTarget   = self.sky
	self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
	self.AltDriftRange    = 700
	self.AltDriftLerp     = 0.003

	self.PhysObj = self:GetPhysicsObject()
	if IsValid(self.PhysObj) then
		self.PhysObj:Wake()
		self.PhysObj:EnableGravity(false)
	end

	sound.Play(ENGINE_START_SOUND, spawnPos, 90, 100, 1.0)

	self.RotorLoopClose = CreateSound(self, ENGINE_LOOP_SOUND)
	if self.RotorLoopClose then
		self.RotorLoopClose:SetSoundLevel(125)
		self.RotorLoopClose:ChangePitch(100, 0)
		self.RotorLoopClose:ChangeVolume(1.0, 0.5)
		self.RotorLoopClose:Play()
	end

	self.RotorLoopDist = CreateSound(self, ENGINE_DIST_SOUND)
	if self.RotorLoopDist then
		self.RotorLoopDist:SetSoundLevel(125)
		self.RotorLoopDist:ChangePitch(100, 0)
		self.RotorLoopDist:ChangeVolume(1.0, 0.5)
		self.RotorLoopDist:Play()
	end

	self.NextPassSound = CurTime() + math.Rand(5, 10)

	-- Weapon state
	self.CurrentWeapon   = nil
	self.WeaponWindowEnd = 0

	-- Dive state
	self.Diving        = false
	self.DiveTarget    = nil
	self.DiveTargetPos = nil
	self.DiveNextTrack = 0
	self.DiveExploded  = false
	self.DiveAimOffset = Vector(0,0,0)

	-- Layer 1H: Horizontal wobble
	self.DiveWobblePhase = 0
	self.DiveWobbleAmp   = 180
	self.DiveWobbleSpeed = 4.5

	-- Layer 1V: Vertical wobble
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveWobbleAmpV   = 130
	self.DiveWobbleSpeedV = 3.1

	-- Layer 2: Speed surge
	self.DiveSpeedMin     = self.DIVE_Speed * 0.55
	self.DiveSpeedCurrent = self.DIVE_Speed * 0.55
	self.DiveSpeedLerp    = 0.018

	-- Layer 3: Pre-dive pitch telegraph
	self.DivePitchTelegraph = 0

	self:Debug("Spawned at " .. tostring(spawnPos))
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
	if self.DiveExploded then return end
	if dmginfo:IsDamageType(DMG_CRUSH) then return end

	local hp = self:GetNWInt("HP", self.MaxHP or 200)
	hp = hp - dmginfo:GetDamage()
	self:SetNWInt("HP", hp)

	if hp <= 0 then
		self:Debug("Shot down! Health depleted.")
		self:DiveExplode(self:GetPos())
	end
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
	print("[Bombin Shahed] " .. tostring(msg))
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

	if ct >= self.NextPassSound then
		sound.Play(
			table.Random(PASS_SOUNDS),
			self:GetPos(), 100, math.random(96, 104), 1.0
		)
		self.NextPassSound = ct + math.Rand(6, 12)
	end

	local age  = ct - self.SpawnTime
	local left = self.DieTime - ct
	local alpha = 255
	if age < self.FadeDuration then
		alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
	elseif left < self.FadeDuration then
		alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
	end
	self:SetColor(Color(255, 255, 255, math.Round(alpha)))

	if self.Diving then
		self:UpdateDive(ct)
	else
		self:HandleWeaponWindow(ct)
	end

	self:NextThink(ct)
	return true
end

-- ============================================================
-- FLIGHT  (orbit — only runs when NOT diving)
-- ============================================================

function ENT:PhysicsUpdate(phys)
	if not self.DieTime or not self.sky then return end

	if self.Diving then return end
	if CurTime() >= self.DieTime then self:Remove() return end

	local pos = self:GetPos()

	-- Altitude drift
	if CurTime() >= self.AltDriftNextPick then
		self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

	-- Wind jitter
	self.JitterPhase = self.JitterPhase + 0.04
	local jitter     = math.sin(self.JitterPhase) * self.JitterAmplitude

	local liveAlt = self.AltDriftCurrent + jitter
	self:SetPos(Vector(pos.x, pos.y, liveAlt))

	-- Orbit turn
	local flatPos    = Vector(pos.x, pos.y, 0)
	local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
	local dist       = flatPos:Distance(flatCenter)

	local orbitYaw = 0
	if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
		orbitYaw       = 0.1
		self.TurnDelay = CurTime() + 0.02
	end

	local trSkyCheck = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
	local skyYaw = 0
	if trSkyCheck.HitSky then
		skyYaw = 0.3
	end

	local totalYawDelta = orbitYaw + skyYaw
	self.ang = self.ang + Angle(0, totalYawDelta, 0)

	-- ROLL — yaw-rate driven
	local currentYaw  = self.ang.y
	local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
	self.PrevYaw      = currentYaw

	local targetRoll  = math.Clamp(rawYawDelta * -25, -25, 25)
	local rollLerp    = rawYawDelta ~= 0 and 0.15 or 0.05
	self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

	-- PITCH — forward-speed driven
	local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
	local forwardSpeed = vel:Dot(self:GetForward())
	local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
	local targetPitch  = math.Clamp(speedRatio * 10, -15, 15)
	self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, targetPitch)

	self.ang.p = self.SmoothedPitch
	self.ang.r = self.SmoothedRoll

	self:SetAngles(self.ang)

	if IsValid(phys) then
		phys:SetVelocity(self:GetForward() * self.Speed)
	end

	if not self:IsInWorld() then
		self:Debug("Out of world — removing")
		self:Remove()
	end
end

-- ============================================================
-- TARGET HELPER
-- ============================================================

function ENT:GetPrimaryTarget()
	local closest, closestDist = nil, math.huge
	for _, ply in ipairs(player.GetAll()) do
		if not IsValid(ply) or not ply:Alive() then continue end
		local d = ply:GetPos():DistToSqr(self.CenterPos)
		if d < closestDist then closestDist = d closest = ply end
	end
	return closest
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
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
-- SLOT 3 — DIVE
-- ============================================================

function ENT:InitDive(ct)
	if self.Diving then return end

	if not self.DiveCommitTime then
		self.DiveCommitTime = ct + 1.0
		self:Debug("DIVE: locking target in 1s...")
		return
	end

	-- Pitch nose down progressively during the 1s commit window
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

	-- Reset wobble phases
	self.DiveWobblePhase  = 0
	self.DiveWobblePhaseV = math.Rand(0, math.pi * 2)
	self.DiveSpeedCurrent = self.DiveSpeedMin

	-- Fixed aim error baked at launch
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

	-- Refresh target position periodically with sensor noise
	if ct >= self.DiveNextTrack then
		if IsValid(self.DiveTarget) and self.DiveTarget:Alive() then
			local trackJitter = Vector(
				math.Rand(-120, 120),
				math.Rand(-120, 120),
				0
			)
			self.DiveTargetPos = self.DiveTarget:GetPos() + trackJitter
		end
		self.DiveNextTrack = ct + self.DIVE_TrackInterval
	end

	if not self.DiveTargetPos then self:Remove() return end

	local aimPos = self.DiveTargetPos + self.DiveAimOffset

	local myPos = self:GetPos()
	local dir   = aimPos - myPos
	local dist  = dir:Length()

	if dist < 120 then
		self:DiveExplode(myPos)
		return
	end

	dir:Normalize()

	-- Speed surge
	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()

	-- Horizontal wobble
	self.DiveWobblePhase = self.DiveWobblePhase + self.DiveWobbleSpeed * dt
	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1, 0, 0) end
	flatRight:Normalize()

	-- Vertical wobble (Gram-Schmidt)
	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt
	local worldUp = Vector(0, 0, 1)
	local upPerp  = worldUp - dir * dir:Dot(worldUp)
	if upPerp:LengthSqr() < 0.01 then upPerp = Vector(0, 1, 0) end
	upPerp:Normalize()

	-- Wobble tapers to zero inside 400 units
	local wobbleScale = math.Clamp(dist / 400, 0, 1)

	local wobbleVel =
		flatRight * math.sin(self.DiveWobblePhase)  * self.DiveWobbleAmp  * wobbleScale +
		upPerp    * math.sin(self.DiveWobblePhaseV) * self.DiveWobbleAmpV * wobbleScale

	local totalVel = dir * self.DiveSpeedCurrent + wobbleVel

	-- Face actual direction of travel
	if totalVel:LengthSqr() > 0.01 then
		local travelDir = totalVel:GetNormalized()
		local faceAng   = travelDir:Angle()
		faceAng.r       = 0
		self:SetAngles(faceAng)
		self.ang = faceAng
	end

	-- Collision check
	local nextPos = myPos + totalVel * dt
	local tr = util.TraceLine({
		start  = myPos,
		endpos = nextPos,
		filter = self,
		mask   = MASK_SOLID,
	})

	if tr.Hit then
		self:DiveExplode(tr.HitPos)
		return
	end

	if IsValid(self.PhysObj) then
		self.PhysObj:SetVelocity(totalVel)
	end
end

function ENT:DiveExplode(pos)
	if self.DiveExploded then return end
	self.DiveExploded = true

	self:Debug("DIVE: exploding at " .. tostring(pos))

	-- Three stacked blast effects — larger than TB-2
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

	-- Extra ground-level ring
	local ed4 = EffectData()
	ed4:SetOrigin(pos + Vector(0,0,-20))
	ed4:SetScale(4) ed4:SetMagnitude(4) ed4:SetRadius(500)
	util.Effect("HelicopterMegaBomb", ed4, true, true)

	sound.Play("weapon_AWP.Single",               pos, 155, 55, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos, 150, 80, 1.0)
	sound.Play("ambient/explosions/explode_8.wav", pos + Vector(0,0,50), 145, 95, 0.8)

	util.BlastDamage(self, self, pos, self.DIVE_ExplosionRadius, self.DIVE_ExplosionDamage)

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

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
	if self.RotorLoopClose then self.RotorLoopClose:Stop() end
	if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end
end
