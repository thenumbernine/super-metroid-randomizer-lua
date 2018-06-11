#!/usr/bin/env luajit
require 'ext'
local ffi = require 'ffi'
local template = require 'template'

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


local randomizeWeaknesses = true

-- what skills does the player know?
local skills = {
	
	-- this one covers a wide range
	-- there's the lower green Brinstar power bomb item, which has always required touch-and-go
	-- but there are several other locations which requier different degrees of skill of touch-and-go:
	-- 1) accessing upper red Brinstar, you need either hijump, spacejump, ice ... or you can just use touch-and-go (super missiles help, for clearing the monsters out of the way)
	-- 2) accessing Kraid without hijump or spacejump
	-- 3) lots more
	touchAndGo = true,
	touchAndGoToBoulderRoom = true,
	touchAndGoUpAlcatraz = true,

	bombTechnique = true,

	damageBoostToBrinstarEnergy = true,

	-- whether the player knows to use mockball to get into the green Brinstar item area
	-- I think that's the only place it's really necessary
	mockball = true,

	maridiaSuitSwap = true,

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


local function effectiveMissileCount()
	return (req.missile or 0) + 5 * (req.supermissile or 0)
end

local function effectiveEnergyCount() 
	return (req.energy or 0) + math.min((req.energy or 0) + 1, req.reserve or 0) 
end



--[[
locations fields:
	name = name of the *location* (unrelated to item name)
	addr = address of the item
	access = callback to determine what is required to access the item
	escape = callback to determine what is required to escape the room after accessing the item
	filter = callback to determine which items to allow here
--]]
local locations = table()


-- start run / pre-alarm items ...


	-- morph ball room:

locations:insert{
	name = "Morphing Ball", 
	addr = 0x786DE, 
	access = function() return true end, 
	-- looks like you always need morph in morph...
	--filter = function(name) return name ~= 'morph' end,
}

local function canUsePowerBombs() 
	return req.morph and req.powerbomb
end

-- power bombs behind power bomb wall near the morph ball 
locations:insert{name="Power Bomb (blue Brinstar)", addr=0x7874C, access=canUsePowerBombs}

	-- first missile room:

locations:insert{
	name = "Missile (blue Brinstar bottom)", 
	addr = 0x78802, 
	access = function() return req.morph end,
	-- but this doesn't have to be a missile =D
	--filter = function(name) return name ~= 'missile' end,
}

local function canOpenMissileDoors() 
	return req.missile 
	or req.supermissile 
end

	-- blue brinstar energy tank room:

local function accessBlueBrinstarEnergyTankRoom() 
	return canOpenMissileDoors()
end

-- second missile tank you get
locations:insert{
	name="Missile (blue Brinstar middle)", 
	addr=0x78798, 
	access=function() 
		return accessBlueBrinstarEnergyTankRoom() 
		and req.morph 
	end,
	-- also doesn't have to be a missile =D
	--filter = function(name) return name ~= 'missile' end,
}

	-- blue brinstar double missile room (behind boulder room):

local function accessBlueBrinstarDoubleMissileRoom()
	-- get in the door
	return canOpenMissileDoors()
	-- get through the power bomb blocks
	and canUsePowerBombs()
	-- if you can already use powerbombs then you can get up the top.  touch and go replaces spacejump / speed boost
	and (
		-- get upstrairs
		skills.touchAndGoToBoulderRoom
		or req.speed
		or req.spacejump
	)
end

locations:insert{name="Missile (blue Brinstar top)", addr=0x78836, access=accessBlueBrinstarDoubleMissileRoom}
locations:insert{name="Missile (blue Brinstar behind missile)", addr=0x7883C, access=accessBlueBrinstarDoubleMissileRoom}

local function canUseBombs() 
	return req.morph and req.bomb
end

local function canBombTechnique()
	return skills.bombTechnique and canUseBombs()
end

-- can you get up to high areas using a runway
local function canGetUpWithRunway()
	return req.speed
	or req.spacejump
	or canBombTechnique()
end

-- in order for the alarm to activate, you need to collect morph and a missile tank and go to some room in crateria.
local function canActivateAlarm()
	return req.morph and req.missile
end

locations:insert{name="Energy Tank (blue Brinstar)", addr=0x7879E, access=function() 
	return accessBlueBrinstarEnergyTankRoom() 
	and (
		-- how to get up?
		req.hijump 
		or canGetUpWithRunway()
		-- technically you can use a damage boost, so all you really need is missiles
		--  however this doesn't work until after security is activated ...
		or (skills.damageBoostToBrinstarEnergy and canActivateAlarm())
	)
end}

	-- Crateria pit room:

-- bomb walls that must be morphed:
local function canDestroyBombWallsMorphed()
	return canUseBombs()
	or canUsePowerBombs() 
end

-- bomb walls that can be destroyed without needing to morph 
local function canDestroyBombWallsStanding() 
	return req.screwattack 
	or canDestroyBombWallsMorphed()
end

