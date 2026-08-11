--[[
   РАДАР ДЛЯ ROBLOX (LUAU) – ДРУЗЬЯ/ВРАГИ + ПЕРЕТАСКИВАНИЕ
   ИСПРАВЛЕННАЯ ВЕРСИЯ (РАБОЧИЕ ID)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

if not LocalPlayer or not Camera then return end

local playerGui = LocalPlayer:WaitForChild("PlayerGui")
if playerGui:FindFirstChild("RadarGUI") then
    playerGui.RadarGUI:Destroy()  -- удаляем старый, чтобы создать новый
end

-- НАСТРОЙКИ
local RADAR_SIZE = 200
local MAX_RANGE = 500
local BLIP_SIZE = 8
local ARROW_SIZE = 18
local FRIEND_CACHE_TIME = 3

-- СОЗДАНИЕ GUI
local function CreateRadar()
    local gui = Instance.new("ScreenGui")
    gui.Name = "RadarGUI"
    gui.Parent = playerGui
    gui.ResetOnSpawn = false

    local radar = Instance.new("Frame")
    radar.Size = UDim2.new(0, RADAR_SIZE, 0, RADAR_SIZE)
    radar.Position = UDim2.new(1, -(RADAR_SIZE + 20), 0, 20)
    radar.AnchorPoint = Vector2.new(0, 0)
    radar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    radar.BackgroundTransparency = 0.3
    radar.BorderSizePixel = 1
    radar.BorderColor3 = Color3.fromRGB(200, 200, 200)
    radar.ClipsDescendants = true
    radar.Parent = gui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 5)
    corner.Parent = radar

    -- Кнопка для перетаскивания
    local dragButton = Instance.new("TextButton")
    dragButton.Size = UDim2.new(1, 0, 1, 0)
    dragButton.BackgroundTransparency = 1
    dragButton.Text = ""
    dragButton.AutoButtonColor = false
    dragButton.ZIndex = 10
    dragButton.Parent = radar

    -- Центральная точка (вы) – Frame + UICorner
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

    -- Стрелка – используем рабочий ID
    local arrow = Instance.new("ImageLabel")
    arrow.Size = UDim2.new(0, ARROW_SIZE, 0, ARROW_SIZE)
    arrow.AnchorPoint = Vector2.new(0.5, 0.5)
    arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
    arrow.BackgroundTransparency = 1
    arrow.Image = "rbxassetid://13655626325"  -- рабочая стрелка вверх
    arrow.ImageColor3 = Color3.fromRGB(255, 255, 255)
    arrow.ZIndex = 6
    arrow.Parent = radar

    return gui, radar, dragButton, arrow
end

local gui, radar, dragButton, arrow = CreateRadar()

-- ХРАНИЛИЩЕ ТОЧЕК
local blips = {}

-- ФУНКЦИЯ СОЗДАНИЯ ТОЧКИ (Frame + UICorner)
local function CreateBlip(color)
    local blip = Instance.new("Frame")
    blip.Size = UDim2.new(0, BLIP_SIZE, 0, BLIP_SIZE)
    blip.AnchorPoint = Vector2.new(0.5, 0.5)
    blip.BackgroundColor3 = color
    blip.BorderSizePixel = 0
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

-- ======== ПЕРЕТАСКИВАНИЕ ========
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

-- ======== КЭШ ДРУЗЕЙ ========
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

-- ======== ОСНОВНОЙ ЦИКЛ ========
RunService.RenderStepped:Connect(function()
    pcall(function()
        local myHRP = GetHRP(LocalPlayer)
        if not myHRP then return end
        local myPos = myHRP.Position

        -- Обновляем стрелку
        local camLook = Camera.CFrame.LookVector
        local angle = math.atan2(camLook.X, -camLook.Z)
        arrow.Rotation = math.deg(angle)

        updateFriendCache()

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
                blip = CreateBlip(color)
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

print("Radar loaded successfully. Arrow and dots should be visible now.")
