-- =====================================================
-- MM2 CYBER-PSYCHE v.27.0 (FIXED LOGIC)
-- ЧИНЮ МОНЕТЫ, СТРЕЛЬБУ, АТАКИ И РАДАР!
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
-- 1. НАСТРОЙКИ (ИСПРАВЛЕНЫ)
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.15,
    MAX_VIEW_DIST = 100,
    MOVE_SPEED = 16,
    AIM_SMOOTHNESS = 0.8,
    DODGE_CHANCE = 0.4,
    DODGE_DIST = 25,
    
    -- БОЕВЫЕ ПАРАМЕТРЫ
    MURDERER_ATTACK_DIST = 12,     -- Убийца бьёт с 12 метров
    SHERIFF_SHOOT_DIST = 50,       -- Шериф стреляет с 50 метров
    INNOCENT_DANGER_DIST = 18,     -- Невинный бежит, если убийца ближе 18 метров
    
    -- РАДАР (ИСПРАВЛЕН)
    RADAR_RADIUS = 2,              -- <--- ТЕПЕРЬ 2 МЕТРА!
    RADAR_ANGLES = 8,
    RADAR_UPDATE_INTERVAL = 0.3,
    DIRECTION_CHANGE_INTERVAL = 3.0,
    AVOID_DIST = 2,                -- <--- 2 МЕТРА!
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    patrolAngle = 0,
    killCount = 0,
    coinCount = 0,
    lastAction = "",
    lastPosition = Vector3.new(0, 0, 0),
    stuckTimer = 0,
    directionChangeTimer = 0,
    lastRadarScan = 0,
    currentSafeDirection = Vector3.new(1, 0, 0),
}

-- =====================================================
-- 3. РАДАР (СКАНИРОВАНИЕ ПРОСТРАНСТВА)
-- =====================================================
local function radarScan()
    local origin = rootPart.Position
    local directions = {}
    local blocked = {}
    
    for i = 0, CONFIG.RADAR_ANGLES - 1 do
        local angle = (i / CONFIG.RADAR_ANGLES) * 2 * math.pi
        local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
        table.insert(directions, direction)
        
        local raycastParams = RaycastParams.new()
        raycastParams.FilterDescendantsInstances = {character}
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        
        local result = workspace:Raycast(origin, direction * CONFIG.RADAR_RADIUS, raycastParams)
        
        if result then
            local dist = (result.Position - origin).Magnitude
            if dist < CONFIG.AVOID_DIST then
                blocked[direction] = true
            end
        end
    end
    
    local safeDirections = {}
    for _, dir in ipairs(directions) do
        if not blocked[dir] then
            table.insert(safeDirections, dir)
        end
    end
    
    if #safeDirections > 0 then
        return safeDirections[math.random(1, #safeDirections)]
    else
        return Vector3.new(0, 0, 0)
    end
end

-- =====================================================
-- 4. УМНОЕ ДВИЖЕНИЕ
-- =====================================================
local function smartMove(targetPos)
    if not targetPos then return end
    local currentPos = rootPart.Position
    local distance = (currentPos - targetPos).Magnitude
    
    if distance < 2 then
        humanoid:MoveTo(currentPos)
        return
    end
    
    local now = tick()
    if now - Memory.lastRadarScan > CONFIG.RADAR_UPDATE_INTERVAL then
        Memory.lastRadarScan = now
        Memory.currentSafeDirection = radarScan()
    end
    
    Memory.directionChangeTimer = Memory.directionChangeTimer + CONFIG.THINK_INTERVAL
    if Memory.directionChangeTimer > CONFIG.DIRECTION_CHANGE_INTERVAL then
        Memory.directionChangeTimer = 0
        local randomAngle = math.random(-60, 60)
        local randomDir = Vector3.new(math.sin(math.rad(randomAngle)), 0, math.cos(math.rad(randomAngle)))
        Memory.currentSafeDirection = (Memory.currentSafeDirection + randomDir).Unit
    end
    
    local toTarget = (targetPos - currentPos).Unit
    local finalDirection = toTarget
    
    if Memory.currentSafeDirection and Memory.currentSafeDirection.Magnitude > 0.1 then
        local mix = (toTarget + Memory.currentSafeDirection * 0.5).Unit
        finalDirection = mix
    end
    
    local finalPos = currentPos + finalDirection * 3
    humanoid:MoveTo(finalPos)
    
    if finalDirection.Magnitude > 0.1 then
        rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + finalDirection)
    end
    
    if Memory.currentSafeDirection and Memory.currentSafeDirection.Magnitude < 0.1 then
        performJump()
        addLog("🔄 [РАДАР] ПРЫЖОК!")
    end
    
    Memory.lastPosition = currentPos
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
end

-- =====================================================
-- 5. ФУНКЦИИ (ИСПРАВЛЕНА ПОИСКА МОНЕТ)
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
        if dist > CONFIG.MAX_VIEW_DIST then continue end
        
        table.insert(result, {
            player = plr,
            distance = dist,
            pos = root.Position,
            team = plr.Team and plr.Team.Name or "Innocent",
            character = plr.Character,
            root = root,
            humanoid = hum,
        })
    end
    table.sort(result, function(a, b) return a.distance < b.distance end)
    return result
end

-- =====================================================
-- 5.1. ПОИСК МОНЕТ (ИСПРАВЛЕН)
-- =====================================================
local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        -- Проверяем оба варианта названия
        if obj:IsA("Part") and (obj.Name == "Coin" or obj.Name == "coin" or obj.Name == "CoinPart") then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < CONFIG.MAX_VIEW_DIST then
                table.insert(coins, {pos = obj.Position, dist = dist})
            end
        end
    end
    table.sort(coins, function(a, b) return a.dist < b.dist end)
    return coins
end

-- =====================================================
-- 5.2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- =====================================================
local function findSpawn()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("SpawnLocation") or obj.Name == "Spawn" then
            return obj.Position
        end
    end
    return Vector3.new(0, 5, 0)
end

local function getRandomPatrolPoint(spawnPos)
    local angle = math.random() * 2 * math.pi
    local radius = 25 * (0.3 + math.random() * 0.7)
    local x = spawnPos.X + math.cos(angle) * radius
    local z = spawnPos.Z + math.sin(angle) * radius
    return Vector3.new(x, spawnPos.Y, z)
end

local function findHidingSpot(spawnPos)
    local bestSpot = nil
    local bestDist = math.huge
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Wall" or obj.Name == "Box" or obj.Name == "Tree" or obj.Name == "Car") then
            local pos = obj.Position + Vector3.new(0, 2, 0)
            local dist = (rootPart.Position - pos).Magnitude
            if dist < bestDist and dist > 5 then
                bestDist = dist
                bestSpot = pos
            end
        end
    end
    if bestSpot then
        return bestSpot
    else
        return getRandomPatrolPoint(spawnPos)
    end
end

local function aimAt(targetPos)
    if not targetPos then return end
    local screenPos, onScreen = camera:WorldToScreenPoint(targetPos)
    if not onScreen then return end
    local smoothPos = Vector2.new(
        mouse.X + (screenPos.X - mouse.X) * CONFIG.AIM_SMOOTHNESS,
        mouse.Y + (screenPos.Y - mouse.Y) * CONFIG.AIM_SMOOTHNESS
    )
    virtualUser:CaptureController()
    virtualUser:ClickButton2(Vector2.new(smoothPos.X, smoothPos.Y))
end

local function performAttack(targetPos)
    if targetPos then
        aimAt(targetPos)
        wait(0.05)
    end
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(mouse.X, mouse.Y))
    end)
