local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local stringFind = string.find
local mathFloor = math.floor
local taskWait = task.wait

local lootCache = {}

local StorageFolder = CoreGui:FindFirstChild("__CrimLootStorage")
if StorageFolder then StorageFolder:Destroy() end
StorageFolder = Instance.new("Folder")
StorageFolder.Name = "__CrimLootStorage"
StorageFolder.Parent = CoreGui

local LOOT_CONFIG = {
    ["register"]    = {text = "💰 Касса", color = Color3.fromRGB(0, 255, 100), isStatic = true, maxDist = 500},
    ["smallsafe"]   = {text = "🔓 Сейф (М)", color = Color3.fromRGB(0, 180, 255), isStatic = true, maxDist = 500},
    ["bigsafe"]     = {text = "💎 СЕЙФ (Б)", color = Color3.fromRGB(255, 0, 120), isStatic = true, maxDist = 500},
    ["largesafe"]   = {text = "💎 СЕЙФ (Б)", color = Color3.fromRGB(255, 0, 120), isStatic = true, maxDist = 500},
    ["supersafe"]   = {text = "💎 СЕЙФ (Б)", color = Color3.fromRGB(255, 0, 120), isStatic = true, maxDist = 500},
    ["atm"]         = {text = "🏧 Банкомат", color = Color3.fromRGB(255, 165, 0), isStatic = true, maxDist = 500},
    ["safe"]        = {text = "💎 СЕЙФ", color = Color3.fromRGB(255, 0, 120), isStatic = true, maxDist = 500},
    ["dealer"]      = {text = "👤 ТОРГОВЕЦ", color = Color3.fromRGB(255, 255, 255), isStatic = false, maxDist = 300},
    ["scrap"]       = {text = "♻️ Мусор (Скрап)", color = Color3.fromRGB(30, 100, 255), isStatic = false, maxDist = 80}
}

-- Глобальный черный список слов в названиях (Защита от стен, блоков и оружия)
local EXPANDED_IGNORED_KEYWORDS = {
    "wall", "floor", "ceiling", "ground", "roof", "brick", "concrete", "structure", "building", "wallpart",
    "zone", "area", "sky", "glass", "door", "window", "hitbox", "collider", "collision", "trigger", "bound",
    "shadow", "light", "effect", "particle", "meshpart", "wedgepart", "cornerwedgepart", "trusspart", "spawnlocation",
    "bat", "weapon", "melee", "tool", "gun", "sword", "knife", "pistol", "riffle", "ammo", "bullet", "arm", "leg", "torso"
}

local function GetLootConfig(nameLower, obj)
    -- Жесткий фильтр: если объект прозрачный (невидимый блок/зона коллизии), игнорируем его
    if obj:IsA("BasePart") and (obj.Transparency >= 0.9 or not obj.CanCollide and obj.Size.Magnitude > 10) then
        return nil
    end

    -- СТРОГАЯ ПРОВЕРКА РАЗМЕРОВ (Защита от стен и гигантских блоков)
    if obj:IsA("BasePart") then
        local size = obj.Size
        
        -- Сейфы и кассы в игре — это компактные 3D-модели (обычно до ~3.5 studs, около 1.5 - 2 метров).
        -- Если блок по любой из осей длиннее 6 studs (около 2-3 метров), это 100% кусок стены или здания.
        if size.X > 6 or size.Y > 6 or size.Z > 6 then
            return nil -- Объект слишком большой, блокируем ESP
        end
        
        -- Специфический фильтр для мелкого скрапа/мусора (он еще меньше)
        if stringFind(nameLower, "scrap") or stringFind(nameLower, "мусор") then
            if size.X > 3 or size.Y > 3 or size.Z > 3 then
                return nil 
            end
        end
    end

    local direct = LOOT_CONFIG[nameLower]
    if direct then return direct end
    
    if stringFind(nameLower, "register") then return LOOT_CONFIG["register"] end
    if stringFind(nameLower, "atm") then return LOOT_CONFIG["atm"] end

    if stringFind(nameLower, "safe") then
        return LOOT_CONFIG["safe"]
    end
    
    if stringFind(nameLower, "dealer") then return LOOT_CONFIG["dealer"] end
    if stringFind(nameLower, "scrap") then return LOOT_CONFIG["scrap"] end
    
    return nil
end

