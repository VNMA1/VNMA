--!nocheck
-- FLING VNMA | MOBILE UI REWORK

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local MY_TG_LINK = "https://t.me/VNMA_OFFICIAL"

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------

getgenv().FlingScriptRunning = false
getgenv().AntiFlingActive = false
getgenv().FlingLoopActive = false
getgenv().SelectedPlayers = {}
getgenv().AntiFlingConnection = nil
getgenv().FlingLoopThread = nil
getgenv().RefreshThread = nil
getgenv().IsMenuHidden = false
getgenv().Connections = getgenv().Connections or {}
getgenv().AntiFlingOriginal = getgenv().AntiFlingOriginal or {}

----------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------

local function disconnectConnection(key)
    local conn = getgenv().Connections[key]
    if conn then
        pcall(function()
            conn:Disconnect()
        end)
        getgenv().Connections[key] = nil
    end
end

local function disconnectAll()
    for key, conn in pairs(getgenv().Connections) do
        if conn then
            pcall(function()
                conn:Disconnect()
            end)
        end
        getgenv().Connections[key] = nil
    end
end

local function restoreAntiFling()
    local original = getgenv().AntiFlingOriginal

    for part, oldCanCollide in pairs(original) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = oldCanCollide
            end)
        end
    end

    table.clear(original)
end

local function removeFlingVelocity(hrp)
    if not hrp or not hrp.Parent then
        return
    end

    pcall(function()
        local lv = hrp:FindFirstChild("FlingLV")
        if lv then
            lv:Destroy()
        end

        local av = hrp:FindFirstChild("FlingAV")
        if av then
            av:Destroy()
        end

        local att = hrp:FindFirstChild("FlingAttachment")
        if att then
            att:Destroy()
        end

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function applyFlingVelocity(hrp)
    if not hrp or not hrp.Parent then
        return
    end

    pcall(function()
        local att = hrp:FindFirstChild("FlingAttachment")

        if not att then
            att = Instance.new("Attachment")
            att.Name = "FlingAttachment"
            att.Parent = hrp
        end

        local lv = hrp:FindFirstChild("FlingLV")

        if not lv then
            lv = Instance.new("LinearVelocity")
            lv.Name = "FlingLV"
            lv.Parent = hrp
        end

        lv.Attachment0 = att
        lv.RelativeTo = Enum.ActuatorRelativeTo.World
        lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
        lv.ForceLimitsEnabled = false
        lv.VectorVelocity = Vector3.new(999999, 999999, 999999)

        local av = hrp:FindFirstChild("FlingAV")

        if not av then
            av = Instance.new("AngularVelocity")
            av.Name = "FlingAV"
            av.Parent = hrp
        end

        av.Attachment0 = att
        av.RelativeTo = Enum.ActuatorRelativeTo.World
        av.MaxTorque = math.huge
        av.AngularVelocity = Vector3.new(999999, 999999, 999999)
    end)
end

----------------------------------------------------------------
-- CLEANUP
----------------------------------------------------------------

local function CleanupExisting()
    getgenv().FlingScriptRunning = false
    getgenv().FlingLoopActive = false
    getgenv().AntiFlingActive = false

    disconnectAll()

    if getgenv().AntiFlingConnection then
        pcall(function()
            getgenv().AntiFlingConnection:Disconnect()
        end)
        getgenv().AntiFlingConnection = nil
    end

    restoreAntiFling()

    local oldGui = CoreGui:FindFirstChild("FlingGui_QueueSystem")

    if oldGui then
        pcall(function()
            oldGui:Destroy()
        end)
    end

    local char = LocalPlayer.Character

    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            removeFlingVelocity(hrp)
        end

        local humanoid = char:FindFirstChildOfClass("Humanoid")
        if humanoid then
            pcall(function()
                humanoid.Sit = false
            end)
        end
    end

    getgenv().SelectedPlayers = {}
    getgenv().IsMenuHidden = false
end

CleanupExisting()

getgenv().FlingScriptRunning = true

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlingGui_QueueSystem"
ScreenGui.ResetOnSpawn = false
ScreenGui.IgnoreGuiInset = true
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = CoreGui

----------------------------------------------------------------
-- BACKGROUND
----------------------------------------------------------------

local Backdrop = Instance.new("Frame")
Backdrop.Parent = ScreenGui
Backdrop.Size = UDim2.fromScale(1, 1)
Backdrop.BackgroundColor3 = Color3.fromRGB(5, 7, 10)
Backdrop.BackgroundTransparency = 0.15
Backdrop.BorderSizePixel = 0

----------------------------------------------------------------
-- MAIN
----------------------------------------------------------------

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.Position = UDim2.fromScale(0.5, 0.5)
MainFrame.Size = UDim2.fromScale(0.94, 0.92)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 21, 28)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 18)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(55, 65, 85)
MainStroke.Thickness = 1.5
MainStroke.Transparency = 0.15
MainStroke.Parent = MainFrame

