--!nocheck
-- VNMA TELEPORT FINDER | MOBILE REWORK
-- Поиск игрока по Username / DisplayName
-- Текущий сервер + поиск сервера игрока (Presence API + fallback)
-- Mobile-friendly GUI

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- GLOBAL STATE
----------------------------------------------------------------

getgenv().TeleportFinderRunning = false
getgenv().TeleportFinderActive = false
getgenv().TeleportFinderGui = nil
getgenv().TeleportFinderConnections = {}

----------------------------------------------------------------
-- CLEAN OLD VERSION
----------------------------------------------------------------

pcall(function()
    for _, connection in pairs(getgenv().TeleportFinderConnections) do
        if connection then
            connection:Disconnect()
        end
    end
end)

getgenv().TeleportFinderConnections = {}

local oldGui = nil

pcall(function()
    oldGui = LocalPlayer
        :WaitForChild("PlayerGui")
        :FindFirstChild("VNMA_TeleportFinder")
end)

if oldGui then
    pcall(function()
        oldGui:Destroy()
    end)
end

getgenv().TeleportFinderRunning = true

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "VNMA_TeleportFinder"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

getgenv().TeleportFinderGui = gui

----------------------------------------------------------------
-- BACKGROUND
----------------------------------------------------------------

local background = Instance.new("Frame")
background.Parent = gui
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(5, 7, 10)
background.BackgroundTransparency = 0.2
background.BorderSizePixel = 0

----------------------------------------------------------------
-- MAIN WINDOW
----------------------------------------------------------------

local frame = Instance.new("Frame")
frame.Parent = gui
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.fromScale(0.5, 0.5)
frame.Size = UDim2.fromScale(0.94, 0.78)
frame.BackgroundColor3 = Color3.fromRGB(20, 24, 32)
frame.BorderSizePixel = 0
frame.ClipsDescendants = true

local frameCorner = Instance.new("UICorner")
frameCorner.CornerRadius = UDim.new(0, 18)
frameCorner.Parent = frame

local frameStroke = Instance.new("UIStroke")
frameStroke.Color = Color3.fromRGB(65, 75, 95)
frameStroke.Thickness = 1.5
frameStroke.Transparency = 0.15
frameStroke.Parent = frame

----------------------------------------------------------------
-- HEADER
----------------------------------------------------------------

local header = Instance.new("Frame")
header.Parent = frame
header.Size = UDim2.new(1, 0, 0, 82)
header.BackgroundColor3 = Color3.fromRGB(27, 32, 43)
header.BorderSizePixel = 0

local title = Instance.new("TextLabel")
title.Parent = header
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 20, 0, 10)
title.Size = UDim2.new(1, -100, 0, 34)
title.Font = Enum.Font.GothamBold
title.Text = "⚡ TELEPORT FINDER"
title.TextColor3 = Color3.fromRGB(245, 248, 255)
title.TextSize = 21
title.TextXAlignment = Enum.TextXAlignment.Left

local subtitle = Instance.new("TextLabel")
subtitle.Parent = header
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 21, 0, 45)
subtitle.Size = UDim2.new(1, -100, 0, 22)
subtitle.Font = Enum.Font.Code
subtitle.Text = "VNMA"
subtitle.TextColor3 = Color3.fromRGB(80, 215, 255)
subtitle.TextSize = 13
subtitle.TextXAlignment = Enum.TextXAlignment.Left

----------------------------------------------------------------
-- CLOSE
----------------------------------------------------------------

local closeButton = Instance.new("TextButton")
closeButton.Parent = header
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -14, 0.5, 0)
closeButton.Size = UDim2.new(0, 48, 0, 48)
closeButton.BackgroundColor3 = Color3.fromRGB(170, 55, 60)
closeButton.BorderSizePixel = 0
closeButton.Font = Enum.Font.GothamBold
closeButton.Text = "×"
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.TextSize = 28
closeButton.AutoButtonColor = true

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(0, 14)
closeCorner.Parent = closeButton

