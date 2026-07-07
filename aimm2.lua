-- ============================================
-- NPC EXPLORER v3.1 (FULLY FIXED)
-- by Цербер для хозяйки
-- НЕТ ТОРМОЗОВ, УМНЫЙ ОБХОД, КНОПКА СТОП
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
    EXPLORE_RADIUS = 45,
    MIN_EXPLORE_RADIUS = 12,
    EXPLORE_CHANGE_TIME = 4,      -- меняем точку каждые 4 сек
    WALL_AVOID_DIST = 3.5,
    JUMP_HEIGHT = 4,
    TURN_SPEED = 0.15,            -- плавный поворот
    LOOK_AROUND_CHANCE = 0.15,
    PAUSE_CHANCE = 0.08,
    PAUSE_TIME = 1.2,
    STUCK_THRESHOLD = 2.5,        -- секунды
    OBSTACLE_RETRY_TIME = 8,
    PATH_STEP = 2.5,
    HEIGHT_CHECK_DIST = 3,        -- для проверки пола впереди
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
        humanoid.JumpPower = 55
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
-- 3. УПРАВЛЕНИЕ WASD (ЭМУЛЯЦИЯ)
-- ============================================
local function pressKey(key)
    virtualInput:SendKeyEvent(true, key, false, nil)
end

local function releaseKey(key)
    virtualInput:SendKeyEvent(false, key, false, nil)
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
    
    -- W/S
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
    
    -- A/D
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
                -- Удаляем старую подсветку
                if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
                -- Создаём зелёную подсветку для цели
                local hl = Instance.new("Highlight")
                hl.Parent = plr.Character
                hl.FillColor = Color3.fromRGB(0, 255, 0)
                hl.FillTransparency = 0.5
                hl.OutlineColor = Color3.fromRGB(0, 255, 0)
                hl.OutlineTransparency = 0.2
                Memory.targetHighlight = hl
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
-- 5. ПУТЬ (ОРАНЖЕВЫЙ)
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
-- 6. ESP (АККУРАТНЫЙ КОНТУР)
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
        
        -- Если это выбранная цель — её подсветка уже создана отдельно
        if plr == Memory.targetPlayer then
            -- пропускаем, чтобы не перезаписывать зелёный
        else
            -- Для всех остальных — белый контур без заливки
            local hl = Instance.new("Highlight")
            hl.Parent = char
            hl.FillColor = Color3.fromRGB(255, 255, 255)
            hl.FillTransparency = 1  -- полностью прозрачная заливка
            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            hl.OutlineTransparency = 0.3
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            table.insert(espHighlights, hl)
        end
        
        -- Имя (для всех, кроме себя)
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

-- Обновляем ESP при изменении списка игроков
players.PlayerAdded:Connect(updateESP)
players.PlayerRemoving:Connect(updateESP)
-- Также обновляем, если цель изменилась
local oldTarget = nil
game:GetService("RunService").Heartbeat:Connect(function()
    if Memory.targetPlayer ~= oldTarget then
        oldTarget = Memory.targetPlayer
        updateESP()
    end
end)

updateESP()

-- ============================================
-- 7. ГЕНЕРАЦИЯ ТОЧЕК
-- ============================================
local function getExplorePoint()
    if not rootPart then return nil end
    local currentPos = rootPart.Position
    local attempts = 0
    while attempts < 35 do
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
    -- fallback
    local angle = math.random() * 2 * math.pi
    local x = currentPos.X + math.cos(angle) * 15
    local z = currentPos.Z + math.sin(angle) * 15
    local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 15, z))
    if groundY then return Vector3.new(x, groundY + 0.5, z) end
    return Vector3.new(x, currentPos.Y, z)
end

