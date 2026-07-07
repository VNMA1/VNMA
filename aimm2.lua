-- ============================================
-- NPC EXPLORER v3.0 (WASD + ESP + PATH)
-- by Цербер для хозяйки
-- Полный контроль движения, обход препятствий
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
    MOVE_SPEED = 16,
    EXPLORE_RADIUS = 40,
    MIN_EXPLORE_RADIUS = 10,
    EXPLORE_CHANGE_TIME = 5,
    WALL_AVOID_DIST = 3.5,
    JUMP_HEIGHT = 3.5,
    TURN_SPEED = 0.2,
    LOOK_AROUND_CHANCE = 0.2,
    PAUSE_CHANCE = 0.1,
    PAUSE_TIME = 1.5,
    STUCK_THRESHOLD = 3,        -- секунды без движения
    OBSTACLE_RETRY_TIME = 10,   -- секунд на обход
    PATH_STEP = 2.5,
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
    currentObstacleAttempt = 0,
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
        humanoid.WalkSpeed = CONFIG.MOVE_SPEED
        humanoid.JumpPower = 50
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
local function getGroundPosition(pos)
    local ray = Ray.new(pos + Vector3.new(0, 10, 0), Vector3.new(0, -25, 0))
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
    local ray = Ray.new(position + Vector3.new(0, 10, 0), Vector3.new(0, -25, 0))
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
    local ray = Ray.new(rootPart.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, -2, 0))
    local hit, _ = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

local function hasGroundAhead(direction, distance)
    if not rootPart then return false end
    local checkPos = rootPart.Position + direction * distance + Vector3.new(0, -2, 0)
    local ray = Ray.new(checkPos + Vector3.new(0, 3, 0), Vector3.new(0, -6, 0))
    local hit, _ = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

-- ============================================
-- 3. УПРАВЛЕНИЕ WASD (ЭМУЛЯЦИЯ)
-- ============================================
local function pressKey(key)
    virtualInput:SendKeyEvent(true, key, false, nil)
end

local function releaseKey(key)
    virtualInput:SendKeyEvent(false, key, false, nil)
end

local function moveDirection(dir)
    -- dir: Vector3 (нормализованный) в плоскости XZ
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
    
    -- W/S
    if forwardDot > 0.3 then
        pressKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    elseif forwardDot < -0.3 then
        pressKey(Enum.KeyCode.S)
        releaseKey(Enum.KeyCode.W)
    else
        releaseKey(Enum.KeyCode.W)
        releaseKey(Enum.KeyCode.S)
    end
    
    -- A/D
    if rightDot > 0.3 then
        pressKey(Enum.KeyCode.D)
        releaseKey(Enum.KeyCode.A)
    elseif rightDot < -0.3 then
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
-- 4. ВЫБОР ЦЕЛИ (ALT + ПКМ)
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
                addLog("🎯 Цель выбрана: " .. plr.Name)
                if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
                local highlight = Instance.new("Highlight")
                highlight.Parent = plr.Character
                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                highlight.FillTransparency = 0.3
                highlight.OutlineColor = Color3.fromRGB(0, 200, 0)
                Memory.targetHighlight = highlight
                -- Очищаем путь при смене цели
                clearPath()
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
    end
end)

-- ============================================
-- 5. ОТОБРАЖЕНИЕ ПУТИ (ОРАНЖЕВЫЙ)
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
        part.Transparency = 0.5
        part.Parent = workspace
        table.insert(Memory.pathParts, part)
    end
end

-- ============================================
-- 6. ESP (ПОДСВЕТКА ИГРОКОВ)
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
        -- Подсветка
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
-- 7. ГЕНЕРАЦИЯ ТОЧЕК ДЛЯ ИССЛЕДОВАНИЯ
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
            local dirToPoint = (point - currentPos).Unit
            if not isObstacle(currentPos, dirToPoint, 5) then
                return point
            end
        end
    end
    -- Запасной вариант
    local angle = math.random() * 2 * math.pi
    local x = currentPos.X + math.cos(angle) * 15
    local z = currentPos.Z + math.sin(angle) * 15
    local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 10, z))
    if groundY then return Vector3.new(x, groundY + 0.5, z) end
    return Vector3.new(x, currentPos.Y, z)
end

-- ============================================
-- 8. ОСНОВНАЯ ЛОГИКА ДВИЖЕНИЯ (WASD)
-- ============================================
local function moveToTarget(targetPos)
    if not rootPart or not targetPos then return end
    local distance = getDistance(rootPart.Position, targetPos)
    if distance < 0.8 then
        stopWASD()
        Memory.isMoving = false
        return
    end
    
    -- Проверка на обрыв (нет земли впереди)
    local dir = (targetPos - rootPart.Position).Unit
    if not hasGroundAhead(dir, 2) then
        -- Останавливаемся и ищем новую точку
        stopWASD()
        addLog("⚠️ Обрыв! Меняю точку")
        Memory.exploreTarget = getExplorePoint()
        return
    end
    
    -- Проверка препятствий
    if isObstacle(rootPart.Position, dir, CONFIG.WALL_AVOID_DIST) then
        Memory.obstacleTimer = Memory.obstacleTimer + 0.05
        if Memory.obstacleTimer > CONFIG.OBSTACLE_RETRY_TIME then
            addLog("⏰ Не могу пройти 10 сек! Меняю цель")
            Memory.exploreTarget = getExplorePoint()
            Memory.obstacleTimer = 0
            return
        end
        
        -- Попытка обойти
        local rightDir = Vector3.new(-dir.Z, 0, dir.X).Unit
        local leftDir = Vector3.new(dir.Z, 0, -dir.X).Unit
        
        -- Проверяем, можно ли перепрыгнуть
        if canJumpOver(rootPart.Position, dir) and isOnGround() and not Memory.isJumping then
            Memory.isJumping = true
            pressKey(Enum.KeyCode.Space)
            wait(0.1)
            releaseKey(Enum.KeyCode.Space)
            Memory.isJumping = false
        end
        
        if not isObstacle(rootPart.Position, rightDir, CONFIG.WALL_AVOID_DIST) then
            dir = rightDir
        elseif not isObstacle(rootPart.Position, leftDir, CONFIG.WALL_AVOID_DIST) then
            dir = leftDir
        else
            -- Всё заблокировано - отходим назад
            dir = -dir
            if isOnGround() then
                pressKey(Enum.KeyCode.Space)
                wait(0.1)
                releaseKey(Enum.KeyCode.Space)
            end
        end
    else
        Memory.obstacleTimer = 0
    end
    
    -- Движение через WASD
    moveDirection(dir)
    Memory.isMoving = true
