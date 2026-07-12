-- ============================================
-- FARMER AI v1.2 (MORE POINTS + SMOOTH BODY ROTATION)
-- by Цербер для хозяйки
-- Исправлено: больше точек для плавного пути, убран поворот головы
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

-- ============================================
-- НАСТРОЙКИ
-- ============================================
local CONFIG = {
    -- Движение
    MOVE_SPEED = 16,
    EXPLORE_RADIUS = 100,
    MIN_EXPLORE_RADIUS = 25,
    EXPLORE_CHANGE_TIME = 15,
    FOLLOW_DISTANCE = 5,
    PATH_UPDATE_INTERVAL = 2.0,
    STUCK_THRESHOLD = 6,
    JUMP_FORCE = 50,
    WAYPOINT_REACH_DIST = 2.0,
    MAX_PATH_ATTEMPTS = 3,
    
    -- Поведение
    PAUSE_CHANCE = 0.12,
    PAUSE_TIME = 3.0,
}

-- ============================================
-- ПАМЯТЬ
-- ============================================
local Memory = {
    running = true,
    exploreTarget = nil,
    exploreTimer = 0,
    lastPosition = nil,
    stuckTimer = 0,
    isPaused = false,
    pauseTimer = 0,
    isJumping = false,
    isMoving = false,
    path = nil,
    currentWaypoint = 1,
    pathParts = {},
    lastPathUpdate = 0,
    lastTargetPosition = nil,
    pathAttempts = 0,
    
    friendTarget = nil,
    friendHighlight = nil,
    isFriendMode = false,
}

-- Логирование
local function addLog(text)
    print("[FARMER-AI] " .. text)
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
        humanoid.AutoRotate = true
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
    local rayResult = workspace:Raycast(position + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0), rayParams)
    if rayResult then
        return rayResult.Position.Y
    end
    return position.Y
end

-- ============================================
-- 3. PATHFINDING SERVICE (БОЛЬШЕ ТОЧЕК)
-- ============================================
local function computePath(targetPosition)
    if not rootPart or not targetPosition then return nil end
    
    local pathParams = {
        AgentRadius = 2.0,
        AgentHeight = 5,
        AgentCanJump = true,
        AgentCanClimb = true,
        WaypointSpacing = 3,        -- ИЗМЕНЕНО: 3 (было 5) → БОЛЬШЕ ТОЧЕК
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
    local lastPos = nil
    for _, waypoint in ipairs(path:GetWaypoints()) do
        if lastPos then
            if getDistance(lastPos, waypoint.Position) < 3 then
                continue
            end
        end
        lastPos = waypoint.Position
        table.insert(waypoints, {
            position = waypoint.Position + Vector3.new(0, 1.0, 0),
            action = waypoint.Action
        })
    end
    return waypoints
end

-- ============================================
-- 4. ОТОБРАЖЕНИЕ ПУТИ
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
        part.Size = Vector3.new(0.6, 0.2, 0.6)
        part.Position = waypoint.position + Vector3.new(0, 0.5, 0)
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.new("Bright blue")
        part.Transparency = 0.4
        part.Parent = workspace
        table.insert(Memory.pathParts, part)
    end
end

-- ============================================
-- 5. УПРАВЛЕНИЕ WASD (ПЛАВНЫЙ ПОВОРОТ ТЕЛА, БЕЗ ГОЛОВЫ)
-- ============================================
local function pressKey(key)
    virtualInput:SendKeyEvent(true, key, false, nil)
end

local function releaseKey(key)
    virtualInput:SendKeyEvent(false, key, false, nil)
end

local function stopWASD()
    releaseKey(Enum.KeyCode.W)
    releaseKey(Enum.KeyCode.S)
    releaseKey(Enum.KeyCode.A)
    releaseKey(Enum.KeyCode.D)
    Memory.isMoving = false
end

local function moveToWaypoint(waypoint)
    if not waypoint or not rootPart then return end
    
    local direction = (waypoint.position - rootPart.Position).Unit
    local distance = getDistance(rootPart.Position, waypoint.position)
    
    if distance < CONFIG.WAYPOINT_REACH_DIST then
        return true
    end
    
    -- ПЛАВНЫЙ ПОВОРОТ ТЕЛА (голова НЕ трогается)
    local targetCFrame = CFrame.new(rootPart.Position, rootPart.Position + direction)
    rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, 0.15)  -- плавность 0.15
    
    -- УБРАН ПОВОРОТ ГОЛОВЫ
    
    -- WASD относительно камеры
    local forward = camera.CFrame.LookVector * Vector3.new(1,0,1)
    local right = camera.CFrame.RightVector * Vector3.new(1,0,1)
    
    local forwardDot = direction:Dot(forward)
    local rightDot = direction:Dot(right)
    
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
    return false