-- this is the missile tank under old mother brain 
-- here's one that, if you choose morph => screw attack, then your first missiles could end up here
--  however ... unless security is activated, this item will not appear
-- so either (a) deactivate security or (b) require morph and 1 missile tank for every item after security
locations:insert{name="Missile (Crateria bottom)", addr=0x783EE, access=function()
	-- alarm needs to be activated or the missile won't appear
	return canActivateAlarm() 
	and canDestroyBombWallsStanding()
end}


	-- Bomb Torizo room:


-- this is another one of those, like plasma and the spore spawn super missiles, where there's no harm if we cut it off, because you need the very item to leave its own area
locations:insert{
	name = "Bomb",
	addr = 0x78404, 
	access = function() 
		return canActivateAlarm()
		and canOpenMissileDoors() 
	end,
	escape = function()
		return skills.touchAndGoUpAlcatraz 
		or canDestroyBombWallsMorphed()
	end,
}

	-- Final missile bombway:

locations:insert{name="Missile (Crateria middle)", addr=0x78486, access=function()
	return canDestroyBombWallsMorphed()
	-- without the alarm, this item is replaced with a security scanner
	and canActivateAlarm()
end}

	-- Terminator room:

-- bomb walls that can be destroyed and have a runway nearby
local function canDestroyBombWallsWithRunway()
	return req.speed
	or canDestroyBombWallsStanding()
end

local function accessTerminator()
	-- accessing terminator from the regular entrance
	return canActivateAlarm()
	and canDestroyBombWallsWithRunway()
end

locations:insert{name="Energy Tank (Crateria tunnel to Brinstar)", addr=0x78432, access=accessTerminator}


-- Crateria surface


local function accessPinkBrinstarFromLeft()
	return
	-- get into terminator
	accessTerminator() 
	-- get through missile door of green brinstar main shaft
	and canOpenMissileDoors()
	-- use bombs, power bombs, screw attack, or speed booster to enter pink Brinstar
	and canDestroyBombWallsWithRunway()
end

-- notice, you can enter pink brinstar from the right with only power bombs
-- ... but you can't leave without getting super missiles ...
local function accessPinkBrinstarFromRight()
	-- power bomb from the morph ball room
	return canUsePowerBombs()
end


local function accessLandingRoom()
	-- going up the normal way
	return canActivateAlarm()
	-- or going up the power bomb way
		-- get to pink brinstar from the right side...
	or (accessPinkBrinstarFromRight()
		-- then get through the bombable wall to the left
		and canDestroyBombWallsWithRunway()
		-- go up the elevator ...
		-- then up terminator
		-- then through the terminator wall
		-- and tata, you're at the surface
	)
end

	-- Crateria power bomb room:

locations:insert{name="Power Bomb (Crateria surface)", addr=0x781CC, access=function() 
	-- get back to the surface
	return accessLandingRoom()
	-- to get up there
	and canGetUpWithRunway()
	-- to get in the door
	and canUsePowerBombs()
end}

	-- Crateria gauntlet:

-- so technically ...
-- you need either bombs, or you need speed + 5 powerbombs to enter ...
-- then you need either bombs or another 5 power bombs to exit
local function accessGauntlet()
	-- getting (back from morph) to the start room
	return accessLandingRoom()
	-- getting up
	and canGetUpWithRunway()
	-- getting through the bombable walls
	and (
		-- either something to destroy it while standing...
		-- screw attack...
		req.screwattack
		-- bombs...
		or canUseBombs()
		-- it takes 3 power bombs (no pull-through walls) to get through the first gauntlet room
		or (req.morph and (req.powerbomb or 0) >= 1)
		-- speed boost from the landing site through the door
		or (req.speed and (req.energy or 0) >= 3)	-- it takes 213 energy from the upper right plateau to go through the first gauntlet room 
	)
end

-- right now escape()'s are only constrained one item at a time
-- maybe I need separate functions ... 
-- ... one for escaping the way you came (energy tank escape() function)
-- ... and one for entering into the second gauntlet room ...are the constraints any different from escaping the way you came?
local function escapeGauntletFirstRoom()
	return req.screwattack
	or canUseBombs()
	-- it takes another 3 power bombs to get back the way we came ...
	-- or another 4 to get through second gauntlet room
	or (req.morph and (req.powerbomb or 0) >= 2)
end

local function accessGauntletSecondRoom()
	return accessGauntlet() and escapeGauntletFirstRoom()
end

-- here's another escape condition shared between items: only one of the two green pirate shaft items needs to be morph
local function escapeGreenPirateShaftItems()
	return req.morph
end

locations:insert{name="Energy Tank (Crateria gauntlet)", addr=0x78264, access=accessGauntlet, escape=escapeGauntletFirstRoom}

	-- Green pirate shaft

locations:insert{name="Missile (Crateria gauntlet right)", addr=0x78464, access=accessGauntletSecondRoom, escape=escapeGreenPirateShaftItems}
locations:insert{name="Missile (Crateria gauntlet left)", addr=0x7846A, access=accessGauntletSecondRoom, escape=escapeGreenPirateShaftItems}

