-- CollisionConfig.lua
local PhysicsService = game:GetService("PhysicsService")

local function ensureGroup(name: string)
	-- RegisterCollisionGroup бросает ошибку, если группа уже есть — оборачиваем pcall
	pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end)
end

ensureGroup("Zombies")
ensureGroup("PlotDecor")

-- Правило: зомби не сталкиваются с декором грядок
PhysicsService:CollisionGroupSetCollidable("Zombies", "PlotDecor", false)

-- Хелпер массового назначения
local function setGroupDescendants(root: Instance, groupName: string)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = groupName -- <-- новое API
		end
	end
end

-- Если папка с зомби уже есть при старте — проставим группу
local zFolder = workspace:FindFirstChild("Zombies")
if zFolder then
	for _, z in ipairs(zFolder:GetChildren()) do
		setGroupDescendants(z, "Zombies")
	end
end

return {
	SetGroupDescendants = setGroupDescendants
}
