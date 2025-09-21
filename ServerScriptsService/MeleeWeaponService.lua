-- MeleeWeaponService.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Remotes
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local MeleeAttack = Remotes:FindFirstChild("MeleeAttack") or Instance.new("RemoteEvent", Remotes)
MeleeAttack.Name = "MeleeAttack"

local WeaponEquipped = Remotes:FindFirstChild("WeaponEquipped") or Instance.new("RemoteEvent", Remotes)
WeaponEquipped.Name = "WeaponEquipped"

-- Конфигурация оружия
local WEAPONS = {
	Shovel = {
		DisplayName = "Лопата",
		Damage = 25,
		Range = 8,
		Cooldown = 0.5,
		SwingTime = 0.3,
		HitboxSize = Vector3.new(4, 4, 6),
		Description = "Стартовая лопата фермера",
		Rarity = "common"
	},
	IronShovel = {
		DisplayName = "Железная лопата", 
		Damage = 40,
		Range = 9,
		Cooldown = 0.45,
		SwingTime = 0.25,
		HitboxSize = Vector3.new(4, 4, 7),
		Description = "Улучшенная железная лопата",
		Rarity = "rare"
	},
	GoldenShovel = {
		DisplayName = "Золотая лопата",
		Damage = 60,
		Range = 10,
		Cooldown = 0.4,
		SwingTime = 0.2,
		HitboxSize = Vector3.new(5, 5, 8),
		Description = "Редкая золотая лопата",
		Rarity = "epic"
	}
}

-- Таблицы для отслеживания кулдаунов и экипированного оружия
local cooldowns = {}
local equippedWeapons = {}

-- Создание модели лопаты
local function createShovelModel(weaponType: string): Tool
	local config = WEAPONS[weaponType] or WEAPONS.Shovel

	local tool = Instance.new("Tool")
	tool.Name = config.DisplayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = config.Description
	tool:SetAttribute("WeaponType", weaponType)
	tool:SetAttribute("Damage", config.Damage)
	tool:SetAttribute("Range", config.Range)
	tool:SetAttribute("Cooldown", config.Cooldown)
	tool:SetAttribute("Rarity", config.Rarity)

	-- Ручка (невидимая для соединения с рукой)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 1.5, 0.3)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Parent = tool

	-- Визуальная часть лопаты
	local shaft = Instance.new("Part")
	shaft.Name = "Shaft"
	shaft.Size = Vector3.new(0.3, 3, 0.3)
	shaft.BrickColor = BrickColor.new("Brown")
	shaft.Material = Enum.Material.Wood
	shaft.CanCollide = false
	shaft.Parent = tool

	local shaftWeld = Instance.new("WeldConstraint")
	shaftWeld.Part0 = handle
	shaftWeld.Part1 = shaft
	shaftWeld.Parent = handle
	shaft.CFrame = handle.CFrame * CFrame.new(0, -0.75, 0)

	-- Лезвие лопаты
	local blade = Instance.new("Part")
	blade.Name = "Blade"
	blade.Size = Vector3.new(1, 0.1, 1.2)
	blade.CanCollide = false
	blade.Parent = tool

	-- Цвет в зависимости от редкости
	if weaponType == "IronShovel" then
		blade.BrickColor = BrickColor.new("Dark grey")
		blade.Material = Enum.Material.Metal
	elseif weaponType == "GoldenShovel" then
		blade.BrickColor = BrickColor.new("Gold")
		blade.Material = Enum.Material.Neon

		-- Эффект свечения для золотой лопаты
		local pointLight = Instance.new("PointLight")
		pointLight.Brightness = 2
		pointLight.Color = Color3.fromRGB(255, 215, 0)
		pointLight.Range = 10
		pointLight.Parent = blade
	else
		blade.BrickColor = BrickColor.new("Dark stone grey")
		blade.Material = Enum.Material.Metal
	end

	local bladeWeld = Instance.new("WeldConstraint")
	bladeWeld.Part0 = shaft
	bladeWeld.Part1 = blade
	bladeWeld.Parent = shaft
	blade.CFrame = shaft.CFrame * CFrame.new(0, -1.5, 0) * CFrame.Angles(math.rad(15), 0, 0)

	return tool
end

-- Выдача стартовой лопаты
local function giveStarterWeapon(player: Player)
	local character = player.Character
	if not character then return end

	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then return end

	-- Проверяем, есть ли уже оружие
	local existingWeapon = backpack:FindFirstChild("Лопата") or 
		(character and character:FindFirstChild("Лопата"))

	if existingWeapon then return end

	-- Создаём и выдаём лопату
	local shovel = createShovelModel("Shovel")
	shovel.Parent = backpack

	-- Уведомляем клиента
	WeaponEquipped:FireClient(player, "Shovel")
