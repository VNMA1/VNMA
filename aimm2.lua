-- ============================================
-- NPC EXPLORER v4.1 (FIXED + SMART FOLLOW)
-- by Цербер для хозяйки
-- Исправлено: точное следование, статус, убрано ускорение
-- ============================================

local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local runService = game:GetService("RunService")
local userInput = game:GetService("UserInputService")
local virtualInput = game:GetService("VirtualInputManager")
local players = game:GetService("Players")

-- Переменные
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

-- Настройки
local CONFIG = {
    MOVE_SPEED = 16,                -- Постоянная скорость (без ускорения)
    EXPLORE_RADIUS = 40,
    MIN_EXPLORE_RADIUS = 10,
    EXPLORE_CHANGE_TIME = 8,
    WALL_AVOID_DIST = 3.5,
    JUMP_HEIGHT = 4,
    TURN_SPEED = 0.5,
    LOOK_AROUND_CHANCE = 0.05,
    PAUSE_CHANCE = 0.02,
    PAUSE_TIME = 0.8,
    STUCK_THRESHOLD = 3,
    OBSTACLE_RETRY_TIME = 8,
    PATH_STEP = 3,
    FOLLOW_DISTANCE = 8,            -- Дистанция следования
    FOLLOW_DEAD_ZONE = 2,           -- Мертвая зона (не двигаться если в пределах)
}

-- Память
local Memory = {
    running = true,
    exploreTarget = nil,
    exploreTimer = 0,
    isMoving = false,
    isJumping = false,
    lastPosition = nil,
    stuckTimer = 0,
    isPaused = false,
    pauseTimer = 0,
    targetPlayer = nil,
    targetHighlight = nil,
    pathParts = {},
    pathPoints = {},
    obstacleTimer = 0,
    currentTarget = nil,
    lastTargetUpdate = 0,
    currentStatus = "🚶 Исследую карту",  -- Текущий статус
    targetName = "",                     -- Имя цели
}

-- Функции логирования
local function addLog(text)
    print("[NPC-EXPLORER] " .. text)
end

-- ============================================
-- 1. ОБНОВЛЕНИЕ ПЕРСОНАЖА
-- ============================================
local function updateCharacter()
    character = player.Character
    if not character then return false end
    humanoid = character:FindFirstChild("Humanoid")
    rootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoid and rootPart then
        humanoid.WalkSpeed = CONFIG.MOVE_SPEED  -- Постоянная скорость
        humanoid.JumpPower = 55
        humanoid.AutoRotate = false
        return true
    end
    return false
end
updateCharacter()
player.CharacterAdded:Connect(updateCharacter)

-- ============================================
-- 2. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (RAYCAST)
-- ============================================
local function getGroundPosition(pos)
    local ray = Ray.new(pos + Vector3.new(0, 10, 0), Vector3.new(0, -30, 0))
    local hit, hitPos = workspace:FindPartOnRay(ray, character, false, true)
    if hit then
        return Vector3.new(pos.X, hitPos.Y + 0.5, pos.Z)
    end
    return Vector3.new(pos.X, pos.Y, pos.Z)
end

local function isObstacle(position, direction, distance)
    local ray = Ray.new(position + Vector3.new(0, 1.5, 0), direction * distance)
    local hit, _ = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

local function getHeightAt(position)
    local ray = Ray.new(position + Vector3.new(0, 15, 0), Vector3.new(0, -30, 0))
    local hit, hitPos = workspace:FindPartOnRay(ray, character, false, true)
    if hit then
        return hitPos.Y
    end
    return position.Y
end

local function canJumpOver(position, direction)
    local checkPos = position + direction * 2.5
    local height = getHeightAt(checkPos)
    local currentHeight = getHeightAt(position)
    if height and (height - currentHeight) < CONFIG.JUMP_HEIGHT and height > currentHeight then
        return true
    end
    return false
end

local function getDistance(pos1, pos2)
    return (pos1 - pos2).Magnitude
end

local function isOnGround()
    if not rootPart then return false end
    local ray = Ray.new(rootPart.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -3, 0))
    local hit, _ = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

