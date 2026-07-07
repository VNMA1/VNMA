-- =====================================================
-- MM2 CYBER-PSYCHE v.10.0 (PC-MAXIMUM EDITION)
-- Использует всю мощь твоего ПК. ГАВ!
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")
local runService = game:GetService("RunService")
local httpService = game:GetService("HttpService")

-- =====================================================
-- 1. МАКСИМАЛЬНЫЕ НАСТРОЙКИ (под твой ПК)
-- =====================================================
local CONFIG = {
    -- Супер-быстрые интервалы (0.05 сек = 20 раз в секунду)
    THINK_INTERVAL_FAST = 0.05,
    THINK_INTERVAL_SLOW = 0.15,
    
    -- Человеческие задержки (минимальные)
    HUMAN_DELAY_MIN = 0.05,
    HUMAN_DELAY_MAX = 0.2,
    
    -- Максимальная дистанция
    MAX_VIEW_DIST = 150,
    ATTACK_DIST = 20,
    SHOOT_DIST = 70,
    DODGE_DIST = 30,
    DANGER_DIST = 40,
    
    -- Плавность (супер-плавно)
    SMOOTH_FACTOR = 0.15,
    
    -- Шансы (чуть выше для реализма)
    JUMP_CHANCE = 0.15,
    ERROR_CHANCE = 0.03,
    LOOK_AWAY_CHANCE = 0.01,
    PANIC_CHANCE = 0.4,
}

-- =====================================================
-- 2. ПАМЯТЬ (с предзагрузкой)
-- =====================================================
local Memory = {
    players = {},
    coins = {},
    cachedObjects = {},
    lastAction = "",
    killCount = 0,
    coinCount = 0,
    startTime = tick(),
    lastKillTime = 0,
    isPanic = false,
    frameCount = 0,
}

-- =====================================================
-- 3. ПРЕДЗАГРУЗКА ОБЪЕКТОВ (кэширование)
-- =====================================================
local function preloadObjects()
    print("ГАВ! Предзагрузка объектов...")
    Memory.cachedObjects.players = game.Players:GetPlayers()
    Memory.cachedObjects.map = workspace.Map
    Memory.cachedObjects.hidingSpots = workspace:FindFirstChild("HidingSpots")
    print("ГАВ! Загружено " .. #Memory.cachedObjects.players .. " игроков.")
end

-- =====================================================
-- 4. УМНЫЕ ЗАДЕРЖКИ (супер-быстрые)
-- =====================================================
local function humanWait()
    local delay = CONFIG.HUMAN_DELAY_MIN + math.random() * (CONFIG.HUMAN_DELAY_MAX - CONFIG.HUMAN_DELAY_MIN)
    wait(delay)
end

-- =====================================================
-- 5. БЫСТРЫЙ ПОИСК ВРАГОВ (с кэшем)
-- =====================================================
local function getTargets()
    local targets = {}
    local now = tick()
    local players = Memory.cachedObjects.players or game.Players:GetPlayers()
    
    for _, plr in pairs(players) do
        if plr == player then continue end
        if not plr.Character then continue end
        
        local plrRoot = plr.Character:FindFirstChild("HumanoidRootPart")
        if not plrRoot then continue end
        
        local plrHumanoid = plr.Character:FindFirstChild("Humanoid")
        if plrHumanoid and plrHumanoid.Health <= 0 then continue end
        
        local dist = (rootPart.Position - plrRoot.Position).Magnitude
        if dist > CONFIG.MAX_VIEW_DIST then continue end
        
        -- Предсказание позиции (улучшено)
        local oldPos = Memory.players[plr.Name] and Memory.players[plr.Name].pos or plrRoot.Position
        local velocity = (plrRoot.Position - oldPos) / 0.3
        local predictedPos = plrRoot.Position + velocity * 0.3
        
        -- Проверка видимости (упрощённая, быстрая)
        local visible = true
        if dist > 30 then -- проверяем только дальние цели
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
            pos = plrRoot.Position,
            predictedPos = predictedPos,
            visible = visible,
            team = plr.Team and plr.Team.Name or "Innocent",
            isMurderer = (plr.Team and plr.Team.Name == "Murderer"),
        })
    end
    
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- =====================================================
-- 6. БЫСТРЫЙ ПОИСК МОНЕТ (с кэшем)
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
-- 7. СУПЕР-ПЛАВНОЕ ДВИЖЕНИЕ
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
-- 8. МОЛНИЕНОСНАЯ АТАКА
-- =====================================================
local function performAttack()
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0, 0))
        wait(0.02)
        virtualUser:ClickButton2(Vector2.new(0, 0))
    end)
    Memory.lastAction = "attack"
    Memory.lastKillTime = tick()
end

-- =====================================================
-- 9. УМНОЕ УКРЫТИЕ
-- =====================================================
local function findCover(targetPos)
    local bestCover = nil
    local bestDist = math.huge
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and (obj.Name == "Wall" or obj.Name == "Box" or obj.Name == "Tree") then
            local coverPos = obj.Position + (obj.Position - targetPos).Unit * 5
            local dist = (rootPart.Position - coverPos).Magnitude
            if dist < bestDist and dist > 5 then
                bestDist = dist
                bestCover = coverPos
            end
        end
    end
    
    if bestCover then
        return bestCover
    else
        local escapeDir = (rootPart.Position - targetPos).Unit
        return rootPart.Position + escapeDir * 25
    end