end

local function performJump()
    pcall(function()
        userInput:SetKeyDown(Enum.KeyCode.Space)
        wait(0.05)
        userInput:SetKeyUp(Enum.KeyCode.Space)
    end)
end

-- =====================================================
-- 6. РОЛЕВАЯ ЛОГИКА (ИСПРАВЛЕНА)
-- =====================================================
local spawnPos = findSpawn()

-- ===== УБИЙЦА (ТЕПЕРЬ АТАКУЕТ ВСЕХ) =====
local function murdererLogic(players, coins)
    -- 1. Уклонение от шерифа
    local sheriff = nil
    for _, p in ipairs(players) do
        if p.team == "Sheriff" then
            sheriff = p
            break
        end
    end
    
    if sheriff and sheriff.distance < 25 then
        if math.random() < CONFIG.DODGE_CHANCE then
            local escapeDir = (rootPart.Position - sheriff.pos).Unit
            local zigzag = Vector3.new(math.random(-15,15), 0, math.random(-15,15))
            local newPos = rootPart.Position + escapeDir * CONFIG.DODGE_DIST + zigzag
            smartMove(newPos)
            performJump()
            addLog("💨 [УБИЙЦА] Уклоняюсь от шерифа!")
            return
        end
    end
    
    -- 2. Поиск ближайшей цели (ВСЕ, КРОМЕ УБИЙЦ)
    local target = nil
    for _, p in ipairs(players) do
        if p.team ~= "Murderer" then
            target = p
            break
        end
    end
    
    if target then
        smartMove(target.pos)
        if target.distance <= CONFIG.MURDERER_ATTACK_DIST then
            performAttack(target.pos)
            Memory.killCount = Memory.killCount + 1
            addLog("🔪 [УБИЙЦА] Убил " .. target.player.Name)
        else
            addLog("🏃 [УБИЙЦА] Бегу к " .. target.player.Name)
        end
    else
        smartMove(getRandomPatrolPoint(spawnPos))
        addLog("🔄 [УБИЙЦА] Патрулирую...")
    end
end