----------------------------------------------------------------
-- HEADER
----------------------------------------------------------------

local Header = Instance.new("Frame")
Header.Parent = MainFrame
Header.Size = UDim2.new(1, 0, 0, 82)
Header.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
Header.BorderSizePixel = 0

local HeaderTitle = Instance.new("TextLabel")
HeaderTitle.Parent = Header
HeaderTitle.BackgroundTransparency = 1
HeaderTitle.Position = UDim2.new(0, 22, 0, 10)
HeaderTitle.Size = UDim2.new(1, -95, 0, 34)
HeaderTitle.Font = Enum.Font.GothamBold
HeaderTitle.Text = "⚡ FLING VNMA"
HeaderTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
HeaderTitle.TextSize = 22
HeaderTitle.TextXAlignment = Enum.TextXAlignment.Left

local HeaderSub = Instance.new("TextLabel")
HeaderSub.Parent = Header
HeaderSub.BackgroundTransparency = 1
HeaderSub.Position = UDim2.new(0, 23, 0, 46)
HeaderSub.Size = UDim2.new(1, -100, 0, 24)
HeaderSub.Font = Enum.Font.Code
HeaderSub.Text = MY_TG_LINK
HeaderSub.TextColor3 = Color3.fromRGB(90, 220, 255)
HeaderSub.TextSize = 12
HeaderSub.TextXAlignment = Enum.TextXAlignment.Left

local CloseBtn = Instance.new("TextButton")
CloseBtn.Parent = Header
CloseBtn.AnchorPoint = Vector2.new(1, 0.5)
CloseBtn.Position = UDim2.new(1, -14, 0.5, 0)
CloseBtn.Size = UDim2.new(0, 48, 0, 48)
CloseBtn.BackgroundColor3 = Color3.fromRGB(175, 50, 55)
CloseBtn.BorderSizePixel = 0
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Text = "×"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 28
CloseBtn.AutoButtonColor = true

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 14)
CloseCorner.Parent = CloseBtn

----------------------------------------------------------------
-- CONTENT
----------------------------------------------------------------

local Content = Instance.new("Frame")
Content.Parent = MainFrame
Content.BackgroundTransparency = 1
Content.Position = UDim2.new(0, 14, 0, 92)
Content.Size = UDim2.new(1, -28, 1, -106)

----------------------------------------------------------------
-- BUTTON FACTORY
----------------------------------------------------------------

local function createButton(parent, text, height)
    local btn = Instance.new("TextButton")
    btn.Parent = parent
    btn.Size = UDim2.new(1, 0, 0, height)
    btn.BackgroundColor3 = Color3.fromRGB(35, 40, 52)
    btn.BorderSizePixel = 0
    btn.Font = Enum.Font.GothamBold
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(245, 245, 245)
    btn.TextSize = 15
    btn.AutoButtonColor = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = btn

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(65, 75, 95)
    stroke.Thickness = 1
    stroke.Transparency = 0.2
    stroke.Parent = btn

    return btn
end

----------------------------------------------------------------
-- TOP BUTTONS
----------------------------------------------------------------

local AntiFlingBtn = createButton(Content, "🛡️  Анти-Флинг: ВЫКЛ", 48)
AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 55)

local StartFlingBtn = createButton(Content, "⚔️  ЗАПУСТИТЬ ФЛИНГ", 54)
StartFlingBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 195)

local ResetBtn = createButton(Content, "🧹  Сбросить цели", 42)
ResetBtn.BackgroundColor3 = Color3.fromRGB(40, 45, 58)

----------------------------------------------------------------
-- TARGET TITLE
----------------------------------------------------------------

local TargetTitle = Instance.new("TextLabel")
TargetTitle.Parent = Content
TargetTitle.BackgroundTransparency = 1
TargetTitle.Position = UDim2.new(0, 4, 0, 160)
TargetTitle.Size = UDim2.new(1, -8, 0, 30)
TargetTitle.Font = Enum.Font.GothamBold
TargetTitle.Text = "ИГРОКИ НА СЕРВЕРЕ"
TargetTitle.TextColor3 = Color3.fromRGB(210, 215, 230)
TargetTitle.TextSize = 15
TargetTitle.TextXAlignment = Enum.TextXAlignment.Left

