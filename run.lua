#!/usr/bin/env luajit
require 'ext'

local seed = select(1, ...)
if seed then
	seed = tonumber(seed, 16)
else
	seed = os.time() 
	math.randomseed(seed)
	for i=1,100 do math.random() end
	seed = math.random(0,0x7fffffff)
end
print('seed', ('%x'):format(seed))
math.randomseed(seed)

local infilename = select(2, ...) or 'sm.sfc'
local outfilename = select(3, ...) or 'sm-random.sfc'


-- what skills does the player know?
local skills = {
	
	-- this one covers a wide range
	-- there's the lower green Brinstar power bomb item, which has always required touch-and-go
	-- but there are several other locations which requier different degrees of skill of touch-and-go:
	-- 1) accessing upper red Brinstar, you need either hijump, spacejump, ice ... or you can just use touch-and-go (super missiles help, for clearing the monsters out of the way)
	-- 2) accessing Kraid without hijump or spacejump
	-- 3) lots more
	touchAndGo = true,

	bombTechnique = true,

	-- whether the player knows to use mockball to get into the green Brinstar item area
	-- I think that's the only place it's really necessary
	mockball = true,
	
	-- if you want to bother freeze the crab to jump up the maridia start area
	suitlessMaridiaFreezeCrabs = true,
	
	-- speed boost by tapping 'a' at first, cuts off a block or two. maybe this isn't the right name.
	shortSpeedBoost = true,

	-- whether you want to run through the lava rooms of norfair without a suit
	hellrun = true,
	
	-- if you want to bother do that stupid freeze-the-mocktroid glitch to jump through the wall
	botwoonFreezeGlitch = false,

	-- I've seen people do this in reverse boss videos ...
	DraygonCrystalFlashBlueSparkWhatever = false,

	-- whether you know how to get through gates using super missiles
	superMissileGateGlitch = false,

	-- I've seen this done ... does it require high jump? either way...
	canJumpAcrossEntranceToWreckedShip = false,
	
	-- how to get out of lower norfair
	preciseTouchAndGoLowerNorfair = false,
	lowerNorfairSuitSwap = true,
}


