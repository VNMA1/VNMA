local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================

local SHOW_HITBOX = true
local SHOW_HEALTH = true

local MAX_DISTANCE = 300

-- НОВОЕ: переключатели
local SHOW_INFECTED = true
local SHOW_ALLIES = false

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
-- НОВОЕ: ОЧИСТКА ЗАРАЖЁННОГО
-- =========================================================

local function removeNPCVisuals(model)
	if not model then
		return
	end

	for _, name in ipairs({
		"NPC_Highlight",
		"NPC_HitboxVisual",
		"NPC_HealthDisplay"
	}) do
		local object = model:FindFirstChild(name)

		if object then
			object:Destroy()
		end
	end
end

-- =========================================================
-- SETUP
-- =========================================================

local trackedNPCs = {}

local function setupNPC(model)
	if not isHostileNPC(model) then
		return
	end

	trackedNPCs[model] = true

	if not SHOW_INFECTED then
		removeNPCVisuals(model)
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
-- НОВОЕ: СОЮЗНИКИ
-- =========================================================

local trackedAllies = {}

local function isAllyPlayer(player)
	if not player or player == Players.LocalPlayer then
		return false
	end

	-- Показываем игроков только своей команды
	if player.Team == nil or Players.LocalPlayer.Team == nil then
		return false
	end

	return player.Team == Players.LocalPlayer.Team
end

local function removeAllyVisual(character)
	if not character then
		return
	end

	local highlight = character:FindFirstChild("VNMA0_AllyHighlight")

	if highlight then
		highlight:Destroy()
	end

	trackedAllies[character] = nil
end

local function createAllyHighlight(character)
	if not character or not character:IsA("Model") then
		return
	end

	if character == Players.LocalPlayer.Character then
		return
	end

	if character:FindFirstChild("VNMA0_AllyHighlight") then
		return
	end

	local highlight = Instance.new("Highlight")

	highlight.Name = "VNMA0_AllyHighlight"

	-- ЕЛЕ ЗАМЕТНЫЙ ЗЕЛЁНЫЙ
	highlight.FillColor = Color3.fromRGB(60, 255, 100)
	highlight.OutlineColor = Color3.fromRGB(90, 255, 120)

	highlight.FillTransparency = 0.90
	highlight.OutlineTransparency = 0.70

	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = SHOW_ALLIES

	highlight.Parent = character

	trackedAllies[character] = true
end

local function setupAlly(player)
	if not isAllyPlayer(player) then
		return
	end

	local character = player.Character

	if character then
		createAllyHighlight(character)
	end
end

local function refreshAllies()
	for character in pairs(trackedAllies) do
		removeAllyVisual(character)
	end

	if not SHOW_ALLIES then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		setupAlly(player)
	end
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