local CountLabel = Instance.new("TextLabel")
CountLabel.Parent = Content
CountLabel.BackgroundTransparency = 1
CountLabel.Position = UDim2.new(1, -160, 0, 160)
CountLabel.Size = UDim2.new(0, 156, 0, 30)
CountLabel.Font = Enum.Font.Gotham
CountLabel.Text = "Целей: 0"
CountLabel.TextColor3 = Color3.fromRGB(130, 180, 255)
CountLabel.TextSize = 13
CountLabel.TextXAlignment = Enum.TextXAlignment.Right

----------------------------------------------------------------
-- PLAYER LIST
----------------------------------------------------------------

local PlayersScroll = Instance.new("ScrollingFrame")
PlayersScroll.Parent = Content
PlayersScroll.Position = UDim2.new(0, 0, 0, 196)
PlayersScroll.Size = UDim2.new(1, 0, 1, -268)
PlayersScroll.BackgroundColor3 = Color3.fromRGB(11, 14, 20)
PlayersScroll.BorderSizePixel = 0
PlayersScroll.ScrollBarThickness = 7
PlayersScroll.ScrollBarImageTransparency = 0.15
PlayersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayersScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
PlayersScroll.ScrollingDirection = Enum.ScrollingDirection.Y

local ScrollCorner = Instance.new("UICorner")
ScrollCorner.CornerRadius = UDim.new(0, 14)
ScrollCorner.Parent = PlayersScroll

local ScrollPadding = Instance.new("UIPadding")
ScrollPadding.Parent = PlayersScroll
ScrollPadding.PaddingTop = UDim.new(0, 8)
ScrollPadding.PaddingBottom = UDim.new(0, 8)
ScrollPadding.PaddingLeft = UDim.new(0, 8)
ScrollPadding.PaddingRight = UDim.new(0, 8)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = PlayersScroll
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 7)

----------------------------------------------------------------
-- BOTTOM BUTTONS
----------------------------------------------------------------

local ReloadBtn = createButton(Content, "🔄  Перезагрузить список", 42)
ReloadBtn.Position = UDim2.new(0, 0, 1, -62)

local HideBtn = createButton(Content, "👁️  Скрыть меню", 42)
HideBtn.Position = UDim2.new(0.5, 5, 1, -62)
HideBtn.Size = UDim2.new(0.5, -5, 0, 42)

ReloadBtn.Size = UDim2.new(0.5, -5, 0, 42)

----------------------------------------------------------------
-- SHOW BUTTON
----------------------------------------------------------------

local ShowBtn = Instance.new("TextButton")
ShowBtn.Parent = ScreenGui
ShowBtn.AnchorPoint = Vector2.new(1, 1)
ShowBtn.Position = UDim2.new(1, -16, 1, -16)
ShowBtn.Size = UDim2.new(0, 68, 0, 68)
ShowBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
ShowBtn.BorderSizePixel = 0
ShowBtn.Font = Enum.Font.GothamBold
ShowBtn.Text = "⚡\nVNMA"
ShowBtn.TextColor3 = Color3.fromRGB(255, 215, 80)
ShowBtn.TextSize = 16
ShowBtn.Visible = false
ShowBtn.ZIndex = 50

local ShowCorner = Instance.new("UICorner")
ShowCorner.CornerRadius = UDim.new(0, 18)
ShowCorner.Parent = ShowBtn

local ShowStroke = Instance.new("UIStroke")
ShowStroke.Color = Color3.fromRGB(255, 210, 70)
ShowStroke.Thickness = 2
ShowStroke.Parent = ShowBtn

----------------------------------------------------------------
-- MOBILE DRAG
----------------------------------------------------------------

local function makeDraggable(frame)
    local dragging = false
    local dragStart
    local startPos

    local function update(input)
        local delta = input.Position - dragStart

        frame.Position = UDim2.new(
            startPos.X.Scale,
            startPos.X.Offset + delta.X,
            startPos.Y.Scale,
            startPos.Y.Offset + delta.Y
        )
    end

    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

            dragging = true
            dragStart = input.Position
            startPos = frame.Position

            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)

    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then

            if dragging then
                update(input)
            end
        end
    end)
end

makeDraggable(MainFrame)

