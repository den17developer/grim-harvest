-- ZombieCatalog.lua
-- Базовые типы зомби (баланс placeholder)
return {
	grunt = { Display="Zombie",     MaxHP=60,  WalkSpeed=10, RewardLeaves=3 },
	brute  = { Display="Brute",      MaxHP=140, WalkSpeed=7,  RewardLeaves=7 },
	skipper= { Display="Skipper",    MaxHP=80,  WalkSpeed=13, RewardLeaves=5 }, -- "прыгун" (логика прыжка позже)
	-- задел под босса:
	boss   = { Display="Boss",       MaxHP=1200, WalkSpeed=8, RewardLeaves=50 },
}
