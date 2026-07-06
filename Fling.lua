local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local CoreGui = game:GetService("CoreGui")
local TweenService = game:GetService("TweenService")

local MY_TG_LINK = "https://t.me/VNMA_OFFICIAL"

getgenv().FlingScriptRunning = false
getgenv().AntiFlingActive = false
getgenv().FlingLoopActive = false
getgenv().SelectedPlayers = {}
getgenv().AntiFlingConnection = nil
getgenv().FlingLoopThread = nil
getgenv().IsMenuCollapsed = false
getgenv().IsMenuHidden = false

local function CleanupExisting()
    getgenv().FlingScriptRunning = false
    task.wait(0.1)
    if getgenv().AntiFlingConnection then
        pcall(function() getgenv().AntiFlingConnection:Disconnect() end)
        getgenv().AntiFlingConnection = nil
    end
    local gui = CoreGui:FindFirstChild("FlingGui_QueueSystem")
    if gui then
        pcall(function() gui:Destroy() end)
    end
    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            pcall(function()
                if hrp:FindFirstChild("FlingLV") then hrp.FlingLV:Destroy() end
                if hrp:FindFirstChild("FlingAV") then hrp.FlingAV:Destroy() end
                if hrp:FindFirstChild("FlingAttachment") then hrp.FlingAttachment:Destroy() end
                hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
            end)
        end
    end
    getgenv().SelectedPlayers = {}
    getgenv().FlingLoopActive = false
    getgenv().AntiFlingActive = false
    getgenv().IsMenuCollapsed = false
    getgenv().IsMenuHidden = false
end

CleanupExisting()
getgenv().FlingScriptRunning = true

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FlingGui_QueueSystem"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame")
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
MainFrame.Position = UDim2.new(0.1, 0, 0.05, 0)
MainFrame.Size = UDim2.new(0, 220, 0, 400) -- УВЕЛИЧИЛ!
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true

local Title = Instance.new("TextLabel")
Title.Parent = MainFrame
Title.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
Title.Size = UDim2.new(1, 0, 0, 30)
Title.Font = Enum.Font.SourceSansBold
Title.Text = "FLING VNMA"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 12

local TgLabel = Instance.new("TextLabel")
TgLabel.Parent = MainFrame
TgLabel.BackgroundTransparency = 1
TgLabel.Position = UDim2.new(0, 0, 0, 30)
TgLabel.Size = UDim2.new(1, 0, 0, 20)
TgLabel.Font = Enum.Font.Code
TgLabel.Text = MY_TG_LINK
TgLabel.TextColor3 = Color3.fromRGB(0, 255, 255)
TgLabel.TextSize = 10

task.spawn(function()
    local hue = 0
    while getgenv().FlingScriptRunning and task.wait(0.02) do
        hue = (hue + 1) % 360
        if TgLabel and TgLabel.Parent then
            TgLabel.TextColor3 = Color3.fromHSV(hue / 360, 0.8, 1)
        end
    end
end)

local ContentContainer = Instance.new("Frame")
ContentContainer.Parent = MainFrame
ContentContainer.BackgroundTransparency = 1
ContentContainer.Position = UDim2.new(0, 0, 0, 50)
ContentContainer.Size = UDim2.new(1, 0, 1, -50)

local AntiFlingBtn = Instance.new("TextButton")
AntiFlingBtn.Parent = ContentContainer
AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
AntiFlingBtn.Position = UDim2.new(0.05, 0, 0.02, 0)
AntiFlingBtn.Size = UDim2.new(0.9, 0, 0, 25)
AntiFlingBtn.Font = Enum.Font.SourceSansBold
AntiFlingBtn.Text = "🛡️ Анти-Флинг: ВЫКЛ"
AntiFlingBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AntiFlingBtn.TextSize = 11

local StartFlingBtn = Instance.new("TextButton")
StartFlingBtn.Parent = ContentContainer
StartFlingBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
StartFlingBtn.Position = UDim2.new(0.05, 0, 0.12, 0)
StartFlingBtn.Size = UDim2.new(0.9, 0, 0, 30)
StartFlingBtn.Font = Enum.Font.SourceSansBold
StartFlingBtn.Text = "⚔️ ЗАПУСТИТЬ ФЛИНГ"
StartFlingBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StartFlingBtn.TextSize = 12

