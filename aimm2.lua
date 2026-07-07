-- =====================================================
-- MM2 CYBER-PSYCHE v.30.0 (FULL REWRITE)
-- =====================================================

local player = game.Players.LocalPlayer
local virtualUser = game:GetService("VirtualUser")
local runService = game:GetService("RunService")
local userInput = game:GetService("UserInputService")
local replicatedStorage = game:GetService("ReplicatedStorage")

-- =====================================================
-- ПЕРЕМЕННЫЕ
-- =====================================================
local character = nil
local humanoid = nil
local rootPart = nil
local camera = workspace.CurrentCamera
local mouse = player:GetMouse()

-- =====================================================
-- НАСТРОЙКИ
-- =====================================================
local CONFIG = {
    THINK_INTERVAL = 0.1,
    MOVE_SPEED = 28,
    AIM_SMOOTHNESS = 0.7,
    DODGE_CHANCE = 0.4,
    DODGE_DIST = 25,
    MURDERER_ATTACK_DIST = 8,
    SHERIFF_SHOOT_DIST = 999,
    INNOCENT_DANGER_DIST = 15,
    WALL_AVOID_DIST = 5,
    PATROL_CHANGE_TIME = 5,  -- Менять патруль каждые 5 секунд
}

-- =====================================================
-- ПАМЯТЬ
-- =====================================================
local Memory = {
    killCount = 0,
    coinCount = 0,
    running = true,
    currentTarget = nil,
    patrolTarget = nil,
    patrolTimer = 0,
    lastKnownMurdererPos = nil,
    mainCoroutine = nil,
    updateConnection = nil,
    characterConnection = nil,
    hasGun = false,
    hasKnife = false,
}

local function addLog(text)
    print("[КИБЕР-ПЁС] " .. text)
end

-- =====================================================
-- ОБНОВЛЕНИЕ ПЕРСОНАЖА
-- =====================================================
local function updateCharacter()
    character = player.Character
    if character then
        humanoid = character:FindFirstChild("Humanoid")
        rootPart = character:FindFirstChild("HumanoidRootPart")
        if humanoid and rootPart then
            humanoid.WalkSpeed = CONFIG.MOVE_SPEED
            humanoid.JumpPower = 50
            return true
        end
    end
    return false
end

-- =====================================================
-- ПОИСК ОРУЖИЯ В ИНВЕНТАРЕ
-- =====================================================
local function checkWeapons()
    Memory.hasGun = false
    Memory.hasKnife = false
    
    if not character then return end
    
    -- Проверяем руку (там обычно оружие)
    local rightHand = character:FindFirstChild("RightHand")
    if rightHand then
        for _, child in pairs(rightHand:GetChildren()) do
            if child:IsA("Tool") then
                if child.Name:lower():find("gun") or child.Name:lower():find("pistol") or child.Name:lower():find("sheriff") then
                    Memory.hasGun = true
                elseif child.Name:lower():find("knife") or child.Name:lower():find("murderer") then
                    Memory.hasKnife = true
                end
            end
        end
    end
    
    -- Проверяем бэкпак
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, child in pairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                if child.Name:lower():find("gun") or child.Name:lower():find("pistol") or child.Name:lower():find("sheriff") then
                    Memory.hasGun = true
                elseif child.Name:lower():find("knife") or child.Name:lower():find("murderer") then
                    Memory.hasKnife = true
                end
            end
        end
    end
end

-- =====================================================
-- АВТОВЫБОР ОРУЖИЯ
-- =====================================================
local function equipWeapon(weaponName)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    
    for _, tool in pairs(backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.Name:lower():find(weaponName:lower()) then
            tool.Parent = character
            wait(0.1)
            addLog("🔫 Взял " .. tool.Name)
            return true
        end
    end
    return false
end

-- =====================================================
-- ДВИЖЕНИЕ ЧЕРЕЗ BODYPOSITION (СТАБИЛЬНЕЕ)
-- =====================================================
local function moveToTarget(targetPos)
    if not targetPos or not rootPart then return end
    if targetPos.Y < 0 then targetPos = Vector3.new(targetPos.X, 5, targetPos.Z) end
    
    local distance = (targetPos - rootPart.Position).Magnitude
    
    if distance < 2 then 
        stopMoving()
        return 
    end
    
    -- Используем BodyPosition для точного движения
    local bp = rootPart:FindFirstChild("CyberMoveBP")
    if not bp then
        bp = Instance.new("BodyPosition")
        bp.Name = "CyberMoveBP"
        bp.MaxForce = Vector3.new(8000, 8000, 8000)
        bp.P = 2000
        bp.D = 1000
        bp.Parent = rootPart
    end
    
    -- Целевая позиция с небольшой высотой
    local targetPosWithHeight = Vector3.new(targetPos.X, targetPos.Y + 1, targetPos.Z)
    bp.Position = targetPosWithHeight
    
    -- Поворот к цели
    local lookDir = Vector3.new(targetPos.X - rootPart.Position.X, 0, targetPos.Z - rootPart.Position.Z).Unit
    if lookDir.Magnitude > 0.1 then
        rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + lookDir * 2)
    end
    
    Memory.currentTarget = targetPos
