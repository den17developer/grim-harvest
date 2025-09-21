-- PlantCombatService.lua
-- ModuleScript
-- Путь: ServerScriptService/PlantCombatService

local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlantCatalog = require(ReplicatedStorage.Shared.PlantCatalog)

local M = {}

-- Конфигурация
local ATTACK_RANGE = 15 -- studs, дальность атаки
local PROJECTILE_SPEED = 20 -- studs/sec
local UPDATE_RATE = 0.5 -- как часто проверяем цели (сек)

-- Активные растения (те, что могут атаковать)
local activePlants = {} -- [plant] = {lastAttack, target, plot}

-- Визуальные настройки снарядов
local PROJECTILE_VISUALS = {
	pea = {
		Size = Vector3.new(0.8, 0.8, 0.8),
		Color = Color3.fromRGB(100, 255, 100),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball
	},
	pear = {
		Size = Vector3.new(1, 1.2, 1),
		Color = Color3.fromRGB(255, 255, 100),
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball
	}
}

-- Создание снаряда
local function createProjectile(plantId: string, startPos: Vector3): Part?
	local visual = PROJECTILE_VISUALS[plantId] or PROJECTILE_VISUALS.pea

	local projectile = Instance.new("Part")
	projectile.Name = "Projectile_" .. plantId
	projectile.Size = visual.Size
	projectile.Shape = visual.Shape
	projectile.Material = visual.Material
	projectile.Color = visual.Color
	projectile.TopSurface = Enum.SurfaceType.Smooth
	projectile.BottomSurface = Enum.SurfaceType.Smooth
	projectile.CanCollide = false
	projectile.CFrame = CFrame.new(startPos)
	projectile.Parent = workspace

	-- Добавляем свечение
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Color = visual.Color
	pointLight.Range = 5
	pointLight.Parent = projectile

	return projectile
end

-- Запуск снаряда
local function fireProjectile(plant: BasePart, target: Model, damage: number)
	local plantId = plant:GetAttribute("PlantId")
	if not plantId then return end

	local startPos = plant.Position + Vector3.new(0, 1, 0)
	local targetPart = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
	if not targetPart then return end

	local projectile = createProjectile(plantId, startPos)
	if not projectile then return end

	-- Рассчитываем траекторию
	local targetPos = targetPart.Position
	local direction = (targetPos - startPos).Unit
	local distance = (targetPos - startPos).Magnitude
	local flightTime = distance / PROJECTILE_SPEED

	-- Используем BodyVelocity для движения
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce = Vector3.new(4000, 4000, 4000)
	bodyVelocity.Velocity = direction * PROJECTILE_SPEED
	bodyVelocity.Parent = projectile

	-- Проверка попадания
	local hitConnection
	local startTime = tick()

	hitConnection = RunService.Heartbeat:Connect(function()
		-- Таймаут полета
		if tick() - startTime > flightTime * 1.5 then
			if hitConnection then hitConnection:Disconnect() end
			if projectile and projectile.Parent then
				projectile:Destroy()
			end
			return
		end

		-- Проверяем попадание
		if not projectile.Parent or not target.Parent then
			if hitConnection then hitConnection:Disconnect() end
			return
		end

		local humanoid = target:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			if hitConnection then hitConnection:Disconnect() end
			if projectile.Parent then projectile:Destroy() end
			return
		end

		local targetRoot = target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("Torso")
		if targetRoot then
			local dist = (projectile.Position - targetRoot.Position).Magnitude
			if dist < 2.5 then -- радиус попадания
				-- Наносим урон
				humanoid:TakeDamage(damage)

				-- Эффект попадания
				local hitEffect = Instance.new("Part")
				hitEffect.Name = "HitEffect"
				hitEffect.Size = Vector3.new(1, 1, 1)
				hitEffect.Shape = Enum.PartType.Ball
				hitEffect.Material = Enum.Material.ForceField
				hitEffect.Color = projectile.Color
				hitEffect.Anchored = true
				hitEffect.CanCollide = false
				hitEffect.CFrame = CFrame.new(targetRoot.Position)
				hitEffect.Parent = workspace

				-- Анимация взрыва
				local tween = TweenService:Create(
					hitEffect,
					TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Size = Vector3.new(3, 3, 3), Transparency = 1}
				)
				tween:Play()

				Debris:AddItem(hitEffect, 0.5)

				-- Удаляем снаряд
				if hitConnection then hitConnection:Disconnect() end
				if projectile.Parent then projectile:Destroy() end
			end
		end
	end)

	-- Автоочистка через время полета
	Debris:AddItem(projectile, flightTime * 1.5)
