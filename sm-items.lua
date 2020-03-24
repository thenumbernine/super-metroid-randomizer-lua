--[[
notice, the items array is full of addresses that point back to the plm_t's in the original ROM
plm's also have door info, and a blue door is the absense of a plm, which means to change door colors I will have to add and remove some plms ... 
so ... always run the item randomization *before* rearranging plms
or in the future (TODO maybe) have this pick out the item plm's based on room and plm cmd ... and x/y ?
--]]

local ffi = require 'ffi'
local config = require 'config'
local playerSkills = config.playerSkills


local SMItems = {}


-- item requirements we've fulfilled so far
-- TODO ... fix this
--local req

-- TODO this is all a lot more complex than this
-- flags work on some enemies and not on others

local function beamCanFreeze(weak, field)
	local value = weak[field]
	if value == 0xff then return true end
	if bit.band(value, 0xf) == 0 then return false end	-- immune to beam, so... can't freeze, right?
	if bit.band(value, 0x80) ~= 0 then return false end	-- can't freeze flag is set
	-- by here we know we aren't immune (can damage) and we don't have can't freeze set, so it should freeze
	return true
end

local function canFreeze(enemyName)
	local enemy = assert(sm.enemyForName[enemyName], 'failed to find enemy named '..enemyName)
	local weak = enemy:getWeakness()
	
	if weak == nil then return false end
	weak = weak[0]
	
	if beamCanFreeze(weak, 'ice') and req.ice then return true end
	if beamCanFreeze(weak, 'ice_wave') and req.ice and req.wave then return true end
	if beamCanFreeze(weak, 'ice_spazer') and req.ice and req.spazer then return true end
	if beamCanFreeze(weak, 'wave_ice_spazer') and req.wave and req.ice and req.spazer then return true end
	if beamCanFreeze(weak, 'ice_plasma') and req.ice and req.plasma then return true end
	if beamCanFreeze(weak, 'wave_ice_plasma') and req.wave and req.ice and req.plasma then return true end

	return true
end

local function notImmune(weak, field)
	local value = weak[field]
--print('checking', field, value)	
	-- 0xff means freeze don't kill ..
	-- does it also mean this for non-ice / non-beam weapons?
	if value == 0xff then 
--print('...returning false')		
		return false 
	end
--print('...returning '..tostring(bit.band(value, 0xf) ~= 0))
	return bit.band(value, 0xf) ~= 0
end

local function canUsePowerBombs() 
	return req.morph and req.powerbomb
end

local function canUseBombs() 
	return req.morph and req.bomb
end

--[[
some TODO's...
* if you can't powerbomb left and the first old mother brain space pirates are weak to missiles
  then you have to make sure missiles are a dropped item before this point
* same with powerbombs?  nah, because, you should be able to save enough 
* also, if they're weak to speed, and the randomization gives you speed beforehand, well,
  canKill needs to make sure there's an accessible runway nearby
* non-solid enemies are only hurt by power bomb, screw attack, etc ... not beams or missiles or bombs
--]]
local function canKill(enemyName)
--io.write('canKill '..enemyName)
	local enemy = assert(sm.enemyForName[enemyName], 'failed to find enemy named '..enemyName)
	local weak = enemy:getWeakness()
	
	-- null weak means invincible
	if weak == nil then return false end
--	weak = weak[0]

--print('weakness '..weak..' vs items so far '..tolua(req))

	if notImmune(weak, 'normal') then return true end
	if notImmune(weak, 'wave') and req.wave then return true end
	if notImmune(weak, 'ice') and req.ice then return true end
	if notImmune(weak, 'ice_wave') and req.ice and req.wave then return true end
	if notImmune(weak, 'spazer') and req.spazer then return true end
	if notImmune(weak, 'wave_spazer') and req.wave and req.spazer then return true end
	if notImmune(weak, 'ice_spazer') and req.ice and req.spazer then return true end
	if notImmune(weak, 'wave_ice_spazer') and req.wave and req.ice and req.spazer then return true end
	if notImmune(weak, 'plasma') and req.plasma then return true end
	if notImmune(weak, 'wave_plasma') and req.wave and req.plasma then return true end
	if notImmune(weak, 'ice_plasma') and req.ice and req.plasma then return true end
	if notImmune(weak, 'wave_ice_plasma') and req.wave and req.ice and req.plasma then return true end
	
	if notImmune(weak, 'missile')
	and req.missile
	-- TODO check all weaknesses vs all potential damage inflicted
	and req.missile * sm.weaponDamageForName.missile.ptr[0] * bit.rshift(bit.band(weak.missile, 0xf), 1) >= enemy.ptr.health
	then
		return true
	end
	
	-- TODO and the supermissile count vs the weakness can possibly kill the boss
	if notImmune(weak, 'supermissile') 
	and req.supermissile 
	and req.supermissile * sm.weaponDamageForName.supermissile.ptr[0] * bit.rshift(bit.band(weak.supermissile, 0xf), 1) >= enemy.ptr.health
	then
		return true
	end

	if notImmune(weak, 'bomb') 
	and canUseBombs() 
	then 
		return true 
	end
	
	if notImmune(weak, 'powerbomb') 
	and canUsePowerBombs() 
	and req.powerbomb * sm.weaponDamageForName.powerbomb.ptr[0] * bit.rshift(bit.band(weak.powerbomb, 0xf), 1) >= enemy.ptr.health
	then 
		return true 
	end

	-- TODO and we have a runway
	if notImmune(weak, 'speed') and req.speed then 
		return true 
	end
	
	-- TODO and we have a runway ...
	if notImmune(weak, 'sparkcharge') and req.speed then 
		return true 
	end
	
	if notImmune(weak, 'screwattack') and req.screwattack then 
		return true 
	end
	
	--if notImmune(weak, 'hyper') and req.hyper then return true end

	-- charge-based screw attack
	-- TODO and your health / monster's touch damage >= monster's health / your pseudo-screw-attack touch damage
	if notImmune(weak, 'pseudo_screwattack') and req.charge then 
		return true 
	end
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
	name = 'Morphing Ball', 
	addr = 0x786DE, 
	plmIndex=17, plmsetIndex=55,
	access = function() return true end, 
	-- looks like you always need morph in morph...
	--filter = function(name) return name ~= 'morph' end,
}

local function canLeaveOldMotherBrainRoom()
	-- to escape the room, you have to kill the grey space pirates
	return canKill'Grey Zebesian (Wall)'
	and canKill'Grey Zebesian'
end