-- ============================================
-- 8. УМНЫЙ ОБХОД (С ПРОВЕРКОЙ ВСЕХ НАПРАВЛЕНИЙ)
-- ============================================
local function findClearDirection(targetPos)
    if not rootPart then return (targetPos - rootPart.Position).Unit end
    
    local dir = (targetPos - rootPart.Position).Unit
    local right = Vector3.new(-dir.Z, 0, dir.X).Unit
    local left = Vector3.new(dir.Z, 0, -dir.X).Unit
    
    -- Проверяем 5 вариантов: прямо, правее, левее, сильно правее, сильно левее
    local options = {
        {dir = dir, angle = 0},
        {dir = (dir + right * 0.5).Unit, angle = 30},
        {dir = (dir - right * 0.5).Unit, angle = -30},
        {dir = (dir + right * 0.8).Unit, angle = 50},
        {dir = (dir - right * 0.8).Unit, angle = -50},
        {dir = -dir, angle = 180},  -- назад
    }
    
    local best = nil
    local bestScore = -math.huge
    
    for _, opt in ipairs(options) do
        local d = opt.dir
        -- Проверяем, есть ли стена в этом направлении
        local blocked = isObstacle(rootPart.Position, d, CONFIG.WALL_AVOID_DIST)
        -- Проверяем, есть ли пол впереди
        local hasFloor = hasGroundAhead(d, 2.5)
        -- Также проверяем, можно ли перепрыгнуть
        local canJump = canJumpOver(rootPart.Position, d)
        
        local score = 0
        if not blocked then score = score + 3 end
        if hasFloor then score = score + 2 end
        if canJump then score = score + 1 end
        -- Чем меньше угол отклонения от прямого направления, тем лучше
        score = score - math.abs(opt.angle) / 30
        
        if score > bestScore then
            bestScore = score
            best = d
        end
    end
    
    return best or dir
end

-- ============================================
-- 9. ДВИЖЕНИЕ (БЕЗ ТОРМОЗОВ)
-- ============================================
local function moveToTarget(targetPos)
    if not rootPart or not targetPos then return end
    local distance = getDistance(rootPart.Position, targetPos)
    if distance < 0.8 then
        stopWASD()
        Memory.isMoving = false
        return
    end
    
    -- Корректируем высоту цели, чтобы не зависать на возвышениях
    local targetY = getHeightAt(targetPos)
    if targetY then
        targetPos = Vector3.new(targetPos.X, targetY + 0.5, targetPos.Z)
    end
    
    local dir = (targetPos - rootPart.Position).Unit
    
    -- Проверка на обрыв
    if not hasGroundAhead(dir, 2) then
        stopWASD()
        addLog("⚠️ Обрыв! Меняю точку")
        Memory.exploreTarget = getExplorePoint()
        return
    end
    
    -- Умный выбор направления (обход)
    local finalDir = findClearDirection(targetPos)
    
    -- Если направление сильно отличается от прямого, считаем что препятствие
    if finalDir ~= dir and (finalDir - dir).Magnitude > 0.3 then
        Memory.obstacleTimer = Memory.obstacleTimer + 0.05
        if Memory.obstacleTimer > CONFIG.OBSTACLE_RETRY_TIME then
            addLog("⏰ Не могу пройти 8 сек! Меняю цель")
            Memory.exploreTarget = getExplorePoint()
            Memory.obstacleTimer = 0
            return
        end
    else
        Memory.obstacleTimer = 0
    end
    
    -- Если можно перепрыгнуть и не прыгаем
    if canJumpOver(rootPart.Position, finalDir) and isOnGround() and not Memory.isJumping then
        Memory.isJumping = true
        pressKey(Enum.KeyCode.Space)
        wait(0.12)
        releaseKey(Enum.KeyCode.Space)
        Memory.isJumping = false
    end
    
    -- Двигаемся
    moveDirection(finalDir)
    Memory.isMoving = true
end

-- ============================================
-- 10. ОСМОТР (СМОТРИТ НА ЦЕЛЬ)
-- ============================================
local function lookAtTarget(targetPos)
    if not rootPart or not targetPos then return
    local head = character:FindFirstChild("Head")
    if head then
        local lookDir = (targetPos - head.Position).Unit
        local targetCFrame = CFrame.lookAt(head.Position, head.Position + lookDir * 10)
        head.CFrame = head.CFrame:Lerp(targetCFrame, 0.15)
    end
end