----------------------------------------------------------------
-- CONTENT
----------------------------------------------------------------

local content = Instance.new("Frame")
content.Parent = frame
content.BackgroundTransparency = 1
content.Position = UDim2.new(0, 16, 0, 96)
content.Size = UDim2.new(1, -32, 1, -112)

----------------------------------------------------------------
-- INPUT
----------------------------------------------------------------

local textBox = Instance.new("TextBox")
textBox.Parent = content
textBox.Position = UDim2.new(0, 0, 0, 0)
textBox.Size = UDim2.new(1, 0, 0, 52)
textBox.BackgroundColor3 = Color3.fromRGB(12, 16, 23)
textBox.BorderSizePixel = 0
textBox.Font = Enum.Font.Gotham
textBox.PlaceholderText = "Введите Username или DisplayName"
textBox.PlaceholderColor3 = Color3.fromRGB(125, 132, 145)
textBox.Text = ""
textBox.TextColor3 = Color3.fromRGB(245, 245, 245)
textBox.TextSize = 15
textBox.ClearTextOnFocus = false

local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 12)
inputCorner.Parent = textBox

local inputStroke = Instance.new("UIStroke")
inputStroke.Color = Color3.fromRGB(55, 65, 82)
inputStroke.Thickness = 1
inputStroke.Parent = textBox

----------------------------------------------------------------
-- STATUS
----------------------------------------------------------------

local statusLabel = Instance.new("TextLabel")
statusLabel.Parent = content
statusLabel.Position = UDim2.new(0, 3, 0, 61)
statusLabel.Size = UDim2.new(1, -6, 0, 52)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Gotham
statusLabel.Text = "Статус: выключено"
statusLabel.TextColor3 = Color3.fromRGB(170, 175, 190)
statusLabel.TextSize = 14
statusLabel.TextWrapped = true
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

----------------------------------------------------------------
-- BUTTON FACTORY
----------------------------------------------------------------

local function createButton(parent, text, position, size)
    local button = Instance.new("TextButton")

    button.Parent = parent
    button.Position = position
    button.Size = size
    button.BackgroundColor3 = Color3.fromRGB(40, 47, 61)
    button.BorderSizePixel = 0
    button.Font = Enum.Font.GothamBold
    button.Text = text
    button.TextColor3 = Color3.fromRGB(245, 245, 245)
    button.TextSize = 14
    button.AutoButtonColor = true

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = button

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(70, 80, 100)
    stroke.Thickness = 1
    stroke.Transparency = 0.2
    stroke.Parent = button

    return button
end

----------------------------------------------------------------
-- ACTIVATE
----------------------------------------------------------------

local activateButton = createButton(
    content,
    "🔴  АКТИВИРОВАТЬ",
    UDim2.new(0, 0, 0, 118),
    UDim2.new(0.48, -4, 0, 50)
)

----------------------------------------------------------------
-- TELEPORT
----------------------------------------------------------------

local teleportButton = createButton(
    content,
    "⚡  НАЙТИ И ТЕЛЕПОРТИРОВАТЬ",
    UDim2.new(0.52, 4, 0, 118),
    UDim2.new(0.48, -4, 0, 50)
)

teleportButton.BackgroundColor3 = Color3.fromRGB(45, 95, 185)

----------------------------------------------------------------
-- INFO
----------------------------------------------------------------

local infoLabel = Instance.new("TextLabel")
infoLabel.Parent = content
infoLabel.Position = UDim2.new(0, 4, 0, 180)
infoLabel.Size = UDim2.new(1, -8, 1, -238)
infoLabel.BackgroundTransparency = 1
infoLabel.Font = Enum.Font.Gotham
infoLabel.Text = "Введите ник игрока.\n\nСкрипт сначала проверит текущий сервер.\nЕсли игрока здесь нет — запросит его сервер через Presence API."
infoLabel.TextColor3 = Color3.fromRGB(165, 172, 188)
infoLabel.TextSize = 14
infoLabel.TextWrapped = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.TextYAlignment = Enum.TextYAlignment.Top