local function canWakeZebes()
	-- in order for the alarm to activate, you need to collect morph and a missile tank and go to some room in crateria.
	return req.morph and req.missile
	-- and you have to go through the old mother brain room
	and (canLeaveOldMotherBrainRoom()
		-- TODO *or* you can go through power bomb brinstar then access some other certain room in crateria ... I think it's the crab room or something
	)
end

-- power bombs behind power bomb wall near the morph ball 
items:insert{
	name='Power Bomb (blue Brinstar)', 
	addr=0x7874C, 
	plmIndex=18, plmsetIndex=56,
	access=function()
		-- this item doesn't appear until you activate the alarm
		return (canWakeZebes() or config.wakeZebesEarly)
		and canUsePowerBombs()
		and (
		-- also notice, to access it from the ship, you need to either
		-- 1) go down from crateria through the old mother brain room (and be able to kill the zebesians)
			canLeaveOldMotherBrainRoom()
		-- or 2) go back through pink brinstar, which requires super missiles and power bombs
			or req.supermissile
		)
	end,
}

	-- first missile room:

items:insert{
	name = 'Missile (blue Brinstar bottom)', 
	addr = 0x78802, 
	plmIndex=1, plmsetIndex=66,
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
	name = 'Missile (blue Brinstar middle)', 
	addr = 0x78798, 
	plmIndex=3, plmsetIndex=58,
	access = function() 
		return accessBlueBrinstarEnergyTankRoom() 
		and req.morph 
	end,
	-- also doesn't have to be a missile =D
	--filter = function(name) return name ~= 'missile' end,
--filter = function(name) return name == 'powerbomb' end,
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

items:insert{
	name='Missile (blue Brinstar top)',
	addr=0x78836,
	plmIndex=1, plmsetIndex=71,
	access=accessBlueBrinstarDoubleMissileRoom,
}

items:insert{
	name='Missile (blue Brinstar behind missile)',
	addr=0x7883C,
	plmIndex=2, plmsetIndex=71,
	access=accessBlueBrinstarDoubleMissileRoom,
}

local function canBombTechnique()
	return playerSkills.bombTechnique and canUseBombs()
end

-- can you get up to high areas using a runway
local function canGetUpWithRunway()
	return req.speed
	or req.spacejump
	or canBombTechnique()
end

items:insert{
	name='Energy Tank (blue Brinstar)',
	addr=0x7879E,
	plmIndex=4, plmsetIndex=58,
	access=function() 
		return accessBlueBrinstarEnergyTankRoom() 
		and (
			-- how to get up?
			req.hijump 
			or canGetUpWithRunway()
			-- technically you can use a damage boost, so all you really need is missiles
			--  however this doesn't work until after security is activated ...
			or (playerSkills.damageBoostToBrinstarEnergy 
				and (canWakeZebes() or config.wakeZebesEarly)
			)
		)
	end,
}

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
	name = 'Missile (Crateria bottom)', 
	addr = 0x783EE, 
	plmIndex=6, plmsetIndex=24,
	access = function()
		-- alarm needs to be activated or the missile won't appear
		return canWakeZebes() 
		and canDestroyBombWallsStanding()
	end,
	escape = function()
		return canLeaveOldMotherBrainRoom()
	end,
}


	-- Bomb Torizo room:

-- notice, you can enter pink brinstar from the right with only power bombs
-- ... but you can't leave without getting super missiles ...
local function accessPinkBrinstarFromRight()
	-- power bomb from the morph ball room
	return canUsePowerBombs()
	-- though, notice, if we are waking zebes early, we'll have to kill those sidehoppers...)
	and (not config.wakeZebesEarly or canKill'Big Sidehopper')
end

-- getting back to the bomb area after getting morph ...
local function accessUpperCrateriaAfterMorph()
	-- TODO sometimes with config.wakeZebesEarly, the ordinary method of waking zebes up just doesn't trigger...
	return canWakeZebes()
	-- or going through pink Brinstar from the right to the left ... all you need is powerbombs ...
	or accessPinkBrinstarFromRight()
end

-- this is another one of those, like plasma and the spore spawn super missiles, where there's no harm if we cut it off, because you need the very item to leave its own area
items:insert{
	name = 'Bomb',
	addr = 0x78404, 
	plmIndex=2, plmsetIndex=26,
	access = function() 
		return accessUpperCrateriaAfterMorph()
		and canOpenMissileDoors() 
	end,
	escape = function()
		return 
		-- fighting the chozo ... or if you don't have bombs, he doesn't fight you
		(not req.bomb or canKill'Grey Torizo')
		-- leaving Alkatraz
		and (playerSkills.touchAndGoUpAlcatraz 
			or canDestroyBombWallsMorphed())
	end,
}

	-- Final missile bombway:

items:insert{
	name='Missile (Crateria middle)',
	addr=0x78486,
	plmIndex=1, plmsetIndex=40,
	access=function()
		-- without the alarm, this item is replaced with a security scanner
		return (canWakeZebes()
		-- or config.wakeZebesEarly
		) and accessUpperCrateriaAfterMorph()
		-- behind some bombable blocks in a morph passageway
		and canDestroyBombWallsMorphed()
	end,
}

	-- Terminator room:

-- bomb walls that can be destroyed and have a runway nearby
local function canDestroyBombWallsWithRunway()
	return req.speed
	or canDestroyBombWallsStanding()
end

local function accessTerminator()
	return 
	-- accessing terminator from the regular entrance
	(canWakeZebes() and canDestroyBombWallsWithRunway())
	-- or accessing it from blue brinstar ...
	or accessPinkBrinstarFromRight()
end

items:insert{
	name='Energy Tank (Crateria tunnel to Brinstar)',
	addr=0x78432,
	plmIndex=1, plmsetIndex=31,
	access=accessTerminator,
}


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

local function accessLandingRoom()
	-- going up the normal way
	return canWakeZebes()
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

items:insert{
	name='Power Bomb (Crateria surface)',
	addr=0x781CC,
	plmIndex=1, plmsetIndex=6,
	access=function() 
		-- get back to the surface
		return accessLandingRoom()
		-- to get up there
		and canGetUpWithRunway()
		-- to get in the door
		and canUsePowerBombs()
	end,
}

	-- Crateria gauntlet:

-- so technically ...
-- you need either bombs, or you need speed + 5 powerbombs to enter ...
-- then you need either bombs or another 5 power bombs to exit
local function accessGauntlet()
	-- getting (back from morph) to the start room
	return accessLandingRoom()
	-- getting up
	and (
		-- turns out you can touch and go up, if you disable hijump
		playerSkills.touchAndGoUpToGauntlet
		or canGetUpWithRunway()
	)
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
	return accessGauntlet() 
	and escapeGauntletFirstRoom() 
	and canUseBombs()	-- oh yeah, you need morph to get past the e-tank in gauntlet.  should that be escape?
end

-- here's another escape condition shared between items: only one of the two green pirate shaft items needs to be morph
local function escapeGreenPirateShaftItems()
	return req.morph
end

items:insert{
	name='Energy Tank (Crateria gauntlet)', 
	addr=0x78264, 
	plmIndex=2, plmsetIndex=19,
	access=accessGauntlet, 
	escape=escapeGauntletFirstRoom,
}

	-- Green pirate shaft

items:insert{
	name='Missile (Crateria gauntlet right)', 
	addr=0x78464, 
	plmIndex=5, plmsetIndex=35,
	access=accessGauntletSecondRoom, 
	escape=escapeGreenPirateShaftItems,
}

items:insert{
	name='Missile (Crateria gauntlet left)', 
	addr=0x7846A, 
	plmIndex=6, plmsetIndex=35,
	access=accessGauntletSecondRoom, 
	escape=escapeGreenPirateShaftItems,
}

-- freeze boyon and speed boost and duck and jump up shaft, then grappling / space jump back 
items:insert{
	name='Super Missile (Crateria)',
	addr=0x78478,
	plmIndex=1, plmsetIndex=36,
	access=function() 
		-- power bomb doors
		return canUsePowerBombs() 
		-- speed boost blocks
		and req.speed 
		-- you need at least 1 extra e-tank for the spark charge jump
		-- (maybe with the exception of being able to freeze the Boyons...)
		and (req.energy or 0) >= 1
		-- escaping over the spikes
		--and (effectiveEnergyCount() >= 1 or req.varia or req.gravity or req.grappling)
		-- killing / freezing the boyons... 
		and (canFreeze'Boyon' or canKill'Boyon')
	end,
}

-- green Brinstar


local accessEnterGreenBrinstar = accessTerminator

	-- early supers room:

items:insert{
	name='Missile (green Brinstar below super missile)', 
	addr=0x78518, 
	plmIndex=7, plmsetIndex=44,
	access=function() 
		return accessEnterGreenBrinstar()
		-- missile door to enter room
		and canOpenMissileDoors() 
	end, 
	escape=function()
		-- because you need to morph and bomb to get out ... 
		return canDestroyBombWallsMorphed()	
	end,
}

-- accessing the items & escaping through the top ...
local function accessEarlySupersRoomItems()
	return accessEnterGreenBrinstar()
	and canOpenMissileDoors() 
	-- missiles and mockball/speed to get up to it ...
	and (playerSkills.mockball or req.speed)
	-- getting up to exit ...
	and (playerSkills.touchAndGo or req.hijump)
end

items:insert{
	name='Super Missile (green Brinstar top)', 
	addr=0x7851E, 
	plmIndex=8, plmsetIndex=44,
	access=accessEarlySupersRoomItems,
}

	-- Brinstar reserve tank room:

items:insert{
	name='Reserve Tank (Brinstar)', 
	addr=0x7852C, 
	plmIndex=2, plmsetIndex=45,
	access=accessEarlySupersRoomItems,
}

local function accessBrinstarReserveMissile()
	return accessEarlySupersRoomItems()
	-- takes morph to get to the item ...
	and req.morph 
end

items:insert{
	name='Missile (green Brinstar behind Reserve Tank)', 
	addr=0x78538, 
	plmIndex=4, plmsetIndex=45,
	access=accessBrinstarReserveMissile,
}

items:insert{
	name='Missile (green Brinstar behind missile)', 
	addr=0x78532, 
	plmIndex=3, plmsetIndex=45,
	access=function()
		return accessBrinstarReserveMissile()
		-- takes morph + power/bombs to get to this item ...
		and canDestroyBombWallsMorphed()
	end,
}

	-- etecoon energy tank room:
local accessEtecoons = canUsePowerBombs

-- takes power bombs to get through the floor
items:insert{
	name='Energy Tank (green Brinstar bottom)', 
	addr=0x787C2, 
	plmIndex=4, plmsetIndex=61,
	access=accessEtecoons,
}

items:insert{
	name='Super Missile (green Brinstar bottom)', 
	addr=0x787D0, 
	plmIndex=1, plmsetIndex=62,
	access=function() 
		return accessEtecoons() 
		-- it's behind one more super missile door
		and req.supermissile 
	end,
}

items:insert{
	name='Power Bomb (green Brinstar bottom)', 
	addr=0x784AC, 
	plmIndex=6, plmsetIndex=41,
	access=function()
		return accessEtecoons()
		-- technically ...
		-- and playerSkills.touchAndGo	-- except you *always* need touch-and-go to get this item ...
		-- and technically you need morph, but you already need it to power bomb through the floor to get into etecoon area
	end,
}


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
	name = 'Super Missile (pink Brinstar)', 
	addr = 0x784E4, 
	plmIndex=3, plmsetIndex=42,
	access=function() 
		-- getting into pink brinstar
		return accessPinkBrinstar() 
		-- getting into spore spawn
		and canOpenMissileDoors()
		-- getting into spore spawn room ...
	
		-- TODO also make sure you can kill *all* of them
		-- i.e. if the Green Kihunter is only weak to pseudo-screwattack
		-- and you have to hit it 'k+1' times to to kill it (its health / your damage = k+1), 
		-- that's k hits against you.  so make sure you have (its touch damage * k * number of Green Kihunters) effective health
		and canKill'Green Kihunter'
		
		-- killing spore spawn
		and canKill'Spore Spawn'
	end,
	escape = function()
		-- super missile door, super missile block, morph passage, bomb to exit
		return req.supermissile
		and canDestroyBombWallsMorphed()
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

items:insert{
	name='Missile (pink Brinstar top)', 
	addr=0x78608, 
	plmIndex=7, plmsetIndex=50,
	access=accessMissilesAtTopOfPinkBrinstar,
}

items:insert{
	name='Power Bomb (pink Brinstar)', 
	addr=0x7865C, 
	plmIndex=4, plmsetIndex=53,
	access=function() 
		return accessMissilesAtTopOfPinkBrinstar()
		-- behind power bomb blocks
		and canUsePowerBombs() 
		-- behind a super missile block
		and req.supermissile 
	end,
}