-- speed boost area ... don't you need ice? nahhh, but you might need to destroy the jumping monsters if you don't have ice 
locations:insert{name="Super Missile (Crateria)", addr=0x78478, access=function() 
	-- power bomb doors
	return canUsePowerBombs() 
	-- speed boost blocks
	and req.speed 
	-- escaping over the spikes
	and (effectiveEnergyCount() >= 1 or req.varia or req.gravity or req.grappling)
	-- killing / freezing the monsters? ... well, you already need power bombs 
end}


-- green Brinstar


local accessEnterGreenBrinstar = accessTerminator

	-- early supers room:

locations:insert{name="Missile (green Brinstar below super missile)", addr=0x78518, access=function() 
	return accessEnterGreenBrinstar()
	-- missile door to enter room
	and canOpenMissileDoors() 
end, escape=function()
	-- because you need to morph and bomb to get out ... 
	return canDestroyBombWallsMorphed()	
end}

-- accessing the items & escaping through the top ...
local function accessEarlySupersRoomItems()
	return accessEnterGreenBrinstar()
	and canOpenMissileDoors() 
	-- missiles and mockball/speed to get up to it ...
	and (skills.mockball or req.speed)
	-- getting up to exit ...
	and (skills.touchAndGo or req.hijump)
end

locations:insert{name="Super Missile (green Brinstar top)", addr=0x7851E, access=accessEarlySupersRoomItems}

	-- Brinstar reserve tank room:

locations:insert{name="Reserve Tank (Brinstar)", addr=0x7852C, access=accessEarlySupersRoomItems}

local function accessBrinstarReserveMissile()
	return accessEarlySupersRoomItems()
	-- takes morph to get to the item ...
	and req.morph 
end

locations:insert{name="Missile (green Brinstar behind Reserve Tank)", addr=0x78538, access=accessBrinstarReserveMissile}

locations:insert{name="Missile (green Brinstar behind missile)", addr=0x78532, access=function()
	return accessBrinstarReserveMissile()
	-- takes morph + power/bombs to get to this item ...
	and canDestroyBombWallsMorphed()
end}

	-- etecoon energy tank room:
local accessEtecoons = canUsePowerBombs

-- takes power bombs to get through the floor
locations:insert{name="Energy Tank (green Brinstar bottom)", addr=0x787C2, access=accessEtecoons}

locations:insert{name="Super Missile (green Brinstar bottom)", addr=0x787D0, access=function() 
	return accessEtecoons() 
	-- it's behind one more super missile door
	and req.supermissile 
end}

locations:insert{name="Power Bomb (green Brinstar bottom)", addr=0x784AC, access=function()
	return accessEtecoons()
	-- technically ...
	-- and skills.touchAndGo	-- except you *always* need touch-and-go to get this item ...
	-- and technically you need morph, but you already need it to power bomb through the floor to get into etecoon area
end}


-- pink Brinstar


-- this is for accessing post-bomb-wall pink-brinstar
local function accessPinkBrinstar()
	-- accessing it from the left entrance:
	return accessPinkBrinstarFromLeft()
	-- accessing from the right entrance
	or accessPinkBrinstarFromRight()
end

	-- Spore Spawn super room

locations:insert{
	name = "Super Missile (pink Brinstar)", 
	addr = 0x784E4, 
	access=function() 
		-- getting into pink brinstar
		return accessPinkBrinstar() 
		-- getting into spore spawn
		and canOpenMissileDoors()
	end,
	escape = function()
		return req.supermissile
		and req.morph
	end
}

local function accessMissilesAtTopOfPinkBrinstar()
	return accessPinkBrinstar()
	and (
		skills.touchAndGo 
		or canBombTechnique()
		or req.grappling 
		or req.spacejump 
		or req.speed
	)
end

locations:insert{name="Missile (pink Brinstar top)", addr=0x78608, access=accessMissilesAtTopOfPinkBrinstar}

locations:insert{name="Power Bomb (pink Brinstar)", addr=0x7865C, access=function() 
	return accessMissilesAtTopOfPinkBrinstar()
	-- behind power bomb blocks
	and canUsePowerBombs() 
	-- behind a super missile block
	and req.supermissile 
end}

locations:insert{name="Missile (pink Brinstar bottom)", addr=0x7860E, access=function() 
	return accessPinkBrinstar() 
end}

local function accessCharge()
	return accessPinkBrinstar() and canDestroyBombWallsMorphed()
end

locations:insert{name="Charge Beam", addr=0x78614, access=accessCharge}

-- doesn't really need gravity, just helps
locations:insert{name="Energy Tank (pink Brinstar bottom)", addr=0x787FA, access=function() 
	-- get to the charge room
	return accessCharge()
	-- power bomb block
	and canUsePowerBombs() 
	-- missile door
	and canOpenMissileDoors() 
	-- speed booster
	and req.speed 
	-- maybe gravity to get through the water
	and (skills.shortSpeedBoost or req.gravity)
end}

