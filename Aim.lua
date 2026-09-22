print("[VNMA SCRIPT] loading...")

-- =========================================================
-- ОБРАБОТКА ОШИБОК
-- =========================================================
local function reportError(where, err)
	warn("[VNMA SCRIPT] ERROR (" .. tostring(where) .. "): " .. tostring(err))
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", {
			Title = "VNMA SCRIPT: ошибка",
			Text = string.sub(tostring(where) .. ": " .. tostring(err), 1, 180),
			Duration = 12,
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
local HttpService = game:GetService("HttpService")

local VirtualUser
do
	local ok, v = pcall(function() return game:GetService("VirtualUser") end)
	VirtualUser = (ok and v) or nil
end

local LocalPlayer = Players.LocalPlayer

-- =========================================================
-- ЗАЩИТА ОТ ДВОЙНОГО ЗАПУСКА
-- =========================================================
local env
do
	local ok, g = pcall(function() return getgenv and getgenv() end)
	env = (ok and type(g) == "table") and g or _G
end

if type(env) == "table" and env.VNMA0_ESP_STOP then
	pcall(env.VNMA0_ESP_STOP)
	print("[VNMA SCRIPT] previous instance stopped")
end

local stopped = false
local connections = {}
local function bind(signal, fn)
	local c = signal:Connect(fn)
	connections[#connections + 1] = c
	return c
end

if type(env) == "table" then
	env.VNMA0_ESP_STOP = function()
		stopped = true
		for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
	end
end

-- =========================================================
-- УТИЛИТЫ
-- =========================================================
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local HAS_DRAWING = (typeof(Drawing) == "table")
local function newDrawing(class, props)
	if not HAS_DRAWING then return nil end
	local ok, obj = pcall(Drawing.new, class)
	if not ok or not obj then return nil end
	for k, v in pairs(props or {}) do pcall(function() obj[k] = v end) end
	return obj
end
local function destroyDrawing(obj)
	if obj then pcall(function() obj:Remove() end) end
end

local function getRoot(char)
	return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
end

local function hasFileAPI()
	return typeof(writefile) == "function" and typeof(readfile) == "function"
		and typeof(isfile) == "function" and typeof(delfile) == "function"
end

local SESSION_START = os.clock()
local function formatTime(sec)
	sec = math.floor(sec)
	local h = math.floor(sec / 3600)
	local m = math.floor((sec % 3600) / 60)
	local s = sec % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function getDeviceTypeKey()
	local ok, res = pcall(function()
		if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled then
			return "device_console"
		elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
			return "device_mobile"
		else
			return "device_pc"
		end
	end)
	return ok and res or "device_pc"
end

-- =========================================================
-- НАСТРОЙКИ (CFG)
-- =========================================================
local function buildDefaultCFG()
	return {
		Language = "RU", -- "RU" или "US"

		-- AIM
		AimPC = false,
		AimPCMode = "hold", -- hold / toggle
		AimMB = false,
		AimPart = "Head",   -- Head / Torso / Nearest
		AimSmooth = 0.15,
		AimFOV = 120,        -- радиус захвата в пикселях
		AimDistance = 1000,
		AimDelay = 0,
		AimWallCheck = true,
		AimPriority = "center", -- center / hp / distance
		AimMode = "normal",      -- normal / fixed
		AimShowCircle = false,   -- круг FOV для аима (Drawing)

		-- FOV ЭКРАНА (зум камеры, не связан с аимом)
		CamFOVEnabled = false,
		CamFOV = 90,

		-- ESP
		EspEnabled = false,
		EspName = true,
		EspBox = true,
		EspChams = false,
		EspChamsTransparency = 0.65,
		EspHP = true,
		EspDistance = true,
		EspTracer = false,

		-- ВИЗУАЛ
		ColorBoxIndex = 1,
		ColorNameIndex = 1,
		ColorDistIndex = 1,
		ColorTracerIndex = 1,
		ColorChamsIndex = 1,
		BoxThickness = 1,
		LineThickness = 1,
		NoFog = false,
		NoDark = false,

		-- MISC PLAYER
		WalkSpeed = 16,
		JumpPower = 50,
		InfiniteJump = false,
		AntiAFK = false,
		ShowFPSPing = false,

		-- КЕЙБИНДЫ
		KeyAim = "Q",
		KeyESP = "E",
		KeyFriends = "F",
		KeyMenu = "RightControl",
	}
end

local DEFAULT_CFG = buildDefaultCFG()
local CFG = buildDefaultCFG()

local PALETTE = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 140, 0),
	Color3.fromRGB(255, 60, 60),
	Color3.fromRGB(60, 255, 100),
	Color3.fromRGB(70, 140, 255),
	Color3.fromRGB(255, 220, 40),
	Color3.fromRGB(185, 95, 255),
	Color3.fromRGB(60, 225, 235),
}
local FRIEND_COLOR = Color3.fromRGB(60, 255, 100)

-- =========================================================
-- ЛОКАЛИЗАЦИЯ
-- =========================================================
local L = {}
L.RU = {
	tab_profile = "Профиль", tab_aim = "AIM", tab_friends = "Друзья", tab_esp = "ESP", tab_visual = "Визуал",
	tab_save = "Сохранение", tab_logs = "Логи", tab_keybinds = "Кейбинды", tab_social = "Соц сети",
	tab_misc = "Настройки игрока",

	profile_session = "Сессия:", profile_nick = "Ник:", profile_display = "DisplayName:",
	profile_device = "Устройство:", profile_players = "Игроков:", profile_language = "Язык",
	device_pc = "ПК", device_mobile = "Телефон", device_console = "Консоль",

	aim_sec_toggles = "| AIM PC / MB",
	aim_toggle_pc = "AIM PC",
	aim_pc_mode_label = "Режим ПКМ",
	opt_hold = "держать", opt_toggle = "переключение",
	aim_toggle_mb = "AIM MB",
	aim_hint_toggles = "ПК: держи ПКМ (или переключай в режиме \"переключение\"). Телефон: включи AIM MB — появится круглая кнопка на экране.",

	aim_sec_general = "| Общие настройки",
	aim_part_label = "Часть тела",
	opt_head = "Голова", opt_torso = "Торс", opt_nearest = "Ближайшая",
	aim_smooth = "Плавность",
	aim_capture_radius = "Радиус захвата (px)",
	aim_distance = "Дистанция",
	aim_delay = "Задержка (сек)",
	aim_wallcheck = "Проверка стен",
	aim_priority_label = "Приоритет",
	opt_center = "к центру", opt_hp = "меньше HP", opt_distance = "ближе всех",

	aim_sec_mode = "| Логика прицеливания",
	aim_mode_label = "Режим",
	opt_normal = "Обычный", opt_fixed = "Фиксированный",
	aim_mode_hint_normal = "Обычный: наводится на того, на кого ты смотришь. Отвести — просто отверни камеру.",
	aim_mode_hint_fixed = "Фиксированный: цель держится, пока жива. Снять можно только выключив AIM.",

	aim_sec_screenfov = "| FOV экрана",
	aim_camfov_toggle = "Свой FOV",
	aim_camfov_value = "FOV камеры",

	aim_sec_circle = "| Круг прицела",
	aim_circle_toggle = "Показать круг FOV",

	friends_sec_players = "| Игроки",
	friends_sec_list = "| Друзья",
	friends_clear_btn = "ОЧИСТИТЬ СПИСОК ДРУЗЕЙ",
	friends_auto_hint = "Твои друзья Roblox на сервере добавляются в список автоматически.",

	esp_sec = "| ESP",
	esp_toggle_main = "ESP включён",
	esp_toggle_name = "Ник",
	esp_toggle_box = "Hitbox",
	esp_toggle_chams = "Chams",
	esp_toggle_hp = "HP",
	esp_toggle_dist = "Дистанция",
	esp_toggle_tracer = "Tracer",
	esp_hint = "Друзья: хитбокс и chams зелёные, ник и дистанция обычного цвета. HP-бар всегда своей цветовой схемой.",

	visual_sec_colors = "| Цвета ESP",
	visual_color_box = "Цвет бокса",
	visual_color_name = "Цвет ника",
	visual_color_dist = "Цвет дистанции",
	visual_color_tracer = "Цвет Tracer",
	visual_color_chams = "Цвет Chams",
	visual_chams_transparency = "Прозрачность Chams",
	visual_box_thickness = "Толщина бокса",
	visual_line_thickness = "Толщина линий",
	visual_sec_env = "| Окружение",
	visual_no_fog = "Нет тумана",
	visual_no_dark = "Нет темноты",

	misc_warning = "ВНИМАНИЕ: эти функции могут привести к бану во многих плейсах. Используй на свой страх и риск!",
	misc_sec_char = "| Персонаж",
	misc_walkspeed = "WalkSpeed",
	misc_jumppower = "JumpPower",
	misc_infjump = "Infinite Jump",
	misc_antiafk = "Anti-AFK",
	misc_sec_screen = "| Экран",
	misc_fpsping = "FPS / Ping",
	misc_reset_btn = "СБРОС НАСТРОЕК ИГРОКА",

	save_sec = "| Файл настроек",
	save_btn = "СОХРАНИТЬ НАСТРОЙКИ",
	load_btn = "ЗАГРУЗИТЬ НАСТРОЙКИ",
	reset_btn = "СБРОСИТЬ НАСТРОЙКИ",
	save_hint_ok = "File API доступен.",
	save_hint_bad = "File API недоступен в этом экзекьюторе — сохранение/загрузка не сработают.",

	logs_sec = "| Журнал событий",
	logs_clear_btn = "ОЧИСТИТЬ ЛОГ",

	keybinds_sec = "| Горячие клавиши",
	key_toggle_aim = "Toggle AIM",
	key_toggle_esp = "Toggle ESP",
	key_friend_target = "Друг под прицелом",
	key_menu_toggle = "Открыть/закрыть меню",
	keybinds_reset_btn = "СБРОСИТЬ КЕЙБИНДЫ",

	social_sec = "| Создатель и соцсети",
	social_creator = "СОЗДАТЕЛЬ",
	social_tg = "TELEGRAM",
	social_tt = "TIKTOK",
	social_copy_all = "СКОПИРОВАТЬ ВСЁ",

	log_aim_on = "AIM PC: ВКЛ", log_aim_off = "AIM PC: ВЫКЛ",
	log_esp_on = "ESP: ВКЛ", log_esp_off = "ESP: ВЫКЛ",
}