-- [[
local function CanUsePowerBombs() 
	return req.morph and req.powerbomb
end

local function CanUseBombs() 
	return req.morph and req.bomb
end

local function CanUseSpringBall()
	return req.morph and req.springball
end

local function CanDestroyBombWalls() 
	return CanUseBombs()
	or CanUsePowerBombs() 
	or req.screwattack 
end

local function CanPassBombPassages() 
	return CanUseBombs() or CanUsePowerBombs() 
end

local function CanGetBackThroughBlueGates()
	return (skills.superMissileGateGlitch and req.supermissile) or req.wave
end


-- what it takes to get into lower green Brinstar, and subsequently red Brinstar
-- either a supermissile through the pink Brinstar door
-- or a powerbomb through the blue Brinstar below Crateria entrance
local function CanAccessRedBrinstar() 
	return req.supermissile or CanUsePowerBombs() 
end


-- upper red Brinstar is the area of the first powerbomb you find, with the missile tank behind it, and the jumper room next to it
-- notice that these items require an on-escape to be powerbombs 
-- ... or else you get stuck in upper red Brinstar
-- however this escape condition is unique, because it is spread among two items
--  either the power bomb must be a powerbomb to escape
--  or you must have super missiles beforehand, and the super missile must be a powerbomb
-- I will implement this as requiring the escape-condition of the power bomb to be to have power bombs
local function CanAccessUpperRedBrinstar()
	return CanAccessRedBrinstar()
	and (
		-- you can freeze the monsters and jump off of them
		req.ice 
		-- or you can super missile them and touch-and-go up
		or (skills.touchAndGo and req.supermissile) 
		-- or you can destroy them (with super missiles or screw attack) and either bomb technique or spacejump up
		or ((req.screwattack or req.supermissile) and (skills.bombTechnique or req.spacejump))
	)
end


local function CanAccessKraid() 
	return CanAccessRedBrinstar() 
	and (skills.touchAndGo or req.spacejump or req.hijump) 
	and CanPassBombPassages() 
end

local function EffectiveMissileCount()
	return (req.missile or 0) + 5 * (req.supermissile or 0)
end

local function EffectiveEnergyCount() 
	return (req.energy or 0) + math.min((req.energy or 0) + 1, req.reserve or 0) 
end

local function CanAccessOuterMaridia() 
	-- get to red brinstar
	return CanAccessRedBrinstar() 
	-- break through the tube
	and req.powerbomb 
	-- now to get up ...
	and (
		-- if you have gravity, you can get up with touch-and-go, spacejump, hijump, or bomb technique
		(req.gravity and (skills.touchAndGo or req.spacejump or req.hijump or (skills.bombTechnique and CanUseBombs())))
		-- if you don't have gravity then you need high jump and ice.  without gravity you do need high jump just to jump up from the tube that you break, into the next room.
		or (skills.suitlessMaridiaFreezeCrabs and req.hijump and req.ice)
		
		-- suitless is possible so long as the space jump item is replaced with gravity suit to get out of Draygon's room ... or you do the crystal spark + blue spark + whatever move that I don't know how to do
	)
end

local function CanAccessInnerMaridia() 
	return CanAccessOuterMaridia() 
	and (req.spacejump or req.grappling or req.speed) 
end

local function CanDefeatBotwoon() 
	return CanAccessInnerMaridia() 
	and (
		(skills.botwoonFreezeGlitch and req.ice) 
		-- need to speed boost underwater
		or (req.gravity and req.speed)
		or skills.DraygonCrystalFlashBlueSparkWhatever
	)
end

local function CanDefeatDraygon() 
	return CanDefeatBotwoon() 
	and EffectiveEnergyCount() >= 3 
	-- can't use space jump or bombs underwater without gravity
	and req.gravity
	and (CanUseBombs() or req.spacejump)
end

local function CanAccessHeatedNorfair() 
	return CanAccessRedBrinstar() 
	and (
		-- you either need a suit
		req.varia 
		or req.gravity
		-- or, if you want to do hellrun ...
		or (skills.hellrun 
			-- ... with high jump / space jump ... how many does this take?
			and EffectiveEnergyCount() >= 4 
			and (req.hijump 
				or req.spacejump 
				-- without high jump and without suits it takes about 7 energy tanks
				or (CanUseBombs() and EffectiveEnergyCount() >= 7)
			)
		)
	) 
	-- idk that you need these ... maybe you need some e-tanks, but otherwise ...
	--and (req.spacejump or req.hijump) 
end

-- crocomire takes either wave on the rhs or speed booster and power bombs on the lhs
local function CanAccessCrocomire() 
	return CanAccessHeatedNorfair() and ((req.speed and CanUsePowerBombs()) or req.wave) 
end

local function CanAccessLowerNorfair() 
	return CanAccessHeatedNorfair() 
	-- powerbomb door
	and req.powerbomb 
	and (
		-- gravity and space jump is the default option
		(req.gravity and req.spacejump)
		-- you can do it without gravity, but you need precise touch and go, and you need high jump, and enough energy
		or (skills.preciseTouchAndGoLowerNorfair and req.hijump and EffectiveEnergyCount() >= 7)
		-- you can do without space jump if you have gravity and high jump -- suit swap
		or (skills.lowerNorfairSuitSwap and req.gravity)
	)
end

local function CanOpenMissileDoors() return req.missile or req.supermissile end

local function CanEnterAndLeaveGauntlet() 
	return CanUseBombs()
	or ((req.powerbomb or 0) >= 2 and req.morph) 
	or req.screwattack 
end

local function CanAccessWreckedShip() 
	return 
	-- super missile door from crateria surface
	-- ... or super missile door through pink Brinstar
	req.supermissile 
	-- power bomb door with the flying space pirates in it
	and CanUsePowerBombs() 
	-- getting across the water
	and (skills.canJumpAcrossEntranceToWreckedShip or req.spacejump or req.grappling or req.speed) 
end

local function CanDefeatPhantoon() 
	return CanAccessWreckedShip() 
	and req.charge 
	and (req.gravity or req.varia or EffectiveEnergyCount() >= 2) 
end

local locations = table{


	-- start run


	{name="Morphing Ball", addr=0x786DE, access=function() return true end},

	-- first missile tank you get
	{name="Missile (blue Brinstar bottom)", addr=0x78802, access=function() 
		return req.morph 
	end},

	-- second missile tank you get
	{name="Missile (blue Brinstar middle)", addr=0x78798, access=function() 
		return CanOpenMissileDoors() and req.morph 
	end},

	-- missile behind the rock-fall water room
	{name="Missile (blue Brinstar top)", addr=0x78836, access=function() 
		return CanOpenMissileDoors() and CanUsePowerBombs() 
		-- if you can already use powerbombs then you can get up the top.  touch and go replaces spacejump / speed boost
		and (skills.touchAndGo or req.speed or req.spacejump) 
	end},

	-- hidden missile behind rock-fall water room
	{name="Missile (blue Brinstar behind missile)", addr=0x7883C, access=function() 
		return CanOpenMissileDoors() and CanUsePowerBombs() 
		and (skills.touchAndGo or req.speed or req.spacejump) 
	end},

	-- technically you can use a damage boost, so all you really need is missiles
	--  however this doesn't work until after security is activated ...
	{name="Energy Tank (blue Brinstar)", addr=0x7879E, access=function() 
		return CanOpenMissileDoors() 
		and (req.hijump or req.speed or req.spacejump
			-- or CanActivateAlarm()
		) 
	end},

	-- power bombs behind power bomb wall near the morph ball 
	{name="Power Bomb (blue Brinstar)", addr=0x7874C, access=CanUsePowerBombs},

	-- this is the missile tank under old mother brain 
	-- here's one that, if you choose morph => screw attack, then your first missiles could end up here
	--  however ... unless security is activated, this item will not appear
	-- so either (a) deactivate security or (b) require morph and 1 missile tank for every item after security
	{name="Missile (Crateria bottom)", addr=0x783EE, access=CanDestroyBombWalls},

	-- this is another one of those, like plasma and the spore spawn super missiles, where there's no harm if we cut it off, because you need the very item to leave its own area
	{name="Bomb", addr=0x78404, access=function() return CanOpenMissileDoors() and CanPassBombPassages() end},
	
	{name="Energy Tank (Crateria tunnel to Brinstar)", addr=0x78432, access=CanDestroyBombWalls},
	

	-- Crateria surface


	-- upper right of the first room on the surface
	{name="Power Bomb (Crateria surface)", addr=0x781CC, access=function() 
		return CanUsePowerBombs() -- to get in the door
		-- to get up there
		and (req.speed or req.spacejump or (CanUseBombs() and skills.bombTechnique)) 
	end},

	-- upper left of the first room on the surface
	{name="Energy Tank (Crateria gauntlet)", addr=0x78264, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump or req.speed) end},

	{name="Missile (Crateria gauntlet right)", addr=0x78464, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump or req.speed) and CanPassBombPassages() end},
	{name="Missile (Crateria gauntlet left)", addr=0x7846A, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump or req.speed) and CanPassBombPassages() end},

	{name="Missile (outside Wrecked Ship bottom)", addr=0x781E8, access=CanAccessWreckedShip},
	{name="Missile (outside Wrecked Ship top)", addr=0x781EE, access=CanDefeatPhantoon},
	{name="Missile (outside Wrecked Ship middle)", addr=0x781F4, access=CanDefeatPhantoon},

	-- on the way to wrecked ship
	{name="Missile (Crateria moat)", addr=0x78248, access=function() 
		-- you just need to get through the doors, from there you can jump across
		return req.supermissile and req.powerbomb 
	end},
	
	-- speed boost area ... don't you need ice?
	{name="Super Missile (Crateria)", addr=0x78478, access=function() 
		return CanUsePowerBombs() 
		and req.speed 
		and (EffectiveEnergyCount() >= 1 or req.varia or req.gravity) 
	end},
	
	{name="Missile (Crateria middle)", addr=0x78486, access=CanPassBombPassages},


	-- green Brinstar


	{name="Missile (green Brinstar below super missile)", addr=0x78518, access=function() return CanPassBombPassages() and CanOpenMissileDoors() end},

	{name="Super Missile (green Brinstar top)", addr=0x7851E, access=function() 
		return CanDestroyBombWalls() and CanOpenMissileDoors() 
		and (skills.mockball or req.speed)
	end},

	{name="Reserve Tank (Brinstar)", addr=0x7852C, access=function() 
		return CanDestroyBombWalls() and CanOpenMissileDoors() 
		and (skills.mockball or req.speed)
	end},

	{name="Missile (green Brinstar behind missile)", addr=0x78532, access=function() 
		return CanPassBombPassages() and CanOpenMissileDoors() 
		and (skills.mockball or req.speed)
	end},

	{name="Missile (green Brinstar behind Reserve Tank)", addr=0x78538, access=function() 
		return CanDestroyBombWalls() and CanOpenMissileDoors() and req.morph 
		and (skills.mockball or req.speed)
	end},

	-- next to walljump creatures
	{name="Energy Tank (green Brinstar bottom)", addr=0x787C2, access=CanUsePowerBombs},

	-- next to walljump creatures
	{name="Super Missile (green Brinstar bottom)", addr=0x787D0, access=function() return CanUsePowerBombs() and req.supermissile end},
	
	-- next to walljump creatures
	{name="Power Bomb (green Brinstar bottom)", addr=0x784AC, access=CanUsePowerBombs},


	-- pink Brinstar


	-- super missile after spore spawn.
	-- this is a potential trap, if it is swapped with something other than super missiles, because you can't get out without them
	{
		name = "Super Missile (pink Brinstar)", 
		addr = 0x784E4, 
		access=function() 
			return CanPassBombPassages() 
		end,
		escape = function()
			return req.supermissile
		end
	},
	
	{name="Missile (pink Brinstar top)", addr=0x78608, access=function() 
		return CanDestroyBombWalls() and CanOpenMissileDoors() 
		-- doesn't really need these.  you can just use touch-and-go
		and (skills.touchAndGo or req.grappling or req.spacejump or req.speed) 
	end},
	
	{name="Missile (pink Brinstar bottom)", addr=0x7860E, access=function() 
		return (CanDestroyBombWalls() and CanOpenMissileDoors()) 
	end},
	
	{name="Charge Beam", addr=0x78614, access=function() 
		return (CanPassBombPassages() and CanOpenMissileDoors()) 
	end},
	
	{name="Power Bomb (pink Brinstar)", addr=0x7865C, access=function() 
		return CanUsePowerBombs() and req.supermissile 
		-- this one has grappling blocks before it, but honestly you can just touch-and-go up there 
		and (skills.touchAndGo or req.grappling or req.spacejump or req.speed) 
	end},

	-- doesn't really need gravity, just helps
	{name="Energy Tank (pink Brinstar bottom)", addr=0x787FA, access=function() 
		return CanUsePowerBombs() 
		and CanOpenMissileDoors() 
		and req.speed 
		and (skills.shortSpeedBoost or req.gravity)
	end},

	-- the only thing that needs wave:
	{name="Energy Tank (pink Brinstar top)", addr=0x78824, access=function() 
		return CanUsePowerBombs() 
		and CanGetBackThroughBlueGates()
	end},


	-- right side of Brinstar (lower green, red, Kraid, etc)
	

	{name="Missile (green Brinstar pipe)", addr=0x78676, access=function() 
		return ((CanPassBombPassages() and req.supermissile) 
			or CanUsePowerBombs()
		) 
		and (skills.touchAndGo or req.hijump or req.spacejump) 
	end},

	{name="X-Ray Visor", addr=0x78876, access=function()
		return CanAccessRedBrinstar() 
		and CanUsePowerBombs() 
		and (req.grappling or req.spacejump) 
	end},

	-- red Brinstar top:

	-- behind a super missile door
	-- you don't need power bombs to get this, but you need power bombs to escape this area
	{
		name = "Power Bomb (red Brinstar spike room)", 
		addr = 0x7890E, 
		access = function() 
			return CanAccessUpperRedBrinstar() and req.supermissile
		end,
		escape = function()
			return CanUsePowerBombs()
		end,
	},

	-- behind a powerbomb wall 
	{name="Missile (red Brinstar spike room)", addr=0x78914, access=function() 
		return CanAccessUpperRedBrinstar() and CanUsePowerBombs() 
	end},

	-- super missile door, power bomb floor
	{name="Power Bomb (red Brinstar sidehopper room)", addr=0x788CA, access=function() 
		return CanAccessUpperRedBrinstar() and req.supermissile and CanUsePowerBombs() 
	end},

	-- red Brinstar bottom:
	
	{name="Spazer", addr=0x7896E, access=function() 
		return CanAccessRedBrinstar() 
		and CanPassBombPassages() 
		and (skills.touchAndGo or req.spacejump or req.hijump) 
	end},
	
	{name="Missile (Kraid)", addr=0x789EC, access=function() 
		return CanAccessKraid() and CanUsePowerBombs() 
	end},

	-- accessible only after kraid is killed
	{name="Energy Tank (Kraid)", addr=0x7899C, access=CanAccessKraid},
	
	{name="Varia Suit", addr=0x78ACA, access=CanAccessKraid},

	
	-- Norfair

	
	{name="Missile (lava room)", addr=0x78AE4, access=CanAccessHeatedNorfair},
	
	{name="Ice Beam", addr=0x78B24, access=function() 
		return CanAccessKraid() 
		and (req.gravity or req.varia
			or EffectiveEnergyCount() >= 4	-- my addition, because you don't need gravity
		)
		and req.speed 
		and (CanUsePowerBombs() or req.ice) 
	end},

	-- TODO give this a different restriction
	-- it doesn't need 7 tanks, like bubble rooms, but maybe just 5
	{name="Missile (below Ice Beam)", addr=0x78B46, access=function() 
		return CanAccessHeatedNorfair() and CanUsePowerBombs() and req.speed 
	end},
	
	{name="Energy Tank (Crocomire)", addr=0x78BA4, access=CanAccessCrocomire},
	{name="Hi-Jump Boots", addr=0x78BAC, access=CanAccessRedBrinstar},
	{name="Missile (above Crocomire)", addr=0x78BC0, access=function() return CanAccessCrocomire() and (req.spacejump or req.grappling) end},
	{name="Missile (Hi-Jump Boots)", addr=0x78BE6, access=CanAccessRedBrinstar},
	{name="Energy Tank (Hi-Jump Boots)", addr=0x78BEC, access=CanAccessRedBrinstar},
	{name="Power Bomb (Crocomire)", addr=0x78C04, access=function() return CanAccessCrocomire() and (req.spacejump or req.grappling) end},
	{name="Missile (below Crocomire)", addr=0x78C14, access=CanAccessCrocomire},
	{name="Missile (Grappling Beam)", addr=0x78C2A, access=function() return CanAccessCrocomire() and (req.spacejump or req.grappling or req.speed) end},
	{name="Grappling Beam", addr=0x78C36, access=function() return CanAccessCrocomire() and (req.spacejump or (req.speed and req.hijump)) end},

	-- upper bubble room ... probably needs high jump or ice ... 
	{name="Reserve Tank (Norfair)", addr=0x78C3E, access=function() return CanAccessHeatedNorfair() and (req.spacejump or req.grappling) end},
	{name="Missile (Norfair Reserve Tank)", addr=0x78C44, access=function() return CanAccessHeatedNorfair() and (req.spacejump or req.grappling) end},
	{name="Missile (bubble Norfair green door)", addr=0x78C52, access=function() return CanAccessHeatedNorfair() and (req.spacejump or req.grappling) end},
	{name="Missile (bubble Norfair)", addr=0x78C66, access=CanAccessHeatedNorfair},
	{name="Missile (Speed Booster)", addr=0x78C74, access=CanAccessHeatedNorfair},
	{name="Speed Booster", addr=0x78C82, access=CanAccessHeatedNorfair},
	{name="Missile (Wave Beam)", addr=0x78CBC, access=CanAccessHeatedNorfair},
	
	{
		name = "Wave Beam",
		addr = 0x78CCA, 
		access = function()
			return CanAccessHeatedNorfair() 
			-- or take some damange and use touch and go ...
			--and (req.spacejump or req.grappling)
		end,
		-- on the way back, you need to go thruogh the top gate, or morph to go through the bottom ...
		escape = function()
			return CanGetBackThroughBlueGates() or req.morph
		end,
	},


	-- lower Norfair


	{name="Missile (Gold Torizo)", addr=0x78E6E, access=CanAccessLowerNorfair},
	{name="Super Missile (Gold Torizo)", addr=0x78E74, access=CanAccessLowerNorfair},
	{name="Screw Attack", addr=0x79110, access=CanAccessLowerNorfair},
	
	{name="Missile (Mickey Mouse room)", addr=0x78F30, access=CanAccessLowerNorfair},

	{name="Energy Tank (lower Norfair fire flea room)", addr=0x79184, access=CanAccessLowerNorfair},
	{name="Missile (lower Norfair above fire flea room)", addr=0x78FCA, access=CanAccessLowerNorfair},
	{name="Power Bomb (lower Norfair above fire flea room)", addr=0x78FD2, access=CanAccessLowerNorfair},
	
	-- spade shaped room?
	{name="Missile (lower Norfair near Wave Beam)", addr=0x79100, access=CanAccessLowerNorfair},
	
	{name="Power Bomb (above Ridley)", addr=0x790C0, access=CanAccessLowerNorfair},
	
	-- these constraints are really for what it takes to kill Ridley
	{name="Energy Tank (Ridley)", addr=0x79108, access=function() 
		return CanAccessLowerNorfair() 
		and EffectiveEnergyCount() >= 4 
		-- you don't need charge.  you can also kill him with a few hundred missiles
		and (req.charge or EffectiveMissileCount() >= 250)
	end},
	
	
	-- Wrecked Ship
	
	
	{name="Missile (Wrecked Ship middle)", addr=0x7C265, access=CanAccessWreckedShip},
	{name="Reserve Tank (Wrecked Ship)", addr=0x7C2E9, access=function() return CanDefeatPhantoon() and req.speed end},
	{name="Missile (Gravity Suit)", addr=0x7C2EF, access=CanDefeatPhantoon},
	{name="Missile (Wrecked Ship top)", addr=0x7C319, access=CanDefeatPhantoon},

	{name="Energy Tank (Wrecked Ship)", addr=0x7C337, access=function() 
		return CanDefeatPhantoon() 
		and (req.grappling or req.spacejump
			or EffectiveEnergyCount() >= 2
		) 
		--and req.gravity 
	end},
	
	{name="Super Missile (Wrecked Ship left)", addr=0x7C357, access=CanDefeatPhantoon},
	{name="Super Missile (Wrecked Ship right)", addr=0x7C365, access=CanDefeatPhantoon},
	{name="Gravity Suit", addr=0x7C36D, access=CanDefeatPhantoon},
	
	
	-- Maridia
	
	
	{name="Missile (green Maridia shinespark)", addr=0x7C437, access=function() return CanAccessOuterMaridia() and req.speed end},
	{name="Super Missile (green Maridia)", addr=0x7C43D, access=CanAccessOuterMaridia},
	{name="Energy Tank (green Maridia)", addr=0x7C47D, access=function() return CanAccessOuterMaridia() and (req.speed or req.grappling or req.spacejump) end},
	{name="Missile (green Maridia tatori)", addr=0x7C483, access=CanAccessOuterMaridia},

	-- top of maridia
	{name="Super Missile (yellow Maridia)", addr=0x7C4AF, access=CanAccessInnerMaridia},
	{name="Missile (yellow Maridia super missile)", addr=0x7C4B5, access=CanAccessInnerMaridia},
	{name="Missile (yellow Maridia false wall)", addr=0x7C533, access=CanAccessInnerMaridia},

	-- This item requires plasma *to exit*
	--  but this is no different from the super missile after spore spawn requiring super missile *to exit*
	-- so I propose to use a different constraint for items in these situations.
	-- Maybe I should make the randomizer to only put worthless items in these locations?
	--  Otherwise I can't make randomizations that don't include the plasma item. 
	{
		name = "Plasma Beam",
		addr = 0x7C559,
		access = function() 
			-- draygon must be defeated to unlock the door to plasma
			return CanDefeatDraygon() 
		end,
		escape = function()
			-- either one of these to kill the space pirates and unlock the door
			return (req.screwattack or req.plasma)
			-- getting in and getting out ...
			and (skills.touchAndGo or skills.bombTechnique or req.spacejump)
		end,
	},
	
	{name="Missile (left Maridia sand pit room)", addr=0x7C5DD, access=function() 
		return CanAccessOuterMaridia() 
		and (CanUseBombs() or CanUseSpringBall())
	end},

	-- also left sand pit room 
	{name="Reserve Tank (Maridia)", addr=0x7C5E3, access=function() 
		return CanAccessOuterMaridia() and (CanUseBombs() or CanUseSpringBall()) 
	end},
	
	{name="Missile (right Maridia sand pit room)", addr=0x7C5EB, access=CanAccessOuterMaridia},
	
	{name="Power Bomb (right Maridia sand pit room)", addr=0x7C5F1, access=CanAccessOuterMaridia},

	-- room with the shell things
	{name="Missile (pink Maridia)", addr=0x7C603, access=function() return CanAccessOuterMaridia() and req.speed end},
	{name="Super Missile (pink Maridia)", addr=0x7C609, access=function() return CanAccessOuterMaridia() and req.speed end},

	-- here's another fringe item
	-- requires grappling, but what if we put something unimportant there? who cares about it then?
	{name="Spring Ball", addr=0x7C6E5, access=function() 
		return CanAccessOuterMaridia() 
		and req.grappling 
		and (skills.touchAndGo or req.spacejump)
	end},

	-- missile right before draygon?
	{name="Missile (Draygon)", addr=0x7C74D, access=CanDefeatDraygon},

	-- energy tank right after botwoon
	{name="Energy Tank (Botwoon)", addr=0x7C755, access=CanDefeatBotwoon},
	
	-- technically you don't need gravity to get to this item 
	-- ... but you need it to escape Draygon's area
	{
		name = "Space Jump", 
		addr = 0x7C7A7, 
		access = function() 
			return CanDefeatDraygon() 
		end,
		escape = function()
			-- if the player knows the crystal-flash-whatever trick then fine
			return skills.DraygonCrystalFlashBlueSparkWhatever
			-- otherwise they will need both gravity and either spacejump or bombs
			or (req.gravity and (req.spacejump or CanUseBombs()))
		end,
	},
}
--]]