end

-- ============================================
-- 6. ПЕРЕМЕЩЕНИЕ К ТОЧКЕ
-- ============================================
local function moveToPosition(targetPos)
    if not rootPart or not targetPos then return end
    
    local timeNow = tick()
    local shouldUpdatePath = false
    
    if not Memory.path then
        shouldUpdatePath = true
    elseif Memory.currentWaypoint > #Memory.path then
        shouldUpdatePath = true
    elseif (timeNow - Memory.lastPathUpdate) > CONFIG.PATH_UPDATE_INTERVAL then
        if Memory.lastTargetPosition then
            if getDistance(Memory.lastTargetPosition, targetPos) > 5 then
                shouldUpdatePath = true
            end
        else
            shouldUpdatePath = true
        end
    end
    
    if shouldUpdatePath then
        local newPath = computePath(targetPos)
        if newPath then
            Memory.path = getWaypoints(newPath)
            Memory.currentWaypoint = 1
            Memory.lastPathUpdate = timeNow
            Memory.lastTargetPosition = targetPos
            Memory.pathAttempts = 0
            drawPath(Memory.path)
        else
            Memory.pathAttempts = Memory.pathAttempts + 1
            if Memory.pathAttempts > CONFIG.MAX_PATH_ATTEMPTS then
                Memory.exploreTarget = getExplorePoint()
                Memory.pathAttempts = 0
                addLog("⚠️ Не могу построить путь, меняю точку")
                return
            end
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
    
    if Memory.path and Memory.currentWaypoint <= #Memory.path then
        local currentWaypoint = Memory.path[Memory.currentWaypoint]
        local reached = moveToWaypoint(currentWaypoint)
        
        if Memory.isMoving then
            if Memory.lastPosition then
                local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
                if moveDist < 0.3 then
                    Memory.stuckTimer = Memory.stuckTimer + 0.05
                    if Memory.stuckTimer > CONFIG.STUCK_THRESHOLD then
                        addLog("🔄 Застрял! Пересчёт пути")
                        Memory.path = nil
                        Memory.currentWaypoint = 1
                        Memory.stuckTimer = 0
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
        
        if reached then
            Memory.currentWaypoint = Memory.currentWaypoint + 1
            if Memory.currentWaypoint > #Memory.path then
                Memory.path = nil
                Memory.currentWaypoint = 1
            end
        end
    end
end

-- ============================================
-- 7. ГЕНЕРАЦИЯ ТОЧЕК
-- ============================================
local function getExplorePoint()
    if not rootPart then return nil end
    local currentPos = rootPart.Position
    local attempts = 0
    while attempts < 40 do
        attempts = attempts + 1
        local angle = math.random() * 2 * math.pi
        local radius = CONFIG.MIN_EXPLORE_RADIUS + math.random() * (CONFIG.EXPLORE_RADIUS - CONFIG.MIN_EXPLORE_RADIUS)
        local x = currentPos.X + math.cos(angle) * radius
        local z = currentPos.Z + math.sin(angle) * radius
        local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 15, z))
        if groundY then
            local point = Vector3.new(x, groundY + 1.5, z)
            local testPath = computePath(point)
            if testPath then
                return point
            end
        end
    end
    return currentPos + Vector3.new(math.random(-30, 30), 2, math.random(-30, 30))
end

