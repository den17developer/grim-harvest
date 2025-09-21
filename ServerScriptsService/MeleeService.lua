-- MeleeService.lua
-- Серверная логика ближнего боя: создание оружия, валидация ударов, урон по зомби

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

-- Создаем Remote Events
local MeleeAttack = Remotes:FindFirstChild("MeleeAttack") or Instance.new("RemoteEvent", Remotes)
MeleeAttack.Name = "MeleeAttack"

local WeaponEquipped = Remotes:FindFirstChild("WeaponEquipped") or Instance.new("RemoteEvent", Remotes)
WeaponEquipped.Name = "WeaponEquipped"

local RequestBuyWeapon = Remotes:FindFirstChild("RequestBuyWeapon") or Instance.new("RemoteEvent", Remotes)
RequestBuyWeapon.Name = "RequestBuyWeapon"

-- Конфигурация оружия
local WEAPONS_CONFIG = {
	BasicShovel = {
		DisplayName = "Лопата",
		Damage = 15,
		Range = 8,
		Cooldown = 0.5,
		HandleColor = Color3.fromRGB(139, 69, 19),
		BladeColor = Color3.fromRGB(120, 120, 120),
		Icon = "🔨"
	},
	IronShovel = {
		DisplayName = "Железная лопата",
		Damage = 25,
		Range = 10,
		Cooldown = 0.4,
		HandleColor = Color3.fromRGB(100, 50, 20),
		BladeColor = Color3.fromRGB(180, 180, 180),
		Icon = "⚔️",
		Price = 500 -- покупается за листочки
	},
	GoldenShovel = {
		DisplayName = "Золотая лопата",
		Damage = 40,
		Range = 12,
		Cooldown = 0.3,
		HandleColor = Color3.fromRGB(255, 215, 0),
		BladeColor = Color3.fromRGB(255, 223, 0),
		Icon = "⚜️",
		Price = 2000
	}
}

-- Хранение кулдаунов и текущего оружия игроков
local playerCooldowns = {}
local playerWeapons = {}

-- Создание модели лопаты
local function createShovelTool(weaponType: string): Tool
	local config = WEAPONS_CONFIG[weaponType]
	if not config then return end

	local tool = Instance.new("Tool")
	tool.Name = config.DisplayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("WeaponType", weaponType)
	tool:SetAttribute("Damage", config.Damage)
	tool:SetAttribute("Range", config.Range)

	-- Создаем ручку (Handle)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 3, 0.3)
	handle.Color = config.HandleColor
	handle.Material = Enum.Material.Wood
	handle.CanCollide = false
	handle.Parent = tool

	-- Создаем лезвие лопаты
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(1.2, 1.5, 0.1)
	blade.Color = config.BladeColor
	blade.Material = Enum.Material.Metal
	blade.CanCollide = false
	blade.Parent = tool

	-- Сварка лезвия к ручке
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = blade
	weld.Parent = handle

	-- Позиционирование лезвия
	blade.CFrame = handle.CFrame * CFrame.new(0, 2, 0)

	-- Звук удара
	local hitSound = Instance.new("Sound")
	hitSound.Name = "HitSound"
	hitSound.SoundId = "rbxasset://sounds/metal.mp3"
	hitSound.Volume = 0.5
	hitSound.Parent = handle

	return tool
end

