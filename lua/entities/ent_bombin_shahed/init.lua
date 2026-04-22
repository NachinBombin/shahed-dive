AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- ENGINE SOUND  (TB2 pattern — anchored to world, not entity)
-- ============================================================

local ENGINE_LOOP_SOUND = "lfs/spitfire/rpm_2.wav"

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

	-- TB2 pattern: world-anchored, no falloff, no PASS_SOUNDS
	self.EngineLoop = CreateSound(game.GetWorld(), ENGINE_LOOP_SOUND)
	if self.EngineLoop then
		self.EngineLoop:SetSoundLevel(0)
		self.EngineLoop:ChangePitch(85, 0)
		self.EngineLoop:ChangeVolume(0.4, 0)
		self.EngineLoop:Play()
	end

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

	self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDir=" .. self.OrbitDir)
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
	local dt  = FrameTime()
	if dt <= 0 then dt = 0.01 end

	self.WanderPhaseX = self.WanderPhaseX + self.WanderRateX
	self.WanderPhaseY = self.WanderPhaseY + self.WanderRateY
	self.CenterPos = Vector(
		self.BaseCenterPos.x + math.sin(self.WanderPhaseX) * self.WanderAmp,
		self.BaseCenterPos.y + math.sin(self.WanderPhaseY) * self.WanderAmp,
		self.BaseCenterPos.z
	)

	self.OrbitAngSpeed = (self.Speed / self.OrbitRadius) * self.OrbitDir
	self.OrbitAngle = self.OrbitAngle + self.OrbitAngSpeed * dt

	local desiredX = self.CenterPos.x + math.cos(self.OrbitAngle) * self.OrbitRadius
	local desiredY = self.CenterPos.y + math.sin(self.OrbitAngle) * self.OrbitRadius

	local tangentYaw    = math.deg(self.OrbitAngle) + 90 * self.OrbitDir
	local yawError      = math.NormalizeAngle(tangentYaw - self.ang.y)
	local yawCorrection = math.Clamp(yawError * 0.08, -0.6, 0.6)
	self.ang = self.ang + Angle(0, yawCorrection, 0)

	self.JitterPhase  = self.JitterPhase  + self.JitterRate1
	self.JitterPhase2 = self.JitterPhase2 + self.JitterRate2
	local jitter = math.sin(self.JitterPhase)  * self.JitterAmp1
	             + math.sin(self.JitterPhase2) * self.JitterAmp2

	if CurTime() >= self.AltDriftNextPick then
		self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
		self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
	end
	self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

	local liveAlt = self.AltDriftCurrent + jitter

	local posErr = Vector(desiredX - pos.x, desiredY - pos.y, 0)
	local vel    = self:GetForward() * self.Speed
	if posErr:LengthSqr() > 400 then
		vel = vel + posErr:GetNormalized() * 80
	end

	self:SetPos(Vector(pos.x, pos.y, liveAlt))

	local rawYawDelta = math.NormalizeAngle(self.ang.y - (self.PrevYaw or self.ang.y))
	self.PrevYaw      = self.ang.y

	local targetRoll  = math.Clamp(rawYawDelta * -25, -30, 30)
	local rollLerp    = rawYawDelta ~= 0 and 0.15 or 0.05
	self.SmoothedRoll = Lerp(rollLerp, self.SmoothedRoll, targetRoll)

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

	self.DiveSpeedCurrent = Lerp(self.DiveSpeedLerp, self.DiveSpeedCurrent, self.DIVE_Speed)

	local dt = FrameTime()

	self.DiveWobblePhase = self.DiveWobblePhase + self.DiveWobbleSpeed * dt
	local flatRight = Vector(-dir.y, dir.x, 0)
	if flatRight:LengthSqr() < 0.01 then flatRight = Vector(1, 0, 0) end
	flatRight:Normalize()

	self.DiveWobblePhaseV = self.DiveWobblePhaseV + self.DiveWobbleSpeedV * dt
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
		local travelDir = totalVel:GetNormalized()
		local faceAng   = travelDir:Angle()
		faceAng.r       = 0
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
-- CLEANUP  (TB2 pattern — fade volume then stop)
-- ============================================================

function ENT:OnRemove()
	if self.EngineLoop then
		self.EngineLoop:ChangeVolume(0, 0.5)
		timer.Simple(0.6, function()
			if self.EngineLoop then self.EngineLoop:Stop() end
		end)
	end
end
