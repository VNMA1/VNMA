-- =====================================================
-- MM2 CYBER-PSYCHE v.28.1 (WASD FIXED)
-- ИСПРАВЛЕНА ЭМУЛЯЦИЯ WASD! ГАВ!
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
-- 1. НАСТРОЙКИ
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.1,
    MOVE_SPEED = 16,
    AIM_SMOOTHNESS = 0.6,
    DODGE_CHANCE = 0.5,
    DODGE_DIST = 25,
    MURDERER_ATTACK_DIST = 12,
    SHERIFF_SHOOT_DIST = 999,
    INNOCENT_DANGER_DIST = 18,
    RADAR_RADIUS = 2,
    RADAR_ANGLES = 8,
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    killCount = 0,
    coinCount = 0,
    lastAction = "",
    lastRadarUpdate = 0,
    safeDir = Vector3.new(1, 0, 0),
    lastTarget = nil,
    lastWASD = {W=false, A=false, S=false, D=false},
}

-- =====================================================
-- 3. ЛОГ
-- =====================================================
local function addLog(text)
    print("[КИБЕР-ПЁС] " .. text)
end

-- =====================================================
-- 4. РАДАР
-- =====================================================
local function getSafeDirection()
    local now = tick()
    if now - Memory.lastRadarUpdate < 0.3 then return Memory.safeDir end
    Memory.lastRadarUpdate = now
    
    local origin = rootPart.Position
    local blocked = {}
    
    for i = 0, CONFIG.RADAR_ANGLES - 1 do
        local angle = (i / CONFIG.RADAR_ANGLES) * 2 * math.pi
        local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        
        local params = RaycastParams.new()
        params.FilterDescendantsInstances = {character}
        params.FilterType = Enum.RaycastFilterType.Blacklist
        
        local result = workspace:Raycast(origin, dir * CONFIG.RADAR_RADIUS, params)
        if result then blocked[dir] = true end
    end
    
    local bestDir = Memory.safeDir
    local bestScore = -math.huge
    
    for i = 0, CONFIG.RADAR_ANGLES - 1 do
        local angle = (i / CONFIG.RADAR_ANGLES) * 2 * math.pi
        local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
        if not blocked[dir] then
            local score = dir:Dot(Memory.safeDir)
            if score > bestScore then
                bestScore = score
                bestDir = dir
            end
        end
    end
    
    Memory.safeDir = bestDir
    return bestDir
end

-- =====================================================
-- 5. НОВАЯ СИСТЕМА WASD (БЕЗ ЗАЛИПАНИЙ)
-- =====================================================
local function resetKeys()
    userInput:SetKeyUp(Enum.KeyCode.W)
    userInput:SetKeyUp(Enum.KeyCode.A)
    userInput:SetKeyUp(Enum.KeyCode.S)
    userInput:SetKeyUp(Enum.KeyCode.D)
    Memory.lastWASD = {W=false, A=false, S=false, D=false}
end

local function moveWithWASD(direction)
    if not direction or direction.Magnitude < 0.1 then
        resetKeys()
        return
    end
    
    local forward = direction.Z
    local right = direction.X
    
    -- Сбрасываем все клавиши перед новым нажатием
    resetKeys()
    wait(0.01)
    
    -- Нажимаем только нужные клавиши
    if forward > 0.3 then
        userInput:SetKeyDown(Enum.KeyCode.W)
        Memory.lastWASD.W = true
    elseif forward < -0.3 then
        userInput:SetKeyDown(Enum.KeyCode.S)
        Memory.lastWASD.S = true
    end
    
    if right > 0.3 then
        userInput:SetKeyDown(Enum.KeyCode.D)
        Memory.lastWASD.D = true
    elseif right < -0.3 then
        userInput:SetKeyDown(Enum.KeyCode.A)
        Memory.lastWASD.A = true
    end
end

-- =====================================================
-- 6. ЭМУЛЯЦИЯ МЫШИ И ПРОБЕЛА
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

local function performJump()
    pcall(function()
        userInput:SetKeyDown(Enum.KeyCode.Space)
        wait(0.05)
        userInput:SetKeyUp(Enum.KeyCode.Space)
    end)
end

-- =====================================================
-- 7. УМНОЕ ДВИЖЕНИЕ
-- =====================================================
local function smartMove(targetPos, actionName)
    if not targetPos then return end
    if targetPos.Y < 0 then targetPos = Vector3.new(targetPos.X, 5, targetPos.Z) end
    
    local currentPos = rootPart.Position
    local dist = (currentPos - targetPos).Magnitude
    
    -- Лог
    if Memory.lastTarget ~= targetPos then
        Memory.lastTarget = targetPos
        addLog("🚶 Иду к " .. actionName .. " (дист: " .. string.format("%.0f", dist) .. "м)")
    end
    
    -- Если цель рядом — сбрасываем клавиши
    if dist < 3 then
        resetKeys()
        humanoid.WalkSpeed = CONFIG.MOVE_SPEED
        return
    end
    
    -- Направление к цели
    local toTarget = (targetPos - currentPos).Unit
    local safeDir = getSafeDirection()
    
    -- Смешиваем направления
    local mixFactor = math.min(dist / 10, 1)
    local finalDir = (toTarget * mixFactor + safeDir * (1 - mixFactor)).Unit
    
    if dist < 5 then
        finalDir = toTarget
    end
    
    -- Двигаемся через WASD
    moveWithWASD(finalDir)
    
    -- Поворачиваемся к цели
    if toTarget.Magnitude > 0.1 then
        rootPart.CFrame = CFrame.new(rootPart.Position, rootPart.Position + toTarget)
    end
    
    -- Если все направления заблокированы — прыгаем
    if safeDir.Magnitude < 0.1 then
        performJump()
        addLog("🔄 ПРЫЖОК! ВСЕ НАПРАВЛЕНИЯ ЗАБЛОКИРОВАНЫ!")
    end
    
    humanoid.WalkSpeed = CONFIG.MOVE_SPEED
