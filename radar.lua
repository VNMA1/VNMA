--[[
   КВАДРАТНЫЙ РАДАР С КНОПКАМИ УПРАВЛЕНИЯ
   - Чёрный фон, сетка
   - Перетаскивание мышкой/пальцем
   - Друзья — зелёные, враги — красные
   - Кнопки: X (закрыть), R (перезапустить)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

if not LocalPlayer or not Camera then return end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Удаляем старый радар, если есть
local function destroyOldRadar()
    local old = playerGui:FindFirstChild("RadarGUI")
    if old then old:Destroy() end
end
destroyOldRadar()

-- НАСТРОЙКИ
local RADAR_SIZE = 180
local MAX_RANGE = 500
local BLIP_SIZE = 6
local FRIEND_CACHE_TIME = 3

-- Переменные для хранения объектов
local gui, radar, dragButton, arrow
local blips = {}
local friendCache = {}
local lastFriendUpdate = 0

-- ФУНКЦИЯ СОЗДАНИЯ РАДАРА (возвращает объекты)
local function CreateRadar()
    gui = Instance.new("ScreenGui")
    gui.Name = "RadarGUI"
    gui.Parent = playerGui
    gui.ResetOnSpawn = false

    radar = Instance.new("Frame")
    radar.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
    radar.Position = UDim2.new(1, -(RADAR_SIZE + 20), 0, 20)
    radar.AnchorPoint = Vector2.new(0, 0)
    radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    radar.BackgroundTransparency = 0.3
    radar.BorderSizePixel = 1
    radar.BorderColor3 = Color3.fromRGB(200, 200, 200)
    radar.ClipsDescendants = true
    radar.Parent = gui

    -- Кнопка для перетаскивания
    dragButton = Instance.new("TextButton")
    dragButton.Size = UDim2.new(1, 0, 1, 0)
    dragButton.BackgroundTransparency = 1
    dragButton.Text = ""
    dragButton.AutoButtonColor = false
    dragButton.ZIndex = 10
    dragButton.Parent = radar

    -- ---- СЕТКА (линии) ----
    local function createLine(rotation, color, sizeX, sizeY, posX, posY)
        local line = Instance.new("Frame")
        line.Size = UDim2.new(sizeX, 0, sizeY, 0)
        line.AnchorPoint = Vector2.new(0.5, 0.5)
        line.Position = UDim2.new(posX, 0, posY, 0)
        line.BackgroundColor3 = color
        line.BackgroundTransparency = 0.5
        line.BorderSizePixel = 0
        line.Rotation = rotation
        line.ZIndex = 1
        line.Parent = radar
        return line
    end

    local lineColor = Color3.fromRGB(150, 150, 150)

    for y = 0.25, 0.75, 0.25 do
        createLine(0, lineColor, 0.9, 0.005, 0.5, y)
    end
    for x = 0.25, 0.75, 0.25 do
        createLine(0, lineColor, 0.005, 0.9, x, 0.5)
    end

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

    -- ---- СТРЕЛКА (треугольник) ----
    arrow = Instance.new("ImageLabel")
    arrow.Size = UDim2.new(0, 20, 0, 20)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrow.BackgroundTransparency = 1
    arrow.Image = "rbxassetid://6031094979"  -- рабочая стрелка
    arrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
    arrow.ZIndex = 6
    arrow.Parent = radar
    arrow.Name = "Arrow"

    -- ---- НИЖНЯЯ ПАНЕЛЬ С ТЕКСТОМ И КНОПКАМИ ----
    local bottomPanel = Instance.new("Frame")
    bottomPanel.Size = UDim2.new(0, RADAR_SIZE, 0, 30)
    bottomPanel.Position = UDim2.new(0, 0, 1, 5)
    bottomPanel.BackgroundTransparency = 1
    bottomPanel.Parent = radar

    -- Текст
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.6, 0, 1, 0)
    label.Position = UDim2.new(0, 0, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = "TGK: VNMA0"
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 14
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = bottomPanel

    -- Кнопка "Закрыть" (красный X)
    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0.2, 0, 1, 0)
    closeBtn.Position = UDim2.new(0.6, 0, 0, 0)
    closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeBtn.Text = "X"
    closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    closeBtn.TextSize = 16
    closeBtn.Font = Enum.Font.SourceSansBold
    closeBtn.BorderSizePixel = 1
    closeBtn.BorderColor3 = Color3.fromRGB(150, 0, 0)
    closeBtn.Parent = bottomPanel

    -- Кнопка "Перезапуск" (зелёная R)
    local restartBtn = Instance.new("TextButton")
    restartBtn.Size = UDim2.new(0.2, 0, 1, 0)
    restartBtn.Position = UDim2.new(0.8, 0, 0, 0)
    restartBtn.BackgroundColor3 = Color3.fromRGB(50, 150, 50)
    restartBtn.Text = "R"
    restartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    restartBtn.TextSize = 16
    restartBtn.Font = Enum.Font.SourceSansBold
    restartBtn.BorderSizePixel = 1
    restartBtn.BorderColor3 = Color3.fromRGB(0, 100, 0)
    restartBtn.Parent = bottomPanel

    -- ---- ПЕРЕТАСКИВАНИЕ (внутри функции, чтобы замыкать radar) ----
    local dragging = false
    local dragOffset = Vector2.new()

    local function updateDrag(input)
        if not radar then return end
        local newX = input.Position.X - dragOffset.X
        local newY = input.Position.Y - dragOffset.Y
        radar.Position = UDim2.new(0, newX, 0, newY)
    end

    local function startDrag(input)
        if not radar then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            local absPos = radar.AbsolutePosition
            dragOffset = Vector2.new(input.Position.X - absPos.X, input.Position.Y - absPos.Y)
        end
    end

    dragButton.InputBegan:Connect(startDrag)

    dragButton.InputChanged:Connect(function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement or
           input.UserInputType == Enum.UserInputType.Touch then
            updateDrag(input)
        end
    end)

    dragButton.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or
           input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    -- ---- ОБРАБОТЧИКИ КНОПОК ----
    closeBtn.MouseButton1Click:Connect(function()
        if gui then gui:Destroy() end
        for _, blip in pairs(blips) do
            blip:Destroy()
        end
        table.clear(blips)
        friendCache = {}
        lastFriendUpdate = 0
        print("Radar closed.")
    end)

    restartBtn.MouseButton1Click:Connect(function()
        if gui then gui:Destroy() end
        for _, blip in pairs(blips) do
            blip:Destroy()
        end
        table.clear(blips)
        friendCache = {}
        lastFriendUpdate = 0
        CreateRadar()
        print("Radar restarted.")
    end)

    return gui, radar, dragButton, arrow
end

-- ИНИЦИАЛИЗАЦИЯ
CreateRadar()

-- ФУНКЦИЯ ДЛЯ ПОЛУЧЕНИЯ HRP
local function GetHRP(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-- ---- ОСНОВНОЙ ЦИКЛ (обновление радара) ----
RunService.RenderStepped:Connect(function()
    pcall(function()
        local myHRP = GetHRP(LocalPlayer)
        if not myHRP then return end
        local myPos = myHRP.Position

        -- Поворачиваем стрелку
        local camLook = Camera.CFrame.LookVector
        local angle = math.atan2(camLook.X, -camLook.Z)
        if arrow then
            arrow.Rotation = math.deg(angle)
        end

        -- Обновляем кэш друзей (раз в FRIEND_CACHE_TIME секунд)
        local now = tick()
        if now - lastFriendUpdate >= FRIEND_CACHE_TIME then
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

        local halfSize = RADAR_SIZE / 2
        local players = Players:GetPlayers()

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
                blip = Instance.new("Frame")
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
                blips[player] = blip
            end

            blip.Position = UDim2.new(0.5, rx, 0.5, ry)
            blip.Visible = true
            if blip.BackgroundColor3 ~= color then
                blip.BackgroundColor3 = color
            end
        end

        -- Удаляем точки для ушедших игроков
        for player, blip in pairs(blips) do
            if not player.Parent then
                blip:Destroy()
                blips[player] = nil
            end
        end
    end)
end)

print("Radar loaded. Use X to close, R to restart.")