local function canGetBackThroughBlueGates()
	return (skills.superMissileGateGlitch and req.supermissile) or req.wave
end

-- the only thing that needs wave:
locations:insert{name="Energy Tank (pink Brinstar top)", addr=0x78824, access=function() 
	return accessPinkBrinstar()
	and canUsePowerBombs() 
	and canGetBackThroughBlueGates()
end}


-- right side of Brinstar (lower green, red, Kraid, etc)


local function accessLowerGreenBrinstar()
	-- technically you can either access pink Brinstar from the left side ...
	-- ... and exit via super missile door
	-- ... or enter via power bombs through the morph ball room
	return (accessPinkBrinstarFromLeft() and req.supermissile)
	or accessPinkBrinstarFromRight()
end

locations:insert{name="Missile (green Brinstar pipe)", addr=0x78676, access=function() 
	return accessLowerGreenBrinstar()
	and (skills.touchAndGo or req.hijump or req.spacejump) 
end}

-- what it takes to get into lower green Brinstar, and subsequently red Brinstar
-- either a supermissile through the pink Brinstar door
-- or a powerbomb through the blue Brinstar below Crateria entrance
local function accessRedBrinstar() 
	return canActivateAlarm()
	and accessLowerGreenBrinstar()
	and (req.supermissile or canUsePowerBombs())
end

locations:insert{name="X-Ray Visor", addr=0x78876, access=function()
	return accessRedBrinstar() 
	and canUsePowerBombs() 
	and (
		req.grappling 
		or req.spacejump 
		or (effectiveEnergyCount() >= 5 and canUseBombs() and skills.bombTechnique)
	)
end}

-- red Brinstar top:

-- upper red Brinstar is the area of the first powerbomb you find, with the missile tank behind it, and the jumper room next to it
-- notice that these items require an on-escape to be powerbombs 
-- ... or else you get stuck in upper red Brinstar
-- however this escape condition is unique, because it is spread among two items
--  either the power bomb must be a powerbomb to escape
--  or you must have super missiles beforehand, and the super missile must be a powerbomb
-- I will implement this as requiring the escape-condition of the power bomb to be to have power bombs
local function accessUpperRedBrinstar()
	return accessRedBrinstar()
	and (
		-- you can freeze the monsters and jump off of them
		req.ice 
		-- or you can super missile them and touch-and-go up
		or (skills.touchAndGo and req.supermissile) 
		-- or you can destroy them (with super missiles or screw attack) and either bomb technique or spacejump up
		or (
			(req.screwattack or req.supermissile) 
			and (skills.bombTechnique or req.spacejump)
		)
	)
end

-- behind a super missile door
-- you don't need power bombs to get this, but you need power bombs to escape this area
-- another shared exit constraint...
locations:insert{
	name = "Power Bomb (red Brinstar spike room)", 
	addr = 0x7890E, 
	access = function() 
		return accessUpperRedBrinstar() and req.supermissile
	end,
	escape = function()
		return canUsePowerBombs()
	end,
}

-- behind a powerbomb wall 
locations:insert{name="Missile (red Brinstar spike room)", addr=0x78914, access=function() 
	return accessUpperRedBrinstar() and canUsePowerBombs() 
end}

-- super missile door, power bomb floor
locations:insert{name="Power Bomb (red Brinstar sidehopper room)", addr=0x788CA, access=function() 
	return accessUpperRedBrinstar() and req.supermissile and canUsePowerBombs() 
end}

-- red Brinstar bottom:

locations:insert{name="Spazer", addr=0x7896E, access=function() 
	-- getting there:
	return accessRedBrinstar() 
	-- getting up:
	and (skills.touchAndGo or skills.bombTechnique or req.spacejump or req.hijump) 
	-- getting over:
	and canDestroyBombWallsMorphed() 
	-- supermissile door:
	and req.supermissile
end}

local function accessKraid() 
	return accessRedBrinstar() 
	and (skills.touchAndGo or req.spacejump or req.hijump) 
	and canDestroyBombWallsMorphed() 
end

locations:insert{name="Missile (Kraid)", addr=0x789EC, access=function() 
	return accessKraid() and canUsePowerBombs() 
end}

-- accessible only after kraid is killed
locations:insert{name="Energy Tank (Kraid)", addr=0x7899C, access=accessKraid}

locations:insert{name="Varia Suit", addr=0x78ACA, access=accessKraid}


-- Norfair


local accessEnterNorfair = accessRedBrinstar

locations:insert{name="Hi-Jump Boots", addr=0x78BAC, access=function() return accessEnterNorfair() end}
locations:insert{name="Missile (Hi-Jump Boots)", addr=0x78BE6, access=accessEnterNorfair}
locations:insert{name="Energy Tank (Hi-Jump Boots)", addr=0x78BEC, access=accessEnterNorfair}

