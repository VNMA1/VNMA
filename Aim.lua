local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local PLAYER  = Players.LocalPlayer
local CC      = Workspace.CurrentCamera

local ENABLED      = false
local ESP_ENABLED  = false
local TRACK        = false

-- Таблица для хранения ID друзей
local FriendsList = {}

_G.FREE_FOR_ALL = true
_G.ESP_BIND    = Enum.KeyCode.Comma -- Клавиша "," (Б в русской раскладке)
_G.CHANGE_AIM  = Enum.KeyCode.M     -- Клавиша "M"
_G.AIM_AT = 'Head' -- 'Head' или 'Torso'

-- === НОВЫЕ ПЕРЕМЕННЫЕ ДЛЯ ФИКСАЦИИ ЦЕЛИ ===
local LOCKED_TARGET = nil      -- Зафиксированный игрок
local UNLOCK_DISTANCE = 600    -- Дистанция, на которой цель отпускается

-- === ОБНОВЛЕННЫЕ НАСТРОЙКИ СКОРОСТИ И ФИКСАЦИИ ===
local FOV_RADIUS = 90
local FOV_COLOR = Color3.fromRGB(255, 255, 255) 

-- Рисуем FOV круг через Drawing API
local FOVCircle = Drawing.new("Circle")
FOVCircle.Position = Vector2.new(CC.ViewportSize.X / 2, CC.ViewportSize.Y / 2)
FOVCircle.Radius = FOV_RADIUS
FOVCircle.Color = FOV_COLOR
FOVCircle.Thickness = 1
FOVCircle.Filled = false
FOVCircle.Visible = true
FOVCircle.Transparency = 0.5

CC:GetPropertyChangedSignal("ViewportSize"):Connect(function()
    if FOVCircle then
        FOVCircle.Position = Vector2.new(CC.ViewportSize.X / 2, CC.ViewportSize.Y / 2)
    end
end)

-- Безопасное получение целевой части тела (поддержка R6 и R15)
local function GetAimPart(character)
    if not character then return nil end
    if _G.AIM_AT == 'Head' then
        return character:FindFirstChild("Head")
    else
        return character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")
    end
end

-- Функция проверки FOV
local function IsInFOV(position)
    local screenPos, onScreen = CC:WorldToViewportPoint(position)
    if onScreen then
        local mousePos = Vector2.new(CC.ViewportSize.X / 2, CC.ViewportSize.Y / 2)
        local distance = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
        if distance <= FOV_RADIUS then
            return true, distance
        end
    end
    return false, math.huge
end

-- Проверка, жив ли игрок
local function IsPlayerAlive(player)
    if not player or not player.Character then return false end
    local hum = player.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

-- Поиск ближайшего игрока с учетом фиксации
local function GetNearestPlayerToMouse()
    -- Если есть зафиксированная цель - проверяем её
    if LOCKED_TARGET then
        if IsPlayerAlive(LOCKED_TARGET) then
            local targetPart = GetAimPart(LOCKED_TARGET.Character)
            if targetPart then
                local worldDist = (CC.CFrame.Position - targetPart.Position).Magnitude
                
                if worldDist > UNLOCK_DISTANCE then
                    LOCKED_TARGET = nil
                    return GetNearestPlayerToMouse()
                end
                
                local inFov, distToCenter = IsInFOV(targetPart.Position)
                if inFov then
                    return LOCKED_TARGET, distToCenter
                else
                    local screenPos, onScreen = CC:WorldToViewportPoint(targetPart.Position)
                    if onScreen then
                        local mousePos = Vector2.new(CC.ViewportSize.X / 2, CC.ViewportSize.Y / 2)
                        local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                        if screenDist <= FOV_RADIUS * 2 then
                            return LOCKED_TARGET, screenDist
                        end
                    end
                end
            end
        end
        
        LOCKED_TARGET = nil
    end
    
    -- Поиск новой цели
    local closestPlayer = nil
    local shortestDistance = math.huge

    for _, v in pairs(Players:GetPlayers()) do
        if v ~= PLAYER and v.Character then
            if FriendsList[v.UserId] then continue end
            
            local targetPart = GetAimPart(v.Character)
            if targetPart then
                if _G.FREE_FOR_ALL or v.TeamColor ~= PLAYER.TeamColor then
                    local inFov, distToCenter = IsInFOV(targetPart.Position)
                    if inFov and distToCenter < shortestDistance then
                        local hum = v.Character:FindFirstChildOfClass("Humanoid")
                        if hum and hum.Health > 0 then
                            shortestDistance = distToCenter
                            closestPlayer = v
                        end
                    end
                end
            end
        end
    end
    
    if closestPlayer then
        LOCKED_TARGET = closestPlayer
    end
    
    return closestPlayer, shortestDistance