L.US = {
	tab_profile = "Profile", tab_aim = "AIM", tab_friends = "Friends", tab_esp = "ESP", tab_visual = "Visual",
	tab_save = "Save", tab_logs = "Logs", tab_keybinds = "Keybinds", tab_social = "Social",
	tab_misc = "Misc Player",

	profile_session = "Session:", profile_nick = "Nick:", profile_display = "DisplayName:",
	profile_device = "Device:", profile_players = "Players:", profile_language = "Language",
	device_pc = "PC", device_mobile = "Mobile", device_console = "Console",

	aim_sec_toggles = "| AIM PC / MB",
	aim_toggle_pc = "AIM PC",
	aim_pc_mode_label = "RMB mode",
	opt_hold = "hold", opt_toggle = "toggle",
	aim_toggle_mb = "AIM MB",
	aim_hint_toggles = "PC: hold RMB (or press to toggle in \"toggle\" mode). Mobile: enable AIM MB — a round button appears on screen.",

	aim_sec_general = "| General settings",
	aim_part_label = "Body part",
	opt_head = "Head", opt_torso = "Torso", opt_nearest = "Nearest",
	aim_smooth = "Smoothness",
	aim_capture_radius = "Capture radius (px)",
	aim_distance = "Distance",
	aim_delay = "Delay (sec)",
	aim_wallcheck = "Wall Check",
	aim_priority_label = "Priority",
	opt_center = "closest to center", opt_hp = "lowest HP", opt_distance = "closest",

	aim_sec_mode = "| Aiming logic",
	aim_mode_label = "Mode",
	opt_normal = "Normal", opt_fixed = "Fixed",
	aim_mode_hint_normal = "Normal: aims at whoever you're looking at. To release, just turn the camera away.",
	aim_mode_hint_fixed = "Fixed: target is held while alive. Release only by turning AIM off.",

	aim_sec_screenfov = "| Screen FOV",
	aim_camfov_toggle = "Custom FOV",
	aim_camfov_value = "Camera FOV",

	aim_sec_circle = "| Aim circle",
	aim_circle_toggle = "Show FOV circle",

	friends_sec_players = "| Players",
	friends_sec_list = "| Friends",
	friends_clear_btn = "CLEAR FRIENDS LIST",
	friends_auto_hint = "Your Roblox friends on the server are added to the list automatically.",

	esp_sec = "| ESP",
	esp_toggle_main = "ESP enabled",
	esp_toggle_name = "Name",
	esp_toggle_box = "Hitbox",
	esp_toggle_chams = "Chams",
	esp_toggle_hp = "HP",
	esp_toggle_dist = "Distance",
	esp_toggle_tracer = "Tracer",
	esp_hint = "Friends: hitbox and chams are green, name and distance keep normal color. HP bar always uses its own color scheme.",

	visual_sec_colors = "| ESP colors",
	visual_color_box = "Box color",
	visual_color_name = "Name color",
	visual_color_dist = "Distance color",
	visual_color_tracer = "Tracer color",
	visual_color_chams = "Chams color",
	visual_chams_transparency = "Chams transparency",
	visual_box_thickness = "Box thickness",
	visual_line_thickness = "Line thickness",
	visual_sec_env = "| Environment",
	visual_no_fog = "No fog",
	visual_no_dark = "No darkness",

	misc_warning = "WARNING: these functions may get you banned in many places. Use at your own risk!",
	misc_sec_char = "| Character",
	misc_walkspeed = "WalkSpeed",
	misc_jumppower = "JumpPower",
	misc_infjump = "Infinite Jump",
	misc_antiafk = "Anti-AFK",
	misc_sec_screen = "| Screen",
	misc_fpsping = "FPS / Ping",
	misc_reset_btn = "RESET PLAYER SETTINGS",

	save_sec = "| Settings file",
	save_btn = "SAVE SETTINGS",
	load_btn = "LOAD SETTINGS",
	reset_btn = "RESET SETTINGS",
	save_hint_ok = "File API available.",
	save_hint_bad = "File API unavailable in this executor — save/load won't work.",

	logs_sec = "| Event log",
	logs_clear_btn = "CLEAR LOG",

	keybinds_sec = "| Hotkeys",
	key_toggle_aim = "Toggle AIM",
	key_toggle_esp = "Toggle ESP",
	key_friend_target = "Friend under crosshair",
	key_menu_toggle = "Open/close menu",
	keybinds_reset_btn = "RESET KEYBINDS",

	social_sec = "| Creator & socials",
	social_creator = "CREATOR",
	social_tg = "TELEGRAM",
	social_tt = "TIKTOK",
	social_copy_all = "COPY ALL",

	log_aim_on = "AIM PC: ON", log_aim_off = "AIM PC: OFF",
	log_esp_on = "ESP: ON", log_esp_off = "ESP: OFF",
}

local OPT_KEYS = {
	hold = "opt_hold", toggle = "opt_toggle",
	Head = "opt_head", Torso = "opt_torso", Nearest = "opt_nearest",
	center = "opt_center", hp = "opt_hp", distance = "opt_distance",
	normal = "opt_normal", fixed = "opt_fixed",
}

local function T(key)
	local set = L[CFG.Language] or L.RU
	return set[key] or key
end

-- =========================================================
-- ЛОГИ
-- =========================================================
local Logs = {}
do
	local list = {}
	local onAdd = nil

	function Logs.add(text)
		local line = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(text))
		table.insert(list, line)
		if #list > 200 then table.remove(list, 1) end
		if onAdd then pcall(onAdd) end
	end

	function Logs.clear()
		list = {}
		if onAdd then pcall(onAdd) end
	end

	function Logs.getText()
		return table.concat(list, "\n")
	end

	function Logs.setCallback(fn)
		onAdd = fn
	end
end

-- =========================================================
-- ДРУЗЬЯ
-- =========================================================
local Friends = {}
local onFriendsChange = nil

local function isFriend(player)
	return player and Friends[player.UserId] == true
end

local function addFriend(player, silent)
	if not player or Friends[player.UserId] then return end
	Friends[player.UserId] = true
	if not silent then Logs.add("+ " .. player.Name) end
	if onFriendsChange then pcall(onFriendsChange) end
end

local function removeFriend(player)
	if not player or not Friends[player.UserId] then return end
	Friends[player.UserId] = nil
	Logs.add("- " .. player.Name)
	if onFriendsChange then pcall(onFriendsChange) end
end

local function toggleFriend(player)
	if isFriend(player) then removeFriend(player) else addFriend(player) end
end

local function clearFriends()
	Friends = {}
	Logs.add("friends cleared")
	if onFriendsChange then pcall(onFriendsChange) end
end

-- автодобавление реальных друзей Roblox, которые есть на сервере
local function tryAutoAddFriend(plr)
	if plr == LocalPlayer then return end
	task.spawn(function()
		local ok, isFr = pcall(function() return LocalPlayer:IsFriendsWith(plr.UserId) end)
		if ok and isFr then addFriend(plr, true) end
	end)
end

for _, plr in ipairs(Players:GetPlayers()) do
	tryAutoAddFriend(plr)
end
bind(Players.PlayerAdded, tryAutoAddFriend)

