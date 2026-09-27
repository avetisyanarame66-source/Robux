--!nocheck
--[[===========================================================================
	MEGA BLOX ADVENTURE -- Main Server Script
	---------------------------------------------------------------------------
	WHAT:    A complete Roblox game in ONE Script.
	WHERE:   Put this Script in ServerScriptService in Roblox Studio.
	         (Copy this file's contents into a Script named "MainServer".)
	VERSION: 1.0.0

	FEATURES:
	  * Data saving (DataStores with autosave + session safety)
	  * leaderstats: Coins, Gems, Wins, Rebirths, Level
	  * XP / Levels, Rebirth system with multipliers
	  * In-game Shop (coins -> tools / coils / sword / potion)
	  * Auto-built obby (25 stages), checkpoints, lava, moving platforms,
	    fading platforms, Win pad with fireworks
	  * Coin orbs that respawn, training dummies, enemy chasers
	  * Quests, daily login streak rewards
	  * VIP lounge + Rebirth pad
	  * Admin chat commands, basic anti-exploit, double-coin events
	  * Day/night cycle + broadcast announcements

	HOW TO INSTALL:
	  1. Open Roblox Studio, open your place.
	  2. In the Explorer, select ServerScriptService.
	  3. Insert a "Script" (NOT a LocalScript, NOT a ModuleScript).
	  4. Name it "MainServer".
	  5. Select all text in that Script, delete it, paste this whole file.
	  6. Press Play. The script builds the whole game world by itself.
	  7. (Optional) Turn on "Enable Studio Access to API Services" in
	     Game Settings > Security so data saves while testing in Studio.

	TWEAKS: Everything tunable lives in CONFIG below. Start there.
=============================================================================]]

--------------------------------------------------------------------------------
-- 1. CONFIG -- tune your whole game from this one table
--------------------------------------------------------------------------------
local CONFIG = {
	GameName = "Mega Blox Adventure",
	DataStoreName = "MegaBloxAdventure_V1",
	SaveIntervalSeconds = 120,
	DataLoadRetries = 5,

	-- Currency
	StartCoins = 100,
	StartGems = 10,
	CoinOrbValue = 25,
	CoinOrbCount = 20,
	CoinRespawnSeconds = 15,
	WinCoins = 500,
	WinGems = 5,

	-- XP / Levels (xpNeeded = Base + Level * Growth)
	XPBase = 100,
	XPGrowth = 50,
	MaxLevel = 100,
	LevelCoinReward = 150,
	LevelGemReward = 3,

	-- Rebirth
	RebirthWinsRequired = 5,
	RebirthCoinBonus = 0.5,
	MaxRebirths = 50,

	-- Obby course
	StageCount = 25,
	StageSpacing = 24,
	CheckpointSize = Vector3.new(8, 1, 8),
	FallKillY = -50,

	-- Enemies / dummies
	EnemyCount = 4,
	EnemyWalkSpeed = 12,
	EnemyDamage = 10,
	EnemyDamageCooldown = 1,
	EnemyRespawnSeconds = 20,
	EnemyHealth = 150,
	DummyCount = 5,
	DummyHealth = 100,
	DummyRewardCoins = 30,
	DummyRespawnSeconds = 15,

	-- Tools / shop prices (coins)
	Prices = {
		SpeedCoil = 500,
		GravityCoil = 750,
		SwiftSword = 1000,
		HealPotion = 250,
	},
	SpeedCoilSpeed = 32,
	GravityCoilJump = 75,
	SwordDamage = 25,

	-- Quests (goal, rewards)
	Quests = {
		{ Id = "earn1", Name = "Earn 1,000 Coins", Goal = 1000, Stat = "CoinsEarned", RewardCoins = 200, RewardGems = 2 },
		{ Id = "climb1", Name = "Reach Stage 10", Goal = 10, Stat = "BestStage", RewardCoins = 300, RewardGems = 3 },
		{ Id = "climb2", Name = "Reach Stage 20", Goal = 20, Stat = "BestStage", RewardCoins = 600, RewardGems = 6 },
		{ Id = "win1", Name = "Win 3 Times", Goal = 3, Stat = "Wins", RewardCoins = 800, RewardGems = 8 },
		{ Id = "dummy1", Name = "Defeat 10 Dummies", Goal = 10, Stat = "DummiesDefeated", RewardCoins = 400, RewardGems = 4 },
	},

	-- Daily login streak (day 1..7 cycle)
	DailyRewards = { 100, 150, 200, 300, 400, 500, 1000 },

	-- Gamepasses (0 = disabled / open to everyone)
	Gamepasses = {
		VIPDoor = 0,
		DoubleCoins = 0,
	},

	-- Events
	DoubleCoinsMinutes = 10,
	DoubleCoinsEveryMinutes = 45,
	FullDaySeconds = 360,
	AnnounceInterval = 90,

	-- Anti-exploit
	MaxWalkSpeed = 40,
	MaxJumpPower = 100,
	MaxStrikes = 5,

	-- Admins: add your Roblox username or UserId here
	Admins = {
		-- "YourNameHere",
		-- 12345678,
	},
}

--------------------------------------------------------------------------------
-- 2. SERVICES
--------------------------------------------------------------------------------
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local IS_STUDIO = RunService:IsStudio()

--------------------------------------------------------------------------------
-- 3. GAME DISPATCHER -- forward declarations so early code can call systems
--    that are defined later in this file. Filled in with real functions below.
--------------------------------------------------------------------------------
local Game = {}
function Game.onProgress(player) end
function Game.onWin(player) end
function Game.buyItem(player, itemId) return false end
function Game.respawn(player) end
function Game.isDoubleCoins() return false end
function Game.hasDoublePass(player) return false end

--------------------------------------------------------------------------------
-- 4. LOGGER -- one place for every print/warn in this game
--------------------------------------------------------------------------------
local Logger = {}
Logger.Prefix = "[MegaBlox] "

function Logger.joinArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring(select(i, ...))
	end
	return table.concat(parts, " ")
end

function Logger.info(...)
	print(Logger.Prefix .. Logger.joinArgs(...))
end

function Logger.warn(...)
	warn(Logger.Prefix .. Logger.joinArgs(...))
end

--------------------------------------------------------------------------------
-- 5. UTILS -- small helpers used all over the game
--------------------------------------------------------------------------------
local Util = {}

function Util.clamp(n, lo, hi)
	if n < lo then
		return lo
	elseif n > hi then
		return hi
	end
	return n
end

function Util.round(n)
	return math.floor(n + 0.5)
end

function Util.formatCoins(n)
	n = math.floor(n or 0)
	if n >= 1000000000 then
		return string.format("%.1fB", n / 1000000000)
	elseif n >= 1000000 then
		return string.format("%.1fM", n / 1000000)
	elseif n >= 1000 then
		return string.format("%.1fk", n / 1000)
	end
	return tostring(n)
end

function Util.retry(fn, tries, waitSecs)
	local lastErr = nil
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		lastErr = res
		if i < tries then
			task.wait(waitSecs or 1)
		end
	end
	return false, lastErr
end

function Util.dayNumber()
	return math.floor(os.time() / 86400)
end

function Util.splitWords(s)
	local out = {}
	for word in string.gmatch(s, "%S+") do
		out[#out + 1] = word
	end
	return out
end

function Util.isAdmin(player)
	for _, entry in ipairs(CONFIG.Admins) do
		if type(entry) == "number" and player.UserId == entry then
			return true
		elseif type(entry) == "string" and string.lower(player.Name) == string.lower(entry) then
			return true
		end
	end
	-- Inside Studio, play-testers double as admins so you can try commands.
	if IS_STUDIO then
		return true
	end
	return false
end

function Util.getHumanoid(player)
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid")
end

function Util.teleportTo(player, cframe)
	if not cframe then
		return
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.CFrame = cframe + Vector3.new(0, 5, 0)
	end
end

function Util.ownsGamePass(player, passId)
	if not passId or passId == 0 then
		return true
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
	end)
	if ok then
		return owns
	end
	return false
end

--------------------------------------------------------------------------------
-- 6. NOTIFIER -- server-built popup messages (no LocalScripts needed)
--------------------------------------------------------------------------------
local Notifier = {}

function Notifier.getContainer(player)
	local guiRoot = player:FindFirstChildOfClass("PlayerGui")
	if not guiRoot then
		return nil
	end
	local gui = guiRoot:FindFirstChild("GameNotifications")
	if gui then
		return gui:FindFirstChildOfClass("Frame")
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "GameNotifications"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = guiRoot
	local frame = Instance.new("Frame")
	frame.Name = "List"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.Position = UDim2.new(0, 12, 1, -12)
	frame.Size = UDim2.new(0, 380, 0, 220)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 6)
	layout.Parent = frame
	return frame
end

function Notifier.send(player, text, color)
	if not player or not player.Parent then
		return
	end
	local box = Notifier.getContainer(player)
	if not box then
		return
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 34)
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 15
	label.TextWrapped = true
	label.Text = tostring(text)
	label.Parent = box
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	Debris:AddItem(label, 5)
	task.delay(4, function()
		if label.Parent then
			local tween = TweenService:Create(label,
				TweenInfo.new(1, Enum.EasingStyle.Linear),
				{ BackgroundTransparency = 1, TextTransparency = 1 })
			tween:Play()
		end
	end)