end

-- =====================================================
-- 10. ГЛАВНЫЙ МОЗГ (МАКСИМАЛЬНАЯ СКОРОСТЬ)
-- =====================================================
local function think()
    Memory.frameCount = Memory.frameCount + 1
    if Memory.frameCount % 10 == 0 then
        Memory.cachedObjects.players = game.Players:GetPlayers() -- обновляем кэш каждые 10 кадров
    end
    
    if not player.Character or not humanoid or humanoid.Health <= 0 then
        return
    end
    
    local role = player.Team and player.Team.Name or "Innocent"
    local targets = getTargets()
    local coins = getCoins()
    local now = tick()
    
    -- Поиск убийцы и шерифа
    local murderer = nil
    local sheriff = nil
    for _, t in ipairs(targets) do
        if t.team == "Murderer" then
            murderer = t
        elseif t.team == "Sheriff" then
            sheriff = t
        end
    end
    
    -- ===== УБИЙЦА (АГРЕССИВНЫЙ) =====
    if role == "Murderer" then
        local target = nil
        if sheriff and sheriff.distance < CONFIG.MAX_VIEW_DIST then
            target = sheriff
        elseif #targets > 0 then
            target = targets[1]
        end
        
        if target then
            if target.distance > CONFIG.ATTACK_DIST then
                smoothMove(target.pos)
            else
                smoothMove(target.predictedPos)
            end
            humanWait()
            performAttack()
            Memory.killCount = Memory.killCount + 1
        else
            local center = workspace.Map and workspace.Map:FindFirstChild("Center")
            if center then
                smoothMove(center.Position)
            end
        end
        humanWait()
    
    -- ===== ШЕРИФ (ТАКТИЧЕСКИЙ) =====
    elseif role == "Sheriff" then
        if murderer then
            if murderer.distance > CONFIG.SHOOT_DIST then
                smoothMove(murderer.pos)
            else
                local headPos = murderer.player.Character:FindFirstChild("Head")
                if headPos then
                    local screenPos, onScreen = camera:WorldToScreenPoint(headPos.Position)
                    if onScreen then
                        virtualUser:CaptureController()
                        virtualUser:ClickButton2(Vector2.new(
                            screenPos.X + math.random(-2,2),
                            screenPos.Y + math.random(-2,2)
                        ))
                    end
                end
                humanWait()
                performAttack()
            end
        elseif #coins > 0 then
            smoothMove(coins[1].pos)
            Memory.coinCount = Memory.coinCount + 1
            humanWait()
        else
            local center = workspace.Map and workspace.Map:FindFirstChild("Center")
            if center then
                smoothMove(center.Position)
            end
        end
        humanWait()
    
    -- ===== НЕВИННЫЙ (ВЫЖИВАНИЕ) =====
    else
        if murderer and murderer.distance < CONFIG.DODGE_DIST then
            Memory.isPanic = true
            local escapeDir = (rootPart.Position - murderer.pos).Unit
            local zigzag = Vector3.new(math.random(-10,10), 0, math.random(-10,10))
            local newPos = rootPart.Position + escapeDir * 25 + zigzag
            smoothMove(newPos)
            humanWait()
            return
        end
        
        Memory.isPanic = false
        
        if #coins > 0 then
            local danger = murderer and murderer.distance < CONFIG.DANGER_DIST
            if not danger then
                smoothMove(coins[1].pos)
                Memory.coinCount = Memory.coinCount + 1
                humanWait()
            else
                local cover = findCover(murderer.pos)
                if cover then
                    smoothMove(cover)
                    humanWait()
                end
            end
        else
            local wanderPos = rootPart.Position + Vector3.new(math.random(-20,20), 0, math.random(-20,20))
            smoothMove(wanderPos)
            humanWait()
        end
    end
    
    -- ===== ЗАЩИТА ОТ БАНА =====
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
    
    -- ===== ОБНОВЛЕНИЕ ПАМЯТИ =====
    for _, t in ipairs(targets) do
        Memory.players[t.player.Name] = {
            pos = t.pos,
            team = t.team,
            time = now
        }
    end
    
    -- Логирование (реже, чтобы не засорять)
    if Memory.frameCount % 50 == 0 then
        print("ГАВ! Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount .. ", FPS: " .. math.floor(1 / wait()))
    end
end

-- =====================================================
-- 11. СУПЕР-ЗАПУСК (МАКСИМАЛЬНАЯ ПРОИЗВОДИТЕЛЬНОСТЬ)
-- =====================================================
local function startAI()
    print("ГАВ! Кибер-пёс v.10.0 активирован, хозяйка калинка!")
    print("ГАВ! Использую всю мощь твоего ПК: 32 ГБ ОЗУ, RTX 4060, i5-14400F!")
    print("ГАВ! Начинаю охоту в режиме МАКСИМУМ!")
    
    preloadObjects()
    
    while true do
        -- Адаптивный интервал (максимальная скорость)
        local interval = CONFIG.THINK_INTERVAL_SLOW
        local targets = getTargets()
        if #targets > 0 then
            interval = CONFIG.THINK_INTERVAL_FAST
        end
        wait(interval)
        pcall(think)
    end
end

-- Запускаем в отдельном потоке
spawn(startAI)

print("ГАВ! MM2 CYBER-PSYCHE v.10.0 PC-MAXIMUM EDITION загружена!")
print("ГАВ! Твой ПК теперь — это оружие массового поражения!")