-- ============================================
-- 11. ОСНОВНАЯ ЛОГИКА
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    -- Проверка застревания
    if Memory.lastPosition then
        local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
        if moveDist < 0.15 then
            Memory.stuckTimer = Memory.stuckTimer + 0.05
            if Memory.stuckTimer > CONFIG.STUCK_THRESHOLD then
                addLog("🔄 Застрял! Меняю точку")
                Memory.exploreTarget = getExplorePoint()
                Memory.stuckTimer = 0
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
            humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            drawPath(targetPos)
            moveToTarget(targetPos)
            -- Смотрим на цель
            lookAtTarget(targetPos)
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
    
    -- Случайный осмотр (без цели)
    if math.random() < CONFIG.LOOK_AROUND_CHANCE then
        -- просто повернуть голову влево/вправо
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
                wait(0.3)
            end
        else
            drawPath(Memory.exploreTarget)
            moveToTarget(Memory.exploreTarget)
        end
    else
        stopWASD()
    end
end

local function lookAround()
    local head = character:FindFirstChild("Head")
    if head then
        local angleY = math.rad(math.random(-35, 35))
        local angleX = math.rad(math.random(-8, 8))
        local lookAt = rootPart.CFrame * CFrame.Angles(0, angleY, 0) * CFrame.Angles(angleX, 0, 0)
        head.CFrame = head.CFrame:Lerp(lookAt, 0.2)
    end
end

-- ============================================
-- 12. ГЛАВНЫЙ ЦИКЛ
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
-- 13. GUI (С КНОПКОЙ СТОП)
-- ============================================
local guiVisible = true
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "NPCExplorerGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 340, 0, 180)
    frame.Position = UDim2.new(0.5, -170, 1, -190)
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
    title.Text = "🐕 NPC EXPLORER v3.1"
    title.TextColor3 = Color3.fromRGB(255, 165, 0)
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 32)
    info1.BackgroundTransparency = 1
    info1.Text = "🚶 Исследует карту (WASD)"
    info1.TextColor3 = Color3.fromRGB(200, 200, 200)
    info1.TextSize = 12
    
    local info2 = Instance.new("TextLabel")
    info2.Parent = frame
    info2.Size = UDim2.new(1, 0, 0, 20)
    info2.Position = UDim2.new(0, 0, 0, 52)
    info2.BackgroundTransparency = 1
    info2.Text = "🎯 Alt+ПКМ = следовать за игроком"
    info2.TextColor3 = Color3.fromRGB(200, 200, 200)
    info2.TextSize = 12
    
    local info3 = Instance.new("TextLabel")
    info3.Parent = frame
    info3.Size = UDim2.new(1, 0, 0, 20)
    info3.Position = UDim2.new(0, 0, 0, 72)
    info3.BackgroundTransparency = 1
    info3.Text = "🟧 Оранжевый путь до цели"
    info3.TextColor3 = Color3.fromRGB(255, 200, 100)
    info3.TextSize = 12
    
    -- Кнопка СТОП
    local stopBtn = Instance.new("TextButton")
    stopBtn.Parent = frame
    stopBtn.Size = UDim2.new(0, 100, 0, 30)
    stopBtn.Position = UDim2.new(0.05, 0, 1, -35)
    stopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    stopBtn.Text = "⏹ СТОП"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.TextSize = 14
    stopBtn.Font = Enum.Font.SourceSansBold
    
    -- Кнопка РЕСТАРТ
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
-- 14. УПРАВЛЕНИЕ
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
    Memory.obstacleTimer = 0
    if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
    clearPath()
    updateESP()
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
-- 15. ЗАПУСК
-- ============================================
addLog("🐕 NPC EXPLORER v3.1 ЗАГРУЖЕН!")
addLog("🚶 Движение через WASD (эмуляция)")
addLog("🟧 Оранжевый путь до цели")
addLog("👁️ ESP: белый контур, цель – зелёная")
addLog("⏹ Кнопка СТОП добавлена")

spawn(mainLoop)

-- Обновление ESP при респавне
player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    updateESP()
    addLog("🔄 Персонаж обновлён")
end)