end

-- Сброс фиксации
local function ResetLock()
    LOCKED_TARGET = nil
end

-- Функция добавления/удаления друга
local function ToggleFriend(targetPlayer)
    if not targetPlayer then return end
    
    if FriendsList[targetPlayer.UserId] then
        FriendsList[targetPlayer.UserId] = nil
        if targetPlayer.Character then
            local hl = targetPlayer.Character:FindFirstChild('ESP_Highlight')
            if hl then hl.FillColor = Color3.fromRGB(255, 60, 60) end
        end
        print("Удален из друзей: " .. targetPlayer.Name)
    else
        FriendsList[targetPlayer.UserId] = true
        if targetPlayer.Character then
            local hl = targetPlayer.Character:FindFirstChild('ESP_Highlight')
            if hl then hl.FillColor = Color3.fromRGB(60, 255, 60) end
        end
        print("Добавлен в друзья: " .. targetPlayer.Name)
    end
end

-- Поиск игрока под прицелом для добавления в друзья
local function GetTargetedPlayer()
    local targetPlayer = nil
    local shortestDistance = math.huge
    
    for _, v in pairs(Players:GetPlayers()) do
        if v ~= PLAYER and v.Character then
            local targetPart = GetAimPart(v.Character)
            if targetPart then
                local inFov, distToCenter = IsInFOV(targetPart.Position)
                if inFov and distToCenter < shortestDistance then
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    if hum and hum.Health > 0 then
                        shortestDistance = distToCenter
                        targetPlayer = v
                    end
                end
            end
        end
    end
    
    return targetPlayer
end

-- === СОЗДАНИЕ ИНТЕРФЕЙСА (GUI) ===
local GUI_MAIN = Instance.new('ScreenGui', PLAYER:WaitForChild("PlayerGui"))
GUI_MAIN.Name = 'WALL_AIMBOT_FAST'
GUI_MAIN.ResetOnSpawn = false

local GUI_TARGET = Instance.new('TextLabel', GUI_MAIN)
GUI_TARGET.Size = UDim2.new(0,200,0,30)
GUI_TARGET.BackgroundTransparency = 0.6
GUI_TARGET.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
GUI_TARGET.BorderSizePixel = 0
GUI_TARGET.Position = UDim2.new(0.5,-100,0,5)
GUI_TARGET.Text = 'AIMBOT : OFF'
GUI_TARGET.TextColor3 = Color3.new(1,1,1)
GUI_TARGET.TextSize = 16
GUI_TARGET.Font = Enum.Font.SourceSansBold

local GUI_AIM_AT = Instance.new('TextLabel', GUI_MAIN)
GUI_AIM_AT.Size = UDim2.new(0,200,0,20)
GUI_AIM_AT.BackgroundTransparency = 0.6
GUI_AIM_AT.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
GUI_AIM_AT.BorderSizePixel = 0
GUI_AIM_AT.Position = UDim2.new(0.5,-100,0,35)
GUI_AIM_AT.Text = 'AIMING : HEAD'
GUI_AIM_AT.TextColor3 = Color3.new(1,1,1)
GUI_AIM_AT.TextSize = 13
GUI_AIM_AT.Font = Enum.Font.SourceSansBold

