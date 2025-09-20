-- InventoryService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local InventoryChanged = Remotes:FindFirstChild("InventoryChanged") or Instance.new("RemoteEvent", Remotes)
InventoryChanged.Name = "InventoryChanged"

local M = {}

-- структура: per-player, только Seeds для простоты
local seedsByPlayer = {} :: {[Player]: {[string]: number}}

local function notify(player: Player)
	local seeds = seedsByPlayer[player] or {}
	-- отправляем клиенту слепок
	InventoryChanged:FireClient(player, { Seeds = seeds })
end

function M.Init(player: Player, saveInventory: table?)
	local seeds = (saveInventory and saveInventory.Seeds) or {}
	seedsByPlayer[player] = {
		pea = seeds.pea or 0,
		sunflower = seeds.sunflower or 0,
		wallnut = seeds.wallnut or 0,
	}
	notify(player)
end

function M.AddSeed(player: Player, plantId: string, amount: number)
	if not seedsByPlayer[player] then M.Init(player) end
	local t = seedsByPlayer[player]
	t[plantId] = math.max(0, (t[plantId] or 0) + (amount or 0))
	notify(player)
end

function M.GetSeeds(player: Player)
	return seedsByPlayer[player]
end

function M.TryConsumeSeed(player: Player, plantId: string): boolean
	local t = seedsByPlayer[player]; if not t then return false end
	local have = t[plantId] or 0
	if have <= 0 then return false end
	t[plantId] = have - 1
	notify(player)
	return true
end

function M.Export(player: Player)
	local t = seedsByPlayer[player] or {}
	return {
		Seeds = {
			pea = t.pea or 0,
			sunflower = t.sunflower or 0,
			wallnut = t.wallnut or 0,
		}
	}
end

function M.Cleanup(player: Player)
	seedsByPlayer[player] = nil
end

return M
