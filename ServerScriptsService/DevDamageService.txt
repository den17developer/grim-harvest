-- DevDamageService.lua — серверный DEV-урон (работает только в Studio)
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local DevDealDamage = Remotes:FindFirstChild("DevDealDamage") or Instance.new("RemoteEvent", Remotes)
DevDealDamage.Name = "DevDealDamage"

DevDealDamage.OnServerEvent:Connect(function(player, origin: Vector3, direction: Vector3)
	-- Безопасность: разрешаем только в Studio
	if not RunService:IsStudio() then return end
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return end
	local mag = direction.Magnitude
	if mag < 1 or mag > 500 then return end  -- анти-эксплойт

	-- Рейкаст на сервере, игнорируя самого игрока
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, direction, params)
	if not result then return end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitModel then return end

	local hum = hitModel:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Валидируем, что это наш зомби
	if hitModel:GetAttribute("ZombieType") or string.find(hitModel.Name, "^Zombie_") then
		hum:TakeDamage(25)
	end
end)
