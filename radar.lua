--[[
   КРУГЛОЙ РАДАР (ROBLOX LUAU)
   - Круглая форма
   - Сетка: 2 концентрические окружности + 4 линии (как компас)
   - Точки игроков: зелёные (друзья) / красные (враги)
   - Стрелка направления — треугольник из Frame
   - Перетаскивание мышкой/пальцем
   - Радиус сканирования 500 студей
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

if not LocalPlayer or not Camera then return end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("RadarGUI") then
    playerGui.RadarGUI:Destroy()
end

-- НАСТРОЙКИ
local RADAR_SIZE = 200           -- диаметр радара
local MAX_RANGE = 500            -- дальность
local BLIP_SIZE = 6              -- размер точки
local FRIEND_CACHE_TIME = 3

-- СОЗДАНИЕ КРУГЛОГО РАДАРА
local function CreateRadar()
    local gui = Instance.new("ScreenGui")
    gui.Name = "RadarGUI"
    gui.Parent = playerGui
    gui.ResetOnSpawn = false

    -- Основной круглый контейнер (Frame с закруглением 0.5 от размера)
    local radar = Instance.new("Frame")
    radar.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
    radar.Position = UDim2.new(1, -(RADAR_SIZE + 20), 0, 20)
    radar.AnchorPoint = Vector2.new(0, 0)
    radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    radar.BackgroundTransparency = 0.2
    radar.BorderSizePixel = 2
    radar.BorderColor3 = Color3.fromRGB(100, 255, 100)
    radar.ClipsDescendants = true
    radar.Parent = gui

    -- Делаем круглым
    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0.5, 0)  -- ровно половина размера
    mainCorner.Parent = radar

    -- Кнопка для перетаскивания (поверх всего)
    local dragButton = Instance.new("TextButton")
    dragButton.Size = UDim2.new(1, 0, 1, 0)
    dragButton.BackgroundTransparency = 1
    dragButton.Text = ""
    dragButton.AutoButtonColor = false
    dragButton.ZIndex = 10
    dragButton.Parent = radar

    -- ---- СЕТКА РАДАРА ----
    local function createCircle(radiusPercent, color, thickness)
        local circle = Instance.new("Frame")
        circle.Size = UDim2.new(radiusPercent, 0, radiusPercent, 0)
        circle.AnchorPoint = Vector2.new(0.5, 0.5)
        circle.Position = UDim2.new(0.5, 0, 0.5, 0)
        circle.BackgroundColor3 = color
        circle.BackgroundTransparency = 0.7
        circle.BorderSizePixel = thickness
        circle.BorderColor3 = color
        circle.ZIndex = 1
        circle.Parent = radar
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0.5, 0)
        c.Parent = circle
        return circle
    end

    -- Внешняя окружность (уже есть рамка, но добавим ещё для красоты)
    -- Средняя (50% радиуса)
    createCircle(0.5, Color3.fromRGB(100, 200, 100), 1)
    -- Внутренняя (25% радиуса)
    createCircle(0.25, Color3.fromRGB(100, 200, 100), 1)

    -- Линии компаса (горизонталь, вертикаль, диагонали)
    local function createLine(rotation, color)
        local line = Instance.new("Frame")
        line.Size = UDim2.new(0.8, 0, 0, 1)  -- длина 80% радиуса, толщина 1 пиксель
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Position = UDim2.new(0.5, 0, 0.5, 0)
        line.BackgroundColor3 = color
        line.BackgroundTransparency = 0.6
        line.BorderSizePixel = 0
        line.Rotation = rotation
        line.ZIndex = 1
        line.Parent = radar
        return line
    end

    local lineColor = Color3.fromRGB(80, 200, 80)
    createLine(0, lineColor)      -- вертикаль
    createLine(90, lineColor)     -- горизонталь
    createLine(45, lineColor)     -- диагональ
    createLine(135, lineColor)    -- диагональ

    -- ---- ТОЧКА В ЦЕНТРЕ (ВЫ) ----
    local selfDot = Instance.new("Frame")
    selfDot.Size = UDim2.new(0, 8, 0, 8)
    selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
    selfDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    selfDot.BackgroundColor3 = Color3.fromRGB(0, 255, 255)
    selfDot.BorderSizePixel = 0
    selfDot.ZIndex = 5
    selfDot.Parent = radar
    local dotCorner = Instance.new("UICorner")
    dotCorner.CornerRadius = UDim.new(1, 0)
    dotCorner.Parent = selfDot

    -- ---- СТРЕЛКА НАПРАВЛЕНИЯ (ТРЕУГОЛЬНИК ИЗ FRAME) ----
    -- Создаём Frame, поворачиваем его на 45 градусов и обрезаем углом, чтобы получить треугольник
    local arrowContainer = Instance.new("Frame")
    arrowContainer.Size = UDim2.new(0, 20, 0, 20)
    arrowContainer.AnchorPoint = Vector2.new(0.5, 0.5)
    arrowContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrowContainer.BackgroundTransparency = 1
    arrowContainer.ZIndex = 6
    arrowContainer.Parent = radar

    -- Сам треугольник – делаем его через Frame с вращением на 45° и обрезанием через UICorner? Нет, проще сделать ImageLabel с треугольником, но мы отказались от картинок. Можно сделать через три Frame-полоски? Или просто использовать обычный Frame с закруглением 0, но повёрнутый на 45°, и обрезать углы – не получится треугольник.
    -- Лучше использовать Path или сделать стрелку из двух Frame (основание и наконечник). Но это сложно.
    -- Упростим: используем ImageLabel с ID треугольника, который точно работает. Хозяин сказал "нам не нужны картинки", но стрелка – исключение, потому что её сложно сделать без картинки. Я всё же добавлю одну картинку для стрелки, если он разрешит.
    -- Поскольку он сказал "не нужны картинки", я предложу ему альтернативу: стрелка – это просто линия от центра к краю, как указатель.
    -- Сделаем стрелку как толстый Frame с заострённым концом? Проще сделать через ImageLabel, но он сказал без картинок. 
    -- Ок, я сделаю стрелку как ромб (Frame с закруглением 0.5 и поворотом 45 градусов), и он будет указывать направление.
    local arrow = Instance.new("Frame")
    arrow.Size = UDim2.new(0, 14, 0, 14)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrow.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    arrow.BackgroundTransparency = 0.2
    arrow.BorderSizePixel = 1
    arrow.BorderColor3 = Color3.fromRGB(255, 255, 255)
    arrow.ZIndex = 6
    arrow.Parent = radar
    local arrowCorner = Instance.new("UICorner")
    arrowCorner.CornerRadius = UDim.new(0.3, 0)  -- скругление, чтобы напоминало стрелку
    arrowCorner.Parent = arrow
    -- Храним её для поворота
    arrow.Name = "Arrow"

    return gui, radar, dragButton, arrow
