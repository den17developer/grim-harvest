-- PlayerPlotService.lua
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

Players.CharacterAutoLoads = false

-- Remotes
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

-- Функция для гарантированного создания Remote
local function ensureRemote(name: string, className: string): Instance
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end

-- Создаём все необходимые Remotes
local RequestFullReset = ensureRemote("RequestFullReset", "RemoteEvent")
local RequestPlant = ensureRemote("RequestPlant", "RemoteEvent")
local CurrencyChanged = ensureRemote("CurrencyChanged", "RemoteEvent")
local TierChanged = ensureRemote("TierChanged", "RemoteEvent")
local RequestBuySeed = ensureRemote("RequestBuySeed", "RemoteEvent")
local InventoryChanged = ensureRemote("InventoryChanged", "RemoteEvent")
local OpenSeedShop = ensureRemote("OpenSeedShop", "RemoteEvent")
local SeedToolEquipped = ensureRemote("SeedToolEquipped", "RemoteEvent")
local SeedToolUnequipped = ensureRemote("SeedToolUnequipped", "RemoteEvent")

-- Modules
local Persistence = require(script.Parent.Persistence)
local PlantRuntime = require(script.Parent.PlantRuntime)
local CurrencyService = require(script.Parent.CurrencyService)
local InventoryService = require(script.Parent.InventoryService)
local PlantCatalog = require(ReplicatedStorage.Shared.PlantCatalog)

-- Data
local PlotTemplate = ServerStorage:WaitForChild("PlotTemplate")
local GardenPlots = workspace:WaitForChild("GardenPlots")
local Anchors = workspace:WaitForChild("PlotAnchors")

local PlayerToPlot : {[Player]: Model} = {}
local AnchorToPlayer : {[BasePart]: Player} = {}

-- Защита от спама
local resetCooldown = {}

-- Настройки цен
local BED_PRICES = { [2]=100, [3]=250, [4]=500 }
local SEED_PRICES = { pea=10, sunflower=15, wallnut=20, pear=25 }

-- Русские названия для Tool
local DISPLAY = {}
for id,cfg in pairs(PlantCatalog) do DISPLAY[id] = cfg.displayName or id end

-- == УТИЛИТЫ ==

local function getFreeAnchor(): BasePart?
	for _, a in ipairs(Anchors:GetChildren()) do
		if a:IsA("BasePart") and not a:GetAttribute("Occupied") then
			return a
		end
	end
	return nil
end

local function getPlot(player: Player): Model?
	return PlayerToPlot[player]
end

-- Обновить/создать Tool для семян в Backpack/Character
local function ensureSeedToolFor(player: Player, plantId: string, count: number)
	local char = player.Character
	local bp = player:FindFirstChildOfClass("Backpack")
	if not bp then return end

	local function findTool(container)
		for _, tool in ipairs(container:GetChildren()) do
			if tool:IsA("Tool") and tool:GetAttribute("PlantId") == plantId then
				return tool
			end
		end
	end

	local tool = (char and findTool(char)) or findTool(bp)

	if count <= 0 then
		if tool then tool:Destroy() end
		return
	end

	if not tool then
		tool = Instance.new("Tool")
		tool.RequiresHandle = true
		tool.CanBeDropped = false
		tool.Name = "Семя: "..DISPLAY[plantId]
		tool:SetAttribute("PlantId", plantId)

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.6,0.6,0.6)
		handle.Color = Color3.fromRGB(170, 255, 170)
		handle.Material = Enum.Material.SmoothPlastic
		handle.CanCollide = false
		handle.Parent = tool

		local countVal = Instance.new("IntValue")
		countVal.Name = "Count"
		countVal.Value = count
		countVal.Parent = tool

		tool.Parent = bp
	else
		local countVal = tool:FindFirstChild("Count")
		if not countVal then
			countVal = Instance.new("IntValue")
			countVal.Name = "Count"
			countVal.Parent = tool
		end
		countVal.Value = count
	end

	tool.Name = ("Семя: %s x%d"):format(DISPLAY[plantId], count)
end

-- Синхронизировать ВСЕ seed tools с InventoryService
local function refreshAllSeedTools(player: Player)
	local inv = InventoryService.GetSeeds(player) or {}
	for plantId, _ in pairs(PlantCatalog) do
		local cnt = inv[plantId] or 0
		ensureSeedToolFor(player, plantId, cnt)
	end
end

