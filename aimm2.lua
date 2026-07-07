-- =====================================================
-- MM2 CYBER-PSYCHE v.23.0 (SMART MOVEMENT)
-- ХОДИТ КАК ЧЕЛОВЕК: ЗИГЗАГИ, ПАУЗЫ, БЕЗ СТЕН!
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
-- 1. НАСТРОЙКИ (ОПТИМИЗИРОВАНЫ)
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.15,
    ATTACK_DIST = 15,
    MAX_VIEW_DIST = 100,
    PATROL_RADIUS = 20,          -- меньше радиус, чтобы не бегать по кругу
    MOVE_SPEED = 16,
    AIM_SMOOTHNESS = 0.8,
    DODGE_CHANCE = 0.3,
    DODGE_DIST = 20,
    STUCK_CHECK_INTERVAL = 1.5,
    JUMP_FORWARD_DIST = 6,
    ZIGZAG_CHANCE = 0.3,         -- шанс зигзага при ходьбе
    DIRECTION_CHANGE_INTERVAL = 3, -- меняем направление каждые 3 сек
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    patrolAngle = 0,
    killCount = 0,
    coinCount = 0,
    lastAction = "",
    isDodging = false,
    lastPosition = Vector3.new(0, 0, 0),
    stuckTimer = 0,
    isStuck = false,
    directionChangeTimer = 0,
    currentTarget = nil,
    zigzagOffset = Vector3.new(0, 0, 0),
}

-- =====================================================
-- 3. УМНОЕ ДВИЖЕНИЕ (БЕЗ PATHFINDING)
-- =====================================================
local function moveToTarget(targetPos)
    if not targetPos then return end

    local currentPos = rootPart.Position
    local distanceToTarget = (currentPos - targetPos).Magnitude

    -- Если цель уже рядом — останавливаемся
    if distanceToTarget < 2 then
        humanoid:MoveTo(currentPos)
        return
    end

    -- Проверка застревания
    local distanceMoved = (currentPos - Memory.lastPosition).Magnitude
    if distanceMoved < 0.3 then
        Memory.stuckTimer = Memory.stuckTimer + CONFIG.THINK_INTERVAL
    else
        Memory.stuckTimer = 0
    end

    -- Если застрял — прыгаем в сторону
    if Memory.stuckTimer > CONFIG.STUCK_CHECK_INTERVAL then
        Memory.isStuck = true
        local jumpDirection = (targetPos - currentPos).Unit
        local sideDirection = Vector3.new(jumpDirection.Z, 0, -jumpDirection.X) -- перпендикуляр
        local jumpPos = currentPos + (jumpDirection + sideDirection * 0.5) * CONFIG.JUMP_FORWARD_DIST
        humanoid:MoveTo(jumpPos)
        performJump()
        Memory.stuckTimer = 0
        addLog("🏃‍♂️ ПРЫЖОК В СТОРОНУ!")
        return
    else
        Memory.isStuck = false
    end

    -- Зигзаг (имитация человека)
    local zigzag = Vector3.new(0, 0, 0)
    if math.random() < CONFIG.ZIGZAG_CHANCE then
        local angle = math.random(-30, 30)
        zigzag = Vector3.new(math.sin(math.rad(angle)), 0, math.cos(math.rad(angle))) * 3
    end

    -- Меняем направление каждые 3 секунды (чтобы не бегать по кругу)
    Memory.directionChangeTimer = Memory.directionChangeTimer + CONFIG.THINK_INTERVAL
    if Memory.directionChangeTimer > CONFIG.DIRECTION_CHANGE_INTERVAL then
        Memory.directionChangeTimer = 0
        Memory.zigzagOffset = Vector3.new(math.random(-5, 5), 0, math.random(-5, 5))
    end

    -- Финальная точка с учётом зигзага и смещения
    local finalTarget = targetPos + zigzag + Memory.zigzagOffset
    humanoid:MoveTo(finalTarget)

    -- Обновляем позицию
    Memory.lastPosition = currentPos
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
end

-- =====================================================
-- 4. ПАТРУЛЬ (ХАОТИЧНЫЙ, КАК У ИГРОКА)
-- =====================================================
local function getPatrolPoint(spawnPos)
    -- Вместо круга — случайные точки в радиусе
    local angle = math.random() * 2 * math.pi
    local radius = CONFIG.PATROL_RADIUS * (0.5 + math.random() * 0.5) -- случайный радиус
    local x = spawnPos.X + math.cos(angle) * radius
    local z = spawnPos.Z + math.sin(angle) * radius
    return Vector3.new(x, spawnPos.Y, z)
end

-- =====================================================
-- 5. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (БЕЗ ИЗМЕНЕНИЙ)
-- =====================================================
local function findSpawn()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("SpawnLocation") or obj.Name == "Spawn" then
            return obj.Position
        end
    end
    return Vector3.new(0, 5, 0)
end

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

        table.insert(targets, {
            player = plr,
            distance = dist,
            pos = plrRoot.Position,
            team = plr.Team and plr.Team.Name or "Innocent",
        })
    end
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and obj.Name == "Coin" then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < CONFIG.MAX_VIEW_DIST then
                table.insert(coins, {pos = obj.Position, dist = dist})
            end
        end
    end
    table.sort(coins, function(a, b) return a.dist < b.dist end)
    return coins
end