--[[
TODO prioritize placement of certain item locations last.
especially those that require certain items to escape from.
1) the super missile tank behind spore spawn that requires super missiles.  place that one last, or not at all, or else it will cause an early super missile placement.
2) plasma beam, will require a plasma beam placement
3) spring bill will require a grappling placement
4) pink Brinstar e-tank will require a wave placement
5) space jump requires space jump ... I guess lower norfair also does, if you don't know the suitless touch-and-go in the lava trick
... or another way to look at this ...
... choose item placement based on what the *least* number of future possibilities will be (i.e. lean away from placing items that open up the game quicker)
--]]

local function shuffle(x)
	local y = {}
	while #x > 0 do table.insert(y, table.remove(x, math.random(#x))) end
	while #y > 0 do table.insert(x, table.remove(y, math.random(#y))) end
	return x
end



local rom = file[infilename]
local header = ''
--header = rom:sub(1,512)
--rom = rom:sub(513)

local function rd2b(addr)
	return bit.bor(
		rom:sub(addr+1,addr+1):byte(),
		bit.lshift( rom:sub(addr+2,addr+2):byte(), 8))
end

local function wr2b(addr, value)
	rom = rom:sub(1, addr)
		.. string.char( bit.band(0xff, value) )
		.. string.char( bit.band(0xff, bit.rshift(value, 8)) )
		.. rom:sub(addr+3)
