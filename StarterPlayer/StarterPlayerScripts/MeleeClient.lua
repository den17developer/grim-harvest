-- MeleeClient.lua
-- Клиентская логика ближнего боя: обработка кликов, визуальные эффекты, предсказание

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MeleeAttack = Remotes:WaitForChild("MeleeAttack")
local WeaponEquipped = Remotes:WaitForChild("WeaponEquipped")

-- Состояние (ВАЖНО: по умолчанию false)
local equipped = false
local currentWeapon = nil
local attackCooldown = 0
local lastAttackTime = 0

-- Конфигурация оружия (для клиентского предсказания)
local WEAPON_CONFIGS = {
	BasicShovel = { Cooldown = 0.5, Range = 8 },
	IronShovel = { Cooldown = 0.4, Range = 10 },
	GoldenShovel = { Cooldown = 0.3, Range = 12 }
}

-- Визуальный эффект удара
local function createSwingEffect(startCFrame: CFrame, endCFrame: CFrame)
	local trail = Instance.new("Part")
	trail.Name = "SwingTrail"
	trail.Size = Vector3.new(0.2, 0.2, (startCFrame.Position - endCFrame.Position).Magnitude)
	trail.Material = Enum.Material.Neon
	trail.Color = Color3.fromRGB(255, 255, 255)
	trail.Transparency = 0.5
	trail.Anchored = true
	trail.CanCollide = false
	trail.CFrame = CFrame.lookAt(startCFrame.Position, endCFrame.Position) * CFrame.new(0, 0, -trail.Size.Z/2)
	trail.Parent = workspace

	-- Анимация исчезновения
	local fadeTween = TweenService:Create(
		trail,
		TweenInfo.new(0.2, Enum.EasingStyle.Linear),
		{Transparency = 1}
	)
	fadeTween:Play()

	Debris:AddItem(trail, 0.3)
end

-- Визуальная индикация точки удара
local function createHitIndicator(position: Vector3)
	local indicator = Instance.new("Part")
	indicator.Name = "HitIndicator"
	indicator.Shape = Enum.PartType.Cylinder
	indicator.Size = Vector3.new(0.1, 6, 6)
	indicator.Material = Enum.Material.ForceField
	indicator.Color = Color3.fromRGB(255, 100, 100)
	indicator.Transparency = 0.7
	indicator.Anchored = true
	indicator.CanCollide = false
	indicator.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	indicator.Parent = workspace

	-- Анимация расширения и исчезновения
	local expandTween = TweenService:Create(
		indicator,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Size = Vector3.new(0.1, 10, 10), Transparency = 1}
	)
	expandTween:Play()

	Debris:AddItem(indicator, 0.4)
end

-- Обработка атаки
local function performAttack()
	if not equipped or not currentWeapon then return end

	local now = tick()
	local config = WEAPON_CONFIGS[currentWeapon] or WEAPON_CONFIGS.BasicShovel

	if now - lastAttackTime < config.Cooldown then
		return -- на кулдауне
	end

	local character = player.Character
	if not character then return end

	local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then return end

	-- Получаем позицию клика
	local targetPosition = mouse.Hit.Position

	-- Проверяем дальность
	local distance = (targetPosition - humanoidRoot.Position).Magnitude
	if distance > config.Range then
		-- Ограничиваем дальность
		local direction = (targetPosition - humanoidRoot.Position).Unit
		targetPosition = humanoidRoot.Position + direction * config.Range
	end

	lastAttackTime = now

	-- Анимация удара (поворот инструмента)
	local tool = character:FindFirstChildOfClass("Tool")
	if tool and tool:FindFirstChild("Handle") then
		local handle = tool.Handle
		local originalCFrame = handle.CFrame

		-- Быстрый удар
		local swingTween = TweenService:Create(
			handle,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = originalCFrame * CFrame.Angles(math.rad(-60), 0, 0)}
		)
		swingTween:Play()

		swingTween.Completed:Connect(function()
			local returnTween = TweenService:Create(
				handle,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{CFrame = originalCFrame}
			)
			returnTween:Play()
		end)

		-- Визуальный эффект следа
		createSwingEffect(handle.CFrame, handle.CFrame * CFrame.new(0, -3, 0))
	end

	-- Визуальная индикация удара
	createHitIndicator(targetPosition)

	-- Отправляем на сервер
	MeleeAttack:FireServer(targetPosition)