-- =========================================================
-- ИГРОКИ / СОЮЗНИКИ
-- =========================================================

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= Players.LocalPlayer then
		player.CharacterAdded:Connect(function(character)
			task.wait(0.2)
			setupAlly(player)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		setupAlly(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	if player.Character then
		removeAllyVisual(player.Character)
	end
end)

Players.LocalPlayer:GetPropertyChangedSignal("Team"):Connect(function()
	refreshAllies()
end)

-- =========================================================
-- DISTANCE CHECK
-- =========================================================

RunService.RenderStepped:Connect(function()
	local localCharacter = Players.LocalPlayer.Character

	if not localCharacter then
		return
	end

	local localRoot = getRootPart(localCharacter)

	if not localRoot then
		return
	end

	-- ЗАРАЖЁННЫЕ
	for model in pairs(trackedNPCs) do
		if not model.Parent then
			trackedNPCs[model] = nil
		else
			local root = getRootPart(model)

			if root then
				local distance = (root.Position - localRoot.Position).Magnitude
				local visible = SHOW_INFECTED and distance <= MAX_DISTANCE

				local highlight = model:FindFirstChild("NPC_Highlight")
				local hitbox = model:FindFirstChild("NPC_HitboxVisual")
				local health = model:FindFirstChild("NPC_HealthDisplay")

				if highlight then
					highlight.Enabled = visible
				end

				if hitbox then
					hitbox.Visible = visible
				end

				if health then
					health.Enabled = visible
				end
			end
		end
	end

	-- СОЮЗНИКИ
	for character in pairs(trackedAllies) do
		if not character.Parent then
			trackedAllies[character] = nil
		else
			local root = getRootPart(character)
			local highlight = character:FindFirstChild("VNMA0_AllyHighlight")

			if root and highlight then
				local distance = (root.Position - localRoot.Position).Magnitude

				highlight.Enabled =
					SHOW_ALLIES
					and distance <= MAX_DISTANCE
					and isAllyPlayer(Players:GetPlayerFromCharacter(character))
			end
		end
	end
end)

-- =========================================================
-- GUI
-- =========================================================

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local oldGui = PlayerGui:FindFirstChild("VNMA0_ESP_GUI")

if oldGui then
	oldGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "VNMA0_ESP_GUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = PlayerGui

-- =========================================================
-- MAIN
-- =========================================================

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.fromOffset(245, 175)
Main.Position = UDim2.new(0, 20, 0.5, -87)
Main.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
Main.BorderSizePixel = 0
Main.Active = true
Main.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = Main

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(70, 70, 80)
MainStroke.Thickness = 1
MainStroke.Transparency = 0.2
MainStroke.Parent = Main

-- =========================================================
-- HEADER
-- =========================================================

local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 46)
Header.BackgroundColor3 = Color3.fromRGB(27, 27, 33)
Header.BorderSizePixel = 0
Header.Active = true
Header.Parent = Main

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 12)
HeaderCorner.Parent = Header

local Title = Instance.new("TextLabel")
Title.Name = "Title"
Title.Size = UDim2.new(1, -55, 1, 0)
Title.Position = UDim2.fromOffset(12, 0)
Title.BackgroundTransparency = 1
Title.Text = "VNMA0  •  ESP"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.TextSize = 17
Title.Font = Enum.Font.GothamBold
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = Header

local Subtitle = Instance.new("TextLabel")
Subtitle.Size = UDim2.new(1, -55, 0, 14)
Subtitle.Position = UDim2.fromOffset(12, 27)
Subtitle.BackgroundTransparency = 1
Subtitle.Text = "TG: VNMA0  •  300 studs"
Subtitle.TextColor3 = Color3.fromRGB(130, 130, 140)
Subtitle.TextSize = 9
Subtitle.Font = Enum.Font.Gotham
Subtitle.TextXAlignment = Enum.TextXAlignment.Left
Subtitle.Parent = Header

local Minimize = Instance.new("TextButton")
Minimize.Name = "Minimize"
Minimize.Size = UDim2.fromOffset(30, 30)
Minimize.Position = UDim2.new(1, -38, 0, 8)
Minimize.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
Minimize.BorderSizePixel = 0
Minimize.Text = "—"
Minimize.TextColor3 = Color3.fromRGB(230, 230, 230)
Minimize.TextSize = 18
Minimize.Font = Enum.Font.GothamBold
Minimize.AutoButtonColor = true
Minimize.Parent = Header

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 8)
MinCorner.Parent = Minimize

-- =========================================================
-- CONTENT
-- =========================================================

local Content = Instance.new("Frame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -57)
Content.Position = UDim2.fromOffset(10, 52)
Content.BackgroundTransparency = 1
Content.Parent = Main

local Layout = Instance.new("UIListLayout")
Layout.Padding = UDim.new(0, 8)
Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
Layout.VerticalAlignment = Enum.VerticalAlignment.Top
Layout.Parent = Content

local function createToggle(text, callback)
	local Button = Instance.new("TextButton")

	Button.Size = UDim2.new(1, 0, 0, 42)
	Button.BackgroundColor3 = Color3.fromRGB(31, 31, 38)
	Button.BorderSizePixel = 0

	Button.Text = text
	Button.TextColor3 = Color3.fromRGB(235, 235, 240)
	Button.TextSize = 13
	Button.Font = Enum.Font.GothamSemibold

	Button.AutoButtonColor = true
	Button.Parent = Content

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 9)
	Corner.Parent = Button

	local Stroke = Instance.new("UIStroke")
	Stroke.Color = Color3.fromRGB(60, 60, 70)
	Stroke.Transparency = 0.45
	Stroke.Parent = Button

	Button.Activated:Connect(callback)

	return Button