items:insert{
	name='Missile (pink Brinstar bottom)', 
	addr=0x7860E, 
	plmIndex=8, plmsetIndex=50,
	access=function() 
		return accessPinkBrinstar() 
	end,
}

local function accessCharge()
	return accessPinkBrinstar() and canDestroyBombWallsMorphed()
end

items:insert{
	name='Charge Beam', 
	addr=0x78614, 
	plmIndex=9, plmsetIndex=50,
	access=accessCharge,
}

-- doesn't really need gravity, just helps
items:insert{
	name='Energy Tank (pink Brinstar bottom)', 
	addr=0x787FA, 
	plmIndex=4, plmsetIndex=65,
	access=function() 
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
	end,
}

local function canGetBackThroughBlueGates()
	return (playerSkills.superMissileGateGlitch and req.supermissile) or req.wave
end

-- the only thing that needs wave:
items:insert{
	name='Energy Tank (pink Brinstar top)', 
	addr=0x78824, 
	plmIndex=1, plmsetIndex=68,
	access=function() 
		return accessPinkBrinstar()
		and canUsePowerBombs() 
		and canGetBackThroughBlueGates()
	end,
}


-- right side of Brinstar (lower green, red, Kraid, etc)


local function accessLowerGreenBrinstar()
	-- technically you can either access pink Brinstar from the left side ...
	-- ... and exit via super missile door
	-- ... or enter via power bombs through the morph ball room
	return (accessPinkBrinstarFromLeft() and req.supermissile)
	or accessPinkBrinstarFromRight()
end

items:insert{
	name = 'Missile (green Brinstar pipe)',
	addr = 0x78676,
	plmIndex=4, plmsetIndex=54,
	access = function() 
		return accessLowerGreenBrinstar()
		and (playerSkills.touchAndGo or req.hijump or req.spacejump) 
	end,
--filter = function(name) return name == 'ice' end,
}

-- what it takes to get into lower green Brinstar
-- either a supermissile through the pink Brinstar door
-- or a powerbomb through the blue Brinstar below Crateria entrance
-- ...
-- what it takes to get into red brinstar is another supermissile door
local function accessRedBrinstar() 
	return canWakeZebes()
	and accessLowerGreenBrinstar()
	and req.supermissile
end

items:insert{
	name='X-Ray Visor', 
	addr=0x78876, 
	plmIndex=1, plmsetIndex=76,
	access=function()
		return accessRedBrinstar() 
		and canUsePowerBombs() 
		and (
			req.grappling 
			or req.spacejump 
			or (effectiveEnergyCount() >= 5 and canUseBombs() and playerSkills.bombTechnique)
		)
	end,
}

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
		-- you can freeze the rippers and jump off of them
		canFreeze'Ripper'
		-- or you can kill the rippers and get up somehow (touch and go, space jump, bomb technique)
		or (
			canKill'Ripper' 
			and (
				playerSkills.touchAndGo
				or playerSkills.bombTechnique 
				or req.spacejump
			)
		)
	)
end

-- you don't need power bombs to get this, 
-- but you need power bombs to escape the overall area
-- another exit constraint shared between multiple items ...
items:insert{
	name = 'Power Bomb (red Brinstar spike room)', 
	addr = 0x7890E, 
	plmIndex=10, plmsetIndex=80,
	access = function() 
		return accessUpperRedBrinstar() 
		-- behind a super missile door
		and req.supermissile
	end,
	escape = function()
		return canUsePowerBombs()
	end,
}

-- behind a powerbomb wall 
items:insert{
	name='Missile (red Brinstar spike room)', 
	addr=0x78914, 
	plmIndex=11, plmsetIndex=80,
	access=function() 
		return accessUpperRedBrinstar() and canUsePowerBombs() 
	end,
}

items:insert{
	name = 'Power Bomb (red Brinstar sidehopper room)', 
	addr = 0x788CA, 
	plmIndex=3, plmsetIndex=79,
	access = function() 
		return accessUpperRedBrinstar() 
		-- super missile door
		and req.supermissile 
		-- power bomb floor
		and canUsePowerBombs() 
	end,
	escape = function()
		-- can't leave until you kill all of your side hoppers 
		return canKill'Big Sidehopper'
	end,
}

-- red Brinstar bottom:

items:insert{
	name='Spazer',
	addr=0x7896E,
	plmIndex=1, plmsetIndex=83,
	access=function() 
		-- getting there:
		return accessRedBrinstar() 
		-- getting up:
		and (playerSkills.touchAndGo or playerSkills.bombTechnique or req.spacejump or req.hijump) 
		-- getting over:
		and canDestroyBombWallsMorphed() 
		-- supermissile door:
		and req.supermissile
	end,
}

local function accessWarehouseKihunterRoom()
	return accessRedBrinstar() 
	-- warehouse entrance
	and (playerSkills.touchAndGo or req.spacejump or req.hijump) 
	-- warehouse zeela room
	and canDestroyBombWallsMorphed() 
end

items:insert{
	name = 'Missile (Kraid)', 
	addr = 0x789EC, 
	plmIndex=13, plmsetIndex=86,
	access = function() 
		return accessWarehouseKihunterRoom() 
		and canUsePowerBombs()
		and (playerSkills.jumpAndMorph or req.springball)
	end,
}

local function accessBabyKraidRoom()
	return accessWarehouseKihunterRoom()
end

local function escapeBabyKraidRoom()
	return canKill'Mini-Kraid'
	and canKill'Green Zebesian'
end

local function accessKraid() 
	return accessBabyKraidRoom()
	and escapeBabyKraidRoom()
end

local function canKillKraid()
	return accessKraid()
	and canKill'Kraid (body)'
end

-- accessible only after kraid is killed
items:insert{
	name = 'Energy Tank (Kraid)', 
	addr = 0x7899C, 
	plmIndex=2, plmsetIndex=85,
	access = canKillKraid,
	escape = function()
		return canKill'Beetom'
	end,
}

items:insert{
	name='Varia Suit', 
	addr=0x78ACA, 
	plmIndex=1, plmsetIndex=95,
	access=canKillKraid,
}


-- Norfair


local accessEnterNorfair = accessRedBrinstar

local function escapeRoomBeforeHiJumpItem()
	return canKill'Norfair Geemer'
	and req.morph
	and canDestroyBombWallsMorphed()
end

items:insert{
	name='Missile (Hi-Jump Boots)',
	addr=0x78BE6,
	plmIndex=6, plmsetIndex=111,
	access=accessEnterNorfair,
	escape=escapeRoomBeforeHiJumpItem,
}