local function accessHeatedNorfair() 
	return accessEnterNorfair() 
	and (
		-- you either need a suit
		req.varia 
		or req.gravity
		-- or, if you want to do hellrun ...
		or (skills.hellrun 
			-- ... with high jump / space jump ... how many does this take?
			and effectiveEnergyCount() >= 4 
			and (req.hijump 
				or req.spacejump 
				-- without high jump and without suits it takes about 7 energy tanks
				or (canUseBombs() and effectiveEnergyCount() >= 7)
			)
		)
	) 
	-- idk that you need these ... maybe you need some e-tanks, but otherwise ...
	--and (req.spacejump or req.hijump) 
end

locations:insert{name="Missile (lava room)", addr=0x78AE4, access=accessHeatedNorfair}

local function accessIce()
	return accessKraid() 
	-- super missile door
	and req.supermissile
	-- speed / lowering barriers
	and (skills.mockball or req.speed)
	-- get through the heat
	and (req.gravity 
		or req.varia
		or (skills.hellrun and effectiveEnergyCount() >= 4)
	)
end

locations:insert{name="Ice Beam", addr=0x78B24, access=accessIce} 

local function accessMissilesUnderIce()
	return accessIce() and canUsePowerBombs() 
end

locations:insert{name="Missile (below Ice Beam)", addr=0x78B46, access=accessMissilesUnderIce}

-- crocomire takes either wave on the rhs or speed booster and power bombs on the lhs
local function accessCrocomire() 
	-- access crocomire from lhs
	return (accessMissilesUnderIce() and req.speed)
	-- access crocomire from flea run
	or (req.speed and req.wave)
	-- access crocomire from hell run / bubble room
	or (accessHeatedNorfair() and req.wave)
end

locations:insert{name="Energy Tank (Crocomire)", addr=0x78BA4, access=accessCrocomire}
locations:insert{name="Missile (above Crocomire)", addr=0x78BC0, access=accessCrocomire}

locations:insert{name="Power Bomb (Crocomire)", addr=0x78C04, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or req.grappling
		or req.speed
		or req.ice
		or skills.bombTechnique
	)
end}

locations:insert{name="Missile (below Crocomire)", addr=0x78C14, access=accessCrocomire}

locations:insert{name="Missile (Grappling Beam)", addr=0x78C2A, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or req.grappling 
		or req.speed
		or skills.bombTechnique
	)
end}

locations:insert{name="Grappling Beam", addr=0x78C36, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or (req.speed and req.hijump)
		or skills.bombTechnique
	) 
end}

locations:insert{name="Missile (bubble Norfair)", addr=0x78C66, access=accessHeatedNorfair}
locations:insert{name="Missile (Speed Booster)", addr=0x78C74, access=accessHeatedNorfair}
locations:insert{name="Speed Booster", addr=0x78C82, access=accessHeatedNorfair}
locations:insert{name="Missile (Wave Beam)", addr=0x78CBC, access=accessHeatedNorfair}

locations:insert{
	name = "Wave Beam",
	addr = 0x78CCA, 
	access = function()
		return accessHeatedNorfair() 
		-- or take some damange and use touch and go ...
		--and (req.spacejump or req.grappling)
	end,
	-- on the way back, you need to go thruogh the top gate, or morph to go through the bottom ...
	escape = function()
		return canGetBackThroughBlueGates() or req.morph
	end,
}

local function accessNorfairReserve()
	return accessHeatedNorfair() 
	and (req.spacejump 
		or req.grappling
		or (skills.touchAndGo and (req.hijump or req.ice))
	)
end

-- upper bubble room ... probably needs high jump or ice ... 
locations:insert{name="Missile (bubble Norfair green door)", addr=0x78C52, access=accessNorfairReserve}
locations:insert{name="Reserve Tank (Norfair)", addr=0x78C3E, access=accessNorfairReserve}
locations:insert{name="Missile (Norfair Reserve Tank)", addr=0x78C44, access=accessNorfairReserve}


-- lower Norfair


local function accessLowerNorfair() 
	return accessHeatedNorfair() 
	-- powerbomb door
	and req.powerbomb 
	and (
		-- gravity and space jump is the default option
		(req.gravity and req.spacejump)
		-- you can do it without gravity, but you need precise touch and go, and you need high jump, and enough energy
		or (skills.preciseTouchAndGoLowerNorfair and req.hijump and effectiveEnergyCount() >= 7)
		-- you can do without space jump if you have gravity and high jump -- suit swap
		or (req.gravity and skills.lowerNorfairSuitSwap)
	)
end

locations:insert{name="Missile (Gold Torizo)", addr=0x78E6E, access=accessLowerNorfair}
locations:insert{name="Super Missile (Gold Torizo)", addr=0x78E74, access=accessLowerNorfair}
locations:insert{name="Screw Attack", addr=0x79110, access=accessLowerNorfair}

locations:insert{name="Missile (Mickey Mouse room)", addr=0x78F30, access=accessLowerNorfair}

