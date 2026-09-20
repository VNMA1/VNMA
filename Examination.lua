local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer

-- =========================================================
-- ЗАЩИТА ОТ ДВОЙНОГО ЗАПУСКА (повторный execute не плодит копии)
-- =========================================================
local env = (getgenv and getgenv()) or _G
if env.VNMA0_ESP_STOP then
	pcall(env.VNMA0_ESP_STOP)
end

local stopped = false
local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================
local CFG = {
	ShowHealth = true,
	ShowInfected = true,
	ShowAllies = false,
	MaxDistance = 500,
	BossHealth = 1000,       -- MaxHealth >= этого => босс
	UpdateRate = 0.15,       -- как часто обновляем (сек). 0.15 ≈ 7 раз/сек
	MaxHighlights = 30,      -- у Roblox лимит ~31 Highlight одновременно
	AlliesIfNoTeams = true,  -- если в игре нет команд, считать всех игроков союзниками
	TrackAllNPCs = true,     -- true = подсвечивать ЛЮБОГО не-игрока с Humanoid (ничего не пропадёт).
	                         -- false = только по списку имён ниже
}

-- =========================================================
-- КЛЮЧЕВЫЕ СЛОВА (по Examination Wiki)
-- Очень короткие (<=3 буквы) ищутся как ОТДЕЛЬНОЕ слово
-- (чтобы "sin" не ловил "using"), остальные — как подстрока.
-- Регистр не важен.
-- =========================================================
local HOSTILE_KEYWORDS = {
	-- Обычные заражённые
	"lurker", "crawler", "riser", "mutant", "slasher", "kamikaze", "kamikazi",
	"shielder", "radaway", "gunner", "fury", "engineer", "deceiver",
	"janitor", "hazmat", "toxic", "infected", "corpse walker", "corpsewalker",
	"corpse_walker", "welder", "hpca", "mms", "rsu", "rif ozk", "zombie",

	-- Virals (бывшие солдаты MGF)
	"viral", "viral runner", "viral executioner", "viral leader", "viral enforcer",

	-- Rasonian Infantry Forces (RIF)
	"rasonian", "rif", "infantryman", "combat medic", "shotgunner", "machine gunner",
}

local BOSS_KEYWORDS = {
	"chimera", "gilbert", "sinitzyn", "sin",
	"d-zero", "dzero", "d_zero", "d zero",
	"mikhail", "mikhail william", "mikhail williams",
	"yakov", "yakov zhukov", "yakov zhukovich",
	"dave", "vorax", "cerberus",
}

-- Сюда добавляй имена, которые НЕ нужно подсвечивать (дружелюбные NPC, манекены)
local IGNORE_KEYWORDS = {
	-- "dummy", "trader",
}

