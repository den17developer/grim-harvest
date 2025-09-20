-- GlobalClock.lua
-- Глобальная фаза "день/ночь" от реального времени (Unix). Все серверы синхронны.
-- Настраивай длительности при необходимости.

local DateTime = DateTime

local Clock = {}

Clock.DAY_LENGTH = 30      -- сек
Clock.NIGHT_LENGTH = 30    -- сек
Clock.CYCLE = Clock.DAY_LENGTH + Clock.NIGHT_LENGTH
Clock.ANCHOR_UNIX = 0      -- якорь цикла (не трогаем, нам хватает любой фикс. опоры)

-- Возвращает фазу и "сколько осталось" в текущем сегменте на момент unix (UTC).
function Clock.phaseAt(unixUtc: number): (string, number)
	local pos = (unixUtc - Clock.ANCHOR_UNIX) % Clock.CYCLE
	if pos < Clock.DAY_LENGTH then
		return "day", math.floor(Clock.DAY_LENGTH - pos + 0.5)
	else
		local p = pos - Clock.DAY_LENGTH
		return "night", math.floor(Clock.NIGHT_LENGTH - p + 0.5)
	end
end

function Clock.nowPhase(): (string, number)
	local unix = DateTime.now().UnixTimestamp
	return Clock.phaseAt(unix)
end

return Clock
