-- ============================================
-- NPC EXPLORER v4.1 (FIXED STUTTER + SMOOTH ROTATION)
-- by Цербер для хозяйки
-- Исправлено: тряска, поворот, застревание
-- ============================================

local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local userInput = game:GetService("UserInputService")
local virtualInput = game:GetService("VirtualInputManager")
local players = game:GetService("Players")
local pathfindingService = game:GetService("PathfindingService")

-- Переменные
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")
local camera = workspace.CurrentCamera

-- Настройки
local CONFIG = {
    MOVE_SPEED = 16,
    EXPLORE_RADIUS = 80,
    MIN_EXPLORE_RADIUS = 15,
    EXPLORE_CHANGE_TIME = 10,
    FOLLOW_DISTANCE = 4,
    PATH_UPDATE_INTERVAL = 1.0,    -- Реже обновляем путь
    STUCK_THRESHOLD = 2.5,
    JUMP_FORCE = 50,
    ROTATION_SPEED = 0.3,          -- Плавный поворот
    PAUSE_CHANCE = 0.08,
    PAUSE_TIME = 2.0,
    WAYPOINT_REACH_DIST = 1.0,     -- Дистанция до точки, чтобы считать её достигнутой
}

-- Память
local Memory = {
    running = true,
    exploreTarget = nil,
    exploreTimer = 0,
    lastPosition = nil,
    stuckTimer = 0,
    isPaused = false,
    pauseTimer = 0,
    targetPlayer = nil,
    targetHighlight = nil,
    path = nil,
    currentWaypoint = 1,
    pathParts = {},
    lastPathUpdate = 0,
    isJumping = false,
    isMoving = false,
}

-- Логирование
local function addLog(text)
    print("[NPC] " .. text)
end

-- ============================================
-- 1. ОБНОВЛЕНИЕ ПЕРСОНАЖА
-- ============================================
local function updateCharacter()
    character = player.Character
    if not character then return false end
    humanoid = character:FindFirstChild("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
    head = character:FindFirstChild("Head")
    if humanoid and rootPart and head then
        humanoid.WalkSpeed = CONFIG.MOVE_SPEED
        humanoid.JumpPower = CONFIG.JUMP_FORCE
        humanoid.AutoRotate = false
        return true
    end
    return false
end
updateCharacter()
player.CharacterAdded:Connect(updateCharacter)

-- ============================================
-- 2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================
local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function isOnGround()
    if not rootPart then return false end
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local rayResult = workspace:Raycast(rootPart.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -2, 0), rayParams)
    return rayResult ~= nil
end

local function getHeightAt(position)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = {character}
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    local rayResult = workspace:Raycast(position + Vector3.new(0, 10, 0), Vector3.new(0, -25, 0), rayParams)
    if rayResult then
        return rayResult.Position.Y
    end
    return position.Y
end

-- ============================================
-- 3. ПОВОРОТ ЛИЦА (ТОЛЬКО ЧЕРЕЗ CFrame, БЕЗ КОНФЛИКТОВ)
-- ============================================
local function smoothRotate(direction)
    if not direction or direction.Magnitude < 0.1 then return end
    
    -- Нормализуем направление в плоскости XZ
    local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
    if flatDir.Magnitude < 0.1 then return end
    
    -- Вычисляем целевой угол
    local targetAngle = math.atan2(flatDir.X, flatDir.Z)
    local currentAngle = math.atan2(rootPart.CFrame.LookVector.X, rootPart.CFrame.LookVector.Z)
    
    -- Плавное вращение
    local angleDiff = targetAngle - currentAngle
    while angleDiff > math.pi do angleDiff = angleDiff - 2 * math.pi end
    while angleDiff < -math.pi do angleDiff = angleDiff + 2 * math.pi end
    
    local newAngle = currentAngle + angleDiff * CONFIG.ROTATION_SPEED
    local newCFrame = CFrame.new(rootPart.Position) * CFrame.Angles(0, newAngle, 0)
    rootPart.CFrame = newCFrame
    
    -- Поворот головы (слегка)
    if head then
        local headAngle = math.atan2(flatDir.X, flatDir.Z)
        local headCFrame = CFrame.new(head.Position) * CFrame.Angles(0, headAngle, 0)
        head.CFrame = head.CFrame:Lerp(headCFrame, 0.2)
    end
end

-- ============================================
-- 4. PATHFINDING SERVICE
-- ============================================
local function computePath(targetPosition)
    if not rootPart or not targetPosition then return nil end
    
    local pathParams = {
        AgentRadius = 1.5,
        AgentHeight = 4,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 2,
    }
    
    local path = pathfindingService:CreatePath(pathParams)
    local success = pcall(function()
        path:ComputeAsync(rootPart.Position, targetPosition)
    end)
    
    if not success or path.Status ~= Enum.PathStatus.Success then
        return nil
    end
    
    return path