local GUI_FRIEND_HINT = Instance.new('TextLabel', GUI_MAIN)
GUI_FRIEND_HINT.Size = UDim2.new(0,200,0,20)
GUI_FRIEND_HINT.BackgroundTransparency = 0.6
GUI_FRIEND_HINT.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
GUI_FRIEND_HINT.BorderSizePixel = 0
GUI_FRIEND_HINT.Position = UDim2.new(0.5,-100,0,55)
GUI_FRIEND_HINT.Text = 'ALT+ПКМ - ДОБАВИТЬ В ДРУЗЬЯ'
GUI_FRIEND_HINT.TextColor3 = Color3.fromRGB(200, 200, 200)
GUI_FRIEND_HINT.TextSize = 12
GUI_FRIEND_HINT.Font = Enum.Font.SourceSansBold

-- === ЛОГИКА ESP И ОБНОВЛЕНИЯ ДАННЫХ ===
local function CREATE_ESP(character, player)
    if not character or not player then return end
    
    local isFriend = FriendsList[player.UserId]
    local isLocked = (LOCKED_TARGET == player)
    local mainColor = isFriend and Color3.fromRGB(60, 255, 60) or 
                     (isLocked and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 60, 60))
    
    if not character:FindFirstChild('ESP_Highlight') then
        local Highlight = Instance.new('Highlight')
        Highlight.Name = 'ESP_Highlight'
        Highlight.Parent = character
        Highlight.FillTransparency = 0.65
        Highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
        Highlight.OutlineTransparency = 0.1
        Highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    end
    
    local hl = character:FindFirstChild('ESP_Highlight')
    if hl then hl.FillColor = mainColor end

    local head = character:FindFirstChild('Head')
    if head and not head:FindFirstChild('ESP_Tag') then
        local BillboardGui = Instance.new('BillboardGui')
        BillboardGui.Name = 'ESP_Tag'
        BillboardGui.Parent = head
        BillboardGui.AlwaysOnTop = true
        BillboardGui.Size = UDim2.new(0, 150, 0, 40)
        BillboardGui.ExtentsOffset = Vector3.new(0, 3.1, 0)
        
        local NameLabel = Instance.new('TextLabel')
        NameLabel.Name = 'ESP_Text'
        NameLabel.Parent = BillboardGui
        NameLabel.BackgroundTransparency = 1
        NameLabel.Size = UDim2.new(1, 0, 0.5, 0)
        NameLabel.Position = UDim2.new(0, 0, 0, 0)
        NameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        NameLabel.TextStrokeTransparency = 0
        NameLabel.TextSize = 9
        NameLabel.Font = Enum.Font.SourceSansBold
        
        local HPLabel = Instance.new('TextLabel')
        HPLabel.Name = 'ESP_HP'
        HPLabel.Parent = BillboardGui
        HPLabel.BackgroundTransparency = 1
        HPLabel.Size = UDim2.new(1, 0, 0.5, 0)
        HPLabel.Position = UDim2.new(0, 0, 0.5, 0)
        HPLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        HPLabel.TextStrokeTransparency = 0
        HPLabel.TextSize = 12
        HPLabel.Font = Enum.Font.SourceSansBold
    end
    
    if head then
        local tag = head:FindFirstChild('ESP_Tag')
        if tag then
            local nl = tag:FindFirstChild('ESP_Text')
            local hl_text = tag:FindFirstChild('ESP_HP')
            if nl then nl.TextColor3 = mainColor end
            if hl_text then hl_text.TextColor3 = mainColor end
        end
    end
end

local function CLEAR_ESP()
    for _, v in pairs(Players:GetPlayers()) do
        if v.Character then
            local highlight = v.Character:FindFirstChild('ESP_Highlight')
            if highlight then highlight:Destroy() end
            
            local head = v.Character:FindFirstChild('Head')
            local tag = head and head:FindFirstChild('ESP_Tag')
            if tag then tag:Destroy() end
        end
    end
end

-- Удаление ESP при выходе игрока
Players.PlayerRemoving:Connect(function(player)
    FriendsList[player.UserId] = nil
    if LOCKED_TARGET == player then
        LOCKED_TARGET = nil
    end
end)