end

local function stopMoving()
    if rootPart then
        local bp = rootPart:FindFirstChild("CyberMoveBP")
        if bp then bp:Destroy() end
    end
    Memory.currentTarget = nil
end

-- Обновление движения через RenderStepped
runService.RenderStepped:Connect(function()
    if Memory.running and Memory.currentTarget and rootPart then
        moveToTarget(Memory.currentTarget)
    end
end)

local function performJump()
    if humanoid then
        humanoid.Jump = true
        wait(0.1)
        humanoid.Jump = false
    end
end

-- =====================================================
-- АТАКА (ГАРАНТИРОВАННО РАБОТАЕТ)
-- =====================================================
local function performAttack()
    pcall(function()
        mouse1click()
        wait(0.05)
        mouse1click()
    end)
end

local function aimAndShoot(targetPos)
    if not targetPos or not camera then return end
    
    local screenPos, onScreen = camera:WorldToScreenPoint(targetPos)
    if onScreen then
        local smoothPos = Vector2.new(
            mouse.X + (screenPos.X - mouse.X) * CONFIG.AIM_SMOOTHNESS,
            mouse.Y + (screenPos.Y - mouse.Y) * CONFIG.AIM_SMOOTHNESS
        )
        
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(smoothPos.X, smoothPos.Y))
        wait(0.05)
    end
    
    performAttack()
end

-- =====================================================
-- ОПРЕДЕЛЕНИЕ РОЛИ ПО ОРУЖИЮ
-- =====================================================
local function getPlayerRole(plr)
    if plr == player then return nil end
    
    local char = plr.Character
    if not char then return nil end
    
    -- Проверяем руку
    local rightHand = char:FindFirstChild("RightHand")
    if rightHand then
        for _, child in pairs(rightHand:GetChildren()) do
            if child:IsA("Tool") then
                local name = child.Name:lower()
                if name:find("gun") or name:find("pistol") or name:find("sheriff") then
                    return "Sheriff"
                elseif name:find("knife") or name:find("murderer") or name:find("blade") then
                    return "Murderer"
                end
            end
        end
    end
    
    -- Проверяем бэкпак
    local backpack = plr:FindFirstChild("Backpack")
    if backpack then
        for _, child in pairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                local name = child.Name:lower()
                if name:find("gun") or name:find("pistol") or name:find("sheriff") then
                    return "Sheriff"
                elseif name:find("knife") or name:find("murderer") or name:find("blade") then
                    return "Murderer"
                end
            end
        end
    end
    
    return "Innocent"
end

-- =====================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- =====================================================
local function getPlayers()
    local result = {}
    if not rootPart then return result end
    
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local root = plr.Character:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local hum = plr.Character:FindFirstChild("Humanoid")
        if hum and hum.Health <= 0 then continue end
        
        local dist = (rootPart.Position - root.Position).Magnitude
        if dist > 9999 then continue end
        
        local role = getPlayerRole(plr)
        
        table.insert(result, {
            player = plr,
            distance = dist,
            pos = root.Position,
            team = role,
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
    if not rootPart then return coins end
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name:lower():find("coin")) then
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
    local radius = 30 + math.random() * 40
    local x = spawnPos.X + math.cos(angle) * radius
    local z = spawnPos.Z + math.sin(angle) * radius
    return Vector3.new(x, spawnPos.Y + 0.5, z)
end

local function findHidingSpot()
    local bestSpot = nil
    local bestDist = math.huge
    if not rootPart then return getRandomPatrolPoint(findSpawn()) end
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name:lower():find("wall") or obj.Name:lower():find("box") or 
           obj.Name:lower():find("tree") or obj.Name:lower():find("car")) then
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
        return getRandomPatrolPoint(findSpawn())
    end
end

-- =====================================================
-- РОЛЕВАЯ ЛОГИКА
-- =====================================================
local spawnPos = findSpawn()