end

local InfectedButton
local AlliesButton

local function updateButtons()
	if SHOW_INFECTED then
		InfectedButton.Text = "☣  Заражённые   [ ВКЛ ]"
		InfectedButton.TextColor3 = Color3.fromRGB(255, 120, 120)
	else
		InfectedButton.Text = "☣  Заражённые   [ ВЫКЛ ]"
		InfectedButton.TextColor3 = Color3.fromRGB(150, 150, 155)
	end

	if SHOW_ALLIES then
		AlliesButton.Text = "●  Союзники       [ ВКЛ ]"
		AlliesButton.TextColor3 = Color3.fromRGB(100, 255, 130)
	else
		AlliesButton.Text = "●  Союзники       [ ВЫКЛ ]"
		AlliesButton.TextColor3 = Color3.fromRGB(150, 150, 155)
	end
end

InfectedButton = createToggle("", function()
	SHOW_INFECTED = not SHOW_INFECTED

	if SHOW_INFECTED then
		for model in pairs(trackedNPCs) do
			if model.Parent then
				setupNPC(model)
			end
		end
	else
		for model in pairs(trackedNPCs) do
			removeNPCVisuals(model)
		end
	end

	updateButtons()
end)

AlliesButton = createToggle("", function()
	SHOW_ALLIES = not SHOW_ALLIES
	refreshAllies()
	updateButtons()
end)

local Info = Instance.new("TextLabel")
Info.Size = UDim2.new(1, 0, 0, 24)
Info.BackgroundTransparency = 1
Info.Text = "ESP Control  •  VNMA0"
Info.TextColor3 = Color3.fromRGB(105, 105, 115)
Info.TextSize = 10
Info.Font = Enum.Font.Gotham
Info.Parent = Content

updateButtons()

-- =========================================================
-- DRAG MAIN GUI
-- =========================================================

local function makeDraggable(handle, frame)
	local dragging = false
	local dragStart
	local startPos
	local dragInput

	handle.InputBegan:Connect(function(input)
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

	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then

			dragInput = input
		end
	end)

	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart

			frame.Position = UDim2.new(
				startPos.X.Scale,
				startPos.X.Offset + delta.X,
				startPos.Y.Scale,
				startPos.Y.Offset + delta.Y
			)
		end
	end)
end

makeDraggable(Header, Main)

-- =========================================================
-- МАЛЕНЬКИЙ КВАДРАТИК
-- =========================================================

local Mini = Instance.new("TextButton")
Mini.Name = "Mini"
Mini.Size = UDim2.fromOffset(50, 50)
Mini.Position = Main.Position
Mini.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Mini.BorderSizePixel = 0
Mini.Text = "V"
Mini.TextColor3 = Color3.fromRGB(255, 255, 255)
Mini.TextSize = 20
Mini.Font = Enum.Font.GothamBold
Mini.AutoButtonColor = true
Mini.Visible = false
Mini.Parent = ScreenGui

local MiniCorner = Instance.new("UICorner")
MiniCorner.CornerRadius = UDim.new(0, 14)
MiniCorner.Parent = Mini

local MiniStroke = Instance.new("UIStroke")
MiniStroke.Color = Color3.fromRGB(90, 90, 105)
MiniStroke.Thickness = 1
MiniStroke.Parent = Mini

makeDraggable(Mini, Mini)

-- =========================================================
-- MINIMIZE
-- =========================================================

Minimize.Activated:Connect(function()
	Mini.Position = Main.Position

	Main.Visible = false
	Mini.Visible = true
end)

Mini.Activated:Connect(function()
	Main.Position = Mini.Position

	Mini.Visible = false
	Main.Visible = true
end)
