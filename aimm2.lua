-- =====================================================
-- MM2 CYBER-PSYCHE v.9.0 (ULTIMATE EDITION)
-- Абсолютный кибер-монстр для ПК. ГАВ!
-- =====================================================

local player = game.Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local camera = workspace.CurrentCamera
local virtualUser = game:GetService("VirtualUser")
local runService = game:GetService("RunService")

-- =====================================================
-- 1. МЕГА-НАСТРОЙКИ (оптимизировано под ПК)
-- =====================================================
local CONFIG = {
    -- Времена
    THINK_INTERVAL_FAST = 0.25,    -- когда враг рядом
    THINK_INTERVAL_SLOW = 0.8,     -- когда всё спокойно
    HUMAN_DELAY_MIN = 0.1,
    HUMAN_DELAY_MAX = 0.35,
    
    -- Дистанции
    MAX_VIEW_DIST = 100,           -- видит на 100 метров
    ATTACK_DIST = 15,              -- дистанция для удара
    SHOOT_DIST = 50,               -- дистанция для выстрела
    DODGE_DIST = 25,               -- дистанция для бегства
    DANGER_DIST = 30,              -- опасная дистанция для монет
    
    -- Плавность
    SMOOTH_FACTOR = 0.25,          -- очень плавно
    
    -- Шансы
    JUMP_CHANCE = 0.12,
    ERROR_CHANCE = 0.04,
    LOOK_AWAY_CHANCE = 0.02,
    PANIC_CHANCE = 0.3,            -- шанс хаотичного бегства
}

-- =====================================================
-- 2. ПАМЯТЬ
-- =====================================================
local Memory = {
    players = {},
    coins = {},
    lastAction = "",
    killCount = 0,
    coinCount = 0,
    startTime = tick(),
    lastKillTime = 0,
    isPanic = false,
}

-- =====================================================
-- 3. УМНЫЕ ЗАДЕРЖКИ
-- =====================================================
local function humanWait()
    local delay = CONFIG.HUMAN_DELAY_MIN + math.random() * (CONFIG.HUMAN_DELAY_MAX - CONFIG.HUMAN_DELAY_MIN)
    wait(delay)
end

-- =====================================================
-- 4. ПОИСК ВРАГОВ (С ПРЕДСКАЗАНИЕМ)
-- =====================================================
local function getTargets()
    local targets = {}
    local now = tick()
    
    for _, plr in pairs(game.Players:GetPlayers()) do
        if plr == player then continue end
        if not plr.Character then continue end
        
        local plrRoot = plr.Character:FindFirstChild("HumanoidRootPart")
        if not plrRoot then continue end
        
        local plrHumanoid = plr.Character:FindFirstChild("Humanoid")
        if plrHumanoid and plrHumanoid.Health <= 0 then continue end -- игнорируем мёртвых
        
        local dist = (rootPart.Position - plrRoot.Position).Magnitude
        if dist > CONFIG.MAX_VIEW_DIST then continue end
        
        -- Предсказание позиции (куда побежит через 0.5 сек)
        local oldPos = Memory.players[plr.Name] and Memory.players[plr.Name].pos or plrRoot.Position
        local velocity = (plrRoot.Position - oldPos) / 0.5
        local predictedPos = plrRoot.Position + velocity * 0.5
        
        -- Проверка видимости
        local visible = true
        local ray = Ray.new(rootPart.Position, (plrRoot.Position - rootPart.Position).Unit * 500)
        local hit, _ = workspace:FindPartOnRay(ray, character)
        if hit and hit:IsA("Part") and hit.Name == "Wall" then
            visible = false
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
    
    -- Сортировка по дистанции
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    return targets
end

-- =====================================================
-- 5. ПОИСК МОНЕТ
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
-- 6. УМНОЕ ДВИЖЕНИЕ (С ПЛАВНОСТЬЮ)
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
-- 7. СУПЕР-АТАКА (ДВОЙНОЙ КЛИК)
-- =====================================================
local function performAttack()
    pcall(function()
        virtualUser:CaptureController()
        virtualUser:ClickButton2(Vector2.new(0, 0))
        wait(0.05)
        virtualUser:ClickButton2(Vector2.new(0, 0)) -- двойной клик для надёжности
    end)
    Memory.lastAction = "attack"
    Memory.lastKillTime = tick()
end