----------------------------------------------------------------
-- HIDE
----------------------------------------------------------------

local hideButton = createButton(
    content,
    "👁️  Скрыть",
    UDim2.new(0, 0, 1, -50),
    UDim2.new(0.48, -4, 0, 44)
)

----------------------------------------------------------------
-- SHOW BUTTON
----------------------------------------------------------------

local showButton = Instance.new("TextButton")
showButton.Parent = gui
showButton.AnchorPoint = Vector2.new(1, 1)
showButton.Position = UDim2.new(1, -15, 1, -15)
showButton.Size = UDim2.new(0, 70, 0, 70)
showButton.BackgroundColor3 = Color3.fromRGB(27, 32, 43)
showButton.BorderSizePixel = 0
showButton.Font = Enum.Font.GothamBold
showButton.Text = "⚡\nVNMA"
showButton.TextColor3 = Color3.fromRGB(255, 215, 80)
showButton.TextSize = 15
showButton.Visible = false
showButton.ZIndex = 50

local showCorner = Instance.new("UICorner")
showCorner.CornerRadius = UDim.new(0, 18)
showCorner.Parent = showButton

local showStroke = Instance.new("UIStroke")
showStroke.Color = Color3.fromRGB(255, 215, 80)
showStroke.Thickness = 2
showStroke.Parent = showButton

----------------------------------------------------------------
-- HIDE / SHOW
----------------------------------------------------------------

local function setHidden(hidden)
    getgenv().TeleportFinderGuiHidden = hidden

    frame.Visible = not hidden
    background.Visible = not hidden
    showButton.Visible = hidden
end

closeButton.Activated:Connect(function()
    setHidden(true)
end)

hideButton.Activated:Connect(function()
    setHidden(true)
end)

showButton.Activated:Connect(function()
    setHidden(false)
end)

----------------------------------------------------------------
-- MOBILE DRAG
----------------------------------------------------------------

local dragging = false
local dragStart
local startPosition

header.InputBegan:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = input.Position
        startPosition = frame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)

    if not dragging then
        return
    end

    if input.UserInputType ~= Enum.UserInputType.MouseMovement
    and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    local delta = input.Position - dragStart

    frame.Position = UDim2.new(
        startPosition.X.Scale,
        startPosition.X.Offset + delta.X,
        startPosition.Y.Scale,
        startPosition.Y.Offset + delta.Y
    )
end)

UserInputService.InputEnded:Connect(function(input)

    if input.UserInputType == Enum.UserInputType.MouseButton1
    or input.UserInputType == Enum.UserInputType.Touch then

        dragging = false
    end
end)

----------------------------------------------------------------
-- ACTIVATION
----------------------------------------------------------------

local function setActive(active)

    getgenv().TeleportFinderActive = active

    if active then
        activateButton.BackgroundColor3 = Color3.fromRGB(50, 155, 80)
        activateButton.Text = "🟢  АКТИВИРОВАНО"

        statusLabel.Text = "Статус: активно"
        statusLabel.TextColor3 = Color3.fromRGB(100, 230, 130)
    else
        activateButton.BackgroundColor3 = Color3.fromRGB(170, 55, 60)
        activateButton.Text = "🔴  АКТИВИРОВАТЬ"

        statusLabel.Text = "Статус: выключено"
        statusLabel.TextColor3 = Color3.fromRGB(190, 150, 150)
    end
end

activateButton.Activated:Connect(function()
    setActive(not getgenv().TeleportFinderActive)
end)

----------------------------------------------------------------
-- FIND CURRENT SERVER PLAYER
----------------------------------------------------------------

