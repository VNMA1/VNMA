-- [[ СКРИПТ: Телепорт к игроку по нику (MM2 / любая игра) ]]
-- [[ Обходит блокировку друзей, работает на общих серверах ]]

-- Создаём GUI
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Проверяем, есть ли уже такое окно
local existingGui = player.PlayerGui:FindFirstChild("TeleportGUI")
if existingGui then existingGui:Destroy() end

-- Создаём ScreenGui
local gui = Instance.new("ScreenGui")
gui.Name = "TeleportGUI"
gui.Parent = player.PlayerGui

-- Фон
local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 300, 0, 150)
frame.Position = UDim2.new(0.5, -150, 0.5, -75)
frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
frame.BackgroundTransparency = 0.8
frame.BorderSizePixel = 0
frame.Parent = gui

-- Заголовок
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 30)
title.Position = UDim2.new(0, 0, 0, 0)
title.Text = "Телепорт к игроку"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.TextScaled = true
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Parent = frame

-- Поле ввода
local textBox = Instance.new("TextBox")
textBox.Size = UDim2.new(0.8, 0, 0, 30)
textBox.Position = UDim2.new(0.1, 0, 0, 40)
textBox.PlaceholderText = "Введите ник игрока"
textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
textBox.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
textBox.BorderSizePixel = 0
textBox.Font = Enum.Font.Gotham
textBox.TextSize = 16
textBox.Parent = frame

-- Кнопка
local button = Instance.new("TextButton")
button.Size = UDim2.new(0.6, 0, 0, 35)
button.Position = UDim2.new(0.2, 0, 0, 85)
button.Text = "Телепорт"
button.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
button.BorderSizePixel = 0
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Font = Enum.Font.GothamBold
button.TextSize = 18
button.Parent = frame

-- Закрыть по ESC
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.Escape then
        gui:Destroy()
    end
end)

-- Функция для запроса к API
local function getUserIdByUsername(username)
    local url = "https://api.roblox.com/users/get-by-username?username=" .. username
    local success, response = pcall(function()
        return game:GetService("HttpService"):GetAsync(url)
    end)
    if success then
        local data = HttpService:JSONDecode(response)
        if data and data.Id then
            return data.Id
        end
    end
    return nil
end

local function getPresence(userId)
    local url = "https://presence.roblox.com/v1/presence/users"
    local body = HttpService:JSONEncode({ userIds = { userId } })
    local headers = { ["Content-Type"] = "application/json" }
    local success, response = pcall(function()
        return game:GetService("HttpService"):PostAsync(url, body, Enum.HttpContentType.ApplicationJson, false, headers)
    end)
    if success then
        local data = HttpService:JSONDecode(response)
        if data and data.userPresences and #data.userPresences > 0 then
            local presence = data.userPresences[1]
            if presence and presence.placeId and presence.gameId then
                return presence.placeId, presence.gameId -- gameId это JobId
            end
        end
    end
    return nil, nil
end

-- Обработчик кнопки
button.MouseButton1Click:Connect(function()
    local username = textBox.Text
    if username == "" then
        print("Введите ник!")
        return
    end

    -- Ищем на текущем сервере
    local target = nil
    for _, p in pairs(Players:GetPlayers()) do
        if string.lower(p.Name) == string.lower(username) or string.lower(p.DisplayName) == string.lower(username) then
            target = p
            break
        end
    end

    if target then
        -- Если на этом сервере — телепортируем к нему
        if target.Character and target.Character:FindFirstChild("HumanoidRootPart") then
            local myChar = player.Character
            if myChar and myChar:FindFirstChild("HumanoidRootPart") then
                myChar.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 2, 0)
                print("Телепортировался к " .. target.Name)
                gui:Destroy()
                return
            end
        end
        print("Игрок есть на сервере, но персонажа нет")
        return
    end

    -- Если не на текущем сервере — ищем через API
    print("Ищем игрока через API...")
    local userId = getUserIdByUsername(username)
    if not userId then
        print("Пользователь не найден")
        return
    end

    local placeId, jobId = getPresence(userId)
    if placeId and jobId then
        print("Найден сервер: PlaceId=" .. placeId .. ", JobId=" .. jobId)
        -- Телепортируемся на сервер
        TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
        gui:Destroy()
    else
        print("Игрок не в игре или сервер недоступен")
    end
end)

print("Готово! Введи ник и нажми 'Телепорт'")