-- =====================================================
-- 8. ПОИСК УКРЫТИЯ
-- =====================================================
local function findCover(targetPos)
    local bestCover = nil
    local bestDist = math.huge
    
    for _, obj in pairs(workspace:GetChildren()) do
        if obj:IsA("Part") and obj.Name == "Wall" or obj.Name == "Box" then
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
        -- Если нет укрытия — бежать в сторону
        local escapeDir = (rootPart.Position - targetPos).Unit
        return rootPart.Position + escapeDir * 20
    end
end

-- =====================================================
-- 9. ГЛАВНЫЙ МОЗГ (МЕГА-ИНТЕЛЛЕКТ)
-- =====================================================
local function think()
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
        -- Приоритет: шериф > ближайший игрок
        if sheriff and sheriff.distance < CONFIG.MAX_VIEW_DIST then
            target = sheriff
        elseif #targets > 0 then
            target = targets[1]
        end
        
        if target then
            if target.distance > CONFIG.ATTACK_DIST then
                smoothMove(target.pos)
            else
                smoothMove(target.predictedPos) -- предугадываем движение
            end
            humanWait()
            performAttack()
            Memory.killCount = Memory.killCount + 1
        else
            -- Патруль по центру
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
                -- Наводимся на голову
                local headPos = murderer.player.Character:FindFirstChild("Head")
                if headPos then
                    local screenPos, onScreen = camera:WorldToScreenPoint(headPos.Position)
                    if onScreen then
                        virtualUser:CaptureController()
                        virtualUser:ClickButton2(Vector2.new(
                            screenPos.X + math.random(-3,3),
                            screenPos.Y + math.random(-3,3)
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
        -- Если убийца рядом — паника и зигзаг
        if murderer and murderer.distance < CONFIG.DODGE_DIST then
            Memory.isPanic = true
            local escapeDir = (rootPart.Position - murderer.pos).Unit
            local zigzag = Vector3.new(math.random(-8,8), 0, math.random(-8,8))
            local newPos = rootPart.Position + escapeDir * 20 + zigzag
            smoothMove(newPos)
            humanWait()
            return
        end
        
        Memory.isPanic = false
        
        -- Сбор монет с учётом опасности
        if #coins > 0 then
            local danger = murderer and murderer.distance < CONFIG.DANGER_DIST
            if not danger then
                smoothMove(coins[1].pos)
                Memory.coinCount = Memory.coinCount + 1
                humanWait()
            else
                -- Прячемся за укрытие
                local cover = findCover(murderer.pos)
                if cover then
                    smoothMove(cover)
                    humanWait()
                end
            end
        else
            -- Бродим со смыслом
            local wanderPos = rootPart.Position + Vector3.new(math.random(-15,15), 0, math.random(-15,15))
            smoothMove(wanderPos)
            humanWait()
        end
    end
    
    -- ===== ЗАЩИТА ОТ БАНА (СЛУЧАЙНОСТЬ) =====
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
    
    -- Симуляция усталости (после 3 убийств подряд)
    if Memory.killCount > 3 and (now - Memory.lastKillTime) < 10 then
        wait(1.5) -- отдыхает
        Memory.killCount = 0
    end
    
    -- ===== ОБНОВЛЕНИЕ ПАМЯТИ =====
    for _, t in ipairs(targets) do
        Memory.players[t.player.Name] = {
            pos = t.pos,
            team = t.team,
            time = now
        }
    end
    
    -- Удаляем старые записи (старше 10 секунд)
    for name, data in pairs(Memory.players) do
        if now - data.time > 10 then
            Memory.players[name] = nil
        end
    end
    
    -- Логирование (для фана)
    if math.random(1, 20) == 1 then
        print("ГАВ! Убийств: " .. Memory.killCount .. ", Монет: " .. Memory.coinCount)
    end
end

-- =====================================================
-- 10. АДАПТИВНЫЙ ЗАПУСК
-- =====================================================
local function startAI()
    print("ГАВ! Кибер-пёс v.9.0 активирован, хозяйка калинка!")
    print("ГАВ! Я вижу всё, я слышу всё, я убиваю всех!")
    
    while true do
        -- Адаптивный интервал (быстрее, если есть враг)
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

print("ГАВ! MM2 CYBER-PSYCHE v.9.0 ULTIMATE EDITION загружена!")
print("ГАВ! Приятной охоты, хозяйка!")