end

-- Валидация атаки
local function validateAttack(player: Player, targetPosition: Vector3): boolean
	local character = player.Character
	if not character then return false end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end

	-- Проверка кулдауна
	local now = tick()
	if cooldowns[player] and now - cooldowns[player] < 0.3 then
		return false
	end

	-- Проверка дистанции (защита от читов)
	local distance = (targetPosition - rootPart.Position).Magnitude
	if distance > 20 then -- максимальная разумная дистанция
		return false
	end

	return true
end

-- Обработка атаки
local function processAttack(player: Player, hitData: {Model: Model?, Position: Vector3})
	if not validateAttack(player, hitData.Position) then return end

	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then return end

	local weaponType = tool:GetAttribute("WeaponType") or "Shovel"
	local config = WEAPONS[weaponType] or WEAPONS.Shovel

	-- Устанавливаем кулдаун
	cooldowns[player] = tick()

	-- Визуальный эффект удара (партиклы)
	local hitEffect = Instance.new("Part")
	hitEffect.Name = "HitEffect"
	hitEffect.Size = Vector3.new(0.5, 0.5, 0.5)
	hitEffect.Transparency = 1
	hitEffect.CanCollide = false
	hitEffect.Anchored = true
	hitEffect.Position = hitData.Position
	hitEffect.Parent = workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = hitEffect

	local particleEmitter = Instance.new("ParticleEmitter")
	particleEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particleEmitter.Lifetime = NumberRange.new(0.3, 0.5)
	particleEmitter.Rate = 50
	particleEmitter.Speed = NumberRange.new(5)
	particleEmitter.SpreadAngle = Vector2.new(45, 45)
	particleEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 200))
	particleEmitter.Parent = attachment

	task.wait(0.1)
	particleEmitter.Enabled = false
	Debris:AddItem(hitEffect, 2)

	-- Проверяем попадание по зомби в области
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local zombiesFolder = workspace:FindFirstChild("Zombies")
	if not zombiesFolder then return end

	-- Ищем зомби в радиусе удара
	for _, zombie in ipairs(zombiesFolder:GetChildren()) do
		if zombie:IsA("Model") then
			local zombieRoot = zombie:FindFirstChild("HumanoidRootPart") or zombie:FindFirstChild("Torso")
			if zombieRoot then
				local distance = (zombieRoot.Position - hitData.Position).Magnitude

				-- Проверяем попадание
				if distance <= config.Range then
					local zombieHum = zombie:FindFirstChildOfClass("Humanoid")
					if zombieHum and zombieHum.Health > 0 then
						-- Наносим урон
						zombieHum:TakeDamage(config.Damage)

						-- Эффект отталкивания
						local bodyVelocity = Instance.new("BodyVelocity")
						bodyVelocity.MaxForce = Vector3.new(4000, 0, 4000)
						bodyVelocity.Velocity = (zombieRoot.Position - rootPart.Position).Unit * 20
						bodyVelocity.Parent = zombieRoot
						Debris:AddItem(bodyVelocity, 0.2)

						-- Визуальный эффект попадания
						local hitMarker = Instance.new("BillboardGui")
						hitMarker.Size = UDim2.new(2, 0, 2, 0)
						hitMarker.StudsOffset = Vector3.new(0, 2, 0)
						hitMarker.AlwaysOnTop = true
						hitMarker.Parent = zombieRoot

						local damageText = Instance.new("TextLabel")
						damageText.Size = UDim2.new(1, 0, 1, 0)
						damageText.BackgroundTransparency = 1
						damageText.Text = tostring(config.Damage)
						damageText.TextColor3 = Color3.fromRGB(255, 100, 100)
						damageText.TextScaled = true
						damageText.Font = Enum.Font.SourceSansBold
						damageText.Parent = hitMarker

						-- Анимация текста урона
						local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
						local tween = TweenService:Create(damageText, tweenInfo, {
							Position = UDim2.new(0, 0, -1, 0),
							TextTransparency = 1
						})
						tween:Play()

						Debris:AddItem(hitMarker, 1)
					end
				end
			end
		end
	end
end

-- Обработчики событий
MeleeAttack.OnServerEvent:Connect(function(player, hitData)
	if typeof(hitData) ~= "table" then return end
	if typeof(hitData.Position) ~= "Vector3" then return end

	processAttack(player, hitData)
end)

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		task.wait(0.5) -- Ждём загрузки персонажа
		giveStarterWeapon(player)
	end)
end)

-- Очистка при выходе
Players.PlayerRemoving:Connect(function(player)
	cooldowns[player] = nil
	equippedWeapons[player] = nil
end)

return {}