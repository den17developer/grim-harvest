-- LocalScript: HUD (валюта снизу слева), модалка магазина по центру,
-- использование стандартного Backpack. Привязка к экипировке Tool.


local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CurrencyChanged = Remotes:WaitForChild("CurrencyChanged")
local TierChanged = Remotes:WaitForChild("TierChanged")
local InventoryChanged = Remotes:WaitForChild("InventoryChanged")
local OpenSeedShop = Remotes:WaitForChild("OpenSeedShop")
local RequestBuySeed = Remotes:WaitForChild("RequestBuySeed")
local SeedToolEquipped = Remotes:WaitForChild("SeedToolEquipped")
local SeedToolUnequipped = Remotes:WaitForChild("SeedToolUnequipped")


local GlobalClock = require(ReplicatedStorage.Shared.GlobalClock)

-- цены (для UI)
local SEED_PRICES = { pea=10, sunflower=15, wallnut=20, pear=25 }

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function mk(parent, class, props)
	local o = Instance.new(class)
	for k,v in pairs(props or {}) do o[k]=v end
	o.Parent = parent
	return o
end

-- ===== HUD (bottom-left) =====
local hud = playerGui:FindFirstChild("HUD") or mk(playerGui, "ScreenGui", {Name="HUD", ResetOnSpawn=false})

local hudFrame = hud:FindFirstChild("HudFrame") or mk(hud, "Frame", {
	Name="HudFrame", AnchorPoint=Vector2.new(0,1), Position=UDim2.new(0, 16, 1, -16),
	Size=UDim2.fromOffset(240, 60), BackgroundTransparency=0.4
})

-- Индикатор экипированного оружия (добавить после создания hudFrame)
local weaponFrame = hud:FindFirstChild("WeaponFrame") or mk(hud, "Frame", {
	Name="WeaponFrame", 
	AnchorPoint=Vector2.new(0,1), 
	Position=UDim2.new(0, 270, 1, -16),
	Size=UDim2.fromOffset(180, 60), 
	BackgroundTransparency=0.4
})

local weaponIcon = weaponFrame:FindFirstChild("WeaponIcon") or mk(weaponFrame, "TextLabel", {
	Name="WeaponIcon", 
	Size=UDim2.fromOffset(44,44), 
	Position=UDim2.new(0,8,0,8),
	Text="🔨", 
	TextScaled=true, 
	BackgroundTransparency=1
})

local weaponName = weaponFrame:FindFirstChild("WeaponName") or mk(weaponFrame, "TextLabel", {
	Name="WeaponName", 
	Size=UDim2.fromOffset(110, 44), 
	Position=UDim2.new(0, 60, 0, 8),
	TextScaled=true, 
	Text="Нет оружия", 
	BackgroundTransparency=1, 
	TextXAlignment=Enum.TextXAlignment.Left
})

-- Обновление индикатора оружия при экипировке
WeaponEquipped.OnClientEvent:Connect(function(weaponType)
	if weaponType == "GoldenShovel" then
		weaponIcon.Text = "⚜️"
		weaponName.Text = "Золотая лопата"
	elseif weaponType == "IronShovel" then
		weaponIcon.Text = "⚔️"
		weaponName.Text = "Железная лопата"
	else
		weaponIcon.Text = "🔨"
		weaponName.Text = "Лопата"
	end
end)		

-- DEV: кнопка сброса (видна только в Studio; убери позже)
local RunService = game:GetService("RunService")
local RequestFullReset = Remotes:WaitForChild("RequestFullReset")

local devReset = hud:FindFirstChild("DevResetBtn") or (function()
	local b = Instance.new("TextButton")
	b.Name = "DevResetBtn"
	b.Size = UDim2.fromOffset(140, 36)
	b.AnchorPoint = Vector2.new(0,1)
	b.Position = UDim2.new(0, 16, 1, -86) -- под HUD
	b.TextScaled = true
	b.Text = "DEV: Reset"
	b.BackgroundTransparency = 0.2
	b.Parent = hud
	return b
end)()

devReset.Visible = RunService:IsStudio()  -- в игре скрыто
devReset.MouseButton1Click:Connect(function()
	RequestFullReset:FireServer()
end)


--Валюта
local leafIcon = hudFrame:FindFirstChild("LeafIcon") or mk(hudFrame, "TextLabel", {
	Name="LeafIcon", Size=UDim2.fromOffset(44,44), Position=UDim2.new(0,8,0,8),
	Text="🍃", TextScaled=true, BackgroundTransparency=1
})

local leafCount = hudFrame:FindFirstChild("LeafCount") or mk(hudFrame, "TextLabel", {
	Name="LeafCount", Size=UDim2.fromOffset(100, 44), Position=UDim2.new(0, 60, 0, 8),
	TextScaled=true, Text="0", BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left
})