-- =========================================================
-- СОХРАНЕНИЕ / ЗАГРУЗКА
-- =========================================================
local SAVE_FILE = "VNMAAIMBOT.json"
local uiRefreshers = {}
local function refreshAllUI()
	for _, fn in ipairs(uiRefreshers) do pcall(fn) end
end

local function saveSettings()
	if not hasFileAPI() then
		Logs.add("save unavailable: no File API")
		return false
	end
	local ok, encoded = pcall(function() return HttpService:JSONEncode(CFG) end)
	if not ok then Logs.add("encode error"); return false end
	local okWrite = pcall(writefile, SAVE_FILE, encoded)
	Logs.add(okWrite and ("saved: " .. SAVE_FILE) or "write error")
	return okWrite
end

local function loadSettings(silent)
	if not hasFileAPI() then return false end
	local okExists, exists = pcall(isfile, SAVE_FILE)
	if not okExists or not exists then return false end
	local okRead, data = pcall(readfile, SAVE_FILE)
	if not okRead then return false end
	local okDecode, decoded = pcall(function() return HttpService:JSONDecode(data) end)
	if not okDecode or type(decoded) ~= "table" then return false end
	for k, v in pairs(decoded) do
		if CFG[k] ~= nil then CFG[k] = v end
	end
	if not silent then Logs.add("loaded from " .. SAVE_FILE) end
	refreshAllUI()
	return true
end

local function resetSettings()
	if hasFileAPI() then pcall(delfile, SAVE_FILE) end
	for k, v in pairs(DEFAULT_CFG) do CFG[k] = v end
	refreshAllUI()
	Logs.add("settings reset")
end

-- =========================================================
-- ОСВЕЩЕНИЕ: ТУМАН + ТЕМНОТА
-- =========================================================
local Light = {}
do
	local weak = { __mode = "k" }
	local FOG_OFF = 100000
	local savedFog = nil
	local atmosSaved = setmetatable({}, weak)
	local darkSaved = {}

	local function enforceFog()
		if not CFG.NoFog then return end
		if Lighting.FogStart ~= FOG_OFF or Lighting.FogEnd ~= FOG_OFF then
			savedFog = savedFog or { start = Lighting.FogStart, fend = Lighting.FogEnd }
			Lighting.FogStart = FOG_OFF
			Lighting.FogEnd = FOG_OFF
		end
	end

	local function killAtmos(a)
		if not atmosSaved[a] then
			atmosSaved[a] = { Density = a.Density, Haze = a.Haze, Glare = a.Glare }
		end
		a.Density, a.Haze, a.Glare = 0, 0, 0
	end

	local function restoreFog()
		if savedFog then
			Lighting.FogStart = savedFog.start
			Lighting.FogEnd = savedFog.fend
			savedFog = nil
		end
		for a, o in pairs(atmosSaved) do
			atmosSaved[a] = nil
			if a.Parent then a.Density, a.Haze, a.Glare = o.Density, o.Haze, o.Glare end
		end
	end

	function Light.applyFog()
		if CFG.NoFog then
			enforceFog()
			for _, d in ipairs(Lighting:GetDescendants()) do
				if d:IsA("Atmosphere") then killAtmos(d) end
			end
		else
			restoreFog()
		end
	end

	local function liftColor(c)
		return Color3.new(math.max(c.R, 0.68), math.max(c.G, 0.68), math.max(c.B, 0.68))
	end

	local function enforceDark()
		if not CFG.NoDark then return end
		local rules = {
			{ "Brightness", math.max(Lighting.Brightness, 2) },
			{ "ExposureCompensation", math.max(Lighting.ExposureCompensation, 0.6) },
			{ "Ambient", liftColor(Lighting.Ambient) },
			{ "OutdoorAmbient", liftColor(Lighting.OutdoorAmbient) },
		}
		for _, r in ipairs(rules) do
			local prop, target = r[1], r[2]
			if darkSaved[prop] == nil then darkSaved[prop] = Lighting[prop] end
			Lighting[prop] = target
		end
	end

	local function restoreDark()
		for prop, value in pairs(darkSaved) do Lighting[prop] = value end
		darkSaved = {}
	end

	function Light.applyDark()
		if CFG.NoDark then enforceDark() else restoreDark() end
	end

	function Light.restoreAll()
		CFG.NoFog = false
		CFG.NoDark = false
		pcall(restoreFog)
		pcall(restoreDark)
	end

	bind(RunService.Heartbeat, function()
		enforceFog()
		enforceDark()
	end)
end

-- =========================================================
-- FOV ЭКРАНА (зум камеры, независим от аима)
-- =========================================================
local Fov = {}
do
	local NAME = "VNMA_CAMFOV"
	local FOV_PRIORITY = Enum.RenderPriority.Last.Value + 1000
	local state = { baseline = nil, cam = nil, camConn = nil }

	local function hookCamera(cam)
		if state.camConn then state.camConn:Disconnect(); state.camConn = nil end
		state.cam = cam
		state.baseline = nil
		state.camConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect(function()
			if stopped or not CFG.CamFOVEnabled or state.baseline == nil then return end
			if cam.FieldOfView ~= CFG.CamFOV then cam.FieldOfView = CFG.CamFOV end
		end)
	end

	local function step()
		if stopped then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		if state.cam ~= cam then hookCamera(cam) end
		if not CFG.CamFOVEnabled then state.baseline = nil; return end
		if not state.baseline then state.baseline = cam.FieldOfView end
		if cam.FieldOfView ~= CFG.CamFOV then cam.FieldOfView = CFG.CamFOV end
	end

	function Fov.start()
		pcall(function()
			RunService:UnbindFromRenderStep(NAME)
			RunService:BindToRenderStep(NAME, FOV_PRIORITY, step)
		end)
		bind(Workspace:GetPropertyChangedSignal("CurrentCamera"), step)
	end

	function Fov.restore()
		local cam = state.cam
		if cam and state.baseline then cam.FieldOfView = state.baseline end
		state.baseline = nil
	end

	function Fov.stop()
		pcall(function() RunService:UnbindFromRenderStep(NAME) end)
		Fov.restore()
		if state.camConn then state.camConn:Disconnect(); state.camConn = nil end
	end
end

-- =========================================================
-- ESP (только игроки)
-- =========================================================
local ESP = {}
local REF_HEIGHT = 180 -- эталонная высота бокса для масштаба 1.0

local function getScreenBox(char, camera)
	local head = char:FindFirstChild("Head")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not head or not root then return nil end

	local topPos = head.Position + Vector3.new(0, 0.5, 0)
	local bottomPos = root.Position - Vector3.new(0, 3, 0)

	local topScreen = camera:WorldToViewportPoint(topPos)
	local bottomScreen = camera:WorldToViewportPoint(bottomPos)
	if topScreen.Z <= 0 or bottomScreen.Z <= 0 then return nil end

	local height = math.abs(bottomScreen.Y - topScreen.Y)
	if height < 4 then return nil end
	local width = height * 0.55

	local pos = Vector2.new(topScreen.X - width / 2, topScreen.Y)
	local size = Vector2.new(width, height)
	return pos, size
end

local function createESPObjects()
	local o = {}
	o.box = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false, ZIndex = 2 })
	o.nameText = newDrawing("Text", { Size = 14, Center = true, Outline = true, Visible = false, ZIndex = 3 })
	o.distText = newDrawing("Text", { Size = 12, Center = true, Outline = true, Visible = false, ZIndex = 3 })
	o.tracer = newDrawing("Line", { Thickness = 1, Visible = false, ZIndex = 1 })
	o.hpBg = newDrawing("Square", { Filled = true, Color = Color3.fromRGB(20, 20, 20), Visible = false, ZIndex = 2 })
	o.hpFill = newDrawing("Square", { Filled = true, Visible = false, ZIndex = 3 })
	o.hpText = newDrawing("Text", { Size = 9, Center = true, Outline = true, Visible = false, ZIndex = 4 })
	o.highlight = nil
	return o
end

local function hideESPObjects(o)
	for _, key in ipairs({ "box", "nameText", "distText", "tracer", "hpBg", "hpFill", "hpText" }) do
		if o[key] then o[key].Visible = false end
	end
	if o.highlight then o.highlight.Enabled = false end
end

local function destroyESPObjects(o)
	for _, key in ipairs({ "box", "nameText", "distText", "tracer", "hpBg", "hpFill", "hpText" }) do
		destroyDrawing(o[key])
	end
	if o.highlight then pcall(function() o.highlight:Destroy() end) end
end

local function ensureHighlight(o, char)
	if not char then return end
	if o.highlight and o.highlight.Parent == char then return end
	if o.highlight then pcall(function() o.highlight:Destroy() end) end
	o.highlight = new("Highlight", {
		Name = "VNMA_CHAMS",
		FillTransparency = CFG.EspChamsTransparency,
		OutlineTransparency = 0.2,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Enabled = false,
	}, char)
end