local function hasGroundAhead(direction, distance)
    if not rootPart then return false end
    local checkPos = rootPart.Position + direction * distance + Vector3.new(0, -2, 0)
    local ray = Ray.new(checkPos + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0))
    local hit, _ = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

-- ============================================
-- 3. УПРАВЛЕНИЕ КАМЕРОЙ
-- ============================================
local function rotateCameraTo(targetPos)
    if not rootPart or not targetPos then return end
    
    local currentPos = rootPart.Position
    local lookDirection = (targetPos - currentPos).Unit
    lookDirection = Vector3.new(lookDirection.X, 0, lookDirection.Z).Unit
    
    if lookDirection.Magnitude < 0.1 then return end
    
    local targetCFrame = CFrame.lookAt(currentPos, currentPos + lookDirection * 10)
    camera.CFrame = camera.CFrame:Lerp(targetCFrame, CONFIG.TURN_SPEED)
end

-- ============================================
-- 4. УПРАВЛЕНИЕ WASD (ЭМУЛЯЦИЯ)
-- ============================================
local function pressKey(key)
    pcall(function()
        virtualInput:SendKeyEvent(true, key, false, nil)
    end)
end

local function releaseKey(key)
    pcall(function()
        virtualInput:SendKeyEvent(false, key, false, nil)
    end)
end

local function moveDirection(dir)
    if not dir or dir.Magnitude < 0.1 then
        releaseKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
        releaseKey(Enum.KeyCode.A)
        releaseKey(Enum.KeyCode.D)
        return
    end
    
    local forward = camera.CFrame.LookVector * Vector3.new(1,0,1)
    local right = camera.CFrame.RightVector * Vector3.new(1,0,1)
    
    local forwardDot = dir:Dot(forward)
    local rightDot = dir:Dot(right)
    
    if forwardDot > 0.25 then
        pressKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    elseif forwardDot < -0.25 then
        pressKey(Enum.KeyCode.S)
        releaseKey(Enum.KeyCode.W)
    else
        releaseKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    end
    
    if rightDot > 0.25 then
        pressKey(Enum.KeyCode.D)
        releaseKey(Enum.KeyCode.A)
    elseif rightDot < -0.25 then
        pressKey(Enum.KeyCode.A)
        releaseKey(Enum.KeyCode.D)
    else
        releaseKey(Enum.KeyCode.A)
        releaseKey(Enum.KeyCode.D)
    end
end

local function stopWASD()
    releaseKey(Enum.KeyCode.W)
    releaseKey(Enum.KeyCode.S)
    releaseKey(Enum.KeyCode.A)
    releaseKey(Enum.KeyCode.D)
end

-- ============================================
-- 5. ВЫБОР ЦЕЛИ (ALT + ПКМ)
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
                Memory.targetPlayer = plr
                Memory.targetName = plr.Name
                Memory.currentStatus = "🎯 Преследую " .. plr.Name
                addLog("🎯 Цель выбрана: " .. plr.Name)
                if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
                local highlight = Instance.new("Highlight")
                highlight.Parent = plr.Character
                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                highlight.FillTransparency = 0.3
                highlight.OutlineColor = Color3.fromRGB(0, 200, 0)
                Memory.targetHighlight = highlight
                clearPath()
                -- Обновляем GUI
                updateGUIStatus()
            end
        end
    end
end)

game.Players.PlayerRemoving:Connect(function(plr)
    if plr == Memory.targetPlayer then
        Memory.targetPlayer = nil
        Memory.targetName = ""
        Memory.currentStatus = "🚶 Исследую карту"
        if Memory.targetHighlight then
            Memory.targetHighlight:Destroy()
            Memory.targetHighlight = nil
        end
        addLog("❌ Цель покинула игру")
        updateGUIStatus()
    end
end)

-- ============================================
-- 6. ОТОБРАЖЕНИЕ ПУТИ
-- ============================================
local function clearPath()
    for _, part in pairs(Memory.pathParts) do
        part:Destroy()
    end
    Memory.pathParts = {}
    Memory.pathPoints = {}