local function purgeSeedTools(player: Player)
	local function purge(container: Instance)
		for _, ch in ipairs(container:GetChildren()) do
			if ch:IsA("Tool") and ch:GetAttribute("PlantId") then
				ch:Destroy()
			end
		end
	end
	local bp = player:FindFirstChildOfClass("Backpack")
	if bp then purge(bp) end
	if player.Character then purge(player.Character) end
end

-- Найти первый BasePart в BedModel (куда вешать промпт покупки)
local function findBedAnchorPart(bed: Instance): BasePart?
	local mesh = bed:FindFirstChild("BedModel")
	if mesh and mesh:IsA("Folder") then
		for _, child in ipairs(mesh:GetChildren()) do
			if child:IsA("BasePart") then return child end
		end
	end
	-- fallback: любой BasePart в модели
	for _, child in ipairs(bed:GetChildren()) do
		if child:IsA("BasePart") then return child end
	end
	return nil
end

-- Удалить все "BuyPrompt" у всех грядок
local function clearAllBuyPrompts(plot: Model)
	local grid = plot:FindFirstChild("GridSlots")
	if not grid then return end
	for _, bed in ipairs(grid:GetChildren()) do
		if bed:IsA("Model") then
			for _, desc in ipairs(bed:GetDescendants()) do
				if desc:IsA("ProximityPrompt") and desc.Name == "BuyPrompt" then
					desc:Destroy()
				end
			end
		end
	end
end

-- Создать "BuyPrompt" на ближайшей к покупке грядке (tier = current+1)
local function setupBuyPromptForNext(plot: Model, player: Player, unlockedTier: number)
	clearAllBuyPrompts(plot)
	local nextTier = unlockedTier + 1
	local price = BED_PRICES[nextTier]
	if not price then return end

	local grid = plot:FindFirstChild("GridSlots")
	if not grid then return end
	for _, bed in ipairs(grid:GetChildren()) do
		if bed:IsA("Model") and (bed:GetAttribute("UnlockTier") == nextTier) then
			-- показываем промпт только если эта грядка в состоянии "purchasable"
			if bed:GetAttribute("Purchasable") == true then
				local anchor = findBedAnchorPart(bed) or plot.PrimaryPart
				if anchor then
					local prompt = Instance.new("ProximityPrompt")
					prompt.Name = "BuyPrompt"
					prompt.ObjectText = ("Грядка #%d"):format(nextTier)
					prompt.ActionText = ("Купить за %d").format and ("Купить за %d"):format(price) or ("Buy "..price)
					prompt.HoldDuration = 1.2
					prompt.MaxActivationDistance = 10
					prompt.RequiresLineOfSight = false
					prompt.Parent = anchor

					prompt.Triggered:Connect(function(triggerPlayer)
						if triggerPlayer ~= player then return end
						-- пытаемся купить следующую грядку
						local current = PlantRuntime.CollectState(plot)
						local currentTierNow = current.UnlockedTier or 1
						if currentTierNow+1 ~= nextTier then return end -- уже не актуально
						local priceNow = BED_PRICES[nextTier]
						if not priceNow then return end

						if not CurrencyService.TrySpendLeaves(player, priceNow) then
							return
						end

						local save = Persistence.Load(player) or Persistence.Default()
						save.UnlockedTier = nextTier
						save.Currency = CurrencyService.Export(player)
						save.Inventory = InventoryService.Export(player)
						Persistence.Save(player, save)

						PlantRuntime.ApplySave(plot, save)
						TierChanged:FireClient(player, nextTier)

						-- переставим промпт на следующую грядку
						setupBuyPromptForNext(plot, player, nextTier)
					end)
				end
			end
		end
	end
end

-- Промпты посадки при экипированном семени
local PlantPromptsByPlayer : {[Player]: { [ProximityPrompt]: boolean }} = {}

local function clearPlantPrompts(player: Player)
	local t = PlantPromptsByPlayer[player]
	if not t then return end
	for prompt,_ in pairs(t) do
		if prompt and prompt.Parent then prompt:Destroy() end
	end
	PlantPromptsByPlayer[player] = nil
end