local function hpColor(pct)
	if pct > 0.6 then return Color3.fromRGB(60, 235, 100) end
	if pct > 0.3 then return Color3.fromRGB(255, 220, 40) end
	return Color3.fromRGB(255, 60, 60)
end

local RAY_IGNORE = {} -- переиспользуемая таблица игнора (оптимизация без изменения логики)

local function updateESPFrame()
	if stopped then return end
	local camera = Workspace.CurrentCamera
	if not camera then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LocalPlayer then
			local o = ESP[plr]

			if CFG.EspEnabled then
				if not o then
					o = createESPObjects()
					ESP[plr] = o
				end

				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local alive = char and hum and hum.Health > 0

				if alive then
					local friend = isFriend(plr)
					local boxColor = friend and FRIEND_COLOR or PALETTE[CFG.ColorBoxIndex] or PALETTE[1]
					local nameColor = PALETTE[CFG.ColorNameIndex] or PALETTE[1]
					local distColor = PALETTE[CFG.ColorDistIndex] or PALETTE[1]
					local tracerColor = PALETTE[CFG.ColorTracerIndex] or PALETTE[1]
					local chamsColor = friend and FRIEND_COLOR or PALETTE[CFG.ColorChamsIndex] or PALETTE[1]

					ensureHighlight(o, char)
					if o.highlight then
						o.highlight.Enabled = CFG.EspChams
						o.highlight.FillColor = chamsColor
						o.highlight.OutlineColor = chamsColor
						o.highlight.FillTransparency = CFG.EspChamsTransparency
					end

					local pos, size = getScreenBox(char, camera)
					if pos then
						-- масштаб текста/толщины по дальности, чтобы толпа вдали не сливалась в одно пятно
						local scale = math.clamp(size.Y / REF_HEIGHT, 0.35, 1.3)

						if o.box then
							o.box.Visible = CFG.EspBox
							o.box.Position = pos
							o.box.Size = size
							o.box.Color = boxColor
							o.box.Thickness = math.max(1, math.floor(CFG.BoxThickness * scale + 0.5))
						end

						if o.nameText then
							o.nameText.Visible = CFG.EspName
							o.nameText.Text = plr.Name
							o.nameText.Size = math.max(8, math.floor(14 * scale))
							o.nameText.Position = Vector2.new(pos.X + size.X / 2, pos.Y - 16 * scale)
							o.nameText.Color = nameColor
						end

						if o.distText then
							local dist = math.floor((camera.CFrame.Position - getRoot(char).Position).Magnitude / 3.57)
							o.distText.Visible = CFG.EspDistance
							o.distText.Text = dist .. "m"
							o.distText.Size = math.max(7, math.floor(12 * scale))
							o.distText.Position = Vector2.new(pos.X + size.X / 2, pos.Y + size.Y + 4 * scale)
							o.distText.Color = distColor
						end

						if o.tracer then
							o.tracer.Visible = CFG.EspTracer
							o.tracer.From = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y)
							o.tracer.To = Vector2.new(pos.X + size.X / 2, pos.Y + size.Y)
							o.tracer.Color = tracerColor
							o.tracer.Thickness = math.max(1, math.floor(CFG.LineThickness * scale + 0.5))
						end

						local pct = hum.MaxHealth > 0 and (hum.Health / hum.MaxHealth) or 1
						local barX = pos.X - 7
						local barW = 3 -- уменьшенная ширина HP-полосы
						if o.hpBg then
							o.hpBg.Visible = CFG.EspHP
							o.hpBg.Position = Vector2.new(barX, pos.Y)
							o.hpBg.Size = Vector2.new(barW, size.Y)
						end
						if o.hpFill then
							local filledH = size.Y * pct
							o.hpFill.Visible = CFG.EspHP
							o.hpFill.Position = Vector2.new(barX, pos.Y + (size.Y - filledH))
							o.hpFill.Size = Vector2.new(barW, filledH)
							o.hpFill.Color = hpColor(pct)
						end
						if o.hpText then
							o.hpText.Visible = CFG.EspHP
							o.hpText.Text = tostring(math.floor(pct * 100)) .. "%"
							o.hpText.Size = math.max(7, math.floor(9 * scale)) -- поменьше надпись
							o.hpText.Position = Vector2.new(barX - 11, pos.Y + size.Y / 2)
							o.hpText.Color = hpColor(pct)
						end
					else
						hideESPObjects(o)
					end
				else
					hideESPObjects(o)
				end
			elseif o then
				hideESPObjects(o)
			end
		end
	end
end

local function clearAllESP()
	for _, o in pairs(ESP) do destroyESPObjects(o) end
	ESP = {}
end

Players.PlayerRemoving:Connect(function(plr)
	if ESP[plr] then
		destroyESPObjects(ESP[plr])
		ESP[plr] = nil
	end
	Friends[plr.UserId] = nil
end)

-- =========================================================
-- AIM (только игроки)
-- =========================================================
local Aim = {}
do
	local NAME = "VNMA_AIM"
	local rayParams = RaycastParams.new()
	pcall(function() rayParams.FilterType = Enum.RaycastFilterType.Exclude end)

	Aim.mobileOn = false
	local pcToggled = false
	local target, pendingTarget, pendingSince = nil, nil, 0

	function Aim.resetPC() pcToggled = false end

	bind(UserInputService.InputBegan, function(input, gpe)
		if gpe then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
		if not CFG.AimPC or CFG.AimPCMode ~= "toggle" then return end
		if UserInputService:GetFocusedTextBox() then return end
		pcToggled = not pcToggled
	end)

	local function pcActive()
		if not CFG.AimPC then return false end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then return false end
		if CFG.AimPCMode == "toggle" then return pcToggled end
		return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
	end

	local function isActive()
		return pcActive() or (CFG.AimMB and Aim.mobileOn)
	end
	Aim.isActive = isActive

	local function getAimPart(char)
		if CFG.AimPart == "Head" then
			return char:FindFirstChild("Head")
		elseif CFG.AimPart == "Torso" then
			return char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
		else
			return char:FindFirstChild("HumanoidRootPart")
		end
	end
	Aim.getAimPart = getAimPart

	local function isVisible(camera, part, char)
		RAY_IGNORE[1] = camera
		RAY_IGNORE[2] = char
		local myChar = LocalPlayer.Character
		RAY_IGNORE[3] = myChar or nil
		rayParams.FilterDescendantsInstances = RAY_IGNORE
		local origin = camera.CFrame.Position
		return Workspace:Raycast(origin, part.Position - origin, rayParams) == nil
	end

	local function computeCandidates(camera)
		local list = {}
		local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer and not isFriend(plr) then
				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local part = getAimPart(char)
					if part then
						local screenPos, onScreen = camera:WorldToViewportPoint(part.Position)
						if onScreen then
							local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
							local worldDist = (camera.CFrame.Position - part.Position).Magnitude
							if screenDist <= CFG.AimFOV and worldDist <= CFG.AimDistance then
								if not CFG.AimWallCheck or isVisible(camera, part, char) then
									list[#list + 1] = {
										player = plr, part = part,
										screenDist = screenDist, worldDist = worldDist, hp = hum.Health,
									}
								end
							end
						end
					end
				end
			end
		end
		return list
	end

	local function pickBest(list)
		if #list == 0 then return nil end
		local best = list[1]
		for i = 2, #list do
			local c = list[i]
			if CFG.AimPriority == "hp" then
				if c.hp < best.hp then best = c end
			elseif CFG.AimPriority == "distance" then
				if c.worldDist < best.worldDist then best = c end
			else
				if c.screenDist < best.screenDist then best = c end
			end
		end
		return best
	end

	function Aim.getTargetedPlayer()
		local camera = Workspace.CurrentCamera
		if not camera then return nil end
		local best = pickBest(computeCandidates(camera))
		return best and best.player or nil
	end

	local function isTargetValid(plr)
		if not plr then return false end
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return char and hum and hum.Health > 0
	end

	local function step(dt)
		if stopped or not isActive() then
			target, pendingTarget = nil, nil
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then return end

		if CFG.AimMode == "fixed" then
			-- фиксированный режим: держим цель, пока она жива, не отвлекаясь на других
			if not isTargetValid(target) then
				target = nil
			end
			if not target then
				local best = pickBest(computeCandidates(camera))
				target = best and best.player or nil
			end
		else
			-- обычный режим: пересчитываем лучшую цель каждый кадр
			local best = pickBest(computeCandidates(camera))
			local now = os.clock()
			if best then
				if target ~= best.player then
					if pendingTarget ~= best.player then
						pendingTarget = best.player
						pendingSince = now
					end
					if now - pendingSince >= CFG.AimDelay then
						target = best.player
					end
				end
			else
				pendingTarget = nil
				target = nil
			end
		end

		if target then
			local char = target.Character
			local part = char and getAimPart(char)
			if part and part.Parent then
				local cf = camera.CFrame
				local goal = CFrame.lookAt(cf.Position, part.Position)
				local alpha = math.clamp(CFG.AimSmooth * dt * 60, 0, 1)
				camera.CFrame = cf:Lerp(goal, alpha)
			else
				target = nil
			end
		end
	end

	function Aim.start()
		pcall(function() RunService:UnbindFromRenderStep(NAME) end)
		RunService:BindToRenderStep(NAME, Enum.RenderPriority.Camera.Value + 1, step)
	end

	function Aim.stop()
		CFG.AimPC = false
		CFG.AimMB = false
		Aim.mobileOn = false
		pcToggled = false
		target, pendingTarget = nil, nil
		pcall(function() RunService:UnbindFromRenderStep(NAME) end)
	end
