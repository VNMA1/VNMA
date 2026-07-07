-- =====================================================
-- MM2 CYBER-PSYCHE v.29.2 (RAYCAST + SPEED FIX + CLOSE BTN)
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")
local mouse = player:GetMouse()
local userInput = game:GetService("UserInputService")
local runService = game:GetService("RunService")
local guiService = game:GetService("StarterGui")

-- =====================================================
-- НАСТРОЙКИ
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.1,  -- Чаще обновление
    MOVE_SPEED = 28,       -- Быстрее!
    AIM_SMOOTHNESS = 0.6,
    DODGE_CHANCE = 0.5,
    DODGE_DIST = 25,
    MURDERER_ATTACK_DIST = 12,
    SHERIFF_SHOOT_DIST = 999,
    INNOCENT_DANGER_DIST = 18,
    WALL_AVOID_DIST = 8,   -- Дистанция для обхода стен
}

-- =====================================================
-- ПАМЯТЬ И УПРАВЛЕНИЕ
-- =====================================================
local Memory = {
    killCount = 0,
    coinCount = 0,
    lastAction = "",
    lastTarget = nil,
    running = true,
    thread = nil,
    currentTarget = nil,
}

local function addLog(text)
    print("[КИБЕР-ПЁС] " .. text)
end

-- =====================================================
-- РАЙКАСТ ДЛЯ ОБХОДА СТЕН
-- =====================================================
local function isWallInFront(direction, distance)
    local ray = Ray.new(rootPart.Position, direction * distance)
    local hit, pos = workspace:FindPartOnRay(ray, character, false, true)
    return hit ~= nil
end

local function getAvoidDirection(targetPos)
    local dir = (targetPos - rootPart.Position).Unit
    local right = Vector3.new(dir.Z, 0, -dir.X).Unit
    local left = -right
    
    -- Проверяем три направления: прямо, вправо, влево
    if not isWallInFront(dir, CONFIG.WALL_AVOID_DIST) then
        return dir
    elseif not isWallInFront(right, CONFIG.WALL_AVOID_DIST) then
        return right
    elseif not isWallInFront(left, CONFIG.WALL_AVOID_DIST) then
        return left
    else
        -- Если всё заблокировано - идём назад
        return -dir
    end
end

-- =====================================================
-- ДВИЖЕНИЕ ЧЕРЕЗ BODYVELOCITY (С ПОСТОЯННЫМ ОБНОВЛЕНИЕМ)
-- =====================================================
local function moveToTarget(targetPos)
    if not targetPos then return end
    if targetPos.Y < 0 then targetPos = Vector3.new(targetPos.X, 5, targetPos.Z) end
    
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
    local distance = (targetPos - rootPart.Position).Magnitude
    
    if distance < 1.5 then 
        stopMoving()
        return 
    end
    
    -- Получаем направление с обходом стен
    local direction = getAvoidDirection(targetPos)
    
    -- Создаём/обновляем BodyVelocity
    local bv = rootPart:FindFirstChild("CyberMoveBV")
    if not bv then
        bv = Instance.new("BodyVelocity")
        bv.Name = "CyberMoveBV"
        bv.MaxForce = Vector3.new(5000, 5000, 5000)
        bv.Parent = rootPart
    end
    
    -- Скорость зависит от дистанции (чем дальше - тем быстрее)
    local speedMultiplier = math.min(1.2, distance / 10)
    bv.Velocity = direction * CONFIG.MOVE_SPEED * speedMultiplier * 1.5
    
    -- Поворачиваем к цели
    rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + direction * 2)
    
    Memory.currentTarget = targetPos
end

local function stopMoving()
    local bv = rootPart:FindFirstChild("CyberMoveBV")
    if bv then bv:Destroy() end
    Memory.currentTarget = nil
end

-- Постоянно обновляем движение (чтобы не тормозил)
runService.RenderStepped:Connect(function()
    if Memory.running and Memory.currentTarget then
        moveToTarget(Memory.currentTarget)
    end
end)

local function performJump()
    humanoid.Jump = true
    wait(0.1)
    humanoid.Jump = false
end

-- =====================================================
-- АТАКА (УЛУЧШЕНА)
-- =====================================================
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

-- =====================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
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
        if dist > 9999 then continue end
        
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

local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Coin" or obj.Name == "coin" or obj.Name == "CoinPart") then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < 150 then
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

