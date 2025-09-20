-- BossEventScheduler.lua
-- Каждую субботу в 21:00 (Asia/Almaty ~ UTC+5) активирует ивент "Ночь босса" до конца текущей ночи.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local BossEventChanged = Remotes:FindFirstChild("BossEventChanged") or Instance.new("RemoteEvent", Remotes)
BossEventChanged.Name = "BossEventChanged"

local GlobalClock = require(game.ReplicatedStorage.Shared.GlobalClock)

-- Конфиг времени:
local LOCAL_UTC_OFFSET = 5 * 3600 -- Азия/Алматы в 2025 = UTC+5
local EVENT_HOUR = 21             -- 21:00 локального (Алматы)
local EVENT_DOW = 6               -- день недели: 0=вс,1=пн,...,6=сб
local SEC_PER_DAY = 86400
local SEC_PER_WEEK = 7 * SEC_PER_DAY

-- day-of-week для локального unix (0=вс,...,6=сб)
local function localDow(localUnix: number): number
	local days = math.floor(localUnix / SEC_PER_DAY)
	-- 1970-01-01 был четверг (4). Приводим к 0=вс.
	return (days + 4) % 7
end

-- часы/минуты локального времени
local function localHMS(localUnix: number): (number, number, number)
	local sec = localUnix % SEC_PER_DAY
	local h = math.floor(sec / 3600)
	sec = sec - h * 3600
	local m = math.floor(sec / 60)
	local s = sec - m * 60
	return h, m, s
end

-- ближайшая следующая суббота 21:00 (UTC)
local function computeNextEventUnix(nowUtc: number): number
	local localNow = nowUtc + LOCAL_UTC_OFFSET
	local days = math.floor(localNow / SEC_PER_DAY)
	local dow = localDow(localNow)
	local h, m, _ = localHMS(localNow)

	-- сколько дней до субботы
	local deltaDays = (EVENT_DOW - dow + 7) % 7
	local localMidnight = days * SEC_PER_DAY
	local candidate = (localMidnight + deltaDays * SEC_PER_DAY) + EVENT_HOUR * 3600

	-- если сегодня суббота и время уже >= 21:00, переносим на следующую неделю
	if deltaDays == 0 and (h > EVENT_HOUR or (h == EVENT_HOUR and m >= 0)) then
		candidate = candidate + SEC_PER_WEEK
	end
	return candidate - LOCAL_UTC_OFFSET
end

-- Флаг, чтобы не триггерить один и тот же ивент многократно в эту неделю
local lastTriggeredWeekIndex = nil

-- Выставить атрибуты и уведомить клиентов
local function setBossActive(active: boolean)
	if workspace:GetAttribute("GG_BossEventActive") ~= active then
		workspace:SetAttribute("GG_BossEventActive", active)
		BossEventChanged:FireAllClients(active)
	end
end

-- Основной цикл
task.spawn(function()
	-- При старте посчитаем nextAt
	local nowUtc = DateTime.now().UnixTimestamp
	local nextAtUtc = computeNextEventUnix(nowUtc)
	workspace:SetAttribute("GG_NextBossEventUnix", nextAtUtc)

	while true do
		local now = DateTime.now().UnixTimestamp
		local localNow = now + LOCAL_UTC_OFFSET
		local dow = localDow(localNow)
		local h, m, _ = localHMS(localNow)

		-- Текущая неделя-индекс (для защиты от повтора)
		local weekIndex = math.floor((localNow) / SEC_PER_WEEK)

		-- Условие начала окна: суббота 21:00 локального времени (минутная точка)
		if (dow == EVENT_DOW) and (h == EVENT_HOUR) and (m == 0) then
			if lastTriggeredWeekIndex ~= weekIndex then
				lastTriggeredWeekIndex = weekIndex
				-- Активируем ивент: держим его до конца текущей ночи нашего цикла
				setBossActive(true)
			end
		end

		-- Деактивируем ивент, когда глобальная фаза изменилась на "day"
		local phase = (workspace:GetAttribute("GG_Phase") or "day")
		if phase == "day" and workspace:GetAttribute("GG_BossEventActive") == true then
			setBossActive(false)
			-- Пересчитаем следующий запуск
			local future = computeNextEventUnix(now)
			workspace:SetAttribute("GG_NextBossEventUnix", future)
		end

		-- Обновляем "следующий запуск" раз в минуту (на всякий случай)
		if (now % 60) == 0 then
			local recomputed = computeNextEventUnix(now)
			workspace:SetAttribute("GG_NextBossEventUnix", recomputed)
		end

		task.wait(1)
	end
end)
