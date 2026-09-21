print("[VNMA-SCRIPT] loading...")

-- показывает ошибку в консоли и уведомлением на экране (видно и на телефоне)
local function reportError(where, err)
	warn("[VNMA-SCRIPT] ERROR (" .. tostring(where) .. "): " .. tostring(err))
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "VNMA-SCRIPT: ошибка",
			Text = string.sub(tostring(where) .. ": " .. tostring(err), 1, 180),
			Duration = 15,
		})
	end)
end

local function main()

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

-- =========================================================
-- ЗАЩИТА ОТ ДВОЙНОГО ЗАПУСКА
-- =========================================================
local env
do
	local ok, g = pcall(function()
		return getgenv and getgenv()
	end)
	env = (ok and type(g) == "table") and g or _G
end

if type(env) == "table" and env.VNMA0_ESP_STOP then
	pcall(env.VNMA0_ESP_STOP)
	print("[VNMA-SCRIPT] previous instance stopped")
end

local stopped = false
local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

-- временная остановка (на случай ошибки при запуске), полная версия ниже перезапишет её
if type(env) == "table" then
	env.VNMA0_ESP_STOP = function()
		stopped = true
		for _, c in ipairs(connections) do
			pcall(function() c:Disconnect() end)
		end
	end
end

-- =========================================================
-- НАСТРОЙКИ
-- =========================================================
local CFG = {
	ShowHealth = true,
	ShowInfected = true,
	ShowAllies = false,
	ShowCards = false,
	ShowDoors = false,
	NoFog = false,
	NoDark = false,
	FOVEnabled = false,
	FOV = 90,

	-- AIM BOT
	AimPC = false,        -- [AIM PC]: аим работает, пока зажата ПКМ
	AimPCHold = true,     -- true = держать ПКМ, false = ПКМ включает/выключает
	AimMobile = false,    -- [AIM MB]: круглая кнопка AIM на экране (телефон)
	AimFOV = 20,          -- угол захвата (градусы). Меньше = незаметнее
	AimSmooth = 0.12,     -- 0.05 очень мягко ... 1 жёстко
	AimDistance = 150,
	AimWallCheck = true,
	AimPart = "Head",     -- "Head" или "HumanoidRootPart"

	MaxDistance = 500,
	ItemDistance = 600,
	ReaderRadius = 14,
	BossHealth = 1000,
	UpdateRate = 0.15,
	MaxHighlights = 30,
	MaxKeyHighlights = 8,
	MaxDoorHighlights = 8,
	MaxKeySize = 15,
	AlliesIfNoTeams = true,
	TrackAllNPCs = true,
	HideDeadNPCs = true,
	IgnoreNPCsWithPrompts = true,
	NPCHealthOffset = 0.5,
	AllyHealthOffset = 1.5,
	Debug = false,
}

local function dbg(...)
	if CFG.Debug then
		print("[VNMA0]", ...)
	end
end

-- =========================================================
-- ПОИСК ПО ИМЕНАМ
-- =========================================================
local function normalizeName(name)
	name = tostring(name)
	name = name:gsub("(%l)(%u)", "%1 %2")
	name = name:gsub("_", " ")
	return name:lower()
end