end

local function drawPath(targetPos)
    clearPath()
    if not rootPart then return end
    local startPos = rootPart.Position
    local dir = (targetPos - startPos).Unit
    local distance = (targetPos - startPos).Magnitude
    if distance < 1 then return end
    
    local steps = math.floor(distance / CONFIG.PATH_STEP)
    for i = 0, steps do
        local t = i / (steps + 1)
        local point = startPos + dir * t * distance
        local groundY = getHeightAt(point)
        if groundY then
            point = Vector3.new(point.X, groundY + 0.1, point.Z)
        else
            point = Vector3.new(point.X, startPos.Y, point.Z)
        end
        table.insert(Memory.pathPoints, point)
        local part = Instance.new("Part")
        part.Size = Vector3.new(0.4, 0.1, 0.4)
        part.Position = point
        part.Anchored = true
        part.CanCollide = false
        part.Material = Enum.Material.Neon
        part.BrickColor = BrickColor.new("Bright orange")
        part.Transparency = 0.4
        part.Parent = workspace
        table.insert(Memory.pathParts, part)
    end
end

-- ============================================
-- 7. ESP
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
        
        if plr == Memory.targetPlayer then
            -- Уже есть зеленая подсветка
        else
            local hl = Instance.new("Highlight")
            hl.Parent = char
            hl.FillColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 0.9
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.OutlineTransparency = 0.3
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            table.insert(espHighlights, hl)
        end
        
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
        label.TextStrokeTransparency = 0.4
        label.TextSize = 16
        label.Font = Enum.Font.SourceSansBold
        table.insert(espNameplates, billboard)
    end
end

players.PlayerAdded:Connect(updateESP)
players.PlayerRemoving:Connect(updateESP)
updateESP()

-- ============================================
-- 8. ГЕНЕРАЦИЯ ТОЧЕК
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
        local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 15, z))
        if groundY then
            local point = Vector3.new(x, groundY + 0.5, z)
            local dirToPoint = (point - currentPos).Unit
            if not isObstacle(currentPos, dirToPoint, 5) then
                return point
            end
        end
    end
    local angle = math.random() * 2 * math.pi
    local x = currentPos.X + math.cos(angle) * 15
    local z = currentPos.Z + math.sin(angle) * 15
    local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 15, z))
    if groundY then return Vector3.new(x, groundY + 0.5, z) end
    return Vector3.new(x, currentPos.Y, z)
end

-- ============================================
-- 9. УМНЫЙ ОБХОД
-- ============================================
local function findClearDirection(targetPos)
    if not rootPart then return (targetPos - rootPart.Position).Unit end
    
    local dir = (targetPos - rootPart.Position).Unit
    local right = Vector3.new(-dir.Z, 0, dir.X).Unit
    local left = Vector3.new(dir.Z, 0, -dir.X).Unit
    
    local options = {
        {dir = dir, angle = 0},
        {dir = (dir + right * 0.5).Unit, angle = 30},
        {dir = (dir - right * 0.5).Unit, angle = -30},
        {dir = (dir + right * 0.8).Unit, angle = 50},
        {dir = (dir - right * 0.8).Unit, angle = -50},
    }
    
    local best = nil
    local bestScore = -math.huge
    
    for _, opt in ipairs(options) do
        local d = opt.dir
        local blocked = isObstacle(rootPart.Position, d, CONFIG.WALL_AVOID_DIST)
        local hasFloor = hasGroundAhead(d, 2.5)
        local canJump = canJumpOver(rootPart.Position, d)
        
        local score = 0
        if not blocked then score = score + 3 end
        if hasFloor then score = score + 2 end
        if canJump then score = score + 1 end
        score = score - math.abs(opt.angle) / 30
        
        if score > bestScore then
            bestScore = score
            best = d
        end
    end
    
    return best or dir
end

