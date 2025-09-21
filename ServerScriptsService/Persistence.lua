-- Persistence.lua
-- ModuleScript
-- Путь: ServerScriptService/Persistence

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

-- ВАЖНО: включи "Enable Studio API Access" (Game Settings → Security), иначе в Studio будет падать
local STORE_NAME = "GG_Save_v1"
local store = nil

-- Безопасная инициализация DataStore
local function getStore()
	if store then return store end

	local success, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)

	if success then
		store = result
	else
		warn("[Persistence] Failed to get DataStore:", result)
		if RunService:IsStudio() then
			warn("[Persistence] Make sure 'Enable Studio Access to API Services' is ON in Game Settings → Security")
		end
	end

	return store
end

local M = {}

-- Память процесса: последний снимок сейва, "грязные" и "в процессе сохранения"
local cache: {[Player]: table} = {}
local dirty: {[Player]: boolean} = {}
local saving: {[Player]: boolean} = {}

-- -------- БАЗОВЫЕ СТРУКТУРЫ --------
function M.Default()
	return {
		UnlockedTier = 1,
		Plants = {},                -- [slotId] = {PlantId, Level, Rarity, HP}
		Currency = { Leaves = 1000, Spores = 0 },
		DayCount = 0,
		Inventory = {
			Seeds = {
				pea = 0,
				sunflower = 0,
				wallnut = 0,
				pear = 0,
			}
		},
		PurchasedWeapon = nil,      -- для сохранения купленного оружия
		_version = 1,
	}
end

local function keyFor(plr: Player)
	return ("u_%d"):format(plr.UserId)
end

-- -------- ЗАГРУЗКА --------
function M.Load(plr: Player): table?
	local dataStore = getStore()
	if not dataStore then
		warn("[Persistence] No DataStore available, using default save")
		return nil
	end

	local key = keyFor(plr)
	local data: table? = nil
	local ok, err = pcall(function()
		data = dataStore:GetAsync(key)
	end)

	if not ok then
		warn("[Persistence] Load failed for", plr.Name, err)
		return nil
	end

	if data == nil then
		return nil
	end

	-- миграции по _version при необходимости
	cache[plr] = data
	dirty[plr] = false
	return data
end

-- -------- СОВМЕСТИМОСТЬ: Save помечает "грязным", но НЕ пишет сразу --------
function M.Save(plr: Player, save: table)
	cache[plr] = save
	dirty[plr] = true
	-- Не пишем SetAsync тут, чтобы не забивать очередь. Пишем батчем в FlushNow.
end

-- Пометить "грязным" (если другие модули меняют состояние без Save)
function M.MarkDirty(plr: Player)
	dirty[plr] = true
end

-- -------- ФАКТИЧЕСКАЯ ЗАПИСЬ В DATASTORE --------
-- buildSaveFn: опционально передай функцию, которая соберёт "актуальный" сейв прямо сейчас.
function M.FlushNow(plr: Player, buildSaveFn: (() -> table)?)
	local dataStore = getStore()
	if not dataStore then
		warn("[Persistence] No DataStore available, cannot save")
		return false, "No DataStore"
	end

	if saving[plr] then return end
	if not dirty[plr] and not buildSaveFn then return end -- нечего писать

	saving[plr] = true
	dirty[plr] = false

	local save = buildSaveFn and buildSaveFn() or cache[plr] or M.Default()
	cache[plr] = save
	local key = keyFor(plr)

	local ok, err
	for i = 1, 3 do
		ok, err = pcall(function()
			dataStore:SetAsync(key, save)
		end)
		if ok then break end
		task.wait(0.8 * i)
	end

	if not ok then
		warn("[Persistence] FlushNow failed for", plr.Name, err)
		dirty[plr] = true -- пометим снова, чтобы можно было повторить позже
	end

	saving[plr] = false
	return ok, err
end

-- Сохранить всех онлайн-игроков (ручной вызов по желанию)
function M.FlushAllNow()
	for _, plr in ipairs(Players:GetPlayers()) do
		M.FlushNow(plr)
	end
end

-- -------- УТИЛИТЫ ДЛЯ ДРУГИХ МОДУЛЕЙ --------

-- Обновить кеш валюты (пример: из CurrencyService)
function M.SetCurrency(plr: Player, leaves: number, spores: number?)
	local s = cache[plr] or M.Default()
	s.Currency = s.Currency or { Leaves = 0, Spores = 0 }
	s.Currency.Leaves = leaves
	if spores ~= nil then s.Currency.Spores = spores end
	cache[plr] = s
	dirty[plr] = true
end

function M.GetCached(plr: Player): table?
	return cache[plr]
end

-- (Опционально) централизованный сбор сейва
function M.BuildCurrentSaveFor(plr: Player): table
	-- Заглушка: вернём из кеша, если есть; при желании подтяни сюда PlantRuntime.CollectState(...)
	return cache[plr] or M.Default()
end

-- -------- АВТО-СБРОС ПРИ ВЫХОДЕ И ЗАКРЫТИИ СЕРВЕРА --------
Players.PlayerRemoving:Connect(function(plr)
	M.FlushNow(plr)
	cache[plr] = nil
	dirty[plr] = nil
	saving[plr] = nil
end)

game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do	
		M.FlushNow(plr)
	end
	task.wait(2) -- даем время на сохранение
end)

return M