-- ============================================
-- NPC EXPLORER v2.0 (UNIVERSAL)
-- by Цербер для хозяйки
-- Режим: исследование карты как NPC
-- НИЧЕГО НЕ СОБИРАЕТ, НЕ УБИВАЕТ
-- Работает в ЛЮБОЙ игре
-- ============================================

local player = game.Players.LocalPlayer
local mouse = player:GetMouse()
local runService = game:GetService("RunService")
local userInput = game:GetService("UserInputService")

-- Переменные
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera

-- Настройки
local CONFIG = {
    MOVE_SPEED = 16,
    EXPLORE_RADIUS = 35,
    MIN_EXPLORE_RADIUS = 8,
    EXPLORE_CHANGE_TIME = 5,
    WALL_AVOID_DIST = 4,
    JUMP_HEIGHT = 3.5,
    TURN_SPEED = 0.3,
    LOOK_AROUND_CHANCE = 0.25,
    PAUSE_CHANCE = 0.12,
    PAUSE_TIME = 1.5,
    STUCK_THRESHOLD = 12,
}

-- Память
local Memory = {
    running = true,
    exploreTarget = nil,
    exploreTimer = 0,
    isMoving = false,
    isJumping = false,
    lastPosition = nil,
    stuckCounter = 0,
    isPaused = false,
    pauseTimer = 0,
    targetPlayer = nil,
    targetHighlight = nil,
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

-- ============================================
-- 3. ВЫБОР ЦЕЛИ (ALT + ПКМ) — ОПЦИОНАЛЬНО
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
                addLog("🎯 Цель выбрана: " .. plr.Name .. " (следование)")
                if Memory.targetHighlight then Memory.targetHighlight:Destroy() end
                local highlight = Instance.new("Highlight")
                highlight.Parent = plr.Character
                highlight.FillColor = Color3.fromRGB(0, 255, 0)
                highlight.FillTransparency = 0.3
                highlight.OutlineColor = Color3.fromRGB(0, 200, 0)
                Memory.targetHighlight = highlight
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
-- 4. ГЕНЕРАЦИЯ ТОЧЕК ДЛЯ ИССЛЕДОВАНИЯ
-- ============================================
local function getExplorePoint()
    if not rootPart then return nil end
    
    local currentPos = rootPart.Position
    local attempts = 0
    local maxAttempts = 30
    
    while attempts < maxAttempts do
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
    
    -- Если не нашли хорошую точку — просто идём в случайном направлении
    local angle = math.random() * 2 * math.pi
    local x = currentPos.X + math.cos(angle) * 15
    local z = currentPos.Z + math.sin(angle) * 15
    local groundY = getHeightAt(Vector3.new(x, currentPos.Y + 10, z))
    if groundY then
        return Vector3.new(x, groundY + 0.5, z)
    end
    return Vector3.new(x, currentPos.Y, z)
end

-- ============================================
-- 5. ПЛАВНОЕ ДВИЖЕНИЕ
-- ============================================
local function moveToTarget(targetPos)
    if not rootPart or not targetPos then return end
    
    local distance = getDistance(rootPart.Position, targetPos)
    
    if distance < 0.5 then
        humanoid:MoveTo(rootPart.Position)
        humanoid.WalkSpeed = 0
        Memory.isMoving = false
        return
    end
    
    local dir = (targetPos - rootPart.Position).Unit
    local lookDir = Vector3.new(dir.X, 0, dir.Z).Unit
    
    -- Проверка препятствий
    if isObstacle(rootPart.Position, dir, CONFIG.WALL_AVOID_DIST) then
        local rightDir = Vector3.new(-dir.Z, 0, dir.X).Unit
        local leftDir = Vector3.new(dir.Z, 0, -dir.X).Unit
        
        if canJumpOver(rootPart.Position, dir) and not Memory.isJumping and isOnGround() then
            Memory.isJumping = true
            humanoid.Jump = true
            wait(0.15)
            humanoid.Jump = false
            Memory.isJumping = false
        end
        
        if not isObstacle(rootPart.Position, rightDir, CONFIG.WALL_AVOID_DIST) then
            dir = rightDir
        elseif not isObstacle(rootPart.Position, leftDir, CONFIG.WALL_AVOID_DIST) then
            dir = leftDir
        else
            dir = -dir
            if isOnGround() then
                humanoid.Jump = true
                wait(0.1)
                humanoid.Jump = false
            end
        end
    end
    
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
    local targetPosAdjusted = rootPart.Position + dir * math.min(distance, 4)
    humanoid:MoveTo(targetPosAdjusted)
    
    if lookDir.Magnitude > 0.1 then
        local targetCFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookDir * 10)
        rootPart.CFrame = rootPart.CFrame:Lerp(targetCFrame, CONFIG.TURN_SPEED)
    end
    
    Memory.isMoving = true
end

local function stopMoving()
    if humanoid then
        humanoid:MoveTo(rootPart.Position)
        humanoid.WalkSpeed = 0
    end
    Memory.isMoving = false
end

-- ============================================
-- 6. ОСМОТР (ПОВОРОТ ГОЛОВЫ)
-- ============================================
local function lookAround()
    if not humanoid or not rootPart then return end
    
    local head = character:FindFirstChild("Head")
    if head then
        local angleY = math.rad(math.random(-40, 40))
        local angleX = math.rad(math.random(-10, 10))
        local lookAt = rootPart.CFrame * CFrame.Angles(0, angleY, 0) * CFrame.Angles(angleX, 0, 0)
        head.CFrame = head.CFrame:Lerp(lookAt, 0.3)
    end
end