local ResetBtn = Instance.new("TextButton")
ResetBtn.Parent = ContentContainer
ResetBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
ResetBtn.Position = UDim2.new(0.05, 0, 0.20, 0)
ResetBtn.Size = UDim2.new(0.9, 0, 0, 20)
ResetBtn.Font = Enum.Font.SourceSans
ResetBtn.Text = "🧹 Сбросить цели"
ResetBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
ResetBtn.TextSize = 10

-- ===== ИСПРАВЛЕННЫЙ СПИСОК ИГРОКОВ (БОЛЬШЕ!) =====
local PlayersScroll = Instance.new("ScrollingFrame")
PlayersScroll.Parent = ContentContainer
PlayersScroll.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
PlayersScroll.Position = UDim2.new(0.05, 0, 0.26, 0)
PlayersScroll.Size = UDim2.new(0.9, 0, 0, 0.45) -- УВЕЛИЧИЛ!
PlayersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayersScroll.ScrollBarThickness = 4

local ReloadBtn = Instance.new("TextButton")
ReloadBtn.Parent = ContentContainer
ReloadBtn.BackgroundColor3 = Color3.fromRGB(210, 105, 30)
ReloadBtn.Position = UDim2.new(0.05, 0, 0.75, 0)
ReloadBtn.Size = UDim2.new(0.9, 0, 0, 22)
ReloadBtn.Font = Enum.Font.SourceSansBold
ReloadBtn.Text = "🔄 ПЕРЕЗАГРУЗИТЬ"
ReloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ReloadBtn.TextSize = 10

local HideBtn = Instance.new("TextButton")
HideBtn.Parent = ContentContainer
HideBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
HideBtn.Position = UDim2.new(0.05, 0, 0.85, 0)
HideBtn.Size = UDim2.new(0.42, 0, 0, 20)
HideBtn.Font = Enum.Font.SourceSans
HideBtn.Text = "👁️ Скрыть"
HideBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
HideBtn.TextSize = 10

local ShowBtn = Instance.new("TextButton")
ShowBtn.Parent = ScreenGui
ShowBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
ShowBtn.Position = UDim2.new(0.42, 0, 0.85, 0)
ShowBtn.Size = UDim2.new(0, 55, 0, 55)
ShowBtn.Font = Enum.Font.SourceSansBold
ShowBtn.Text = "⚡\nVNMA"
ShowBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
ShowBtn.TextSize = 12
ShowBtn.Visible = false
ShowBtn.ZIndex = 20
ShowBtn.BorderSizePixel = 2
ShowBtn.BorderColor3 = Color3.fromRGB(255, 215, 0)

local ToggleBtn = Instance.new("TextButton")
ToggleBtn.Parent = MainFrame
ToggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
ToggleBtn.BackgroundTransparency = 0.3
ToggleBtn.Position = UDim2.new(0.82, 0, 0.005, 0)
ToggleBtn.Size = UDim2.new(0, 35, 0, 22)
ToggleBtn.Font = Enum.Font.SourceSansBold
ToggleBtn.Text = "FLING"
ToggleBtn.TextColor3 = Color3.fromRGB(255, 215, 0)
ToggleBtn.TextSize = 8
ToggleBtn.ZIndex = 10
ToggleBtn.BorderSizePixel = 1
ToggleBtn.BorderColor3 = Color3.fromRGB(255, 215, 0)

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Parent = PlayersScroll
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 3)

local function ToggleMenu()
    getgenv().IsMenuCollapsed = not getgenv().IsMenuCollapsed
    local targetSize
    local targetText
    local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    if getgenv().IsMenuCollapsed then
        targetSize = UDim2.new(0, 220, 0, 30)
        targetText = "▼"
        ContentContainer.Visible = false
    else
        targetSize = UDim2.new(0, 220, 0, 400)
        targetText = "FLING"
        ContentContainer.Visible = true
    end
    local tween = TweenService:Create(MainFrame, tweenInfo, {Size = targetSize})
    tween:Play()
    ToggleBtn.Text = targetText
end

local function ToggleHide()
    getgenv().IsMenuHidden = not getgenv().IsMenuHidden
    if getgenv().IsMenuHidden then
        MainFrame.Visible = false
        ShowBtn.Visible = true
        HideBtn.Text = "👁️ Показать"
    else
        MainFrame.Visible = true
        ShowBtn.Visible = false
        HideBtn.Text = "👁️ Скрыть"
    end