-- ============================================
-- 10. ДВИЖЕНИЕ (ОБНОВЛЕНО - ТОЧНОЕ СЛЕДОВАНИЕ)
-- ============================================
local function moveToTarget(targetPos)
    if not rootPart or not targetPos then return end
    local distance = getDistance(rootPart.Position, targetPos)
    
    -- Если цель - игрок, проверяем дистанцию
    if Memory.targetPlayer then
        local followDist = CONFIG.FOLLOW_DISTANCE
        local deadZone = CONFIG.FOLLOW_DEAD_ZONE
        
        -- Если в мертвой зоне - стоим
        if distance < followDist - deadZone then
            stopWASD()
            Memory.isMoving = false
            Memory.currentStatus = "🧍 Жду " .. Memory.targetName .. " (8м)"
            updateGUIStatus()
            return
        end
        
        -- Обновляем статус
        if distance > followDist + 5 then
            Memory.currentStatus = "🏃 Догоняю " .. Memory.targetName .. " (" .. math.floor(distance) .. "м)"
        else
            Memory.currentStatus = "🚶 Следую за " .. Memory.targetName .. " (" .. math.floor(distance) .. "м)"
        end
        updateGUIStatus()
    end
    
    if distance < 1.5 then
        stopWASD()
        Memory.isMoving = false
        return
    end
    
    -- Проверка на обрыв
    local dir = (targetPos - rootPart.Position).Unit
    if not hasGroundAhead(dir, 2) then
        stopWASD()
        Memory.exploreTarget = getExplorePoint()
        Memory.currentStatus = "⚠️ Обрыв! Ищу обход"
        updateGUIStatus()
        return
    end
    
    -- Умный обход препятствий
    local finalDir = findClearDirection(targetPos)
    
    -- Проверка застревания
    if finalDir ~= dir and (finalDir - dir).Magnitude > 0.3 then
        Memory.obstacleTimer = Memory.obstacleTimer + 0.05
        if Memory.obstacleTimer > CONFIG.OBSTACLE_RETRY_TIME then
            Memory.exploreTarget = getExplorePoint()
            Memory.obstacleTimer = 0
            Memory.currentStatus = "🔄 Обхожу препятствие"
            updateGUIStatus()
            return
        end
    else
        Memory.obstacleTimer = 0
    end
    
    -- Прыжки через препятствия
    if canJumpOver(rootPart.Position, finalDir) and isOnGround() and not Memory.isJumping then
        Memory.isJumping = true
        pressKey(Enum.KeyCode.Space)
        wait(0.1)
        releaseKey(Enum.KeyCode.Space)
        Memory.isJumping = false
    end
    
    -- Движение
    moveDirection(finalDir)
    Memory.isMoving = true
end

-- ============================================
-- 11. GUI СТАТУС (НОВОЕ)
-- ============================================
local statusLabel = nil

local function updateGUIStatus()
    if statusLabel then
        statusLabel.Text = Memory.currentStatus
    end
end

