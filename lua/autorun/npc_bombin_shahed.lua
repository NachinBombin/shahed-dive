AddCSLuaFile()

if SERVER then

    util.AddNetworkString("BombinShahed_FlareSpawned")

    -- ============================================================
    -- ConVars
    -- ============================================================

    local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

    local cv_enabled      = CreateConVar("npc_bombinshahed_enabled",      "1",    SHARED_FLAGS, "Enable/disable Shahed loiter munition calls")
    local cv_chance       = CreateConVar("npc_bombinshahed_chance",       "0.12", SHARED_FLAGS, "Probability per check")
    local cv_interval     = CreateConVar("npc_bombinshahed_interval",     "12",   SHARED_FLAGS, "Seconds between NPC checks")
    local cv_cooldown     = CreateConVar("npc_bombinshahed_cooldown",     "50",   SHARED_FLAGS, "Cooldown per NPC")
    local cv_max_dist     = CreateConVar("npc_bombinshahed_max_dist",     "3000", SHARED_FLAGS, "Max call distance")
    local cv_min_dist     = CreateConVar("npc_bombinshahed_min_dist",     "400",  SHARED_FLAGS, "Min call distance")
    local cv_delay        = CreateConVar("npc_bombinshahed_delay",        "5",    SHARED_FLAGS, "Flare to arrival delay")
    local cv_life         = CreateConVar("npc_bombinshahed_lifetime",     "40",   SHARED_FLAGS, "Munition lifetime seconds")
    local cv_speed        = CreateConVar("npc_bombinshahed_speed",        "250",  SHARED_FLAGS, "Forward orbit speed HU/s")
    local cv_radius       = CreateConVar("npc_bombinshahed_radius",       "2500", SHARED_FLAGS, "Orbit radius HU")
    local cv_height       = CreateConVar("npc_bombinshahed_height",       "2500", SHARED_FLAGS, "Altitude above ground HU")
    local cv_dive_damage  = CreateConVar("npc_bombinshahed_dive_damage",  "700",  SHARED_FLAGS, "Dive explosion damage")
    local cv_dive_radius  = CreateConVar("npc_bombinshahed_dive_radius",  "900",  SHARED_FLAGS, "Dive explosion radius HU")
    local cv_announce     = CreateConVar("npc_bombinshahed_announce",     "0",    SHARED_FLAGS, "Debug prints")

    -- ============================================================
    -- NPC classes that can call the munition
    -- ============================================================

    local CALLERS = {
        ["npc_combine_s"]     = true,
        ["npc_metropolice"]   = true,
        ["npc_combine_elite"] = true,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================

    local function BS_Debug(msg)
        if not cv_announce:GetBool() then return end
        local full = "[Bombin Shahed] " .. tostring(msg)
        print(full)
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, full) end
        end
    end

    local function CheckSkyAbove(pos)
        local tr = util.TraceLine({
            start  = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 1050),
        })
        if tr.Hit and not tr.HitSky then
            tr = util.TraceLine({
                start  = tr.HitPos + Vector(0, 0, 50),
                endpos = tr.HitPos + Vector(0, 0, 1000),
            })
        end
        return not (tr.Hit and not tr.HitSky)
    end

    local function ThrowSupportFlare(npc, targetPos)
        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()

        local flare = ents.Create("ent_bombin_flare_blue")
        if not IsValid(flare) then
            BS_Debug("Flare spawn failed")
            return nil
        end

        flare:SetPos(npcEyePos + toTarget * 52)
        flare:SetAngles(npc:GetAngles())
        flare:Spawn()
        flare:Activate()

        local dir  = targetPos - flare:GetPos()
        local dist = dir:Length()
        dir:Normalize()

        timer.Simple(0, function()
            if not IsValid(flare) then return end
            local phys = flare:GetPhysicsObject()
            if not IsValid(phys) then return end
            phys:SetVelocity(dir * 700 + Vector(0, 0, dist * 0.25))
            phys:Wake()
        end)

        net.Start("BombinShahed_FlareSpawned")
        net.WriteEntity(flare)
        net.Broadcast()

        BS_Debug("Flare thrown")
        return flare
    end

    local function SpawnShahedAtPos(centerPos, callDir)
        if not scripted_ents.GetStored("ent_bombin_shahed") then
            BS_Debug("ent_bombin_shahed not registered")
            return false
        end

        local ent = ents.Create("ent_bombin_shahed")
        if not IsValid(ent) then
            BS_Debug("ents.Create returned invalid entity")
            return false
        end

        ent:SetPos(centerPos)
        ent:SetAngles(callDir:Angle())
        ent:SetVar("CenterPos",           centerPos)
        ent:SetVar("CallDir",             callDir)
        ent:SetVar("Lifetime",            cv_life:GetFloat())
        ent:SetVar("Speed",               cv_speed:GetFloat())
        ent:SetVar("OrbitRadius",         cv_radius:GetFloat())
        ent:SetVar("SkyHeightAdd",        cv_height:GetFloat())
        ent:SetVar("DIVE_ExplosionDamage", cv_dive_damage:GetFloat())
        ent:SetVar("DIVE_ExplosionRadius", cv_dive_radius:GetFloat())
        ent:Spawn()
        ent:Activate()

        if not IsValid(ent) then
            BS_Debug("Entity invalid after Spawn()")
            return false
        end

        BS_Debug("Shahed spawned at " .. tostring(centerPos))
        return true
    end

    local function FireShahed(npc, target)
        if not IsValid(npc) then BS_Debug("NPC invalid") return false end
        if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
            BS_Debug("Target invalid") return false
        end

        local targetPos = target:GetPos() + Vector(0, 0, 36)
        if not CheckSkyAbove(targetPos) then
            BS_Debug("No open sky above target") return false
        end

        local callDir = targetPos - npc:GetPos()
        callDir.z = 0
        if callDir:LengthSqr() <= 1 then callDir = npc:GetForward() callDir.z = 0 end
        if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
        callDir:Normalize()

        local flare = ThrowSupportFlare(npc, targetPos)
        if not IsValid(flare) then BS_Debug("Flare failed") return false end

        local fallbackPos = Vector(targetPos.x, targetPos.y, targetPos.z)
        local storedDir   = Vector(callDir.x, callDir.y, callDir.z)

        timer.Simple(cv_delay:GetFloat(), function()
            local centerPos = IsValid(flare) and flare:GetPos() or fallbackPos
            SpawnShahedAtPos(centerPos, storedDir)
        end)

        return true
    end

    -- ============================================================
    -- MAIN POLL TIMER
    -- ============================================================

    timer.Create("BombinShahed_Think", 0.5, 0, function()
        if not cv_enabled:GetBool() then return end

        local now      = CurTime()
        local interval = math.max(1, cv_interval:GetFloat())

        for _, npc in ipairs(ents.GetAll()) do
            if not IsValid(npc) or not CALLERS[npc:GetClass()] then continue end

            if not npc.__bombinshahed_hooked then
                npc.__bombinshahed_hooked    = true
                npc.__bombinshahed_nextCheck = now + math.Rand(1, interval)
                npc.__bombinshahed_lastCall  = 0
            end

            if now < npc.__bombinshahed_nextCheck then continue end

            local jitter = math.min(2, interval * 0.5)
            npc.__bombinshahed_nextCheck = now + interval + math.Rand(-jitter, jitter)

            if now - npc.__bombinshahed_lastCall < cv_cooldown:GetFloat() then continue end
            if npc:Health() <= 0 then continue end

            local enemy = npc:GetEnemy()
            if not IsValid(enemy) or not enemy:IsPlayer() or not enemy:Alive() then continue end

            local dist = npc:GetPos():Distance(enemy:GetPos())
            if dist > cv_max_dist:GetFloat() or dist < cv_min_dist:GetFloat() then continue end

            if math.random() > cv_chance:GetFloat() then continue end

            if FireShahed(npc, enemy) then
                npc.__bombinshahed_lastCall = now
                BS_Debug("Call accepted targeting " .. tostring(enemy))
            end
        end
    end)

end -- SERVER

-- ============================================================
-- CLIENT — flare dynamic light
-- ============================================================

if CLIENT then
    local activeFlares = {}

    net.Receive("BombinShahed_FlareSpawned", function()
        local flare = net.ReadEntity()
        if IsValid(flare) then
            activeFlares[flare:EntIndex()] = flare
        end
    end)

    hook.Add("Think", "BombinShahed_FlareLight", function()
        for idx, flare in pairs(activeFlares) do
            if not IsValid(flare) then
                activeFlares[idx] = nil
                continue
            end

            local dlight = DynamicLight(flare:EntIndex())
            if dlight then
                dlight.Pos        = flare:GetPos()
                dlight.r          = 0
                dlight.g          = 80
                dlight.b          = 255
                dlight.Brightness = (math.random() > 0.4) and math.Rand(4.0, 6.0) or math.Rand(0.0, 0.2)
                dlight.Size       = 55
                dlight.Decay      = 3000
                dlight.DieTime    = CurTime() + 0.05
            end
        end
    end)
end
