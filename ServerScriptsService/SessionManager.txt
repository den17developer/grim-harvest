-- SessionManager.lua
-- Глобальный день/ночь от реального времени + дневной доход + мягкий Lighting

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

local DayNightChanged = Remotes:FindFirstChild("DayNightChanged") or Instance.new("RemoteEvent", Remotes)
DayNightChanged.Name = "DayNightChanged"
local DayTimer = Remotes:FindFirstChild("DayTimer") or Instance.new("RemoteEvent", Remotes)
DayTimer.Name = "DayTimer"

local GardenPlots = workspace:WaitForChild("GardenPlots")

local CurrencyService = require(game.ServerScriptService.CurrencyService)
local Persistence = require(game.ServerScriptService.Persistence)
local PlantCatalog = require(game.ReplicatedStorage.Shared.PlantCatalog)
local GlobalClock = require(game.ReplicatedStorage.Shared.GlobalClock)

local FADE = 2.0 -- сек для плавного Lighting

-- ===== Lighting helpers =====
local function ensureLightingParts()
	local cc = Lighting:FindFirstChild("GG_Color") or Instance.new("ColorCorrectionEffect", Lighting)
	cc.Name = "GG_Color"
	local bloom = Lighting:FindFirstChild("GG_Bloom") or Instance.new("BloomEffect", Lighting)
	bloom.Name = "GG_Bloom"
	local atmo = Lighting:FindFirstChild("GG_Atmosphere") or Instance.new("Atmosphere", Lighting)
	atmo.Name = "GG_Atmosphere"
	return cc, bloom, atmo
end

local function applyDayLighting()
	Lighting.ClockTime = 13
	Lighting.Brightness = 2
	local cc, bloom, atmo = ensureLightingParts()
	local t = TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(cc, t, { Brightness = 0.05, Contrast = 0.05, TintColor = Color3.fromRGB(255,255,255) }):Play()
	TweenService:Create(bloom, t, { Intensity = 0.3, Size = 24, Threshold = 2.0 }):Play()
	TweenService:Create(atmo, t, { Density = 0.15, Haze = 1.0, Color = Color3.fromRGB(200, 230, 255), Decay = Color3.fromRGB(255, 255, 255) }):Play()
end

local function applyNightLighting()
	Lighting.ClockTime = 22
	Lighting.Brightness = 1
	local cc, bloom, atmo = ensureLightingParts()
	local t = TweenInfo.new(FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(cc, t, { Brightness = -0.08, Contrast = 0.12, TintColor = Color3.fromRGB(210,220,255) }):Play()
	TweenService:Create(bloom, t, { Intensity = 0.8, Size = 40, Threshold = 1.5 }):Play()
	TweenService:Create(atmo, t, { Density = 0.35, Haze = 2.0, Color = Color3.fromRGB(160, 180, 210), Decay = Color3.fromRGB(180, 190, 220) }):Play()
end

local function setPlotNightActive(plot: Model, active: boolean)
	plot:SetAttribute("NightActive", active)
	local lightsFolder = plot:FindFirstChild("Lights")
	if lightsFolder then
		for _, d in ipairs(lightsFolder:GetDescendants()) do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				d.Enabled = active
			end
		end
	end
end

local function setAllPlotsNight(active: boolean)
	for _, plot in ipairs(GardenPlots:GetChildren()) do
		if plot:IsA("Model") then
			setPlotNightActive(plot, active)
		end
	end
end

local function playerByUserId(uid: number)
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.UserId == uid then return pl end
	end
	return nil
end

local function awardDayIncomeForPlot(plot: Model)
	local ownerId = plot:GetAttribute("OwnerUserId")
	if not ownerId then return end
	local player = playerByUserId(ownerId)
	if not player then return end

	local total = 0
	for _, obj in ipairs(plot:GetChildren()) do
		if obj:IsA("BasePart") and obj.Name:find("^Plant_") then
			local pid = obj:GetAttribute("PlantId")
			local cfg = pid and PlantCatalog[pid] or nil
			if cfg and cfg.Type == "resource" then
				total += (cfg.IncomeDay or 2)
			end
		end
	end
	local grid = plot:FindFirstChild("GridSlots")
	if grid then
		for _, bed in ipairs(grid:GetChildren()) do
			if bed:IsA("Model") and (bed:GetAttribute("Unlocked") == true) then
				total += 2
			end
		end
	end
	if total > 0 then
		CurrencyService.AddLeaves(player, total)
	end
end

local function incrementDayCountAndSave(plot: Model)
	local ownerId = plot:GetAttribute("OwnerUserId")
	if not ownerId then return end
	local player = playerByUserId(ownerId)
	if not player then return end

	local current = plot:GetAttribute("DayCount") or 0
	plot:SetAttribute("DayCount", current + 1)

	local save = Persistence.Load(player) or Persistence.Default()
	save.DayCount = current + 1
	save.Currency = CurrencyService.Export(player)
	Persistence.Save(player, save)
end

-- Синхронизация нового участка с текущей фазой
GardenPlots.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		local phase = workspace:GetAttribute("GG_Phase") or "day"
		setPlotNightActive(child, phase == "night")
	end
end)

-- ===== Главный «такт» от реального времени =====
task.spawn(function()
	ensureLightingParts()

	local lastPhase = nil
	while true do
		local phase, timeLeft = GlobalClock.nowPhase()

		-- Фаза как атрибут мира
		if workspace:GetAttribute("GG_Phase") ~= phase then
			workspace:SetAttribute("GG_Phase", phase)
		end

		-- Переход фазы
		if phase ~= lastPhase then
			if phase == "day" then
				applyDayLighting()
				setAllPlotsNight(false)
				-- ночь закончилась → засчитываем день и выдаём дневной доход
				for _, plot in ipairs(GardenPlots:GetChildren()) do
					if plot:IsA("Model") then
						incrementDayCountAndSave(plot)
						awardDayIncomeForPlot(plot)
					end
				end
			else -- night
				applyNightLighting()
				setAllPlotsNight(true)
			end
			DayNightChanged:FireAllClients(phase, (phase=="day" and GlobalClock.DAY_LENGTH or GlobalClock.NIGHT_LENGTH))
			lastPhase = phase
		end

		-- Таймер каждую секунду
		DayTimer:FireAllClients(phase, timeLeft)

		task.wait(1)
	end
end)