end

function Notifier.broadcast(text, color)
	for _, player in ipairs(Players:GetPlayers()) do
		Notifier.send(player, text, color)
	end
end

--------------------------------------------------------------------------------
-- 7. DATA MANAGER -- load / save / autosave / daily streaks
--------------------------------------------------------------------------------
local DataManager = {}
DataManager._cache = {}
DataManager._store = nil
DataManager._storeOK = false

function DataManager.defaultData()
	return {
		Coins = CONFIG.StartCoins,
		Gems = CONFIG.StartGems,
		Wins = 0,
		Rebirths = 0,
		Level = 1,
		XP = 0,
		Stage = 1,
		BestStage = 1,
		CoinsEarned = 0,
		DummiesDefeated = 0,
		QuestsDone = {},
		LastDailyDay = 0,
		Streak = 0,
	}
end

function DataManager.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(CONFIG.DataStoreName)
	end)
	if ok and result then
		DataManager._store = result
		DataManager._storeOK = true
		Logger.info("DataStore connected.")
	else
		Logger.warn("DataStore unavailable, using session-only data.", tostring(result))
	end
end

function DataManager.load(player)
	local data = DataManager.defaultData()
	if DataManager._storeOK then
		local ok, saved = Util.retry(function()
			return DataManager._store:GetAsync("player_" .. player.UserId)
		end, CONFIG.DataLoadRetries, 1)
		if ok and type(saved) == "table" then
			for k, v in pairs(saved) do
				if data[k] ~= nil or k == "QuestsDone" then
					data[k] = v
				end
			end
			Logger.info("Loaded data for", player.Name)
		else
			Logger.warn("Using default data for", player.Name)
		end
	end
	-- Sanitize numbers so corrupt saves cannot break the game.
	for _, key in ipairs({ "Coins", "Gems", "Wins", "Rebirths", "Level", "XP",
		"Stage", "BestStage", "CoinsEarned", "DummiesDefeated", "Streak", "LastDailyDay" }) do
		if type(data[key]) ~= "number" or data[key] ~= data[key] then
			data[key] = 0
		end
		if data[key] < 0 then
			data[key] = 0
		end
	end
	if data.Level < 1 then
		data.Level = 1
	end
	if data.Stage < 1 then
		data.Stage = 1
	end
	if type(data.QuestsDone) ~= "table" then
		data.QuestsDone = {}
	end
	-- Daily login streak.
	local daily = nil
	local today = Util.dayNumber()
	if data.LastDailyDay ~= today then
		if data.LastDailyDay == today - 1 then
			data.Streak = (data.Streak % 7) + 1
		else
			data.Streak = 1
		end
		data.LastDailyDay = today
		local reward = CONFIG.DailyRewards[Util.clamp(data.Streak, 1, 7)] or 100
		data.Coins = data.Coins + reward
		daily = { streak = data.Streak, reward = reward }
	end
	DataManager._cache[player.UserId] = { data = data, player = player }
	return data, daily
end

function DataManager.get(player)
	local entry = DataManager._cache[player.UserId]
	if entry then
		return entry.data
	end
	return nil
end

-- Copies live leaderstat values back into the cached table before saving.
function DataManager.syncLiveValues(player, data)
	local board = player:FindFirstChild("leaderstats")
	local hidden = player:FindFirstChild("HiddenStats")
	local function read(folder, name, fallback)
		if folder then
			local v = folder:FindFirstChild(name)
			if v and v:IsA("IntValue") then
				return v.Value
			end
		end
		return fallback
	end
	data.Coins = read(board, "Coins", data.Coins)
	data.Gems = read(board, "Gems", data.Gems)
	data.Wins = read(board, "Wins", data.Wins)
	data.Rebirths = read(board, "Rebirths", data.Rebirths)
	data.Level = read(board, "Level", data.Level)
	data.Stage = read(hidden, "Stage", data.Stage)
	data.XP = read(hidden, "XP", data.XP)
	data.CoinsEarned = read(hidden, "CoinsEarned", data.CoinsEarned)
	data.BestStage = read(hidden, "BestStage", data.BestStage)
	data.DummiesDefeated = read(hidden, "DummiesDefeated", data.DummiesDefeated)
end

function DataManager.save(player)
	local entry = DataManager._cache[player.UserId]
	if not entry then
		return false
	end
	DataManager.syncLiveValues(player, entry.data)
	if not DataManager._storeOK then
		return true
	end
	local ok, err = Util.retry(function()
		DataManager._store:SetAsync("player_" .. player.UserId, entry.data)
	end, 3, 1)
	if ok then
		Logger.info("Saved data for", player.Name)
	else
		Logger.warn("Save failed for", player.Name, tostring(err))
	end
	return ok
end

function DataManager.saveAll()
	for _, entry in pairs(DataManager._cache) do
		if entry.player and entry.player.Parent then
			DataManager.save(entry.player)
		end
	end
end

function DataManager.clear(player)
	DataManager._cache[player.UserId] = nil
end

--------------------------------------------------------------------------------
-- 8. STATS MANAGER -- leaderstats, XP/levels, coins, rebirths
--------------------------------------------------------------------------------
local StatsManager = {}

local function readNum(player, name, fallback)
	for _, folderName in ipairs({ "leaderstats", "HiddenStats" }) do
		local folder = player:FindFirstChild(folderName)
		if folder then
			local v = folder:FindFirstChild(name)
			if v and v:IsA("IntValue") then
				return v.Value
			end
		end
	end
	return fallback or 0
end

local function writeNum(player, name, value)
	for _, folderName in ipairs({ "leaderstats", "HiddenStats" }) do
		local folder = player:FindFirstChild(folderName)
		if folder then
			local v = folder:FindFirstChild(name)
			if v and v:IsA("IntValue") then
				v.Value = math.floor(value)
				return true
			end
		end
	end
	return false
end

function StatsManager.setup(player, data)
	local old = player:FindFirstChild("leaderstats")
	if old then
		old:Destroy()
	end
	local hiddenOld = player:FindFirstChild("HiddenStats")
	if hiddenOld then
		hiddenOld:Destroy()
	end
	local board = Instance.new("Folder")
	board.Name = "leaderstats"
	board.Parent = player
	local function addInt(parent, name, val)
		local v = Instance.new("IntValue")
		v.Name = name
		v.Value = math.floor(val or 0)
		v.Parent = parent
		return v
	end
	addInt(board, "Coins", data.Coins)
	addInt(board, "Gems", data.Gems)
	addInt(board, "Wins", data.Wins)
	addInt(board, "Rebirths", data.Rebirths)
	addInt(board, "Level", math.max(1, data.Level))
	local hidden = Instance.new("Folder")
	hidden.Name = "HiddenStats"
	hidden.Parent = player
	addInt(hidden, "Stage", math.max(1, data.Stage))
	addInt(hidden, "XP", data.XP)
	addInt(hidden, "CoinsEarned", data.CoinsEarned)
	addInt(hidden, "BestStage", math.max(1, data.BestStage))
	addInt(hidden, "DummiesDefeated", data.DummiesDefeated)
end

function StatsManager.getCoins(player)
	return readNum(player, "Coins", 0)
end

function StatsManager.xpNeeded(level)
	return CONFIG.XPBase + (level * CONFIG.XPGrowth)
end

-- Awards coins with rebirth + event + gamepass multipliers. Returns granted.
function StatsManager.addCoins(player, base, noMult)
	base = math.floor(base or 0)
	if base <= 0 then
		return 0
	end
	local mult = 1
	if not noMult then
		mult = mult + (readNum(player, "Rebirths", 0) * CONFIG.RebirthCoinBonus)
		if Game.isDoubleCoins() then
			mult = mult * 2
		end
		if Game.hasDoublePass(player) then
			mult = mult * 2
		end
	end
	local grant = Util.round(base * mult)
	writeNum(player, "Coins", readNum(player, "Coins", 0) + grant)
	writeNum(player, "CoinsEarned", readNum(player, "CoinsEarned", 0) + base)
	Game.onProgress(player)
	return grant
end

function StatsManager.spendCoins(player, price)
	price = math.floor(price or 0)
	local have = readNum(player, "Coins", 0)
	if have < price then
		return false
	end
	writeNum(player, "Coins", have - price)
	return true
end

function StatsManager.addGems(player, amount)
	amount = math.floor(amount or 0)
	if amount <= 0 then
		return
	end
	writeNum(player, "Gems", readNum(player, "Gems", 0) + amount)
	Game.onProgress(player)
end

function StatsManager.addWins(player, amount)
	amount = math.floor(amount or 1)
	if amount <= 0 then
		return
	end
	writeNum(player, "Wins", readNum(player, "Wins", 0) + amount)
	Game.onProgress(player)
end