end

local function getWaypoints(path)
    local waypoints = {}
    for _, waypoint in ipairs(path:GetWaypoints()) do
        table.insert(waypoints, {
            position = waypoint.Position,
            action = waypoint.Action
        })
    end
    return waypoints
end

-- ============================================
-- 5. ОТОБРАЖЕНИЕ ЖЁЛТОГО ПУТИ
-- ============================================
local function clearPath()
    for _, part in pairs(Memory.pathParts) do
        part:Destroy()
    end
    Memory.pathParts = {}
end

local function drawPath(waypoints)
    clearPath()
    if not waypoints or #waypoints == 0 then return end
    
    for i, waypoint in ipairs(waypoints) do
        local part = Instance.new("Part")
        part.Size = Vector3.new(0.4, 0.1, 0.4)
        part.Position = waypoint.position + Vector3.new(0, 0.2, 0)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.new("Bright yellow")
        part.Transparency = 0.5
        part.Parent = workspace
        table.insert(Memory.pathParts, part)
    end
end

-- ============================================
-- 6. УПРАВЛЕНИЕ WASD (БЕЗ РЫВКОВ)
-- ============================================
local keysPressed = {
    W = false,
    S = false,
    A = false,
    D = false,
}

local function pressKey(key)
    if not keysPressed[key.Name] then
        keysPressed[key.Name] = true
        virtualInput:SendKeyEvent(true, key, false, nil)
    end
end

local function releaseKey(key)
    if keysPressed[key.Name] then
        keysPressed[key.Name] = false
        virtualInput:SendKeyEvent(false, key, false, nil)
    end
end

local function stopWASD()
    releaseKey(Enum.KeyCode.W)
    releaseKey(Enum.KeyCode.S)
    releaseKey(Enum.KeyCode.A)
    releaseKey(Enum.KeyCode.D)
    Memory.isMoving = false
end

local function updateWASD(direction)
    if not direction or direction.Magnitude < 0.1 then
        stopWASD()
        return
    end
    
    -- Нормализуем направление
    local dir = direction.Unit
    
    -- Определяем направление относительно камеры
    local forward = camera.CFrame.LookVector * Vector3.new(1,0,1)
    local right = camera.CFrame.RightVector * Vector3.new(1,0,1)
    
    local forwardDot = dir:Dot(forward)
    local rightDot = dir:Dot(right)
    
    -- W/S
    if forwardDot > 0.2 then
        pressKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    elseif forwardDot < -0.2 then
        pressKey(Enum.KeyCode.S)
        releaseKey(Enum.KeyCode.W)
    else
        releaseKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    end
    
    -- A/D
    if rightDot > 0.2 then
        pressKey(Enum.KeyCode.D)
        releaseKey(Enum.KeyCode.A)
    elseif rightDot < -0.2 then
        pressKey(Enum.KeyCode.A)
        releaseKey(Enum.KeyCode.D)
    else
        releaseKey(Enum.KeyCode.A)
        releaseKey(Enum.KeyCode.D)
    end
    
    Memory.isMoving = true
end

-- ============================================
-- 7. ВЫБОР ЦЕЛИ (ALT + ПКМ)
-- ============================================
local altPressed = false

userInput.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
        altPressed = true
    end
end)

userInput.InputEnded:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Enum.KeyCode.LeftAlt or input.KeyCode == Enum.KeyCode.RightAlt then
        altPressed = false
    end
end)

mouse.Button2Down:Connect(function()
    if altPressed then
        local targetPart = mouse.Target
        if targetPart then
            local plr = game.Players:GetPlayerFromCharacter(targetPart.Parent)
            if plr and plr ~= player then
                -- Сбрасываем старую цель
                if Memory.targetHighlight then 
                    Memory.targetHighlight:Destroy() 
                end
                Memory.targetPlayer = plr
                addLog("🎯 Цель выбрана: " .. plr.Name)
                
                -- Зелёная подсветка
                local highlight = Instance.new("Highlight")
                highlight.Parent = plr.Character
                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                highlight.FillTransparency = 0.3
                highlight.OutlineColor = Color3.fromRGB(0, 200, 0)
                Memory.targetHighlight = highlight
                
                clearPath()
                Memory.path = nil
                Memory.currentWaypoint = 1
            end
        end
    end
end)