-- ==== Индикатор фазы (по центру сверху) ====
local DayNightChanged = Remotes:WaitForChild("DayNightChanged")
local DayTimer = Remotes:WaitForChild("DayTimer")

local phaseUI = playerGui:FindFirstChild("PhaseUI") or mk(playerGui, "ScreenGui", {Name="PhaseUI", ResetOnSpawn=false})
local phaseFrame = phaseUI:FindFirstChild("PhaseFrame") or mk(phaseUI, "Frame", {
	Name="PhaseFrame", AnchorPoint=Vector2.new(0.5,0), Position=UDim2.fromScale(0.5, 0.02),
	Size=UDim2.fromOffset(220, 44), BackgroundTransparency=0.3
})
local phaseIcon = phaseFrame:FindFirstChild("Icon") or mk(phaseFrame, "TextLabel", {
	Name="Icon", Size=UDim2.fromOffset(44,44), Position=UDim2.new(0, 6, 0, 0),
	TextScaled=true, BackgroundTransparency=1, Text="☀"
})
local phaseText = phaseFrame:FindFirstChild("Text") or mk(phaseFrame, "TextLabel", {
	Name="Text", Size=UDim2.fromOffset(160,44), Position=UDim2.new(0, 56, 0, 0),
	TextScaled=true, BackgroundTransparency=1, Text="Day 00:00"
})

local function fmt(sec)
	local m = math.floor(sec/60)
	local s = sec%60
	return string.format("%02d:%02d", m, s)
end

local ph, left = GlobalClock.nowPhase()
currentPhase = ph
timeLeft = left
phaseIcon.Text = (ph == "night") and "🌙" or "☀"
phaseText.Text = ((ph == "night") and "Night " or "Day ") .. fmt(left)

local currentPhase = "day"
local timeLeft = 0

DayNightChanged.OnClientEvent:Connect(function(phase, duration)
	currentPhase = phase
	timeLeft = tonumber(duration) or 0
	phaseIcon.Text = (phase == "night") and "🌙" or "☀"
	phaseText.Text = ((phase == "night") and "Night " or "Day ") .. fmt(timeLeft)
end)

DayTimer.OnClientEvent:Connect(function(phase, t)
	currentPhase = phase or currentPhase
	timeLeft = tonumber(t) or timeLeft
	phaseIcon.Text = (currentPhase == "night") and "🌙" or "☀"
	phaseText.Text = ((currentPhase == "night") and "Night " or "Day ") .. fmt(timeLeft)
end)



-- ==== Boss Event Indicator (top-right) ====
local BossEventChanged = Remotes:WaitForChild("BossEventChanged")

local bossUI = playerGui:FindFirstChild("BossUI") or mk(playerGui, "ScreenGui", {Name="BossUI", ResetOnSpawn=false})
local bossFrame = bossUI:FindFirstChild("BossFrame") or mk(bossUI, "Frame", {
	Name="BossFrame", AnchorPoint=Vector2.new(1,0), Position=UDim2.new(1, -16, 0, 16),
	Size=UDim2.fromOffset(240, 44), BackgroundTransparency=0.3
})
local bossLabel = bossFrame:FindFirstChild("BossLabel") or mk(bossFrame, "TextLabel", {
	Name="BossLabel", Size=UDim2.fromScale(1,1), BackgroundTransparency=1, TextScaled=true,
	Text="Next Boss: ..."
})

local function fmtCountdown(unixTarget: number)
	local now = DateTime.now().UnixTimestamp
	local d = math.max(0, unixTarget - now)
	local days = math.floor(d/86400); d%=86400
	local h = math.floor(d/3600); d%=3600
	local m = math.floor(d/60)
	if days > 0 then
		return string.format("%dd %02dh %02dm", days, h, m)
	else
		return string.format("%02dh %02dm", h, m)
	end
end

-- Обновляем «Next Boss» раз в 5 сек
task.spawn(function()
	while true do
		local nextAt = workspace:GetAttribute("GG_NextBossEventUnix")
		if typeof(nextAt) == "number" then
			local active = workspace:GetAttribute("GG_BossEventActive") == true
			if active then
				bossLabel.Text = "Boss Event: ACTIVE"
			else
				bossLabel.Text = "Next Boss: "..fmtCountdown(nextAt)
			end
		end
		task.wait(5)
	end
end)

BossEventChanged.OnClientEvent:Connect(function(active)
	if active then
		bossLabel.Text = "Boss Event: ACTIVE"
	else
		local nextAt = workspace:GetAttribute("GG_NextBossEventUnix")
		if typeof(nextAt) == "number" then
			bossLabel.Text = "Next Boss: "..fmtCountdown(nextAt)
		else
			bossLabel.Text = "Next Boss: ..."
		end
	end
end)