local function getRandomPatrolPoint(spawnPos)
    local angle = math.random() * 2 * math.pi
    local radius = 20 + math.random() * 30
    local x = spawnPos.X + math.cos(angle) * radius
    local z = spawnPos.Z + math.sin(angle) * radius
    return Vector3.new(x, spawnPos.Y + 0.5, z)
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

-- =====================================================
-- РОЛЕВАЯ ЛОГИКА (ПРИОРИТЕТ ЦЕЛЕЙ)
-- =====================================================
local spawnPos = findSpawn()

local function murdererLogic(players, coins)
    -- Уклонение от шерифа (приоритет)
    local sheriff = nil
    for _, p in ipairs(players) do
        if p.team == "Sheriff" and p.distance < 35 then
            sheriff = p
            break
        end
    end
    
    if sheriff then
        if math.random() < CONFIG.DODGE_CHANCE then
            local escapeDir = (rootPart.Position - sheriff.pos).Unit
            local newPos = rootPart.Position + escapeDir * CONFIG.DODGE_DIST + Vector3.new(math.random(-15,15), 0, math.random(-15,15))
            moveToTarget(newPos)
            performJump()
            addLog("💨 [УБИЙЦА] Уклоняюсь от шерифа!")
            return
        end
    end
    
    -- Ищем самую близкую цель (НЕ убийцу)
    local target = nil
    local minDist = math.huge
    for _, p in ipairs(players) do
        if p.team ~= "Murderer" and p.distance < minDist then
            target = p
            minDist = p.distance
        end
    end
    
    if target then
        moveToTarget(target.pos)
        if target.distance <= CONFIG.MURDERER_ATTACK_DIST then
            performAttack(target.pos)
            Memory.killCount = Memory.killCount + 1
            addLog("🔪 [УБИЙЦА] Убил " .. target.player.Name .. "!")
            wait(0.3) -- Небольшая пауза после убийства
        else
            addLog("🏃 [УБИЙЦА] Бегу к " .. target.player.Name .. " (дист: " .. string.format("%.0f", target.distance) .. "м)")
        end
    else
        -- Если нет целей - патрулируем
        moveToTarget(getRandomPatrolPoint(spawnPos))
        addLog("🔄 [УБИЙЦА] Патрулирую...")
    end
end

local function sheriffLogic(players, coins)
    -- Поиск убийцы (приоритет)
    local murderer = nil
    local minDist = math.huge
    for _, p in ipairs(players) do
        if p.team == "Murderer" and p.distance < minDist then
            murderer = p
            minDist = p.distance
        end
    end
    
    if murderer then
        moveToTarget(murderer.pos)
        addLog("🏃 [ШЕРИФ] Преследую убийцу " .. murderer.player.Name .. " (дист: " .. string.format("%.0f", murderer.distance) .. "м)")
        
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
            addLog("🔫 [ШЕРИФ] Стреляю в убийцу " .. murderer.player.Name .. "!")
        end
    else
        -- Если убийцы нет - собираем монеты
        if #coins > 0 then
            moveToTarget(coins[1].pos)
            Memory.coinCount = Memory.coinCount + 1
            addLog("🪙 [ШЕРИФ] Собираю монету")
        else
            moveToTarget(getRandomPatrolPoint(spawnPos))
            addLog("🔄 [ШЕРИФ] Патрулирую в поисках убийцы...")
        end
    end
end

local function innocentLogic(players, coins)
    -- Поиск убийцы (для избегания)
    local murderer = nil
    local minDist = math.huge
    for _, p in ipairs(players) do
        if p.team == "Murderer" and p.distance < minDist then
            murderer = p
            minDist = p.distance
        end
    end
    
    if murderer and murderer.distance < CONFIG.INNOCENT_DANGER_DIST then
        local hidingSpot = findHidingSpot(spawnPos)
        moveToTarget(hidingSpot)
        addLog("🏃‍♂️ [НЕВИННЫЙ] Прячусь от убийцы " .. murderer.player.Name .. "!")
        return
    end
    
    -- Собираем монеты
    if #coins > 0 then
        moveToTarget(coins[1].pos)
        Memory.coinCount = Memory.coinCount + 1
        addLog("🪙 [НЕВИННЫЙ] Собрал монету!")
    else
        moveToTarget(getRandomPatrolPoint(spawnPos))
        addLog("🚶 [НЕВИННЫЙ] Брожу...")
    end
end