-- Очистка при смерти цели
game.Players.PlayerRemoving:Connect(function(plr)
    if plr == Memory.targetPlayer then
        Memory.targetPlayer = nil
        if Memory.targetHighlight then
            Memory.targetHighlight:Destroy()
            Memory.targetHighlight = nil
        end
        addLog("❌ Цель покинула игру")
        -- Обновляем ESP, чтобы цель стала белой
        updateESP()
    end
end)

-- ============================================
-- 8. ESP (БЕЛАЯ ПОДСВЕТКА + ИМЕНА)
-- ============================================
local espHighlights = {}
local espNameplates = {}

local function updateESP()
    -- Удаляем старые
    for _, hl in pairs(espHighlights) do hl:Destroy() end
    for _, np in pairs(espNameplates) do np:Destroy() end
    espHighlights = {}
    espNameplates = {}
    
    for _, plr in pairs(players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local char = plr.Character
        
        -- Если это цель - она уже зелёная, пропускаем
        if plr == Memory.targetPlayer then
            continue
        end
        
        -- Подсветка белая
        local hl = Instance.new("Highlight")
        hl.Parent = char
        hl.FillColor = Color3.fromRGB(255, 255, 255)
        hl.FillTransparency = 0.15
        hl.OutlineColor = Color3.fromRGB(255, 255, 255)
        hl.OutlineTransparency = 0.3
        table.insert(espHighlights, hl)
        
        -- Имя
        local billboard = Instance.new("BillboardGui")
        billboard.Parent = char:FindFirstChild("Head") or char
        billboard.Size = UDim2.new(0, 200, 0, 50)
        billboard.StudsOffset = Vector3.new(0, 2.5, 0)
        billboard.AlwaysOnTop = true
        local label = Instance.new("TextLabel")
        label.Parent = billboard
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = plr.Name
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextStrokeTransparency = 0.5
        label.TextSize = 18
        label.Font = Enum.Font.SourceSansBold
        table.insert(espNameplates, billboard)
    end
end

-- Обновляем ESP при появлении игроков
players.PlayerAdded:Connect(updateESP)
players.PlayerRemoving:Connect(updateESP)
updateESP()

-- ============================================
-- 9. ГЕНЕРАЦИЯ ТОЧЕК ДЛЯ ИССЛЕДОВАНИЯ
-- ============================================
local function getExplorePoint()
    if not rootPart then return nil end
    local currentPos = rootPart.Position
    local attempts = 0
    while attempts < 30 do
        attempts = attempts + 1
        local angle = math.random() * 2 * math.pi
        local radius = CONFIG.MIN_EXPLORE_RADIUS + math.random() * (CONFIG.EXPLORE_RADIUS - CONFIG.MIN_EXPLORE_RADIUS)
        local x = currentPos.X + math.cos(angle) * radius
        local z = currentPos.Z + math.sin(angle) * radius
        local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 10, z))
        if groundY then
            local point = Vector3.new(x, groundY + 0.5, z)
            -- Проверка, что точка достижима
            local testPath = computePath(point)
            if testPath then
                return point
            end
        end
    end
    -- Запасной вариант
    return currentPos + Vector3.new(math.random(-30, 30), 0, math.random(-30, 30))
end