local function aimAt(targetPos)
    if not targetPos then return end
    local screenPos, onScreen = camera:WorldToScreenPoint(targetPos)
    if not onScreen then return end
    local currentMousePos = Vector2.new(mouse.X, mouse.Y)
    local targetMousePos = Vector2.new(screenPos.X, screenPos.Y)
    local smoothPos = currentMousePos + (targetMousePos - currentMousePos) * CONFIG.AIM_SMOOTHNESS
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

local function dodgeFromSheriff(sheriffPos)
    if not sheriffPos then return end
    local escapeDir = (rootPart.Position - sheriffPos).Unit
    local zigzag = Vector3.new(math.random(-15,15), 0, math.random(-15,15))
    local newPos = rootPart.Position + escapeDir * CONFIG.DODGE_DIST + zigzag
    moveToTarget(newPos)
    performJump()
end

-- =====================================================
-- 6. GUI ЛОГА
-- =====================================================
local function createLogGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheLog"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 420, 0, 260)
    frame.Position = UDim2.new(0.5, -210, 1, -270)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)

    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! ЛОГ ДЕЙСТВИЙ КИБЕР-ПСА v.23"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 18
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
        maxLines = 10,
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
    label.TextSize = 14
    label.Font = Enum.Font.SourceSans
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ClipsDescendants = true
    table.insert(gui.lines, label)
    gui.logFrame.CanvasSize = UDim2.new(0, 0, 0, #gui.lines * 26)
    gui.logFrame.CanvasPosition = Vector2.new(0, gui.logFrame.CanvasSize.Y.Offset)
end

-- =====================================================
-- 7. ГЛАВНЫЙ ЦИКЛ
-- =====================================================
local spawnPos = findSpawn()
addLog("ГАВ! Спавн найден: " .. tostring(spawnPos))

local function startAI()
    addLog("ГАВ! Кибер-пёс v.23.0 (SMART) активирован!")
    addLog("ГАВ! ХОДИТ КАК ЧЕЛОВЕК, НЕ ЗАСТРЕВАЕТ!")

    while true do
        wait(CONFIG.THINK_INTERVAL)

        if not player.Character or not humanoid or humanoid.Health <= 0 then
            Memory.stuckTimer = 0
            if Memory.lastAction ~= "Ожидание респауна" then
                addLog("⏳ Ожидание респауна...")
                Memory.lastAction = "Ожидание респауна"
            end
            continue
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

        -- ===== УБИЙЦА =====
        if role == "Murderer" then
            if sheriff and sheriff.distance < CONFIG.ATTACK_DIST * 2 then
                if math.random() < CONFIG.DODGE_CHANCE then
                    dodgeFromSheriff(sheriff.pos)
                    addLog("💨 Уклонение от шерифа!")
                    Memory.lastAction = "Уклонение"
                end
            end

            if #targets > 0 then
                local target = targets[1]
                moveToTarget(target.pos)
                if target.distance <= CONFIG.ATTACK_DIST then
                    performAttack(target.pos)
                    Memory.killCount = Memory.killCount + 1
                    addLog("🔪 Убийца атакует " .. target.player.Name)
                    Memory.lastAction = "Атака"
                else
                    addLog("🏃 Убийца бежит к " .. target.player.Name)
                    Memory.lastAction = "Бег к цели"
                end
            else
                moveToTarget(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль" then
                    addLog("🔄 Убийца патрулирует")
                    Memory.lastAction = "Патруль"
                end
            end

        -- ===== ШЕРИФ =====
        elseif role == "Sheriff" then
            if murderer then
                moveToTarget(murderer.pos)
                if murderer.distance <= CONFIG.ATTACK_DIST then
                    local headPos = murderer.player.Character:FindFirstChild("Head")
                    if headPos then
                        local screenPos, onScreen = camera:WorldToScreenPoint(headPos.Position)
                        if onScreen then
                            virtualUser:CaptureController()
                            virtualUser:ClickButton2(Vector2.new(screenPos.X, screenPos.Y))
                            wait(0.05)
                        end
                    end
                    performAttack(murderer.pos)
                    addLog("🔫 Шериф застрелил убийцу!")
                    Memory.lastAction = "Убил убийцу"
                else
                    addLog("🏃 Шериф преследует убийцу")
                    Memory.lastAction = "Преследование"
                end
            else
                moveToTarget(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль (поиск)" then
                    addLog("🔄 Шериф ищет убийцу")
                    Memory.lastAction = "Патруль (поиск)"
                end
            end

        -- ===== НЕВИННЫЙ =====
        else
            if #coins > 0 then
                moveToTarget(coins[1].pos)
                if Memory.lastAction ~= "Сбор монет" then
                    addLog("🪙 Невинный собирает монеты")
                    Memory.lastAction = "Сбор монет"
                end
                Memory.coinCount = Memory.coinCount + 1
            else
                moveToTarget(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль" then
                    addLog("🔄 Невинный патрулирует")
                    Memory.lastAction = "Патруль"
                end
            end
        end

        if math.random(1, 30) == 1 then
            addLog("📊 Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
        end
    end
end

-- =====================================================
-- 8. ЗАПУСК
-- =====================================================
spawn(startAI)
addLog("ГАВ! MM2 CYBER-PSYCHE v.23.0 (SMART) загружена!")
addLog("ГАВ! БЕЗ ЗАСТРЕВАНИЙ И КРУГОВ!")