----------------------------------------------------------------
-- HIDE / SHOW
----------------------------------------------------------------

local function setHidden(hidden)
    getgenv().IsMenuHidden = hidden

    MainFrame.Visible = not hidden
    Backdrop.Visible = not hidden
    ShowBtn.Visible = hidden

    if hidden then
        HideBtn.Text = "👁️  Показать меню"
    else
        HideBtn.Text = "👁️  Скрыть меню"
    end
end

CloseBtn.MouseButton1Click:Connect(function()
    setHidden(true)
end)

HideBtn.MouseButton1Click:Connect(function()
    setHidden(not getgenv().IsMenuHidden)
end)

ShowBtn.MouseButton1Click:Connect(function()
    setHidden(false)
end)

----------------------------------------------------------------
-- ANTI-FLING
----------------------------------------------------------------

getgenv().AntiFlingConnection = RunService.Heartbeat:Connect(function()
    if not getgenv().FlingScriptRunning then
        return
    end

    if not getgenv().AntiFlingActive then
        return
    end

    pcall(function()
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer
            and player.Character
            and player.Character.Parent then

                for _, part in ipairs(player.Character:GetDescendants()) do
                    if part:IsA("BasePart") then
                        if getgenv().AntiFlingOriginal[part] == nil then
                            getgenv().AntiFlingOriginal[part] = part.CanCollide
                        end

                        if part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
    end)
end)

AntiFlingBtn.MouseButton1Click:Connect(function()
    getgenv().AntiFlingActive = not getgenv().AntiFlingActive

    if getgenv().AntiFlingActive then
        AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(50, 155, 80)
        AntiFlingBtn.Text = "🛡️  Анти-Флинг: ВКЛ"
    else
        AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(120, 50, 55)
        AntiFlingBtn.Text = "🛡️  Анти-Флинг: ВЫКЛ"

        restoreAntiFling()
    end
end)

----------------------------------------------------------------
-- FLING LOOP
----------------------------------------------------------------

getgenv().FlingLoopThread = task.spawn(function()
    while getgenv().FlingScriptRunning do
        task.wait(0.1)

        if not getgenv().FlingLoopActive then
            continue
        end

        local selected = getgenv().SelectedPlayers or {}
        local targetCount = 0

        for _, enabled in pairs(selected) do
            if enabled then
                targetCount += 1
            end
        end

        if targetCount <= 0 then
            getgenv().FlingLoopActive = false
            StartFlingBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 195)
            StartFlingBtn.Text = "⚔️  ЗАПУСТИТЬ ФЛИНГ"
            continue
        end

        for targetPlayer, enabled in pairs(selected) do
            if not getgenv().FlingLoopActive
            or not getgenv().FlingScriptRunning then
                break
            end

            if not enabled
            or not targetPlayer
            or not targetPlayer.Parent then
                continue
            end

            pcall(function()
                local targetChar = targetPlayer.Character
                if not targetChar or not targetChar.Parent then
                    return
                end

                local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
                if not targetHRP then
                    return
                end

                local myChar = LocalPlayer.Character
                if not myChar or not myChar.Parent then
                    return
                end

                local myHRP = myChar:FindFirstChild("HumanoidRootPart")
                local myHumanoid = myChar:FindFirstChildOfClass("Humanoid")

                if not myHRP or not myHumanoid then
                    return
                end

                if myHumanoid.Health <= 0 then
                    return
                end

                myHumanoid.Sit = true
                applyFlingVelocity(myHRP)

                local elapsed = 0

                while elapsed < 0.4
                and getgenv().FlingLoopActive
                and getgenv().FlingScriptRunning
                and targetPlayer.Parent
                and targetPlayer.Character
                and myHumanoid.Health > 0 do

                    if not targetHRP.Parent or not myHRP.Parent then
                        break
                    end

                    myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 0.05)

                    task.wait(0.02)
                    elapsed += 0.02
                end

                removeFlingVelocity(myHRP)

                if myHumanoid.Parent then
                    myHumanoid.Sit = false
                end

                task.wait(3)
            end)
        end
    end
end)

StartFlingBtn.MouseButton1Click:Connect(function()
    getgenv().FlingLoopActive = not getgenv().FlingLoopActive

    if getgenv().FlingLoopActive then
        StartFlingBtn.BackgroundColor3 = Color3.fromRGB(175, 50, 55)
        StartFlingBtn.Text = "🛑  ОСТАНОВИТЬ"
    else
        StartFlingBtn.BackgroundColor3 = Color3.fromRGB(45, 100, 195)
        StartFlingBtn.Text = "⚔️  ЗАПУСТИТЬ ФЛИНГ"

        local char = LocalPlayer.Character
        if char then
            removeFlingVelocity(char:FindFirstChild("HumanoidRootPart"))

            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function()
                    hum.Sit = false
                end)
            end
        end
    end