-- Выдача оружия игроку
local function giveWeapon(player: Player, weaponType: string)
	-- Удаляем старое оружие
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	for _, child in ipairs(backpack:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("WeaponType") then
			child:Destroy()
		end
	end

	if player.Character then
		for _, child in ipairs(player.Character:GetChildren()) do
			if child:IsA("Tool") and child:GetAttribute("WeaponType") then
				child:Destroy()
			end
		end
	end

	-- Создаем новое оружие
	local tool = createShovelTool(weaponType)
	if tool then
		tool.Parent = backpack
		playerWeapons[player] = weaponType

		-- Уведомляем клиента
		WeaponEquipped:FireClient(player, weaponType)

		-- Привязываем события экипировки
		tool.Equipped:Connect(function()
			WeaponEquipped:FireClient(player, weaponType)
		end)

		tool.Unequipped:Connect(function()
			WeaponEquipped:FireClient(player, nil)
		end)
	end
end

-- Проверка и нанесение урона
local function validateAndDealDamage(player: Player, targetPosition: Vector3)
	-- Проверка кулдауна
	local now = tick()
	local lastAttack = playerCooldowns[player] or 0
	local weaponType = playerWeapons[player] or "BasicShovel"
	local config = WEAPONS_CONFIG[weaponType]

	if now - lastAttack < config.Cooldown then
		return -- еще на кулдауне
	end

	-- Проверка дистанции от игрока
	local character = player.Character
	if not character then return end

	local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then return end

	local distance = (targetPosition - humanoidRoot.Position).Magnitude
	if distance > config.Range then
		return -- слишком далеко
	end

	playerCooldowns[player] = now

	-- Находим всех зомби в радиусе удара
	local zombiesFolder = workspace:FindFirstChild("Zombies")
	if not zombiesFolder then return end

	local hitRadius = 3 -- радиус поражения вокруг точки удара
	local hitCount = 0
	local maxHits = 3 -- максимум целей за удар

	for _, zombie in ipairs(zombiesFolder:GetChildren()) do
		if hitCount >= maxHits then break end

		if zombie:IsA("Model") then
			local zombieRoot = zombie:FindFirstChild("HumanoidRootPart")
			local humanoid = zombie:FindFirstChildOfClass("Humanoid")

			if zombieRoot and humanoid and humanoid.Health > 0 then
				local dist = (targetPosition - zombieRoot.Position).Magnitude
				if dist <= hitRadius then
					-- Наносим урон
					humanoid:TakeDamage(config.Damage)
					hitCount = hitCount + 1

					-- Визуальный эффект удара
					local hitEffect = Instance.new("Part")
					hitEffect.Name = "HitEffect"
					hitEffect.Size = Vector3.new(0.5, 0.5, 0.5)
					hitEffect.Shape = Enum.PartType.Ball
					hitEffect.Material = Enum.Material.Neon
					hitEffect.Color = Color3.fromRGB(255, 100, 100)
					hitEffect.Anchored = true
					hitEffect.CanCollide = false
					hitEffect.CFrame = zombieRoot.CFrame
					hitEffect.Parent = workspace

					-- Анимация исчезновения
					local tween = game:GetService("TweenService"):Create(
						hitEffect,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Size = Vector3.new(2, 2, 2), Transparency = 1}
					)
					tween:Play()

					Debris:AddItem(hitEffect, 0.5)

					-- Звук удара (если есть Tool в руках)
					if character then
						local tool = character:FindFirstChildOfClass("Tool")
						if tool then
							local sound = tool:FindFirstChild("HitSound", true)
							if sound then
								sound:Play()
							end
						end
					end
				end
			end
		end
	end
end

-- Обработка атаки от клиента
MeleeAttack.OnServerEvent:Connect(function(player, targetPosition)
	-- Валидация входных данных
	if typeof(targetPosition) ~= "Vector3" then return end

	-- Проверка, что позиция в разумных пределах
	local character = player.Character
	if not character then return end

	local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then return end

	local distance = (targetPosition - humanoidRoot.Position).Magnitude
	if distance > 50 then return end -- защита от читов

	validateAndDealDamage(player, targetPosition)
end)

-- Инициализация при входе игрока (ИСПРАВЛЕНО)
Players.PlayerAdded:Connect(function(player)
	-- НЕ подключаем CharacterAdded здесь, чтобы избежать дублирования
end)

-- Очистка при выходе
Players.PlayerRemoving:Connect(function(player)
	playerCooldowns[player] = nil
	playerWeapons[player] = nil
end)

-- API для покупки улучшенного оружия (вызывается из магазина)
local M = {}

function M.PurchaseWeapon(player: Player, weaponType: string): boolean
	local config = WEAPONS_CONFIG[weaponType]
	if not config or not config.Price then return false end

	local CurrencyService = require(script.Parent.CurrencyService)

	-- Проверяем, хватает ли валюты
	if CurrencyService.TrySpendLeaves(player, config.Price) then
		giveWeapon(player, weaponType)

		-- Сохраняем покупку
		local Persistence = require(script.Parent.Persistence)
		local save = Persistence.Load(player) or Persistence.Default()
		save.PurchasedWeapon = weaponType
		save.Currency = CurrencyService.Export(player)
		Persistence.Save(player, save)

		return true
	end

	return false
end

-- Восстановление купленного оружия при входе (ИСПРАВЛЕНО)
local function restorePurchasedWeapon(player: Player)
	local Persistence = require(script.Parent.Persistence)

	player.CharacterAdded:Connect(function()
		task.wait(0.5) -- ждем загрузки персонажа

		local save = Persistence.Load(player)
		if save and save.PurchasedWeapon then
			-- Восстанавливаем купленное оружие
			giveWeapon(player, save.PurchasedWeapon)
		else
			-- Даем базовую лопату только если нет сохраненного оружия
			giveWeapon(player, "BasicShovel")
		end

		-- ВАЖНО: сбрасываем состояние экипировки на клиенте
		WeaponEquipped:FireClient(player, nil)
	end)
end

Players.PlayerAdded:Connect(restorePurchasedWeapon)

-- Обработка покупки оружия
RequestBuyWeapon.OnServerEvent:Connect(function(player, weaponType)
	if typeof(weaponType) ~= "string" then return end
	if not WEAPONS_CONFIG[weaponType] then return end

	M.PurchaseWeapon(player, weaponType)
end)

return M