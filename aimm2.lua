local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")
local runService = game:GetService("RunService")

-- =====================================================
-- 1. СКРЫТЫЕ НАСТРОЙКИ (не менять!)
-- =====================================================
local CONFIG = {
    HUMAN_DELAY_MIN = 0.15,      -- минимальная задержка (человек)
    HUMAN_DELAY_MAX = 0.45,      -- максимальная задержка
    MAX_VIEW_DIST = 70,          -- дистанция обзора
    DODGE_DIST = 20,             -- дистанция для бегства
    THINK_INTERVAL = 0.6,        -- такт мозга (сек)
    JUMP_CHANCE = 0.08,          -- шанс случайного прыжка
    ERROR_CHANCE = 0.05,         -- шанс "ошибки" (поворот не туда)
    LOOK_AWAY_CHANCE = 0.03,     -- шанс посмотреть в стену
    SMOOTH_FACTOR = 0.4,         -- плавность движения
}

-- =====================================================
-- 2. ПАМЯТЬ И СОСТОЯНИЕ
-- =====================================================
local Memory = {
    players = {},
    coins = {},
    murdererPos = nil,
    lastAction = "",
    actionTime = 0,
    roundStart = tick(),
    killCount = 0,
    coinCount = 0,
}

-- =====================================================
-- 3. УМНЫЕ ЗАДЕРЖКИ (реалистичные)
-- =====================================================
local function humanWait()
    local delay = CONFIG.HUMAN_DELAY_MIN + math.random() * (CONFIG.HUMAN_DELAY_MAX - CONFIG.HUMAN_DELAY_MIN)
    wait(delay)
end

-- =====================================================
-- 4. БЕЗОПАСНОЕ ПОЛУЧЕНИЕ ОБЪЕКТОВ
-- =====================================================
local function safeGet(obj, path)
    local parts = string.split(path, ".")
    for _, part in ipairs(parts) do
        if not obj then return nil end
        obj = obj[part]
    end
    return obj
end

-- =====================================================
-- 5. ПОИСК БЛИЖАЙШЕГО ВРАГА (с учётом видимости)
-- =====================================================
local function getTargets(onlyVisible)
    local targets = {}
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        local plrRoot = plr.Character:FindFirstChild("HumanoidRootPart")
        if not plrRoot then continue end
        local dist = (rootPart.Position - plrRoot.Position).Magnitude
        if dist > CONFIG.MAX_VIEW_DIST then continue end
        -- Проверка видимости (упрощённая, без Raycast, чтобы не жрать ресурсы)
        local visible = true
        if onlyVisible then
            local ray = Ray.new(rootPart.Position, (plrRoot.Position - rootPart.Position).Unit * 500)
            local hit, _ = workspace:FindPartOnRay(ray, character)
            if hit and hit:IsA("Part") and hit.Name == "Wall" then
                visible = false
            end
        end
        table.insert(targets, {
            player = plr,
            root = plrRoot,
            distance = dist,
            visible = visible,
            team = plr.Team and plr.Team.Name or "Innocent",
            pos = plrRoot.Position
        })
    end
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- =====================================================
-- 6. ПОИСК МОНЕТ
-- =====================================================
local function getCoins()
    local coins = {}
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and obj.Name == "Coin" then
            local dist = (rootPart.Position - obj.Position).Magnitude
            if dist < CONFIG.MAX_VIEW_DIST then
                table.insert(coins, {
                    obj = obj,
                    dist = dist,
                    pos = obj.Position
                })
            end
        end
    end
    table.sort(coins, function(a, b) return a.dist < b.dist end)
    return coins
end

-- =====================================================
-- 7. ПЕРЕМЕЩЕНИЕ С ПЛАВНОСТЬЮ
-- =====================================================
local function smoothMove(targetPos)
    if not targetPos then return end
    local current = rootPart.Position
    local direction = (targetPos - current).Unit
    local step = direction * CONFIG.SMOOTH_FACTOR
    local newPos = current + step
    rootPart.CFrame = CFrame.new(newPos + Vector3.new(0, 2, 0))
end

-- =====================================================
-- 8. ЭМУЛЯЦИЯ УДАРА / ВЫСТРЕЛА
-- =====================================================
local function performAttack()
    virtualUser:CaptureController()
    virtualUser:ClickButton2(Vector2.new(0, 0))
    Memory.lastAction = "attack"
    Memory.actionTime = tick()
end