-- ============================================
-- 10. ОСНОВНАЯ ЛОГИКА ДВИЖЕНИЯ
-- ============================================
local function moveToTarget(targetPosition)
    if not rootPart or not targetPosition then return end
    
    -- Проверяем, нужно ли обновить путь
    local timeNow = tick()
    local shouldUpdatePath = false
    
    if not Memory.path then
        shouldUpdatePath = true
    elseif Memory.currentWaypoint > #Memory.path then
        shouldUpdatePath = true
    elseif (timeNow - Memory.lastPathUpdate) > CONFIG.PATH_UPDATE_INTERVAL then
        -- Обновляем путь, только если цель сильно сместилась
        local lastTarget = Memory.lastTargetPosition or targetPosition
        if getDistance(lastTarget, targetPosition) > 3 then
            shouldUpdatePath = true
        end
    end
    
    if shouldUpdatePath then
        local newPath = computePath(targetPosition)
        if newPath then
            Memory.path = getWaypoints(newPath)
            Memory.currentWaypoint = 1
            Memory.lastPathUpdate = timeNow
            Memory.lastTargetPosition = targetPosition
            drawPath(Memory.path)
            addLog("🔄 Путь обновлён, точек: " .. #Memory.path)
        else
            -- Если путь не найден, пробуем прыгнуть
            if isOnGround() and not Memory.isJumping then
                Memory.isJumping = true
                pressKey(Enum.KeyCode.Space)
                wait(0.15)
                releaseKey(Enum.KeyCode.Space)
                Memory.isJumping = false
            end
            return
        end
    end
    
    -- Двигаемся по точкам пути
    if Memory.path and Memory.currentWaypoint <= #Memory.path then
        local currentWaypoint = Memory.path[Memory.currentWaypoint]
        local waypointPos = currentWaypoint.position
        local distance = getDistance(rootPart.Position, waypointPos)
        
        -- Проверка на достижение точки
        if distance < CONFIG.WAYPOINT_REACH_DIST then
            Memory.currentWaypoint = Memory.currentWaypoint + 1
            if Memory.currentWaypoint > #Memory.path then
                -- Путь закончен
                Memory.path = nil
                Memory.currentWaypoint = 1
                stopWASD()
                clearPath()
                return
            end
            currentWaypoint = Memory.path[Memory.currentWaypoint]
            waypointPos = currentWaypoint.position
        end
        
        -- Двигаемся к текущей точке
        local direction = (waypointPos - rootPart.Position).Unit
        if direction.Magnitude > 0.1 then
            smoothRotate(direction)
            updateWASD(direction)
        end
        
        -- Проверка на застревание (только если движемся)
        if Memory.isMoving then
            if Memory.lastPosition then
                local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
                if moveDist < 0.2 then
                    Memory.stuckTimer = Memory.stuckTimer + 0.05
                    if Memory.stuckTimer > CONFIG.STUCK_THRESHOLD then
                        addLog("🔄 Застрял! Пересчитываю путь")
                        Memory.path = nil
                        Memory.currentWaypoint = 1
                        Memory.stuckTimer = 0
                        -- Прыжок
                        if isOnGround() and not Memory.isJumping then
                            Memory.isJumping = true
                            pressKey(Enum.KeyCode.Space)
                            wait(0.15)
                            releaseKey(Enum.KeyCode.Space)
                            Memory.isJumping = false
                        end
                    end
                else
                    Memory.stuckTimer = 0
                end
            end
            Memory.lastPosition = rootPart.Position
        end
    end
end

-- ============================================
-- 11. ОСНОВНОЙ ЦИКЛ
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    -- ЕСЛИ ЕСТЬ ЦЕЛЬ — СЛЕДУЕМ
    if Memory.targetPlayer and Memory.targetPlayer.Character then
        local targetRoot = Memory.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position
            local dist = getDistance(rootPart.Position, targetPos)
            if dist > CONFIG.FOLLOW_DISTANCE then
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED
                moveToTarget(targetPos)
            else
                stopWASD()
                Memory.path = nil
                clearPath()
            end
            return
        end
    end
    
    -- ЕСЛИ НЕТ ЦЕЛИ — ИССЛЕДОВАНИЕ
    Memory.exploreTimer = Memory.exploreTimer + 0.05
    
    if Memory.isPaused then
        Memory.pauseTimer = Memory.pauseTimer - 0.05
        if Memory.pauseTimer <= 0 then
            Memory.isPaused = false
            Memory.exploreTarget = getExplorePoint()
            Memory.path = nil
            Memory.currentWaypoint = 1
            addLog("🚶 Продолжаю движение")
        else
            stopWASD()
            clearPath()
        end
        return
    end
    
    if not Memory.exploreTarget or Memory.exploreTimer > CONFIG.EXPLORE_CHANGE_TIME then
        Memory.exploreTarget = getExplorePoint()
        Memory.exploreTimer = 0
        Memory.path = nil
        Memory.currentWaypoint = 1
        if Memory.exploreTarget then
            addLog("🔍 Новая точка исследования")
        end
    end
    
    -- Случайная пауза
    if math.random() < CONFIG.PAUSE_CHANCE and not Memory.isPaused then
        Memory.isPaused = true
        Memory.pauseTimer = CONFIG.PAUSE_TIME * (0.5 + math.random() * 0.5)
        stopWASD()
        clearPath()
        addLog("⏸ Пауза на " .. string.format("%.1f", Memory.pauseTimer) .. "с")
        return
    end
    
    if Memory.exploreTarget then
        local dist = getDistance(rootPart.Position, Memory.exploreTarget)
        if dist < CONFIG.WAYPOINT_REACH_DIST then
            -- Достигли цели
            Memory.exploreTarget = nil
            Memory.path = nil
            clearPath()
            stopWASD()
            if math.random() < 0.3 then
                wait(0.5)
            end
        else
            humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            moveToTarget(Memory.exploreTarget)
        end
    else
        stopWASD()
        clearPath()
    end
end

-- ============================================
-- 12. ГЛАВНЫЙ ЦИКЛ
-- ============================================
local function mainLoop()
    while Memory.running do
        wait(0.05)
        if not character or not humanoid or not rootPart or not head then
            updateCharacter()
            wait(0.5)
            continue
        end
        if humanoid.Health <= 0 then
            stopWASD()
            clearPath()
            wait(1)
            continue
        end
        npcBehavior()
    end
end

-- ============================================
-- 13. GUI
-- ============================================
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "NPCExplorerGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 320, 0, 160)
    frame.Position = UDim2.new(0.5, -160, 1, -170)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 165, 0)
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Parent = frame
    closeBtn.Size = UDim2.new(0, 25, 0, 25)
    closeBtn.Position = UDim2.new(1, -30, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.SourceSansBold
    
    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, -35, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "🐕 NPC EXPLORER v4.1"
    title.TextColor3 = Color3.fromRGB(255, 165, 0)
    title.TextSize = 15
    title.Font = Enum.Font.SourceSansBold
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 32)
    info1.BackgroundTransparency = 1
    info1.Text = "🚶 Использует PathfindingService (обход стен)"
    info1.TextColor3 = Color3.fromRGB(200, 200, 200)
    info1.TextSize = 12
    info1.Font = Enum.Font.SourceSans
    
    local info2 = Instance.new("TextLabel")
    info2.Parent = frame
    info2.Size = UDim2.new(1, 0, 0, 20)
    info2.Position = UDim2.new(0, 0, 0, 52)
    info2.BackgroundTransparency = 1
    info2.Text = "🎯 Alt+ПКМ = следовать за игроком"
    info2.TextColor3 = Color3.fromRGB(200, 200, 200)
    info2.TextSize = 12
    info2.Font = Enum.Font.SourceSans
    
    local info3 = Instance.new("TextLabel")
    info3.Parent = frame
    info3.Size = UDim2.new(1, 0, 0, 20)
    info3.Position = UDim2.new(0, 0, 0, 72)
    info3.BackgroundTransparency = 1
    info3.Text = "🟡 Жёлтый путь = маршрут до цели"
    info3.TextColor3 = Color3.fromRGB(255, 200, 100)
    info3.TextSize = 12
    info3.Font = Enum.Font.SourceSans
    
    local restartBtn = Instance.new("TextButton")
    restartBtn.Parent = frame
    restartBtn.Size = UDim2.new(0, 120, 0, 30)
    restartBtn.Position = UDim2.new(0.5, -60, 1, -35)
    restartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
    restartBtn.Text = "🔄 РЕСТАРТ"
    restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    restartBtn.TextSize = 14
    restartBtn.Font = Enum.Font.SourceSansBold
    
    return {
        screenGui = screenGui,
        frame = frame,
        closeBtn = closeBtn,
        restartBtn = restartBtn,
    }