local function makeMatcher(list, wordOnly)
	local substrings, patterns = {}, {}
	for _, kw in ipairs(list) do
		kw = normalizeName(kw)
		if wordOnly or #kw <= 3 then
			local escaped = (kw:gsub("[^%w]", "%%%0"))
			patterns[#patterns + 1] = "%f[%a]" .. escaped .. "%f[%A]"
		else
			substrings[#substrings + 1] = kw
		end
	end

	local cache, count = {}, 0

	return function(name)
		name = tostring(name)

		local hit = cache[name]
		if hit ~= nil then
			return hit
		end

		local n = normalizeName(name)
		local result = false

		for _, s in ipairs(substrings) do
			if n:find(s, 1, true) then
				result = true
				break
			end
		end

		if not result then
			for _, p in ipairs(patterns) do
				if n:find(p) then
					result = true
					break
				end
			end
		end

		if count >= 5000 then
			cache, count = {}, 0
		end
		cache[name] = result
		count += 1

		return result
	end
end

local Match = {}
do
	local HOSTILE = {
		"lurker", "crawler", "riser", "mutant", "slasher", "kamikaze", "kamikazi",
		"shielder", "radaway", "gunner", "fury", "engineer", "deceiver",
		"janitor", "hazmat", "toxic", "infected", "corpse walker", "corpsewalker",
		"welder", "hpca", "mms", "rsu", "rif ozk", "zombie",
		"viral", "viral runner", "viral executioner", "viral leader", "viral enforcer",
		"rasonian", "rif", "infantryman", "combat medic", "shotgunner", "machine gunner",
	}

	local BOSS = {
		"chimera", "gilbert", "sinitzyn", "sin",
		"d-zero", "dzero", "d zero",
		"mikhail", "mikhail william", "mikhail williams",
		"yakov", "yakov zhukov", "yakov zhukovich",
		"dave", "vorax", "cerberus",
	}

	local CREATURE = {
		"lurker", "crawler", "riser", "mutant", "slasher", "kamikaze", "kamikazi",
		"shielder", "radaway", "gunner", "fury", "deceiver", "zombie",
		"viral", "rasonian", "infantryman", "combat medic", "shotgunner", "machine gunner",
	}
	for _, k in ipairs(BOSS) do
		CREATURE[#CREATURE + 1] = k
	end

	local IGNORE = {
		"adam", "dice", "isaac", "vicente", "yuri", "scarlet",
		"viewmodel", "view model", "arms", "hands",
		"dummy", "trader", "vendor", "merchant", "shopkeeper",
	}

	Match.hostile = makeMatcher(HOSTILE)
	Match.boss = makeMatcher(BOSS)
	Match.creature = makeMatcher(CREATURE)
	Match.ignore = makeMatcher(IGNORE)

	Match.keyStrong = makeMatcher({ "keycard", "key card", "passcard", "access card" })
	Match.keyWord = makeMatcher({ "key", "keys", "keycard", "key card", "card" }, true)
	Match.cardWord = makeMatcher({ "card" }, true)
	Match.keyIgnSub = makeMatcher({
		"reader", "scanner", "keypad", "keyboard", "locker", "cabinet", "drawer",
		"terminal", "laptop", "tablet", "document", "notebook", "clipboard",
	})
	Match.keyIgnWord = makeMatcher({
		"slot", "lock", "door", "gate", "box", "crate", "chest", "safe", "bin",
		"note", "paper", "map", "file", "book", "panel", "switch", "button", "hook",
		"spawn", "spawns", "spawner", "marker",
	}, true)

	Match.reader = makeMatcher({ "reader", "scanner", "terminal", "keypad", "access panel", "card reader" }, true)
	Match.door = makeMatcher({ "door", "doors", "gate", "hatch", "vault" }, true)
	Match.doorIgn = makeMatcher({
		"frame", "handle", "knob", "hinge", "sign", "light", "lamp", "number", "label",
		"glass", "window", "button", "prompt", "trim", "arrow", "decal", "text", "poster", "lock",
	}, true)
	Match.colorPart = makeMatcher({ "card", "strip", "stripe", "level", "color", "colour", "access", "band" })

	Match.fog = makeMatcher({ "fog", "mist", "haze", "smog" })
end

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

local function isOwnOrViewModel(model)
	local cam = Workspace.CurrentCamera
	if cam and model:IsDescendantOf(cam) then
		return true
	end
	local char = LocalPlayer.Character
	if char and (model == char or model:IsDescendantOf(char)) then
		return true
	end
	return false
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
-- ОСВЕЩЕНИЕ: ТУМАН + ТЕМНОТА
-- =========================================================
local Light = {}
do
	local weak = { __mode = "k" }
	local FOG_OFF = 100000
	local ATMOS_PROPS = { "Density", "Haze", "Glare" }

	local fog = {
		lighting = nil,
		atmos = setmetatable({}, weak),
		emitters = setmetatable({}, weak),
		clouds = nil,
		cloudsWas = nil,
	}
	local atmosphereSet = setmetatable({}, weak)
	local emitterSet = setmetatable({}, weak)
	local fogPartSet = setmetatable({}, weak)
	local ccSet = setmetatable({}, weak)
	local darkSaved = {}
	local ccSaved = setmetatable({}, weak)

	local function enforceFog()
		if not CFG.NoFog then return end

		if Lighting.FogStart ~= FOG_OFF or Lighting.FogEnd ~= FOG_OFF then
			local s = fog.lighting or {}
			if Lighting.FogStart ~= FOG_OFF then s.start = Lighting.FogStart end
			if Lighting.FogEnd ~= FOG_OFF then s.fend = Lighting.FogEnd end
			fog.lighting = s

			Lighting.FogStart = FOG_OFF
			Lighting.FogEnd = FOG_OFF
		end
	end

	local function killAtmosphere(a)
		local o = fog.atmos[a]
		if not o then
			o = {}
			for _, p in ipairs(ATMOS_PROPS) do
				o[p] = a[p]
			end
			fog.atmos[a] = o
		end
		for _, p in ipairs(ATMOS_PROPS) do
			if a[p] ~= 0 then
				a[p] = 0
			end
		end
	end

	local function watchAtmosphere(a)
		for _, prop in ipairs(ATMOS_PROPS) do
			bind(a:GetPropertyChangedSignal(prop), function()
				if CFG.NoFog and a[prop] ~= 0 then
					local o = fog.atmos[a]
					if o then
						o[prop] = a[prop]
					end
					killAtmosphere(a)
				end
			end)
		end
	end

	local function killEmitter(p)
		if fog.emitters[p] == nil then
			fog.emitters[p] = p.Enabled
		end
		if p.Enabled then
			p.Enabled = false
		end
	end

	function Light.registerEmitter(p)
		if emitterSet[p] then return end
		emitterSet[p] = true

		bind(p:GetPropertyChangedSignal("Enabled"), function()
			if CFG.NoFog and p.Enabled then
				fog.emitters[p] = true
				p.Enabled = false
			end
		end)

		if CFG.NoFog then
			killEmitter(p)
		end
	end

	function Light.registerFogPart(p)
		if fogPartSet[p] or p.CanCollide then return end
		fogPartSet[p] = true
		if CFG.NoFog then
			p.LocalTransparencyModifier = 1
		end
	end

	local function getClouds()
		local t = Workspace:FindFirstChildOfClass("Terrain")
		return t and t:FindFirstChildOfClass("Clouds")
	end

	local function restoreFog()
		local s = fog.lighting
		if s then
			fog.lighting = nil
			if s.fend then Lighting.FogEnd = s.fend end
			if s.start then Lighting.FogStart = s.start end
		end

		for a, o in pairs(fog.atmos) do
			fog.atmos[a] = nil
			if a.Parent then
				for prop, value in pairs(o) do
					a[prop] = value
				end
			end
		end

		for p, was in pairs(fog.emitters) do
			fog.emitters[p] = nil
			if p.Parent then
				p.Enabled = was
			end
		end

		for p in pairs(fogPartSet) do
			if p.Parent then
				p.LocalTransparencyModifier = 0
			end
		end

		if fog.clouds then
			if fog.clouds.Parent and fog.cloudsWas ~= nil then
				fog.clouds.Enabled = fog.cloudsWas
			end
			fog.clouds, fog.cloudsWas = nil, nil
		end
	end

	function Light.applyFog()
		if CFG.NoFog then
			enforceFog()
			for a in pairs(atmosphereSet) do
				if a.Parent then killAtmosphere(a) end
			end
			for p in pairs(emitterSet) do
				if p.Parent then killEmitter(p) end
			end
			for p in pairs(fogPartSet) do
				if p.Parent then p.LocalTransparencyModifier = 1 end
			end
			local c = getClouds()
			if c then
				if fog.cloudsWas == nil then fog.cloudsWas = c.Enabled end
				fog.clouds = c
				c.Enabled = false
			end
		else
			restoreFog()
		end
	end

	local function liftColor(c)
		return Color3.new(math.max(c.R, 0.68), math.max(c.G, 0.68), math.max(c.B, 0.68))
	end

	local DARK_RULES = {
		{ "Brightness", function(v) return math.max(v, 2) end },
		{ "ExposureCompensation", function(v) return math.max(v, 0.6) end },
		{ "Ambient", liftColor },
		{ "OutdoorAmbient", liftColor },
	}

	local function differs(a, b)
		if typeof(a) == "number" then
			return math.abs(a - b) > 1e-4
		end
		return math.abs(a.R - b.R) > 1e-3 or math.abs(a.G - b.G) > 1e-3 or math.abs(a.B - b.B) > 1e-3
	end

	local function enforceDark()
		if not CFG.NoDark then return end

		for _, rule in ipairs(DARK_RULES) do
			local prop, fn = rule[1], rule[2]
			local cur = Lighting[prop]
			local target = fn(cur)
			if differs(cur, target) then
				darkSaved[prop] = cur
				Lighting[prop] = target
			end
		end

		for cc in pairs(ccSet) do
			if cc.Parent and cc.Brightness < 0 then
				if ccSaved[cc] == nil then
					ccSaved[cc] = cc.Brightness
				end
				cc.Brightness = 0
			end
		end
	end

	local function restoreDark()
		for prop, value in pairs(darkSaved) do
			darkSaved[prop] = nil
			Lighting[prop] = value
		end
		for cc, b in pairs(ccSaved) do
			ccSaved[cc] = nil
			if cc.Parent then
				cc.Brightness = b
			end
		end
	end

	function Light.applyDark()
		if CFG.NoDark then
			enforceDark()
		else
			restoreDark()
		end
	end

	function Light.registerCC(cc)
		ccSet[cc] = true
	end

	function Light.restoreAll()
		CFG.NoFog = false
		CFG.NoDark = false
		pcall(restoreFog)
		pcall(restoreDark)
	end

	local function trackLightingInstance(d)
		if d:IsA("Atmosphere") and not atmosphereSet[d] then
			atmosphereSet[d] = true
			watchAtmosphere(d)
			if CFG.NoFog then
				killAtmosphere(d)
			end
		elseif d:IsA("ColorCorrectionEffect") then
			ccSet[d] = true
		end
	end

	for _, d in ipairs(Lighting:GetDescendants()) do
		trackLightingInstance(d)
	end
	bind(Lighting.DescendantAdded, trackLightingInstance)

	bind(Lighting:GetPropertyChangedSignal("FogEnd"), enforceFog)
	bind(Lighting:GetPropertyChangedSignal("FogStart"), enforceFog)

	bind(RunService.RenderStepped, function()
		enforceFog()
		enforceDark()
	end)
end

-- =========================================================
-- ЗАРАЖЁННЫЕ / БОССЫ
-- =========================================================
local Npc = {}
do
	local npcs = {}
	local ignored = setmetatable({}, { __mode = "k" })
	local retried = setmetatable({}, { __mode = "k" })

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

	local function ensureVisuals(e)
		if not (e.highlight and e.highlight.Parent) then
			e.highlight = new("Highlight", {
				Name = "NPC_Highlight",
				FillTransparency = 0.9,
				OutlineTransparency = 0.7,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				Enabled = false,
			}, e.model)
			paint(e)
		end

		if CFG.ShowHealth and e.humanoid and not (e.gui and e.gui.Parent) then
			local _, size = e.model:GetBoundingBox()
			e.gui = makeHealthLabel(e.root, e.model, e.humanoid, "NPC_HealthDisplay",
				180, 45, size.Y / 2 + CFG.NPCHealthOffset, 12, NPC_PALETTE)
		end
	end

	local function trackNPC(h)
		if stopped then return end

		local model = h.Parent
		if not model or not model:IsA("Model") or model == Workspace or npcs[model] then
			return
		end
		if ignored[model] or Players:GetPlayerFromCharacter(model) then
			return
		end

		if isOwnOrViewModel(model) then
			ignored[model] = true
			return
		end

		local hostileByName = nameMatches(model, h, Match.hostile) or nameMatches(model, h, Match.boss)

		if not hostileByName then
			if nameMatches(model, h, Match.ignore) then
				ignored[model] = true
				dbg("ignored (name):", model:GetFullName())
				return
			end
			if CFG.IgnoreNPCsWithPrompts and model:FindFirstChildWhichIsA("ProximityPrompt", true) then
				ignored[model] = true
				dbg("ignored (has prompt):", model:GetFullName())
				return
			end
		end

		local boss = nameMatches(model, h, Match.boss) or h.MaxHealth >= CFG.BossHealth
		if not boss and not CFG.TrackAllNPCs and not hostileByName then
			return
		end

		local e = { model = model, humanoid = h, boss = boss }
		npcs[model] = e
		dbg("tracked:", model:GetFullName(), "boss =", boss)

		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				dropNPC(model)
			end
		end)

		h:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			if not e.boss and h.MaxHealth >= CFG.BossHealth then
				e.boss = true
				if e.highlight then paint(e) end
			end
		end)
	end

	function Npc.onHumanoidAdded(h)
		task.defer(trackNPC, h)
		task.delay(2, trackNPC, h)
	end

	function Npc.trackNamedModel(model)
		if stopped or npcs[model] or ignored[model] then return end
		if not model:IsA("Model") or model == Workspace then return end
		if not Match.creature(model.Name) then return end
		if model:FindFirstChildOfClass("Humanoid") then return end
		if Players:GetPlayerFromCharacter(model) then return end

		if Match.ignore(model.Name) or isOwnOrViewModel(model) then
			ignored[model] = true
			return
		end

		local parent = model.Parent
		if parent and parent ~= Workspace and parent:IsA("Model") then
			if npcs[parent] or parent:FindFirstChildOfClass("Humanoid") then
				return
			end
		end

		local root = getRoot(model)
		if not root then
			if not retried[model] then
				retried[model] = true
				task.delay(1, Npc.trackNamedModel, model)
			end
			return
		end

		local ok, size = pcall(model.GetExtentsSize, model)
		if not ok or size.Magnitude > 80 then
			return
		end

		npcs[model] = { model = model, boss = Match.boss(model.Name), root = root }
		dbg("tracked (no Humanoid):", model:GetFullName())

		model.AncestryChanged:Connect(function(_, p)
			if not p then
				dropNPC(model)
			end
		end)
	end

	function Npc.update(origin, camPos, budget)
		local inRange, list = {}, {}

		if CFG.ShowInfected then
			for model, e in pairs(npcs) do
				if isOwnOrViewModel(model) then
					ignored[model] = true
					dropNPC(model)
				else
					local hum = e.humanoid
					local alive = not (CFG.HideDeadNPCs and hum and hum.Health <= 0)

					if alive then
						local root = e.root
						if not root or not root.Parent then
							root = getRoot(model)
							e.root = root
						end

						if root then
							local d = (root.Position - origin).Magnitude
							local nearCamera = camPos and (root.Position - camPos).Magnitude < 3

							if d <= CFG.MaxDistance and not nearCamera then
								local ok, err = pcall(ensureVisuals, e)
								if ok then
									inRange[e] = true
									list[#list + 1] = { e = e, d = d }
								else
									dbg("visuals error:", model:GetFullName(), err)
								end
							end
						end
					end
				end
			end
		end

		table.sort(list, function(a, b) return a.d < b.d end)

		local hlOn = {}
		for i = 1, math.min(#list, budget) do
			hlOn[list[i].e] = true
		end

		for _, e in pairs(npcs) do
			if e.highlight then e.highlight.Enabled = hlOn[e] == true end
			if e.gui then e.gui.Enabled = inRange[e] == true end
		end
	end

	function Npc.clear()
		for model in pairs(npcs) do
			dropNPC(model)
		end
	end

	-- список целей для Aim Bot
	function Npc.targets()
		return npcs
	end
end

-- =========================================================
-- СОЮЗНИКИ
-- =========================================================
local Allies = {}
do
	local allyVis = setmetatable({}, { __mode = "k" })

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

	local function createVisuals(char, hum, root)
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
				"VNMA0_AllyHealth", 100, 20, CFG.AllyHealthOffset, 11, ALLY_PALETTE)
		end

		return { highlight = hl, gui = gui }
	end

	function Allies.update(origin)
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
						vis = createVisuals(char, hum, root)
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

	function Allies.clear()
		for _, vis in pairs(allyVis) do
			if vis.highlight then vis.highlight:Destroy() end
			if vis.gui then vis.gui:Destroy() end
		end
	end
end

-- =========================================================
-- [TUNNEL] КЛЮЧ-КАРТЫ, КЛЮЧИ, ДВЕРИ И ТЕРМИНАЛЫ
-- =========================================================
local Items = {}
do
	local weak = { __mode = "k" }
	local items = {}
	local readers = setmetatable({}, weak)
	local doorCands = setmetatable({}, weak)
	local doorNeg = setmetatable({}, weak)
	local readerCache = setmetatable({}, weak)

	local DEFAULT_COLOR = Color3.fromRGB(255, 160, 40)
	local WHITE = Color3.new(1, 1, 1)

	local COLORS = {
		{ id = "red",    f = "Красная",    fl = "красная",    m = "Красный",    words = { "red", "crimson" },        rgb = Color3.fromRGB(255, 55, 55) },
		{ id = "blue",   f = "Синяя",      fl = "синяя",      m = "Синий",      words = { "blue", "navy" },          rgb = Color3.fromRGB(70, 140, 255) },
		{ id = "yellow", f = "Жёлтая",     fl = "жёлтая",     m = "Жёлтый",     words = { "yellow", "gold" },        rgb = Color3.fromRGB(255, 220, 40) },
		{ id = "green",  f = "Зелёная",    fl = "зелёная",    m = "Зелёный",    words = { "green", "lime" },         rgb = Color3.fromRGB(60, 235, 100) },
		{ id = "orange", f = "Оранжевая",  fl = "оранжевая",  m = "Оранжевый",  words = { "orange" },                rgb = Color3.fromRGB(255, 140, 0) },
		{ id = "purple", f = "Фиолетовая", fl = "фиолетовая", m = "Фиолетовый", words = { "purple", "violet" },      rgb = Color3.fromRGB(185, 95, 255) },
		{ id = "cyan",   f = "Голубая",    fl = "голубая",    m = "Голубой",    words = { "cyan", "teal", "aqua" },  rgb = Color3.fromRGB(60, 225, 235) },
		{ id = "pink",   f = "Розовая",    fl = "розовая",    m = "Розовый",    words = { "pink", "magenta" },       rgb = Color3.fromRGB(255, 115, 195) },
		{ id = "white",  f = "Белая",      fl = "белая",      m = "Белый",      words = { "white" },                 rgb = Color3.fromRGB(245, 245, 245) },
		{ id = "black",  f = "Чёрная",     fl = "чёрная",     m = "Чёрный",     words = { "black" },                 rgb = Color3.fromRGB(150, 150, 170) },
		{ id = "gray",   f = "Серая",      fl = "серая",      m = "Серый",      words = { "gray", "grey", "silver" }, rgb = Color3.fromRGB(190, 190, 200) },
		{ id = "brown",  f = "Коричневая", fl = "коричневая", m = "Коричневый", words = { "brown" },                 rgb = Color3.fromRGB(200, 125, 60) },
	}
	local byId = {}
	for _, def in ipairs(COLORS) do
		def.match = makeMatcher(def.words, true)
		byId[def.id] = def
	end

	local function colorFromText(s)
		if s == nil or s == "" then return nil end
		for _, def in ipairs(COLORS) do
			if def.match(s) then
				return def
			end
		end
		return nil
	end

	local function classifyColor(c)
		local h, s, v = c:ToHSV()
		h = h * 360
		if v < 0.2 then return byId.black end
		if s < 0.2 then
			return v > 0.8 and byId.white or byId.gray
		end
		if h < 15 or h >= 345 then return byId.red end
		if h < 40 then return v < 0.5 and byId.brown or byId.orange end
		if h < 70 then return byId.yellow end
		if h < 160 then return byId.green end
		if h < 200 then return byId.cyan end
		if h < 260 then return byId.blue end
		if h < 320 then return byId.purple end
		return byId.pink
	end

	local ATTR_HINTS = { "color", "colour", "card", "key", "access", "level", "require", "clearance", "type" }
	local function attrRelevant(name)
		name = tostring(name):lower()
		for _, h in ipairs(ATTR_HINTS) do
			if name:find(h, 1, true) then
				return true
			end
		end
		return false
	end

	local function colorFromAttributes(inst)
		for name, value in pairs(inst:GetAttributes()) do
			if attrRelevant(name) then
				local t = typeof(value)
				if t == "string" then
					local def = colorFromText(value)
					if def then return def end
				elseif t == "Color3" then
					return classifyColor(value)
				elseif t == "BrickColor" then
					return classifyColor(value.Color)
				end
			end
		end
		return nil
	end

	local function colorFromParts(inst, filter)
		local parts = {}
		if inst:IsA("BasePart") then
			parts[1] = inst
		else
			for _, p in ipairs(inst:GetDescendants()) do
				if p:IsA("BasePart") then
					parts[#parts + 1] = p
					if #parts >= 40 then break end
				end
			end
		end

		local best, bestScore
		for _, p in ipairs(parts) do
			if p.Transparency < 0.9 and (not filter or filter(p)) then
				local _, s, v = p.Color:ToHSV()
				local score = s * v
				if not bestScore or score > bestScore then
					best, bestScore = p, score
				end
			end
		end

		return best and classifyColor(best.Color) or nil
	end

	local function namesChain(inst, depth)
		local out, cur = {}, inst
		for _ = 1, depth do
			if not cur or cur == Workspace then break end
			out[#out + 1] = cur.Name
			cur = cur.Parent
		end
		return out
	end

	local function keyIgnored(s)
		return Match.keyIgnSub(s) or Match.keyIgnWord(s)
	end

	local function forbiddenHolder(inst)
		local cam = Workspace.CurrentCamera
		if cam and inst:IsDescendantOf(cam) then
			return true
		end
		local char = LocalPlayer.Character
		if char and inst:IsDescendantOf(char) then
			return true
		end
		local model = inst:FindFirstAncestorOfClass("Model")
		return model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil
	end

	local function getItemRoot(obj)
		if obj:IsA("BasePart") then
			return obj
		end
		if obj:IsA("Model") then
			return getRoot(obj)
		end
		return obj:FindFirstChildWhichIsA("BasePart", true)
	end

	local function extentSize(inst)
		if inst:IsA("BasePart") then
			return inst.Size.Magnitude
		end
		if inst:IsA("Model") then
			local ok, size = pcall(inst.GetExtentsSize, inst)
			return ok and size.Magnitude or math.huge
		end
		local root = getItemRoot(inst)
		return root and root.Size.Magnitude or math.huge
	end

	local function nearestContainer(inst)
		local cur = inst.Parent
		for _ = 1, 5 do
			if not cur or cur == Workspace then
				return nil
			end
			if cur:IsA("Model") or cur:IsA("Tool") then
				return cur
			end
			cur = cur.Parent
		end
		return nil
	end

	local function pickKeyTarget(holder)
		local container = (holder:IsA("Model") or holder:IsA("Tool")) and holder or nearestContainer(holder)

		if container and container ~= Workspace and not keyIgnored(container.Name)
			and (container == holder or Match.keyStrong(container.Name) or Match.keyWord(container.Name)) then

			if extentSize(container) <= CFG.MaxKeySize then
				return container
			end
		end

		return holder
	end

	local DONE_TRUE_WORDS = {
		"activated", "used", "completed", "collected", "opened", "done", "taken",
		"unlocked", "finished", "pressed", "solved", "triggered", "interacted",
		"claimed", "picked", "disabled",
	}
	local DONE_FALSE_WORDS = {
		"available", "interactable", "canuse", "caninteract", "usable", "enabled",
	}

	local function hasWord(name, words)
		name = tostring(name):lower()
		if name:find("unused", 1, true) or name:find("notused", 1, true) then
			return false
		end
		for _, w in ipairs(words) do
			if name:find(w, 1, true) then
				return true
			end
		end
		return false
	end

	local function stateDone(inst)
		for name, value in pairs(inst:GetAttributes()) do
			if type(value) == "boolean" then
				if value and hasWord(name, DONE_TRUE_WORDS) then return true end
				if (not value) and hasWord(name, DONE_FALSE_WORDS) then return true end
			end
		end

		for _, child in ipairs(inst:GetChildren()) do
			if child:IsA("BoolValue") then
				if child.Value and hasWord(child.Name, DONE_TRUE_WORDS) then return true end
				if (not child.Value) and hasWord(child.Name, DONE_FALSE_WORDS) then return true end
			end
		end

		return false
	end

	local function removeItem(target)
		local e = items[target]
		if not e then return end
		items[target] = nil
		if e.highlight then e.highlight:Destroy() end
		if e.gui then e.gui:Destroy() end
	end

	local function registerItem(kind, target, opts)
		if stopped then return end
		opts = opts or {}

		local e = items[target]
		if not e then
			local root = getItemRoot(target)
			if not root then return end

			e = {
				kind = kind,
				target = target,
				root = root,
				prompts = {},
				hadPrompt = false,
				done = false,
				sawDisabled = false,
				valid = true,
				lastCheck = 0,
				defTry = 0,
			}
			items[target] = e

			target.AncestryChanged:Connect(function(_, parent)
				if not parent then
					removeItem(target)
				end
			end)
		end

		if opts.isCard then e.isCard = true end
		if opts.text and opts.text ~= "" then e.text = opts.text end
		if opts.holder then e.holder = opts.holder end

		if kind == "door" or kind == "reader" then
			e.def = opts.def
			e.isReader = opts.isReader
		end

		local prompt = opts.prompt
		if prompt and not table.find(e.prompts, prompt) then
			e.prompts[#e.prompts + 1] = prompt
			e.hadPrompt = true

			prompt.Triggered:Connect(function(plr)
				if plr == LocalPlayer then
					e.done = true
					e.sawDisabled = false
				end
			end)

			prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
				if not prompt.Enabled then
					e.sawDisabled = true
				elseif e.done and e.sawDisabled then
					e.done = false
				end
			end)
		end

		local click = opts.click
		if click then
			click.MouseClick:Connect(function()
				e.done = true
			end)
		end
	end

	local function itemDef(e)
		if e.kind == "door" or e.kind == "reader" then
			return e.def
		end
		if e.def ~= nil then
			return e.def
		end
		if os.clock() - e.defTry < 2 then
			return nil
		end
		e.defTry = os.clock()

		local def
		for _, s in ipairs(namesChain(e.target, 4)) do
			def = colorFromText(s)
			if def then break end
		end
		if not def then def = colorFromAttributes(e.target) end
		if not def and e.holder then def = colorFromAttributes(e.holder) end
		if not def and e.text then def = colorFromText(e.text) end
		if not def and e.isCard then def = colorFromParts(e.target) end

		if def then
			e.def = def
		end
		return def
	end

	local function considerPrompt(d)
		local holder = d.Parent
		if holder and holder:IsA("Attachment") then
			holder = holder.Parent
		end
		if not holder or holder == Workspace or forbiddenHolder(holder) then
			return
		end

		local prompt = d:IsA("ProximityPrompt") and d or nil
		local target = pickKeyTarget(holder)

		local names = { target.Name, holder.Name }
		if prompt then
			names[#names + 1] = prompt.ObjectText
		end

		for _, s in ipairs(names) do
			if s ~= "" and keyIgnored(s) then
				return
			end
		end

		local matched, isCard = false, false
		for _, s in ipairs(names) do
			if s ~= "" and (Match.keyStrong(s) or Match.keyWord(s)) then
				matched = true
				if Match.keyStrong(s) or Match.cardWord(s) then
					isCard = true
				end
			end
		end

		if matched then
			registerItem("key", target, {
				prompt = prompt,
				click = (not prompt) and d or nil,
				text = prompt and prompt.ObjectText or nil,
				isCard = isCard,
				holder = holder,
			})
			dbg("card/key:", target:GetFullName())
		end
	end

	local function considerNamedKey(d)
		local name = d.Name
		if Match.keyStrong(name) and not keyIgnored(name) and not forbiddenHolder(d) then
			if d:IsA("BasePart") then
				local parent = d.Parent
				if parent and parent ~= Workspace and (parent:IsA("Model") or parent:IsA("Tool"))
					and Match.keyStrong(parent.Name) then
					return
				end
			end
			if extentSize(d) <= CFG.MaxKeySize then
				registerItem("key", d, { isCard = true })
				dbg("card (name):", d:GetFullName())
			end
		end
	end

	local function considerDoorLike(d)
		local name = d.Name

		if Match.reader(name) then
			if not forbiddenHolder(d) then
				readers[d] = true
			end
			return
		end

		if Match.door(name) and not Match.doorIgn(name) then
			local p = d.Parent
			if p and p ~= Workspace and p:IsA("Model") and Match.door(p.Name) and not Match.doorIgn(p.Name) then
				return
			end
			if forbiddenHolder(d) or extentSize(d) > 80 then
				return
			end

			local def = nil
			for _, s in ipairs(namesChain(d, 2)) do
				def = colorFromText(s)
				if def then break end
			end
			if not def then def = colorFromAttributes(d) end
			if not def then
				def = colorFromParts(d, function(part)
					return part.Transparency < 0.9
				end)
			end

			if def and (def.id == "red" or def.id == "blue" or def.id == "yellow") then
				doorCands[d] = true
				dbg("key door:", d:GetFullName(), def.id)
			end
		end
	end

	local function readerColor(r)
		local c = readerCache[r]
		if c and os.clock() - c.t < 5 then
			return c.def
		end

		local def
		for _, s in ipairs(namesChain(r, 3)) do
			def = colorFromText(s)
			if def then break end
		end
		if not def then def = colorFromAttributes(r) end
		if not def then
			for _, d in ipairs(r:GetDescendants()) do
				if d:IsA("ProximityPrompt") then
					def = colorFromText(d.ObjectText) or colorFromText(d.ActionText)
					if def then break end
				end
			end
		end
		if not def then
			def = colorFromParts(r, function(p)
				return Match.colorPart(p.Name)
			end)
		end

		readerCache[r] = { t = os.clock(), def = def }
		return def
	end

	local function doorAccess(door)
		for _, s in ipairs(namesChain(door, 2)) do
			local def = colorFromText(s)
			if def then return true, def end
		end

		local def = colorFromAttributes(door)
		if def then return true, def end

		local generic = false
		for _, d in ipairs(door:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				for _, s in ipairs({ d.ObjectText, d.ActionText }) do
					local dc = colorFromText(s)
					if dc then return true, dc end
					if s ~= "" and (Match.keyStrong(s) or Match.keyWord(s)) then
						generic = true
					end
				end
			end
		end

		local root = getItemRoot(door)
		if root then
			local best, bestD
			for r in pairs(readers) do
				if r.Parent then
					local rr = getItemRoot(r)
					if rr then
						local dd = (rr.Position - root.Position).Magnitude
						if dd <= CFG.ReaderRadius and (not bestD or dd < bestD) then
							best, bestD = r, dd
						end
					end
				end
			end
			if best then
				return true, readerColor(best)
			end
		end

		if generic then
			return true, nil
		end

		return false, nil
	end

	function Items.resolveDoors()
		local now = os.clock()

		for door in pairs(doorCands) do
			if door.Parent then
				local e = items[door]
				if not e then
					if not (doorNeg[door] and doorNeg[door] > now) then
						local ok, found, def = pcall(doorAccess, door)
						if ok and found then
							registerItem("door", door, { def = def })
							dbg("door:", door:GetFullName(), def and def.id or "unknown color")
						else
							doorNeg[door] = now + 8
						end
					end
				elseif e.def == nil and now - e.defTry >= 5 then
					e.defTry = now
					local ok, found, def = pcall(doorAccess, door)
					if ok and found and def then
						e.def = def
					end
				end
			end
		end

		for r in pairs(readers) do
			if r.Parent and not items[r] then
				local rr = getItemRoot(r)
				if rr then
					local near = false
					for door in pairs(doorCands) do
						if door.Parent then
							local dr = getItemRoot(door)
							if dr and (dr.Position - rr.Position).Magnitude <= CFG.ReaderRadius then
								near = true
								break
							end
						end
					end
					if not near then
						registerItem("reader", r, { def = readerColor(r), isReader = true })
					end
				end
			end
		end
	end

	local function computeValid(e)
		local target = e.target

		if not target:IsDescendantOf(Workspace) then
			return false
		end
		if forbiddenHolder(target) then
			return false
		end
		if target:IsA("BasePart") and target.Transparency >= 0.95 then
			return false
		end
		if stateDone(target) then
			return false
		end

		for _, p in ipairs(e.prompts) do
			if stateDone(p) then
				return false
			end
			local h = p.Parent
			if h and h ~= target and stateDone(h) then
				return false
			end
		end

		return true
	end

	local function isActive(e)
		if e.done then
			return false
		end

		if e.hadPrompt then
			local anyOn = false
			for _, p in ipairs(e.prompts) do
				if p.Enabled and p:IsDescendantOf(Workspace) then
					anyOn = true
					break
				end
			end
			if not anyOn then
				return false
			end
		end

		local now = os.clock()
		if now - e.lastCheck >= 0.5 then
			e.lastCheck = now
			e.valid = computeValid(e)
		end

		return e.valid
	end

	local function ensureVisuals(e)
		if not (e.highlight and e.highlight.Parent) then
			e.highlight = new("Highlight", {
				Name = "VNMA0_ItemHighlight",
				FillTransparency = 0.35,
				OutlineTransparency = 0,
				DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
				Enabled = false,
			}, e.target)
			e.applied = nil
		end

		if not (e.gui and e.gui.Parent) then
			e.gui = new("BillboardGui", {
				Name = "VNMA0_ItemLabel",
				Adornee = e.root,
				Size = UDim2.fromOffset(250, 40),
				StudsOffset = Vector3.new(0, (e.kind == "door" or e.kind == "reader") and 3 or 1.5, 0),
				AlwaysOnTop = true,
				MaxDistance = CFG.ItemDistance,
				Enabled = false,
			}, e.target)

			e.label = new("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextStrokeTransparency = 0.1,
				TextWrapped = true,
			}, e.gui)
			e.applied = nil
		end
	end

	local function labelFor(e, def, dist)
		local text
		if e.kind == "door" then
			local a = def and (def.f .. " дверь") or "Дверь"
			local b = def and ("нужна: " .. def.fl .. " ключ-карта") or "нужна ключ-карта"
			text = string.format("%s  [%d]\n%s", a, dist, b)
		elseif e.kind == "reader" then
			local a = def and (def.f .. " терминал") or "Терминал"
			local b = def and ("нужна: " .. def.fl .. " ключ-карта") or "нужна ключ-карта"
			text = string.format("%s  [%d]\n%s", a, dist, b)
		elseif e.isCard then
			text = string.format("%s  [%d]", def and (def.f .. " ключ-карта") or "Ключ-карта", dist)
		else
			text = string.format("%s  [%d]", def and (def.m .. " ключ") or "Ключ", dist)
		end
		return text
	end

	function Items.update(origin)
		local keyList, doorList = {}, {}

		for _, e in pairs(items) do
			local wanted = (e.kind == "door" and CFG.ShowDoors) or (e.kind == "reader" and CFG.ShowDoors) or (e.kind ~= "door" and e.kind ~= "reader" and CFG.ShowCards)

			if wanted then
				local root = e.root
				if not root or not root.Parent then
					root = getItemRoot(e.target)
					e.root = root
				end

				if root then
					local d = (root.Position - origin).Magnitude
					if d <= CFG.ItemDistance and isActive(e) then
						local list = (e.kind == "door" or e.kind == "reader") and doorList or keyList
						list[#list + 1] = { e = e, d = d }
					end
				end
			end
		end

		local shown = {}

		local function show(list, cap)
			table.sort(list, function(a, b) return a.d < b.d end)
			for i, item in ipairs(list) do
				local e = item.e
				if pcall(ensureVisuals, e) then
					shown[e] = true

					local def = itemDef(e)
					local color = def and def.rgb or DEFAULT_COLOR
					if e.applied ~= color then
						e.applied = color
						e.highlight.FillColor = color
						e.highlight.OutlineColor = color:Lerp(WHITE, 0.4)
						e.label.TextColor3 = color:Lerp(WHITE, 0.2)
					end

					e.highlight.Enabled = i <= cap
					e.gui.Enabled = true
					e.label.Text = labelFor(e, def, math.floor(item.d))
				end
			end
			return math.min(#list, cap)
		end

		local used = show(keyList, CFG.MaxKeyHighlights) + show(doorList, CFG.MaxDoorHighlights)

		for _, e in pairs(items) do
			if not shown[e] then
				if e.highlight then e.highlight.Enabled = false end
				if e.gui then e.gui.Enabled = false end
			end
		end

		return used
	end

	function Items.consider(d)
		if stopped then return end

		if d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
			considerPrompt(d)
		elseif d:IsA("Model") or d:IsA("BasePart") or d:IsA("Tool") then
			considerNamedKey(d)
			if not d:IsA("Tool") then
				considerDoorLike(d)
			end
		end
	end

	function Items.clear()
		for target in pairs(items) do
			removeItem(target)
		end
	end
end

-- =========================================================
-- СКАН МИРА
-- =========================================================
local function onDescendant(d)
	if d:IsA("Humanoid") then
		Npc.onHumanoidAdded(d)
	elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
		task.defer(Items.consider, d)
	elseif d:IsA("ParticleEmitter") then
		if Match.fog(d.Name) then
			Light.registerEmitter(d)
		end
	elseif d:IsA("ColorCorrectionEffect") then
		Light.registerCC(d)
	else
		if d:IsA("Model") then
			Npc.trackNamedModel(d)
		elseif d:IsA("BasePart") and Match.fog(d.Name) then
			Light.registerFogPart(d)
		end
		Items.consider(d)
	end
end

bind(Workspace.DescendantAdded, onDescendant)

-- Разбитый на мелкие пачки стартовый скан — не подвешивает игру
task.spawn(function()
	task.wait(0.1)
	local ok, all = pcall(function()
		return Workspace:GetDescendants()
	end)
	if not ok or type(all) ~= "table" then
		warn("[VNMA-SCRIPT] initial scan failed, continuing without it")
		return
	end
	for i = 1, #all do
		if stopped then return end
		local d = all[i]
		pcall(onDescendant, d)
		if i % 200 == 0 then
			task.wait()
		end
	end
end)

-- =========================================================
-- FOV
-- =========================================================
local Fov = {}
do
	local NAME = "VNMA0_FOV"
	local FOV_PRIORITY = Enum.RenderPriority.Last.Value + 1000
	local state = {
		baseline = nil,
		cam = nil,
		camConn = nil,
	}

	local function hookCamera(cam)
		if state.camConn then
			state.camConn:Disconnect()
			state.camConn = nil
		end
		state.cam = cam
		state.baseline = nil

		-- Как только игра меняет FOV (прицел / выход из прицела), сразу возвращаем свой
		state.camConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
			if stopped or not CFG.FOVEnabled or state.baseline == nil then return end
			if cam.FieldOfView ~= CFG.FOV then
				cam.FieldOfView = CFG.FOV
			end
		end)
	end

	local function step()
		if stopped then return end

		local cam = Workspace.CurrentCamera
		if not cam then return end

		if state.cam ~= cam then
			hookCamera(cam)
		end

		if not CFG.FOVEnabled then
			state.baseline = nil
			return
		end

		if not state.baseline then
			state.baseline = cam.FieldOfView
		end

		if cam.FieldOfView ~= CFG.FOV then
			cam.FieldOfView = CFG.FOV
		end
	end

	function Fov.start()
		pcall(function()
			RunService:UnbindFromRenderStep(NAME)
			RunService:BindToRenderStep(NAME, FOV_PRIORITY, step)
		end)
		bind(RunService.RenderStepped, step)
		bind(RunService.Heartbeat, step)
		bind(Workspace:GetPropertyChangedSignal("CurrentCamera"), step)
	end

	function Fov.restore()
		local cam = state.cam
		if cam and state.baseline then
			cam.FieldOfView = state.baseline
		end
		state.baseline = nil
	end

	function Fov.stop()
		pcall(function() RunService:UnbindFromRenderStep(NAME) end)
		Fov.restore()
		if state.camConn then
			state.camConn:Disconnect()
			state.camConn = nil
		end
	end
end

-- =========================================================
-- AIM BOT (мягкая наводка на заражённых)
-- =========================================================
local Aim = {}
do
	local NAME = "VNMA0_AIM"

	local rayParams = RaycastParams.new()
	pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Exclude end)
	pcall(function() rayParams.RespectCanCollide = true end)

	Aim.mobileOn = false      -- состояние круглой кнопки AIM (телефон)
	local pcToggled = false   -- состояние для режима "ПКМ включает/выключает"

	function Aim.resetPC()
		pcToggled = false
	end

	-- ПК: ПКМ (держать или переключать)
	bind(UserInputService.InputBegan, function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
		if not CFG.AimPC or CFG.AimPCHold then return end
		if UserInputService:GetFocusedTextBox() then return end
		pcToggled = not pcToggled
	end)

	local function pcActive()
		if not CFG.AimPC then return false end
		if CFG.AimPCHold then
			return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		end
		return pcToggled
	end

	local function isActive()
		return (CFG.AimMobile and Aim.mobileOn)
			or pcActive()
	end

	local function pickPart(e)
		local m = e.model
		return m:FindFirstChild(CFG.AimPart) or m:FindFirstChild("Head") or getRoot(m)
	end

	local function visible(cam, part, model)
		local ignore = { cam, model }
		local char = LocalPlayer.Character
		if char then ignore[#ignore + 1] = char end
		rayParams.FilterDescendantsInstances = ignore
		local origin = cam.CFrame.Position
		return Workspace:Raycast(origin, part.Position - origin, rayParams) == nil
	end

	local function findTarget(cam)
		local camCF = cam.CFrame
		local look = camCF.LookVector
		local best, bestAngle

		for model, e in pairs(Npc.targets()) do
			local hum = e.humanoid
			if model.Parent and hum and hum.Parent and hum.Health > 0 then
				local part = pickPart(e)
				if part and part.Parent then
					local offset = part.Position - camCF.Position
					local dist = offset.Magnitude
					if dist > 3 and dist <= CFG.AimDistance then
						local angle = math.deg(math.acos(math.clamp(look:Dot(offset.Unit), -1, 1)))
						if angle <= CFG.AimFOV and (not bestAngle or angle < bestAngle) then
							if not CFG.AimWallCheck or visible(cam, part, model) then
								best, bestAngle = part, angle
							end
						end
					end
				end
			end
		end

		return best
	end

	local function step(dt)
		if stopped or not isActive() then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end

		local part = findTarget(cam)
		if not part then return end

		local cf = cam.CFrame
		local goal = CFrame.lookAt(cf.Position, part.Position)
		local alpha = math.clamp(CFG.AimSmooth * dt * 60, 0, 1)
		cam.CFrame = cf:Lerp(goal, alpha)
	end

	function Aim.start()
		pcall(function()
			RunService:UnbindFromRenderStep(NAME)
		end)
		RunService:BindToRenderStep(NAME, Enum.RenderPriority.Camera.Value + 1, step)
	end

	function Aim.stop()
		CFG.AimPC = false
		CFG.AimMobile = false
		Aim.mobileOn = false
		pcToggled = false
		pcall(function() RunService:UnbindFromRenderStep(NAME) end)
	end
end

-- =========================================================
-- ГЛАВНЫЙ ЦИКЛ
-- =========================================================
local function step()
	local char = LocalPlayer.Character
	local myRoot = char and getRoot(char)
	if not myRoot then return end
	local origin = myRoot.Position
	local cam = Workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position

	local okA, usedAllies = pcall(Allies.update, origin)
	if not okA then
		dbg("allies error:", usedAllies)
		usedAllies = 0
	end

	local okI, usedItems = pcall(Items.update, origin)
	if not okI then
		dbg("items error:", usedItems)
		usedItems = 0
	end

	local ok, err = pcall(Npc.update, origin, camPos, CFG.MaxHighlights - usedAllies - usedItems)
	if not ok then
		dbg("npc error:", err)
	end
end

local acc, resolveAcc = 0, 0

bind(RunService.Heartbeat, function(dt)
	resolveAcc += dt
	if resolveAcc >= 2 then
		resolveAcc = 0
		if CFG.ShowDoors then
			pcall(Items.resolveDoors)
		end
	end

	acc += dt
	if acc < CFG.UpdateRate then return end
	acc = 0

	local ok, err = pcall(step)
	if not ok then
		dbg("step error:", err)
	end
end)

do
	local okF, errF = pcall(Fov.start)
	if not okF then reportError("FOV", errF) end

	local okA, errA = pcall(Aim.start)
	if not okA then reportError("AIM", errA) end
end
print("[VNMA-SCRIPT] core started")

-- =========================================================
-- GUI
-- =========================================================
local screenGui
local okGui, errGui = pcall(function()
	local C = {
		bg = Color3.fromRGB(9, 9, 11),
		panel = Color3.fromRGB(18, 18, 22),
		panel2 = Color3.fromRGB(27, 27, 33),
		line = Color3.fromRGB(58, 42, 26),
		orange = Color3.fromRGB(255, 140, 0),
		orangeLight = Color3.fromRGB(255, 186, 82),
		orangeDark = Color3.fromRGB(190, 88, 0),
		text = Color3.fromRGB(244, 244, 247),
		muted = Color3.fromRGB(150, 150, 160),
		off = Color3.fromRGB(46, 46, 54),
		dark = Color3.fromRGB(14, 14, 14),
	}
	local TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local WHITE = Color3.new(1, 1, 1)

	local function corner(inst, r)
		return new("UICorner", { CornerRadius = UDim.new(0, r) }, inst)
	end
	local function stroke(inst, color, thickness, transparency)
		return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0 }, inst)
	end
	local function gradient(inst, c0, c1, rotation)
		return new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 0 }, inst)
	end
	local function escapeRich(s)
		s = tostring(s)
		s = s:gsub("&", "&amp;")
		s = s:gsub("<", "&lt;")
		s = s:gsub(">", "&gt;")
		return s
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		-- запасной вариант, если PlayerGui не найден
		local okH, hui = pcall(function()
			return gethui and gethui()
		end)
		if okH and typeof(hui) == "Instance" then
			playerGui = hui
		end
	end
	if not playerGui then
		warn("[VNMA-SCRIPT] PlayerGui not found")
		return
	end

	local old = playerGui:FindFirstChild("VNMA0_ESP_GUI")
	if old then old:Destroy() end

	screenGui = new("ScreenGui", {
		Name = "VNMA0_ESP_GUI",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	local main = new("Frame", {
		Name = "Main",
		Size = UDim2.fromOffset(440, 300),
		Position = UDim2.new(0, 20, 0.5, -150),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
		Active = true,
	}, screenGui)
	corner(main, 14)
	gradient(stroke(main, WHITE, 1.5, 0.05), C.orangeLight, C.orangeDark, 45)

	local header = new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		Active = true,
	}, main)

	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.fromOffset(14, 5),
		BackgroundTransparency = 1,
		RichText = true,
		Text = '<font color="#FF8C00">VNMA-SCRIPT</font>',
		TextColor3 = C.text,
		TextSize = 17,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 12),
		Position = UDim2.fromOffset(14, 26),
		BackgroundTransparency = 1,
		Text = "TGK: VNMA0  |  black & orange",
		TextColor3 = C.muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	local minimize = new("TextButton", {
		Name = "Minimize",
		Size = UDim2.fromOffset(28, 28),
		Position = UDim2.new(1, -38, 0, 8),
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		Text = "-",
		TextColor3 = C.orange,
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = true,
	}, header)
	corner(minimize, 8)

	local headerLine = new("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.new(0, 12, 0, 44),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, main)
	gradient(headerLine, C.orangeDark, C.orangeLight, 0)

	local sidebar = new("Frame", {
		Size = UDim2.fromOffset(104, 240),
		Position = UDim2.fromOffset(8, 52),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, main)
	corner(sidebar, 10)
	stroke(sidebar, C.line, 1, 0)
	new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, sidebar)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

	local pagesHolder = new("Frame", {
		Size = UDim2.fromOffset(312, 240),
		Position = UDim2.fromOffset(120, 52),
		BackgroundTransparency = 1,
	}, main)

	local pages, tabs = {}, {}

	local function styleTab(tab, active)
		tab.button.BackgroundColor3 = active and WHITE or C.panel2
		tab.grad.Enabled = active
		tab.button.TextColor3 = active and C.dark or C.muted
	end

	local function selectTab(id)
		for pid, page in pairs(pages) do
			page.Visible = (pid == id)
		end
		for tid, tab in pairs(tabs) do
			styleTab(tab, tid == id)
		end
	end

	local function createTab(order, id, text)
		local button = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 38),
			BackgroundColor3 = C.panel2,
			BorderSizePixel = 0,
			Text = text,
			TextColor3 = C.muted,
			TextSize = 12,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = false,
			LayoutOrder = order,
		}, sidebar)
		corner(button, 9)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, button)
		local grad = gradient(button, C.orangeLight, C.orangeDark, 0)
		grad.Enabled = false
		tabs[id] = { button = button, grad = grad }
		button.Activated:Connect(function()
			selectTab(id)
		end)
	end

	createTab(1, "home", "Главная")
	createTab(2, "visual", "Visual")
	createTab(3, "aim", "AIM BOT")
	createTab(4, "social", "Соц сети")

	local function createToggle(parent, order, text, key, onChange, height)
		local row = new("TextButton", {
			Size = UDim2.new(1, 0, 0, height or 36),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
		}, parent)
		corner(row, 9)
		local st = stroke(row, C.line, 1, 0)

		local label = new("TextLabel", {
			Size = UDim2.new(1, -66, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextSize = 13,
			Font = Enum.Font.GothamSemibold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.muted,
		}, row)

		local track = new("Frame", {
			Size = UDim2.fromOffset(38, 20),
			Position = UDim2.new(1, -48, 0.5, -10),
			BackgroundColor3 = C.off,
			BorderSizePixel = 0,
		}, row)
		corner(track, 10)
		local grad = gradient(track, C.orangeLight, C.orangeDark, 0)
		grad.Enabled = false

		local knob = new("Frame", {
			Size = UDim2.fromOffset(14, 14),
			Position = UDim2.fromOffset(3, 3),
			BackgroundColor3 = C.muted,
			BorderSizePixel = 0,
		}, track)
		corner(knob, 7)

		local function refresh()
			local on = CFG[key]
			grad.Enabled = on

			TweenService:Create(track, TWEEN, { BackgroundColor3 = on and WHITE or C.off }):Play()
			TweenService:Create(knob, TWEEN, {
				Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3),
				BackgroundColor3 = on and C.dark or C.muted,
			}):Play()
			TweenService:Create(st, TWEEN, { Color = on and C.orange or C.line }):Play()
			TweenService:Create(label, TWEEN, { TextColor3 = on and C.text or C.muted }):Play()
		end

		row.Activated:Connect(function()
			CFG[key] = not CFG[key]
			refresh()
			if onChange then
				onChange()
			end
		end)

		refresh()
		return row, refresh
	end

	-- строка со значением и кнопками  -  /  +
	local function createStepper(parent, order, text, key, minV, maxV, stepV, fmt)
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 36),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			LayoutOrder = order,
		}, parent)
		corner(row, 9)
		stroke(row, C.line, 1, 0)

		new("TextLabel", {
			Size = UDim2.new(1, -120, 1, 0),
			Position = UDim2.fromOffset(12, 0),
			BackgroundTransparency = 1,
			Text = text,
			TextSize = 13,
			Font = Enum.Font.GothamSemibold,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.text,
		}, row)

		local valueLabel = new("TextLabel", {
			Size = UDim2.fromOffset(46, 36),
			Position = UDim2.new(1, -84, 0, 0),
			BackgroundTransparency = 1,
			TextSize = 12,
			Font = Enum.Font.GothamBold,
			TextColor3 = C.orange,
		}, row)

		local function refresh()
			valueLabel.Text = string.format(fmt, CFG[key])
		end
		refresh()

		local function makeBtn(txt, x, delta)
			local b = new("TextButton", {
				Size = UDim2.fromOffset(22, 22),
				Position = UDim2.new(1, x, 0.5, -11),
				BackgroundColor3 = C.off,
				BorderSizePixel = 0,
				Text = txt,
				TextColor3 = C.text,
				TextSize = 15,
				Font = Enum.Font.GothamBold,
				AutoButtonColor = true,
			}, row)
			corner(b, 6)
			b.Activated:Connect(function()
				local v = CFG[key] + delta
				v = math.floor(v / stepV + 0.5) * stepV
				CFG[key] = math.clamp(v, minV, maxV)
				refresh()
			end)
		end

		makeBtn("-", -112, -stepV)
		makeBtn("+", -32, stepV)

		return row
	end

	local function sectionTitle(parent, order, text)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = C.orange,
			TextSize = 11,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
		}, parent)
	end

	local function hint(parent, order, text, height)
		return new("TextLabel", {
			Size = UDim2.new(1, 0, 0, height or 26),
			BackgroundTransparency = 1,
			Text = text,
			TextColor3 = C.muted,
			TextSize = 10,
			Font = Enum.Font.Gotham,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			LayoutOrder = order,
		}, parent)
	end

	-- ГЛАВНАЯ
	local home = new("Frame", {
		Name = "Home",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, pagesHolder)
	pages.home = home

	local userCard = new("Frame", {
		Size = UDim2.new(1, 0, 0, 88),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, home)
	corner(userCard, 10)
	stroke(userCard, C.line, 1, 0)

	local avatar = new("ImageLabel", {
		Size = UDim2.fromOffset(62, 62),
		Position = UDim2.fromOffset(12, 13),
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		Image = "",
	}, userCard)
	corner(avatar, 31)
	gradient(stroke(avatar, WHITE, 2, 0), C.orangeLight, C.orangeDark, 45)

	local userText = new("TextLabel", {
		Size = UDim2.new(1, -92, 1, -20),
		Position = UDim2.fromOffset(84, 10),
		BackgroundTransparency = 1,
		RichText = true,
		TextColor3 = C.text,
		TextSize = 13,
		Font = Enum.Font.GothamSemibold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		Text = "",
	}, userCard)

	local placeName = game.Name
	local function refreshUser()
		local nick = LocalPlayer.Name
		if LocalPlayer.DisplayName ~= LocalPlayer.Name then
			nick = nick .. " (" .. LocalPlayer.DisplayName .. ")"
		end
		userText.Text = string.format(
			'<font color="#FF8C00">Ник:</font> %s\n<font color="#FF8C00">Плейс:</font> %s\n<font color="#FF8C00">Игроков:</font> %d/%d',
			escapeRich(nick), escapeRich(placeName), #Players:GetPlayers(), Players.MaxPlayers
		)
	end
	refreshUser()
	bind(Players.PlayerAdded, refreshUser)
	bind(Players.PlayerRemoving, function()
		task.defer(refreshUser)
	end)

	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId,
			Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and not stopped and typeof(img) == "string" then
			avatar.Image = img
		end
	end)

	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(game.PlaceId)
		end)
		if ok and info and info.Name and not stopped then
			placeName = info.Name
			refreshUser()
		end
	end)

	local fovBlock = new("Frame", {
		Size = UDim2.new(1, 0, 0, 132),
		Position = UDim2.fromOffset(0, 96),
		BackgroundColor3 = C.panel,
		BorderSizePixel = 0,
	}, home)
	corner(fovBlock, 10)
	stroke(fovBlock, C.line, 1, 0)

	new("TextLabel", {
		Size = UDim2.fromOffset(120, 18),
		Position = UDim2.fromOffset(12, 8),
		BackgroundTransparency = 1,
		Text = "FOV  (80 - 110)",
		TextColor3 = C.orange,
		TextSize = 12,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, fovBlock)

	local fovValue = new("TextLabel", {
		Size = UDim2.fromOffset(60, 18),
		Position = UDim2.new(1, -72, 0, 8),
		BackgroundTransparency = 1,
		Text = "90",
		TextColor3 = C.text,
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, fovBlock)

	local sliderArea = new("Frame", {
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 32),
		BackgroundTransparency = 1,
	}, fovBlock)

	local track = new("Frame", {
		Size = UDim2.new(1, 0, 0, 8),
		Position = UDim2.new(0, 0, 0.5, -4),
		BackgroundColor3 = C.off,
		BorderSizePixel = 0,
	}, sliderArea)
	corner(track, 4)

	local fill = new("Frame", {
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}, track)
	corner(fill, 4)
	gradient(fill, C.orangeDark, C.orangeLight, 0)

	local knob = new("Frame", {
		Size = UDim2.fromOffset(20, 20),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		ZIndex = 3,
	}, sliderArea)
	corner(knob, 10)
	gradient(stroke(knob, WHITE, 2, 0), C.orangeLight, C.orangeDark, 45)
	gradient(knob, C.orangeLight, C.orangeDark, 90)

	local hitbox = new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 5,
	}, sliderArea)

	new("TextLabel", {
		Size = UDim2.new(1, -24, 0, 12),
		Position = UDim2.fromOffset(12, 62),
		BackgroundTransparency = 1,
		Text = "80                     тяни пальцем или мышкой                     110",
		TextColor3 = C.muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
	}, fovBlock)

	local FOV_MIN, FOV_MAX = 80, 110

	local fovToggle, fovToggleRefresh = createToggle(fovBlock, 1, "Свой FOV", "FOVEnabled", function()
		if not CFG.FOVEnabled then
			Fov.restore()
		end
	end, 30)
	fovToggle.Size = UDim2.new(1, -24, 0, 30)
	fovToggle.Position = UDim2.fromOffset(12, 88)

	local function setFov(value)
		value = math.clamp(math.round(value), FOV_MIN, FOV_MAX)
		CFG.FOV = value
		local a = (value - FOV_MIN) / (FOV_MAX - FOV_MIN)
		fill.Size = UDim2.new(a, 0, 1, 0)
		knob.Position = UDim2.new(a, 0, 0.5, 0)
		fovValue.Text = value .. " deg"
	end

	local function fovFromX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return end
		local a = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
		setFov(FOV_MIN + a * (FOV_MAX - FOV_MIN))
		if not CFG.FOVEnabled then
			CFG.FOVEnabled = true
			fovToggleRefresh()
		end
	end

	do
		local cam = Workspace.CurrentCamera
		setFov(cam and cam.FieldOfView or 90)
	end

	hitbox.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1
			and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		fovFromX(input.Position.X)

		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
				fovFromX(i.Position.X)
			end
		end)
		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
			end
		end)
	end)

	-- КРУГЛАЯ КНОПКА AIM (mobile): зелёная = включён, красная = выключен, двигается пальцем
	local AIM_GREEN = Color3.fromRGB(46, 204, 90)
	local AIM_RED = Color3.fromRGB(220, 55, 55)

	local mobileBtn = new("TextButton", {
		Name = "AimMobileButton",
		Size = UDim2.fromOffset(64, 64),
		Position = UDim2.new(1, -100, 0.55, 0),
		BackgroundColor3 = AIM_RED,
		BorderSizePixel = 0,
		Text = "AIM",
		TextColor3 = WHITE,
		TextSize = 16,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
		Visible = false,
		ZIndex = 10,
	}, screenGui)
	corner(mobileBtn, 32)
	stroke(mobileBtn, WHITE, 2, 0.1)

	local function paintMobileBtn()
		mobileBtn.BackgroundColor3 = Aim.mobileOn and AIM_GREEN or AIM_RED
	end

	local function updateMobileButton()
		if not CFG.AimMobile then
			Aim.mobileOn = false
		end
		mobileBtn.Visible = CFG.AimMobile
		paintMobileBtn()
	end

	mobileBtn.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch
			and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local startPos = input.Position
		local startFramePos = mobileBtn.Position
		local dragged = false
		local moveConn, endConn

		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = i.Position - startPos
				if not dragged and delta.Magnitude > 8 then
					dragged = true
				end
				if dragged then
					mobileBtn.Position = UDim2.new(
						startFramePos.X.Scale, startFramePos.X.Offset + delta.X,
						startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y
					)
				end
			end
		end)

		endConn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				moveConn:Disconnect()
				endConn:Disconnect()
				if not dragged then
					Aim.mobileOn = not Aim.mobileOn
					paintMobileBtn()
				end
			end
		end)
	end)

	-- VISUAL
	local visual = new("ScrollingFrame", {
		Name = "Visual",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.orange,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, pagesHolder)
	pages.visual = visual

	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, visual)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, visual)

	sectionTitle(visual, 1, "| ESP")
	createToggle(visual, 2, "Заражённые", "ShowInfected")
	createToggle(visual, 3, "Союзники", "ShowAllies")

	sectionTitle(visual, 4, "| Окружение")
	createToggle(visual, 5, "Нет тумана", "NoFog", Light.applyFog)
	createToggle(visual, 6, "Без темноты", "NoDark", Light.applyDark)

	sectionTitle(visual, 7, "| [Tunnel]")
	createToggle(visual, 8, "Показать ключ-карту", "ShowCards", function()
		if CFG.ShowCards then pcall(Items.resolveDoors) end
	end)
	createToggle(visual, 9, "Показать двери и терминалы", "ShowDoors", function()
		if CFG.ShowDoors then pcall(Items.resolveDoors) end
	end)
	hint(visual, 10, "Двери: красная, синяя, жёлтая. Терминалы — по цвету нужной карты.")

	-- AIM BOT (отдельная ветка)
	local aim = new("ScrollingFrame", {
		Name = "AimBot",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.orange,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Visible = false,
	}, pagesHolder)
	pages.aim = aim

	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, aim)
	new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, aim)

	sectionTitle(aim, 1, "| AIM BOT")
	createToggle(aim, 2, "[AIM PC]", "AimPC", Aim.resetPC)
	createToggle(aim, 3, "[AIM MB]", "AimMobile", updateMobileButton)
	hint(aim, 4, "ПК: включи [AIM PC] и держи правую кнопку мыши. Телефон: включи [AIM MB] - на экране появится круглая кнопка AIM (зелёная = вкл, красная = выкл), её можно двигать пальцем.", 52)

	sectionTitle(aim, 5, "| [настройки AIM BOT]")
	createToggle(aim, 6, "Проверка стен", "AimWallCheck")
	createStepper(aim, 7, "Угол захвата", "AimFOV", 5, 60, 5, "%d°")
	createStepper(aim, 8, "Плавность", "AimSmooth", 0.05, 1, 0.05, "%.2f")
	hint(aim, 9, "Меньше плавность = мягче и незаметнее. Аим целится в заражённых рядом с центром экрана.", 40)

	-- СОЦ СЕТИ
	local social = new("Frame", {
		Name = "Social",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
	}, pagesHolder)
	pages.social = social

	new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, social)

	local clip = (typeof(setclipboard) == "function" and setclipboard)
		or (typeof(toclipboard) == "function" and toclipboard)
		or nil

	local function createSocialRow(order, icon, title, value, copyValue)
		local row = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = order,
		}, social)
		corner(row, 10)
		stroke(row, C.line, 1, 0)

		local badge = new("TextLabel", {
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.fromOffset(10, 9),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Text = icon,
			TextSize = 20,
			Font = Enum.Font.GothamBold,
			TextColor3 = C.dark,
		}, row)
		corner(badge, 10)
		gradient(badge, C.orangeLight, C.orangeDark, 45)

		new("TextLabel", {
			Size = UDim2.new(1, -70, 0, 16),
			Position = UDim2.fromOffset(58, 10),
			BackgroundTransparency = 1,
			Text = title,
			TextColor3 = C.orange,
			TextSize = 11,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		local valueLabel = new("TextLabel", {
			Size = UDim2.new(1, -70, 0, 20),
			Position = UDim2.fromOffset(58, 26),
			BackgroundTransparency = 1,
			Text = value,
			TextColor3 = C.text,
			TextSize = 15,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
		}, row)

		if copyValue then
			row.Activated:Connect(function()
				local ok = clip and pcall(clip, copyValue)
				valueLabel.Text = ok and "Скопировано OK" or "Копирование недоступно"
				task.delay(1.4, function()
					if valueLabel.Parent then
						valueLabel.Text = value
					end
				end)
			end)
		end
	end

	createSocialRow(1, "@", "СОЗДАТЕЛЬ СКРИПТА", "VNMA", nil)
	createSocialRow(2, ">", "TGK", "VNMA0", "VNMA0")
	createSocialRow(3, "#", "TIKTOK", "vnma_official", "vnma_official")

	hint(social, 4, "Нажми на строку - скопируется ник.")

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

	local mini = new("TextButton", {
		Name = "Mini",
		Size = UDim2.fromOffset(50, 50),
		Position = main.Position,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Text = "V",
		TextColor3 = C.dark,
		TextSize = 22,
		Font = Enum.Font.GothamBold,
		Visible = false,
	}, screenGui)
	corner(mini, 14)
	gradient(mini, C.orangeLight, C.orangeDark, 45)

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

	selectTab("home")
end)

if okGui then
	print("[VNMA-SCRIPT] GUI created")
else
	reportError("GUI", errGui)
end

-- =========================================================
-- ПОЛНАЯ ОСТАНОВКА
-- =========================================================
if type(env) == "table" then
	env.VNMA0_ESP_STOP = function()
		stopped = true

		pcall(Light.restoreAll)
		pcall(Fov.stop)
		pcall(Aim.stop)

		for _, c in ipairs(connections) do
			c:Disconnect()
		end

		pcall(Npc.clear)
		pcall(Items.clear)
		pcall(Allies.clear)

		if screenGui then
			screenGui:Destroy()
		end
	end
end

print("[VNMA-SCRIPT] ready")

end -- main

local okMain, errMain = xpcall(main, function(e)
	return debug.traceback(tostring(e), 2)
end)
if not okMain then
	reportError("запуск", errMain)
end