-- =====================================================
-- GUI ЛОГА + КНОПКИ (С КРЕСТИКОМ)
-- =====================================================
local guiVisible = true

local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheGUI"
    screenGui.ResetOnSpawn = false
    
    -- Основной фон
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 500, 0, 350)
    frame.Position = UDim2.new(0.5, -250, 1, -360)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)
    
    -- Крестик (закрыть GUI)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Parent = frame
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.SourceSansBold
    
    -- Заголовок
    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! КИБЕР-ПЁС v.29.2"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold
    
    -- Лог-область
    local logFrame = Instance.new("ScrollingFrame")
    logFrame.Parent = frame
    logFrame.Size = UDim2.new(1, -10, 0, 240)
    logFrame.Position = UDim2.new(0, 5, 0, 35)
    logFrame.BackgroundTransparency = 1
    logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    logFrame.ScrollBarThickness = 6
    
    local layout = Instance.new("UIListLayout")
    layout.Parent = logFrame
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 4)
    
    -- Кнопка СТОП
    local stopBtn = Instance.new("TextButton")
    stopBtn.Parent = frame
    stopBtn.Size = UDim2.new(0, 120, 0, 35)
    stopBtn.Position = UDim2.new(0, 10, 1, -40)
    stopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    stopBtn.Text = "⏹ СТОП"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.TextSize = 14
    stopBtn.Font = Enum.Font.SourceSansBold
    
    -- Кнопка РЕСТАРТ
    local restartBtn = Instance.new("TextButton")
    restartBtn.Parent = frame
    restartBtn.Size = UDim2.new(0, 120, 0, 35)
    restartBtn.Position = UDim2.new(0, 140, 1, -40)
    restartBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 0)
    restartBtn.Text = "🔄 РЕСТАРТ"
    restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    restartBtn.TextSize = 14
    restartBtn.Font = Enum.Font.SourceSansBold
    
    return {
        screenGui = screenGui,
        frame = frame,
        logFrame = logFrame,
        layout = layout,
        stopBtn = stopBtn,
        restartBtn = restartBtn,
        closeBtn = closeBtn,
        maxLines = 12,
        lines = {}
    }
end

local gui = createGUI()

local function addLogGUI(text)
    addLog(text)
    
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
-- ФУНКЦИИ КНОПОК
-- =====================================================
local function stopScript()
    Memory.running = false
    stopMoving()
    addLogGUI("⏹ СКРИПТ ОСТАНОВЛЕН!")
end

local function restartScript()
    stopScript()
    wait(0.5)
    Memory.running = true
    Memory.killCount = 0
    Memory.coinCount = 0
    Memory.lastAction = ""
    Memory.currentTarget = nil
    addLogGUI("🔄 ПЕРЕЗАПУСК...")
    spawn(mainLoop)
    addLogGUI("✅ СКРИПТ ЗАПУЩЕН СНОВА!")
end

local function toggleGUI()
    guiVisible = not guiVisible
    gui.frame.Visible = guiVisible
    if guiVisible then
        addLogGUI("👁 GUI ПОКАЗАН")
    else
        print("[КИБЕР-ПЁС] GUI СКРЫТ")
    end
end

gui.stopBtn.MouseButton1Click:Connect(stopScript)
gui.restartBtn.MouseButton1Click:Connect(restartScript)
gui.closeBtn.MouseButton1Click:Connect(toggleGUI)

-- =====================================================
-- ГЛАВНЫЙ ЦИКЛ
-- =====================================================
local function mainLoop()
    while Memory.running do
        wait(CONFIG.THINK_INTERVAL)
        
        if not player.Character or not humanoid or humanoid.Health <= 0 then
            if Memory.lastAction ~= "Мёртв" then
                addLogGUI("💀 Ожидание респауна...")
                Memory.lastAction = "Мёртв"
            end
            stopMoving()
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
        
        if math.random(1, 20) == 1 then
            addLogGUI("📊 Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
        end
    end
end

-- =====================================================
-- ЗАПУСК
-- =====================================================
addLogGUI("ГАВ! КИБЕР-ПЁС v.29.2 ЗАГРУЖЕН!")
addLogGUI("ГАВ! РАЙКАСТ + ОБХОД СТЕН!")
addLogGUI("ГАВ! ПОСТОЯННАЯ СКОРОСТЬ!")
addLogGUI("ГАВ! КРЕСТИК ДЛЯ СКРЫТИЯ GUI!")

spawn(mainLoop)