items:insert{
	name='Energy Tank (Hi-Jump Boots)',
	addr=0x78BEC,
	plmIndex=7, plmsetIndex=111,
	access=accessEnterNorfair,
	escape=escapeRoomBeforeHiJumpItem,
}

items:insert{
	name='Hi-Jump Boots', 
	addr=0x78BAC, 
	plmIndex=1, plmsetIndex=109,
	access=accessEnterNorfair, 
	escape=function()
		return escapeRoomBeforeHiJumpItem()
		-- and you need to jump out
		and (playerSkills.touchAndGo or canBombTechnique() or req.hijump or req.spacejump)
	end,
}

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
		)
	) 
	and (
		req.hijump 
		or req.spacejump 
		-- without high jump and without suits it takes about 7 energy tanks
		or (canUseBombs() and effectiveEnergyCount() >= 7)
		or canFreeze 'Norfair Geemer'
	)
end

items:insert{
	name='Missile (lava room)',
	addr=0x78AE4,
	plmIndex=1, plmsetIndex=99,
	access=accessHeatedNorfair,
}

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

items:insert{
	name='Ice Beam',
	addr=0x78B24,
	plmIndex=1, plmsetIndex=104,
	access=accessIce,
}

local function accessMissilesUnderIce()
	return accessIce() and canUsePowerBombs() 
end

items:insert{
	name='Missile (below Ice Beam)',
	addr=0x78B46,
	plmIndex=1, plmsetIndex=106,
	access=accessMissilesUnderIce,
}

-- crocomire takes either wave on the rhs or speed booster and power bombs on the lhs
local function accessCrocomire() 
	-- access crocomire from lhs
	return (accessMissilesUnderIce() and req.speed)
	-- access crocomire from flea run
	or (req.speed and req.wave)
	-- access crocomire from hell run / bubble room
	or (accessHeatedNorfair() and req.wave)
end

items:insert{
	name='Energy Tank (Crocomire)',
	addr=0x78BA4,
	plmIndex=2, plmsetIndex=108,
	access=accessCrocomire,
}

items:insert{
	name='Missile (above Crocomire)',
	addr=0x78BC0,
	plmIndex=3, plmsetIndex=110,
	access=accessCrocomire,
}

items:insert{
	name='Power Bomb (Crocomire)',
	addr=0x78C04,
	plmIndex=1, plmsetIndex=114,
	access=function() 
		return accessCrocomire() 
		and (
			req.spacejump 
			or req.grappling
			or playerSkills.bombTechnique
		)
	end,
}

items:insert{
	name='Missile (below Crocomire)',
	addr=0x78C14,
	plmIndex=1, plmsetIndex=116,
	access=accessCrocomire,
}

items:insert{
	name='Missile (Grappling Beam)',
	addr=0x78C2A,
	plmIndex=1, plmsetIndex=118,
	access=function() 
		return accessCrocomire() 
		and (
			req.spacejump 
			or req.grappling 
			or req.speed
			or playerSkills.bombTechnique
		)
	end,
}

items:insert{
	name='Grappling Beam',
	addr=0x78C36,
	plmIndex=1, plmsetIndex=121,
	access=function() 
		return accessCrocomire() 
		and (
			req.spacejump 
			or (req.speed and req.hijump)
			or playerSkills.bombTechnique
		) 
	end,
}

items:insert{
	name='Missile (bubble Norfair)', 
	addr=0x78C66, 
	plmIndex=3, plmsetIndex=124,
	access=accessHeatedNorfair,
}

items:insert{
	name='Missile (Speed Booster)', 
	addr=0x78C74, 
	plmIndex=2, plmsetIndex=125,
	access=accessHeatedNorfair,
}

items:insert{
	name='Speed Booster', 
	addr=0x78C82, 
	plmIndex=1, plmsetIndex=126,
	access=accessHeatedNorfair,
}

items:insert{
	name='Missile (Wave Beam)', 
	addr=0x78CBC, 
	plmIndex=3, plmsetIndex=128,
	access=accessHeatedNorfair,
}

items:insert{
	name = 'Wave Beam',
	addr = 0x78CCA, 
	plmIndex=1, plmsetIndex=129,
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
		or (playerSkills.touchAndGo and (req.hijump or canFreeze'Waver'))
	)
end

-- upper bubble room ... probably needs high jump or ice ... 
items:insert{
	name='Missile (bubble Norfair green door)', 
	addr=0x78C52, 
	plmIndex=2, plmsetIndex=123,
	access=accessNorfairReserve,
}

items:insert{
	name='Reserve Tank (Norfair)', 
	addr=0x78C3E, 
	plmIndex=1, plmsetIndex=122,
	access=accessNorfairReserve,
}

items:insert{
	name='Missile (Norfair Reserve Tank)', 
	addr=0x78C44, 
	plmIndex=2, plmsetIndex=122,
	access=accessNorfairReserve,
}


-- lower Norfair


local function accessLowerNorfair() 
	return accessHeatedNorfair() 
	-- powerbomb door
	and canUsePowerBombs()
	and (
		-- gravity and space jump is the default option
		(req.gravity and req.spacejump)
		-- you can do it without gravity, but you need precise touch and go, and you need high jump, and enough energy
		or (playerSkills.preciseTouchAndGoLowerNorfair and req.hijump and effectiveEnergyCount() >= 7)
		-- you can do without space jump if you have gravity and high jump -- suit swap
		or (req.gravity and req.hijump and playerSkills.lowerNorfairSuitSwap)
	)
end

local function accessGoldTorizo()
	return accessLowerNorfair()
	and (req.spacejump or playerSkills.superMissileGateGlitch)
end

items:insert{
	name='Missile (Gold Torizo)', 
	addr=0x78E6E, 
	plmIndex=9, plmsetIndex=153,
	access=function()
		return accessGoldTorizo() 
		-- the chozo statue won't let you past the acid bath room without spacejump
		-- and you can't access the missiles from the other side because of the fallthru blocks
		--and req.spacejump
	end,
}

items:insert{
	name='Super Missile (Gold Torizo)',
	addr=0x78E74,
	plmIndex=10, plmsetIndex=153,
	access=accessGoldTorizo,
}

items:insert{
	name='Screw Attack',
	addr=0x79110,
	plmIndex=1, plmsetIndex=172,
	access=accessGoldTorizo,
}

items:insert{
	name='Missile (Mickey Mouse room)', 
	addr=0x78F30, 
	plmIndex=16, plmsetIndex=160,
	access=accessLowerNorfair,
}