locations:insert{name="Energy Tank (lower Norfair fire flea room)", addr=0x79184, access=accessLowerNorfair}
locations:insert{name="Missile (lower Norfair above fire flea room)", addr=0x78FCA, access=accessLowerNorfair}
locations:insert{name="Power Bomb (lower Norfair above fire flea room)", addr=0x78FD2, access=accessLowerNorfair}

-- spade shaped room?
locations:insert{name="Missile (lower Norfair near Wave Beam)", addr=0x79100, access=accessLowerNorfair}

locations:insert{name="Power Bomb (above Ridley)", addr=0x790C0, access=accessLowerNorfair}

-- these constraints are really for what it takes to kill Ridley
locations:insert{name="Energy Tank (Ridley)", addr=0x79108, access=function() 
	return accessLowerNorfair() 
	and effectiveEnergyCount() >= 4 
	-- you don't need charge.  you can also kill him with a few hundred missiles
	and (req.charge or effectiveMissileCount() >= 250)
end}


-- Wrecked Ship


-- on the way to wrecked ship
locations:insert{name="Missile (Crateria moat)", addr=0x78248, access=function() 
	-- you just need to get through the doors, from there you can jump across
	return req.supermissile and req.powerbomb 
end}

local function accessWreckedShip() 
	return 
	-- super missile door from crateria surface
	-- ... or super missile door through pink Brinstar
	req.supermissile 
	-- power bomb door with the flying space pirates in it
	and canUsePowerBombs() 
	-- getting across the water
	and (skills.canJumpAcrossEntranceToWreckedShip or req.spacejump or req.grappling or req.speed)
end

locations:insert{name="Missile (outside Wrecked Ship bottom)", addr=0x781E8, access=accessWreckedShip}
locations:insert{name="Missile (Wrecked Ship middle)", addr=0x7C265, access=accessWreckedShip}

local function canDefeatPhantoon() 
	return accessWreckedShip() 
	and req.charge 
	and (req.gravity or req.varia or effectiveEnergyCount() >= 2) 
end

locations:insert{name="Missile (outside Wrecked Ship top)", addr=0x781EE, access=canDefeatPhantoon}
locations:insert{name="Missile (outside Wrecked Ship middle)", addr=0x781F4, access=canDefeatPhantoon}
locations:insert{name="Reserve Tank (Wrecked Ship)", addr=0x7C2E9, access=function() return canDefeatPhantoon() and req.speed end}
locations:insert{name="Missile (Gravity Suit)", addr=0x7C2EF, access=canDefeatPhantoon}
locations:insert{name="Missile (Wrecked Ship top)", addr=0x7C319, access=canDefeatPhantoon}

locations:insert{name="Energy Tank (Wrecked Ship)", addr=0x7C337, access=function() 
	return canDefeatPhantoon() 
	and (req.grappling or req.spacejump
		or effectiveEnergyCount() >= 2
	) 
	--and req.gravity 
end}

locations:insert{name="Super Missile (Wrecked Ship left)", addr=0x7C357, access=canDefeatPhantoon}
locations:insert{name="Super Missile (Wrecked Ship right)", addr=0x7C365, access=canDefeatPhantoon}
locations:insert{name="Gravity Suit", addr=0x7C36D, access=canDefeatPhantoon}


-- Maridia


local function accessOuterMaridia() 
	-- get to red brinstar
	return accessRedBrinstar() 
	-- break through the tube
	and req.powerbomb 
	-- now to get up ...
	and (
		-- if you have gravity, you can get up with touch-and-go, spacejump, hijump, or bomb technique
		(req.gravity and (
			-- you need touch-and-go to get to the balooon grappling room ... but you need suit-swap to get past it ...
			skills.maridiaSuitSwap --skills.touchAndGo 
			or req.spacejump 
			or req.hijump or (skills.bombTechnique and canUseBombs())))
		-- if you don't have gravity then you need high jump and ice.  without gravity you do need high jump just to jump up from the tube that you break, into the next room.
		or (skills.suitlessMaridiaFreezeCrabs and req.hijump and req.ice)
		
		-- suitless is possible so long as the space jump item is replaced with gravity suit to get out of Draygon's room ... or you do the crystal spark + blue spark + whatever move that I don't know how to do
	)
end

locations:insert{name="Missile (green Maridia shinespark)", addr=0x7C437, access=function() return accessOuterMaridia() and req.speed end}
locations:insert{name="Super Missile (green Maridia)", addr=0x7C43D, access=accessOuterMaridia}
locations:insert{name="Energy Tank (green Maridia)", addr=0x7C47D, access=function() return accessOuterMaridia() and (req.speed or req.grappling or req.spacejump) end}
locations:insert{name="Missile (green Maridia tatori)", addr=0x7C483, access=accessOuterMaridia}

local function accessInnerMaridia() 
	return accessOuterMaridia() 
	and (req.spacejump or req.grappling or req.speed or (req.gravity and skills.touchAndGo)) 
end