local function findCurrentPlayer(username)

    username = string.lower(username)

    for _, target in ipairs(Players:GetPlayers()) do

        if target ~= LocalPlayer then

            if string.lower(target.Name) == username
            or string.lower(target.DisplayName) == username then

                return target
            end
        end
    end

    return nil
end

----------------------------------------------------------------
-- GET USER ID
----------------------------------------------------------------

local function getUserId(username)

    local success, result = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)

    if success and typeof(result) == "number" then
        return result
    end

    return nil
end

----------------------------------------------------------------
-- HTTP HELPERS (request / HttpService fallback)
----------------------------------------------------------------

-- Ищем доступный executor-request
local httpRequest = (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or (krnl and krnl.request)
    or (secure_call and request)
    or (typeof(request) == "function" and request)
    or nil

local function httpPost(url, bodyTable, headers)
    local body = HttpService:JSONEncode(bodyTable)
    local finalHeaders = headers or {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
    }

    -- 1) executor request (работает чаще всего)
    if httpRequest then
        local ok, res = pcall(function()
            return httpRequest({
                Url = url,
                Method = "POST",
                Headers = finalHeaders,
                Body = body
            })
        end)

        if ok and type(res) == "table" and (res.Body or res.body) then
            local code = res.StatusCode or res.Status or 200
            return {
                Success = code < 400,
                StatusCode = code,
                Body = res.Body or res.body
            }
        end
    end

    -- 2) HttpService
    local ok, res = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = finalHeaders,
            Body = body
        })
    end)

    if ok and res then
        return res
    end

    return nil, tostring(res)
end

----------------------------------------------------------------
-- FIND OTHER PLAYER SERVER (Presence API + fallback)
----------------------------------------------------------------

local function findPlayerServer(userId)

    -- Прокси → прямой домен
    local endpoints = {
        "https://presence.roproxy.com/v1/presence/users",
        "https://presence.roblox.com/v1/presence/users",
        "https://presence.rprxy.xyz/v1/presence/users",
    }

    local lastError = "нет соединения"

    for _, url in ipairs(endpoints) do

        local response, reqErr = httpPost(url, { userIds = { userId } })

        if not response then
            lastError = tostring(reqErr)
            continue
        end

        if not response.Success then
            lastError = "код " .. tostring(response.StatusCode)
            continue
        end

        local ok, data = pcall(function()
            return HttpService:JSONDecode(response.Body)
        end)

        if not ok or not data then
            lastError = "не удалось разобрать ответ"
            continue
        end

        local presence = data.userPresences and data.userPresences[1]

        if not presence then
            return nil, nil, "Игрок не в сети."
        end

        -- 0 = Offline, 1 = Online (меню), 2 = In Game, 3 = In Studio
        if presence.userPresenceType ~= 2 then
            return nil, nil, "Игрок не в игре (статус: "
                .. tostring(presence.userPresenceType) .. ")."
        end

        local placeId = presence.placeId
        local jobId   = presence.gameId

        if not placeId or not jobId or jobId == "" then
            return nil, nil, "Игрок скрыл свой сервер (приватность)."
        end

        return placeId, jobId, nil
    end

    return nil, nil, "HTTP недоступен: " .. lastError
end

----------------------------------------------------------------
-- TELEPORT
----------------------------------------------------------------