-- ============================================
-- 7. ОСНОВНАЯ ЛОГИКА (NPC ПОВЕДЕНИЕ)
-- ============================================
local function npcBehavior()
    if not rootPart or not humanoid then return end
    
    -- Проверка застревания
    if Memory.lastPosition then
        local moveDist = getDistance(rootPart.Position, Memory.lastPosition)
        if moveDist < 0.2 then
            Memory.stuckCounter = Memory.stuckCounter + 1
            if Memory.stuckCounter > CONFIG.STUCK_THRESHOLD then
                humanoid.Jump = true
                wait(0.1)
                humanoid.Jump = false
                Memory.exploreTarget = getExplorePoint()
                Memory.stuckCounter = 0
                addLog("🔄 Застрял! Новая точка")
            end
        else
            Memory.stuckCounter = 0
        end
    end
    Memory.lastPosition = rootPart.Position
    
    -- ЕСЛИ ЕСТЬ ЦЕЛЬ — СЛЕДУЕМ ЗА НЕЙ
    if Memory.targetPlayer and Memory.targetPlayer.Character then
        local targetRoot = Memory.targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if targetRoot then
            local targetPos = targetRoot.Position
            local dist = getDistance(rootPart.Position, targetPos)
            
            if dist > 20 then
                -- Если цель далеко — идём быстрее
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED * 1.2
            else
                humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            end
            
            moveToTarget(targetPos)
            return
        end
    end
    
    -- ЕСЛИ НЕТ ЦЕЛИ — ИССЛЕДОВАНИЕ КАРТЫ
    Memory.exploreTimer = Memory.exploreTimer + 0.05
    
    -- Пауза (как NPC)
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
        stopMoving()
        addLog("⏸ Пауза на " .. string.format("%.1f", Memory.pauseTimer) .. "с")
        return
    end
    
    if Memory.exploreTarget then
        local dist = getDistance(rootPart.Position, Memory.exploreTarget)
        if dist < 2 then
            Memory.exploreTarget = getExplorePoint()
            if math.random() < 0.3 then
                stopMoving()
                lookAround()
                wait(0.5)
            end
        else
            moveToTarget(Memory.exploreTarget)
        end
    else
        stopMoving()
    end
end

-- ============================================
-- 8. ГЛАВНЫЙ ЦИКЛ
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
            stopMoving()
            wait(1)
            continue
        end
        
        npcBehavior()
    end
end

-- ============================================
-- 9. GUI
-- ============================================
local guiVisible = true
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "NPCExplorerGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 320, 0, 140)
    frame.Position = UDim2.new(0.5, -160, 1, -150)
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
    title.Text = "🐕 NPC EXPLORER v2.0"
    title.TextColor3 = Color3.fromRGB(255, 165, 0)
    title.TextSize = 15
    title.Font = Enum.Font.SourceSansBold
    
    local info1 = Instance.new("TextLabel")
    info1.Parent = frame
    info1.Size = UDim2.new(1, 0, 0, 20)
    info1.Position = UDim2.new(0, 0, 0, 32)
    info1.BackgroundTransparency = 1
    info1.Text = "🚶 Исследует карту как NPC"
    info1.TextColor3 = Color3.fromRGB(200, 200, 200)
    info1.TextSize = 12
    info1.Font = Enum.Font.SourceSans
    
    local info2 = Instance.new("TextLabel")
    info2.Parent = frame
    info2.Size = UDim2.new(1, 0, 0, 20)
    info2.Position = UDim2.new(0, 0, 0, 52)
    info2.BackgroundTransparency = 1
    info2.Text = "🎯 Alt + ПКМ = следовать за игроком"
    info2.TextColor3 = Color3.fromRGB(200, 200, 200)
    info2.TextSize = 12
    info2.Font = Enum.Font.SourceSans
    
    local info3 = Instance.new("TextLabel")
    info3.Parent = frame
    info3.Size = UDim2.new(1, 0, 0, 20)
    info3.Position = UDim2.new(0, 0, 0, 72)
    info3.BackgroundTransparency = 1
    info3.Text = "❌ НЕ УБИВАЕТ, НЕ СОБИРАЕТ"
    info3.TextColor3 = Color3.fromRGB(255, 100, 100)
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
-- 10. УПРАВЛЕНИЕ
-- ============================================
local function restartScript()
    Memory.running = false
    stopMoving()
    Memory.exploreTarget = nil
    Memory.exploreTimer = 0
    Memory.isMoving = false
    Memory.isJumping = false
    Memory.stuckCounter = 0
    Memory.isPaused = false
    Memory.pauseTimer = 0
    Memory.lastPosition = nil
    Memory.targetPlayer = nil
    if Memory.targetHighlight then
        Memory.targetHighlight:Destroy()
        Memory.targetHighlight = nil
    end
    
    wait(0.3)
    Memory.running = true
    addLog("🔄 Скрипт перезапущен")
    spawn(mainLoop)
end

gui.closeBtn.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    gui.frame.Visible = guiVisible
end)

gui.restartBtn.MouseButton1Click:Connect(restartScript)

-- ============================================
-- 11. ЗАПУСК
-- ============================================
addLog("🐕 NPC EXPLORER v2.0 ЗАГРУЖЕН!")
addLog("🚶 Режим: исследование карты")
addLog("🎯 Alt + ПКМ = следовать за игроком")
addLog("❌ НЕ УБИВАЕТ, НЕ СОБИРАЕТ!")

spawn(mainLoop)

-- Обновление персонажа при респавне
player.CharacterAdded:Connect(function()
    wait(0.5)
    updateCharacter()
    Memory.exploreTarget = nil
    Memory.lastPosition = nil
    addLog("🔄 Персонаж обновлён")
end)
