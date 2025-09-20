-- Schemas.lua
local START_LEAVES = 1000   -- <<< временно для теста
local START_SPORES = 0

return {
	PlayerSave = function()
		return {
			Currency = { Leaves = START_LEAVES, Spores = START_SPORES },
			UnlockedTier = 1,
			Plants = {},
			Traps = {},
			DayCount = 0,
			NightDifficulty = "normal",
			LostPlants = {},
			Inventory = {
				Seeds = {
					pea = 0,
					sunflower = 0,
					wallnut = 0,
					pear = 0,
				}
			}
		}
	end
}