items:insert{
	name='Energy Tank (lower Norfair fire flea room)', 
	addr=0x79184, 
	plmIndex=19, plmsetIndex=173,
	access=accessLowerNorfair,
}

items:insert{
	name='Missile (lower Norfair above fire flea room)', 
	addr=0x78FCA, 
	plmIndex=14, plmsetIndex=165,
	access=accessLowerNorfair,
}

items:insert{
	name='Power Bomb (lower Norfair above fire flea room)', 
	addr=0x78FD2, 
	plmIndex=1, plmsetIndex=166,
	access=accessLowerNorfair,
}

-- spade shaped room?
items:insert{
	name='Missile (lower Norfair near Wave Beam)', 
	addr=0x79100, 
	plmIndex=9, plmsetIndex=170,
	access=accessLowerNorfair,
}

items:insert{
	name='Power Bomb (above Ridley)', 
	addr=0x790C0, 
	plmIndex=24, plmsetIndex=168,
	access=accessLowerNorfair,
}

-- these constraints are really for what it takes to kill Ridley
items:insert{
	name='Energy Tank (Ridley)', 
	addr=0x79108, 
	plmIndex=1, plmsetIndex=171,
	access=function() 
		return accessLowerNorfair() 
		-- and you can get through the black zebesian rooms
		and canKill'Black Zebesian (Fighter)'
		-- how much health should we give?
		and effectiveEnergyCount() >= 4 
		-- and you can kill ridley
		and canKill'Ridley'
		-- TODO mix canKill flags with damage, health, etc
		-- you don't need charge.  you can also kill him with a few hundred missiles
		and (req.charge or effectiveMissileCount() >= 250)
	end,
}


-- Wrecked Ship


-- on the way to wrecked ship
items:insert{
	name='Missile (Crateria moat)', 
	addr=0x78248, 
	plmIndex=1, plmsetIndex=17,
	access=function() 
		-- you need to access the landing room
		return accessLandingRoom()
		-- you just need to get through the doors, from there you can jump across
		and req.supermissile and canUsePowerBombs()
	end,
}

local function accessWreckedShip() 
	return 
	-- super missile door from crateria surface
	-- ... or super missile door through pink Brinstar
	req.supermissile 
	-- power bomb door with the flying space pirates in it
	and canUsePowerBombs() 
	-- getting across the water
	and (playerSkills.canJumpAcrossEntranceToWreckedShip or req.spacejump or req.grappling or req.speed)
	-- and you have to make it back to the landing room
	and accessLandingRoom()
end

items:insert{
	name='Missile (outside Wrecked Ship bottom)', 
	addr=0x781E8, 
	plmIndex=3, plmsetIndex=8,
	access=accessWreckedShip,
}

items:insert{
	name='Missile (Wrecked Ship middle)', 
	addr=0x7C265, 
	plmIndex=6, plmsetIndex=183,
	access=accessWreckedShip,
}

local function canKillPhantoon() 
	return accessWreckedShip() 
	and req.charge 
	and (req.gravity or req.varia or effectiveEnergyCount() >= 2) 
	and canKill'Phantoon (body)'
end

items:insert{
	name='Missile (outside Wrecked Ship top)', 
	addr=0x781EE, 
	plmIndex=4, plmsetIndex=8,
	access=canKillPhantoon,
}

items:insert{
	name='Missile (outside Wrecked Ship middle)', 
	addr=0x781F4, 
	plmIndex=5, plmsetIndex=8,
	access=canKillPhantoon,
}

items:insert{
	name='Reserve Tank (Wrecked Ship)', 
	addr=0x7C2E9, 
	plmIndex=5, plmsetIndex=176,
	access=function() return canKillPhantoon() and req.speed end,
}

items:insert{
	name='Missile (Gravity Suit)', 
	addr=0x7C2EF, 
	plmIndex=6, plmsetIndex=176,
	access=canKillPhantoon,
}

items:insert{
	name='Missile (Wrecked Ship top)', 
	addr=0x7C319, 
	plmIndex=1, plmsetIndex=182,
	access=canKillPhantoon,
}

items:insert{
	name='Energy Tank (Wrecked Ship)', 
	addr=0x7C337, 
	plmIndex=1, plmsetIndex=189,
	access=function() 
		return canKillPhantoon() 
		and (req.grappling or req.spacejump
			or effectiveEnergyCount() >= 2
		) 
		--and req.gravity 
	end,
}

items:insert{
	name='Super Missile (Wrecked Ship left)', 
	addr=0x7C357, 
	plmIndex=1, plmsetIndex=198,
	access=canKillPhantoon,
}

items:insert{
	name='Super Missile (Wrecked Ship right)', 
	addr=0x7C365, 
	plmIndex=2, plmsetIndex=200,
	access=canKillPhantoon,
}

local function accessCrateriaAboveWreckedShip()
	-- first you have to kill phantoon
	return canKillPhantoon()
	-- next you have to get through that room with the grey doors
	-- that have atomics and kihunters ...
	and canKill'Atomic' 
	and canKill'Greenish Kihunter'
	-- or canKill'Sparks (Wrecked Ship)'
end


items:insert{
	name='Gravity Suit', 
	addr=0x7C36D, 
	plmIndex=1, plmsetIndex=202,
	access=canKillPhantoon,
}


-- Maridia


local function accessOuterMaridia() 
	-- get to red brinstar
	return accessRedBrinstar() 
	-- break through the tube
	and canUsePowerBombs()
	-- now to get up ...
	and (
		-- if you have gravity, you can get up with touch-and-go, spacejump, hijump, or bomb technique
		(req.gravity and (
			-- you need touch-and-go to get to the balooon grappling room ... but you need suit-swap to get past it ...
			playerSkills.maridiaSuitSwap --playerSkills.touchAndGo 
			or req.spacejump 
			or req.hijump or (playerSkills.bombTechnique and canUseBombs())))
		-- if you don't have gravity then you need high jump and ice.  without gravity you do need high jump just to jump up from the tube that you break, into the next room.
		or (playerSkills.suitlessMaridiaFreezeCrabs and req.hijump and canFreeze'Sciser')
		
		-- suitless is possible so long as the space jump item is replaced with gravity suit to get out of Draygon's room ... or you do the crystal spark + blue spark + whatever move that I don't know how to do
	)
end

items:insert{
	name='Missile (green Maridia shinespark)', 
	addr=0x7C437, 
	plmIndex=3, plmsetIndex=208,
	access=function() return accessOuterMaridia() and req.speed end,
}