-- отладочная подпись (Unlocked Tier)
local tierDebug = hudFrame:FindFirstChild("TierDebug") or mk(hudFrame, "TextLabel", {
	Name="TierDebug", Size=UDim2.fromOffset(72, 44), Position=UDim2.new(0, 160, 0, 8),
	TextScaled=true, Text="T:1", BackgroundTransparency=1, TextXAlignment=Enum.TextXAlignment.Left
})

-- ===== Модалка магазина =====
local shopGui = playerGui:FindFirstChild("SeedShopUI") or mk(playerGui, "ScreenGui", {
	Name="SeedShopUI", ResetOnSpawn=false, Enabled=false
})

local modal = shopGui:FindFirstChild("Modal") or mk(shopGui, "Frame", {
	Name="Modal", AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.fromScale(0.5,0.5),
	Size=UDim2.fromOffset(420, 260), BackgroundTransparency=0.2
})

local title = modal:FindFirstChild("Title") or mk(modal, "TextLabel", {
	Name="Title", Size=UDim2.fromOffset(380, 32), Position=UDim2.new(0,20,0,16),
	TextScaled=true, BackgroundTransparency=1, Text="Магазин семян"
})

local closeBtn = modal:FindFirstChild("CloseBtn") or mk(modal, "TextButton", {
	Name="CloseBtn", Size=UDim2.fromOffset(32,32), Position=UDim2.new(1,-44,0,16),
	TextScaled=true, Text="✖"
})

local grid = modal:FindFirstChild("Grid") or mk(modal, "Frame", {
	Name="Grid", Size=UDim2.fromOffset(380, 180), Position=UDim2.new(0,20,0,60), BackgroundTransparency=1
})

local function mkBuy(name, price, x, y, id)
	local btn = grid:FindFirstChild(name) or mk(grid, "TextButton", {
		Name=name, Size=UDim2.fromOffset(180, 48), Position=UDim2.new(0, x, 0, y),
		TextScaled=true, Text = ("%s (%d)"):format(name, price)
	})
	btn.MouseButton1Click:Connect(function()
		RequestBuySeed:FireServer(id, 1)
	end)
end

mkBuy("Горох",     SEED_PRICES.pea,       0,   0,   "pea")
mkBuy("Подсолнух", SEED_PRICES.sunflower, 200, 0,   "sunflower")
mkBuy("Орех",      SEED_PRICES.wallnut,   0,   60,  "wallnut")
mkBuy("Груша",     SEED_PRICES.pear,      200, 60,  "pear")

closeBtn.MouseButton1Click:Connect(function() shopGui.Enabled = false end)
OpenSeedShop.OnClientEvent:Connect(function() shopGui.Enabled = true end)

-- ===== Обновление HUD =====
local leaves, tier = 0, 1

CurrencyChanged.OnClientEvent:Connect(function(b)
	leaves = b.Leaves or 0
	leafCount.Text = tostring(leaves)
end)

TierChanged.OnClientEvent:Connect(function(newTier)
	tier = newTier or tier
	tierDebug.Text = "T:"..tostring(tier)
end)

-- ===== Привязка к экипировке Tools (семена) =====
local function connectTool(tool: Tool)
	local plantId = tool:GetAttribute("PlantId")
	if not plantId then return end

	tool.Equipped:Connect(function()
		SeedToolEquipped:FireServer(plantId)
	end)
	tool.Unequipped:Connect(function()
		SeedToolUnequipped:FireServer()
	end)
end

local function scanContainer(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("PlantId") then
			connectTool(child)
		end
	end
	container.ChildAdded:Connect(function(child)
		task.defer(function()
			if child:IsA("Tool") and child:GetAttribute("PlantId") then
				connectTool(child)
			end
		end)
	end)
end

-- Backpack и Character
local function bindAll()
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then scanContainer(bp) end
	if player.Character then scanContainer(player.Character) end

	player.CharacterAdded:Connect(function(char)
		scanContainer(char)
	end)
end



bindAll()

-- DEV DAMAGE (Studio only): V стреляет из центра экрана
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DevDealDamage = Remotes:WaitForChild("DevDealDamage")

if RunService:IsStudio() then
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == Enum.KeyCode.V then
			local cam = workspace.CurrentCamera
			if not cam then return end
			local vp = cam.ViewportSize
			-- Луч из центра экрана, работает и в 1-м, и в 3-м лице
			local ray = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
			DevDealDamage:FireServer(ray.Origin, ray.Direction * 200)
		end
	end)
end
	