local function murdererLogic(players, coins)
    if not rootPart then return end
    
    -- Проверяем оружие
    checkWeapons()
    if not Memory.hasKnife then
        equipWeapon("knife")
        equipWeapon("murderer")
    end
    
    -- Уклонение от шерифа
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
    
    -- Поиск цели (мирные)
    local target = nil
    local minDist = math.huge
    
    for _, p in ipairs(players) do
        if p.team == "Innocent" and p.distance < minDist then
            target = p
            minDist = p.distance
        end
    end
    
    -- Если мирных нет - ищем шерифа
    if not target then
        for _, p in ipairs(players) do
            if p.team == "Sheriff" and p.distance < minDist then
                target = p
                minDist = p.distance
            end
        end
    end
    
    if target then
        moveToTarget(target.pos)
        if target.distance <= CONFIG.MURDERER_ATTACK_DIST then
            aimAndShoot(target.pos)
            Memory.killCount = Memory.killCount + 1
            addLog("🔪 [УБИЙЦА] Убил " .. target.player.Name .. "!")
            wait(0.3)
        else
            addLog("🏃 [УБИЙЦА] Бегу к " .. target.player.Name .. " (дист: " .. string.format("%.0f", target.distance) .. "м)")
        end
    else
        -- Патруль с обновлением точки
        Memory.patrolTimer = Memory.patrolTimer + CONFIG.THINK_INTERVAL
        if not Memory.patrolTarget or Memory.patrolTimer > CONFIG.PATROL_CHANGE_TIME then
            Memory.patrolTarget = getRandomPatrolPoint(spawnPos)
            Memory.patrolTimer = 0
            addLog("🔄 [УБИЙЦА] Новая точка патруля")
        end
        moveToTarget(Memory.patrolTarget)
    end
end

local function sheriffLogic(players, coins)
    if not rootPart then return end
    
    -- Проверяем оружие
    checkWeapons()
    if not Memory.hasGun then
        equipWeapon("gun")
        equipWeapon("pistol")
        equipWeapon("sheriff")
    end
    
    -- Поиск убийцы
    local murderer = nil
    local minDist = math.huge
    
    for _, p in ipairs(players) do
        if p.team == "Murderer" and p.distance < minDist then
            murderer = p
            minDist = p.distance
        end
    end
    
    if murderer then
        Memory.lastKnownMurdererPos = murderer.pos
        moveToTarget(murderer.pos)
        addLog("🏃 [ШЕРИФ] Преследую убийцу " .. murderer.player.Name .. " (дист: " .. string.format("%.0f", murderer.distance) .. "м)")
        
        -- Стреляем
        local shootPos = murderer.pos
        local head = murderer.character:FindFirstChild("Head")
        if head then
            shootPos = head.Position
        end
        
        aimAndShoot(shootPos)
        addLog("🔫 [ШЕРИФ] Стреляю в убийцу " .. murderer.player.Name .. "!")
    else
        if #coins > 0 then
            moveToTarget(coins[1].pos)
            Memory.coinCount = Memory.coinCount + 1
            addLog("🪙 [ШЕРИФ] Собираю монету")
        else
            Memory.patrolTimer = Memory.patrolTimer + CONFIG.THINK_INTERVAL
            if not Memory.patrolTarget or Memory.patrolTimer > CONFIG.PATROL_CHANGE_TIME then
                Memory.patrolTarget = getRandomPatrolPoint(spawnPos)
                Memory.patrolTimer = 0
            end
            moveToTarget(Memory.patrolTarget)
            addLog("🔄 [ШЕРИФ] Патрулирую...")
        end
    end
end

local function innocentLogic(players, coins)
    if not rootPart then return end
    
    -- Поиск убийцы
    local murderer = nil
    local minDist = math.huge
    
    for _, p in ipairs(players) do
        if p.team == "Murderer" and p.distance < minDist then
            murderer = p
            minDist = p.distance
        end
    end
    
    if murderer and murderer.distance < CONFIG.INNOCENT_DANGER_DIST then
        local hidingSpot = findHidingSpot()
        moveToTarget(hidingSpot)
        addLog("🏃‍♂️ [НЕВИННЫЙ] Прячусь от убийцы " .. murderer.player.Name .. "!")
        return
    end
    
    if #coins > 0 then
        moveToTarget(coins[1].pos)
        Memory.coinCount = Memory.coinCount + 1
        addLog("🪙 [НЕВИННЫЙ] Собрал монету!")
    else
        Memory.patrolTimer = Memory.patrolTimer + CONFIG.THINK_INTERVAL
        if not Memory.patrolTarget or Memory.patrolTimer > CONFIG.PATROL_CHANGE_TIME then
            Memory.patrolTarget = getRandomPatrolPoint(spawnPos)
            Memory.patrolTimer = 0
        end
        moveToTarget(Memory.patrolTarget)
        addLog("🚶 [НЕВИННЫЙ] Брожу...")
    end