function StatsManager.addXP(player, amount)
	amount = math.floor(amount or 0)
	if amount <= 0 then
		return
	end
	local level = Util.clamp(readNum(player, "Level", 1), 1, CONFIG.MaxLevel)
	local xp = readNum(player, "XP", 0) + amount
	while level < CONFIG.MaxLevel and xp >= StatsManager.xpNeeded(level) do
		xp = xp - StatsManager.xpNeeded(level)
		level = level + 1
		writeNum(player, "Coins", readNum(player, "Coins", 0) + CONFIG.LevelCoinReward)
		writeNum(player, "Gems", readNum(player, "Gems", 0) + CONFIG.LevelGemReward)
		Notifier.send(player, "LEVEL UP! You are now level " .. level
			.. " (+" .. CONFIG.LevelCoinReward .. " coins, +"
			.. CONFIG.LevelGemReward .. " gems)")
	end
	writeNum(player, "Level", level)
	writeNum(player, "XP", xp)
	Game.onProgress(player)
end

function StatsManager.getStage(player)
	return Util.clamp(readNum(player, "Stage", 1), 1, CONFIG.StageCount)
end

function StatsManager.setStage(player, stage)
	stage = Util.clamp(math.floor(stage or 1), 1, CONFIG.StageCount)
	writeNum(player, "Stage", stage)
	if stage > readNum(player, "BestStage", 1) then
		writeNum(player, "BestStage", stage)
	end
	Game.onProgress(player)
end

function StatsManager.addDummyKill(player)
	writeNum(player, "DummiesDefeated", readNum(player, "DummiesDefeated", 0) + 1)
	Game.onProgress(player)
end

function StatsManager.tryRebirth(player)
	local rebirths = readNum(player, "Rebirths", 0)
	local wins = readNum(player, "Wins", 0)
	if rebirths >= CONFIG.MaxRebirths then
		return false, "Max rebirths reached!"
	end
	if wins < CONFIG.RebirthWinsRequired then
		return false, "Need " .. CONFIG.RebirthWinsRequired .. " wins (you have " .. wins .. ")."
	end
	writeNum(player, "Rebirths", rebirths + 1)
	writeNum(player, "Wins", 0)
	writeNum(player, "Coins", CONFIG.StartCoins)
	writeNum(player, "Level", 1)
	writeNum(player, "XP", 0)
	StatsManager.setStage(player, 1)
	Game.respawn(player)
	Notifier.broadcast(player.Name .. " rebirthed! (x" .. (rebirths + 1) .. " coins)",
		Color3.fromRGB(255, 200, 60))
	return true, "REBIRTH! Coins reset, but you now earn +" ..
		Util.round((rebirths + 1) * CONFIG.RebirthCoinBonus * 100) .. "% coins forever."
end

--------------------------------------------------------------------------------
-- 9. WORLD BUILDER -- the script builds the whole map by itself
--------------------------------------------------------------------------------
local SHOP_ITEMS = {
	{ Id = "SpeedCoil", Name = "Speed Coil" },
	{ Id = "GravityCoil", Name = "Gravity Coil" },
	{ Id = "SwiftSword", Name = "Swift Sword" },
	{ Id = "HealPotion", Name = "Heal Potion" },
}

local WorldBuilder = {}
WorldBuilder.StageSpawns = {}
WorldBuilder.Movers = {}
WorldBuilder.Faders = {}
WorldBuilder.CoinParts = {}
WorldBuilder.Dummies = {}
WorldBuilder.Enemies = {}
WorldBuilder.SpawnCF = CFrame.new(0, 14, -8)
WorldBuilder.ArenaCenter = Vector3.new(-55, 10, 55)

local worldFolder = nil

local function P(name, size, pos, mat, color, opts)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = pos
	part.Material = mat or Enum.Material.SmoothPlastic
	part.Color = color or Color3.fromRGB(163, 162, 165)
	part.Anchored = true
	part.Parent = worldFolder
	if opts then
		for k, v in pairs(opts) do
			part[k] = v
		end
	end
	return part
end

local function signBoard(text, subtext, pos, width)
	width = width or 400
	P("SignPole", Vector3.new(1, 8, 1), pos + Vector3.new(0, 4, 0),
		Enum.Material.Wood, Color3.fromRGB(90, 60, 30))
	local head = P("SignHead", Vector3.new(12, 4, 1), pos + Vector3.new(0, 9, 0),
		Enum.Material.WoodPlanks, Color3.fromRGB(120, 80, 40))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, width, 0, 120)
	gui.StudsOffset = Vector3.new(0, 1, 0)
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0.6, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 30
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	if subtext then
		local sub = Instance.new("TextLabel")
		sub.Size = UDim2.new(1, 0, 0.4, 0)
		sub.Position = UDim2.new(0, 0, 0.6, 0)
		sub.BackgroundTransparency = 1
		sub.Font = Enum.Font.GothamBold
		sub.TextSize = 18
		sub.TextColor3 = Color3.fromRGB(255, 230, 150)
		sub.Text = subtext
		sub.Parent = gui
	end
end

local function priceTag(parentPart, title, price)
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(0, 220, 0, 90)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.Parent = parentPart
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
	label.BackgroundTransparency = 0.3
	label.Font = Enum.Font.GothamBold
	label.TextSize = 17
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextWrapped = true
	label.Text = title .. "\n" .. Util.formatCoins(price) .. " coins (click)"
	label.Parent = gui
end

local function spawnBurst(pos, color)
	local dot = Instance.new("Part")
	dot.Name = "BurstFX"
	dot.Shape = Enum.PartType.Ball
	dot.Size = Vector3.new(1, 1, 1)
	dot.CFrame = CFrame.new(pos)
	dot.Color = color or Color3.fromRGB(255, 220, 60)
	dot.Material = Enum.Material.Neon
	dot.Anchored = true
	dot.CanCollide = false
	dot.CanTouch = false
	dot.CanQuery = false
	dot.Parent = worldFolder
	local fx = Instance.new("ParticleEmitter")
	fx.Color = ColorSequence.new(dot.Color)
	fx.Size = NumberSequence.new(1.2)
	fx.Speed = NumberRange.new(12, 24)
	fx.Lifetime = NumberRange.new(0.4, 0.9)
	fx.Rate = 0
	fx.Parent = dot
	fx:Emit(30)
	Debris:AddItem(dot, 1.5)
end

local function killCharacter(humanoid)
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = 0
	end
end

local function playerFromHit(hit)
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model then
		return nil, nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, nil
	end
	return Players:GetPlayerFromCharacter(model), humanoid
end

--------------------------------------------------------------------------------
-- 9a. Spawn area
--------------------------------------------------------------------------------
function WorldBuilder.buildSpawn()
	P("SpawnPlatform", Vector3.new(48, 1, 40), Vector3.new(0, 10, -4),
		Enum.Material.Grass, Color3.fromRGB(80, 160, 70))
	P("SpawnLocationPad", Vector3.new(8, 1, 8), Vector3.new(0, 10.6, -14),
		Enum.Material.SmoothPlastic, Color3.fromRGB(60, 120, 200))
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.Position = Vector3.new(0, 11.2, -14)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Anchored = true
	spawn.Parent = worldFolder
	WorldBuilder.SpawnCF = CFrame.new(0, 13, -14)
	signBoard(CONFIG.GameName, "Finish the obby - earn coins - rebirth!  Type /shop",
		Vector3.new(0, 11, 4), 500)
	local rb = P("RebirthPad", Vector3.new(6, 1, 6), Vector3.new(-17, 10.6, 8),
		Enum.Material.Neon, Color3.fromRGB(170, 60, 220))
	priceTag(rb, "REBIRTH (" .. CONFIG.RebirthWinsRequired .. " wins)", 0)
	local rbDeb = {}
	rb.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if not player then
			return
		end
		if rbDeb[player] and os.clock() - rbDeb[player] < 2 then
			return
		end
		rbDeb[player] = os.clock()
		local ok, msg = StatsManager.tryRebirth(player)
		Notifier.send(player, msg, ok and Color3.fromRGB(220, 150, 255) or Color3.fromRGB(255, 120, 120))
	end)
end