items:insert{
	name='Super Missile (green Maridia)', 
	addr=0x7C43D, 
	plmIndex=4, plmsetIndex=208,
	access=accessOuterMaridia,
}

items:insert{
	name='Energy Tank (green Maridia)', 
	addr=0x7C47D, 
	plmIndex=1, plmsetIndex=210,
	access=function() return accessOuterMaridia() and (req.speed or req.grappling or req.spacejump) end,
}

items:insert{
	name='Missile (green Maridia tatori)', 
	addr=0x7C483, 
	plmIndex=2, plmsetIndex=210,
	access=accessOuterMaridia,
}

local function accessInnerMaridia() 
	return accessOuterMaridia() 
	and (req.spacejump or req.grappling or req.speed or (req.gravity and playerSkills.touchAndGo)) 
end

-- top of maridia
items:insert{
	name='Super Missile (yellow Maridia)', 
	addr=0x7C4AF, 
	plmIndex=2, plmsetIndex=214,
	access=accessInnerMaridia,
}

items:insert{
	name='Missile (yellow Maridia super missile)', 
	addr=0x7C4B5, 
	plmIndex=3, plmsetIndex=214,
	access=accessInnerMaridia,
}

items:insert{
	name='Missile (yellow Maridia false wall)', 
	addr=0x7C533, 
	plmIndex=9, plmsetIndex=217,
	access=accessInnerMaridia,
}

local function accessBotwoon()
	return accessInnerMaridia() 
	and (
		(playerSkills.freezeTheMocktroidToGetToBotwoon and canFreeze'Mochtroid') 
		-- need to speed boost underwater
		or (req.gravity and req.speed)
	)
end

local function canKillBotwoon() 
	return accessBotwoon()
	and canKill'Botwoon'
end

local function canKillDraygon() 
	return canKillBotwoon() 
	and canKill'Draygon (body)'
end

-- This item requires plasma *to exit*
--  but this is no different from the super missile after spore spawn requiring super missile *to exit*
-- so I propose to use a different constraint for items in these situations.
-- Maybe I should make the randomizer to only put worthless items in these places?
--  Otherwise I can't make randomizations that don't include the plasma item. 
items:insert{
	name = 'Plasma Beam',
	addr = 0x7C559,
	plmIndex=2, plmsetIndex=221,
	access = canKillDraygon,
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

items:insert{
	name='Missile (left Maridia sand pit room)', 
	addr=0x7C5DD, 
	plmIndex=1, plmsetIndex=233,
	access=function() 
		return accessOuterMaridia() 
		and (canUseBombs() or canUseSpringBall())
	end,
}

-- also left sand pit room 
items:insert{
	name='Reserve Tank (Maridia)', 
	addr=0x7C5E3, 
	plmIndex=2, plmsetIndex=233,
	access=function() 
		return accessOuterMaridia() and (canUseBombs() or canUseSpringBall()) 
	end,
}

items:insert{
	name='Missile (right Maridia sand pit room)', 
	addr=0x7C5EB, 
	plmIndex=1, plmsetIndex=234,
	access=accessOuterMaridia,
}

items:insert{
	name='Power Bomb (right Maridia sand pit room)', 
	addr=0x7C5F1, 
	plmIndex=2, plmsetIndex=234,
	access=accessOuterMaridia,
}

-- room with the shell things
items:insert{
	name='Missile (pink Maridia)', 
	addr=0x7C603, 
	plmIndex=2, plmsetIndex=237,
	access=function() return accessOuterMaridia() and req.speed end,
}

items:insert{
	name='Super Missile (pink Maridia)', 
	addr=0x7C609, 
	plmIndex=3, plmsetIndex=237,
	access=function() return accessOuterMaridia() and req.speed end,
}

-- here's another fringe item
-- requires grappling, but what if we put something unimportant there? who cares about it then?
items:insert{
	name='Spring Ball', 
	addr=0x7C6E5, 
	plmIndex=1, plmsetIndex=242,
	access=function() 
		return accessOuterMaridia() 
		and req.grappling 
		and (playerSkills.touchAndGo or req.spacejump)
	end,
}

-- missile right before draygon?
items:insert{
	name='Missile (Draygon)', 
	addr=0x7C74D, 
	plmIndex=12, plmsetIndex=246,
	access=canKillDraygon,
}

-- energy tank right after botwoon
items:insert{
	name='Energy Tank (Botwoon)', 
	addr=0x7C755, 
	plmIndex=1, plmsetIndex=247,
	access=canKillBotwoon,
}

-- technically you don't need gravity to get to this item 
-- ... but you need it to escape Draygon's area
items:insert{
	name = 'Space Jump', 
	addr = 0x7C7A7, 
	plmIndex=1, plmsetIndex=255,
	access = canKillDraygon,
	escape = function()
		-- if the player knows the crystal-flash-whatever trick then fine
		return playerSkills.DraygonCrystalFlashBlueSparkWhatever
		-- otherwise they will need both gravity and either spacejump or bombs
		or (req.gravity and (req.spacejump or canUseBombs()))
	end,
}
--]]

-- this is a subset of plm cmds in sm-map
SMItems.itemTypes = table{
	energy 			= 0xeed7,
	missile 		= 0xeedb,
	supermissile	= 0xeedf,
	powerbomb		= 0xeee3,
	bomb			= 0xeee7,
	charge			= 0xeeeb,
	ice				= 0xeeef,
	hijump			= 0xeef3,
	speed			= 0xeef7,
	wave			= 0xeefb,
	spazer 			= 0xeeff,
	springball		= 0xef03,
	varia			= 0xef07,
	plasma			= 0xef13,
	grappling		= 0xef17,
	morph			= 0xef23,
	reserve			= 0xef27,
	gravity			= 0xef0b,
	xray			= 0xef0f,
	spacejump 		= 0xef1b,
	screwattack		= 0xef1f,
}

-- add 84 = 0x54 to get to chozo , another 84 = 0x54 to hidden
SMItems.itemTypeBaseForType = {}
for _,k in ipairs(SMItems.itemTypes:keys()) do
	local v = SMItems.itemTypes[k]
	SMItems.itemTypeBaseForType[v] = v
	SMItems.itemTypes[k..'_chozo'] = v + 0x54	-- _chozo really means shoot to open, then it resolidifies 
	SMItems.itemTypeBaseForType[v + 0x54] = v
	SMItems.itemTypes[k..'_hidden'] = v + 2*0x54	-- _hidden really means shoot to open and it stays open
	SMItems.itemTypeBaseForType[v + 2*0x54] = v