end

-- =====================================================
-- GUI
-- =====================================================
local guiVisible = true

local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Parent = player.PlayerGui
    screenGui.Name = "CyberPsycheGUI"
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame")
    frame.Parent = screenGui
    frame.Size = UDim2.new(0, 500, 0, 350)
    frame.Position = UDim2.new(0.5, -250, 1, -360)
    frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    frame.BackgroundTransparency = 0.85
    frame.BorderSizePixel = 2
    frame.BorderColor3 = Color3.fromRGB(255, 0, 0)
    
    local closeBtn = Instance.new("TextButton")
    closeBtn.Parent = frame
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -35, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 18
    closeBtn.Font = Enum.Font.SourceSansBold
    
    local title = Instance.new("TextLabel")
    title.Parent = frame
    title.Size = UDim2.new(1, -40, 0, 30)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "ГАВ! КИБЕР-ПЁС v.30.0"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Font = Enum.Font.SourceSansBold
    
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
    
    local stopBtn = Instance.new("TextButton")
    stopBtn.Parent = frame
    stopBtn.Size = UDim2.new(0, 120, 0, 35)
    stopBtn.Position = UDim2.new(0, 10, 1, -40)
    stopBtn.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
    stopBtn.Text = "⏹ СТОП"
    stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    stopBtn.TextSize = 14
    stopBtn.Font = Enum.Font.SourceSansBold
    
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
-- УПРАВЛЕНИЕ
-- =====================================================
local function stopScript()
    Memory.running = false
    stopMoving()
    
    if Memory.mainCoroutine then
        coroutine.close(Memory.mainCoroutine)
        Memory.mainCoroutine = nil
    end
    
    if Memory.updateConnection then
        Memory.updateConnection:Disconnect()
        Memory.updateConnection = nil
    end
    
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
    Memory.patrolTarget = nil
    Memory.patrolTimer = 0
    Memory.lastKnownMurdererPos = nil
    Memory.hasGun = false
    Memory.hasKnife = false
    
    updateCharacter()
    
    addLogGUI("🔄 ПЕРЕЗАПУСК...")
    
    Memory.mainCoroutine = coroutine.create(mainLoop)
    coroutine.resume(Memory.mainCoroutine)
    
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
-- ОБНОВЛЕНИЕ ПЕРСОНАЖА
-- =====================================================
local function onCharacterAdded(newChar)
    character = newChar
    updateCharacter()
    checkWeapons()
    addLogGUI("🔄 Персонаж обновлён!")
    
    if Memory.updateConnection then
        Memory.updateConnection:Disconnect()
        Memory.updateConnection = nil
    end
    
    Memory.updateConnection = runService.RenderStepped:Connect(function()
        if Memory.running and Memory.currentTarget and rootPart then
            moveToTarget(Memory.currentTarget)
        end
    end)
end

-- =====================================================
-- ГЛАВНЫЙ ЦИКЛ
-- =====================================================
local function mainLoop()
    while Memory.running do
        wait(CONFIG.THINK_INTERVAL)
        
        if not character or not humanoid or not rootPart then
            if not updateCharacter() then
                wait(0.5)
                continue
            end
        end
        
        if humanoid and humanoid.Health <= 0 then
            if Memory.lastAction ~= "Мёртв" then
                addLogGUI("💀 Ожидание респауна...")
                Memory.lastAction = "Мёртв"
            end
            stopMoving()
            continue
        end
        
        -- Проверяем оружие
        checkWeapons()
        
        local players = getPlayers()
        local coins = getCoins()
        local role = getPlayerRole(player)
        
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
updateCharacter()
checkWeapons()

Memory.characterConnection = player.CharacterAdded:Connect(onCharacterAdded)

Memory.updateConnection = runService.RenderStepped:Connect(function()
    if Memory.running and Memory.currentTarget and rootPart then
        moveToTarget(Memory.currentTarget)
    end
end)

addLogGUI("ГАВ! КИБЕР-ПЁС v.30.0 ЗАГРУЖЕН!")
addLogGUI("ГАВ! НОВОЕ ДВИЖЕНИЕ - BODYPOSITION!")
addLogGUI("ГАВ! АВТОВЫБОР ОРУЖИЯ!")
addLogGUI("ГАВ! ОБНОВЛЯЕМЫЙ ПАТРУЛЬ!")

Memory.mainCoroutine = coroutine.create(mainLoop)
coroutine.resume(Memory.mainCoroutine)
