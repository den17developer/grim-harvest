-- ZombieService.lua
local ZombieDirector = require(script.Parent.ZombieDirector)
local MeleeService = require(script.Parent.MeleeService)

-- Запускаем сервис ближнего боя
MeleeService = MeleeService or {}

-- Запускаем директора зомби
ZombieDirector.Start()