end

ToggleBtn.MouseButton1Click:Connect(ToggleMenu)
HideBtn.MouseButton1Click:Connect(ToggleHide)

ShowBtn.MouseButton1Click:Connect(function()
    getgenv().IsMenuHidden = false
    MainFrame.Visible = true
    ShowBtn.Visible = false
    HideBtn.Text = "👁️ Скрыть"
end)

local function removeFlingVelocity(hrp)
    if not hrp or not hrp.Parent then return end
    pcall(function()
        if hrp:FindFirstChild("FlingLV") then hrp.FlingLV:Destroy() end
        if hrp:FindFirstChild("FlingAV") then hrp.FlingAV:Destroy() end
        if hrp:FindFirstChild("FlingAttachment") then hrp.FlingAttachment:Destroy() end
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        hrp.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end)
end

local function applyFlingVelocity(hrp)
    if not hrp or not hrp.Parent then return end
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
        lv.MaxForce = math.huge
        lv.VectorVelocity = Vector3.new(999999, 999999, 999999)
        lv.Attachment0 = att
        local av = hrp:FindFirstChild("FlingAV")
        if not av then
            av = Instance.new("AngularVelocity")
            av.Name = "FlingAV"
            av.Parent = hrp
        end
        av.MaxTorque = math.huge
        av.AngularVelocity = Vector3.new(999999, 999999, 999999)
        av.Attachment0 = att
    end)
end

getgenv().AntiFlingConnection = RunService.Heartbeat:Connect(function()
    if not getgenv().FlingScriptRunning then 
        if getgenv().AntiFlingConnection then
            getgenv().AntiFlingConnection:Disconnect()
            getgenv().AntiFlingConnection = nil
        end
        return 
    end
    if getgenv().AntiFlingActive then
        pcall(function()
            for _, p in pairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character and p.Character.Parent then
                    for _, part in pairs(p.Character:GetDescendants()) do
                        if part:IsA("BasePart") and part.CanCollide then 
                            part.CanCollide = false 
                        end
                    end
                end
            end
        end)
    end
end)

AntiFlingBtn.MouseButton1Click:Connect(function()
    getgenv().AntiFlingActive = not getgenv().AntiFlingActive
    if getgenv().AntiFlingActive then
        AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(60, 180, 60)
        AntiFlingBtn.Text = "🛡️ Анти-Флинг: ВКЛ"
    else
        AntiFlingBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
        AntiFlingBtn.Text = "🛡️ Анти-Флинг: ВЫКЛ"
    end
end)

getgenv().FlingLoopThread = task.spawn(function()
    while getgenv().FlingScriptRunning do
        task.wait(0.1)
        if not getgenv().FlingLoopActive then
            task.wait(0.5)
            continue
        end
        local targetCount = 0
        local selected = getgenv().SelectedPlayers or {}
        for _, isActive in pairs(selected) do
            if isActive then targetCount = targetCount + 1 end
        end
        if targetCount == 0 then
            getgenv().FlingLoopActive = false
            if StartFlingBtn then
                StartFlingBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
                StartFlingBtn.Text = "⚔️ ЗАПУСТИТЬ ФЛИНГ"
            end
            continue
        end
        for targetPlayer, isActive in pairs(selected) do
            if not getgenv().FlingLoopActive or not getgenv().FlingScriptRunning then 
                break 
            end
            if not isActive or not targetPlayer or not targetPlayer.Parent then
                continue
            end
            pcall(function()
                local targetChar = targetPlayer.Character
                if not targetChar or not targetChar.Parent then return end
                local targetHRP = targetChar:FindFirstChild("HumanoidRootPart")
                if not targetHRP or not targetHRP.Parent then return end
                local myChar = LocalPlayer.Character
                if not myChar or not myChar.Parent then return end
                local myHRP = myChar:FindFirstChild("HumanoidRootPart")
                if not myHRP or not myHRP.Parent then return end
                local myHumanoid = myChar:FindFirstChildOfClass("Humanoid")
                if not myHumanoid or myHumanoid.Health <= 0 then return end
                myHumanoid.Sit = true
                applyFlingVelocity(myHRP)
                local duration = 0
                while duration < 0.4 and getgenv().FlingLoopActive and targetPlayer.Parent and targetPlayer.Character and myHumanoid.Health > 0 do
                    if not targetHRP or not targetHRP.Parent or not myHRP or not myHRP.Parent then 
                        break 
                    end
                    pcall(function()
                        myHRP.CFrame = targetHRP.CFrame * CFrame.new(0, 0, 0.05)
                    end)
                    task.wait(0.02)
                    duration = duration + 0.02
                end
                removeFlingVelocity(myHRP)
                if myHumanoid then 
                    myHumanoid.Sit = false 
                end
                task.wait(3.0)
            end)
        end
    end
end)

