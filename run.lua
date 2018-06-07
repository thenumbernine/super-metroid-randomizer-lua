#!/usr/bin/env luajit
require 'ext'
local ffi = require 'ffi'

require 'ffi.c.stdlib'

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

-- [[
local function CanUsePowerBombs() return req.powerbomb() and req.morph() end
local function CanDestroyBombWalls() return (req.bomb() and req.morph()) or CanUsePowerBombs() or req.screwattack() end
local function CanPassBombPassages() return (req.bomb() and req.morph()) or (req.powerbomb() and req.morph()) end
local function CanAccessRedBrinstar() return req.supermissile() and ((CanDestroyBombWalls() and req.morph()) or (CanUsePowerBombs())) end
local function CanAccessKraid() return CanAccessRedBrinstar() and (req.spacejump() or req.hijump()) and CanPassBombPassages() end
local function EnergyReserveCount() return (req.energy() or 0) + math.min((req.energy() or 0) + 1, req.reserve() or 0) end
local function CanAccessOuterMaridia() return CanAccessRedBrinstar() and req.powerbomb() and req.gravity() and (req.spacejump() or req.hijump()) end
local function CanAccessInnerMaridia() return CanAccessOuterMaridia() and (req.spacejump() or req.grappling() or req.speed()) end
local function CanDefeatBotwoon() return CanAccessInnerMaridia() and (req.ice() or req.speed()) end
local function CanDefeatDraygon() return CanDefeatBotwoon() and req.spacejump() and EnergyReserveCount() >= 3 end
local function CanAccessHeatedNorfair() return CanAccessRedBrinstar() and (req.spacejump() or req.hijump()) and (req.varia() or req.gravity()) end
local function CanAccessLowerNorfair() return CanAccessHeatedNorfair() and req.powerbomb() and req.gravity() and req.spacejump() end
local function CanAccessCrocomire() return CanAccessHeatedNorfair() and ((req.speed() and CanUsePowerBombs()) or req.wave()) end
local function CanOpenMissileDoors() return req.missile() or req.supermissile() end
local function CanEnterAndLeaveGauntlet() return (req.bomb() and req.morph()) or ((req.powerbomb() or 0) >= 2 and req.morph()) or req.screwattack() end
local function CanAccessWs() return req.supermissile() and CanUsePowerBombs() and (req.spacejump() or req.grappling() or req.speed()) end
local function CanDefeatPhantoon() return CanAccessWs() and req.charge() and (req.gravity() or req.varia() or EnergyReserveCount() >= 2) end

local locations = table{
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Power Bomb (Crateria surface)", addr=0x781CC, access=function() return req.powerbomb() and (req.speed() or req.spacejump() or req.bomb()) end},
	{GravityOkay=false, Region='Crateria', name="Missile (outside Wrecked Ship bottom)", addr=0x781E8, access=CanAccessWs},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (outside Wrecked Ship top)", addr=0x781EE, ItemStorageType='Hidden', access=CanDefeatPhantoon},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (outside Wrecked Ship middle)", addr=0x781F4, access=CanDefeatPhantoon},
	{NoHidden=true, GravityOkay=false, Region='Crateria', name="Missile (Crateria moat)", addr=0x78248, access=function() return req.supermissile() and req.powerbomb() end},
	{NoHidden=true, GravityOkay=false, Region='Crateria', name="Energy Tank (Crateria gauntlet)", addr=0x78264, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump() or req.speed()) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (Crateria bottom)", addr=0x783EE, access=CanDestroyBombWalls},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Bomb", addr=0x78404, ItemStorageType='Chozo', access=function() return CanOpenMissileDoors() and CanPassBombPassages() end},
	{NoHidden=true, GravityOkay=false, Region='Crateria', name="Energy Tank (Crateria tunnel to Brinstar)", addr=0x78432, access=CanDestroyBombWalls},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (Crateria gauntlet right)", addr=0x78464, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump() or req.speed()) and CanPassBombPassages() end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (Crateria gauntlet left)", addr=0x7846A, access=function() return CanEnterAndLeaveGauntlet() and (req.spacejump() or req.speed()) and CanPassBombPassages() end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Super Missile (Crateria)", addr=0x78478, access=function() return CanUsePowerBombs() and req.speed() and (EnergyReserveCount() >= 1 or req.varia() or req.gravity()) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', name="Missile (Crateria middle)", addr=0x78486, access=CanPassBombPassages},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Power Bomb (green Brinstar bottom)", addr=0x784AC, ItemStorageType='Chozo', access=CanUsePowerBombs},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Super Missile (pink Brinstar)", addr=0x784E4, ItemStorageType='Chozo', access=function() return CanPassBombPassages() and req.supermissile() end},
	{NoHidden=true, GravityOkay=false, Region='Brinstar', name="Missile (green Brinstar below super missile)", addr=0x78518, access=function() return CanPassBombPassages() and CanOpenMissileDoors() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Super Missile (green Brinstar top)", addr=0x7851E, access=function() return CanDestroyBombWalls() and CanOpenMissileDoors() and req.speed() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Reserve Tank (Brinstar)", addr=0x7852C, ItemStorageType='Chozo', access=function() return CanDestroyBombWalls() and CanOpenMissileDoors() and req.speed() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (green Brinstar behind missile)", addr=0x78532, ItemStorageType='Hidden', access=function() return CanPassBombPassages() and CanOpenMissileDoors() and req.speed() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (green Brinstar behind Reserve Tank)", addr=0x78538, access=function() return CanDestroyBombWalls() and CanOpenMissileDoors() and req.speed() and req.morph() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (pink Brinstar top)", addr=0x78608, access=function() return CanDestroyBombWalls() and CanOpenMissileDoors() and (req.grappling() or req.spacejump() or req.speed()) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (pink Brinstar bottom)", addr=0x7860E, access=function() return (CanDestroyBombWalls() and CanOpenMissileDoors()) or CanUsePowerBombs() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Charge Beam", addr=0x78614, ItemStorageType='Chozo', access=function() return (CanPassBombPassages() and CanOpenMissileDoors()) or CanUsePowerBombs() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Power Bomb (pink Brinstar)", addr=0x7865C, access=function() return CanUsePowerBombs() and req.supermissile() and (req.grappling() or req.spacejump() or req.speed()) end,    },
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (green Brinstar pipe)", addr=0x78676, access=function() return ((CanPassBombPassages() and req.supermissile()) or CanUsePowerBombs()) and (req.hijump() or req.spacejump()) end},
	{NoHidden=true, GravityOkay=false, Region='Brinstar', name="Morphing Ball", addr=0x786DE, access=function() return true end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Power Bomb (blue Brinstar)", addr=0x7874C, access=CanUsePowerBombs},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (blue Brinstar middle)", addr=0x78798, access=function() return CanOpenMissileDoors() and req.morph() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Energy Tank (blue Brinstar)", addr=0x7879E, ItemStorageType='Hidden', access=function() return CanOpenMissileDoors() and (req.hijump() or req.speed() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Energy Tank (green Brinstar bottom)", addr=0x787C2, access=CanUsePowerBombs},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Super Missile (green Brinstar bottom)", addr=0x787D0, access=function() return CanUsePowerBombs() and req.supermissile() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Energy Tank (pink Brinstar bottom)", addr=0x787FA, access=function() return CanUsePowerBombs() and CanOpenMissileDoors() and req.speed() and req.gravity() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (blue Brinstar bottom)", addr=0x78802, ItemStorageType='Chozo', access=function() return req.morph() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Energy Tank (pink Brinstar top)", addr=0x78824, access=function() return CanUsePowerBombs() and req.wave() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (blue Brinstar top)", addr=0x78836, access=function() return CanOpenMissileDoors() and CanUsePowerBombs() and (req.speed() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (blue Brinstar behind missile)", addr=0x7883C, ItemStorageType='Hidden', access=function() return CanOpenMissileDoors() and CanUsePowerBombs() and (req.speed() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="X-Ray Visor", addr=0x78876, ItemStorageType='Chozo', access=function() return CanAccessRedBrinstar() and CanUsePowerBombs() and (req.grappling() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Power Bomb (red Brinstar sidehopper room)", addr=0x788CA, access=function() return CanAccessRedBrinstar() and CanUsePowerBombs() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Power Bomb (red Brinstar spike room)", addr=0x7890E, ItemStorageType='Chozo', access=function() return CanAccessRedBrinstar() and CanUsePowerBombs() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (red Brinstar spike room)", addr=0x78914, access=function() return CanAccessRedBrinstar() and CanUsePowerBombs() end},
	{GravityOkay=false, Region='Brinstar', name="Spazer", addr=0x7896E, ItemStorageType='Chozo', access=function() return CanAccessRedBrinstar() and CanPassBombPassages() and (req.spacejump() or req.hijump()) end},
	{GravityOkay=false, Region='Brinstar', name="Energy Tank (Kraid)", addr=0x7899C, ItemStorageType='Hidden', access=CanAccessKraid},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Missile (Kraid)", addr=0x789EC, ItemStorageType='Hidden', access=function() return CanAccessKraid() and CanUsePowerBombs() end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', name="Varia Suit", addr=0x78ACA, ItemStorageType='Chozo', access=CanAccessKraid},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (lava room)", addr=0x78AE4, ItemStorageType='Hidden', access=CanAccessHeatedNorfair},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Ice Beam", addr=0x78B24, ItemStorageType='Chozo', access=function() return CanAccessKraid() and (req.gravity() or req.varia()) and req.speed() and (CanUsePowerBombs() or req.ice()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (below Ice Beam)", addr=0x78B46, ItemStorageType='Hidden', access=function() return CanAccessHeatedNorfair() and CanUsePowerBombs() and req.speed() end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Energy Tank (Crocomire)", addr=0x78BA4, access=CanAccessCrocomire},
	{NoHidden=false, GravityOkay=false, Region='Norfair', name="Hi-Jump Boots", addr=0x78BAC, ItemStorageType='Chozo', access=CanAccessRedBrinstar},
	{NoHidden=true, GravityOkay=true, Region='Norfair', name="Missile (above Crocomire)", addr=0x78BC0, access=function() return CanAccessCrocomire() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=false, Region='Norfair', name="Missile (Hi-Jump Boots)", addr=0x78BE6, access=CanAccessRedBrinstar},
	{NoHidden=false, GravityOkay=false, Region='Norfair', name="Energy Tank (Hi-Jump Boots)", addr=0x78BEC, access=CanAccessRedBrinstar},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Power Bomb (Crocomire)", addr=0x78C04, access=function() return CanAccessCrocomire() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (below Crocomire)", addr=0x78C14, access=CanAccessCrocomire},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (Grapple Beam)", addr=0x78C2A, access=function() return CanAccessCrocomire() and (req.spacejump() or req.grappling() or req.speed()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Grapple Beam", addr=0x78C36, ItemStorageType='Chozo', access=function() return CanAccessCrocomire() and (req.spacejump() or (req.speed() and req.hijump())) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Reserve Tank (Norfair)", addr=0x78C3E, ItemStorageType='Chozo', access=function() return CanAccessHeatedNorfair() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (Norfair Reserve Tank)", addr=0x78C44, ItemStorageType='Hidden', access=function() return CanAccessHeatedNorfair() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (bubble Norfair green door)", addr=0x78C52, access=function() return CanAccessHeatedNorfair() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (bubble Norfair)", addr=0x78C66, access=CanAccessHeatedNorfair},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (Speed Booster)", addr=0x78C74, ItemStorageType='Hidden', access=CanAccessHeatedNorfair},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Speed Booster", addr=0x78C82, ItemStorageType='Chozo', access=CanAccessHeatedNorfair},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Missile (Wave Beam)", addr=0x78CBC, access=CanAccessHeatedNorfair},
	{NoHidden=false, GravityOkay=true, Region='Norfair', name="Wave Beam", addr=0x78CCA, ItemStorageType='Chozo', access=function() return CanAccessHeatedNorfair() and (req.spacejump() or req.grappling()) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Missile (Gold Torizo)", addr=0x78E6E, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Super Missile (Gold Torizo)", addr=0x78E74, ItemStorageType='Hidden', access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Missile (Mickey Mouse room)", addr=0x78F30, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Missile (lower Norfair above fire flea room)", addr=0x78FCA, access=CanAccessLowerNorfair},
	{NoHidden=true, GravityOkay=true, Region='LowerNorfair', name="Power Bomb (lower Norfair above fire flea room)", addr=0x78FD2, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Power Bomb (above Ridley)", addr=0x790C0, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Missile (lower Norfair near Wave Beam)", addr=0x79100, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Energy Tank (Ridley)", addr=0x79108, ItemStorageType='Hidden', access=function() return CanAccessLowerNorfair() and req.charge() and EnergyReserveCount() >= 4 end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Screw Attack", addr=0x79110, ItemStorageType='Chozo', access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', name="Energy Tank (lower Norfair fire flea room)", addr=0x79184, access=CanAccessLowerNorfair},
	{NoHidden=false, GravityOkay=false, Region='WreckedShip', name="Missile (Wrecked Ship middle)", addr=0x7C265, access=CanAccessWs},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Reserve Tank (Wrecked Ship)", addr=0x7C2E9, ItemStorageType='Chozo', access=function() return CanDefeatPhantoon() and req.speed() end},
	{NoHidden=true, GravityOkay=true, Region='WreckedShip', name="Missile (Gravity Suit)", addr=0x7C2EF, access=CanDefeatPhantoon},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Missile (Wrecked Ship top)", addr=0x7C319, access=CanDefeatPhantoon},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Energy Tank (Wrecked Ship)", addr=0x7C337, access=function() return CanDefeatPhantoon() and req.gravity() and (req.grappling() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Super Missile (Wrecked Ship left)", addr=0x7C357, access=CanDefeatPhantoon},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Super Missile (Wrecked Ship right)", addr=0x7C365, access=CanDefeatPhantoon},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', name="Gravity Suit", addr=0x7C36D, ItemStorageType='Chozo', access=CanDefeatPhantoon},
	{NoHidden=true, GravityOkay=true, Region='Maridia', name="Missile (green Maridia shinespark)", addr=0x7C437, access=function() return CanAccessOuterMaridia() and req.speed() end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Super Missile (green Maridia)", addr=0x7C43D, access=CanAccessOuterMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Energy Tank (green Maridia)", addr=0x7C47D, access=function() return CanAccessOuterMaridia() and (req.speed() or req.grappling() or req.spacejump()) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (green Maridia tatori)", addr=0x7C483, ItemStorageType='Hidden', access=CanAccessOuterMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Super Missile (yellow Maridia)", addr=0x7C4AF, access=CanAccessInnerMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (yellow Maridia super missile)", addr=0x7C4B5, access=CanAccessInnerMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (yellow Maridia false wall)", addr=0x7C533, access=CanAccessInnerMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Plasma Beam", addr=0x7C559, ItemStorageType='Chozo', access=function() return CanDefeatDraygon() and req.spacejump() and (req.screwattack() or req.plasma()) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (left Maridia sand pit room)", addr=0x7C5DD, access=function() return CanAccessOuterMaridia() and req.morph() and (req.springball() or req.bomb()) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Reserve Tank (Maridia)", addr=0x7C5E3, ItemStorageType='Chozo', access=function() return CanAccessOuterMaridia() and req.morph() and (req.springball() or req.bomb()) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (right Maridia sand pit room)", addr=0x7C5EB, access=CanAccessOuterMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Power Bomb (right Maridia sand pit room)", addr=0x7C5F1, access=CanAccessOuterMaridia},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (pink Maridia)", addr=0x7C603, access=function() return CanAccessOuterMaridia() and req.speed() end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Super Missile (pink Maridia)", addr=0x7C609, access=function() return CanAccessOuterMaridia() and req.speed() end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Spring Ball", addr=0x7C6E5, ItemStorageType='Chozo', access=function() return CanAccessOuterMaridia() and req.grappling() and req.spacejump() end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Missile (Draygon)", addr=0x7C74D, ItemStorageType='Hidden', access=CanDefeatDraygon},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Energy Tank (Botwoon)", addr=0x7C755, access=CanDefeatBotwoon},
	{NoHidden=false, GravityOkay=true, Region='Maridia', name="Space Jump", addr=0x7C7A7, ItemStorageType='Chozo', access=CanDefeatDraygon},
}
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