local function TargetCheck(obj)
    -- Фильтр неподходящих классов (декали, звуки, скрипты внутри моделей)
    if not (obj:IsA("Model") or obj:IsA("MeshPart") or obj:IsA("BasePart")) then return end

    local nameLower = obj.Name:lower()
    
    -- Проверка по черному списку ключевых слов
    for i = 1, #EXPANDED_IGNORED_KEYWORDS do
        if stringFind(nameLower, EXPANDED_IGNORED_KEYWORDS[i]) then
            return 
        end
    end
    
    -- Проверка родителей (чтобы отсечь лут в руках игроков или элементы зданий)
    local parent = obj.Parent
    if parent then
        local pName = parent.Name:lower()
        if parent:IsA("Backpack") or parent:IsA("Accessory") or parent:IsA("Tool") then return end
        
        for i = 1, #EXPANDED_IGNORED_KEYWORDS do
            if stringFind(pName, EXPANDED_IGNORED_KEYWORDS[i]) then return end
        end

        if parent.Parent and parent.Parent:FindFirstChildOfClass("Humanoid") then return end
    end

    local config = GetLootConfig(nameLower, obj)
    if config then
        -- Дополнительная проверка: берем физическую часть объекта
        local rootPart = obj:IsA("BasePart") and obj or (obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart"))
        if not rootPart then return end
        
        -- Если у родительской модели в имени есть признаки карты — отменяем
        if obj.Parent and stringFind(obj.Parent.Name:lower(), "map") then return end

        -- Создаем ESP только если проверки пройдены
        if not lootCache[obj] then
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "__CrimLootESP"
            billboard.AlwaysOnTop = true
            billboard.Size = UDim2.new(0, 160, 0, 30)
            billboard.StudsOffset = Vector3.new(0, 2.5, 0) -- Красиво парит НАД объектом
            billboard.Adornee = rootPart
            billboard.Parent = StorageFolder

            local label = Instance.new("TextLabel")
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.Font = Enum.Font.RobotoMono
            label.TextSize = 11
            label.TextColor3 = config.color
            label.TextStrokeTransparency = 0.1
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.Parent = billboard

            local highlight = Instance.new("Highlight")
            highlight.Name = "__CrimLootChams"
            highlight.FillColor = config.color
            highlight.FillTransparency = 0.4
            highlight.OutlineColor = Color3.new(1, 1, 1)
            highlight.OutlineTransparency = 0.2
            highlight.Adornee = obj
            highlight.Parent = StorageFolder

            lootCache[obj] = {
                label = label, 
                highlight = highlight, 
                billboard = billboard,
                baseText = config.text, 
                isStatic = config.isStatic, 
                maxDist = config.maxDist,
                defaultColor = config.color,
                targetPart = rootPart,
                lastDist = -1,
                lastBroken = false
            }
        end
    end
end

Workspace.DescendantAdded:Connect(function(desc)
    TargetCheck(desc)
end)

task.spawn(function()
    local allCurrent = Workspace:GetDescendants()
    for i = 1, #allCurrent do
        if i % 150 == 0 then task.wait() end 
        local obj = allCurrent[i]
        if obj and obj.Parent then
            TargetCheck(obj)
        end
    end
    allCurrent = nil
end)

task.spawn(function()
    while true do
        for obj, data in pairs(lootCache) do
            if not obj or not obj.Parent or not data.targetPart or not data.targetPart.Parent then
                if data.billboard then data.billboard:Destroy() end
                if data.highlight then data.highlight:Destroy() end
                lootCache[obj] = nil
            end
        end
        taskWait(5.0)
    end
end)

task.spawn(function()
    while true do
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")

        if hrp then
            local myPos = hrp.Position
            for obj, data in pairs(lootCache) do
                if obj and obj.Parent and data.targetPart and data.targetPart.Parent then
                    local dist = mathFloor((myPos - data.targetPart.Position).Magnitude)
                    
                    if dist <= data.maxDist then
                        data.billboard.Enabled = true
                        data.highlight.Enabled = true
                        
                        local isBroken = false
                        if data.isStatic then
                            local values = obj:FindFirstChild("Values")
                            local brokenObj = values and values:FindFirstChild("Broken")
                            isBroken = brokenObj and brokenObj.Value == true
                        end
                        
                        if dist ~= data.lastDist or isBroken ~= data.lastBroken then
                            data.lastDist = dist
                            data.lastBroken = isBroken
                            
                            local activeColor = isBroken and Color3.fromRGB(130, 35, 35) or data.defaultColor
                            data.label.TextColor3 = activeColor
                            data.highlight.FillColor = activeColor
                            
                            local status = data.isStatic and (isBroken and " [ВЗЛОМАН]" or "") or ""
                            data.label.Text = string.format("%s%s\n[%dм]", data.baseText, status, dist)
                        end
                    else
                        data.billboard.Enabled = false
                        data.highlight.Enabled = false
                    end
                end
            end
        end
        taskWait(0.2)
    end
end)