--------------------------------------------------------------------------------
-- 9b. Obby course
--------------------------------------------------------------------------------
function WorldBuilder.buildCourse()
	local startZ = 30
	local spacing = CONFIG.StageSpacing
	local padDeb = {}

	local function checkpointTouch(pad, stage)
		pad.Touched:Connect(function(hit)
			local player, humanoid = playerFromHit(hit)
			if not player or not humanoid then
				return
			end
			if padDeb[player] and os.clock() - padDeb[player] < 1 then
				return
			end
			padDeb[player] = os.clock()
			if StatsManager.getStage(player) < stage then
				StatsManager.setStage(player, stage)
				humanoid.Health = humanoid.MaxHealth
				Notifier.send(player, "Checkpoint: Stage " .. stage .. "/" .. CONFIG.StageCount,
					Color3.fromRGB(140, 255, 140))
				local old = pad.Color
				pad.Color = Color3.fromRGB(255, 255, 255)
				task.delay(0.4, function()
					if pad.Parent then
						pad.Color = old
					end
				end)
			end
		end)
	end

	local function lavaTouch(part)
		part.Touched:Connect(function(hit)
			local _, humanoid = playerFromHit(hit)
			if humanoid then
				killCharacter(humanoid)
			end
		end)
	end

	for i = 1, CONFIG.StageCount do
		local z = startZ + (i - 1) * spacing
		local tint
		if i == CONFIG.StageCount then
			tint = Color3.fromRGB(255, 200, 40)
		elseif i % 5 == 0 then
			tint = Color3.fromRGB(120, 200, 255)
		elseif i % 2 == 0 then
			tint = Color3.fromRGB(240, 240, 240)
		else
			tint = Color3.fromRGB(255, 150, 90)
		end
		local pad = P("Stage" .. i, CONFIG.CheckpointSize, Vector3.new(0, 10, z),
			Enum.Material.SmoothPlastic, tint, { TopSurface = Enum.SurfaceType.Smooth })
		pad:SetAttribute("Stage", i)
		WorldBuilder.StageSpawns[i] = CFrame.new(Vector3.new(0, 13, z))
		checkpointTouch(pad, i)

		if i < CONFIG.StageCount then
			local mid = z + spacing / 2
			local variant = i % 6
			if variant == 1 then
				P("Stone", Vector3.new(4, 1, 4), Vector3.new(0, 10, mid - 6),
					Enum.Material.Slate, Color3.fromRGB(140, 140, 150))
				P("Stone", Vector3.new(4, 1, 4), Vector3.new(0, 10, mid + 6),
					Enum.Material.Slate, Color3.fromRGB(140, 140, 150))
			elseif variant == 2 then
				P("Stone", Vector3.new(4, 1, 4), Vector3.new(0, 10, mid - 6),
					Enum.Material.Slate, Color3.fromRGB(140, 140, 150))
				local lava = P("Lava", Vector3.new(6, 1, 5), Vector3.new(0, 9.8, mid),
					Enum.Material.Neon, Color3.fromRGB(255, 60, 20))
				lavaTouch(lava)
				P("Stone", Vector3.new(4, 1, 4), Vector3.new(0, 10, mid + 6),
					Enum.Material.Slate, Color3.fromRGB(140, 140, 150))
			elseif variant == 3 then
				for s = 0, 3 do
					P("Step", Vector3.new(4, 1, 4),
						Vector3.new(0, 10 + s, mid - 9 + (s * 4)),
						Enum.Material.WoodPlanks, Color3.fromRGB(170, 120, 70))
				end
			elseif variant == 4 then
				P("Beam", Vector3.new(2, 1, 20), Vector3.new(0, 10, mid),
					Enum.Material.Wood, Color3.fromRGB(200, 170, 100))
			elseif variant == 5 then
				local mover = P("Mover", Vector3.new(4, 1, 4), Vector3.new(0, 10, mid),
					Enum.Material.Neon, Color3.fromRGB(90, 220, 255))
				WorldBuilder.Movers[#WorldBuilder.Movers + 1] = {
					part = mover, base = mover.CFrame, range = 5, speed = 2, phase = i,
				}
			else
				for k = 1, 2 do
					local f = P("Fader", Vector3.new(5, 1, 5),
						Vector3.new(0, 10, mid - 6 + ((k - 1) * 12)),
						Enum.Material.Neon, Color3.fromRGB(220, 120, 255))
					WorldBuilder.Faders[#WorldBuilder.Faders + 1] = {
						part = f, offset = (k - 1) * 2,
					}
				end
			end
		end

		if i % 5 == 1 then
			P("TorchPole", Vector3.new(0.6, 6, 0.6), Vector3.new(7, 13, z),
				Enum.Material.Wood, Color3.fromRGB(90, 60, 30))
			local flame = P("TorchFlame", Vector3.new(1.4, 1.4, 1.4), Vector3.new(7, 16.4, z),
				Enum.Material.Neon, Color3.fromRGB(255, 150, 30),
				{ Shape = Enum.PartType.Ball, CanCollide = false, CanTouch = false })
			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(255, 170, 60)
			light.Range = 24
			light.Parent = flame
		end
	end
end

--------------------------------------------------------------------------------
-- 9c. Win area
--------------------------------------------------------------------------------
function WorldBuilder.buildWinArea()
	local lastZ = 30 + (CONFIG.StageCount - 1) * CONFIG.StageSpacing
	local z = lastZ + CONFIG.StageSpacing
	P("WinPlatform", Vector3.new(24, 1, 24), Vector3.new(0, 10, z),
		Enum.Material.Marble, Color3.fromRGB(250, 230, 150))
	local winPad = P("WinPad", Vector3.new(10, 1, 4), Vector3.new(0, 10.6, z),
		Enum.Material.Neon, Color3.fromRGB(255, 210, 40))
	WorldBuilder.WinPad = winPad
	P("TrophyBase", Vector3.new(3, 1, 3), Vector3.new(-8, 11, z - 6),
		Enum.Material.Marble, Color3.fromRGB(200, 200, 200))
	P("TrophyPole", Vector3.new(0.8, 4, 0.8), Vector3.new(-8, 13.4, z - 6),
		Enum.Material.Neon, Color3.fromRGB(255, 210, 40))
	P("TrophyCup", Vector3.new(2.4, 2.4, 2.4), Vector3.new(-8, 16.4, z - 6),
		Enum.Material.Neon, Color3.fromRGB(255, 210, 40), { Shape = Enum.PartType.Ball })
	signBoard("YOU WIN!", "Step on the gold pad", Vector3.new(8, 11, z + 6), 300)
end