local function makeMatcher(list)
	local substrings, patterns = {}, {}
	for _, kw in ipairs(list) do
		kw = kw:lower()
		if #kw <= 3 then
			local escaped = (kw:gsub("[^%w]", "%%%0"))
			patterns[#patterns + 1] = "%f[%a]" .. escaped .. "%f[%A]"
		else
			substrings[#substrings + 1] = kw
		end
	end
	return function(name)
		name = tostring(name):lower()
		for _, s in ipairs(substrings) do
			if name:find(s, 1, true) then return true end
		end
		for _, p in ipairs(patterns) do
			if name:find(p) then return true end
		end
		return false
	end
end

local isHostileName = makeMatcher(HOSTILE_KEYWORDS)
local isBossName = makeMatcher(BOSS_KEYWORDS)
local isIgnoredName = makeMatcher(IGNORE_KEYWORDS)

local function nameMatches(model, humanoid, matcher)
	if matcher(model.Name) or matcher(humanoid.DisplayName) then
		return true
	end
	local dn = model:GetAttribute("DisplayName")
	return typeof(dn) == "string" and matcher(dn)
end

-- =========================================================
-- УТИЛИТЫ
-- =========================================================
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do
		o[k] = v
	end
	o.Parent = parent
	return o
end

local function getRoot(model)
	return model:FindFirstChild("HumanoidRootPart")
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart")
end

local NPC_PALETTE = {
	ok = Color3.fromRGB(255, 255, 255),
	mid = Color3.fromRGB(255, 220, 60),
	low = Color3.fromRGB(255, 60, 60),
}
local ALLY_PALETTE = {
	ok = Color3.fromRGB(100, 255, 130),
	mid = Color3.fromRGB(255, 220, 80),
	low = Color3.fromRGB(255, 100, 100),
}

-- Общая функция HP-надписи (и для врагов, и для союзников)
local function makeHealthLabel(adornee, parent, humanoid, name, width, height, offsetY, textSize, palette)
	local gui = new("BillboardGui", {
		Name = name,
		Adornee = adornee,
		Size = UDim2.fromOffset(width, height),
		StudsOffset = Vector3.new(0, offsetY, 0),
		AlwaysOnTop = true,
		MaxDistance = CFG.MaxDistance,
		Enabled = false,
	}, parent)

	local label = new("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		TextSize = textSize,
		TextStrokeTransparency = 0.15,
		TextColor3 = palette.ok,
	}, gui)

	local function update()
		local hp, maxHp = humanoid.Health, humanoid.MaxHealth
		label.Text = string.format("HP: %d / %d", math.max(0, math.round(hp)), math.max(0, math.round(maxHp)))
		local pct = maxHp > 0 and hp / maxHp or 1
		label.TextColor3 = (pct <= 0.25 and palette.low) or (pct <= 0.5 and palette.mid) or palette.ok
	end
	update()

	local c1 = humanoid.HealthChanged:Connect(update)
	local c2 = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(update)
	gui.Destroying:Connect(function()
		c1:Disconnect()
		c2:Disconnect()
	end)

	return gui
end

-- =========================================================
-- ЗАРАЖЁННЫЕ / БОССЫ
-- =========================================================
local npcs = {} -- [model] = {model, humanoid, boss, root, highlight, gui}

local function paint(e)
	local hl = e.highlight
	if e.boss then
		hl.FillColor = Color3.fromRGB(255, 210, 0)
		hl.OutlineColor = Color3.fromRGB(255, 240, 100)
	else
		hl.FillColor = Color3.fromRGB(255, 0, 0)
		hl.OutlineColor = Color3.fromRGB(255, 100, 100)
	end
end

local function dropNPC(model)
	local e = npcs[model]
	if not e then return end
	npcs[model] = nil
	if e.highlight then e.highlight:Destroy() end
	if e.gui then e.gui:Destroy() end
end

local function ensureNPCVisuals(e)
	if e.highlight and e.highlight.Parent then
		return
	end

	e.highlight = new("Highlight", {
		Name = "NPC_Highlight",
		FillTransparency = 0.9,
		OutlineTransparency = 0.7,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	}, e.model)
	paint(e)

	if CFG.ShowHealth and not (e.gui and e.gui.Parent) then
		local _, size = e.model:GetBoundingBox()
		e.gui = makeHealthLabel(e.root, e.model, e.humanoid, "NPC_HealthDisplay",
			180, 45, size.Y / 2 + 2, 12, NPC_PALETTE)
	end
end

local function trackNPC(h)
	if stopped then return end

	local model = h.Parent
	if not model or not model:IsA("Model") or npcs[model] or h.Health <= 0 then
		return
	end
	if Players:GetPlayerFromCharacter(model) then
		return
	end

	if nameMatches(model, h, isIgnoredName) then
		return
	end

	local boss = nameMatches(model, h, isBossName) or h.MaxHealth >= CFG.BossHealth
	if not boss and not CFG.TrackAllNPCs and not nameMatches(model, h, isHostileName) then
		return
	end

	local e = { model = model, humanoid = h, boss = boss }
	npcs[model] = e

	-- Труп больше не показываем
	h.Died:Connect(function()
		dropNPC(model)
	end)

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			dropNPC(model)
		end
	end)

	-- Обычный заражённый может стать боссом, если MaxHealth выставят позже.
	-- Обратно босс не понижается.
	h:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		if not e.boss and h.MaxHealth >= CFG.BossHealth then
			e.boss = true
			if e.highlight then paint(e) end
		end
	end)
end

local function onHumanoidAdded(h)
	-- Даём игре время выставить имя/HP, потом проверяем; вторая попытка через 2 сек
	task.defer(trackNPC, h)
	task.delay(2, trackNPC, h)
end

-- Ловим только Humanoid, а не каждую добавленную деталь в Workspace
for _, d in ipairs(Workspace:GetDescendants()) do
	if d:IsA("Humanoid") then
		onHumanoidAdded(d)
	end
end