-- ============================================
-- 12. ОСНОВНАЯ ЛОГИКА (ОБНОВЛЕНО)
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    -- Проверка застревания
    if Memory.lastPosition then
        local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
        if moveDist < 0.15 then
            Memory.stuckTimer = Memory.stuckTimer + 0.05
            if Memory.stuckTimer > CONFIG.STUCK_THRESHOLD then
                Memory.exploreTarget = getExplorePoint()
                Memory.stuckTimer = 0
                Memory.currentStatus = "🔄 Застрял! Меняю направление"
                updateGUIStatus()
                pressKey(Enum.KeyCode.Space)
                wait(0.1)
                releaseKey(Enum.KeyCode.Space)
            end
        else
            Memory.stuckTimer = 0
        end
    end
    Memory.lastPosition = rootPart.Position
    
    -- ЕСЛИ ЕСТЬ ЦЕЛЬ
    if Memory.targetPlayer and Memory.targetPlayer.Character then
        local targetRoot = Memory.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position
            local dist = getDistance(rootPart.Position, targetPos)
            
            -- Поворачиваем камеру к цели
            rotateCameraTo(targetPos)
            
            -- Рисуем путь
            drawPath(targetPos)
            
            -- Если далеко - идем, если близко - стоим
            if dist > CONFIG.FOLLOW_DISTANCE - CONFIG.FOLLOW_DEAD_ZONE then
                moveToTarget(targetPos)
            else
                stopWASD()
                Memory.isMoving = false
                Memory.currentStatus = "🧍 Жду " .. Memory.targetName .. " (" .. math.floor(dist) .. "м)"
                updateGUIStatus()
                -- Иногда смотрим по сторонам
                if math.random() < 0.02 then
                    local head = character:FindFirstChild("Head")
                    if head then
                        head.CFrame = head.CFrame * CFrame.Angles(0, math.rad(math.random(-30, 30)), 0)
                    end
                end
            end
            return
        end
    end
    
    -- ИССЛЕДОВАНИЕ
    if Memory.targetPlayer == nil then
        Memory.currentStatus = "🚶 Исследую карту"
        updateGUIStatus()
    end
    
    Memory.exploreTimer = Memory.exploreTimer + 0.05
    
    if Memory.isPaused then
        Memory.pauseTimer = Memory.pauseTimer - 0.05
        if Memory.pauseTimer <= 0 then
            Memory.isPaused = false
            Memory.exploreTarget = getExplorePoint()
            Memory.currentStatus = "🚶 Продолжаю исследование"
            updateGUIStatus()
        end
        return
    end
    
    if not Memory.exploreTarget or Memory.exploreTimer > CONFIG.EXPLORE_CHANGE_TIME then
        Memory.exploreTarget = getExplorePoint()
        Memory.exploreTimer = 0
    end
    
    -- Случайная пауза (очень редко)
    if math.random() < CONFIG.PAUSE_CHANCE and not Memory.isPaused then
        Memory.isPaused = true
        Memory.pauseTimer = CONFIG.PAUSE_TIME * (0.5 + math.random() * 0.5)
        stopWASD()
        Memory.currentStatus = "⏸ Пауза..."
        updateGUIStatus()
        return
    end
    
    if Memory.exploreTarget then
        local dist = getDistance(rootPart.Position, Memory.exploreTarget)
        if dist < 2 then
            Memory.exploreTarget = getExplorePoint()
            if math.random() < 0.2 then
                stopWASD()
                wait(0.2)
            end
        else
            rotateCameraTo(Memory.exploreTarget)
            drawPath(Memory.exploreTarget)
            moveToTarget(Memory.exploreTarget)
        end
    else
        stopWASD()
    end
end

-- ============================================
-- 13. ГЛАВНЫЙ ЦИКЛ
-- ============================================
local function mainLoop()
    while Memory.running do
        wait(0.05)
        if not character or not humanoid or not rootPart then
            updateCharacter()
            wait(0.5)
            continue
        end
        if humanoid.Health <= 0 then
            stopWASD()
            wait(1)
            continue
        end
        pcall(npcBehavior)
    end
end

