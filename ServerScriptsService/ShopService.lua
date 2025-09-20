-- ShopService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local OpenSeedShop = Remotes:WaitForChild("OpenSeedShop")

local shopFolder = workspace:WaitForChild("SeedShop")
local trigger = shopFolder:WaitForChild("ShopTrigger")
local prompt = trigger:WaitForChild("OpenSeedShopPrompt")

prompt.Triggered:Connect(function(player)
	OpenSeedShop:FireClient(player)
end)
