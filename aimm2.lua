-- =====================================================
-- MM2 CYBER-PSYCHE v.28.0 (FINAL)
-- ХОДИТ, СТРЕЛЯЕТ, СОБИРАЕТ МОНЕТЫ, РАДАР 2 МЕТРА
-- ГАВ!
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")
local mouse = player:GetMouse()
local userInput = game:GetService("UserInputService")

-- =====================================================
-- 1. НАСТРОЙКИ
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.2,
    MOVE_SPEED = 16,
    ATTACK_DIST = 12,
    SHOOT_DIST = 50,
    DANGER_DIST = 18,
    RADAR_RADIUS = 2,
    RADAR_ANGLES = 8,
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    killCount = 0,
    coinCount = 0,
    lastAction = "",
    lastRadarScan = 0,
    safeDir = Vector3.new(1, 0, 0),
}

-- =====================================================
-- 3. РАДАР (СКАНИРУЕТ 2 МЕТРА)
-- =====================================================
local function getSafeDirection()
    local now = tick()
    if now - Memory.lastRadarScan < 0.3 then return Memory.safeDir end
    Memory.lastRadarScan = now
    
    local origin = rootPart.Position
    local blocked = {}
    
    for i = 0, CONFIG.RADAR_ANGLES - 1 do
        local angle = (i / CONFIG.RADAR_ANGLES) * 2 * math.pi
        local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {character}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        
        local result = workspace:Raycast(origin, dir * CONFIG.RADAR_RADIUS, params)
        if result then blocked[dir] = true end
    end
    
    -- Ищем свободное направление
    for i = 0, CONFIG.RADAR_ANGLES - 1 do
        local angle = (i / CONFIG.RADAR_ANGLES) * 2 * math.pi
        local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        if not blocked[dir] then
            Memory.safeDir = dir
            return dir
        end
    end
    
    return Vector3.new(1, 0, 0)
end

-- =====================================================
-- 4. ДВИЖЕНИЕ (ПРОСТОЕ И НАДЁЖНОЕ)
-- =====================================================
local function moveTo(targetPos)
    if not targetPos then return end
    
    -- Убеждаемся, что координаты нормальные
    if targetPos.Y < 0 then targetPos = Vector3.new(targetPos.X, 5, targetPos.Z) end
    
    -- Устанавливаем скорость
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
    
    -- Проверяем радар и корректируем направление
    local safeDir = getSafeDirection()
    local toTarget = (targetPos - rootPart.Position).Unit
    local finalDir = (toTarget + safeDir * 0.3).Unit
    
    -- Двигаемся
    local movePos = rootPart.Position + finalDir * 4
    humanoid:MoveTo(movePos)
    
    -- Поворачиваемся к цели
    if toTarget.Magnitude > 0.1 then
        rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + toTarget)
    end
end

-- =====================================================
-- 5. АТАКА
-- =====================================================
local function aimAndShoot(targetPos)
    if not targetPos then return end
    local screenPos, onScreen = camera:WorldToScreenPoint(targetPos)
    if onScreen then
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
        wait(0.05)
        virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
    end
end

local function jump()
    pcall(function()
        userInput:SetKeyDown(Enum.KeyCode.Space)
        wait(0.05)
        userInput:SetKeyUp(Enum.KeyCode.Space)
    end)
end

-- =====================================================
-- 6. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- =====================================================
local function getPlayers()
    local result = {}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local root = plr.Character:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local hum = plr.Character:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then continue end
        
        local dist = (rootPart.Position - root.Position).Magnitude
        if dist > 100 then continue end
        
        table.insert(result, {
            player = plr,
            distance = dist,
            pos = root.Position,
            team = plr.Team and plr.Team.Name or "Innocent",
            character = plr.Character,
            root = root,
        })
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Coin" or obj.Name == "coin") then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < 100 then
                table.insert(coins, {pos = obj.Position, dist = dist})
            end
        end
    end
    table.sort(coins, function(a, b) return a.dist < b.dist end)
    return coins
