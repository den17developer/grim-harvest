-- PlantCombatStarter.lua
-- Script (обычный серверный скрипт)
-- Путь: ServerScriptService/PlantCombatStarter

local PlantCombatService = require(script.Parent.PlantCombatService)

-- Запускаем боевую систему
PlantCombatService.Start()

print("[PlantCombat] Combat system started")