local function createPlantPromptsFor(player: Player, plantId: string)
	clearPlantPrompts(player)

	local plot = getPlot(player)
	if not plot then return end

	local grid = plot:FindFirstChild("GridSlots")
	if not grid then return end

	PlantPromptsByPlayer[player] = {}

	-- Соберём занятые слоты (по уже стоящим растениям)
	local occupied = {}
	for _, obj in ipairs(plot:GetChildren()) do
		if obj:IsA("BasePart") and obj.Name:find("^Plant_") then
			local sid = obj:GetAttribute("SlotId")
			if sid then occupied[sid] = true end
		end
	end

	for _, bed in ipairs(grid:GetChildren()) do
		if bed:IsA("Model") and (bed:GetAttribute("Unlocked") == true) then
			local slots = bed:FindFirstChild("Slots")
			if slots then
				for _, s in ipairs(slots:GetChildren()) do
					if s:IsA("BasePart") then
						local sid = s:GetAttribute("SlotId")
						if sid and not occupied[sid] then
							local p = Instance.new("ProximityPrompt")
							p.Name = "PlantPrompt"
							p.ObjectText = "Лунка"
							p.ActionText = ("Посадить %s"):format(DISPLAY[plantId] or plantId)
							p.HoldDuration = 2.0
							p.MaxActivationDistance = 8
							p.RequiresLineOfSight = false
							p.Parent = s

							PlantPromptsByPlayer[player][p] = true

							p.Triggered:Connect(function(triggerPlayer)
								if triggerPlayer ~= player then return end

								-- сервер проверит наличие семени и посадит
								if not InventoryService.TryConsumeSeed(player, plantId) then
									return
								end

								PlantRuntime.SpawnPlantAtSlotId(plot, sid, {
									PlantId = plantId, Level = 1, Rarity = "common"
								})

								-- обновим сейв и инструменты
								local partial = PlantRuntime.CollectState(plot)
								local save = Persistence.Load(player) or Persistence.Default()
								save.UnlockedTier = partial.UnlockedTier or save.UnlockedTier
								save.Plants = partial.Plants or save.Plants
								save.DayCount = partial.DayCount or save.DayCount
								save.Currency = CurrencyService.Export(player)
								save.Inventory = InventoryService.Export(player)
								Persistence.Save(player, save)

								refreshAllSeedTools(player)

								-- слот стал занятым → удаляем его промпт
								if p and p.Parent then p:Destroy() end
								PlantPromptsByPlayer[player][p] = nil
							end)
						end
					end
				end
			end
		end
	end
end

-- == РАЗВЁРТЫВАНИЕ УЧАСТКА ==

local function deployPlot(player: Player, saveData: table)
	-- Защита от дублирования
	if PlayerToPlot[player] then
		warn("Plot already exists for", player.Name)
		return
	end

	local anchor = getFreeAnchor()
	if not anchor then
		warn("Нет свободных якорей для", player.Name)
		return
	end
	anchor:SetAttribute("Occupied", true)
	AnchorToPlayer[anchor] = player

	local plot = PlotTemplate:Clone()
	plot.Name = "Plot_"..player.UserId
	plot:SetAttribute("OwnerUserId", player.UserId)
	plot.Parent = GardenPlots

	if not plot.PrimaryPart then
		local root = plot:FindFirstChild("Root")
		if root and root:IsA("BasePart") then plot.PrimaryPart = root end
	end
	if plot.PrimaryPart then
		plot:PivotTo(anchor.CFrame)
	end

	PlantRuntime.ApplySave(plot, saveData)
	PlayerToPlot[player] = plot	

	local phase = workspace:GetAttribute("GG_Phase")
	if phase == "night" then
		plot:SetAttribute("NightActive", true)
	else
		plot:SetAttribute("NightActive", false)
	end

	-- Респавн на участке
	local plotSpawn = plot:FindFirstChild("PlotSpawn")
	if plotSpawn and plotSpawn:IsA("SpawnLocation") then
		player.RespawnLocation = plotSpawn
	end

	-- Промпт покупки следующей грядки (рядом на самой грядке)
	setupBuyPromptForNext(plot, player, saveData.UnlockedTier or 1)

	-- Текущий tier → клиенту (для дебага)
	TierChanged:FireClient(player, saveData.UnlockedTier or 1)
end

local function cleanup(player: Player)
	clearPlantPrompts(player)
	local plot = PlayerToPlot[player]
	if plot then plot:Destroy() end
	for a,pl in pairs(AnchorToPlayer) do
		if pl == player then a:SetAttribute("Occupied", nil); AnchorToPlayer[a]=nil end
	end
	PlayerToPlot[player] = nil
end

-- == ОБРАБОТЧИКИ ==