local function performTeleport()

    if not getgenv().TeleportFinderActive then
        statusLabel.Text = "Сначала нажми «АКТИВИРОВАТЬ»."
        statusLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
        return
    end

    local username = textBox.Text:gsub("^%s+", ""):gsub("%s+$", "")

    if username == "" then
        statusLabel.Text = "Введите Username или DisplayName."
        statusLabel.TextColor3 = Color3.fromRGB(255, 170, 90)
        return
    end

    statusLabel.Text = "🔎 Ищу игрока..."
    statusLabel.TextColor3 = Color3.fromRGB(120, 190, 255)

    ----------------------------------------------------------------
    -- CURRENT SERVER
    ----------------------------------------------------------------

    local currentTarget = findCurrentPlayer(username)

    if currentTarget then

        local targetCharacter = currentTarget.Character
        local targetRoot =
            targetCharacter
            and targetCharacter:FindFirstChild("HumanoidRootPart")

        local myCharacter = LocalPlayer.Character
        local myRoot =
            myCharacter
            and myCharacter:FindFirstChild("HumanoidRootPart")

        if targetRoot and myRoot then

            pcall(function()
                myRoot.CFrame =
                    targetRoot.CFrame
                    * CFrame.new(0, 3, 0)
            end)

            statusLabel.Text =
                "✅ " .. currentTarget.DisplayName ..
                "\nИгрок найден на текущем сервере."

            statusLabel.TextColor3 = Color3.fromRGB(100, 230, 130)

            return
        end
    end

    ----------------------------------------------------------------
    -- OTHER SERVER (Presence API)
    ----------------------------------------------------------------

    statusLabel.Text = "🌐 Игрок не на этом сервере.\nЗапрашиваю Presence API..."
    statusLabel.TextColor3 = Color3.fromRGB(120, 190, 255)

    local userId = getUserId(username)

    if not userId then
        statusLabel.Text = "❌ Username не найден."
        statusLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
        return
    end

    local placeId, jobId, errorMessage = findPlayerServer(userId)

    if not placeId or not jobId then

        statusLabel.Text =
            "❌ Не удалось получить сервер игрока.\n" ..
            (errorMessage or "Неизвестная ошибка.")

        statusLabel.TextColor3 = Color3.fromRGB(255, 110, 110)

        return
    end

    statusLabel.Text =
        "✅ Сервер найден.\n🚀 Выполняю телепорт..."

    statusLabel.TextColor3 = Color3.fromRGB(100, 230, 130)

    local success, teleportError = pcall(function()
        TeleportService:TeleportToPlaceInstance(
            placeId,
            jobId,
            LocalPlayer
        )
    end)

    if not success then

        statusLabel.Text =
            "❌ Ошибка телепорта:\n" ..
            tostring(teleportError)

        statusLabel.TextColor3 = Color3.fromRGB(255, 110, 110)

        return
    end

    task.wait(2)

    setHidden(true)
end

teleportButton.Activated:Connect(performTeleport)

----------------------------------------------------------------
-- ENTER KEY
----------------------------------------------------------------

UserInputService.InputBegan:Connect(function(input, processed)

    if processed then
        return
    end

    if input.KeyCode == Enum.KeyCode.Return
    or input.KeyCode == Enum.KeyCode.KeypadEnter then

        performTeleport()
    end
end)

----------------------------------------------------------------
-- TELEPORT ERROR
----------------------------------------------------------------

getgenv().TeleportFinderConnections.TeleportFailed =
    TeleportService.TeleportInitFailed:Connect(
        function(player, result, errorMessage)

            if player ~= LocalPlayer then
                return
            end

            statusLabel.Text =
                "❌ Телепорт не удался:\n" ..
                tostring(result) ..
                "\n" ..
                tostring(errorMessage)

            statusLabel.TextColor3 =
                Color3.fromRGB(255, 110, 110)
        end
    )

----------------------------------------------------------------
-- ESC
----------------------------------------------------------------

getgenv().TeleportFinderConnections.Input =
    UserInputService.InputBegan:Connect(
        function(input, processed)

            if processed then
                return
            end

            if input.KeyCode == Enum.KeyCode.Escape then
                setHidden(not getgenv().TeleportFinderGuiHidden)
            end
        end
    )

----------------------------------------------------------------
-- START
----------------------------------------------------------------

setActive(false)

print("✅ VNMA TELEPORT FINDER загружен")
print("🔴 Статус: выключено")
print("📱 Mobile UI: ON")
print("🌐 Поиск сервера: Presence API + fallback")