bind(Workspace.DescendantAdded, function(d)
	if d:IsA("Humanoid") then
		onHumanoidAdded(d)
	end
end)

-- =========================================================
-- СОЮЗНИКИ
-- =========================================================
local allyVis = setmetatable({}, { __mode = "k" }) -- [character] = {highlight, gui}

local function isAlly(player)
	if player == LocalPlayer then
		return false
	end
	local mine, theirs = LocalPlayer.Team, player.Team
	if mine == nil or theirs == nil then
		return CFG.AlliesIfNoTeams
	end
	return mine == theirs
end

local function createAllyVisuals(char, hum, root)
	local hl = new("Highlight", {
		Name = "VNMA0_AllyHighlight",
		FillColor = Color3.fromRGB(60, 255, 100),
		OutlineColor = Color3.fromRGB(90, 255, 120),
		FillTransparency = 0.9,
		OutlineTransparency = 0.7,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	}, char)

	local gui
	if CFG.ShowHealth then
		gui = makeHealthLabel(char:FindFirstChild("Head") or root, char, hum,
			"VNMA0_AllyHealth", 100, 20, 2.8, 11, ALLY_PALETTE)
	end

	return { highlight = hl, gui = gui }
end

-- Игроков мало, поэтому перебираем их напрямую — без ивентов и трекинга команд
local function updateAllies(origin)
	local used = 0

	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local vis = char and allyVis[char]
		local show = false

		if char and CFG.ShowAllies and isAlly(p) then
			local root = getRoot(char)
			local hum = char:FindFirstChildOfClass("Humanoid")

			if root and hum and hum.Health > 0
				and (root.Position - origin).Magnitude <= CFG.MaxDistance then

				if not vis then
					vis = createAllyVisuals(char, hum, root)
					allyVis[char] = vis
				end
				show = true
			end
		end

		if vis then
			vis.highlight.Enabled = show
			if vis.gui then vis.gui.Enabled = show end
			if show then used += 1 end
		end
	end

	return used
end

-- =========================================================
-- ГЛАВНЫЙ ЦИКЛ (~7 раз/сек вместо 60+ на каждый кадр)
-- =========================================================
local acc = 0