function WorldBuilder.fireworks(center)
	for i = 1, 4 do
		task.delay(i * 0.35, function()
			local pos = center + Vector3.new(math.random(-12, 12), math.random(6, 16), math.random(-12, 12))
			local palette = { Color3.fromRGB(255, 90, 90), Color3.fromRGB(90, 255, 140),
				Color3.fromRGB(120, 160, 255), Color3.fromRGB(255, 220, 80) }
			spawnBurst(pos, palette[math.random(1, #palette)])
		end)
	end
end

--------------------------------------------------------------------------------
-- 9d. Coin orbs
--------------------------------------------------------------------------------
function WorldBuilder.buildCoins()
	local spots = {}
	for i = 1, 8 do
		local a = (math.pi * 2 * i) / 8
		spots[#spots + 1] = Vector3.new(math.cos(a) * 18, 12.5, -4 + (math.sin(a) * 14))
	end
	for i = 1, 8 do
		local z = 30 + (i - 1) * 60
		local x = 10
		if i % 2 == 0 then
			x = -10
		end
		spots[#spots + 1] = Vector3.new(x, 12.5, z)
	end
	for i = 1, 4 do
		spots[#spots + 1] = Vector3.new(40 + (i * 3), 12.5, -6 + (i * 3))
	end
	for n, pos in ipairs(spots) do
		if n > CONFIG.CoinOrbCount + 4 then
			break
		end
		local orb = P("CoinOrb", Vector3.new(2, 2, 2), pos,
			Enum.Material.Neon, Color3.fromRGB(255, 210, 40),
			{ Shape = Enum.PartType.Ball, CanCollide = false })
		orb:SetAttribute("CoinOrb", true)
		WorldBuilder.CoinParts[#WorldBuilder.CoinParts + 1] = orb
		local takenAt = 0
		orb.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if not player then
				return
			end
			if os.clock() - takenAt < 1 then
				return
			end
			takenAt = os.clock()
			StatsManager.addCoins(player, CONFIG.CoinOrbValue)
			spawnBurst(orb.Position, Color3.fromRGB(255, 210, 40))
			orb.Transparency = 1
			orb.CanTouch = false
			task.delay(CONFIG.CoinRespawnSeconds, function()
				if orb.Parent then
					orb.Transparency = 0
					orb.CanTouch = true
				end
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- 9e. Training dummies (breakable blocks)
--------------------------------------------------------------------------------
function WorldBuilder.buildDummies()
	P("TrainingMat", Vector3.new(40, 1, 14), Vector3.new(0, 10, 22),
		Enum.Material.SmoothPlastic, Color3.fromRGB(200, 90, 90))
	signBoard("TRAINING", "Hit dummies with your sword", Vector3.new(-14, 11, 22), 340)
	for i = 1, CONFIG.DummyCount do
		local x = -14 + ((i - 1) * 7)
		local body = P("Dummy", Vector3.new(2.5, 5, 2.5), Vector3.new(x, 13, 22),
			Enum.Material.Wood, Color3.fromRGB(150, 100, 60))
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 120, 0, 40)
		gui.StudsOffset = Vector3.new(0, 3.4, 0)
		gui.Parent = body
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(255, 255, 255)
		label.Text = "Dummy " .. CONFIG.DummyHealth
		label.Parent = gui
		WorldBuilder.Dummies[#WorldBuilder.Dummies + 1] = {
			part = body, health = CONFIG.DummyHealth, max = CONFIG.DummyHealth,
			label = label, alive = true,
		}
	end
end

function WorldBuilder.findBreakable(part)
	for _, d in ipairs(WorldBuilder.Dummies) do
		if d.part == part then
			return "dummy", d
		end
	end
	for _, e in ipairs(WorldBuilder.Enemies) do
		if e.part == part then
			return "enemy", e
		end
	end
	return nil, nil
end

function WorldBuilder.damageDummy(entry, dmg, attacker)
	if not entry.alive then
		return
	end
	entry.health = entry.health - dmg
	if entry.health <= 0 then
		entry.health = 0
		entry.alive = false
		entry.label.Text = "KO!"
		entry.part.Transparency = 1
		entry.part.CanTouch = false
		entry.part.CanCollide = false
		spawnBurst(entry.part.Position, Color3.fromRGB(255, 150, 60))
		if attacker and attacker.Parent then
			StatsManager.addCoins(attacker, CONFIG.DummyRewardCoins)
			StatsManager.addXP(attacker, 10)
			StatsManager.addDummyKill(attacker)
			Notifier.send(attacker, "+" .. CONFIG.DummyRewardCoins .. " coins! Dummy destroyed (+10 XP)")
		end
		task.delay(CONFIG.DummyRespawnSeconds, function()
			if entry.part.Parent then
				entry.health = entry.max
				entry.alive = true
				entry.label.Text = "Dummy " .. entry.max
				entry.part.Transparency = 0
				entry.part.CanTouch = true
				entry.part.CanCollide = true
			end
		end)
	else
		entry.label.Text = "Dummy " .. math.floor(entry.health)
		local old = entry.part.Color
		entry.part.Color = Color3.fromRGB(255, 80, 80)
		task.delay(0.15, function()
			if entry.part.Parent and entry.alive then
				entry.part.Color = old
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- 9f. Enemy arena (chaser blocks)
--------------------------------------------------------------------------------
function WorldBuilder.buildEnemies()
	local c = WorldBuilder.ArenaCenter
	P("ArenaFloor", Vector3.new(60, 1, 60), c,
		Enum.Material.Sand, Color3.fromRGB(190, 150, 90))
	signBoard("MONSTER ARENA", "Beware of chasers - fight back with a sword!",
		c + Vector3.new(0, 1, -28), 420)
	local tp = P("ArenaTP", Vector3.new(5, 1, 5), Vector3.new(17, 10.6, 8),
		Enum.Material.Neon, Color3.fromRGB(255, 120, 60))
	priceTag(tp, "ARENA", 0)
	local tpDeb = {}
	tp.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if not player then
			return
		end
		if tpDeb[player] and os.clock() - tpDeb[player] < 2 then
			return
		end
		tpDeb[player] = os.clock()
		Util.teleportTo(player, CFrame.new(c + Vector3.new(0, 3, -20)))
		Notifier.send(player, "Welcome to the Monster Arena!")
	end)
	for i = 1, CONFIG.EnemyCount do
		local pos = c + Vector3.new(-18 + (i * 9), 3, 8)
		local body = P("Chaser", Vector3.new(3, 3, 3), pos,
			Enum.Material.Neon, Color3.fromRGB(220, 40, 40))
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 120, 0, 40)
		gui.StudsOffset = Vector3.new(0, 2.6, 0)
		gui.Parent = body
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.TextColor3 = Color3.fromRGB(255, 120, 120)
		label.Text = "Chaser " .. CONFIG.EnemyHealth
		label.Parent = gui
		local entry = {
			part = body, health = CONFIG.EnemyHealth, max = CONFIG.EnemyHealth,
			label = label, spawnPos = pos, alive = true, lastHit = 0,
		}
		WorldBuilder.Enemies[#WorldBuilder.Enemies + 1] = entry
		body.Touched:Connect(function(hit)
			local _, humanoid = playerFromHit(hit)
			if humanoid and entry.alive and os.clock() - entry.lastHit > CONFIG.EnemyDamageCooldown then
				entry.lastHit = os.clock()
				humanoid:TakeDamage(CONFIG.EnemyDamage)
			end
		end)
	end
end

function WorldBuilder.damageEnemy(entry, dmg, attacker)
	if not entry.alive then
		return
	end
	entry.health = entry.health - dmg
	if entry.health <= 0 then
		entry.health = 0
		entry.alive = false
		entry.label.Text = "KO!"
		entry.part.Transparency = 1
		entry.part.CanTouch = false
		entry.part.CanCollide = false
		spawnBurst(entry.part.Position, Color3.fromRGB(220, 40, 40))
		if attacker and attacker.Parent then
			StatsManager.addCoins(attacker, 100)
			StatsManager.addXP(attacker, 25)
			Notifier.send(attacker, "Chaser defeated! +100 coins, +25 XP",
				Color3.fromRGB(255, 180, 120))
		end
		task.delay(CONFIG.EnemyRespawnSeconds, function()
			if entry.part.Parent then
				entry.health = entry.max
				entry.alive = true
				entry.label.Text = "Chaser " .. entry.max
				entry.part.CFrame = CFrame.new(entry.spawnPos)
				entry.part.Transparency = 0
				entry.part.CanTouch = true
				entry.part.CanCollide = true
			end
		end)
	else
		entry.label.Text = "Chaser " .. math.floor(entry.health)
	end
end

--------------------------------------------------------------------------------
-- 9g. VIP lounge
--------------------------------------------------------------------------------
function WorldBuilder.buildVIP()
	P("VIPLounge", Vector3.new(24, 1, 24), Vector3.new(45, 10, 0),
		Enum.Material.Marble, Color3.fromRGB(140, 220, 255))
	signBoard("VIP LOUNGE", "Bonus coins inside", Vector3.new(45, 11, 8), 320)
	local door = P("VIPDoor", Vector3.new(1, 8, 12), Vector3.new(31, 14, 0),
		Enum.Material.Glass, Color3.fromRGB(120, 200, 255),
		{ Transparency = 0.4, CanCollide = false })
	priceTag(door, "VIP DOOR", 0)
	local doorDeb = {}
	door.Touched:Connect(function(hit)
		local player = playerFromHit(hit)
		if not player then
			return
		end
		if doorDeb[player] and os.clock() - doorDeb[player] < 2 then
			return
		end
		doorDeb[player] = os.clock()
		local allowed = Util.isAdmin(player)
			or Util.ownsGamePass(player, CONFIG.Gamepasses.VIPDoor)
		if allowed then
			Util.teleportTo(player, CFrame.new(Vector3.new(38, 13, 0)))
			Notifier.send(player, "Welcome to the VIP Lounge!")
		else
			Util.teleportTo(player, CFrame.new(Vector3.new(26, 13, 0)))
			Notifier.send(player, "VIP only! (Set a Gamepass id in CONFIG to sell access.)",
				Color3.fromRGB(255, 140, 140))
		end
	end)
end

--------------------------------------------------------------------------------
-- 9h. Shop row (click-to-buy pads)
--------------------------------------------------------------------------------
function WorldBuilder.buildShopRow()
	for i, item in ipairs(SHOP_ITEMS) do
		local price = CONFIG.Prices[item.Id] or 0
		local x = -18 + ((i - 1) * 12)
		local pad = P("Shop_" .. item.Id, Vector3.new(5, 1, 5), Vector3.new(x, 10.6, -14),
			Enum.Material.Neon, Color3.fromRGB(90, 255, 150))
		priceTag(pad, item.Name, price)
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 14
		click.Parent = pad
		local itemId = item.Id
		click.MouseClick:Connect(function(player)
			Game.buyItem(player, itemId)
		end)
	end
end

--------------------------------------------------------------------------------
-- 9i. Build everything + per-frame loops
--------------------------------------------------------------------------------
function WorldBuilder.buildAll()
	local old = Workspace:FindFirstChild("GameWorld")
	if old then
		old:Destroy()
	end
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate then
		baseplate:Destroy()
	end
	local oldSpawn = Workspace:FindFirstChild("SpawnLocation")
	if oldSpawn then
		oldSpawn:Destroy()
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "GameWorld"
	worldFolder.Parent = Workspace
	Lighting.ClockTime = 14
	Lighting.Brightness = 2
	WorldBuilder.buildSpawn()
	WorldBuilder.buildCourse()
	WorldBuilder.buildWinArea()
	WorldBuilder.buildCoins()
	WorldBuilder.buildDummies()
	WorldBuilder.buildEnemies()
	WorldBuilder.buildVIP()
	WorldBuilder.buildShopRow()
	Logger.info("World built: " .. CONFIG.StageCount .. " stages, "
		.. #WorldBuilder.CoinParts .. " coins, "
		.. #WorldBuilder.Dummies .. " dummies, "
		.. #WorldBuilder.Enemies .. " chasers.")
end

function WorldBuilder.startLoops()
	local enemyAcc = 0
	RunService.Heartbeat:Connect(function(dt)
		local t = os.clock()
		for _, m in ipairs(WorldBuilder.Movers) do
			if m.part.Parent then
				m.part.CFrame = m.base * CFrame.new(math.sin(t * m.speed + m.phase) * m.range, 0, 0)
			end
		end
		for _, f in ipairs(WorldBuilder.Faders) do
			if f.part.Parent then
				local solid = ((t + f.offset) % 4) < 2
				f.part.Transparency = solid and 0 or 1
				f.part.CanCollide = solid
				f.part.CanTouch = solid
			end
		end
		for _, orb in ipairs(WorldBuilder.CoinParts) do
			if orb.Parent and orb.Transparency == 0 then
				orb.CFrame = orb.CFrame * CFrame.Angles(0, math.rad(120) * dt, 0)
			end
		end
		enemyAcc = enemyAcc + dt
		local doAI = enemyAcc >= 0.15
		if doAI then
			enemyAcc = 0
		end
		for _, player in ipairs(Players:GetPlayers()) do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				if hrp.Position.Y < CONFIG.FallKillY then
					local cf = WorldBuilder.StageSpawns[StatsManager.getStage(player)]
						or WorldBuilder.SpawnCF
					hrp.CFrame = cf + Vector3.new(0, 5, 0)
				end
				if doAI then
					WorldBuilder._targets[#WorldBuilder._targets + 1] = hrp
				end
			end
		end
		if doAI then
			WorldBuilder.moveEnemies(0.15)
		end
	end)
end

WorldBuilder._targets = {}

function WorldBuilder.moveEnemies(step)
	for _, e in ipairs(WorldBuilder.Enemies) do
		if e.alive and e.part.Parent then
			local best = nil
			local bestDist = 60
			for _, hrp in ipairs(WorldBuilder._targets) do
				if hrp.Parent then
					local d = (hrp.Position - e.part.Position).Magnitude
					if d < bestDist then
						bestDist = d
						best = hrp
					end
				end
			end
			if best and bestDist > 5 then
				local from = e.part.Position
				local to = best.Position
				local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
				if dir.Magnitude > 0.01 then
					dir = dir.Unit
					local nextPos = from + (dir * CONFIG.EnemyWalkSpeed * step)
					local flat = Vector3.new(nextPos.X - WorldBuilder.ArenaCenter.X, 0,
						nextPos.Z - WorldBuilder.ArenaCenter.Z)
					if flat.Magnitude < 28 then
						e.part.CFrame = CFrame.new(Vector3.new(nextPos.X, e.spawnPos.Y, nextPos.Z))
					end
				end
			end
		end
	end
	table.clear(WorldBuilder._targets)
end

--------------------------------------------------------------------------------
-- 10. TOOLS FACTORY -- coils, sword, potion (built by code, no assets)
--------------------------------------------------------------------------------
local ToolsFactory = {}
ToolsFactory.Templates = {}

local function makeHandle(color, size, shape)
	local h = Instance.new("Part")
	h.Name = "Handle"
	h.Size = size or Vector3.new(0.5, 2, 0.5)
	h.Color = color
	h.Material = Enum.Material.Neon
	if shape then
		h.Shape = shape
	end
	return h
end

local function baseTool(name)
	local t = Instance.new("Tool")
	t.Name = name
	t.CanBeDropped = false
	return t
end

function ToolsFactory.createSpeedCoil()
	local tool = baseTool("Speed Coil")
	tool:SetAttribute("Coil", "Speed")
	tool.ToolTip = "Equip to run super fast!"
	makeHandle(Color3.fromRGB(60, 255, 90)).Parent = tool
	return tool
end

function ToolsFactory.createGravityCoil()
	local tool = baseTool("Gravity Coil")
	tool:SetAttribute("Coil", "Gravity")
	tool.ToolTip = "Equip to jump super high!"
	makeHandle(Color3.fromRGB(80, 140, 255)).Parent = tool
	return tool
end

function ToolsFactory.createSwiftSword()
	local tool = baseTool("Swift Sword")
	tool:SetAttribute("SwordDamage", CONFIG.SwordDamage)
	tool.ToolTip = "Click to swing. Hits dummies, chasers and players!"
	local handle = makeHandle(Color3.fromRGB(110, 70, 30), Vector3.new(0.4, 1.5, 0.4))
	handle.Material = Enum.Material.Wood
	handle.Parent = tool
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(0.3, 3, 0.8)
	blade.Color = Color3.fromRGB(220, 220, 230)
	blade.Material = Enum.Material.SmoothPlastic
	blade.CanCollide = false
	blade.Parent = tool
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = handle
	blade.CFrame = handle.CFrame * CFrame.new(0, 2.2, 0)
	return tool
end

function ToolsFactory.createHealPotion()
	local tool = baseTool("Heal Potion")
	tool:SetAttribute("Potion", true)
	tool.ToolTip = "Click to heal to full. One use!"
	makeHandle(Color3.fromRGB(255, 70, 90), Vector3.new(1.2, 1.2, 1.2), Enum.PartType.Ball).Parent = tool
	return tool
end

function ToolsFactory.init()
	local folder = ServerStorage:FindFirstChild("GameTools")
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "GameTools"
	folder.Parent = ServerStorage
	ToolsFactory.Templates.SpeedCoil = ToolsFactory.createSpeedCoil()
	ToolsFactory.Templates.SpeedCoil.Parent = folder
	ToolsFactory.Templates.GravityCoil = ToolsFactory.createGravityCoil()
	ToolsFactory.Templates.GravityCoil.Parent = folder
	ToolsFactory.Templates.SwiftSword = ToolsFactory.createSwiftSword()
	ToolsFactory.Templates.SwiftSword.Parent = folder
	ToolsFactory.Templates.HealPotion = ToolsFactory.createHealPotion()
	ToolsFactory.Templates.HealPotion.Parent = folder
end

-- Wires up behavior for one tool owned by a player. Connections live and die
-- with the tool, so respawns and drops cannot leak them.
function ToolsFactory.watch(player, tool)
	if not tool:IsA("Tool") then
		return
	end
	if tool:GetAttribute("Watched") then
		return
	end
	tool:SetAttribute("Watched", true)

	local coil = tool:GetAttribute("Coil")
	if coil == "Speed" or coil == "Gravity" then
		tool.Equipped:Connect(function()
			local _, humanoid = Util.getHumanoid(player)
			if not humanoid then
				return
			end
			if coil == "Speed" then
				humanoid.WalkSpeed = CONFIG.SpeedCoilSpeed
				Notifier.send(player, "Speed Coil ON!")
			else
				humanoid.JumpPower = CONFIG.GravityCoilJump
				Notifier.send(player, "Gravity Coil ON!")
			end
		end)
		tool.Unequipped:Connect(function()
			local _, humanoid = Util.getHumanoid(player)
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
			end
		end)
		return
	end

	if tool:GetAttribute("Potion") then
		tool.Activated:Connect(function()
			local _, humanoid = Util.getHumanoid(player)
			if humanoid and humanoid.Health > 0 then
				humanoid.Health = humanoid.MaxHealth
				Notifier.send(player, "Healed to full!", Color3.fromRGB(140, 255, 140))
				tool:Destroy()
			end
		end)
		return
	end

	local swordDmg = tool:GetAttribute("SwordDamage")
	if swordDmg and swordDmg > 0 then
		local swingUntil = 0
		local swingId = 0
		local hitThisSwing = {}
		tool.Activated:Connect(function()
			swingUntil = os.clock() + 0.6
			swingId = swingId + 1
			hitThisSwing = {}
			local char = player.Character
			local handle = tool:FindFirstChild("Handle")
			if char and handle then
				-- Quick lunge feel: brief speed pop while swinging.
				local humanoid = char:FindFirstChildOfClass("Humanoid")
				if humanoid then
					local old = humanoid.WalkSpeed
					humanoid.WalkSpeed = old + 6
					task.delay(0.3, function()
						if humanoid.Parent then
							humanoid.WalkSpeed = old
						end
					end)
				end
			end
		end)
		tool.DescendantAdded:Connect(function() end)
		local handle = tool:WaitForChild("Handle", 5)
		if handle then
			handle.Touched:Connect(function(hit)
				if os.clock() > swingUntil then
					return
				end
				if hitThisSwing[hit] then
					return
				end
				local kind, entry = WorldBuilder.findBreakable(hit)
				if kind == "dummy" then
					hitThisSwing[hit] = true
					WorldBuilder.damageDummy(entry, swordDmg, player)
					return
				elseif kind == "enemy" then
					hitThisSwing[hit] = true
					WorldBuilder.damageEnemy(entry, swordDmg, player)
					return
				end
				local model = hit:FindFirstAncestorOfClass("Model")
				local humanoid = model and model:FindFirstChildOfClass("Humanoid")
				if humanoid and model ~= player.Character and not hitThisSwing[humanoid] then
					hitThisSwing[humanoid] = true
					humanoid:TakeDamage(swordDmg)
				end
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- 11. SHOP -- spend coins, get tools (+ server-built shop window)
--------------------------------------------------------------------------------
local Shop = {}

function Shop.buy(player, itemId)
	local price = CONFIG.Prices[itemId]
	if price == nil then
		Notifier.send(player, "Unknown item.", Color3.fromRGB(255, 140, 140))
		return false
	end
	local template = ToolsFactory.Templates[itemId]
	if not template then
		Notifier.send(player, "Shop is restocking, try again!", Color3.fromRGB(255, 140, 140))
		return false
	end
	local have = StatsManager.getCoins(player)
	if have < price then
		Notifier.send(player, "Not enough coins! Need " .. Util.formatCoins(price - have) .. " more.",
			Color3.fromRGB(255, 140, 140))
		return false
	end
	StatsManager.spendCoins(player, price)
	local tool = template:Clone()
	tool.Parent = (player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack"))
	ToolsFactory.watch(player, tool)
	Notifier.send(player, "Purchased " .. tool.Name .. "!", Color3.fromRGB(140, 255, 140))
	Logger.info(player.Name, "bought", itemId)
	return true
end

function Shop.toggleGui(player)
	local guiRoot = player:FindFirstChildOfClass("PlayerGui")
	if not guiRoot then
		return
	end
	local old = guiRoot:FindFirstChild("ShopGui")
	if old then
		old:Destroy()
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ShopGui"
	gui.ResetOnSpawn = false
	gui.Parent = guiRoot
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 320, 0, 380)
	frame.Position = UDim2.new(0.5, -160, 0.5, -190)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 50)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 24
	title.TextColor3 = Color3.fromRGB(140, 255, 140)
	title.Text = "ITEM SHOP"
	title.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 56)
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.Parent = frame
	for _, item in ipairs(SHOP_ITEMS) do
		local price = CONFIG.Prices[item.Id] or 0
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, 0, 0, 52)
		btn.BackgroundColor3 = Color3.fromRGB(45, 130, 70)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 17
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Text = item.Name .. " - " .. Util.formatCoins(price) .. "c"
		btn.Parent = frame
		local bcorner = Instance.new("UICorner")
		bcorner.CornerRadius = UDim.new(0, 8)
		bcorner.Parent = btn
		local itemId = item.Id
		btn.MouseButton1Click:Connect(function()
			Shop.buy(player, itemId)
		end)
	end
	local close = Instance.new("TextButton")
	close.Size = UDim2.new(1, 0, 0, 40)
	close.BackgroundColor3 = Color3.fromRGB(150, 60, 60)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 16
	close.TextColor3 = Color3.fromRGB(255, 255, 255)
	close.Text = "CLOSE"
	close.Parent = frame
	local ccorner = Instance.new("UICorner")
	ccorner.CornerRadius = UDim.new(0, 8)
	ccorner.Parent = close
	close.MouseButton1Click:Connect(function()
		gui:Destroy()
	end)
end

Game.buyItem = Shop.buy

--------------------------------------------------------------------------------
-- 12. QUESTS
--------------------------------------------------------------------------------
local QuestManager = {}

function QuestManager.value(player, stat)
	if stat == "Wins" then
		local board = player:FindFirstChild("leaderstats")
		local v = board and board:FindFirstChild("Wins")
		if v and v:IsA("IntValue") then
			return v.Value
		end
		return 0
	end
	local hidden = player:FindFirstChild("HiddenStats")
	local v = hidden and hidden:FindFirstChild(stat)
	if v and v:IsA("IntValue") then
		return v.Value
	end
	return 0
end

function QuestManager.check(player)
	local data = DataManager.get(player)
	if not data then
		return
	end
	for _, q in ipairs(CONFIG.Quests) do
		if not data.QuestsDone[q.Id] and QuestManager.value(player, q.Stat) >= q.Goal then
			data.QuestsDone[q.Id] = true
			if q.RewardCoins > 0 then
				StatsManager.addCoins(player, q.RewardCoins, true)
			end
			if q.RewardGems > 0 then
				StatsManager.addGems(player, q.RewardGems)
			end
			StatsManager.addXP(player, 50)
			Notifier.send(player, "Quest complete: " .. q.Name .. "! (+50 XP)",
				Color3.fromRGB(255, 230, 120))
			Logger.info(player.Name, "completed quest", q.Id)
		end
	end
end

Game.onProgress = QuestManager.check

--------------------------------------------------------------------------------
-- 13. WIN HANDLER
--------------------------------------------------------------------------------
do
	local winDeb = {}
	function Game.onWin(player)
		if winDeb[player] and os.clock() - winDeb[player] < 5 then
			return
		end
		winDeb[player] = os.clock()
		local granted = StatsManager.addCoins(player, CONFIG.WinCoins)
		StatsManager.addGems(player, CONFIG.WinGems)
		StatsManager.addWins(player, 1)
		StatsManager.addXP(player, 100)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			WorldBuilder.fireworks(hrp.Position)
		end
		Notifier.broadcast(player.Name .. " BEAT THE OBBY! (+" .. granted .. " coins)",
			Color3.fromRGB(255, 215, 90))
		Notifier.send(player, "You win! Back to start in 5s for another run...")
		task.delay(5, function()
			if player.Parent then
				Game.respawn(player)
			end
		end)
	end
end

function Game.respawn(player)
	local cf = WorldBuilder.StageSpawns[StatsManager.getStage(player)]
		or WorldBuilder.SpawnCF
	Util.teleportTo(player, cf)
end

--------------------------------------------------------------------------------
-- 14. EVENTS -- double coins, day/night, announcements
--------------------------------------------------------------------------------
local Events = {}
Events.DoubleCoins = false

function Game.isDoubleCoins()
	return Events.DoubleCoins
end

function Game.hasDoublePass(player)
	local passId = CONFIG.Gamepasses.DoubleCoins
	if not passId or passId == 0 then
		return false
	end
	return Util.ownsGamePass(player, passId)
end

local TIPS = {
	"Tip: type /shop to buy coils, swords and potions!",
	"Tip: step on the purple pad to REBIRTH once you have 5 wins!",
	"Tip: dummies in the training area give coins when smashed!",
	"Tip: log in daily to grow your streak reward up to 1,000 coins!",
	"Tip: the gold pad at stage 25 pays 500 coins every win!",
	"Tip: chasers in the arena drop 100 coins each!",
}

function Events.start()
	-- Double-coins schedule.
	task.spawn(function()
		while true do
			task.wait(CONFIG.DoubleCoinsEveryMinutes * 60)
			Events.DoubleCoins = true
			Notifier.broadcast("DOUBLE COINS for " .. CONFIG.DoubleCoinsMinutes .. " minutes!",
				Color3.fromRGB(255, 215, 90))
			task.wait(CONFIG.DoubleCoinsMinutes * 60)
			Events.DoubleCoins = false
			Notifier.broadcast("Double coins event ended.")
		end
	end)
	-- Day/night cycle.
	task.spawn(function()
		local fullDay = math.max(60, CONFIG.FullDaySeconds)
		while true do
			task.wait(1)
			Lighting.ClockTime = (Lighting.ClockTime + (24 / fullDay)) % 24
		end
	end)
	-- Rotating announcements.
	task.spawn(function()
		local i = 0
		while true do
			task.wait(CONFIG.AnnounceInterval)
			i = (i % #TIPS) + 1
			Notifier.broadcast(TIPS[i])
		end
	end)
end

--------------------------------------------------------------------------------
-- 15. ADMIN COMMANDS -- chat "/" commands
--------------------------------------------------------------------------------
local Admin = {}

local function findPlayer(fragment)
	if not fragment or fragment == "" then
		return nil
	end
	fragment = string.lower(fragment)
	local best = nil
	for _, p in ipairs(Players:GetPlayers()) do
		local name = string.lower(p.Name)
		if name == fragment then
			return p
		end
		if string.sub(name, 1, #fragment) == fragment and not best then
			best = p
		end
	end
	return best
end

local function targetOrSelf(player, args, n)
	local target = player
	if args[n] then
		target = findPlayer(args[n]) or player
	end
	return target
end

local CMDS = {}

function CMDS.help(player)
	Notifier.send(player, "Commands: /shop /stats /heal /coins /gems /setstage /give /tp /bring /kill /kick /event /day /night /announce")
end

function CMDS.stats(player)
	local board = player:FindFirstChild("leaderstats")
	local hidden = player:FindFirstChild("HiddenStats")
	local function v(folder, name)
		local x = folder and folder:FindFirstChild(name)
		return (x and x:IsA("IntValue") and x.Value) or 0
	end
	Notifier.send(player, "Coins " .. v(board, "Coins") .. " | Gems " .. v(board, "Gems")
		.. " | Wins " .. v(board, "Wins") .. " | Lv " .. v(board, "Level")
		.. " | Stage " .. v(hidden, "Stage") .. "/" .. CONFIG.StageCount)
end

function CMDS.shop(player)
	Shop.toggleGui(player)
end

function CMDS.heal(player)
	local _, humanoid = Util.getHumanoid(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
		Notifier.send(player, "Healed!")
	end
end

function CMDS.coins(player, args)
	local n = math.floor(tonumber(args[2]) or 0)
	local target = targetOrSelf(player, args, 3)
	StatsManager.addCoins(target, n, true)
	Notifier.send(player, "Gave " .. target.Name .. " " .. n .. " coins.")
end

function CMDS.gems(player, args)
	local n = math.floor(tonumber(args[2]) or 0)
	local target = targetOrSelf(player, args, 3)
	StatsManager.addGems(target, n)
	Notifier.send(player, "Gave " .. target.Name .. " " .. n .. " gems.")
end

function CMDS.wins(player, args)
	local n = math.floor(tonumber(args[2]) or 1)
	local target = targetOrSelf(player, args, 3)
	StatsManager.addWins(target, n)
	Notifier.send(player, "Gave " .. target.Name .. " " .. n .. " wins.")
end

function CMDS.level(player, args)
	local n = Util.clamp(math.floor(tonumber(args[2]) or 1), 1, CONFIG.MaxLevel)
	local board = player:FindFirstChild("leaderstats")
	local v = board and board:FindFirstChild("Level")
	if v then
		v.Value = n
	end
	Notifier.send(player, "Level set to " .. n)
end

function CMDS.setstage(player, args)
	local n = Util.clamp(math.floor(tonumber(args[2]) or 1), 1, CONFIG.StageCount)
	StatsManager.setStage(player, n)
	Game.respawn(player)
	Notifier.send(player, "Teleported to stage " .. n)
end

function CMDS.give(player, args)
	local id = args[2]
	local target = targetOrSelf(player, args, 3)
	if id and Shop.buy(target, id) then
		Notifier.send(player, "Gave " .. target.Name .. " " .. id)
	end
end

function CMDS.kill(player, args)
	local target = targetOrSelf(player, args, 2)
	local _, humanoid = Util.getHumanoid(target)
	if humanoid then
		humanoid.Health = 0
	end
end

function CMDS.kick(player, args)
	local target = findPlayer(args[2] or "")
	if target and target ~= player then
		target:Kick("Kicked by an admin.")
	else
		Notifier.send(player, "Player not found.")
	end
end

function CMDS.speed(player, args)
	local n = Util.clamp(tonumber(args[2]) or 16, 0, 200)
	local _, humanoid = Util.getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = n
	end
end

function CMDS.jump(player, args)
	local n = Util.clamp(tonumber(args[2]) or 50, 0, 300)
	local _, humanoid = Util.getHumanoid(player)
	if humanoid then
		humanoid.JumpPower = n
	end
end

function CMDS.tp(player, args)
	local target = findPlayer(args[2] or "")
	local _, humanoid = Util.getHumanoid(player)
	if target and target.Character then
		local hrp = target.Character:FindFirstChild("HumanoidRootPart")
		local myHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and myHrp then
			myHrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)
		end
	else
		Notifier.send(player, "Player not found.")
	end
end

function CMDS.bring(player, args)
	local target = findPlayer(args[2] or "")
	local myHrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if target and target.Character and myHrp then
		local hrp = target.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			hrp.CFrame = myHrp.CFrame + Vector3.new(0, 3, 3)
		end
	else
		Notifier.send(player, "Player not found.")
	end
end

function CMDS.event(player, args)
	if (args[2] or "") == "coins" then
		Events.DoubleCoins = not Events.DoubleCoins
		Notifier.broadcast("Double coins toggled by admin. Active: " .. tostring(Events.DoubleCoins))
	else
		Notifier.send(player, "Usage: /event coins")
	end
end

function CMDS.day(player)
	Lighting.ClockTime = 14
	Notifier.broadcast("Time set to day.")
end

function CMDS.night(player)
	Lighting.ClockTime = 0
	Notifier.broadcast("Time set to night.")
end

function CMDS.announce(player, args, raw)
	local text = string.sub(raw, #"announce" + 3)
	if text == "" then
		text = "Announcement!"
	end
	Notifier.broadcast("[ADMIN] " .. text, Color3.fromRGB(255, 215, 90))
end

function CMDS.shutdown(player)
	Notifier.broadcast("Server shutting down...")
	task.wait(2)
	for _, p in ipairs(Players:GetPlayers()) do
		p:Kick("Server shut down by an admin.")
	end
end

local OPEN_COMMANDS = { shop = true, help = true, stats = true }

function Admin.handle(player, message)
	if string.sub(message, 1, 1) ~= "/" then
		return
	end
	local raw = string.sub(message, 2)
	local args = Util.splitWords(raw)
	if #args == 0 then
		return
	end
	local name = string.lower(args[1])
	local fn = CMDS[name]
	if not fn then
		return
	end
	if not OPEN_COMMANDS[name] and not Util.isAdmin(player) then
		Notifier.send(player, "Admins only.", Color3.fromRGB(255, 140, 140))
		return
	end
	local ok, err = pcall(fn, player, args, raw)
	if not ok then
		Logger.warn("Admin command failed:", name, tostring(err))
	end
end

--------------------------------------------------------------------------------
-- 16. ANTI-EXPLOIT -- speed/jump sanity checks with strikes
--------------------------------------------------------------------------------
local Anti = {}
Anti.strikes = {}

local function equippedCoil(char)
	local tool = char and char:FindFirstChildOfClass("Tool")
	if tool then
		return tool:GetAttribute("Coil")
	end
	return nil
end

function Anti.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc = acc + dt
		if acc < 1 then
			return
		end
		acc = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local char, humanoid = Util.getHumanoid(player)
			if char and humanoid and humanoid.Health > 0 then
				local coil = equippedCoil(char)
				local expectSpeed = 16
				local expectJump = 50
				if coil == "Speed" then
					expectSpeed = CONFIG.SpeedCoilSpeed
				elseif coil == "Gravity" then
					expectJump = CONFIG.GravityCoilJump
				end
				local bad = false
				if humanoid.WalkSpeed > math.max(expectSpeed + 10, CONFIG.MaxWalkSpeed + 10) then
					humanoid.WalkSpeed = expectSpeed
					bad = true
				end
				if humanoid.JumpPower > math.max(expectJump + 10, CONFIG.MaxJumpPower + 10) then
					humanoid.JumpPower = expectJump
					bad = true
				end
				if bad and not Util.isAdmin(player) then
					local id = player.UserId
					Anti.strikes[id] = (Anti.strikes[id] or 0) + 1
					Notifier.send(player, "Warning: unusual stats detected ("
						.. Anti.strikes[id] .. "/" .. CONFIG.MaxStrikes .. ")",
						Color3.fromRGB(255, 140, 140))
					Logger.warn(player.Name, "speed/jump strike", Anti.strikes[id])
					if Anti.strikes[id] >= CONFIG.MaxStrikes then
						player:Kick("Exploiting detected.")
					end
				end
			end
			-- Coins can never go negative.
			local board = player:FindFirstChild("leaderstats")
			local coins = board and board:FindFirstChild("Coins")
			if coins and coins:IsA("IntValue") and coins.Value < 0 then
				coins.Value = 0
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- 17. PLAYER LIFECYCLE
--------------------------------------------------------------------------------
local function onCharacter(player, char)
	local hrp = char:WaitForChild("HumanoidRootPart", 10)
	local humanoid = char:WaitForChildOfClass("Humanoid", 10)
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end
	if hrp then
		local cf = WorldBuilder.StageSpawns[StatsManager.getStage(player)]
			or WorldBuilder.SpawnCF
		hrp.CFrame = cf + Vector3.new(0, 5, 0)
	end
	local shield = Instance.new("ForceField")
	shield.Visible = true
	shield.Parent = char
	Debris:AddItem(shield, 3)
end

local function onPlayerAdded(player)
	local data, daily = DataManager.load(player)
	StatsManager.setup(player, data)

	local backpack = player:WaitForChild("Backpack", 10) or player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack.ChildAdded:Connect(function(child)
			if child:IsA("Tool") then
				ToolsFactory.watch(player, child)
			end
		end)
	end
	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		task.spawn(onCharacter, player, player.Character)
	end
	player.Chatted:Connect(function(message)
		Admin.handle(player, message)
	end)

	task.delay(2, function()
		if not player.Parent then
			return
		end
		Notifier.send(player, "Welcome to " .. CONFIG.GameName .. "!",
			Color3.fromRGB(140, 255, 140))
		Notifier.send(player, "Stage " .. StatsManager.getStage(player) .. "/"
			.. CONFIG.StageCount .. " - type /shop to buy gear!")
		if daily then
			Notifier.send(player, "Daily reward: +" .. daily.reward .. " coins (day "
				.. daily.streak .. " streak)!", Color3.fromRGB(255, 215, 90))
		end
	end)
	Logger.info(player.Name, "joined the game.")
end

local function onPlayerRemoving(player)
	DataManager.save(player)
	DataManager.clear(player)
	Anti.strikes[player.UserId] = nil
	Logger.info(player.Name, "left the game.")
end

--------------------------------------------------------------------------------
-- 18. INIT -- build the world, wire players, start loops
--------------------------------------------------------------------------------
DataManager.init()
WorldBuilder.buildAll()
ToolsFactory.init()

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Win pad wiring (needs Game.onWin, so it happens after all definitions).
do
	local winPad = WorldBuilder.WinPad
	if winPad then
		winPad.Touched:Connect(function(hit)
			local player = playerFromHit(hit)
			if player then
				Game.onWin(player)
			end
		end)
	end
end

WorldBuilder.startLoops()
Events.start()
Anti.start()

-- Autosave.
task.spawn(function()
	while true do
		task.wait(CONFIG.SaveIntervalSeconds)
		DataManager.saveAll()
		Logger.info("Autosaved all player data.")
	end
end)

game:BindToClose(function()
	DataManager.saveAll()
end)

Logger.info(CONFIG.GameName, "v1.0.0 READY - world, shop, quests and events running.")