end

bind(UserInputService.InputBegan, function(input, gpe)
	if gpe then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 and UserInputService:IsKeyDown(Enum.KeyCode.LeftAlt) then
		local targeted = Aim.getTargetedPlayer()
		if targeted then toggleFriend(targeted) end
	end
end)

-- =========================================================
-- MISC PLAYER
-- =========================================================
local function applyMisc()
	local char = LocalPlayer.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.WalkSpeed = CFG.WalkSpeed
		hum.JumpPower = CFG.JumpPower
	end
end

bind(LocalPlayer.CharacterAdded, function()
	task.wait(0.2)
	applyMisc()
end)

bind(RunService.Heartbeat, function()
	if not stopped then applyMisc() end
end)

bind(UserInputService.JumpRequest, function()
	if CFG.InfiniteJump then
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
	end
end)

bind(LocalPlayer.Idled, function()
	if CFG.AntiAFK and VirtualUser then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
		Logs.add("anti-afk")
	end
end)

local function resetMisc()
	CFG.WalkSpeed = DEFAULT_CFG.WalkSpeed
	CFG.JumpPower = DEFAULT_CFG.JumpPower
	CFG.InfiniteJump = false
	CFG.AntiAFK = false
	CFG.ShowFPSPing = false
	applyMisc()
	refreshAllUI()
	Logs.add("misc player reset")
end

-- =========================================================
-- ГЛАВНЫЙ ЦИКЛ
-- =========================================================
bind(RunService.RenderStepped, updateESPFrame)

do
	local okA, errA = pcall(Aim.start)
	if not okA then reportError("AIM", errA) end
	local okF, errF = pcall(Fov.start)
	if not okF then reportError("FOV", errF) end
end