end

-- Поиск ближайшего зомби для растения
local function findNearestZombie(plant: BasePart, plot: Model): Model?
	local zombiesFolder = workspace:FindFirstChild("Zombies")
	if not zombiesFolder then return nil end

	local plantPos = plant.Position
	local nearestZombie = nil
	local nearestDist = ATTACK_RANGE

	for _, zombie in ipairs(zombiesFolder:GetChildren()) do
		if zombie:IsA("Model") then
			-- Проверяем, что зомби на нашем участке или идет к нему
			local humanoid = zombie:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local zombieRoot = zombie:FindFirstChild("HumanoidRootPart") or zombie:FindFirstChild("Torso")
				if zombieRoot then
					-- Проверяем, что зомби привязан к нашему участку
					local zombiePlotAttr = zombie:GetAttribute("TargetPlot")
					local plotId = plot:GetAttribute("OwnerUserId")

					-- Если атрибута нет, проверяем по расстоянию до участка
					local plotRoot = plot.PrimaryPart or plot:FindFirstChild("Root")
					if plotRoot then
						local distToPlot = (zombieRoot.Position - plotRoot.Position).Magnitude
						if distToPlot < 50 then -- зомби рядом с участком
							local dist = (plantPos - zombieRoot.Position).Magnitude
							if dist < nearestDist then
								nearestDist = dist
								nearestZombie = zombie
							end
						end
					end
				end
			end
		end
	end

	return nearestZombie
end

-- Обновление атаки для растения
local function updatePlantCombat(plant: BasePart, plantData: table)
	local plantId = plant:GetAttribute("PlantId")
	if not plantId then return end

	local config = PlantCatalog[plantId]
	if not config or config.Type ~= "attack" then return end

	local now = tick()
	local lastAttack = plantData.lastAttack or 0
	local fireRate = config.FireRate or 1.0

	-- Проверяем кулдаун
	if now - lastAttack < fireRate then return end

	-- Ищем цель
	local target = findNearestZombie(plant, plantData.plot)
	if not target then 
		plantData.target = nil
		return 
	end

	-- Атакуем
	plantData.lastAttack = now
	plantData.target = target

	local damage = config.Damage or 10
	fireProjectile(plant, target, damage)
end

-- Регистрация растения для боевой системы
function M.RegisterPlant(plant: BasePart, plot: Model)
	if not plant or not plot then return end

	local plantId = plant:GetAttribute("PlantId")
	if not plantId then return end

	local config = PlantCatalog[plantId]
	if not config or config.Type ~= "attack" then return end

	-- Добавляем в активные
	activePlants[plant] = {
		lastAttack = 0,
		target = nil,
		plot = plot
	}
end

-- Удаление растения из боевой системы
function M.UnregisterPlant(plant: BasePart)
	activePlants[plant] = nil
end

-- Главный цикл обновления
local updateConnection = nil

function M.Start()
	if updateConnection then return end

	updateConnection = RunService.Heartbeat:Connect(function()
		-- Проверяем фазу (атакуем только ночью)
		local phase = workspace:GetAttribute("GG_Phase")
		if phase ~= "night" then return end

		-- Обновляем каждое активное растение
		for plant, data in pairs(activePlants) do
			if plant.Parent and plant:GetAttribute("HP") and plant:GetAttribute("HP") > 0 then
				-- Проверяем, что растение не украдено
				if not plant:GetAttribute("IsCarried") and not plant:GetAttribute("BeingStolen") then
					updatePlantCombat(plant, data)
				end
			else
				-- Удаляем мертвые/удаленные растения
				activePlants[plant] = nil
			end
		end
	end)

	-- Подчищаем при смене фазы на день
	workspace:GetAttributeChangedSignal("GG_Phase"):Connect(function()
		if workspace:GetAttribute("GG_Phase") == "day" then
			-- Очищаем все снаряды
			for _, obj in ipairs(workspace:GetChildren()) do
				if obj.Name:match("^Projectile_") then
					obj:Destroy()
				end
			end
		end
	end)
end

function M.Stop()
	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	-- Очищаем все снаряды
	for _, obj in ipairs(workspace:GetChildren()) do
		if obj.Name:match("^Projectile_") then
			obj:Destroy()
		end
	end

	activePlants = {}
end

return M