end

SMItems.itemTypeNameForValue = SMItems.itemTypes:map(function(v,k) return k,v end)

function SMItems:itemsInit()
	local rom = self.rom
	local sm = self

	self.items = table(items)

	for _,item in ipairs(self.items) do
		-- ptr to the item type
		-- ANOTHER TODO: enemies[] addr is 16-bit, while items[] addr is PC /  24-bit. pick one method and stick with it.
		-- TODO I bet this is part of a bigger structure, maybe with position, etc
		--item.ptr = ffi.cast('uint16_t*', rom + item.addr)

		-- no need to use item.addr anymore, now we can use the plm
		--local plm = self.plmsets[item.plmsetIndex].plms[item.plmIndex]
		--assert(plm.cmd == item.ptr[0])

		-- use the original plm reference so that, if we remove any plms later, we are still pointing to the original correct thing
		item.plmset = assert(self.plmsets[item.plmsetIndex])
		item.plm = self.plmsets[item.plmsetIndex].plms[item.plmIndex]

		function item:getCmd()
			-- don't use plmsetIndex and plmIndex here in case we've removed a plm preceding this one 
			--return sm.plmsets[item.plmsetIndex].plms[item.plmIndex].cmd
			return item.plm.cmd
		end
		function item:setCmd(value)
			-- don't use plmsetIndex and plmIndex here in case we've removed a plm preceding this one 
			--sm.plmsets[item.plmsetIndex].plms[item.plmIndex].cmd = value
			item.plm.cmd = value
		end

--local ptr = ffi.cast('uint16_t*', rom + item.addr)
--assert(ptr[0] == item:getCmd(), "looks like the item plm/plmset don't match up with the value at the original address.  maybe something changed the plms around before the map could read them.")	
	end

--[[ debugging - determine original item index order
print('item original indexing')
table(self.items):sort(function(a,b) return a.plm.args < b.plm.args end):mapi(function(item)
	print(item.plm.args, item.name)	
end)
--[=[ and the values, separated in groups of 8:

0	Power Bomb (Crateria surface)
1	Missile (outside Wrecked Ship bottom)
2	Missile (outside Wrecked Ship top)
3	Missile (outside Wrecked Ship middle)
4	Missile (Crateria moat)
5	Energy Tank (Crateria gauntlet)
6	Missile (Crateria bottom)
7	Bomb

8	Energy Tank (Crateria tunnel to Brinstar)
9	Missile (Crateria gauntlet right)
10	Missile (Crateria gauntlet left)
11	Super Missile (Crateria)
12	Missile (Crateria middle)
13	Power Bomb (green Brinstar bottom)
14	Super Missile (pink Brinstar)
15	Missile (green Brinstar below super missile)

16	Super Missile (green Brinstar top)
17	Reserve Tank (Brinstar)
18	Missile (green Brinstar behind missile)
19	Missile (green Brinstar behind Reserve Tank)
21	Missile (pink Brinstar top)
22	Missile (pink Brinstar bottom)
23	Charge Beam

24	Power Bomb (pink Brinstar)
25	Missile (green Brinstar pipe)
26	Morphing Ball
27	Power Bomb (blue Brinstar)
28	Missile (blue Brinstar middle)
29	Energy Tank (blue Brinstar)
30	Energy Tank (green Brinstar bottom)
31	Super Missile (green Brinstar bottom)

33	Energy Tank (pink Brinstar bottom)
34	Missile (blue Brinstar bottom)
35	Energy Tank (pink Brinstar top)
36	Missile (blue Brinstar top)
37	Missile (blue Brinstar behind missile)
38	X-Ray Visor
39	Power Bomb (red Brinstar sidehopper room)

40	Power Bomb (red Brinstar spike room)
41	Missile (red Brinstar spike room)
42	Spazer
43	Energy Tank (Kraid)
44	Missile (Kraid)

48	Varia Suit
49	Missile (lava room)
50	Ice Beam
51	Missile (below Ice Beam)
52	Energy Tank (Crocomire)
53	Hi-Jump Boots
54	Missile (above Crocomire)
55	Missile (Hi-Jump Boots)

56	Energy Tank (Hi-Jump Boots)
57	Power Bomb (Crocomire)
58	Missile (below Crocomire)
59	Missile (Grappling Beam)
60	Grappling Beam
61	Reserve Tank (Norfair)
62	Missile (Norfair Reserve Tank)
63	Missile (bubble Norfair green door)

64	Missile (bubble Norfair)
65	Missile (Speed Booster)
66	Speed Booster
67	Missile (Wave Beam)
68	Wave Beam
70	Missile (Gold Torizo)
71	Super Missile (Gold Torizo)

73	Missile (Mickey Mouse room)
74	Missile (lower Norfair above fire flea room)
75	Power Bomb (lower Norfair above fire flea room)
76	Power Bomb (above Ridley)
77	Missile (lower Norfair near Wave Beam)
78	Energy Tank (Ridley)
79	Screw Attack

80	Energy Tank (lower Norfair fire flea room)

128	Missile (Wrecked Ship middle)
129	Reserve Tank (Wrecked Ship)
130	Missile (Gravity Suit)
131	Missile (Wrecked Ship top)
132	Energy Tank (Wrecked Ship)
133	Super Missile (Wrecked Ship left)
134	Super Missile (Wrecked Ship right)
135	Gravity Suit

136	Missile (green Maridia shinespark)
137	Super Missile (green Maridia)
138	Energy Tank (green Maridia)
139	Missile (green Maridia tatori)
140	Super Missile (yellow Maridia)
141	Missile (yellow Maridia super missile)
142	Missile (yellow Maridia false wall)
143	Plasma Beam

144	Missile (left Maridia sand pit room)
145	Reserve Tank (Maridia)
146	Missile (right Maridia sand pit room)
147	Power Bomb (right Maridia sand pit room)
148	Missile (pink Maridia)
149	Super Missile (pink Maridia)
150	Spring Ball
151	Missile (Draygon)

152	Energy Tank (Botwoon)
154	Space Jump

--]=]
--]]


	self.itemsForName = self.items:map(function(item) return item, item.name end)
-- don't use addr anymore
--	self.itemsForAddr = self.items:map(function(item) return item, item.addr end)
end


-- this doesn't do anything
-- items are just plms with specific cmds
function SMItems:itemsBuildMemoryMap(mem)
	--[[
	for _,item in ipairs(self.items) do
		mem:add(item.addr, 2, 'item: '..item.name)
	end
	--]]
end

return SMItems