end

local function findSpawn()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("SpawnLocation") or obj.Name == "Spawn" then
            return obj.Position
        end
    end
    return Vector3.new(0, 5, 0)
end

local function getPatrolPoint()
    local spawn = findSpawn()
    local angle = math.random() * 2 * math.pi
    local radius = 15 + math.random() * 20
    return Vector3.new(
        spawn.X + math.cos(angle) * radius,
        spawn.Y + 2,
        spawn.Z + math.sin(angle) * radius
    )
end

local function getHidingSpot()
    -- Ищем укрытие
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Wall" or obj.Name == "Box" or obj.Name == "Tree") then
            return obj.Position + Vector3.new(0, 2, 0)
        end
    end
    return getPatrolPoint()
end

-- =====================================================
-- 7. РОЛЕВАЯ ЛОГИКА
-- =====================================================
local function murdererLogic(players)
    -- Уклонение от шерифа
    local sheriff = nil
    for _, p in ipairs(players) do
        if p.team == "Sheriff" and p.distance < 25 then
            sheriff = p
            break
        end
    end
    
    if sheriff then
        local escapeDir = (rootPart.Position - sheriff.pos).Unit
        local newPos = rootPart.Position + escapeDir * 20 + Vector3.new(math.random(-10,10), 0, math.random(-10,10))
        moveTo(newPos)
        jump()
        return
    end
    
    -- Атака ближайшего игрока
    local target = players[1]
    if target then
        moveTo(target.pos)
        if target.distance <= CONFIG.ATTACK_DIST then
            aimAndShoot(target.pos)
            Memory.killCount = Memory.killCount + 1
        end
    else
        moveTo(getPatrolPoint())
    end
end

local function sheriffLogic(players, coins)
    -- Поиск убийцы
    local murderer = nil
    for _, p in ipairs(players) do
        if p.team == "Murderer" then
            murderer = p
            break
        end
    end
    
    if murderer then
        moveTo(murderer.pos)
        if murderer.distance <= CONFIG.SHOOT_DIST then
            -- Целимся в голову
            local head = murderer.character:FindFirstChild("Head")
            if head then
                local screenPos, onScreen = camera:WorldToScreenPoint(head.Position)
                if onScreen then
                    virtualUser:CaptureController()
                    virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
                    wait(0.05)
                    virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
                end
            end
        end
    elseif #coins > 0 then
        moveTo(coins[1].pos)
        Memory.coinCount = Memory.coinCount + 1
    else
        moveTo(getPatrolPoint())
    end
end

local function innocentLogic(players, coins)
    -- Поиск убийцы
    local murderer = nil
    for _, p in ipairs(players) do
        if p.team == "Murderer" then
            murderer = p
            break
        end
    end
    
    if murderer and murderer.distance < CONFIG.DANGER_DIST then
        moveTo(getHidingSpot())
        return
    end
    
    if #coins > 0 then
        moveTo(coins[1].pos)
        Memory.coinCount = Memory.coinCount + 1
    else
        moveTo(getPatrolPoint())
    end
end

-- =====================================================
-- 8. ГЛАВНЫЙ ЦИКЛ
-- =====================================================
print("ГАВ! Кибер-пёс v.28.0 активирован, хозяйка!")

while true do
    wait(CONFIG.THINK_INTERVAL)
    
    if not player.Character or not humanoid or humanoid.Health <= 0 then
        continue
    end
    
    local players = getPlayers()
    local coins = getCoins()
    local role = player.Team and player.Team.Name or "Innocent"
    
    if role == "Murderer" then
        murdererLogic(players)
    elseif role == "Sheriff" then
        sheriffLogic(players, coins)
    else
        innocentLogic(players, coins)
    end
    
    -- Статистика
    if math.random(1, 30) == 1 then
        print("ГАВ! Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
    end
end
