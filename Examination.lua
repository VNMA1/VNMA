local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================

local SHOW_HITBOX = true
local SHOW_HEALTH = true

local MAX_DISTANCE = 500

-- Ключевые слова в названиях враждебных NPC
local HOSTILE_KEYWORDS = {
	-- Основные заражённые
	"lurker",
	"crawler",
	"riser",
	"kamikaze",
	"shielder",
	"slasher",
	"gunner",
	"fury",
	"deceiver",
	"mutant",
	"radaway",
	"engineer",

	-- Варианты Lurker / заражённых
	"welder",
	"rsu",
	"mms",
	"hpca",
	"rif ozk",

	-- Viral
	"viral runner",
	"viral executioner",
	"viral leader",
	"viral enforcer",

	-- Rasonian
	"infantryman",
	"combat medic",
	"shotgunner",
	"machine gunner",

	-- Особые враги
	"d-zero",
	"dzero",
	"chimera",
	"gilbert",
	"sinitzyn",
	"sin",
	"cerberus",

	-- Дополнительные боссы / мини-боссы
	"mikhail",
	"mikhail william",
	"yakov",
	"yakov zhukov",
	"dave",
	"vorax",
}

-- =========================================================
-- PLAYER CHECK
-- =========================================================

local function isPlayerCharacter(model)
	if not model or not model:IsA("Model") then
		return false
	end

	return Players:GetPlayerFromCharacter(model) ~= nil
end

-- =========================================================
-- ПОИСК НАСТОЯЩЕЙ МОДЕЛИ NPC
-- =========================================================

local function getNPCModel(obj)
	local current = obj

	while current and current ~= Workspace do
		if current:IsA("Model") then
			if current:FindFirstChildOfClass("Humanoid") then
				return current
			end
		end

		current = current.Parent
	end

	return nil
end

-- =========================================================
-- ПРОВЕРКА ИМЕНИ
-- =========================================================

local function containsHostileKeyword(name)
	name = string.lower(name)

	for _, keyword in ipairs(HOSTILE_KEYWORDS) do
		if string.find(name, keyword, 1, true) then
			return true
		end
	end

	return false
end

local function isHostileNPC(model)
	if not model or not model:IsA("Model") then
		return false
	end

	-- Игроков никогда не трогаем
	if isPlayerCharacter(model) then
		return false
	end

	-- Нужен Humanoid
	if not model:FindFirstChildOfClass("Humanoid") then
		return false
	end

	-- Проверяем имя
	return containsHostileKeyword(model.Name)
end

-- =========================================================
-- ROOT
-- =========================================================

local function getRootPart(model)
	return model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
end

-- =========================================================
-- HITBOX VISUAL
-- =========================================================

local function createHitboxVisual(model)
	if not SHOW_HITBOX then
		return
	end

	if model:FindFirstChild("NPC_HitboxVisual") then
		return
	end

	local root = getRootPart(model)
	if not root then
		return
	end

	local boxCFrame, boxSize = model:GetBoundingBox()

	local box = Instance.new("BoxHandleAdornment")
	box.Name = "NPC_HitboxVisual"

	box.Adornee = root
	box.AlwaysOnTop = true
	box.ZIndex = 5

	box.Size = boxSize
	box.CFrame = root.CFrame:ToObjectSpace(boxCFrame)

	box.Transparency = 0.75
	box.Color3 = Color3.fromRGB(255, 255, 255)

	box.Parent = model
end

-- =========================================================
-- HEALTH DISPLAY
-- =========================================================

local function createHealthDisplay(model, humanoid)
	if not SHOW_HEALTH then
		return
	end

	if model:FindFirstChild("NPC_HealthDisplay") then
		return
	end

	local root = getRootPart(model)
	if not root then
		return
	end

	local _, size = model:GetBoundingBox()

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NPC_HealthDisplay"
	billboard.Adornee = root

	billboard.Size = UDim2.fromOffset(180, 45)
	billboard.StudsOffset = Vector3.new(0, size.Y / 2 + 2, 0)

	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MAX_DISTANCE

	billboard.Parent = model

	local text = Instance.new("TextLabel")
	text.Name = "HealthText"

	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1

	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0

	text.Font = Enum.Font.GothamBold

	-- Только уменьшаем шрифт
	text.TextScaled = false
	text.TextSize = 12

	text.Parent = billboard

	local function updateHealth()
		local hp = humanoid.Health
		local maxHp = humanoid.MaxHealth

		text.Text = string.format(
			"HP: %d / %d",
			math.max(0, math.round(hp)),
			math.max(0, math.round(maxHp))
		)

		if maxHp > 0 then
			local percent = hp / maxHp

			if percent <= 0.25 then
				text.TextColor3 = Color3.fromRGB(255, 60, 60)
			elseif percent <= 0.5 then
				text.TextColor3 = Color3.fromRGB(255, 220, 60)
			else
				text.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end

	updateHealth()

	humanoid.HealthChanged:Connect(function()
		if text.Parent then
			updateHealth()
		end
	end)

	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if text.Parent then
			updateHealth()
		end
	end)
end

-- =========================================================
-- HIGHLIGHT
-- =========================================================

local function createHighlight(model)
	if model:FindFirstChild("NPC_Highlight") then
		return
	end

	local highlight = Instance.new("Highlight")

	highlight.Name = "NPC_Highlight"

	highlight.FillColor = Color3.fromRGB(255, 0, 0)
	highlight.OutlineColor = Color3.fromRGB(255, 255, 255)

	highlight.FillTransparency = 0.45
	highlight.OutlineTransparency = 0

	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

	highlight.Parent = model
end

-- =========================================================
-- SETUP
-- =========================================================

local function setupNPC(model)
	if not isHostileNPC(model) then
		return
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	createHighlight(model)
	createHitboxVisual(model)
	createHealthDisplay(model, humanoid)
end

-- =========================================================
-- СУЩЕСТВУЮЩИЕ
-- =========================================================

for _, obj in ipairs(Workspace:GetDescendants()) do
	local model = getNPCModel(obj)

	if model then
		setupNPC(model)
	end
end

-- =========================================================
-- НОВЫЕ
-- =========================================================

Workspace.DescendantAdded:Connect(function(obj)
	task.defer(function()
		local model = getNPCModel(obj)

		if model then
			setupNPC(model)
		end
	end)
end)