-- Покупка семян из магазина (через Remote от клиенты)
RequestBuySeed.OnServerEvent:Connect(function(player: Player, plantId: string, amount: number?)
	local plot = getPlot(player); if not plot then return end
	if typeof(plantId) ~= "string" then return end
	if not PlantCatalog[plantId] then return end -- Добавлена проверка

	amount = (typeof(amount) == "number" and amount or 1)
	amount = math.clamp(amount, 1, 99)

	local unit = SEED_PRICES[plantId]
	if not unit then return end
	local total = unit * amount
	if not CurrencyService.TrySpendLeaves(player, total) then return end

	InventoryService.AddSeed(player, plantId, amount)
	-- синхронизируем Tool в Backpack
	local seeds = InventoryService.GetSeeds(player) or {}
	local cnt = seeds[plantId] or 0
	ensureSeedToolFor(player, plantId, cnt)

	-- сейв
	local save = Persistence.Load(player) or Persistence.Default()
	save.Currency = CurrencyService.Export(player)
	save.Inventory = InventoryService.Export(player)
	Persistence.Save(player, save)
end)

-- Экипировка семени → создаём промпты посадки на свободных слотах
SeedToolEquipped.OnServerEvent:Connect(function(player: Player, plantId: string)
	if typeof(plantId) ~= "string" then return end
	if not PlantCatalog[plantId] then return end -- Добавлена проверка
	createPlantPromptsFor(player, plantId)
end)

SeedToolUnequipped.OnServerEvent:Connect(function(player: Player)
	clearPlantPrompts(player)
end)

-- Запрос ресета с защитой от спама
RequestFullReset.OnServerEvent:Connect(function(player: Player)
	-- Антиспам защита
	local now = tick()
	if resetCooldown[player] and now - resetCooldown[player] < 5 then
		return -- cooldown 5 секунд
	end
	resetCooldown[player] = now

	-- 1) сформировать дефолтный сейв (уже со 1000 Leaves по Schemas)
	local fresh = Persistence.Default()

	-- 2) Сохранить «чистый» сейв в DS/мок (перезаписываем старый прогресс)
	Persistence.Save(player, fresh)

	-- 3) Удалить подсказки посадки, участок и освободить якорь, очистить сервисы
	clearPlantPrompts(player)
	cleanup(player)
	purgeSeedTools(player)

	-- 4) Инициализировать валюту/инвентарь из «чистого» сейва
	CurrencyService.Init(player, fresh.Currency)
	InventoryService.Init(player, fresh.Inventory)
	refreshAllSeedTools(player)

	-- 5) Развернуть участок заново и заспавнить персонажа
	deployPlot(player, fresh)
	player:LoadCharacter()
end)

-- Жизненный цикл игрока
Players.PlayerAdded:Connect(function(player)
	local save = Persistence.Load(player)
	if not save then save = Persistence.Default() end

	-- Валюта/Инвентарь
	CurrencyService.Init(player, save.Currency)
	InventoryService.Init(player, save.Inventory)

	-- Создаём Tool'ы согласно инвентарю
	refreshAllSeedTools(player)

	-- Дублируем синхронизацию после появления персонажа — чтобы Tools точно оказались в Backpack
	player.CharacterAdded:Connect(function()
		task.delay(0.2, function()
			refreshAllSeedTools(player)
		end)
	end)

	-- Разворачиваем участок
	deployPlot(player, save)

	-- Спавним персонажа
	player:LoadCharacter()
end)

Players.PlayerRemoving:Connect(function(player)
	local plot = getPlot(player)
	if plot then
		local partial = PlantRuntime.CollectState(plot)
		local save = Persistence.Load(player) or Persistence.Default()
		save.UnlockedTier = partial.UnlockedTier or save.UnlockedTier
		save.Plants = partial.Plants or save.Plants
		save.DayCount = partial.DayCount or save.DayCount
		save.Currency = CurrencyService.Export(player)
		save.Inventory = InventoryService.Export(player)
		Persistence.Save(player, save)
	end
	cleanup(player)
	resetCooldown[player] = nil -- Очистка cooldown
end)

game:BindToClose(function()
	for player, plot in pairs(PlayerToPlot) do
		local partial = PlantRuntime.CollectState(plot)
		local save = Persistence.Load(player) or Persistence.Default()
		save.UnlockedTier = partial.UnlockedTier or save.UnlockedTier
		save.Plants = partial.Plants or save.Plants
		save.DayCount = partial.DayCount or save.DayCount
		save.Currency = CurrencyService.Export(player)
		save.Inventory = InventoryService.Export(player)
		Persistence.Save(player, save)
	end
end)