-- ============================================
-- 8. "ОСМОТР" (ПОВОРОТ ГОЛОВЫ)
-- ============================================
local function lookAround()
    if not head then return end
    local angleY = math.rad(math.random(-45, 45))
    local angleX = math.rad(math.random(-10, 10))
    local lookAt = CFrame.new(head.Position) * CFrame.Angles(angleX, angleY, 0)
    head.CFrame = head.CFrame:Lerp(lookAt, 0.2)
end

-- ============================================
-- 9. ВЫБОР ДРУГА (ALT + ПКМ)
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
                if Memory.friendHighlight then
                    Memory.friendHighlight:Destroy()
                end
                
                if Memory.friendTarget == plr then
                    Memory.friendTarget = nil
                    Memory.isFriendMode = false
                    addLog("❌ Режим следования отключён")
                    updateESP()
                    return
                end
                
                Memory.friendTarget = plr
                Memory.isFriendMode = true
                addLog("👥 Следую за: " .. plr.Name)
                
                local highlight = Instance.new("Highlight")
                highlight.Parent = plr.Character
                highlight.FillColor = Color3.fromRGB(0, 255, 255)
                highlight.FillTransparency = 0.3
                highlight.OutlineColor = Color3.fromRGB(0, 200, 255)
                Memory.friendHighlight = highlight
                
                updateESP()
            end
        end
    end
end)

-- ============================================
-- 10. ESP
-- ============================================
local espHighlights = {}
local espNameplates = {}