-- ============================================
-- 14. GUI (ОБНОВЛЕН - ДОБАВЛЕН СТАТУС)
-- ============================================
local guiVisible = true
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "NPCExplorerGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 380, 0, 210)  -- Увеличен размер
    frame.Position = UDim2.new(0.5, -190, 1, -220)
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
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold
    
    -- СТАТУС (НОВЫЙ)
    local statusBg = Instance.new("Frame")
    statusBg.Parent = frame
    statusBg.Size = UDim2.new(0.95, 0, 0, 35)
    statusBg.Position = UDim2.new(0.025, 0, 0, 35)
    statusBg.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    statusBg.BackgroundTransparency = 0.5
    statusBg.BorderSizePixel = 1
    statusBg.BorderColor3 = Color3.fromRGB(255, 165, 0)
    
    statusLabel = Instance.new("TextLabel")
    statusLabel.Parent = statusBg
    statusLabel.Size = UDim2.new(1, 0, 1, 0)
    statusLabel.Position = UDim2.new(0, 0, 0, 0)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "🚶 Исследую карту"
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.SourceSansBold
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextTruncate = Enum.TextTruncate.AtEnd
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 75)
    info1.BackgroundTransparency = 1
    info1.Text = "🎯 Alt+ПКМ = следовать за игроком"
    info1.TextColor3 = Color3.fromRGB(200, 200, 200)
    info1.TextSize = 12
    
    local info2 = Instance.new("TextLabel")
    info2.Parent = frame
    info2.Size = UDim2.new(1, 0, 0, 20)
    info2.Position = UDim2.new(0, 0, 0, 95)
    info2.BackgroundTransparency = 1
    info2.Text = "📏 Дистанция до цели: 8 метров"
    info2.TextColor3 = Color3.fromRGB(255, 200, 100)
    info2.TextSize = 12
    
    local info3 = Instance.new("TextLabel")
    info3.Parent = frame
    info3.Size = UDim2.new(1, 0, 0, 20)
    info3.Position = UDim2.new(0, 0, 0, 115)
    info3.BackgroundTransparency = 1
    info3.Text = "🟧 Оранжевый путь до цели"
    info3.TextColor3 = Color3.fromRGB(200, 200, 200)
    info3.TextSize = 12
    
    local stopBtn = Instance.new("TextButton")
    stopBtn.Parent = frame
    stopBtn.Size = UDim2.new(0, 100, 0, 30)
    stopBtn.Position = UDim2.new(0.05, 0, 1, -35)
    stopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    stopBtn.Text = "⏹ СТОП"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.TextSize = 14
    stopBtn.Font = Enum.Font.SourceSansBold
    
    local restartBtn = Instance.new("TextButton")
    restartBtn.Parent = frame
    restartBtn.Size = UDim2.new(0, 100, 0, 30)
    restartBtn.Position = UDim2.new(0.55, 0, 1, -35)
    restartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
    restartBtn.Text = "🔄 РЕСТАРТ"
    restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    restartBtn.TextSize = 14
    restartBtn.Font = Enum.Font.SourceSansBold
    
    return {
        screenGui = screenGui,
        frame = frame,
        closeBtn = closeBtn,
        stopBtn = stopBtn,
        restartBtn = restartBtn,
    }
end

local gui = createGUI()

-- ============================================
-- 15. УПРАВЛЕНИЕ
-- ============================================
local function stopScript()
    Memory.running = false
    stopWASD()
    clearPath()
    if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
    for _, hl in pairs(espHighlights) do hl:Destroy() end
    for _, np in pairs(espNameplates) do np:Destroy() end
    espHighlights = {}
    espNameplates = {}
    Memory.currentStatus = "⏹ Остановлен"
    updateGUIStatus()
    addLog("⏹ СКРИПТ ОСТАНОВЛЕН")
end

local function restartScript()
    stopScript()
    wait(0.3)
    Memory.running = true
    Memory.exploreTarget = nil
    Memory.exploreTimer = 0
    Memory.isMoving = false
    Memory.isJumping = false
    Memory.stuckTimer = 0
    Memory.isPaused = false
    Memory.pauseTimer = 0
    Memory.lastPosition = nil
    Memory.targetPlayer = nil
    Memory.targetName = ""
    Memory.obstacleTimer = 0
    Memory.currentStatus = "🚶 Исследую карту"
    if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
    clearPath()
    updateESP()
    updateGUIStatus()
    addLog("🔄 Скрипт перезапущен")
    spawn(mainLoop)
end

gui.closeBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    gui.frame.Visible = guiVisible
end)

gui.stopBtn.MouseButton1Click:Connect(stopScript)
gui.restartBtn.MouseButton1Click:Connect(restartScript)

-- ============================================
-- 16. ЗАПУСК
-- ============================================
addLog("🐕 NPC EXPLORER v4.1 ЗАГРУЖЕН!")
addLog("🚶 Движение через WASD (эмуляция)")
addLog("🟧 Оранжевый путь до цели")
addLog("👁️ ESP: белый контур, цель – зелёная")
addLog("📏 Дистанция до цели: 8 метров")
addLog("📊 Статус отображается в GUI")

spawn(mainLoop)

player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    Memory.currentStatus = "🔄 Персонаж обновлён"
    updateESP()
    updateGUIStatus()
    addLog("🔄 Персонаж обновлён")
end)
