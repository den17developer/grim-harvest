-- CurrencyService.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local CurrencyChanged = Remotes:FindFirstChild("CurrencyChanged") or Instance.new("RemoteEvent", Remotes)
CurrencyChanged.Name = "CurrencyChanged"

local M = {}

local balances: {[Player]: {Leaves:number, Spores:number}} = {}

local function notify(player: Player)
	local b = balances[player]
	if b then CurrencyChanged:FireClient(player, {Leaves=b.Leaves, Spores=b.Spores}) end
end

function M.Init(player: Player, startCurrency: {Leaves:number, Spores:number}?)
	balances[player] = {
		Leaves = (startCurrency and startCurrency.Leaves) or 0,
		Spores = (startCurrency and startCurrency.Spores) or 0
	}
	notify(player)
end

function M.Get(player: Player)
	return balances[player]
end

function M.AddLeaves(player: Player, n: number)
	local b = balances[player]; if not b then return end
	b.Leaves += math.max(0, n or 0)
	notify(player)
end

function M.AddSpores(player: Player, n: number)
	local b = balances[player]; if not b then return end
	b.Spores += math.max(0, n or 0)
	notify(player)
end

function M.TrySpendLeaves(player: Player, price: number): boolean
	local b = balances[player]; if not b or not price or price < 0 then return false end
	if b.Leaves >= price then
		b.Leaves -= price
		notify(player)
		return true
	end
	return false
end

function M.Export(player: Player)
	local b = balances[player]
	return { Leaves = (b and b.Leaves) or 0, Spores = (b and b.Spores) or 0 }
end

function M.Cleanup(player: Player)
	balances[player] = nil
end

return M
