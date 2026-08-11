--[[
   РАДАР ДЛЯ ROBLOX (LUAU) – ДРУЗЬЯ/ВРАГИ + ПЕРЕТАСКИВАНИЕ (ОПТИМИЗИРОВАН)
   - Квадратный радар в правом верхнем углу (можно переместить)
   - Радиус сканирования: 500 студей
   - Друзья — 🟢 зелёные точки, враги — 🔴 красные
   - Стрелка указывает направление взгляда
   - Перетаскивание мышкой / пальцем
   - Кэш друзей (обновление раз в 3 сек)
   - Лёгкие точки (ImageLabel вместо Frame+UICorner)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

if not LocalPlayer or not Camera then return end -- защита от запуска до загрузки

-- Проверка, что радар ещё не создан (чтобы не дублировать)
local playerGui = LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("RadarGUI") then
    return -- уже есть, выходим
end

-- НАСТРОЙКИ
local RADAR_SIZE = 200
local MAX_RANGE = 500
local BLIP_SIZE = 8          -- увеличил для лучшей видимости
local ARROW_SIZE = 14
local FRIEND_CACHE_TIME = 3  -- обновлять список друзей каждые 3 секунды

-- СОЗДАНИЕ GUI
local function CreateRadar()
    local gui = Instance.new("ScreenGui")
    gui.Name = "RadarGUI"
    gui.Parent = playerGui

    local radar = Instance.new("Frame")
    radar.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
    -- Стартовая позиция – правый верхний угол, но AnchorPoint (0,0) для правильного перетаскивания
    radar.Position = UDim2.new(1, -(RADAR_SIZE + 20), 0, 20)
    radar.AnchorPoint = Vector2.new(0, 0)  -- <-- исправлено!
    radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    radar.BackgroundTransparency = 0.4
    radar.BorderSizePixel = 1
    radar.BorderColor3 = Color3.fromRGB(255, 255, 255)
    radar.ClipsDescendants = true
    radar.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = radar

    -- Прозрачная кнопка для перетаскивания
    local dragButton = Instance.new("TextButton")
    dragButton.Size = UDim2.new(1, 0, 1, 0)
    dragButton.BackgroundTransparency = 1
    dragButton.Text = ""
    dragButton.AutoButtonColor = false
    dragButton.ZIndex = 10
    dragButton.Parent = radar

    -- Центральная точка (вы) – теперь ImageLabel для однообразия
    local selfDot = Instance.new("ImageLabel")
    selfDot.Size = UDim2.new(0, 8, 0, 8)
    selfDot.AnchorPoint = Vector2.new(0.5, 0.5)
    selfDot.Position = UDim2.new(0.5, 0, 0.5, 0)
    selfDot.BackgroundTransparency = 1
    selfDot.Image = "rbxassetid://1500860382"  -- круг
    selfDot.ImageColor3 = Color3.fromRGB(0, 255, 255)
    selfDot.ZIndex = 5
    selfDot.Parent = radar

    -- Стрелка (оставляем как есть)
    local arrow = Instance.new("ImageLabel")
    arrow.Size = UDim2.new(0, ARROW_SIZE, 0, ARROW_SIZE)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrow.BackgroundTransparency = 1
    arrow.Image = "rbxassetid://6031094979"
    arrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
    arrow.ZIndex = 6
    arrow.Parent = radar

    return gui, radar, dragButton, arrow
end

local gui, radar, dragButton, arrow = CreateRadar()

-- ХРАНИЛИЩЕ ТОЧЕК (ключ – игрок, значение – ImageLabel)
local blips = {}

-- ФУНКЦИЯ СОЗДАНИЯ ТОЧКИ (теперь ImageLabel, без UICorner)
local function CreateBlip(color)
    local blip = Instance.new("ImageLabel")
    blip.Size = UDim2.new(0, BLIP_SIZE, 0, BLIP_SIZE)
    blip.AnchorPoint = Vector2.new(0.5, 0.5)
    blip.BackgroundTransparency = 1
    blip.Image = "rbxassetid://1500860382"  -- круг
    blip.ImageColor3 = color
    blip.ZIndex = 3
    blip.Parent = radar
    return blip
end

-- ПОЛУЧИТЬ HRP (с проверкой на существование)
local function GetHRP(player)
    local char = player.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp:IsA("BasePart") then
        return hrp
    end
    return nil
end

-- ======== ПЕРЕТАСКИВАНИЕ ========
local dragging = false
local dragOffset = Vector2.new()

local function updateDrag(input)
    local newX = input.Position.X - dragOffset.X
    local newY = input.Position.Y - dragOffset.Y
    radar.Position = UDim2.new(0, newX, 0, newY)  -- используем абсолютные координаты
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

-- ======== КЭШ ДРУЗЕЙ (обновление раз в FRIEND_CACHE_TIME) ========
local friendCache = {}
local lastFriendUpdate = 0

local function updateFriendCache()
    local now = tick()
    if now - lastFriendUpdate < FRIEND_CACHE_TIME then
        return
    end
    lastFriendUpdate = now
    local newCache = {}
    local players = Players:GetPlayers()
    for _, p in ipairs(players) do
        if p ~= LocalPlayer then
            local isFriend = p:IsFriendsWith(LocalPlayer.UserId)
            if isFriend then
                newCache[p.UserId] = true
            end
        end
    end
    friendCache = newCache
end

-- ======== ОСНОВНОЙ ЦИКЛ ОБНОВЛЕНИЯ ========
RunService.RenderStepped:Connect(function()
    -- Обработка ошибок, чтобы скрипт не падал
    local success, err = pcall(function()
        local myHRP = GetHRP(LocalPlayer)
        if not myHRP then return end

        local myPos = myHRP.Position

        -- Стрелка
        local camLook = Camera.CFrame.LookVector
        local angle = math.atan2(camLook.X, -camLook.Z)
        arrow.Rotation = math.deg(angle)

        -- Обновляем кэш друзей (не каждый кадр)
        updateFriendCache()

        local players = Players:GetPlayers()
        local halfSize = RADAR_SIZE / 2

        for _, player in ipairs(players) do
            if player == LocalPlayer then continue end

            local hrp = GetHRP(player)
            if not hrp then
                if blips[player] then
                    blips[player].Visible = false
                end
                continue
            end

            local targetPos = hrp.Position
            local distance = (myPos - targetPos).Magnitude

            -- Если дальше радиуса – скрываем точку
            if distance > MAX_RANGE then
                if blips[player] then
                    blips[player].Visible = false
                end
                continue
            end

            -- Вычисляем относительные координаты
            local dx = targetPos.X - myPos.X
            local dz = targetPos.Z - myPos.Z
            local scale = halfSize / MAX_RANGE
            local rx = dx * scale
            local ry = -dz * scale

            -- Определяем цвет по кэшу друзей
            local isFriend = friendCache[player.UserId] == true
            local color = isFriend and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)

            -- Создаём или обновляем точку
            local blip = blips[player]
            if not blip then
                blip = CreateBlip(color)
                blips[player] = blip
            end

            blip.Position = UDim2.new(0.5, rx, 0.5, ry)
            blip.Visible = true

            -- Меняем цвет, если изменился статус (на всякий случай)
            if blip.ImageColor3 ~= color then
                blip.ImageColor3 = color
            end
        end

        -- Удаляем точки для игроков, которые покинули игру
        for player, blip in pairs(blips) do
            if not player.Parent then
                blip:Destroy()
                blips[player] = nil
            end
        end
    end)

    if not success then
        warn("[Radar Error] " .. tostring(err))
    end
end)

print ("Radar loaded successfully.")