end

-- Обработка экипировки оружия
WeaponEquipped.OnClientEvent:Connect(function(weaponType)
	currentWeapon = weaponType
	equipped = weaponType ~= nil

	-- Курсор НЕ меняем (убрали изменение)
end)

-- Обработка клика мыши
mouse.Button1Down:Connect(function()
	if equipped then
		performAttack()
	end
end)

-- Альтернативный ввод на мобильных устройствах
UserInputService.TouchTap:Connect(function(touchPositions, gameProcessedEvent)
	if gameProcessedEvent then return end
	if equipped then
		performAttack()
	end
end)

-- Визуальная подсказка дальности (опционально)
local rangeIndicator = nil

local function showRangeIndicator()
	if not equipped or not currentWeapon then
		if rangeIndicator then
			rangeIndicator:Destroy()
			rangeIndicator = nil
		end
		return
	end

	local character = player.Character
	if not character then return end

	local humanoidRoot = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRoot then return end

	if not rangeIndicator then
		rangeIndicator = Instance.new("Part")
		rangeIndicator.Name = "RangeIndicator"
		rangeIndicator.Shape = Enum.PartType.Cylinder
		rangeIndicator.Material = Enum.Material.ForceField
		rangeIndicator.Color = Color3.fromRGB(100, 255, 100)
		rangeIndicator.Transparency = 0.9
		rangeIndicator.Anchored = true
		rangeIndicator.CanCollide = false
		rangeIndicator.Parent = workspace
	end

	local config = WEAPON_CONFIGS[currentWeapon] or WEAPON_CONFIGS.BasicShovel
	rangeIndicator.Size = Vector3.new(0.1, config.Range * 2, config.Range * 2)
	rangeIndicator.CFrame = humanoidRoot.CFrame * CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, math.rad(90))
end

-- Обновление индикатора дальности
RunService.Heartbeat:Connect(function()
	if equipped then
		-- Опционально: показывать круг дальности
		-- showRangeIndicator()
	elseif rangeIndicator then
		rangeIndicator:Destroy()
		rangeIndicator = nil
	end
end)

-- Отслеживание экипировки инструментов
local function onToolEquipped(tool)
	if tool:GetAttribute("WeaponType") then
		equipped = true
		currentWeapon = tool:GetAttribute("WeaponType")
	end
end

local function onToolUnequipped()
	equipped = false
	currentWeapon = nil
	-- Курсор НЕ меняем (убрали)
end

-- Следим за инструментами в руках (ИСПРАВЛЕНО)
player.CharacterAdded:Connect(function(character)
	-- Сброс состояния при респавне
	equipped = false
	currentWeapon = nil

	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("WeaponType") then
			-- Экипировка произошла
			equipped = true
			currentWeapon = child:GetAttribute("WeaponType")

			child.Unequipped:Connect(function()
				onToolUnequipped()
			end)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("WeaponType") then
			onToolUnequipped()
		end
	end)
end)

-- При старте скрипта проверяем, если персонаж уже существует
if player.Character then
	-- Сброс состояния
	equipped = false
	currentWeapon = nil

	player.Character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("WeaponType") then
			equipped = true
			currentWeapon = child:GetAttribute("WeaponType")

			child.Unequipped:Connect(function()
				onToolUnequipped()
			end)
		end
	end)

	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") and child:GetAttribute("WeaponType") then
			onToolUnequipped()
		end
	end)

	-- Проверяем, есть ли уже Tool в руках
	local existingTool = player.Character:FindFirstChildOfClass("Tool")
	if existingTool and existingTool:GetAttribute("WeaponType") then
		equipped = true
		currentWeapon = existingTool:GetAttribute("WeaponType")
	end
end