-- [[
local sofar = table{}
req = setmetatable({}, {
	__index = function(t,k)
		return function()
			return sofar[k]
		end
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

	local chooseLocs = currentLocs:filter(function(loc) return loc.access() end)
	dprint('options to replace: '..tolua(chooseLocs:map(function(loc,i,t) return (t[loc.defaultName] or 0) + 1, loc.defaultName end)))

	-- pick an item to replace
	if #chooseLocs == 0 then 
		dprint('we ran out of options with '..#currentLocs..' items unplaced!')
		return
	end
	local chooseLoc = chooseLocs[math.random(#chooseLocs)]
	dprint('choosing to replace '..chooseLoc.defaultName)
	
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
		dprint('...with '..objNameForValue[origItems[replaceInstIndex]])

		local value = origItems[replaceInstIndex]
		local name = objNameForValue[value]

		-- now replace it with an item
		local push_sofar = table(sofar)
		sofar[name] = (sofar[name] or 0) + 1

		-- TODO write it here.  only really works with depth-first searching.
		itemInsts[replaceInstIndex].value = value

		local push_currentLocs = table(currentLocs)
		currentLocs = nextLocs

		dprint('iterating...')
		if iterate(depth + 1) then return true end

		currentLocs = push_currentLocs
		sofar = push_sofar
		itemInstIndexesLeft = push_itemInstIndexesLeft
	end
end	
iterate()

--]]



-- [[ filter out bombs and morph ball, so we know the run is possible 
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
print('found '..#itemInsts..' items')
print('found '..#doorInsts..' doors')
print(tolua(countsForType):gsub(', ', ',\n\t'))

local itemInstValues = itemInsts:map(function(item) return item.value end)
shuffle(itemInstValues)
for i=1,#itemInsts do itemInsts[i].value = itemInstValues[i] end


for i,item in ipairs(itemInsts) do
	wr2b(item.addr, item.value)
end
for i,door in ipairs(doorInsts) do
	wr2b(door.addr, door.value)
end

file[outfilename] = header .. rom

print('done converting '..infilename..' => '..outfilename)