local function updateESP()
    for _, hl in pairs(espHighlights) do hl:Destroy() end
    for _, np in pairs(espNameplates) do np:Destroy() end
    espHighlights = {}
    espNameplates = {}
    
    for _, plr in pairs(players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local char = plr.Character
        
        if plr == Memory.friendTarget then
            continue
        end
        
        local hl = Instance.new("Highlight")
        hl.Parent = char
        hl.FillColor = Color3.fromRGB(200, 200, 255)
        hl.FillTransparency = 0.15
        hl.OutlineColor = Color3.fromRGB(150, 150, 255)
        hl.OutlineTransparency = 0.3
        table.insert(espHighlights, hl)
        
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
        label.TextColor3 = Color3.fromRGB(200, 200, 255)
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextStrokeTransparency = 0.5
        label.TextSize = 18
        label.Font = Enum.Font.SourceSansBold
        table.insert(espNameplates, billboard)
    end
end

players.PlayerAdded:Connect(updateESP)
players.PlayerRemoving:Connect(updateESP)
updateESP()

-- ============================================
-- 11. ОСНОВНОЙ ЦИКЛ
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    if Memory.friendTarget and Memory.friendTarget.Character then
        local targetRoot = Memory.friendTarget.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position
            local dist = getDistance(rootPart.Position, targetPos)
            if dist > CONFIG.FOLLOW_DISTANCE then
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED
                moveToPosition(targetPos)
            else
                stopWASD()
                Memory.path = nil
                clearPath()
                if math.random() < 0.05 then
                    lookAround()
                end
            end
            return
        end
    end
    
    Memory.exploreTimer = Memory.exploreTimer + 0.05
    
    if Memory.isPaused then
        Memory.pauseTimer = Memory.pauseTimer - 0.05
        if Memory.pauseTimer <= 0 then
            Memory.isPaused = false
            Memory.exploreTarget = getExplorePoint()
            Memory.path = nil
            Memory.currentWaypoint = 1
            addLog("🚶 Продолжаю исследование")
        else
            stopWASD()
            clearPath()
            if math.random() < 0.1 then
                lookAround()
            end
        end
        return
    end
    
    if not Memory.exploreTarget or Memory.exploreTimer > CONFIG.EXPLORE_CHANGE_TIME then
        Memory.exploreTarget = getExplorePoint()
        Memory.exploreTimer = 0
        Memory.path = nil
        Memory.currentWaypoint = 1
        Memory.pathAttempts = 0
        if Memory.exploreTarget then
            addLog("🔍 Новая точка исследования")
        end
    end
    
    if math.random() < CONFIG.PAUSE_CHANCE and not Memory.isPaused and Memory.exploreTarget then
        Memory.isPaused = true
        Memory.pauseTimer = CONFIG.PAUSE_TIME * (0.5 + math.random() * 0.5)
        stopWASD()
        clearPath()
        lookAround()
        addLog("⏸ Осмотр на " .. string.format("%.1f", Memory.pauseTimer) .. "с")
        return
    end
    
    if Memory.exploreTarget then
        local dist = getDistance(rootPart.Position, Memory.exploreTarget)
        if dist < CONFIG.WAYPOINT_REACH_DIST then
            Memory.exploreTarget = nil
            Memory.path = nil
            clearPath()
            stopWASD()
            lookAround()
            if math.random() < 0.3 then
                wait(0.5)
            end
        else
            humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            moveToPosition(Memory.exploreTarget)
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
    screenGui.Name = "FarmerAIGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 320, 0, 170)
    frame.Position = UDim2.new(0.5, -160, 1, -180)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(0, 150, 255)
    
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
    title.Text = "🌾 FARMER AI v1.2"
    title.TextColor3 = Color3.fromRGB(0, 150, 255)
    title.TextSize = 15
    title.Font = Enum.Font.SourceSansBold
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 32)
    info1.BackgroundTransparency = 1
    info1.Text = "🚶 Больше точек для плавного пути"
    info1.TextColor3 = Color3.fromRGB(200, 200, 200)
    info1.TextSize = 12
    info1.Font = Enum.Font.SourceSans
    
    local info2 = Instance.new("TextLabel")
    info2.Parent = frame
    info2.Size = UDim2.new(1, 0, 0, 20)
    info2.Position = UDim2.new(0, 0, 0, 52)
    info2.BackgroundTransparency = 1
    info2.Text = "👥 Alt+ПКМ = следовать за игроком"
    info2.TextColor3 = Color3.fromRGB(200, 200, 200)
    info2.TextSize = 12
    info2.Font = Enum.Font.SourceSans
    
    local info3 = Instance.new("TextLabel")
    info3.Parent = frame
    info3.Size = UDim2.new(1, 0, 0, 20)
    info3.Position = UDim2.new(0, 0, 0, 72)
    info3.BackgroundTransparency = 1
    info3.Text = "🔵 Точки пути подняты выше"
    info3.TextColor3 = Color3.fromRGB(100, 200, 255)
    info3.TextSize = 12
    info3.Font = Enum.Font.SourceSans
    
    local info4 = Instance.new("TextLabel")
    info4.Parent = frame
    info4.Size = UDim2.new(1, 0, 0, 20)
    info4.Position = UDim2.new(0, 0, 0, 92)
    info4.BackgroundTransparency = 1
    info4.Text = "🔄 Плавный поворот тела (без головы)"
    info4.TextColor3 = Color3.fromRGB(200, 255, 200)
    info4.TextSize = 12
    info4.Font = Enum.Font.SourceSans
    
    local restartBtn = Instance.new("TextButton")
    restartBtn.Parent = frame
    restartBtn.Size = UDim2.new(0, 120, 0, 30)
    restartBtn.Position = UDim2.new(0.5, -60, 1, -35)
    restartBtn.BackgroundColor3 = Color3.fromRGB(0, 100, 200)
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
    Memory.path = nil
    Memory.currentWaypoint = 1
    Memory.isMoving = false
    Memory.friendTarget = nil
    Memory.isFriendMode = false
    Memory.pathAttempts = 0
    if Memory.friendHighlight then Memory.friendHighlight:Destroy() end
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
addLog("🌾 FARMER AI v1.2 ЗАГРУЖЕН!")
addLog("🚶 Больше точек для плавного пути")
addLog("🔵 Точки на уровне +1 студия")
addLog("🔄 Плавный поворот тела (без головы)")
addLog("👥 Alt+ПКМ по игроку = следование")

spawn(mainLoop)

player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    Memory.path = nil
    Memory.currentWaypoint = 1
    updateESP()
    addLog("🔄 Персонаж обновлён")
end)
