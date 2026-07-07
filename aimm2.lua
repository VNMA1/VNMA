-- =====================================================
-- MM2 CYBER-PSYCHE v.14.0 (GUI LOG EDITION)
-- С логом действий в правом углу. ГАВ!
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local virtualUser = game:GetService("VirtualUser")

-- =====================================================
-- 1. GUI ДЛЯ ЛОГА
-- =====================================================
local function createLogGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheLog"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 250, 0, 180)
    frame.Position = UDim2.new(1, -260, 0, 10)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.6
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)

    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, 0, 0, 20)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! ЛОГ ДЕЙСТВИЙ"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 12
    title.Font = Enum.Font.SourceSansBold

    local logFrame = Instance.new("ScrollingFrame")
    logFrame.Parent = frame
    logFrame.Size = UDim2.new(1, -10, 1, -30)
    logFrame.Position = UDim2.new(0, 5, 0, 25)
    logFrame.BackgroundTransparency = 1
    logFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    logFrame.ScrollBarThickness = 4

    local layout = Instance.new("UIListLayout")
    layout.Parent = logFrame
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)

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

-- =====================================================
-- 2. ФУНКЦИЯ ДОБАВЛЕНИЯ ЛОГА
-- =====================================================
local function addLog(text)
    if #gui.lines >= gui.maxLines then
        local oldLine = table.remove(gui.lines, 1)
        oldLine:Destroy()
    end

    local label = Instance.new("TextLabel")
    label.Parent = gui.logFrame
    label.Size = UDim2.new(1, 0, 0, 16)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 11
    label.Font = Enum.Font.SourceSans
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.ClipsDescendants = true

    table.insert(gui.lines, label)
    gui.logFrame.CanvasSize = UDim2.new(0, 0, 0, #gui.lines * 18)
    gui.logFrame.CanvasPosition = Vector2.new(0, gui.logFrame.CanvasSize.Y.Offset)
end

-- =====================================================
-- 3. НАСТРОЙКИ
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.3,
    ATTACK_DIST = 15,
    MAX_VIEW_DIST = 100,
    PATROL_RADIUS = 25,
    SMOOTH_FACTOR = 0.2,
}

local Memory = {
    patrolAngle = 0,
    killCount = 0,
    coinCount = 0,
    lastAction = "",
}

-- =====================================================
-- 4. ФУНКЦИИ
-- =====================================================
local function findSpawn()
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("SpawnLocation") or obj.Name == "Spawn" then
            return obj.Position
        end
    end
    return Vector3.new(0, 5, 0)
end

local function getPatrolPoint(spawnPos)
    Memory.patrolAngle = Memory.patrolAngle + 0.15
    local radius = CONFIG.PATROL_RADIUS
    local x = spawnPos.X + math.cos(Memory.patrolAngle) * radius
    local z = spawnPos.Z + math.sin(Memory.patrolAngle) * radius
    return Vector3.new(x, spawnPos.Y, z)
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

local function smoothMove(targetPos)
    if not targetPos then return end
    local current = rootPart.Position
    local direction = (targetPos - current).Unit
    local step = direction * CONFIG.SMOOTH_FACTOR
    local newPos = current + step
    rootPart.CFrame = CFrame.new(newPos + Vector3.new(0, 2, 0))
end

local function performAttack()
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end

-- =====================================================
-- 5. ГЛАВНЫЙ ЦИКЛ С ЛОГОМ
-- =====================================================
local spawnPos = findSpawn()
addLog("ГАВ! Спавн найден!")

local function startAI()
    addLog("ГАВ! Кибер-пёс v.14.0 активирован!")

    while true do
        wait(CONFIG.THINK_INTERVAL)

        if not player.Character or not humanoid or humanoid.Health <= 0 then
            if Memory.lastAction ~= "Ожидание респауна" then
                addLog("Ожидание респауна...")
                Memory.lastAction = "Ожидание респауна"
            end
            continue
        end

        local role = player.Team and player.Team.Name or "Innocent"
        local targets = getTargets()
        local coins = getCoins()

        local murderer = nil
        for _, t in ipairs(targets) do
            if t.team == "Murderer" then
                murderer = t
                break
            end
        end

        -- ===== УБИЙЦА =====
        if role == "Murderer" then
            if #targets > 0 then
                local target = targets[1]
                smoothMove(target.pos)
                local distText = string.format("%.1f", target.distance)
                if target.distance <= CONFIG.ATTACK_DIST then
                    performAttack()
                    Memory.killCount = Memory.killCount + 1
                    addLog("🔪 Убийца атакует " .. target.player.Name .. " (" .. distText .. "м)")
                    Memory.lastAction = "Атака"
                else
                    addLog("🏃 Убийца бежит к " .. target.player.Name .. " (" .. distText .. "м)")
                    Memory.lastAction = "Бег к цели"
                end
            else
                smoothMove(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль" then
                    addLog("🔄 Убийца патрулирует спавн")
                    Memory.lastAction = "Патруль"
                end
            end

        -- ===== ШЕРИФ =====
        elseif role == "Sheriff" then
            if murderer then
                smoothMove(murderer.pos)
                if murderer.distance <= CONFIG.ATTACK_DIST then
                    performAttack()
                    addLog("🔫 Шериф стреляет в убийцу (" .. string.format("%.1f", murderer.distance) .. "м)")
                    Memory.lastAction = "Стрельба"
                else
                    addLog("🏃 Шериф преследует убийцу (" .. string.format("%.1f", murderer.distance) .. "м)")
                    Memory.lastAction = "Преследование"
                end
            elseif #coins > 0 then
                smoothMove(coins[1].pos)
                if Memory.lastAction ~= "Сбор монет" then
                    addLog("🪙 Шериф собирает монеты (" .. #coins .. " рядом)")
                    Memory.lastAction = "Сбор монет"
                end
                Memory.coinCount = Memory.coinCount + 1
            else
                smoothMove(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль" then
                    addLog("🔄 Шериф патрулирует спавн")
                    Memory.lastAction = "Патруль"
                end
            end

        -- ===== НЕВИННЫЙ =====
        else
            if murderer and murderer.distance < CONFIG.ATTACK_DIST then
                local escapeDir = (rootPart.Position - murderer.pos).Unit
                local zigzag = Vector3.new(math.random(-10,10), 0, math.random(-10,10))
                local newPos = rootPart.Position + escapeDir * 20 + zigzag
                smoothMove(newPos)
                addLog("😱 Невинный убегает от убийцы!")
                Memory.lastAction = "Бегство"
            elseif #coins > 0 then
                smoothMove(coins[1].pos)
                if Memory.lastAction ~= "Сбор монет" then
                    addLog("🪙 Невинный собирает монеты (" .. #coins .. " рядом)")
                    Memory.lastAction = "Сбор монет"
                end
                Memory.coinCount = Memory.coinCount + 1
            else
                smoothMove(getPatrolPoint(spawnPos))
                if Memory.lastAction ~= "Патруль" then
                    addLog("🔄 Невинный патрулирует спавн")
                    Memory.lastAction = "Патруль"
                end
            end
        end

        -- Статистика
        if math.random(1, 30) == 1 then
            addLog("📊 Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
        end
    end
end

-- =====================================================
-- 6. ЗАПУСК
-- =====================================================
spawn(startAI)
addLog("ГАВ! MM2 CYBER-PSYCHE v.14.0 загружена!")
addLog("ГАВ! ВСЁ РАБОТАЕТ, ХОЗЯЙКА!")