end

-- =====================================================
-- 8. ОСТАЛЬНЫЕ ФУНКЦИИ (БЕЗ ИЗМЕНЕНИЙ)
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
            if dist < 100 then
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

-- =====================================================
-- 9. РОЛЕВАЯ ЛОГИКА
-- =====================================================
local spawnPos = findSpawn()

local function murdererLogic(players, coins)
    local sheriff = nil
    for _, p in ipairs(players) do
        if p.team == "Sheriff" and p.distance < 30 then
            sheriff = p
            break
        end
    end
    
    if sheriff then
        if math.random() < CONFIG.DODGE_CHANCE then
            local escapeDir = (rootPart.Position - sheriff.pos).Unit
            local newPos = rootPart.Position + escapeDir * CONFIG.DODGE_DIST + Vector3.new(math.random(-10,10), 0, math.random(-10,10))
            smartMove(newPos, "укрытию от шерифа")
            performJump()
            addLog("💨 [УБИЙЦА] Уклоняюсь от шерифа!")
            return
        end
    end
    
    local target = nil
    for _, p in ipairs(players) do
        if p.team ~= "Murderer" then
            target = p
            break
        end
    end
    
    if target then
        smartMove(target.pos, target.player.Name .. " (убийца)")
        if target.distance <= CONFIG.MURDERER_ATTACK_DIST then
            performAttack(target.pos)
            Memory.killCount = Memory.killCount + 1
            addLog("🔪 [УБИЙЦА] Убил " .. target.player.Name .. "!")
        else
            addLog("🏃 [УБИЙЦА] Бегу к " .. target.player.Name .. " (дист: " .. string.format("%.0f", target.distance) .. "м)")
        end
    else
        smartMove(getRandomPatrolPoint(spawnPos), "патрулю")
        addLog("🔄 [УБИЙЦА] Патрулирую...")
    end
end

local function sheriffLogic(players, coins)
    local murderer = nil
    for _, p in ipairs(players) do
        if p.team == "Murderer" then
            murderer = p
            break
        end
    end
    
    if murderer then
        smartMove(murderer.pos, murderer.player.Name .. " (убийца)")
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
        if #coins > 0 then
            smartMove(coins[1].pos, "монете")
            Memory.coinCount = Memory.coinCount + 1
            addLog("🪙 [ШЕРИФ] Собираю монету")
        else
            smartMove(getRandomPatrolPoint(spawnPos), "патрулю")
            addLog("🔄 [ШЕРИФ] Патрулирую в поисках убийцы...")
        end
    end
end

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
        smartMove(hidingSpot, "укрытию")
        addLog("🏃‍♂️ [НЕВИННЫЙ] Прячусь от убийцы " .. murderer.player.Name .. "!")
        return
    end
    
    if #coins > 0 then
        smartMove(coins[1].pos, "монете")
        Memory.coinCount = Memory.coinCount + 1
        addLog("🪙 [НЕВИННЫЙ] Собрал монету!")
    else
        smartMove(getRandomPatrolPoint(spawnPos), "патрулю")
        addLog("🚶 [НЕВИННЫЙ] Брожу...")
    end
end

-- =====================================================
-- 10. GUI ЛОГА
-- =====================================================
local function createLogGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheLog"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 500, 0, 300)
    frame.Position = UDim2.new(0.5, -250, 1, -310)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)

    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! КИБЕР-ПЁС v.28.1 (WASD FIXED)"
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
        maxLines = 15,
        lines = {}
    }
end

local gui = createLogGUI()

local originalAddLog = addLog
addLog = function(text)
    originalAddLog(text)
    
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
-- 11. ГЛАВНЫЙ ЦИКЛ
-- =====================================================
addLog("ГАВ! Спавн найден!")

local function startAI()
    addLog("ГАВ! Кибер-пёс v.28.1 активирован!")
    addLog("ГАВ! WASD ИСПРАВЛЕН — НЕ ЗАЛИПАЕТ!")
    
    while true do
        wait(CONFIG.THINK_INTERVAL)
        
        if not player.Character or not humanoid or humanoid.Health <= 0 then
            resetKeys() -- Сбрасываем клавиши при смерти
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
addLog("ГАВ! MM2 CYBER-PSYCHE v.28.1 загружена!")
addLog("ГАВ! ТЕПЕРЬ ХОДИТ БЕЗ ЗАЛИПАНИЙ!")