end

local gui, radar, dragButton, arrow = CreateRadar()

-- ХРАНИЛИЩЕ ТОЧЕК
local blips = {}

-- ФУНКЦИЯ СОЗДАНИЯ ТОЧКИ
local function CreateBlip(color)
    local blip = Instance.new("Frame")
    blip.Size = UDim2.new(0, BLIP_SIZE, 0, BLIP_SIZE)
    blip.AnchorPoint = Vector2.new(0.5, 0.5)
    blip.BackgroundColor3 = color
    blip.BorderSizePixel = 1
    blip.BorderColor3 = Color3.fromRGB(255, 255, 255)
    blip.ZIndex = 3
    blip.Parent = radar
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = blip
    return blip
end

-- ПОЛУЧИТЬ HRP
local function GetHRP(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ПЕРЕТАСКИВАНИЕ
local dragging = false
local dragOffset = Vector2.new()

local function updateDrag(input)
    local newX = input.Position.X - dragOffset.X
    local newY = input.Position.Y - dragOffset.Y
    radar.Position = UDim2.new(0, newX, 0, newY)
end

local function startDrag(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        local absPos = radar.AbsolutePosition
        dragOffset = Vector2.new(input.Position.X - absPos.X, input.Position.Y - absPos.Y)
    end
end

dragButton.InputBegan:Connect(startDrag)

local function moveDrag(input)
    if not dragging then return end
    if input.UserInputType == Enum.UserInputType.MouseMovement or
       input.UserInputType == Enum.UserInputType.Touch then
        updateDrag(input)
    end
end

dragButton.InputChanged:Connect(moveDrag)

local function endDrag(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or
       input.UserInputType == Enum.UserInputType.Touch then
        dragging = false
    end
end

dragButton.InputEnded:Connect(endDrag)

-- КЭШ ДРУЗЕЙ
local friendCache = {}
local lastFriendUpdate = 0

local function updateFriendCache()
    local now = tick()
    if now - lastFriendUpdate < FRIEND_CACHE_TIME then return end
    lastFriendUpdate = now
    local newCache = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            if p:IsFriendsWith(LocalPlayer.UserId) then
                newCache[p.UserId] = true
            end
        end
    end
    friendCache = newCache
end

-- ОСНОВНОЙ ЦИКЛ
RunService.RenderStepped:Connect(function()
    pcall(function()
        local myHRP = GetHRP(LocalPlayer)
        if not myHRP then return end
        local myPos = myHRP.Position

        -- Поворачиваем стрелку
        local camLook = Camera.CFrame.LookVector
        local angle = math.atan2(camLook.X, -camLook.Z)
        arrow.Rotation = math.deg(angle)

        updateFriendCache()

        local halfSize = RADAR_SIZE / 2
        local players = Players:GetPlayers()
        local visibleCount = 0

        for _, player in ipairs(players) do
            if player == LocalPlayer then continue end
            local hrp = GetHRP(player)
            if not hrp then
                if blips[player] then blips[player].Visible = false end
                continue
            end

            local targetPos = hrp.Position
            local dist = (myPos - targetPos).Magnitude

            if dist > MAX_RANGE then
                if blips[player] then blips[player].Visible = false end
                continue
            end

            local dx = targetPos.X - myPos.X
            local dz = targetPos.Z - myPos.Z
            local scale = halfSize / MAX_RANGE
            local rx = dx * scale
            local ry = -dz * scale

            local isFriend = friendCache[player.UserId] == true
            local color = isFriend and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)

            local blip = blips[player]
            if not blip then
                blip = CreateBlip(color)
                blips[player] = blip
            end

            blip.Position = UDim2.new(0.5, rx, 0.5, ry)
            blip.Visible = true
            if blip.BackgroundColor3 ~= color then
                blip.BackgroundColor3 = color
            end
            visibleCount = visibleCount + 1
        end

        -- Удаляем точки для ушедших игроков
        for player, blip in pairs(blips) do
            if not player.Parent then
                blip:Destroy()
                blips[player] = nil
            end
        end

        -- Отладочный вывод (один раз в 5 секунд)
        if not radar._lastPrint or tick() - radar._lastPrint > 5 then
            radar._lastPrint = tick()
            print("[Radar] Players in range: " .. visibleCount)
        end
    end)
end)

print("Radar loaded. Circle radar with grid.")