-- top of maridia
locations:insert{name="Super Missile (yellow Maridia)", addr=0x7C4AF, access=accessInnerMaridia}
locations:insert{name="Missile (yellow Maridia super missile)", addr=0x7C4B5, access=accessInnerMaridia}
locations:insert{name="Missile (yellow Maridia false wall)", addr=0x7C533, access=accessInnerMaridia}

local function canDefeatBotwoon() 
	return accessInnerMaridia() 
	and (
		(skills.botwoonFreezeGlitch and req.ice) 
		-- need to speed boost underwater
		or (req.gravity and req.speed)
		or skills.DraygonCrystalFlashBlueSparkWhatever
	)
end

local function canDefeatDraygon() 
	return canDefeatBotwoon() 
	and effectiveEnergyCount() >= 3 
	-- can't use space jump or bombs underwater without gravity
	and req.gravity
	and (canUseBombs() or req.spacejump)
end

-- This item requires plasma *to exit*
--  but this is no different from the super missile after spore spawn requiring super missile *to exit*
-- so I propose to use a different constraint for items in these situations.
-- Maybe I should make the randomizer to only put worthless items in these locations?
--  Otherwise I can't make randomizations that don't include the plasma item. 
locations:insert{
	name = "Plasma Beam",
	addr = 0x7C559,
	access = function() 
		-- draygon must be defeated to unlock the door to plasma
		return canDefeatDraygon() 
	end,
	escape = function()
		-- either one of these to kill the space pirates and unlock the door
		return (req.screwattack or req.plasma)
		-- getting in and getting out ...
		and (skills.touchAndGo or skills.bombTechnique or req.spacejump)
	end,
}

local function canUseSpringBall()
	return req.morph and req.springball
end

locations:insert{name="Missile (left Maridia sand pit room)", addr=0x7C5DD, access=function() 
	return accessOuterMaridia() 
	and (canUseBombs() or canUseSpringBall())
end}

-- also left sand pit room 
locations:insert{name="Reserve Tank (Maridia)", addr=0x7C5E3, access=function() 
	return accessOuterMaridia() and (canUseBombs() or canUseSpringBall()) 
end}

locations:insert{name="Missile (right Maridia sand pit room)", addr=0x7C5EB, access=accessOuterMaridia}
locations:insert{name="Power Bomb (right Maridia sand pit room)", addr=0x7C5F1, access=accessOuterMaridia}

-- room with the shell things
locations:insert{name="Missile (pink Maridia)", addr=0x7C603, access=function() return accessOuterMaridia() and req.speed end}
locations:insert{name="Super Missile (pink Maridia)", addr=0x7C609, access=function() return accessOuterMaridia() and req.speed end}

-- here's another fringe item
-- requires grappling, but what if we put something unimportant there? who cares about it then?
locations:insert{name="Spring Ball", addr=0x7C6E5, access=function() 
	return accessOuterMaridia() 
	and req.grappling 
	and (skills.touchAndGo or req.spacejump)
end}

-- missile right before draygon?
locations:insert{name="Missile (Draygon)", addr=0x7C74D, access=canDefeatDraygon}

-- energy tank right after botwoon
locations:insert{name="Energy Tank (Botwoon)", addr=0x7C755, access=canDefeatBotwoon}

