--[[
   КВАДРАТНЫЙ РАДАР С СЕТКОЙ И СЕКТОРОМ ОБЗОРА (ИСПРАВЛЕННЫЙ)
   - Чёрный фон, круги и линии сетки
   - Перетаскивание мышкой/пальцем
   - Друзья — зелёные, враги — красные
   - Сектор из трёх линий показывает направление камеры
   - Дальность 1000 студей
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
local RADAR_SIZE = 200
local MAX_RANGE = 1000
local BLIP_SIZE = 4
local FRIEND_CACHE_TIME = 3
local SECTOR_ANGLE = 30              -- градусы отклонения боковых линий
local LINE_LENGTH = 0.35             -- длина линий относительно радиуса

-- Переменные
local gui, radar, dragButton, sectorContainer
local blips = {}
local friendCache = {}
local lastFriendUpdate = 0

-- ФУНКЦИЯ СОЗДАНИЯ РАДАРА
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
    radar.BackgroundTransparency = 0.2
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

    -- ---- СЕТКА (окружности) ----
    local function createCircle(radiusPercent, color, thickness)
        local circle = Instance.new("Frame")
        circle.Size = UDim2.new(radiusPercent, 0, radiusPercent, 0)
        circle.AnchorPoint = Vector2.new(0.5, 0.5)
        circle.Position = UDim2.new(0.5, 0, 0.5, 0)
        circle.BackgroundTransparency = 1
        circle.BorderSizePixel = thickness
        circle.BorderColor3 = color
        circle.ZIndex = 1
        circle.Parent = radar
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0.5, 0)
        corner.Parent = circle
        return circle
    end

    local gridColor = Color3.fromRGB(100, 150, 200)
    createCircle(0.5, gridColor, 1)   -- средняя окружность (50% радиуса)
    createCircle(0.25, gridColor, 1)  -- внутренняя окружность (25% радиуса)

    -- ---- ЛИНИИ СЕТКИ (горизонталь, вертикаль, диагонали) ----
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

    local lineColor = Color3.fromRGB(80, 120, 180)
    createLine(0, lineColor, 0.8, 0.008, 0.5, 0.5)    -- вертикаль
    createLine(90, lineColor, 0.8, 0.008, 0.5, 0.5)   -- горизонталь
    createLine(45, lineColor, 0.7, 0.006, 0.5, 0.5)   -- диагональ
    createLine(135, lineColor, 0.7, 0.006, 0.5, 0.5)  -- диагональ

    -- ---- СЕКТОР ОБЗОРА (три линии) ----
    sectorContainer = Instance.new("Frame")
    sectorContainer.Size = UDim2.new(1, 0, 1, 0)
    sectorContainer.AnchorPoint = Vector2.new(0.5, 0.5)
    sectorContainer.Position = UDim2.new(0.5, 0, 0.5, 0)
    sectorContainer.BackgroundTransparency = 1
    sectorContainer.ClipsDescendants = false
    sectorContainer.ZIndex = 4
    sectorContainer.Parent = radar

    local function createSectorLine(rotation, length, color, thickness)
        local line = Instance.new("Frame")
        line.Size = UDim2.new(0, 0, length, thickness)
        line.AnchorPoint = Vector2.new(0.5, 0)
        line.Position = UDim2.new(0.5, 0, 0.5, 0)
        line.BackgroundColor3 = color
        line.BackgroundTransparency = 0.3
        line.BorderSizePixel = 0
        line.Rotation = rotation
        line.ZIndex = 4
        line.Parent = sectorContainer
        return line
    end

    local sectorColor = Color3.fromRGB(180, 200, 255)
    createSectorLine(0, LINE_LENGTH, sectorColor, 2)                -- центр
    createSectorLine(-SECTOR_ANGLE, LINE_LENGTH * 0.85, sectorColor, 2) -- лево
    createSectorLine(SECTOR_ANGLE, LINE_LENGTH * 0.85, sectorColor, 2)  -- право

    -- ---- ТЕКСТ ПОД РАДАРОМ ----
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0, RADAR_SIZE, 0, 20)
    label.Position = UDim2.new(0, 0, 1, 5)
    label.BackgroundTransparency = 1
    label.Text = "TGK: VNMA0"
    label.TextColor3 = Color3.fromRGB(200, 200, 200)
    label.TextSize = 14
    label.Font = Enum.Font.Code
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Parent = radar

    -- ---- ПЕРЕТАСКИВАНИЕ ----
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

    return gui, radar, dragButton, sectorContainer
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

        -- Исправленный угол камеры (правильная ориентация)
        local camLook = Camera.CFrame.LookVector
        local angle = math.atan2(-camLook.X, -camLook.Z)  -- <-- ключевое исправление
        if sectorContainer then
            sectorContainer.Rotation = math.deg(angle)
        end

        -- Обновляем кэш друзей
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
        local scale = halfSize / MAX_RANGE
        local cosA = math.cos(angle)
        local sinA = math.sin(angle)

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

            -- Поворачиваем вектор на угол камеры
            local rotX = dx * cosA - dz * sinA
            local rotY = dx * sinA + dz * cosA
            local rx = rotX * scale
            local ry = -rotY * scale

            local isFriend = friendCache[player.UserId] == true
            local color = isFriend and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)

            local blip = blips[player]
            if not blip then
                blip = Instance.new("Frame")
                blip.Size = UDim2.new(0, BLIP_SIZE, 0, BLIP_SIZE)
                blip.AnchorPoint = Vector2.new(0.5, 0.5)
                blip.BackgroundColor3 = color
                blip.BorderSizePixel = 0
                blip.ZIndex = 5
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

print("Radar loaded. Fixed rotation, grid restored.")