end

local gui = createGUI()

-- ============================================
-- 14. УПРАВЛЕНИЕ
-- ============================================
local function restartScript()
    Memory.running = false
    stopWASD()
    clearPath()
    Memory.exploreTarget = nil
    Memory.exploreTimer = 0
    Memory.stuckTimer = 0
    Memory.isPaused = false
    Memory.pauseTimer = 0
    Memory.lastPosition = nil
    Memory.targetPlayer = nil
    Memory.path = nil
    Memory.currentWaypoint = 1
    Memory.isMoving = false
    if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
    for _, hl in pairs(espHighlights) do hl:Destroy() end
    for _, np in pairs(espNameplates) do np:Destroy() end
    espHighlights = {}
    espNameplates = {}
    wait(0.3)
    Memory.running = true
    updateESP()
    addLog("🔄 Скрипт перезапущен")
    spawn(mainLoop)
end

gui.closeBtn.MouseButton1Click:Connect(function()
    local visible = gui.frame.Visible
    gui.frame.Visible = not visible
end)

gui.restartBtn.MouseButton1Click:Connect(restartScript)

-- ============================================
-- 15. ЗАПУСК
-- ============================================
addLog("🐕 NPC EXPLORER v4.1 ЗАГРУЖЕН!")
addLog("🚶 Используется PathfindingService для обхода препятствий")
addLog("🟡 Жёлтый путь до цели")
addLog("👁️ ESP: подсветка игроков + имена")
addLog("🎯 Alt+ПКМ по игроку = следование")

spawn(mainLoop)

-- Обновление ESP при респавне
player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    Memory.path = nil
    Memory.currentWaypoint = 1
    updateESP()
    addLog("🔄 Персонаж обновлён, ESP обновлён")
end)