end



local itemTypes = table{
	energy 		= 0xeed7,
	missile 	= 0xeedb,
	supermissile = 0xeedf,
	powerbomb	= 0xeee3,
	bomb		= 0xeee7,
	charge		= 0xeeeb,
	ice			= 0xeeef,
	hijump		= 0xeef3,
	speed		= 0xeef7,
	wave		= 0xeefb,
	spazer 		= 0xeeff,
	springball	= 0xef03,
	varia		= 0xef07,
	plasma		= 0xef13,
	grappling	= 0xef17,
	morph		= 0xef23,
	reserve		= 0xef27,
	gravity		= 0xef0b,
	xray		= 0xef0f,
	spacejump 	= 0xef1b,
	screwattack	= 0xef1f,
}

-- add 84 = 0x54 to get to chozo , another 84 = 0x54 to hidden
local itemTypeBaseForType = {}
for _,k in ipairs(itemTypes:keys()) do
	local v = itemTypes[k]
	itemTypeBaseForType[v] = v
	itemTypes[k..'_chozo'] = v + 0x54
	itemTypeBaseForType[v + 0x54] = v
	itemTypes[k..'_hidden'] = v + 2*0x54
	itemTypeBaseForType[v + 2*0x54] = v
end

-- not completely working just yet
local doorTypes = table{
	door_blue_left = 0xc82a,
	door_blue_right = 0xc830,
	door_blue_up = 0xc836,
	door_blue_down = 0xc83c,
	
	door_grey_left = 0xc842,
	door_grey_right = 0xc848,
	door_grey_up = 0xc84e,
	door_grey_down = 0xc854,
	
	door_yellow_left = 0xc85a,
	door_yellow_right = 0xc860,
	door_yellow_up = 0xc866,
	door_yellow_down = 0xc86c,
	
	door_green_left = 0xc872,
	door_green_right = 0xc878,
	door_green_up = 0xc87e,
	door_green_down = 0xc884,
	
	door_red_left = 0xc88a,
	door_red_right = 0xc890,
	door_red_up = 0xc896,
	door_red_down = 0xc89c,
	
	door_blue_opening_left = 0xc8a2,
	door_blue_opening_right = 0xc8a8,
	door_blue_opening_up = 0xc8b4,
	door_blue_opening_down = 0xc8ae,
	
	door_blue_closing_left = 0xc8ba,
	door_blue_closing_right = 0xc8be,
	door_blue_closing_up = 0xc8c6,
	door_blue_closing_down = 0xc8c2,
}

