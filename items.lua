return function(rom)
-- [[

local ffi = require 'ffi'
local config = require 'config'
local playerSkills = config.playerSkills

-- item requirements we've fulfilled so far
local req

local function canKill(enemyName)
io.write('canKill '..enemyName)
	local enemy = assert(enemyForName[enemyName], "failed to find enemy named "..enemyName)
	local weak = enemy:getWeakness()
	
	-- null weak means ... ?
	if weak == nil then 
print('...is empty')	
		return false
	end
	weak = weak[0]

	print(' weakness '..weak..' vs items so far '..tolua(req))

	if bit.band(0xf, weak.normal) ~= 0 then return true end
	if bit.band(0xf, weak.wave) ~= 0 and req.wave then return true end
	if bit.band(0xf, weak.ice) ~= 0 and req.ice then return true end
	if bit.band(0xf, weak.ice_wave) ~= 0 and req.ice and req.wave then return true end
	if bit.band(0xf, weak.spazer) ~= 0 and req.spazer then return true end
	if bit.band(0xf, weak.wave_spazer) ~= 0 and req.wave and req.spazer then return true end
	if bit.band(0xf, weak.ice_spazer) ~= 0 and req.ice and req.spazer then return true end
	if bit.band(0xf, weak.wave_ice_spazer) ~= 0 and req.wave and req.ice and req.spazer then return true end
	if bit.band(0xf, weak.plasma) ~= 0 and req.plasma then return true end
	if bit.band(0xf, weak.wave_plasma) ~= 0 and req.wave and req.plasma then return true end
	if bit.band(0xf, weak.ice_plasma) ~= 0 and req.ice and req.plasma then return true end
	if bit.band(0xf, weak.wave_ice_plasma) ~= 0 and req.wave and req.ice and req.plasma then return true end
	
	if bit.band(0xf, weak.missile) ~= 0 and req.missile
	-- TODO and the missile count vs the weakness can possibly kill the boss
	then return true end
	
	if bit.band(0xf, weak.supermissile) ~= 0 and req.supermissile
	-- TODO and the supermissile count vs the weakness can possibly kill the boss
	then return true end

	if bit.band(0xf, weak.bomb) ~= 0 and req.bomb then return true end
	if bit.band(0xf, weak.powerbomb) ~= 0 and req.powerbomb then return true end
	if bit.band(0xf, weak.speed) ~= 0 and req.speed then return true end
	
	if bit.band(0xf, weak.sparkcharge) ~= 0 and req.speed
	-- TODO and we have a runway ...
	then return true end
	
	if bit.band(0xf, weak.screwattack) ~= 0 and req.screwattack then return true end
	--if bit.band(0xf, weak.hyper) ~= 0 and req.hyper then return true end
	
	if bit.band(0xf, weak.pseudo_screwattack) ~= 0 and req.charge then return true end
end


local function effectiveMissileCount()
	return (req.missile or 0) + 5 * (req.supermissile or 0)
end

local function effectiveEnergyCount() 
	return (req.energy or 0) + math.min((req.energy or 0) + 1, req.reserve or 0) 
end



--[[
items fields:
	name = name of the *location* (unrelated to item name)
	addr = address of the item
	access = callback to determine what is required to access the item
	escape = callback to determine what is required to escape the room after accessing the item
	filter = callback to determine which items to allow here
--]]
local items = table()


-- start run / pre-alarm items ...


	-- morph ball room:

items:insert{
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
items:insert{name="Power Bomb (blue Brinstar)", addr=0x7874C, access=canUsePowerBombs}

	-- first missile room:

items:insert{
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
items:insert{
	name = "Missile (blue Brinstar middle)", 
	addr = 0x78798, 
	access = function() 
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
		playerSkills.touchAndGoToBoulderRoom
		or req.speed
		or req.spacejump
	)
end

items:insert{name="Missile (blue Brinstar top)", addr=0x78836, access=accessBlueBrinstarDoubleMissileRoom}
items:insert{name="Missile (blue Brinstar behind missile)", addr=0x7883C, access=accessBlueBrinstarDoubleMissileRoom}

local function canUseBombs() 
	return req.morph and req.bomb
end

local function canBombTechnique()
	return playerSkills.bombTechnique and canUseBombs()
end

-- can you get up to high areas using a runway
local function canGetUpWithRunway()
	return req.speed
	or req.spacejump
	or canBombTechnique()
end

local function canLeaveOldMotherBrainRoom()
	-- to escape the room, you have to kill the grey space pirates
	return canKill'Grey Zebesian (Wall)'
	and canKill'Grey Zebesian'
end

local function canActivateAlarm()
	-- in order for the alarm to activate, you need to collect morph and a missile tank and go to some room in crateria.
	return req.morph and req.missile
	-- and you have to go through the old mother brain room
	and (canLeaveOldMotherBrainRoom()
		-- TODO *or* you can go through power bomb brinstar then access some other certain room in crateria ... I think it's the crab room or something
	)
end

items:insert{name="Energy Tank (blue Brinstar)", addr=0x7879E, access=function() 
	return accessBlueBrinstarEnergyTankRoom() 
	and (
		-- how to get up?
		req.hijump 
		or canGetUpWithRunway()
		-- technically you can use a damage boost, so all you really need is missiles
		--  however this doesn't work until after security is activated ...
		or (playerSkills.damageBoostToBrinstarEnergy and canActivateAlarm())
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
items:insert{
	name = "Missile (Crateria bottom)", 
	addr = 0x783EE, 
	access = function()
		-- alarm needs to be activated or the missile won't appear
		return canActivateAlarm() 
		and canDestroyBombWallsStanding()
	end,
	escape = function()
		return canLeaveOldMotherBrainRoom()
	end,
}


	-- Bomb Torizo room:

-- getting back to the bomb area after getting morph ...
local function accessUpperCrateriaAfterMorph()
	return canActivateAlarm()
	-- or going through pink Brinstar from the right to the left ... all you need is powerbombs ...
	or req.powerbomb
end

-- this is another one of those, like plasma and the spore spawn super missiles, where there's no harm if we cut it off, because you need the very item to leave its own area
items:insert{
	name = "Bomb",
	addr = 0x78404, 
	access = function() 
		return accessUpperCrateriaAfterMorph()
		and canOpenMissileDoors() 
	end,
	escape = function()
		return playerSkills.touchAndGoUpAlcatraz 
		or canDestroyBombWallsMorphed()
	end,
}

	-- Final missile bombway:

items:insert{name="Missile (Crateria middle)", addr=0x78486, access=function()
	-- without the alarm, this item is replaced with a security scanner
	return canActivateAlarm()
	and accessUpperCrateriaAfterMorph()
	-- behind some bombable blocks in a morph passageway
	and canDestroyBombWallsMorphed()
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

items:insert{name="Energy Tank (Crateria tunnel to Brinstar)", addr=0x78432, access=accessTerminator}


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
		-- and tada, you're at the surface
	)
end

	-- Crateria power bomb room:

items:insert{name="Power Bomb (Crateria surface)", addr=0x781CC, access=function() 
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

items:insert{name="Energy Tank (Crateria gauntlet)", addr=0x78264, access=accessGauntlet, escape=escapeGauntletFirstRoom}

	-- Green pirate shaft

items:insert{name="Missile (Crateria gauntlet right)", addr=0x78464, access=accessGauntletSecondRoom, escape=escapeGreenPirateShaftItems}
items:insert{name="Missile (Crateria gauntlet left)", addr=0x7846A, access=accessGauntletSecondRoom, escape=escapeGreenPirateShaftItems}

-- speed boost area 
items:insert{name="Super Missile (Crateria)", addr=0x78478, access=function() 
	-- power bomb doors
	return canUsePowerBombs() 
	-- speed boost blocks
	and req.speed 
	-- escaping over the spikes
	and (effectiveEnergyCount() >= 1 or req.varia or req.gravity or req.grappling)
	-- killing / freezing the monsters
	and ((req.ice -- TODO make sure you can freeze the boyon 
		) or canKill'Boyon')
end}


-- green Brinstar


local accessEnterGreenBrinstar = accessTerminator

	-- early supers room:

items:insert{name="Missile (green Brinstar below super missile)", addr=0x78518, access=function() 
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
	and (playerSkills.mockball or req.speed)
	-- getting up to exit ...
	and (playerSkills.touchAndGo or req.hijump)
end

items:insert{name="Super Missile (green Brinstar top)", addr=0x7851E, access=accessEarlySupersRoomItems}

	-- Brinstar reserve tank room:

items:insert{name="Reserve Tank (Brinstar)", addr=0x7852C, access=accessEarlySupersRoomItems}

local function accessBrinstarReserveMissile()
	return accessEarlySupersRoomItems()
	-- takes morph to get to the item ...
	and req.morph 
end

items:insert{name="Missile (green Brinstar behind Reserve Tank)", addr=0x78538, access=accessBrinstarReserveMissile}

items:insert{name="Missile (green Brinstar behind missile)", addr=0x78532, access=function()
	return accessBrinstarReserveMissile()
	-- takes morph + power/bombs to get to this item ...
	and canDestroyBombWallsMorphed()
end}

	-- etecoon energy tank room:
local accessEtecoons = canUsePowerBombs

-- takes power bombs to get through the floor
items:insert{name="Energy Tank (green Brinstar bottom)", addr=0x787C2, access=accessEtecoons}

items:insert{name="Super Missile (green Brinstar bottom)", addr=0x787D0, access=function() 
	return accessEtecoons() 
	-- it's behind one more super missile door
	and req.supermissile 
end}

items:insert{name="Power Bomb (green Brinstar bottom)", addr=0x784AC, access=function()
	return accessEtecoons()
	-- technically ...
	-- and playerSkills.touchAndGo	-- except you *always* need touch-and-go to get this item ...
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

items:insert{
	name = "Super Missile (pink Brinstar)", 
	addr = 0x784E4, 
	access=function() 
		-- getting into pink brinstar
		return accessPinkBrinstar() 
		-- getting into spore spawn
		and canOpenMissileDoors()
		-- killing spore spawn
		and canKill'Spore Spawn'
	end,
	escape = function()
		return req.supermissile
		and req.morph
	end
}

local function accessMissilesAtTopOfPinkBrinstar()
	return accessPinkBrinstar()
	and (
		playerSkills.touchAndGo 
		or canBombTechnique()
		or req.grappling 
		or req.spacejump 
		or req.speed
	)
end

items:insert{name="Missile (pink Brinstar top)", addr=0x78608, access=accessMissilesAtTopOfPinkBrinstar}

items:insert{name="Power Bomb (pink Brinstar)", addr=0x7865C, access=function() 
	return accessMissilesAtTopOfPinkBrinstar()
	-- behind power bomb blocks
	and canUsePowerBombs() 
	-- behind a super missile block
	and req.supermissile 
end}

items:insert{name="Missile (pink Brinstar bottom)", addr=0x7860E, access=function() 
	return accessPinkBrinstar() 
end}

local function accessCharge()
	return accessPinkBrinstar() and canDestroyBombWallsMorphed()
end

items:insert{name="Charge Beam", addr=0x78614, access=accessCharge}

-- doesn't really need gravity, just helps
items:insert{name="Energy Tank (pink Brinstar bottom)", addr=0x787FA, access=function() 
	-- get to the charge room
	return accessCharge()
	-- power bomb block
	and canUsePowerBombs() 
	-- missile door
	and canOpenMissileDoors() 
	-- speed booster
	and req.speed 
	-- maybe gravity to get through the water
	and (playerSkills.shortSpeedBoost or req.gravity)
end}

local function canGetBackThroughBlueGates()
	return (playerSkills.superMissileGateGlitch and req.supermissile) or req.wave
end

-- the only thing that needs wave:
items:insert{name="Energy Tank (pink Brinstar top)", addr=0x78824, access=function() 
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

items:insert{name="Missile (green Brinstar pipe)", addr=0x78676, access=function() 
	return accessLowerGreenBrinstar()
	and (playerSkills.touchAndGo or req.hijump or req.spacejump) 
end}

-- what it takes to get into lower green Brinstar, and subsequently red Brinstar
-- either a supermissile through the pink Brinstar door
-- or a powerbomb through the blue Brinstar below Crateria entrance
local function accessRedBrinstar() 
	return canActivateAlarm()
	and accessLowerGreenBrinstar()
	and (req.supermissile or canUsePowerBombs())
end

items:insert{name="X-Ray Visor", addr=0x78876, access=function()
	return accessRedBrinstar() 
	and canUsePowerBombs() 
	and (
		req.grappling 
		or req.spacejump 
		or (effectiveEnergyCount() >= 5 and canUseBombs() and playerSkills.bombTechnique)
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
		or (playerSkills.touchAndGo and req.supermissile) 
		-- or you can destroy them (with super missiles or screw attack) and either bomb technique or spacejump up
		or (
			(req.screwattack or req.supermissile) 
			and (playerSkills.bombTechnique or req.spacejump)
		)
	)
end

-- behind a super missile door
-- you don't need power bombs to get this, but you need power bombs to escape this area
-- another shared exit constraint...
items:insert{
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
items:insert{name="Missile (red Brinstar spike room)", addr=0x78914, access=function() 
	return accessUpperRedBrinstar() and canUsePowerBombs() 
end}

-- super missile door, power bomb floor
items:insert{name="Power Bomb (red Brinstar sidehopper room)", addr=0x788CA, access=function() 
	return accessUpperRedBrinstar() and req.supermissile and canUsePowerBombs() 
end}

-- red Brinstar bottom:

items:insert{name="Spazer", addr=0x7896E, access=function() 
	-- getting there:
	return accessRedBrinstar() 
	-- getting up:
	and (playerSkills.touchAndGo or playerSkills.bombTechnique or req.spacejump or req.hijump) 
	-- getting over:
	and canDestroyBombWallsMorphed() 
	-- supermissile door:
	and req.supermissile
end}

local function accessKraid() 
	return accessRedBrinstar() 
	and (playerSkills.touchAndGo or req.spacejump or req.hijump) 
	and canDestroyBombWallsMorphed() 
end

items:insert{name="Missile (Kraid)", addr=0x789EC, access=function() 
	return accessKraid() and canUsePowerBombs() 
end}

local function canKillKraid()
	return accessKraid()
	and canKill'Kraid (body)'
end

-- accessible only after kraid is killed
items:insert{name="Energy Tank (Kraid)", addr=0x7899C, access=canKillKraid}

items:insert{name="Varia Suit", addr=0x78ACA, access=canKillKraid}


-- Norfair


local accessEnterNorfair = accessRedBrinstar

items:insert{name="Hi-Jump Boots", addr=0x78BAC, access=function() return accessEnterNorfair() end}
items:insert{name="Missile (Hi-Jump Boots)", addr=0x78BE6, access=accessEnterNorfair}
items:insert{name="Energy Tank (Hi-Jump Boots)", addr=0x78BEC, access=accessEnterNorfair}

local function accessHeatedNorfair() 
	return accessEnterNorfair() 
	and (
		-- you either need a suit
		req.varia 
		or req.gravity
		-- or, if you want to do hellrun ...
		or (playerSkills.hellrun 
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

items:insert{name="Missile (lava room)", addr=0x78AE4, access=accessHeatedNorfair}

local function accessIce()
	return accessKraid() 
	-- super missile door
	and req.supermissile
	-- speed / lowering barriers
	and (playerSkills.mockball or req.speed)
	-- get through the heat
	and (req.gravity 
		or req.varia
		or (playerSkills.hellrun and effectiveEnergyCount() >= 4)
	)
end

items:insert{name="Ice Beam", addr=0x78B24, access=accessIce} 

local function accessMissilesUnderIce()
	return accessIce() and canUsePowerBombs() 
end

items:insert{name="Missile (below Ice Beam)", addr=0x78B46, access=accessMissilesUnderIce}

-- crocomire takes either wave on the rhs or speed booster and power bombs on the lhs
local function accessCrocomire() 
	-- access crocomire from lhs
	return (accessMissilesUnderIce() and req.speed)
	-- access crocomire from flea run
	or (req.speed and req.wave)
	-- access crocomire from hell run / bubble room
	or (accessHeatedNorfair() and req.wave)
end

items:insert{name="Energy Tank (Crocomire)", addr=0x78BA4, access=accessCrocomire}
items:insert{name="Missile (above Crocomire)", addr=0x78BC0, access=accessCrocomire}

items:insert{name="Power Bomb (Crocomire)", addr=0x78C04, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or req.grappling
		or req.speed
		or req.ice
		or playerSkills.bombTechnique
	)
end}

items:insert{name="Missile (below Crocomire)", addr=0x78C14, access=accessCrocomire}

items:insert{name="Missile (Grappling Beam)", addr=0x78C2A, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or req.grappling 
		or req.speed
		or playerSkills.bombTechnique
	)
end}

items:insert{name="Grappling Beam", addr=0x78C36, access=function() 
	return accessCrocomire() 
	and (
		req.spacejump 
		or (req.speed and req.hijump)
		or playerSkills.bombTechnique
	) 
end}

items:insert{name="Missile (bubble Norfair)", addr=0x78C66, access=accessHeatedNorfair}
items:insert{name="Missile (Speed Booster)", addr=0x78C74, access=accessHeatedNorfair}
items:insert{name="Speed Booster", addr=0x78C82, access=accessHeatedNorfair}
items:insert{name="Missile (Wave Beam)", addr=0x78CBC, access=accessHeatedNorfair}

items:insert{
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
		or (playerSkills.touchAndGo and (req.hijump or req.ice))
	)
end

-- upper bubble room ... probably needs high jump or ice ... 
items:insert{name="Missile (bubble Norfair green door)", addr=0x78C52, access=accessNorfairReserve}
items:insert{name="Reserve Tank (Norfair)", addr=0x78C3E, access=accessNorfairReserve}
items:insert{name="Missile (Norfair Reserve Tank)", addr=0x78C44, access=accessNorfairReserve}


-- lower Norfair


local function accessLowerNorfair() 
	return accessHeatedNorfair() 
	-- powerbomb door
	and req.powerbomb 
	and (
		-- gravity and space jump is the default option
		(req.gravity and req.spacejump)
		-- you can do it without gravity, but you need precise touch and go, and you need high jump, and enough energy
		or (playerSkills.preciseTouchAndGoLowerNorfair and req.hijump and effectiveEnergyCount() >= 7)
		-- you can do without space jump if you have gravity and high jump -- suit swap
		or (req.gravity and playerSkills.lowerNorfairSuitSwap)
	)
end

items:insert{name="Missile (Gold Torizo)", addr=0x78E6E, access=accessLowerNorfair}
items:insert{name="Super Missile (Gold Torizo)", addr=0x78E74, access=accessLowerNorfair}
items:insert{name="Screw Attack", addr=0x79110, access=accessLowerNorfair}

items:insert{name="Missile (Mickey Mouse room)", addr=0x78F30, access=accessLowerNorfair}

items:insert{name="Energy Tank (lower Norfair fire flea room)", addr=0x79184, access=accessLowerNorfair}
items:insert{name="Missile (lower Norfair above fire flea room)", addr=0x78FCA, access=accessLowerNorfair}
items:insert{name="Power Bomb (lower Norfair above fire flea room)", addr=0x78FD2, access=accessLowerNorfair}

-- spade shaped room?
items:insert{name="Missile (lower Norfair near Wave Beam)", addr=0x79100, access=accessLowerNorfair}

items:insert{name="Power Bomb (above Ridley)", addr=0x790C0, access=accessLowerNorfair}

-- these constraints are really for what it takes to kill Ridley
items:insert{name="Energy Tank (Ridley)", addr=0x79108, access=function() 
	return accessLowerNorfair() 
	and effectiveEnergyCount() >= 4 
	-- you don't need charge.  you can also kill him with a few hundred missiles
	and (req.charge or effectiveMissileCount() >= 250)
end}


-- Wrecked Ship


-- on the way to wrecked ship
items:insert{name="Missile (Crateria moat)", addr=0x78248, access=function() 
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
	and (playerSkills.canJumpAcrossEntranceToWreckedShip or req.spacejump or req.grappling or req.speed)
end

items:insert{name="Missile (outside Wrecked Ship bottom)", addr=0x781E8, access=accessWreckedShip}
items:insert{name="Missile (Wrecked Ship middle)", addr=0x7C265, access=accessWreckedShip}

local function canDefeatPhantoon() 
	return accessWreckedShip() 
	and req.charge 
	and (req.gravity or req.varia or effectiveEnergyCount() >= 2) 
end

items:insert{name="Missile (outside Wrecked Ship top)", addr=0x781EE, access=canDefeatPhantoon}
items:insert{name="Missile (outside Wrecked Ship middle)", addr=0x781F4, access=canDefeatPhantoon}
items:insert{name="Reserve Tank (Wrecked Ship)", addr=0x7C2E9, access=function() return canDefeatPhantoon() and req.speed end}
items:insert{name="Missile (Gravity Suit)", addr=0x7C2EF, access=canDefeatPhantoon}
items:insert{name="Missile (Wrecked Ship top)", addr=0x7C319, access=canDefeatPhantoon}

items:insert{name="Energy Tank (Wrecked Ship)", addr=0x7C337, access=function() 
	return canDefeatPhantoon() 
	and (req.grappling or req.spacejump
		or effectiveEnergyCount() >= 2
	) 
	--and req.gravity 
end}

items:insert{name="Super Missile (Wrecked Ship left)", addr=0x7C357, access=canDefeatPhantoon}
items:insert{name="Super Missile (Wrecked Ship right)", addr=0x7C365, access=canDefeatPhantoon}
items:insert{name="Gravity Suit", addr=0x7C36D, access=canDefeatPhantoon}


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
			playerSkills.maridiaSuitSwap --playerSkills.touchAndGo 
			or req.spacejump 
			or req.hijump or (playerSkills.bombTechnique and canUseBombs())))
		-- if you don't have gravity then you need high jump and ice.  without gravity you do need high jump just to jump up from the tube that you break, into the next room.
		or (playerSkills.suitlessMaridiaFreezeCrabs and req.hijump and req.ice)
		
		-- suitless is possible so long as the space jump item is replaced with gravity suit to get out of Draygon's room ... or you do the crystal spark + blue spark + whatever move that I don't know how to do
	)
end

items:insert{name="Missile (green Maridia shinespark)", addr=0x7C437, access=function() return accessOuterMaridia() and req.speed end}
items:insert{name="Super Missile (green Maridia)", addr=0x7C43D, access=accessOuterMaridia}
items:insert{name="Energy Tank (green Maridia)", addr=0x7C47D, access=function() return accessOuterMaridia() and (req.speed or req.grappling or req.spacejump) end}
items:insert{name="Missile (green Maridia tatori)", addr=0x7C483, access=accessOuterMaridia}

local function accessInnerMaridia() 
	return accessOuterMaridia() 
	and (req.spacejump or req.grappling or req.speed or (req.gravity and playerSkills.touchAndGo)) 
end

-- top of maridia
items:insert{name="Super Missile (yellow Maridia)", addr=0x7C4AF, access=accessInnerMaridia}
items:insert{name="Missile (yellow Maridia super missile)", addr=0x7C4B5, access=accessInnerMaridia}
items:insert{name="Missile (yellow Maridia false wall)", addr=0x7C533, access=accessInnerMaridia}

local function canDefeatBotwoon() 
	return accessInnerMaridia() 
	and (
		(playerSkills.botwoonFreezeGlitch and req.ice) 
		-- need to speed boost underwater
		or (req.gravity and req.speed)
		or playerSkills.DraygonCrystalFlashBlueSparkWhatever
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
-- Maybe I should make the randomizer to only put worthless items in these places?
--  Otherwise I can't make randomizations that don't include the plasma item. 
items:insert{
	name = "Plasma Beam",
	addr = 0x7C559,
	access = function() 
		-- draygon must be defeated to unlock the door to plasma
		return canDefeatDraygon() 
	end,
	escape = function()
		-- either one of these to kill the space pirates and unlock the door
		return (
			-- make sure req matches the weaknesses of the climbing & standing pink space pirates
			canKill'Pink Zebesian (Wall)'
			and canKill'Pink Zebesian'
		)
		-- getting in and getting out ...
		and (
			-- do you need hijump with touch-and-go?
			playerSkills.touchAndGo 
			or playerSkills.bombTechnique 
			or req.spacejump
		)
	end,
}

local function canUseSpringBall()
	return req.morph and req.springball
end

items:insert{name="Missile (left Maridia sand pit room)", addr=0x7C5DD, access=function() 
	return accessOuterMaridia() 
	and (canUseBombs() or canUseSpringBall())
end}

-- also left sand pit room 
items:insert{name="Reserve Tank (Maridia)", addr=0x7C5E3, access=function() 
	return accessOuterMaridia() and (canUseBombs() or canUseSpringBall()) 
end}

items:insert{name="Missile (right Maridia sand pit room)", addr=0x7C5EB, access=accessOuterMaridia}
items:insert{name="Power Bomb (right Maridia sand pit room)", addr=0x7C5F1, access=accessOuterMaridia}

-- room with the shell things
items:insert{name="Missile (pink Maridia)", addr=0x7C603, access=function() return accessOuterMaridia() and req.speed end}
items:insert{name="Super Missile (pink Maridia)", addr=0x7C609, access=function() return accessOuterMaridia() and req.speed end}

-- here's another fringe item
-- requires grappling, but what if we put something unimportant there? who cares about it then?
items:insert{name="Spring Ball", addr=0x7C6E5, access=function() 
	return accessOuterMaridia() 
	and req.grappling 
	and (playerSkills.touchAndGo or req.spacejump)
end}

-- missile right before draygon?
items:insert{name="Missile (Draygon)", addr=0x7C74D, access=canDefeatDraygon}

-- energy tank right after botwoon
items:insert{name="Energy Tank (Botwoon)", addr=0x7C755, access=canDefeatBotwoon}

-- technically you don't need gravity to get to this item 
-- ... but you need it to escape Draygon's area
items:insert{
	name = "Space Jump", 
	addr = 0x7C7A7, 
	access = function() 
		return canDefeatDraygon() 
	end,
	escape = function()
		-- if the player knows the crystal-flash-whatever trick then fine
		return playerSkills.DraygonCrystalFlashBlueSparkWhatever
		-- otherwise they will need both gravity and either spacejump or bombs
		or (req.gravity and (req.spacejump or canUseBombs()))
	end,
}


--]]

local itemsForName = items:map(function(item) return item, item.name end)
local itemsForAddr = items:map(function(item) return item, item.addr end)

for _,item in ipairs(items) do
	-- ptr to the item type
	-- ANOTHER TODO: enemies[] addr is 16-bit, while items[] addr is PC /  24-bit. pick one method and stick with it.
	-- TODO I bet this is part of a bigger structure, maybe with position, etc
	item.ptr = ffi.cast('uint16_t*', rom + item.addr)
end



--[[
TODO prioritize placement of certain items last.
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

local itemTypeNameForValue = itemTypes:map(function(v,k) return k,v end)

--[[ filter out bombs and morph ball, so we know the run is possible 
items = items:filter(function(item)
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
for _,item in ipairs(items) do
	local name = itemTypeNameForValue[item.ptr[0]]

	-- save it as a flag for later -- whether this used to be chozo or hidden
	item.isChozo = not not name:match'_chozo$' 
	item.isHidden = not not name:match'_hidden$' 
	-- remove all chozo and hidden status
	name = name:gsub('_chozo', ''):gsub('_hidden', '')	

	-- write back our change
	item.ptr[0] = itemTypes[name]
end
--]]

print('found '..#items..' items')


--[[
changes around the original values that are to be randomized
in case you want to try a lean run, with less items, or something
args:
	changes = {[from type] => [to type]} key/value pairs
	args = extra args:
		leave = how many to leave
--]]
local function change(changes, args)
	local leave = (args and args.leave) or 0
	for from, to in pairs(changes) do
		local found = items:filter(function(item) 
			return itemTypeNameForValue[item.ptr[0]]:match('^'..from) 
		end)
		for i=1,leave do
			if #found == 0 then break end
			found:remove(math.random(#found))	-- leave as many as the caller wants
		end
		for _,item in ipairs(found) do 
			item.ptr[0] = itemTypes[to] 
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

local function removeItem(itemName, withType)
	local item = assert(itemsForName[itemName], "couldn't find item "..itemName)
	item.ptr[0] = itemTypes[withType]
	
	items:removeObject(item)
	itemsForName[itemName] = nil
end

-- removing plasma means you must keep screwattack, or else you can't escape the plasma room and it'll stall the randomizer
-- the other fix is to just not consider the plasma location, and put something innocuous there ...
change{plasma='missile'}

-- this will stall the randomizer because of pink Brinstar energy tank
-- so lets remove it and write it as a missile
change{wave='missile'}
removeItem("Energy Tank (pink Brinstar top)", 'missile')

-- grappling is only absolutely required to get into springball...
change{grappling='missile'}
removeItem("Spring Ball", 'missile')

-- is this possible?  maybe you can't kill the golden chozo without charge, or a lot of super missiles ... or a lot of restocking on 5 super missiles and shooting them all off at him
--change{charge='missile'}

-- is this possible?  you will have a hard time escaping Draygon's room
--change{gravity='missile'}

-- only possible if you have enough e-tanks before hell runs
-- what this means is ... if the randomizer doesn't come up with a varia suit before hell run ... then it will be forced to place *all* energy tanks before hell run ... which might make a game that's too easy
change{varia='missile'}

-- if you're replacing plasma item and screw attack item then you must remove plasma location ...
change{screwattack='missile'}
removeItem('Plasma Beam', 'missile')

change{spacejump='missile'}


--]]
--[[
change{missile='supermissile'}						-- turn all missiles into super missiles (one is already left -- the first missile tank)
change({powerbomb='supermissile'}, {leave=1}) 		-- turn all but one power bombs into super missiles
change{spazer='supermissile', hijump='supermissile', springball='supermissile', reserve='supermissile', xray='supermissile'}	-- no need for these
change({energy='supermissile'}, {leave=7})
--]]



--[[ boring randomization:
for i,value in ipairs(shuffle(items:map(function(item) return item.ptr[0] end))) do
	items[i].ptr[0] = value
end
--]]


-- [[ placement algorithm:


-- defined above so item constraints can see it 
req = {}

-- deep copy, so the orginal items is intact
local origItemValues = items:map(function(item) return item.ptr[0] end)
-- feel free to modify origItemValues to your hearts content ... like replacing all reserve tanks with missiles, etc
-- I guess I'm doing this above alread with the change() and removeItem() functions


-- keep track of the remaining items to place -- via indexes into the original array
local itemValueIndexesLeft = range(#origItemValues)

local currentItems = table(items)

for _,item in ipairs(items) do
	local value = item.ptr[0]
	item.defaultTypeName = itemTypeNameForValue[itemTypeBaseForType[value]]
end

local replaceMap = {}

local function iterate(depth)
	depth = depth or 0
	local function dprint(...)
		io.write(('%3d%% '):format(depth))
		return print(...)
	end

	if #currentItems == 0 then
		dprint'done!'
		return true
	end

	local chooseLocs = currentItems:filter(function(loc)
		return loc.access()
	end)
	dprint('options to replace: '..tolua(chooseLocs:map(function(loc,i,t) return (t[loc.defaultTypeName] or 0) + 1, loc.defaultTypeName end)))

	-- pick an item to replace
	if #chooseLocs == 0 then 
		dprint('we ran out of options with '..#currentItems..' items unplaced!')
		return
	end
	local chooseItem = chooseLocs[math.random(#chooseLocs)]
	dprint('choosing to replace '..chooseItem.name)
	
	-- remove it from the currentItems list 
	local nextItems = currentItems:filter(function(loc) return chooseItem ~= loc end)
	
	-- find an item to replace it with
	if #itemValueIndexesLeft == 0 then 
		dprint('we have no items left to replace it with!')
		os.exit()
	end
	
	for _,i in ipairs(shuffle(range(#itemValueIndexesLeft))) do
		local push_itemValueIndexesLeft = table(itemValueIndexesLeft)
		local replaceInstIndex = itemValueIndexesLeft:remove(i)
		
		local value = origItemValues[replaceInstIndex]
		local name = itemTypeNameForValue[value]
		
		if not chooseItem.filter
		or chooseItem.filter(name)
		then
			dprint('...replacing '..chooseItem.name..' with '..name)
					
			-- plan to write it 
			replaceMap[chooseItem.addr] = {value=value, req=table(req)}
		
			-- now replace it with an item
			local push_req = setmetatable(table(req), nil)
			req[name] = (req[name] or 0) + 1
		
			local push_currentItems = table(currentItems)
			currentItems = nextItems

			-- if the chooseItem has an escape req, and it isn't satisfied, then don't iterate
			if chooseItem.escape and not chooseItem.escape() then
				dprint('...escape condition not met!')
			else
				dprint('iterating...')
				if iterate(depth + 1) then return true end	-- return 'true' when finished to exit out of all recursion
			end
			
			currentItems = push_currentItems
			req = push_req
		end
		itemValueIndexesLeft = push_itemValueIndexesLeft
	end
end	

iterate()

print()
print()
print'summary:'
local longestName = items:map(function(item) return #item.name end):sup()
-- sort by # of constraints, so first item expected to get is listed first
local function score(item)
	return table.values(replaceMap[item.addr].req):sum() or 0
end
table(items):sort(function(a,b) 
	return score(a) < score(b) 
end):map(function(item)
	local addr = item.addr
	local value = replaceMap[addr].value
	local req = replaceMap[addr].req
	print(item.name
		..('.'):rep(longestName - #item.name + 10)
		..itemTypeNameForValue[value]
		..'\t'..tolua(req))
	-- do the writing:
	itemsForAddr[addr].ptr[0] = value
end)


end