-- technically you don't need gravity to get to this item 
-- ... but you need it to escape Draygon's area
locations:insert{
	name = "Space Jump", 
	addr = 0x7C7A7, 
	access = function() 
		return canDefeatDraygon() 
	end,
	escape = function()
		-- if the player knows the crystal-flash-whatever trick then fine
		return skills.DraygonCrystalFlashBlueSparkWhatever
		-- otherwise they will need both gravity and either spacejump or bombs
		or (req.gravity and (req.spacejump or canUseBombs()))
	end,
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

local function pickRandom(t)
	return t[math.random(#t)]
end

local function shuffle(x)
	local y = {}
	while #x > 0 do table.insert(y, table.remove(x, math.random(#x))) end
	while #y > 0 do table.insert(x, table.remove(y, math.random(#y))) end
	return x
end


local romstr = file[infilename]
local header = ''
--header = romstr:sub(1,512)
--romstr = romstr:sub(513)

local rom = ffi.cast('uint8_t*', romstr) 

local function readShort(addr)
	return ffi.cast('uint16_t*', rom+addr)[0]
end

local function writeShort(addr, value)
	ffi.cast('uint16_t*', rom+addr)[0] = value
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
	local value = readShort(addr)
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
	local value = readShort(addr)
	return {addr=addr, value=value, name=objNameForValue[value]}
end)
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


--[[  change items around


change({supermissile='missile'}, {leave=1})		-- turn all (but one) super missiles into missiles
change({powerbomb='missile'}, {leave=1}) 	-- turn all (but one) power bombs into missiles
change({energy='missile'}, {leave=6})
change{reserve='missile'}
change{spazer='missile'}
change{hijump='missile'}
change{xray='missile'}
change{springball='missile'}

local function removeLocation(locName, with)
	local loc = locations:remove(locations:find(nil, function(loc) 
		return loc.name == locName 
	end))
	local inst = itemInsts:remove(itemInsts:find(nil, function(inst) 
		return inst.addr == loc.addr 
	end))
	writeShort(inst.addr, itemTypes[with])
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
change{varia='missile'}

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


-- [[ placement algorithm:


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
	loc.defaultValue = itemTypeBaseForType[readShort(loc.addr)]
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
		
		if not chooseLoc.filter
		or chooseLoc.filter(name)
		then
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
		end
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

local addrbase = 0xf8000

-- one array is from 0xf8000 +0xcebf to +0xf0ff
local enemyStart = addrbase + 0xcebf
local enemyCount = (0xf0ff - 0xcebf) / 0x40 + 1
-- another is from +0xf153 to +0xf793 (TODO)
local enemy2Start = addrbase + 0xf153
local enemy2Count = (0xf793 - 0xf153) / 0x40 + 1
ffi.cdef[[
typedef uint8_t uint24_t[3];
]]
local enemyFields = {
	{tileDataSize = 'uint16_t'},
	{palette = 'uint16_t'},
	{health = 'uint16_t'},
	{damage = 'uint16_t'},
	{width = 'uint16_t'},
	{height = 'uint16_t'},
	{bank = 'uint8_t'},
	{hurtAITime = 'uint8_t'},
	{sound = 'uint16_t'},
	{bossValue = 'uint16_t'},
	{initiationAI = 'uint16_t'},
	{numParts = 'uint16_t'},
	{unused = 'uint16_t'},
	{graphAI = 'uint16_t'},
	{grappleAI = 'uint16_t'},
	{specialEnemyShot = 'uint16_t'},
	{frozenAI = 'uint16_t'},
	{xrayAI = 'uint16_t'},
	{deathAnimation = 'uint16_t'},
	{unused = 'uint32_t'},
	{powerBombReaction = 'uint16_t'},
	{unknown = 'uint16_t'},
	{unused2 = 'uint32_t'},
	{enemyTouch = 'uint16_t'},
	{enemyShot = 'uint16_t'},
	{unknown2 = 'uint16_t'},
	{tileData = 'uint24_t'},
	{layer = 'uint8_t'},
	{itemdrop = 'uint16_t'},
	-- pointer 
	{weakness = 'uint16_t'},
	{name = 'uint16_t'},
}

local code = template([[
struct enemy_s {
<? for _,kv in ipairs(enemyFields) do
	local name,ctype = next(kv)
?>	<?=ctype?> <?=name?>;
<? end
?>} __attribute__((packed));
typedef struct enemy_s enemy_t;
]], {enemyFields=enemyFields})
ffi.cdef(code)

local enemyAddrs = range(0,enemyCount-1):map(function(i)
	return enemyStart + ffi.sizeof'enemy_t' * i
end):append(range(0,enemy2Count-1):map(function(i)
	return enemy2Start + ffi.sizeof'enemy_t' * i
end))


local weaknessAddrs
if randomizeWeaknesses then
	weaknessAddrs = enemyAddrs:map(function(addr)
		return true, ffi.cast('enemy_t*', rom+addr)[0].weakness
	end):keys():sort()
	
	print('weakness addrs:')
	for _,addr in ipairs(weaknessAddrs) do
		io.write('  '..('0x%04x'):format(addr)..' ')
		if addr ~= 0 then
			for i=0,21 do
				local ptr = 0x198000+addr+i
				
				--- I only see 0,1,2,4,8,f per nibble
				rom[ptr] = math.random(0,255)
				
				io.write( (' %02x'):format(rom[ptr]) )
			end
		end
		print()
	end
end


print'enemies:'
for i,addr in ipairs(enemyAddrs) do
	local enemy = ffi.cast('enemy_t*', rom + addr)
	print('enemy '..i)
	print(' addr: '..('0x%04x'):format(addr - 0xf8000))
	print(' health='..enemy[0].health)
	print(' damage='..enemy[0].damage)
	io.write(' weakness='..('0x%04x'):format(enemy[0].weakness))
	
	-- points to 22 bytes that has weakness info
	if randomizeWeaknesses then
		enemy[0].weakness = pickRandom(weaknessAddrs)
	end
	local weaknessAddr = enemy[0].weakness
	if weaknessAddr ~= 0 then
		weaknessAddr = weaknessAddr + 0x198000
		io.write('  ')
		for i=0,21 do
			io.write( (' %02x'):format(rom[weaknessAddr+i]) )
		end
	end
	print()
	
	print(' itemdrop='..('0x%04x'):format(enemy[0].itemdrop))
	
end


for i,item in ipairs(itemInsts) do
	writeShort(item.addr, item.value)
end
--[[
for i,door in ipairs(doorInsts) do
	writeShort(door.addr, door.value)
end
--]]

file[outfilename] = header .. ffi.string(rom, #romstr)

print('done converting '..infilename..' => '..outfilename)