print("[VNMA SCRIPT] core started")
Logs.add("script started")

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
		warn = Color3.fromRGB(255, 90, 90),
	}
	local TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local WHITE = Color3.new(1, 1, 1)

	local function corner(inst, r) return new("UICorner", { CornerRadius = UDim.new(0, r) }, inst) end
	local function stroke(inst, color, thickness, transparency)
		return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0 }, inst)
	end
	local function gradient(inst, c0, c1, rotation)
		return new("UIGradient", { Color = ColorSequence.new(c0, c1), Rotation = rotation or 0 }, inst)
	end
	local function escapeRich(s)
		s = tostring(s)
		s = s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
		return s
	end

	local localizedLabels = {}
	local function loc(obj, key)
		table.insert(localizedLabels, { obj = obj, key = key })
		obj.Text = T(key)
		return obj
	end

	local updateMobileButton -- forward declare (исправление бага AIM MB)
	local refreshProfile
	local refreshFriendsUI
	local refreshLocalization -- forward declare

	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then
		local okH, hui = pcall(function() return gethui and gethui() end)
		if okH and typeof(hui) == "Instance" then playerGui = hui end
	end
	if not playerGui then warn("[VNMA SCRIPT] PlayerGui not found") return end

	local old = playerGui:FindFirstChild("VNMA0_ESP_GUI")
	if old then old:Destroy() end

	screenGui = new("ScreenGui", {
		Name = "VNMA0_ESP_GUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, playerGui)

	-- увеличенный размер окна, чтобы контент не выходил за края
	local main = new("Frame", {
		Name = "Main", Size = UDim2.fromOffset(486, 340), Position = UDim2.new(0, 20, 0.5, -170),
		BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
	}, screenGui)
	corner(main, 14)
	gradient(stroke(main, WHITE, 1.5, 0.05), C.orangeLight, C.orangeDark, 45)

	local header = new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Active = true }, main)

	new("TextLabel", {
		Size = UDim2.new(1, -60, 0, 26), Position = UDim2.fromOffset(14, 5), BackgroundTransparency = 1,
		RichText = true, Text = '<font color="#FF8C00">VNMA</font> <font color="#FFBA52">SCRIPT</font>',
		TextColor3 = C.text, TextSize = 19, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left,
	}, header)

	local minimize = new("TextButton", {
		Name = "Minimize", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -38, 0, 8),
		BackgroundColor3 = C.panel2, BorderSizePixel = 0, Text = "-", TextColor3 = C.orange,
		TextSize = 16, Font = Enum.Font.GothamBold, AutoButtonColor = true,
	}, header)
	corner(minimize, 8)

	local headerLine = new("Frame", { Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, 44), BackgroundColor3 = WHITE, BorderSizePixel = 0 }, main)
	gradient(headerLine, C.orangeDark, C.orangeLight, 0)

	local sidebar = new("ScrollingFrame", {
		Size = UDim2.fromOffset(120, 276), Position = UDim2.fromOffset(8, 52), BackgroundColor3 = C.panel,
		BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = C.orange,
		CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, main)
	corner(sidebar, 10)
	stroke(sidebar, C.line, 1, 0)
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6) }, sidebar)
	new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sidebar)

	local pagesHolder = new("Frame", { Size = UDim2.fromOffset(342, 276), Position = UDim2.fromOffset(136, 52), BackgroundTransparency = 1 }, main)

	local pages, tabs = {}, {}
	local function styleTab(tab, active)
		tab.button.BackgroundColor3 = active and WHITE or C.panel2
		tab.grad.Enabled = active
		tab.button.TextColor3 = active and C.dark or C.muted
	end
	local function selectTab(id)
		for pid, page in pairs(pages) do page.Visible = (pid == id) end
		for tid, tab in pairs(tabs) do styleTab(tab, tid == id) end
	end
	local function createTab(order, id, key)
		local button = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = C.panel2, BorderSizePixel = 0, Text = T(key),
			TextColor3 = C.muted, TextSize = 11, Font = Enum.Font.GothamBold, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, AutoButtonColor = false, LayoutOrder = order,
		}, sidebar)
		loc(button, key)
		corner(button, 7)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 4) }, button)
		local grad = gradient(button, C.orangeLight, C.orangeDark, 0)
		grad.Enabled = false
		tabs[id] = { button = button, grad = grad }
		button.Activated:Connect(function() selectTab(id) end)
	end

	-- порядок вкладок: MISC PLAYER перенесён в конец
	createTab(1, "profile", "tab_profile")
	createTab(2, "aim", "tab_aim")
	createTab(3, "friends", "tab_friends")
	createTab(4, "esp", "tab_esp")
	createTab(5, "visual", "tab_visual")
	createTab(6, "save", "tab_save")
	createTab(7, "logs", "tab_logs")
	createTab(8, "keybinds", "tab_keybinds")
	createTab(9, "social", "tab_social")
	createTab(10, "misc", "tab_misc")

	local function createToggle(parent, order, labelKey, key, onChange, height)
		local row = new("TextButton", { Size = UDim2.new(1, 0, 0, height or 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = order }, parent)
		corner(row, 9)
		local st = stroke(row, C.line, 1, 0)
		local label = new("TextLabel", { Size = UDim2.new(1, -66, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T(labelKey), TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.muted }, row)
		loc(label, labelKey)
		local track = new("Frame", { Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -48, 0.5, -10), BackgroundColor3 = C.off, BorderSizePixel = 0 }, row)
		corner(track, 10)
		local grad = gradient(track, C.orangeLight, C.orangeDark, 0)
		grad.Enabled = false
		local knob = new("Frame", { Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = C.muted, BorderSizePixel = 0 }, track)
		corner(knob, 7)

		local function refresh()
			local on = CFG[key]
			grad.Enabled = on
			TweenService:Create(track, TWEEN, { BackgroundColor3 = on and WHITE or C.off }):Play()
			TweenService:Create(knob, TWEEN, { Position = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3), BackgroundColor3 = on and C.dark or C.muted }):Play()
			TweenService:Create(st, TWEEN, { Color = on and C.orange or C.line }):Play()
			TweenService:Create(label, TWEEN, { TextColor3 = on and C.text or C.muted }):Play()
		end

		row.Activated:Connect(function()
			CFG[key] = not CFG[key]
			refresh()
			if onChange then onChange() end
		end)
		refresh()
		table.insert(uiRefreshers, refresh)
		return row, refresh
	end

	local function createStepper(parent, order, labelKey, key, minV, maxV, stepV, fmt, onChange)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, LayoutOrder = order }, parent)
		corner(row, 9)
		stroke(row, C.line, 1, 0)
		local label = new("TextLabel", { Size = UDim2.new(1, -128, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T(labelKey), TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		loc(label, labelKey)
		local valueLabel = new("TextLabel", { Size = UDim2.fromOffset(44, 34), Position = UDim2.new(1, -104, 0, 0), BackgroundTransparency = 1, TextSize = 11, Font = Enum.Font.GothamBold, TextColor3 = C.orange }, row)

		local function refresh() valueLabel.Text = string.format(fmt, CFG[key]) end
		refresh()
		table.insert(uiRefreshers, refresh)

		local function makeBtn(txt, x, delta)
			local b = new("TextButton", { Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, x, 0.5, -11), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = txt, TextColor3 = C.text, TextSize = 15, Font = Enum.Font.GothamBold, AutoButtonColor = true }, row)
			corner(b, 6)
			b.Activated:Connect(function()
				local v = CFG[key] + delta
				v = math.floor(v / stepV + 0.5) * stepV
				CFG[key] = math.clamp(v, minV, maxV)
				refresh()
				if onChange then onChange() end
			end)
		end
		makeBtn("-", -56, -stepV)
		makeBtn("+", -30, stepV)
		return row
	end

	local function createChoice(parent, order, labelKey, key, options)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, LayoutOrder = order }, parent)
		corner(row, 9)
		stroke(row, C.line, 1, 0)
		local label = new("TextLabel", { Size = UDim2.new(1, -116, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T(labelKey), TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		loc(label, labelKey)
		local valBtn = new("TextButton", { Size = UDim2.fromOffset(96, 24), Position = UDim2.new(1, -104, 0.5, -12), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = T(OPT_KEYS[CFG[key]] or CFG[key]), TextColor3 = C.orange, TextSize = 11, Font = Enum.Font.GothamBold, AutoButtonColor = true, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		corner(valBtn, 6)
		local function refresh() valBtn.Text = T(OPT_KEYS[CFG[key]] or CFG[key]) end
		table.insert(uiRefreshers, refresh)
		valBtn.Activated:Connect(function()
			local idx = table.find(options, CFG[key]) or 1
			idx = idx % #options + 1
			CFG[key] = options[idx]
			refresh()
		end)
		return row
	end

	local function createColorPicker(parent, order, labelKey, key)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, LayoutOrder = order }, parent)
		corner(row, 9)
		stroke(row, C.line, 1, 0)
		local label = new("TextLabel", { Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T(labelKey), TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.text }, row)
		loc(label, labelKey)
		local swatch = new("TextButton", { Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -40, 0.5, -11), BackgroundColor3 = PALETTE[CFG[key]] or PALETTE[1], BorderSizePixel = 0, Text = "", AutoButtonColor = false }, row)
		corner(swatch, 6)
		stroke(swatch, WHITE, 1, 0.3)
		local function refresh() swatch.BackgroundColor3 = PALETTE[CFG[key]] or PALETTE[1] end
		table.insert(uiRefreshers, refresh)
		swatch.Activated:Connect(function()
			CFG[key] = (CFG[key] % #PALETTE) + 1
			refresh()
		end)
		return row
	end

	local function sectionTitle(parent, order, key)
		local lbl = new("TextLabel", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Text = T(key), TextColor3 = C.orange, TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order }, parent)
		loc(lbl, key)
		return lbl
	end

	local function hint(parent, order, key, height, colorOverride)
		local lbl = new("TextLabel", { Size = UDim2.new(1, 0, 0, height or 24), BackgroundTransparency = 1, Text = T(key), TextColor3 = colorOverride or C.muted, TextSize = 10, Font = Enum.Font.Gotham, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = order }, parent)
		loc(lbl, key)
		return lbl
	end

	local function bigButton(parent, order, key, onClick)
		local btn = new("TextButton", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel2, BorderSizePixel = 0, Text = T(key), TextColor3 = C.orange, TextSize = 12, Font = Enum.Font.GothamBold, LayoutOrder = order, AutoButtonColor = true, TextWrapped = true }, parent)
		loc(btn, key)
		corner(btn, 9)
		stroke(btn, C.line, 1, 0)
		btn.Activated:Connect(onClick)
		return btn
	end

	local function makeScrollPage(name, order)
		local page = new("ScrollingFrame", {
			Name = name, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0,
			ScrollBarThickness = 3, ScrollBarImageColor3 = C.orange, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
		}, pagesHolder)
		new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6) }, page)
		pages[order] = page
		return page
	end

	-- ===================== ПРОФИЛЬ =====================
	local profile = new("Frame", { Name = "Profile", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, pagesHolder)
	pages.profile = profile

	local userCard = new("Frame", { Size = UDim2.new(1, 0, 0, 88), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, profile)
	corner(userCard, 10)
	stroke(userCard, C.line, 1, 0)
	local avatar = new("ImageLabel", { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(12, 13), BackgroundColor3 = C.panel2, BorderSizePixel = 0, Image = "" }, userCard)
	corner(avatar, 31)
	gradient(stroke(avatar, WHITE, 2, 0), C.orangeLight, C.orangeDark, 45)

	local userText = new("TextLabel", { Size = UDim2.new(1, -92, 1, -10), Position = UDim2.fromOffset(84, 8), BackgroundTransparency = 1, RichText = true, TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true, Text = "" }, userCard)

	refreshProfile = function()
		userText.Text = string.format(
			'<font color="#FF8C00">%s</font> %s\n<font color="#FF8C00">%s</font> %s\n<font color="#FF8C00">%s</font> %s\n<font color="#FF8C00">%s</font> %d/%d',
			T("profile_nick"), escapeRich(LocalPlayer.Name),
			T("profile_display"), escapeRich(LocalPlayer.DisplayName),
			T("profile_device"), T(getDeviceTypeKey()),
			T("profile_players"), #Players:GetPlayers(), Players.MaxPlayers
		)
	end
	refreshProfile()
	bind(Players.PlayerAdded, refreshProfile)
	bind(Players.PlayerRemoving, function() task.defer(refreshProfile) end)

	task.spawn(function()
		local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if ok and not stopped then avatar.Image = img end
	end)

	local sessionBlock = new("Frame", { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 96), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, profile)
	corner(sessionBlock, 10)
	stroke(sessionBlock, C.line, 1, 0)
	local sessionLabel = new("TextLabel", { Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, RichText = true, TextColor3 = C.text, TextSize = 13, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left, Text = "" }, sessionBlock)

	task.spawn(function()
		while not stopped do
			sessionLabel.Text = '<font color="#FF8C00">' .. T("profile_session") .. '</font> ' .. formatTime(os.clock() - SESSION_START)
			task.wait(1)
		end
	end)

	-- переключатель языка
	local langBlock = new("Frame", { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 148), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, profile)
	corner(langBlock, 10)
	stroke(langBlock, C.line, 1, 0)
	local langLabel = new("TextLabel", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T("profile_language"), TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, langBlock)
	loc(langLabel, "profile_language")

	local ruBtn = new("TextButton", { Size = UDim2.fromOffset(50, 26), Position = UDim2.new(1, -112, 0.5, -13), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = "RU", TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamBold }, langBlock)
	corner(ruBtn, 7)
	local usBtn = new("TextButton", { Size = UDim2.fromOffset(50, 26), Position = UDim2.new(1, -56, 0.5, -13), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = "US", TextColor3 = C.text, TextSize = 12, Font = Enum.Font.GothamBold }, langBlock)
	corner(usBtn, 7)

	local function refreshLangButtons()
		ruBtn.BackgroundColor3 = (CFG.Language == "RU") and C.orange or C.off
		usBtn.BackgroundColor3 = (CFG.Language == "US") and C.orange or C.off
	end
	refreshLangButtons()
	table.insert(uiRefreshers, refreshLangButtons)

	ruBtn.Activated:Connect(function()
		CFG.Language = "RU"
		refreshLangButtons()
		if refreshLocalization then refreshLocalization() end
	end)
	usBtn.Activated:Connect(function()
		CFG.Language = "US"
		refreshLangButtons()
		if refreshLocalization then refreshLocalization() end
	end)

	-- ===================== AIM =====================
	local aimPage = makeScrollPage("Aim", "aim")
	sectionTitle(aimPage, 1, "aim_sec_toggles")
	createToggle(aimPage, 2, "aim_toggle_pc", "AimPC", Aim.resetPC)
	createChoice(aimPage, 3, "aim_pc_mode_label", "AimPCMode", { "hold", "toggle" })
	createToggle(aimPage, 4, "aim_toggle_mb", "AimMB", function()
		if updateMobileButton then updateMobileButton() end
	end)
	hint(aimPage, 5, "aim_hint_toggles", 30)

	sectionTitle(aimPage, 6, "aim_sec_general")
	createChoice(aimPage, 7, "aim_part_label", "AimPart", { "Head", "Torso", "Nearest" })
	createStepper(aimPage, 8, "aim_smooth", "AimSmooth", 0.05, 1, 0.05, "%.2f")
	createStepper(aimPage, 9, "aim_capture_radius", "AimFOV", 20, 400, 10, "%d")
	createStepper(aimPage, 10, "aim_distance", "AimDistance", 50, 3000, 50, "%d")
	createStepper(aimPage, 11, "aim_delay", "AimDelay", 0, 2, 0.05, "%.2f")
	createToggle(aimPage, 12, "aim_wallcheck", "AimWallCheck")
	createChoice(aimPage, 13, "aim_priority_label", "AimPriority", { "center", "hp", "distance" })

	sectionTitle(aimPage, 14, "aim_sec_mode")
	createChoice(aimPage, 15, "aim_mode_label", "AimMode", { "normal", "fixed" })
	hint(aimPage, 16, "aim_mode_hint_normal", 26)
	hint(aimPage, 17, "aim_mode_hint_fixed", 26)

	sectionTitle(aimPage, 18, "aim_sec_screenfov")
	createToggle(aimPage, 19, "aim_camfov_toggle", "CamFOVEnabled", function()
		if not CFG.CamFOVEnabled then Fov.restore() end
	end)
	createStepper(aimPage, 20, "aim_camfov_value", "CamFOV", 40, 120, 5, "%d")

	sectionTitle(aimPage, 21, "aim_sec_circle")
	createToggle(aimPage, 22, "aim_circle_toggle", "AimShowCircle")

	-- ===================== ДРУЗЬЯ =====================
	local friendsPage = makeScrollPage("Friends", "friends")
	sectionTitle(friendsPage, 1, "friends_sec_players")
	hint(friendsPage, 2, "friends_auto_hint", 24)

	local playersHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, friendsPage)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, playersHolder)

	sectionTitle(friendsPage, 4, "friends_sec_list")
	local friendsHolder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5 }, friendsPage)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, friendsHolder)

	bigButton(friendsPage, 6, "friends_clear_btn", function() clearFriends() end)

	local function makePlayerRow(parent, plr, btnText, onClick, color)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = C.panel, BorderSizePixel = 0 }, parent)
		corner(row, 8)
		new("TextLabel", { Size = UDim2.new(1, -50, 1, 0), Position = UDim2.fromOffset(10, 0), BackgroundTransparency = 1, Text = plr.Name, TextColor3 = color, TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		local btn = new("TextButton", { Size = UDim2.fromOffset(30, 22), Position = UDim2.new(1, -38, 0.5, -11), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = btnText, TextColor3 = C.text, TextSize = 14, Font = Enum.Font.GothamBold }, row)
		corner(btn, 6)
		btn.Activated:Connect(onClick)
		return row
	end

	refreshFriendsUI = function()
		for _, c in ipairs(playersHolder:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for _, c in ipairs(friendsHolder:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LocalPlayer then
				if isFriend(plr) then
					makePlayerRow(friendsHolder, plr, "-", function() removeFriend(plr) end, FRIEND_COLOR)
				else
					makePlayerRow(playersHolder, plr, "+", function() addFriend(plr) end, WHITE)
				end
			end
		end
	end
	onFriendsChange = refreshFriendsUI
	refreshFriendsUI()
	bind(Players.PlayerAdded, refreshFriendsUI)
	bind(Players.PlayerRemoving, function() task.defer(refreshFriendsUI) end)

	-- ===================== ESP =====================
	local espPage = makeScrollPage("ESP", "esp")
	sectionTitle(espPage, 1, "esp_sec")
	createToggle(espPage, 2, "esp_toggle_main", "EspEnabled")
	createToggle(espPage, 3, "esp_toggle_name", "EspName")
	createToggle(espPage, 4, "esp_toggle_box", "EspBox")
	createToggle(espPage, 5, "esp_toggle_chams", "EspChams")
	createToggle(espPage, 6, "esp_toggle_hp", "EspHP")
	createToggle(espPage, 7, "esp_toggle_dist", "EspDistance")
	createToggle(espPage, 8, "esp_toggle_tracer", "EspTracer")
	hint(espPage, 9, "esp_hint", 40)

	-- ===================== ВИЗУАЛ =====================
	local visualPage = makeScrollPage("Visual", "visual")
	sectionTitle(visualPage, 1, "visual_sec_colors")
	createColorPicker(visualPage, 2, "visual_color_box", "ColorBoxIndex")
	createColorPicker(visualPage, 3, "visual_color_name", "ColorNameIndex")
	createColorPicker(visualPage, 4, "visual_color_dist", "ColorDistIndex")
	createColorPicker(visualPage, 5, "visual_color_tracer", "ColorTracerIndex")
	createColorPicker(visualPage, 6, "visual_color_chams", "ColorChamsIndex")
	createStepper(visualPage, 7, "visual_chams_transparency", "EspChamsTransparency", 0, 0.95, 0.05, "%.2f")
	createStepper(visualPage, 8, "visual_box_thickness", "BoxThickness", 1, 4, 1, "%d")
	createStepper(visualPage, 9, "visual_line_thickness", "LineThickness", 1, 4, 1, "%d")

	sectionTitle(visualPage, 10, "visual_sec_env")
	createToggle(visualPage, 11, "visual_no_fog", "NoFog", Light.applyFog)
	createToggle(visualPage, 12, "visual_no_dark", "NoDark", Light.applyDark)

	-- ===================== СОХРАНЕНИЕ =====================
	local savePage = makeScrollPage("Save", "save")
	sectionTitle(savePage, 1, "save_sec")
	bigButton(savePage, 2, "save_btn", saveSettings)
	bigButton(savePage, 3, "load_btn", function() loadSettings(false) end)
	bigButton(savePage, 4, "reset_btn", resetSettings)
	hint(savePage, 5, hasFileAPI() and "save_hint_ok" or "save_hint_bad", 30)

	-- ===================== ЛОГИ =====================
	local logsPage = makeScrollPage("Logs", "logs")
	sectionTitle(logsPage, 1, "logs_sec")
	bigButton(logsPage, 2, "logs_clear_btn", function() Logs.clear() end)
	local logsText = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		Text = "", TextColor3 = C.muted, TextSize = 11, Font = Enum.Font.Code, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 3,
	}, logsPage)
	Logs.setCallback(function()
		logsText.Text = Logs.getText()
		task.defer(function() logsPage.CanvasPosition = Vector2.new(0, math.huge) end)
	end)
	logsText.Text = Logs.getText()

	-- ===================== КЕЙБИНДЫ =====================
	local keybindsPage = makeScrollPage("Keybinds", "keybinds")
	sectionTitle(keybindsPage, 1, "keybinds_sec")

	local capturingKey = nil

	local function bindRow(order, labelKey, cfgKey)
		local row = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = C.panel, BorderSizePixel = 0, LayoutOrder = order }, keybindsPage)
		corner(row, 9)
		stroke(row, C.line, 1, 0)
		local label = new("TextLabel", { Size = UDim2.new(1, -108, 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = T(labelKey), TextSize = 12, Font = Enum.Font.GothamSemibold, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd }, row)
		loc(label, labelKey)
		local btn = new("TextButton", { Size = UDim2.fromOffset(88, 24), Position = UDim2.new(1, -98, 0.5, -12), BackgroundColor3 = C.off, BorderSizePixel = 0, Text = CFG[cfgKey], TextColor3 = C.orange, TextSize = 11, Font = Enum.Font.GothamBold }, row)
		corner(btn, 6)
		local function refresh() btn.Text = capturingKey == cfgKey and "..." or CFG[cfgKey] end
		table.insert(uiRefreshers, refresh)
		btn.Activated:Connect(function()
			capturingKey = cfgKey
			refresh()
		end)
		return refresh
	end

	bindRow(2, "key_toggle_aim", "KeyAim")
	bindRow(3, "key_toggle_esp", "KeyESP")
	bindRow(4, "key_friend_target", "KeyFriends")
	bindRow(5, "key_menu_toggle", "KeyMenu")

	bigButton(keybindsPage, 6, "keybinds_reset_btn", function()
		CFG.KeyAim = DEFAULT_CFG.KeyAim
		CFG.KeyESP = DEFAULT_CFG.KeyESP
		CFG.KeyFriends = DEFAULT_CFG.KeyFriends
		CFG.KeyMenu = DEFAULT_CFG.KeyMenu
		refreshAllUI()
		Logs.add("keybinds reset")
	end)

	local mini
	local function doMinimize()
		if capturingKey then
			capturingKey = nil
			refreshAllUI()
		end
		mini.Position = main.Position
		main.Visible = false
		mini.Visible = true
	end
	local function doRestore()
		main.Position = mini.Position
		mini.Visible = false
		main.Visible = true
	end

	bind(UserInputService.InputBegan, function(input, gpe)
		if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local kc = input.KeyCode.Name

		if capturingKey then
			CFG[capturingKey] = kc
			capturingKey = nil
			refreshAllUI()
			return
		end

		if gpe then return end

		if kc == CFG.KeyMenu then
			if main.Visible then doMinimize() else doRestore() end
		elseif kc == CFG.KeyAim then
			CFG.AimPC = not CFG.AimPC
			Logs.add(CFG.AimPC and T("log_aim_on") or T("log_aim_off"))
			refreshAllUI()
		elseif kc == CFG.KeyESP then
			CFG.EspEnabled = not CFG.EspEnabled
			Logs.add(CFG.EspEnabled and T("log_esp_on") or T("log_esp_off"))
			refreshAllUI()
		elseif kc == CFG.KeyFriends then
			local targeted = Aim.getTargetedPlayer()
			if targeted then toggleFriend(targeted) end
		end
	end)

	-- ===================== СОЦ СЕТИ =====================
	local socialPage = makeScrollPage("Social", "social")
	sectionTitle(socialPage, 1, "social_sec")

	local clip = (typeof(setclipboard) == "function" and setclipboard) or (typeof(toclipboard) == "function" and toclipboard) or nil

	local function socialRow(order, titleKey, value)
		local row = new("TextButton", { Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "", AutoButtonColor = false, LayoutOrder = order }, socialPage)
		corner(row, 9)
		stroke(row, C.line, 1, 0)
		local title = new("TextLabel", { Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(12, 6), BackgroundTransparency = 1, Text = T(titleKey), TextColor3 = C.orange, TextSize = 11, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, row)
		loc(title, titleKey)
		local valueLabel = new("TextLabel", { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.fromOffset(12, 22), BackgroundTransparency = 1, Text = value, TextColor3 = C.text, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left }, row)
		row.Activated:Connect(function()
			local ok = clip and pcall(clip, value)
			valueLabel.Text = ok and "..." or value
			task.delay(1.2, function() if valueLabel.Parent then valueLabel.Text = value end end)
		end)
		return row
	end

	socialRow(2, "social_creator", "VNMA")
	socialRow(3, "social_tg", "@VNMA_OFFICIAL")
	socialRow(4, "social_tt", "@vnma_official")

	bigButton(socialPage, 5, "social_copy_all", function()
		local text = "VNMA | @VNMA_OFFICIAL | @vnma_official"
		local ok = clip and pcall(clip, text)
		Logs.add(ok and "socials copied" or "clipboard unavailable")
	end)

	-- ===================== MISC PLAYER (перенесено в конец) =====================
	local miscPage = makeScrollPage("Misc", "misc")
	hint(miscPage, 1, "misc_warning", 40, C.warn)

	sectionTitle(miscPage, 2, "misc_sec_char")
	createStepper(miscPage, 3, "misc_walkspeed", "WalkSpeed", 16, 200, 2, "%d", applyMisc)
	createStepper(miscPage, 4, "misc_jumppower", "JumpPower", 50, 500, 10, "%d", applyMisc)
	createToggle(miscPage, 5, "misc_infjump", "InfiniteJump")
	createToggle(miscPage, 6, "misc_antiafk", "AntiAFK")

	sectionTitle(miscPage, 7, "misc_sec_screen")
	createToggle(miscPage, 8, "misc_fpsping", "ShowFPSPing")

	bigButton(miscPage, 9, "misc_reset_btn", resetMisc)

	local fpsLabel = new("TextLabel", {
		Name = "FPSPing", Size = UDim2.fromOffset(120, 40), Position = UDim2.fromOffset(8, 8),
		BackgroundTransparency = 0.4, BackgroundColor3 = C.dark, TextColor3 = C.orange,
		TextSize = 13, Font = Enum.Font.GothamBold, Visible = false, ZIndex = 20,
	}, screenGui)
	corner(fpsLabel, 8)
	do
		local frames, lastCheck = 0, os.clock()
		bind(RunService.RenderStepped, function()
			frames = frames + 1
			fpsLabel.Visible = CFG.ShowFPSPing
			local now = os.clock()
			if now - lastCheck >= 1 then
				local fps = frames
				frames = 0
				lastCheck = now
				local ping = "N/A"
				local okPing, pingVal = pcall(function() return LocalPlayer:GetNetworkPing() end)
				if okPing then ping = tostring(math.floor(pingVal * 1000)) .. "ms" end
				fpsLabel.Text = string.format("FPS: %d\nPing: %s", fps, ping)
			end
		end)
	end

	-- ===================== МОБИЛЬНАЯ AIM-КНОПКА =====================
	local AIM_GREEN = Color3.fromRGB(46, 204, 90)
	local AIM_RED = Color3.fromRGB(220, 55, 55)

	local mobileBtn = new("TextButton", {
		Name = "AimMobileButton", Size = UDim2.fromOffset(64, 64), Position = UDim2.new(1, -90, 1, -180),
		BackgroundColor3 = AIM_RED, BorderSizePixel = 0, Text = "AIM", TextColor3 = WHITE, TextSize = 16,
		Font = Enum.Font.GothamBold, AutoButtonColor = false, Visible = false, ZIndex = 10,
	}, screenGui)
	corner(mobileBtn, 32)
	stroke(mobileBtn, WHITE, 2, 0.1)

	local function paintMobileBtn() mobileBtn.BackgroundColor3 = Aim.mobileOn and AIM_GREEN or AIM_RED end

	-- исправление бага: теперь эта функция реально вызывается при переключении AIM MB
	updateMobileButton = function()
		if not CFG.AimMB then Aim.mobileOn = false end
		mobileBtn.Visible = CFG.AimMB
		paintMobileBtn()
	end
	table.insert(uiRefreshers, updateMobileButton)

	mobileBtn.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local startPos = input.Position
		local startFramePos = mobileBtn.Position
		local dragged = false
		local moveConn, endConn
		moveConn = UserInputService.InputChanged:Connect(function(i)
			if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
				local delta = i.Position - startPos
				if not dragged and delta.Magnitude > 8 then dragged = true end
				if dragged then
					mobileBtn.Position = UDim2.new(startFramePos.X.Scale, startFramePos.X.Offset + delta.X, startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y)
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

	-- ===================== КРУГ FOV (только по своей кнопке) =====================
	local fovCircle = newDrawing("Circle", { Thickness = 1, Filled = false, Color = WHITE, Transparency = 0.5, Visible = false, NumSides = 48 })
	bind(RunService.RenderStepped, function()
		if not fovCircle then return end
		local camera = Workspace.CurrentCamera
		if not camera or stopped then fovCircle.Visible = false; return end
		fovCircle.Visible = CFG.AimShowCircle -- теперь зависит только от этого тумблера
		if fovCircle.Visible then
			fovCircle.Position = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
			fovCircle.Radius = CFG.AimFOV
		end
	end)

	-- ===================== ПЕРЕТАСКИВАНИЕ / СВОРАЧИВАНИЕ =====================
	local function makeDraggable(handle, frame)
		handle.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local startPos = input.Position
			local startFramePos = frame.Position
			local moveConn, endConn
			moveConn = UserInputService.InputChanged:Connect(function(i)
				if i == input or i.UserInputType == Enum.UserInputType.MouseMovement then
					local delta = i.Position - startPos
					frame.Position = UDim2.new(startFramePos.X.Scale, startFramePos.X.Offset + delta.X, startFramePos.Y.Scale, startFramePos.Y.Offset + delta.Y)
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

	mini = new("TextButton", {
		Name = "Mini", Size = UDim2.fromOffset(50, 50), Position = main.Position, BackgroundColor3 = WHITE,
		BorderSizePixel = 0, Text = "V", TextColor3 = C.dark, TextSize = 22, Font = Enum.Font.GothamBold, Visible = false,
	}, screenGui)
	corner(mini, 14)
	gradient(mini, C.orangeLight, C.orangeDark, 45)
	makeDraggable(mini, mini)

	minimize.Activated:Connect(doMinimize)
	mini.Activated:Connect(doRestore)

	refreshLocalization = function()
		for _, item in ipairs(localizedLabels) do
			if item.obj and item.obj.Parent then
				item.obj.Text = T(item.key)
			end
		end
		refreshProfile()
		refreshFriendsUI()
		refreshAllUI()
	end

	selectTab("profile")

	if loadSettings(true) then
		Logs.add("autoload: " .. SAVE_FILE)
	end
	updateMobileButton()
	refreshLocalization()
end)

if okGui then
	print("[VNMA SCRIPT] GUI created")
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
		clearAllESP()

		for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end

		if screenGui then screenGui:Destroy() end
	end
end

print("[VNMA SCRIPT] ready")

end -- main

local okMain, errMain = xpcall(main, function(e) return debug.traceback(tostring(e), 2) end)
if not okMain then reportError("запуск", errMain) end