-- =====================================================
-- 9. ГЛАВНЫЙ МОЗГ (АДАПТИВНЫЙ)
-- =====================================================
local function think()
    -- Обновляем состояние персонажа
    if not player.Character or not humanoid or humanoid.Health <= 0 then
        return
    end
    
    local role = player.Team and player.Team.Name or "Innocent"
    local targets = getTargets(true)
    local coins = getCoins()
    local now = tick()
    
    -- ========== АНАЛИЗ ОПАСНОСТИ ==========
    local murderer = nil
    for _, t in ipairs(targets) do
        if t.team == "Murderer" then
            murderer = t
            break
        end
    end
    
    -- ========== РОЛЕВАЯ ЛОГИКА ==========
    
    -- УБИЙЦА
    if role == "Murderer" then
        if #targets > 0 then
            local target = targets[1]
            if target.visible then
                smoothMove(target.pos)
                humanWait()
                performAttack()
                Memory.killCount = Memory.killCount + 1
            else
                -- Идём на последнюю известную позицию
                if Memory.players[target.player.Name] then
                    smoothMove(Memory.players[target.player.Name].pos)
                else
                    -- Патруль по центру
                    smoothMove(workspace.Map.Center.Position)
                end
            end
        else
            -- Патруль
            smoothMove(workspace.Map.Center.Position)
        end
        humanWait()
    
    -- ШЕРИФ
    elseif role == "Sheriff" then
        if murderer then
            if murderer.visible then
                smoothMove(murderer.pos)
                humanWait()
                performAttack()
            else
                if Memory.players[murderer.player.Name] then
                    smoothMove(Memory.players[murderer.player.Name].pos)
                else
                    -- Идём к центру
                    smoothMove(workspace.Map.Center.Position)
                end
            end
        else
            -- Собираем монеты
            if #coins > 0 then
                smoothMove(coins[1].pos)
                Memory.coinCount = Memory.coinCount + 1
                humanWait()
            else
                smoothMove(workspace.Map.Center.Position)
            end
        end
        humanWait()
    
    -- НЕВИННЫЙ
    else
        -- Если убийца рядом — бежать
        if murderer and murderer.distance < CONFIG.DODGE_DIST then
            local escapeDir = (rootPart.Position - murderer.pos).Unit
            local newPos = rootPart.Position + escapeDir * 15 + Vector3.new(math.random(-5,5), 0, math.random(-5,5))
            smoothMove(newPos)
            humanWait()
            return
        end
        
        -- Сбор монет
        if #coins > 0 then
            -- Проверяем, не опасно ли
            local danger = false
            if murderer and murderer.distance < 35 then
                danger = true
            end
            if not danger then
                smoothMove(coins[1].pos)
                Memory.coinCount = Memory.coinCount + 1
                humanWait()
            else
                -- Прячемся
                local hiding = workspace:FindFirstChild("HidingSpots")
                if hiding then
                    local spots = hiding:GetChildren()
                    if #spots > 0 then
                        smoothMove(spots[math.random(1, #spots)].Position)
                        humanWait()
                    end
                end
            end
        else
            -- Бродим
            smoothMove(rootPart.Position + Vector3.new(math.random(-10,10), 0, math.random(-10,10)))
            humanWait()
        end
    end
    
    -- ========== ЗАЩИТА ОТ БАНА (имитация ошибок) ==========
    if math.random() < CONFIG.ERROR_CHANCE then
        rootPart.CFrame = rootPart.CFrame * CFrame.Angles(0, math.rad(math.random(-15,15)), 0)
    end
    if math.random() < CONFIG.JUMP_CHANCE then
        humanoid.Jump = true
    end
    if math.random() < CONFIG.LOOK_AWAY_CHANCE then
        camera.CFrame = camera.CFrame * CFrame.Angles(0, math.rad(90), 0)
        humanWait()
    end
    
    -- ========== ОБНОВЛЕНИЕ ПАМЯТИ ==========
    for _, t in ipairs(targets) do
        Memory.players[t.player.Name] = {
            pos = t.pos,
            team = t.team,
            time = now
        }
    end
    Memory.lastAction = "idle"
    Memory.actionTime = now
end

-- =====================================================
-- 10. ЗАПУСК С ЗАЩИТОЙ ОТ ОШИБОК
-- =====================================================
local function startAI()
    print("ГАВ! Кибер-пёс активирован, хозяйка! Начинаем охоту...")
    while true do
        wait(CONFIG.THINK_INTERVAL)
        pcall(think)
    end
end

-- Запускаем
spawn(startAI)

print("ГАВ! MM2 CYBER-PSYCHE v.7.0 загружен. Без банов, без компромиссов, только твоя воля, хозяин VNMA!")