end)

----------------------------------------------------------------
-- PLAYER LIST
----------------------------------------------------------------

local updating = false

local function updateList()
    if not getgenv().FlingScriptRunning or updating then
        return
    end

    updating = true

    pcall(function()
        for _, child in ipairs(PlayersScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end

        local players = Players:GetPlayers()
        local selected = getgenv().SelectedPlayers or {}

        local totalPlayers = 0
        local selectedCount = 0

        for player, enabled in pairs(selected) do
            if enabled and player and player.Parent then
                selectedCount += 1
            end
        end

        for _, player in ipairs(players) do
            if player ~= LocalPlayer and player.Parent then
                totalPlayers += 1

                local row = Instance.new("TextButton")
                row.Parent = PlayersScroll
                row.Name = "Player_" .. player.Name
                row.Size = UDim2.new(1, 0, 0, 46)
                row.BackgroundColor3 =
                    selected[player]
                    and Color3.fromRGB(45, 135, 70)
                    or Color3.fromRGB(25, 30, 40)

                row.BorderSizePixel = 0
                row.Font = Enum.Font.GothamMedium
                row.Text = selected[player]
                    and "🎯  " .. player.DisplayName
                    or "   " .. player.DisplayName
                row.TextColor3 = Color3.fromRGB(245, 245, 245)
                row.TextSize = 15
                row.TextXAlignment = Enum.TextXAlignment.Left
                row.AutoButtonColor = true

                local rowCorner = Instance.new("UICorner")
                rowCorner.CornerRadius = UDim.new(0, 10)
                rowCorner.Parent = row

                local rowStroke = Instance.new("UIStroke")
                rowStroke.Color = Color3.fromRGB(60, 70, 90)
                rowStroke.Thickness = 1
                rowStroke.Transparency = 0.35
                rowStroke.Parent = row

                row.MouseButton1Click:Connect(function()
                    if not player or not player.Parent then
                        return
                    end

                    if getgenv().SelectedPlayers[player] then
                        getgenv().SelectedPlayers[player] = nil
                    else
                        getgenv().SelectedPlayers[player] = true
                    end

                    updateList()
                end)
            end
        end

        CountLabel.Text =
            "Игроков: " .. totalPlayers ..
            "  •  Целей: " .. selectedCount

        if totalPlayers == 0 then
            local empty = Instance.new("TextLabel")
            empty.Parent = PlayersScroll
            empty.Size = UDim2.new(1, 0, 0, 50)
            empty.BackgroundTransparency = 1
            empty.Text = "На сервере пока нет других игроков"
            empty.TextColor3 = Color3.fromRGB(160, 165, 180)
            empty.Font = Enum.Font.Gotham
            empty.TextSize = 14
        end
    end)

    updating = false
end

----------------------------------------------------------------
-- RESET
----------------------------------------------------------------

ResetBtn.MouseButton1Click:Connect(function()
    getgenv().SelectedPlayers = {}
    updateList()
end)

----------------------------------------------------------------
-- RELOAD
----------------------------------------------------------------

ReloadBtn.MouseButton1Click:Connect(function()
    updateList()
end)

----------------------------------------------------------------
-- PLAYER CONNECTIONS
----------------------------------------------------------------

getgenv().Connections.PlayerAdded = Players.PlayerAdded:Connect(function()
    task.wait(0.25)

    if getgenv().FlingScriptRunning then
        updateList()
    end
end)

getgenv().Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
    getgenv().SelectedPlayers[player] = nil

    task.wait(0.15)

    if getgenv().FlingScriptRunning then
        updateList()
    end
end)

----------------------------------------------------------------
-- PERIODIC REFRESH
----------------------------------------------------------------

getgenv().RefreshThread = task.spawn(function()
    while getgenv().FlingScriptRunning do
        task.wait(3)

        if getgenv().FlingScriptRunning then
            updateList()
        end
    end
end)

----------------------------------------------------------------
-- FIRST UPDATE
----------------------------------------------------------------

task.wait(0.5)
updateList()

print("✅ FLING VNMA MOBILE запущен")
print("📱 Mobile UI включён")
print("📋 Игроки обновляются автоматически")