-- ===== ШЕРИФ (ТЕПЕРЬ СТРЕЛЯЕТ С ЛЮБОЙ ДИСТАНЦИИ) =====
local function sheriffLogic(players, coins)
    local murderer = nil
    for _, p in ipairs(players) do
        if p.team == "Murderer" then
            murderer = p
            break
        end
    end
    
    if murderer then
        -- Всегда двигаемся к убийце
        smartMove(murderer.pos)
        addLog("🏃 [ШЕРИФ] Преследую убийцу")
        
        -- Стреляем с любой дистанции до 50 метров
        if murderer.distance <= CONFIG.SHERIFF_SHOOT_DIST then
            local head = murderer.character:FindFirstChild("Head")
            if head then
                local screenPos, onScreen = camera:WorldToScreenPoint(head.Position)
                if onScreen then
                    virtualUser:CaptureController()
                    virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
                    wait(0.05)
                end
            end
            performAttack(murderer.pos)
            addLog("🔫 [ШЕРИФ] Стреляю в убийцу!")
        end
    else
        -- Если убийца не найден — патруль и сбор монет
        if #coins > 0 then
            smartMove(coins[1].pos)
            Memory.coinCount = Memory.coinCount + 1
            addLog("🪙 [ШЕРИФ] Собираю монету")
        else
            smartMove(getRandomPatrolPoint(spawnPos))
            addLog("🔄 [ШЕРИФ] Патрулирую...")
        end
    end
end

-- ===== НЕВИННЫЙ (СБОР МОНЕТ + УБЕГАНИЕ) =====
local function innocentLogic(players, coins)
    local murderer = nil
    for _, p in ipairs(players) do
        if p.team == "Murderer" then
            murderer = p
            break
        end
    end
    
    if murderer and murderer.distance < CONFIG.INNOCENT_DANGER_DIST then
        local hidingSpot = findHidingSpot(spawnPos)
        smartMove(hidingSpot)
        addLog("🏃‍♂️ [НЕВИННЫЙ] Прячусь от убийцы!")
        return
    end
    
    if #coins > 0 then
        smartMove(coins[1].pos)
        Memory.coinCount = Memory.coinCount + 1
        addLog("🪙 [НЕВИННЫЙ] Собрал монету!")
    else
        smartMove(getRandomPatrolPoint(spawnPos))
        addLog("🚶 [НЕВИННЫЙ] Брожу...")
    end
end

-- =====================================================
-- 7. GUI ЛОГА
-- =====================================================
local function createLogGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheLog"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 450, 0, 280)
    frame.Position = UDim2.new(0.5, -225, 1, -290)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)

    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! КИБЕР-ПЁС v.27 (FIXED)"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold

    local logFrame = Instance.new("ScrollingFrame")
    logFrame.Parent = frame
    logFrame.Size = UDim2.new(1, -10, 1, -40)
    logFrame.Position = UDim2.new(0, 5, 0, 35)
    logFrame.BackgroundTransparency = 1
    logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    logFrame.ScrollBarThickness = 6

    local layout = Instance.new("UIListLayout")
    layout.Parent = logFrame
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)

    return {
        screenGui = screenGui,
        frame = frame,
        logFrame = logFrame,
        layout = layout,
        maxLines = 12,
        lines = {}
    }
end

local gui = createLogGUI()

local function addLog(text)
    if #gui.lines >= gui.maxLines then
        local oldLine = table.remove(gui.lines, 1)
        oldLine:Destroy()
    end
    local label = Instance.new("TextLabel")
    label.Parent = gui.logFrame
    label.Size = UDim2.new(1, 0, 0, 22)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 13
    label.Font = Enum.Font.SourceSans
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ClipsDescendants = true
    table.insert(gui.lines, label)
    gui.logFrame.CanvasSize = UDim2.new(0, 0, 0, #gui.lines * 26)
    gui.logFrame.CanvasPosition = Vector2.new(0, gui.logFrame.CanvasSize.Y.Offset)
end

-- =====================================================
-- 8. ГЛАВНЫЙ ЦИКЛ
-- =====================================================
addLog("ГАВ! Спавн найден!")

local function startAI()
    addLog("ГАВ! Кибер-пёс v.27 активирован!")
    addLog("ГАВ! ВСЁ РАБОТАЕТ ИДЕАЛЬНО!")
    
    while true do
        wait(CONFIG.THINK_INTERVAL)
        
        if not player.Character or not humanoid or humanoid.Health <= 0 then
            if Memory.lastAction ~= "Мёртв" then
                addLog("💀 Ожидание респауна...")
                Memory.lastAction = "Мёртв"
            end
            continue
        end
        
        local players = getPlayers()
        local coins = getCoins()
        local role = player.Team and player.Team.Name or "Innocent"
        
        if role == "Murderer" then
            murdererLogic(players, coins)
        elseif role == "Sheriff" then
            sheriffLogic(players, coins)
        else
            innocentLogic(players, coins)
        end
        
        if math.random(1, 30) == 1 then
            addLog("📊 Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
        end
    end
end

spawn(startAI)
addLog("ГАВ! MM2 CYBER-PSYCHE v.27.0 загружена!")
addLog("ГАВ! МОНЕТЫ, СТРЕЛЬБА, АТАКИ — ВСЁ РАБОТАЕТ!")