StartFlingBtn.MouseButton1Click:Connect(function()
    getgenv().FlingLoopActive = not getgenv().FlingLoopActive
    if getgenv().FlingLoopActive then
        StartFlingBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        StartFlingBtn.Text = "🛑 ОСТАНОВИТЬ"
    else
        StartFlingBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 200)
        StartFlingBtn.Text = "⚔️ ЗАПУСТИТЬ ФЛИНГ"
        local myChar = LocalPlayer.Character
        if myChar then
            local myHRP = myChar:FindFirstChild("HumanoidRootPart")
            removeFlingVelocity(myHRP)
        end
    end
end)

-- ===== ИСПРАВЛЕННАЯ ФУНКЦИЯ ОБНОВЛЕНИЯ СПИСКА =====
local function updateList()
    if not getgenv().FlingScriptRunning or not PlayersScroll then 
        return 
    end
    
    pcall(function()
        -- Очищаем старые кнопки
        for _, child in pairs(PlayersScroll:GetChildren()) do
            if child:IsA("TextButton") then
                child:Destroy()
            end
        end
        
        local selected = getgenv().SelectedPlayers or {}
        local players = Players:GetPlayers()
        local count = 0
        
        -- Создаём кнопки для каждого игрока
        for _, p in pairs(players) do
            if p ~= LocalPlayer and p.Parent then
                count = count + 1
                local PBtn = Instance.new("TextButton")
                PBtn.Name = p.Name
                PBtn.Size = UDim2.new(1, 0, 0, 22)
                PBtn.Font = Enum.Font.SourceSans
                PBtn.TextSize = 11
                PBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
                PBtn.Parent = PlayersScroll
                
                if selected[p] then
                    PBtn.BackgroundColor3 = Color3.fromRGB(45, 140, 45)
                    PBtn.Text = "🎯 " .. p.DisplayName
                else
                    PBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
                    PBtn.Text = p.DisplayName
                end
                
                PBtn.MouseButton1Click:Connect(function()
                    if p and p.Parent then
                        local sel = getgenv().SelectedPlayers
                        if sel[p] then
                            sel[p] = nil
                        else
                            sel[p] = true
                        end
                        updateList()
                    end
                end)
            end
        end
        
        -- Обновляем размер списка
        PlayersScroll.CanvasSize = UDim2.new(0, 0, 0, count * 25 + 10)
        
        -- Если игроков нет, показываем сообщение
        if count == 0 then
            local emptyLabel = Instance.new("TextLabel")
            emptyLabel.Parent = PlayersScroll
            emptyLabel.Size = UDim2.new(1, 0, 0, 30)
            emptyLabel.BackgroundTransparency = 1
            emptyLabel.Text = "❌ Нет игроков на сервере"
            emptyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
            emptyLabel.TextSize = 12
            emptyLabel.Font = Enum.Font.SourceSans
        end
    end)
end

ResetBtn.MouseButton1Click:Connect(function()
    getgenv().SelectedPlayers = {}
    updateList()
end)

ReloadBtn.MouseButton1Click:Connect(function()
    CleanupExisting()
    print("✅ Перезагружено!")
end)

Players.PlayerAdded:Connect(updateList)
Players.PlayerRemoving:Connect(function(p)
    if getgenv().SelectedPlayers then
        getgenv().SelectedPlayers[p] = nil
    end
    updateList()
end)

task.spawn(function()
    while getgenv().FlingScriptRunning do
        task.wait(1.0)
        updateList()
    end
end)

updateList()
print("✅ FLING VNMA ЗАПУЩЕН!")
