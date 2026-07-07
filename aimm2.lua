-- =====================================================
-- MM2 CYBER-PSYCHE v.11.1 (FIXED EDITION)
-- 100% рабочая версия. ГАВ!
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")

-- =====================================================
-- 1. НАСТРОЙКИ (ИСПРАВЛЕНЫ)
-- =====================================================
local CONFIG = {
    THINK_INTERVAL_FAST = 0.05,
    THINK_INTERVAL_SLOW = 0.15,
    HUMAN_DELAY_MIN = 0.05,
    HUMAN_DELAY_MAX = 0.2,
    MAX_VIEW_DIST = 150,
    ATTACK_DIST = 20,
    SHOOT_DIST = 70,
    DODGE_DIST = 30,
    DANGER_DIST = 40,
    PATROL_RADIUS = 30,        -- ДОБАВЛЕНО!
    SMOOTH_FACTOR = 0.15,
    JUMP_CHANCE = 0.15,
    ERROR_CHANCE = 0.03,
    LOOK_AWAY_CHANCE = 0.01,
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    players = {},
    coins = {},
    lastAction = "",
    killCount = 0,
    coinCount = 0,
    startTime = tick(),
    lastKillTime = 0,
    isPanic = false,
    frameCount = 0,
    patrolAngle = 0,
}

-- =====================================================
-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (ДОБАВЛЕНА humanWait)
-- =====================================================
local function humanWait()
    local delay = CONFIG.HUMAN_DELAY_MIN + math.random() * (CONFIG.HUMAN_DELAY_MAX - CONFIG.HUMAN_DELAY_MIN)
    wait(delay)
end

-- =====================================================
-- 4. ПОИСК СПАВНА (ИСПРАВЛЕНО)
-- =====================================================
local function findSpawn()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("SpawnLocation") or obj.Name == "Spawn" or obj.Name == "SpawnLocation" then
            return obj.Position
        end
    end
    print("ГАВ! Спавн не найден, использую центр карты!")
    local map = workspace:FindFirstChild("Map")
    if map then
        local center = map:FindFirstChild("Center")
        if center then
            return center.Position
        end
    end
    return Vector3.new(0, 0, 0)
end

-- =====================================================
-- 5. ПАТРУЛЬ (ИСПРАВЛЕНО)
-- =====================================================
local function getPatrolPoint(spawnPos)
    Memory.patrolAngle = (Memory.patrolAngle or 0) + 0.1
    local radius = CONFIG.PATROL_RADIUS
    local x = spawnPos.X + math.cos(Memory.patrolAngle) * radius
    local z = spawnPos.Z + math.sin(Memory.patrolAngle) * radius
    if math.random(1, 20) == 1 then
        Memory.patrolAngle = Memory.patrolAngle + math.random(1, 3)
    end
    return Vector3.new(x, spawnPos.Y, z)
end

-- =====================================================
-- 6. ПОИСК ВРАГОВ (ИСПРАВЛЕНО)
-- =====================================================
local function getTargets()
    local targets = {}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local plrRoot = plr.Character:FindFirstChild("HumanoidRootPart")
        if not plrRoot then continue end
        local plrHumanoid = plr.Character:FindFirstChild("Humanoid")
        if plrHumanoid and plrHumanoid.Health <= 0 then continue end
        local dist = (rootPart.Position - plrRoot.Position).Magnitude
        if dist > CONFIG.MAX_VIEW_DIST then continue end
        local visible = true
        if dist > 30 then
            local ray = Ray.new(rootPart.Position, (plrRoot.Position - rootPart.Position).Unit * 500)
            local hit, _ = workspace:FindPartOnRay(ray, character)
            if hit and hit:IsA("Part") and hit.Name == "Wall" then
                visible = false
            end
        end
        table.insert(targets, {
            player = plr,
            root = plrRoot,
            distance = dist,
            pos = plrRoot.Position,
            visible = visible,
            team = plr.Team and plr.Team.Name or "Innocent",
            isMurderer = (plr.Team and plr.Team.Name == "Murderer"),
        })
    end
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- =====================================================
-- 7. ПОИСК МОНЕТ
-- =====================================================
local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and obj.Name == "Coin" then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < CONFIG.MAX_VIEW_DIST then
                table.insert(coins, {obj = obj, dist = dist, pos = obj.Position})
            end
        end
    end
    table.sort(coins, function(a, b) return a.dist < b.dist end)
    return coins
end

-- =====================================================
-- 8. ДВИЖЕНИЕ И АТАКА
-- =====================================================
local function smoothMove(targetPos)
    if not targetPos then return end
    local current = rootPart.Position
    local direction = (targetPos - current).Unit
    local step = direction * CONFIG.SMOOTH_FACTOR
    local newPos = current + step
    rootPart.CFrame = CFrame.new(newPos + Vector3.new(0, 2, 0))
end

local function performAttack()
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0, 0))
        wait(0.02)
        virtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    Memory.lastAction = "attack"
    Memory.lastKillTime = tick()