local objNameForValue = table(
	itemTypes:map(function(v,k) return k,v end),
	doorTypes:map(function(v,k) return k,v end)
)
--local itemTypeValues = itemTypes:map(function(v,k,t) return v,#t+1 end)

local countsForType = table()
local itemInsts = table()
local doorInsts = table()

-- [[ build from object memory range
local function check(addr)
	local value = rd2b(addr)
	local name = objNameForValue[value]
	if name then
		countsForType[name] = (countsForType[name] or 0) + 1
		if itemTypes[name] then
			itemInsts:insert{addr=addr, value=value, name=name}
		elseif doorTypes[name] then
			doorInsts:insert{addr=addr, value=value, name=name}
		end	
	end
end
for addr=0x78000,0x79192,2 do check(addr) end
for addr=0x7c215,0x7c7bb,2 do check(addr) end
--]]
--[[ build from the loc database
itemInsts = locations:map(function(loc)
	local addr = loc.addr
	local value = rd2b(addr)
	return {addr=addr, value=value, name=objNameForValue[value]}
end)
--]]


--[[
item restrictions...
morph ball must be morph ball
blue brinstar bottom must be either missiles
	or super missiles, and blue brinstar right must be either missiles
		or power bombs, and blue brinstar top or blue brinstar behind top must be missiles
		or high jump, and blue brinstar energy must be missiles
--]]

-- [[ reveal all items
for _,item in ipairs(itemInsts) do
	local name = objNameForValue[item.value]
	name = name:gsub('_chozo', ''):gsub('_hidden', '')	-- remove all chozo and hidden status
	item.value = itemTypes[name]
end
--]]

print('found '..#itemInsts..' items')
print('found '..#doorInsts..' doors')
print(tolua(countsForType):gsub(', ', ',\n\t'))


--[[
args:
	changes = {[from] => [to]} key/value pairs
	args = extra args:
		leave = how many to leave
--]]
local function change(changes, args)
	local leave = (args and args.leave) or 0
	for from, to in pairs(changes) do
		local insts = itemInsts:filter(function(item) 
			return objNameForValue[item.value]:match('^'..from) 
		end)
		for i=1,leave do
			if #insts == 0 then break end
			insts:remove(math.random(#insts))	-- leave a single inst 
		end
		for _,item in ipairs(insts) do 
			item.value = itemTypes[to] 
		end
	end
end

-- [[ 
change({supermissile='missile'}, {leave=1})		-- turn all (but one) super missiles into missiles
change({powerbomb='missile'}, {leave=1}) 	-- turn all (but one) power bombs into missiles
change({energy='missile'}, {leave=6})
change{reserve='missile'}
change{spazer='missile'}
change{hijump='missile'}
change{xray='missile'}
change{springball='missile'}

-- beyond this point is retarded

local function removeLocation(locName, with)
	local loc = locations:remove(locations:find(nil, function(loc) 
		return loc.name == locName 
	end))
	local inst = itemInsts:remove(itemInsts:find(nil, function(inst) 
		return inst.addr == loc.addr 
	end))
	wr2b(inst.addr, itemTypes[with])
end

-- removing plasma means you must keep screwattack, or else you can't escape the plasma room and it'll stall the randomizer
-- the other fix is to just not consider the plasma location, and put something innocuous there ...
change{plasma='missile'}

-- this will stall the randomizer because of pink Brinstar energy tank
-- so lets remove it and write it as a missile
change{wave='missile'}
removeLocation("Energy Tank (pink Brinstar top)", 'missile')

-- grappling is only absolutely required to get into springball...
change{grappling='missile'}
removeLocation("Spring Ball", 'missile')

-- is this possible?  maybe you can't kill the golden chozo without charge, or a lot of super missiles ... or a lot of restocking on 5 super missiles and shooting them all off at him
--change{charge='missile'}

-- is this possible?  you will have a hard time escaping Draygon's room
--change{gravity='missile'}

-- only possible if you have enough e-tanks before hell runs
-- what this means is ... if the randomizer doesn't come up with a varia suit before hell run ... then it will be forced to place *all* energy tanks before hell run ... which might make a game that's too easy
--change{varia='missile'}

-- if you're replacing plasma item and screw attack item then you must remove plasma location ...
change{screwattack='missile'}
removeLocation('Plasma Beam', 'missile')

change{spacejump='missile'}

--]]
--[[
change{missile='supermissile'}						-- turn all missiles into super missiles (one is already left -- the first missile tank)
change({powerbomb='supermissile'}, {leave=1}) 		-- turn all but one power bombs into super missiles
change{spazer='supermissile', hijump='supermissile', springball='supermissile', reserve='supermissile', xray='supermissile'}	-- no need for these
change({energy='supermissile'}, {leave=7})
--]]

--[[ change all doors to blue
for _,door in ipairs(doorInsts) do
	--door.value = 
end
--]]




--[[
local itemInstValues = itemInsts:map(function(item) return item.value end)
shuffle(itemInstValues)
for i=1,#itemInsts do itemInsts[i].value = itemInstValues[i] end
--]]

--[[ filter out bombs and morph ball, so we know the run is possible 
itemInsts = itemInsts:filter(function(item)
	if item.addr ~= 0x786de		-- morph ball -- must be morph ball
	and item.addr ~= 0x78802	-- blue brinstar bottom -- must be either missiles or super missiles
	--and item.addr ~= 0x78798	-- blue brinstar middle -- if blue brinstar bottom isn't missiles then this must be missiles
	and item.addr ~= 0x78404	-- chozo bombs
	then
		return true
	end
end)
--]]


-- [[
local sofar = table{}
-- I could just change the 'req' references to 'sofar' references ...
-- notice I'm not using __index = sofar, because sofar itself is push'd / pop'd, so its pointer changes
req = setmetatable({}, {
	__index = function(t,k)
		return sofar[k]
	end,
})

-- deep copy, so the orginal itemInsts is intact
local origItems = itemInsts:map(function(inst) return inst.value end)
-- feel free to modify origItems to your hearts content ... like replacing all reserve tanks with missiles, etc

-- keep track of the remaining items to place -- via indexes into the original array
local itemInstIndexesLeft = range(#origItems)

local currentLocs = table(locations)

for _,loc in ipairs(locations) do
	loc.defaultValue = itemTypeBaseForType[rd2b(loc.addr)]
	loc.defaultName = objNameForValue[loc.defaultValue]
end

local replaceMap = {}

local function iterate(depth)
	depth = depth or 0
	local function dprint(...)
		io.write(('%3d%% '):format(depth))
		return print(...)
	end

	if #currentLocs == 0 then
		dprint'done!'
		return true
	end

	local chooseLocs = currentLocs:filter(function(loc)
		return loc.access()
	end)
	dprint('options to replace: '..tolua(chooseLocs:map(function(loc,i,t) return (t[loc.defaultName] or 0) + 1, loc.defaultName end)))

	-- pick an item to replace
	if #chooseLocs == 0 then 
		dprint('we ran out of options with '..#currentLocs..' items unplaced!')
		return
	end
	local chooseLoc = chooseLocs[math.random(#chooseLocs)]
	dprint('choosing to replace '..chooseLoc.name)
	
	-- remove it from the currentLocs list 
	local nextLocs = currentLocs:filter(function(loc) return chooseLoc ~= loc end)
	
	-- find an item to replace it with
	if #itemInstIndexesLeft == 0 then 
		dprint('we have no items left to replace it with!')
		os.exit()
	end
	
	for _,i in ipairs(shuffle(range(#itemInstIndexesLeft))) do
		local push_itemInstIndexesLeft = table(itemInstIndexesLeft)
		
		local replaceInstIndex = itemInstIndexesLeft:remove(i)
		local value = origItems[replaceInstIndex]
		local name = objNameForValue[value]
		dprint('...replacing '..chooseLoc.name..' with '..name)
				
		-- plan to write it 
		replaceMap[chooseLoc.addr] = {value=value, sofar=table(sofar)}
	
		-- now replace it with an item
		local push_sofar = table(sofar)
		sofar[name] = (sofar[name] or 0) + 1
	
		local push_currentLocs = table(currentLocs)
		currentLocs = nextLocs

		-- if the chooseLoc has an escape req, and it isn't satisfied, then don't iterate
		if chooseLoc.escape and not chooseLoc.escape() then
			dprint('...escape condition not met!')
		else
			dprint('iterating...')
			if iterate(depth + 1) then return true end	-- return 'true' when finished to exit out of all recursion
		end
		
		currentLocs = push_currentLocs
		sofar = push_sofar
		itemInstIndexesLeft = push_itemInstIndexesLeft
	end
end	

iterate()

print()
print()
print'summary:'
local longestName = locations:map(function(loc) return #loc.name end):sup()
local function score(loc)
	return table.values(replaceMap[loc.addr].sofar):sum() or 0
end
table(locations):sort(function(a,b) 
	return score(a) < score(b) 
end):map(function(loc)
	local addr = loc.addr
	local value = replaceMap[addr].value
	local sofar = replaceMap[addr].sofar
	print(loc.name
		..('.'):rep(longestName - #loc.name + 10)
		..objNameForValue[value]
		..'\t'..tolua(sofar))
	select(2, itemInsts:find(nil, function(inst) return inst.addr == addr end)).value = value
end)
--]]


for i,item in ipairs(itemInsts) do
	wr2b(item.addr, item.value)
end
--[[
for i,door in ipairs(doorInsts) do
	wr2b(door.addr, door.value)
end
--]]

file[outfilename] = header .. rom

print('done converting '..infilename..' => '..outfilename)