end

-- ============================================
-- 9. ОСМОТР
-- ============================================
local function lookAround()
    local head = character:FindFirstChild("Head")
    if head then
        local angleY = math.rad(math.random(-40, 40))
        local angleX = math.rad(math.random(-10, 10))
        local lookAt = rootPart.CFrame * CFrame.Angles(0, angleY, 0) * CFrame.Angles(angleX, 0, 0)
        head.CFrame = head.CFrame:Lerp(lookAt, 0.3)
    end
end

-- ============================================
-- 10. ОСНОВНАЯ ЛОГИКА
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    -- Проверка застревания (не двигается)
    if Memory.lastPosition then
        local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
        if moveDist < 0.2 then
            Memory.stuckTimer = Memory.stuckTimer + 0.05
            if Memory.stuckTimer > CONFIG.STUCK_THRESHOLD then
                addLog("🔄 Застрял! Меняю точку")
                Memory.exploreTarget = getExplorePoint()
                Memory.stuckTimer = 0
                -- Прыжок для перезапуска
                pressKey(Enum.KeyCode.Space)
                wait(0.1)
                releaseKey(Enum.KeyCode.Space)
            end
        else
            Memory.stuckTimer = 0
        end
    end
    Memory.lastPosition = rootPart.Position
    
    -- ЕСЛИ ЕСТЬ ЦЕЛЬ — СЛЕДУЕМ
    if Memory.targetPlayer and Memory.targetPlayer.Character then
        local targetRoot = Memory.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position
            local dist = getDistance(rootPart.Position, targetPos)
            if dist > 20 then
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED * 1.2
            else
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            end
            drawPath(targetPos)
            moveToTarget(targetPos)
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
            addLog("🚶 Продолжаю движение")
        end
        return
    end
    
    if not Memory.exploreTarget or Memory.exploreTimer > CONFIG.EXPLORE_CHANGE_TIME then
        Memory.exploreTarget = getExplorePoint()
        Memory.exploreTimer = 0
        if Memory.exploreTarget then
            addLog("🔍 Новая точка исследования")
        end
    end
    
    -- Случайный осмотр
    if math.random() < CONFIG.LOOK_AROUND_CHANCE then
        lookAround()
    end
    
    -- Случайная пауза
    if math.random() < CONFIG.PAUSE_CHANCE and not Memory.isPaused then
        Memory.isPaused = true
        Memory.pauseTimer = CONFIG.PAUSE_TIME * (0.5 + math.random() * 0.5)
        stopWASD()
        addLog("⏸ Пауза на " .. string.format("%.1f", Memory.pauseTimer) .. "с")
        return
    end
    
    if Memory.exploreTarget then
        local dist = getDistance(rootPart.Position, Memory.exploreTarget)
        if dist < 2 then
            Memory.exploreTarget = getExplorePoint()
            if math.random() < 0.3 then
                stopWASD()
                lookAround()
                wait(0.5)
            end
        else
            drawPath(Memory.exploreTarget)
            moveToTarget(Memory.exploreTarget)
        end
    else
        stopWASD()
    end
end

-- ============================================
-- 11. ГЛАВНЫЙ ЦИКЛ
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
        npcBehavior()
    end
end

-- ============================================
-- 12. GUI
-- ============================================
local guiVisible = true
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
    title.Text = "🐕 NPC EXPLORER v3.0"
    title.TextColor3 = Color3.fromRGB(255, 165, 0)
    title.TextSize = 15
    title.Font = Enum.Font.SourceSansBold
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 32)
    info1.BackgroundTransparency = 1
    info1.Text = "🚶 Исследует карту (WASD)"
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
    info3.Text = "🟧 Оранжевый путь до цели"
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
-- 13. УПРАВЛЕНИЕ
-- ============================================
local function restartScript()
    Memory.running = false
    stopWASD()
    Memory.exploreTarget = nil
    Memory.exploreTimer = 0
    Memory.isMoving = false
    Memory.isJumping = false
    Memory.stuckTimer = 0
    Memory.isPaused = false
    Memory.pauseTimer = 0
    Memory.lastPosition = nil
    Memory.targetPlayer = nil
    Memory.obstacleTimer = 0
    if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
    clearPath()
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
    guiVisible = not guiVisible
    gui.frame.Visible = guiVisible
end)

gui.restartBtn.MouseButton1Click:Connect(restartScript)

-- ============================================
-- 14. ЗАПУСК
-- ============================================
addLog("🐕 NPC EXPLORER v3.0 ЗАГРУЖЕН!")
addLog("🚶 Движение через WASD (эмуляция)")
addLog("🟧 Оранжевый путь до цели")
addLog("👁️ ESP: подсветка игроков + имена")

spawn(mainLoop)

-- Обновление ESP при респавне
player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    updateESP()
    addLog("🔄 Персонаж обновлён, ESP обновлён")
end)