task.spawn(function()
    while true do
        if ESP_ENABLED and TRACK then
            for _, v in pairs(Players:GetPlayers()) do
                if v ~= PLAYER and v.Character then
                    local head = v.Character:FindFirstChild('Head')
                    local hum = v.Character:FindFirstChildOfClass("Humanoid")
                    
                    if head and hum and hum.Health > 0 then
                        if _G.FREE_FOR_ALL or v.TeamColor ~= PLAYER.TeamColor then
                            CREATE_ESP(v.Character, v)
                            
                            local tag = head:FindFirstChild('ESP_Tag')
                            local nameLabel = tag and tag:FindFirstChild('ESP_Text')
                            local hpLabel = tag and tag:FindFirstChild('ESP_HP')
                            
                            if nameLabel and hpLabel then
                                local distance = math.floor((CC.CFrame.Position - head.Position).Magnitude / 3)
                                local hpPercent = math.floor((hum.Health / hum.MaxHealth) * 100)
                                
                                local lockedText = (LOCKED_TARGET == v) and " [🔒]" or ""
                                local friendText = FriendsList[v.UserId] and " ⭐" or ""
                                nameLabel.Text = string.format("%s | %dM%s%s", v.Name:upper(), distance, lockedText, friendText)
                                hpLabel.Text = string.format("[%d%%]", hpPercent)
                            end
                        end
                    else
                        local hl = v.Character:FindFirstChild('ESP_Highlight')
                        if hl then hl:Destroy() end
                        local tag = head and head:FindFirstChild('ESP_Tag')
                        if tag then tag:Destroy() end
                    end
                end
            end
        end
        task.wait(0.1)
    end
end)

local CURRENT_FOV = FOV_RADIUS or 90

-- === ОТСЛЕЖИВАНИЕ ВВОДА ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    -- ALT + ПКМ для добавления в друзья
    if input.UserInputType == Enum.UserInputType.MouseButton2 and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
        local targetPlayer = GetTargetedPlayer()
        if targetPlayer then
            ToggleFriend(targetPlayer)
        end
        return
    end
    
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        ENABLED = true
        ResetLock()
    elseif input.KeyCode == _G.ESP_BIND then
        ESP_ENABLED = not ESP_ENABLED
        if ESP_ENABLED then
            TRACK = true
            print("ESP : ON")
        else
            TRACK = false
            CLEAR_ESP()
            print("ESP : OFF")
        end
    elseif input.KeyCode == _G.CHANGE_AIM then
        if _G.AIM_AT == 'Head' then
            _G.AIM_AT = 'Torso'
            GUI_AIM_AT.Text = 'AIMING : TORSO'
        else
            _G.AIM_AT = 'Head'
            GUI_AIM_AT.Text = 'AIMING : HEAD'
        end
        ResetLock()
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton2 then
        ENABLED = false
        ResetLock()
    end
end)

-- === ЦИКЛ РЕНДЕРА ===
RunService.RenderStepped:Connect(function()
    if FOVCircle then
        FOVCircle.Position = Vector2.new(CC.ViewportSize.X / 2, CC.ViewportSize.Y / 2)
    end
    
    if ENABLED then
        local TARGET, distToCenter = GetNearestPlayerToMouse()
        
        if TARGET and TARGET.Character then
            local targetPart = GetAimPart(TARGET.Character)
            if targetPart then
                local startSmoothness = 0.08
                local maxSmoothness = 0.35
                
                local currentSmoothness
                if LOCKED_TARGET == TARGET then
                    currentSmoothness = 0.25
                else
                    local proximity = 1 - math.clamp(distToCenter / CURRENT_FOV, 0, 1)
                    currentSmoothness = startSmoothness + (maxSmoothness - startSmoothness) * (proximity ^ 2)
                end
                
                local targetCFrame = CFrame.new(CC.CFrame.Position, targetPart.Position)
                CC.CFrame = CC.CFrame:Lerp(targetCFrame, math.clamp(currentSmoothness, 0, 1))
                GUI_TARGET.Text = 'AIMBOT : LOCK' .. (LOCKED_TARGET == TARGET and ' [🔒]' or '')
            end
        else
            GUI_TARGET.Text = 'AIMBOT : OFF'
        end
    else
        GUI_TARGET.Text = 'AIMBOT : OFF'
        if LOCKED_TARGET then
            ResetLock()
        end
    end
end)