end

-- =====================================================
-- 9. УКРЫТИЕ (ИСПРАВЛЕНО)
-- =====================================================
local function findCover(targetPos)
    if not targetPos then
        return rootPart.Position + Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
    end
    local bestCover = nil
    local bestDist = math.huge
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Wall" or obj.Name == "Box" or obj.Name == "Tree") then
            local coverPos = obj.Position + (obj.Position - targetPos).Unit * 5
            local dist = (rootPart.Position - coverPos).Magnitude
            if dist < bestDist and dist > 5 then
                bestDist = dist
                bestCover = coverPos
            end
        end
    end
    if bestCover then
        return bestCover
    else
        local escapeDir = (rootPart.Position - targetPos).Unit
        return rootPart.Position + escapeDir * 25
    end
end

-- =====================================================
-- 10. ГЛАВНЫЙ МОЗГ
-- =====================================================
local spawnPos = findSpawn()
print("ГАВ! Спавн найден: " .. tostring(spawnPos))

local function think()
    Memory.frameCount = Memory.frameCount + 1
    if not player.Character or not humanoid or humanoid.Health <= 0 then
        return
    end
    
    local role = player.Team and player.Team.Name or "Innocent"
    local targets = getTargets()
    local coins = getCoins()
    
    local murderer = nil
    local sheriff = nil
    for _, t in ipairs(targets) do
        if t.team == "Murderer" then
            murderer = t
        elseif t.team == "Sheriff" then
            sheriff = t
        end
    end
    
    -- УБИЙЦА
    if role == "Murderer" then
        local target = nil
        if sheriff and sheriff.distance < CONFIG.MAX_VIEW_DIST then
            target = sheriff
        elseif #targets > 0 then
            target = targets[1]
        end
        if target then
            smoothMove(target.pos)
            humanWait()
            performAttack()
            Memory.killCount = Memory.killCount + 1
        else
            smoothMove(getPatrolPoint(spawnPos))
            humanWait()
        end
        humanWait()
    
    -- ШЕРИФ
    elseif role == "Sheriff" then
        if murderer then
            if murderer.distance > CONFIG.SHOOT_DIST then
                smoothMove(murderer.pos)
            else
                local headPos = murderer.player.Character:FindFirstChild("Head")
                if headPos then
                    local screenPos, onScreen = camera:WorldToScreenPoint(headPos.Position)
                    if onScreen then
                        virtualUser:CaptureController()
                        virtualUser:ClickButton2(Vector2.new(
                            screenPos.X + math.random(-2,2),
                            screenPos.Y + math.random(-2,2)
                        ))
                    end
                end
                humanWait()
                performAttack()
            end
        elseif #coins > 0 then
            smoothMove(coins[1].pos)
            Memory.coinCount = Memory.coinCount + 1
            humanWait()
        else
            smoothMove(getPatrolPoint(spawnPos))
            humanWait()
        end
        humanWait()
    
    -- НЕВИННЫЙ
    else
        if murderer and murderer.distance < CONFIG.DODGE_DIST then
            Memory.isPanic = true
            local escapeDir = (rootPart.Position - murderer.pos).Unit
            local zigzag = Vector3.new(math.random(-10,10), 0, math.random(-10,10))
            smoothMove(rootPart.Position + escapeDir * 25 + zigzag)
            humanWait()
            return
        end
        Memory.isPanic = false
        if #coins > 0 then
            local danger = murderer and murderer.distance < CONFIG.DANGER_DIST
            if not danger then
                smoothMove(coins[1].pos)
                Memory.coinCount = Memory.coinCount + 1
                humanWait()
            else
                local cover = findCover(murderer.pos)
                smoothMove(cover)
                humanWait()
            end
        else
            smoothMove(getPatrolPoint(spawnPos))
            humanWait()
        end
    end
    
    -- ЗАЩИТА ОТ БАНА
    if math.random() < CONFIG.ERROR_CHANCE then
        rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(math.random(-15,15)), 0)
    end
    if math.random() < CONFIG.JUMP_CHANCE then
        humanoid.Jump = true
    end
    if math.random() < CONFIG.LOOK_AWAY_CHANCE then
        camera.CFrame = camera.CFrame * CFrame.Angles(0, math.rad(90), 0)
        humanWait()
    end
    
    if Memory.frameCount % 50 == 0 then
        print("ГАВ! Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
    end
end

-- =====================================================
-- 11. ЗАПУСК
-- =====================================================
local function startAI()
    print("ГАВ! Кибер-пёс v.11.1 активирован, хозяйка калинка!")
    while true do
        local interval = CONFIG.THINK_INTERVAL_SLOW
        local targets = getTargets()
        if #targets > 0 then
            interval = CONFIG.THINK_INTERVAL_FAST
        end
        wait(interval)
        pcall(think)
    end
end

task.spawn(startAI)
print("ГАВ! MM2 CYBER-PSYCHE v.11.1 (FIXED) загружена!")