bind(RunService.Heartbeat, function(dt)
	acc += dt
	if acc < CFG.UpdateRate then return end
	acc = 0

	local char = LocalPlayer.Character
	local myRoot = char and getRoot(char)
	if not myRoot then return end
	local origin = myRoot.Position

	-- Союзники в приоритете, остаток лимита Highlight — врагам
	local budget = CFG.MaxHighlights - updateAllies(origin)

	local inRange, list = {}, {}

	if CFG.ShowInfected then
		for model, e in pairs(npcs) do
			local root = e.root
			if not root or not root.Parent then
				root = getRoot(model)
				e.root = root
			end

			if root then
				local d = (root.Position - origin).Magnitude
				if d <= CFG.MaxDistance then
					ensureNPCVisuals(e)
					inRange[e] = true
					list[#list + 1] = { e = e, d = d }
				end
			end
		end
	end

	table.sort(list, function(a, b) return a.d < b.d end)

	-- Highlight только у ближайших (лимит движка), HP-надпись у всех в радиусе
	local hlOn = {}
	for i = 1, math.min(#list, budget) do
		hlOn[list[i].e] = true
	end

	for _, e in pairs(npcs) do
		if e.highlight then e.highlight.Enabled = hlOn[e] == true end
		if e.gui then e.gui.Enabled = inRange[e] == true end
	end
end)

-- =========================================================
-- GUI
-- =========================================================
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local old = playerGui:FindFirstChild("VNMA0_ESP_GUI")
if old then old:Destroy() end

local screenGui = new("ScreenGui", {
	Name = "VNMA0_ESP_GUI",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local main = new("Frame", {
	Name = "Main",
	Size = UDim2.fromOffset(245, 175),
	Position = UDim2.new(0, 20, 0.5, -87),
	BackgroundColor3 = Color3.fromRGB(18, 18, 22),
	BorderSizePixel = 0,
	Active = true,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, main)
new("UIStroke", { Color = Color3.fromRGB(70, 70, 80), Transparency = 0.2 }, main)

local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 46),
	BackgroundColor3 = Color3.fromRGB(27, 27, 33),
	BorderSizePixel = 0,
	Active = true,
}, main)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, header)

new("TextLabel", {
	Size = UDim2.new(1, -55, 1, 0),
	Position = UDim2.fromOffset(12, 0),
	BackgroundTransparency = 1,
	Text = "VNMA0  •  ESP",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

new("TextLabel", {
	Size = UDim2.new(1, -55, 0, 14),
	Position = UDim2.fromOffset(12, 27),
	BackgroundTransparency = 1,
	Text = string.format("TG: VNMA0  •  %d studs", CFG.MaxDistance),
	TextColor3 = Color3.fromRGB(130, 130, 140),
	TextSize = 9,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local minimize = new("TextButton", {
	Name = "Minimize",
	Size = UDim2.fromOffset(30, 30),
	Position = UDim2.new(1, -38, 0, 8),
	BackgroundColor3 = Color3.fromRGB(40, 40, 48),
	BorderSizePixel = 0,
	Text = "—",
	TextColor3 = Color3.fromRGB(230, 230, 230),
	TextSize = 18,
	Font = Enum.Font.GothamBold,
}, header)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, minimize)

local content = new("Frame", {
	Name = "Content",
	Size = UDim2.new(1, -20, 1, -57),
	Position = UDim2.fromOffset(10, 52),
	BackgroundTransparency = 1,
}, main)

new("UIListLayout", {
	Padding = UDim.new(0, 8),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Top,
}, content)

local OFF_COLOR = Color3.fromRGB(150, 150, 155)

local function createToggle(icon, label, key, onColor)
	local btn = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundColor3 = Color3.fromRGB(31, 31, 38),
		BorderSizePixel = 0,
		TextSize = 13,
		Font = Enum.Font.GothamSemibold,
	}, content)
	new("UICorner", { CornerRadius = UDim.new(0, 9) }, btn)
	new("UIStroke", { Color = Color3.fromRGB(60, 60, 70), Transparency = 0.45 }, btn)

	local function refresh()
		local on = CFG[key]
		btn.Text = string.format("%s  %s   [ %s ]", icon, label, on and "ВКЛ" or "ВЫКЛ")
		btn.TextColor3 = on and onColor or OFF_COLOR
	end

	btn.Activated:Connect(function()
		CFG[key] = not CFG[key]
		refresh()
	end)
	refresh()
end

createToggle("☣", "Заражённые", "ShowInfected", Color3.fromRGB(255, 120, 120))
createToggle("●", "Союзники", "ShowAllies", Color3.fromRGB(100, 255, 130))

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	Text = "ESP Control  •  VNMA0",
	TextColor3 = Color3.fromRGB(105, 105, 115),
	TextSize = 10,
	Font = Enum.Font.Gotham,
}, content)

-- Перетаскивание: InputChanged подключается ТОЛЬКО пока тянем
local function makeDraggable(handle, frame)
	handle.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local startPos = input.Position
		local startFramePos = frame.Position
		local moveConn, endConn

		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = i.Position - startPos
				frame.Position = UDim2.new(
					startFramePos.X.Scale, startFramePos.X.Offset + delta.X,
					startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y
				)
			end
		end)

		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)
end

makeDraggable(header, main)

-- Свёрнутый квадратик
local mini = new("TextButton", {
	Name = "Mini",
	Size = UDim2.fromOffset(50, 50),
	Position = main.Position,
	BackgroundColor3 = Color3.fromRGB(22, 22, 28),
	BorderSizePixel = 0,
	Text = "V",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 20,
	Font = Enum.Font.GothamBold,
	Visible = false,
}, screenGui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, mini)
new("UIStroke", { Color = Color3.fromRGB(90, 90, 105) }, mini)

makeDraggable(mini, mini)

minimize.Activated:Connect(function()
	mini.Position = main.Position
	main.Visible = false
	mini.Visible = true
end)

mini.Activated:Connect(function()
	main.Position = mini.Position
	mini.Visible = false
	main.Visible = true
end)

-- =========================================================
-- ПОЛНАЯ ОСТАНОВКА (вызывается при повторном запуске скрипта)
-- =========================================================
env.VNMA0_ESP_STOP = function()
	stopped = true
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	for model in pairs(npcs) do
		dropNPC(model)
	end
	for _, vis in pairs(allyVis) do
		if vis.highlight then vis.highlight:Destroy() end
		if vis.gui then vis.gui:Destroy() end
	end
	screenGui:Destroy()
end
