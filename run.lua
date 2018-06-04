#!/usr/bin/env luajit
require 'ext'
local ffi = require 'ffi'

require 'ffi.c.stdlib'

local seed = os.time() 
math.randomseed(seed)
for i=1,100 do math.random() end
seed = math.random(0,0x7fffffff)
print('seed', ('%x'):format(seed))
math.randomseed(seed)

local infilename = select(1, ...) or 'sm.sfc'
local outfilename = select(2, ...) or 'sm-random.sfc'

-- [[
local locations = table{
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Power Bomb (Crateria surface)", Address=0x781CC, CanAccess=function(have) return CanUsePowerBombs(have) and (have.Contains(ItemType.SpeedBooster) or have.Contains(ItemType.SpaceJump)) end},
	{GravityOkay=false, Region='Crateria', Name="Missile (outside Wrecked Ship bottom)", Address=0x781E8, CanAccess=function(have) return CanAccessWs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (outside Wrecked Ship top)", Address=0x781EE, ItemStorageType='Hidden', CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (outside Wrecked Ship middle)", Address=0x781F4, CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=true, GravityOkay=false, Region='Crateria', Name="Missile (Crateria moat)", Address=0x78248, CanAccess=function(have) return have.Contains(ItemType.SuperMissile) and CanUsePowerBombs(have) end},
	{NoHidden=true, GravityOkay=false, Region='Crateria', Name="Energy Tank (Crateria gauntlet)", Address=0x78264, CanAccess=function(have) return CanEnterAndLeaveGauntlet(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.SpeedBooster)) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (Crateria bottom)", Address=0x783EE, CanAccess=function(have) return CanDestroyBombWalls(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Bomb", Address=0x78404, ItemStorageType='Chozo', CanAccess=function(have) return CanOpenMissileDoors(have) and CanPassBombPassages(have) end},
	{NoHidden=true, GravityOkay=false, Region='Crateria', Name="Energy Tank (Crateria tunnel to Brinstar)", Address=0x78432, CanAccess=function(have) return CanDestroyBombWalls(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (Crateria gauntlet right)", Address=0x78464, CanAccess=function(have) return CanEnterAndLeaveGauntlet(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.SpeedBooster)) and CanPassBombPassages(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (Crateria gauntlet left)", Address=0x7846A, CanAccess=function(have) return CanEnterAndLeaveGauntlet(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.SpeedBooster)) and CanPassBombPassages(have) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Super Missile (Crateria)", Address=0x78478, CanAccess=function(have) return CanUsePowerBombs(have) and have.Contains(ItemType.SpeedBooster) and (EnergyReserveCount(have) >= 1 or have.Contains(ItemType.VariaSuit) or have.Contains(ItemType.GravitySuit)) end},
	{NoHidden=false, GravityOkay=false, Region='Crateria', Name="Missile (Crateria middle)", Address=0x78486, CanAccess=function(have) return CanPassBombPassages(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Power Bomb (green Brinstar bottom)", Address=0x784AC, ItemStorageType='Chozo', CanAccess=function(have) return CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Super Missile (pink Brinstar)", Address=0x784E4, ItemStorageType='Chozo', CanAccess=function(have) return CanPassBombPassages(have) and have.Contains(ItemType.SuperMissile) end},
	{NoHidden=true, GravityOkay=false, Region='Brinstar', Name="Missile (green Brinstar below super missile)", Address=0x78518, CanAccess=function(have) return CanPassBombPassages(have) and CanOpenMissileDoors(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Super Missile (green Brinstar top)", Address=0x7851E, CanAccess=function(have) return CanDestroyBombWalls(have) and CanOpenMissileDoors(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Reserve Tank (Brinstar)", Address=0x7852C, ItemStorageType='Chozo', CanAccess=function(have) return CanDestroyBombWalls(have) and CanOpenMissileDoors(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (green Brinstar behind missile)", Address=0x78532, ItemStorageType='Hidden', CanAccess=function(have) return CanPassBombPassages(have) and CanOpenMissileDoors(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (green Brinstar behind Reserve Tank)", Address=0x78538, CanAccess=function(have) return CanDestroyBombWalls(have) and CanOpenMissileDoors(have) and have.Contains(ItemType.SpeedBooster) and have.Contains(ItemType.MorphingBall) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (pink Brinstar top)", Address=0x78608, CanAccess=function(have) return CanDestroyBombWalls(have) and CanOpenMissileDoors(have) and (have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.SpeedBooster)) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (pink Brinstar bottom)", Address=0x7860E, CanAccess=function(have) return (CanDestroyBombWalls(have) and CanOpenMissileDoors(have)) or CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Charge Beam", Address=0x78614, ItemStorageType='Chozo', CanAccess=function(have) return (CanPassBombPassages(have) and CanOpenMissileDoors(have)) or CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Power Bomb (pink Brinstar)", Address=0x7865C, CanAccess=function(have) return CanUsePowerBombs(have) and have.Contains(ItemType.SuperMissile) and (have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.SpeedBooster)) end,    },
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (green Brinstar pipe)", Address=0x78676, CanAccess=function(have) return ((CanPassBombPassages(have) and have.Contains(ItemType.SuperMissile)) or CanUsePowerBombs(have)) and (have.Contains(ItemType.HiJumpBoots) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=true, GravityOkay=false, Region='Brinstar', Name="Morphing Ball", Address=0x786DE, CanAccess=function(have) return true end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Power Bomb (blue Brinstar)", Address=0x7874C, CanAccess=function(have) return CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (blue Brinstar middle)", Address=0x78798, CanAccess=function(have) return CanOpenMissileDoors(have) and have.Contains(ItemType.MorphingBall) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Energy Tank (blue Brinstar)", Address=0x7879E, ItemStorageType='Hidden', CanAccess=function(have) return CanOpenMissileDoors(have) and (have.Contains(ItemType.HiJumpBoots) or have.Contains(ItemType.SpeedBooster) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Energy Tank (green Brinstar bottom)", Address=0x787C2, CanAccess=function(have) return CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Super Missile (green Brinstar bottom)", Address=0x787D0, CanAccess=function(have) return CanUsePowerBombs(have) and have.Contains(ItemType.SuperMissile) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Energy Tank (pink Brinstar bottom)", Address=0x787FA, CanAccess=function(have) return CanUsePowerBombs(have) and CanOpenMissileDoors(have) and have.Contains(ItemType.SpeedBooster) and have.Contains(ItemType.GravitySuit) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (blue Brinstar bottom)", Address=0x78802, ItemStorageType='Chozo', CanAccess=function(have) return have.Contains(ItemType.MorphingBall) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Energy Tank (pink Brinstar top)", Address=0x78824, CanAccess=function(have) return CanUsePowerBombs(have) and have.Contains(ItemType.WaveBeam) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (blue Brinstar top)", Address=0x78836, CanAccess=function(have) return CanOpenMissileDoors(have) and CanUsePowerBombs(have) and (have.Contains(ItemType.SpeedBooster) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (blue Brinstar behind missile)", Address=0x7883C, ItemStorageType='Hidden', CanAccess=function(have) return CanOpenMissileDoors(have) and CanUsePowerBombs(have) and (have.Contains(ItemType.SpeedBooster) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="X-Ray Visor", Address=0x78876, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessRedBrinstar(have) and CanUsePowerBombs(have) and (have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Power Bomb (red Brinstar sidehopper room)", Address=0x788CA, CanAccess=function(have) return CanAccessRedBrinstar(have) and CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Power Bomb (red Brinstar spike room)", Address=0x7890E, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessRedBrinstar(have) and CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (red Brinstar spike room)", Address=0x78914, CanAccess=function(have) return CanAccessRedBrinstar(have) and CanUsePowerBombs(have) end},
	{GravityOkay=false, Region='Brinstar', Name="Spazer", Address=0x7896E, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessRedBrinstar(have) and CanPassBombPassages(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.HiJumpBoots)) end},
	{GravityOkay=false, Region='Brinstar', Name="Energy Tank (Kraid)", Address=0x7899C, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessKraid(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Missile (Kraid)", Address=0x789EC, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessKraid(have) and CanUsePowerBombs(have) end},
	{NoHidden=false, GravityOkay=false, Region='Brinstar', Name="Varia Suit", Address=0x78ACA, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessKraid(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (lava room)", Address=0x78AE4, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessHeatedNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Ice Beam", Address=0x78B24, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessKraid(have) and (have.Contains(ItemType.GravitySuit) or have.Contains(ItemType.VariaSuit)) and have.Contains(ItemType.SpeedBooster) and (CanUsePowerBombs(have) or have.Contains(ItemType.IceBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (below Ice Beam)", Address=0x78B46, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessHeatedNorfair(have) and CanUsePowerBombs(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Energy Tank (Crocomire)", Address=0x78BA4, CanAccess=function(have) return CanAccessCrocomire(have) end},
	{NoHidden=false, GravityOkay=false, Region='Norfair', Name="Hi-Jump Boots", Address=0x78BAC, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessRedBrinstar(have) end},
	{NoHidden=true, GravityOkay=true, Region='Norfair', Name="Missile (above Crocomire)", Address=0x78BC0, CanAccess=function(have) return CanAccessCrocomire(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=false, Region='Norfair', Name="Missile (Hi-Jump Boots)", Address=0x78BE6, CanAccess=function(have) return CanAccessRedBrinstar(have) end},
	{NoHidden=false, GravityOkay=false, Region='Norfair', Name="Energy Tank (Hi-Jump Boots)", Address=0x78BEC, CanAccess=function(have) return CanAccessRedBrinstar(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Power Bomb (Crocomire)", Address=0x78C04, CanAccess=function(have) return CanAccessCrocomire(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (below Crocomire)", Address=0x78C14, CanAccess=function(have) return CanAccessCrocomire(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (Grapple Beam)", Address=0x78C2A, CanAccess=function(have) return CanAccessCrocomire(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpeedBooster)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Grapple Beam", Address=0x78C36, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessCrocomire(have) and (have.Contains(ItemType.SpaceJump) or (have.Contains(ItemType.SpeedBooster) and have.Contains(ItemType.HiJumpBoots))) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Reserve Tank (Norfair)", Address=0x78C3E, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessHeatedNorfair(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (Norfair Reserve Tank)", Address=0x78C44, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessHeatedNorfair(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (bubble Norfair green door)", Address=0x78C52, CanAccess=function(have) return CanAccessHeatedNorfair(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (bubble Norfair)", Address=0x78C66, CanAccess=function(have) return CanAccessHeatedNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (Speed Booster)", Address=0x78C74, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessHeatedNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Speed Booster", Address=0x78C82, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessHeatedNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Missile (Wave Beam)", Address=0x78CBC, CanAccess=function(have) return CanAccessHeatedNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='Norfair', Name="Wave Beam", Address=0x78CCA, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessHeatedNorfair(have) and (have.Contains(ItemType.SpaceJump) or have.Contains(ItemType.GrappleBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Missile (Gold Torizo)", Address=0x78E6E, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Super Missile (Gold Torizo)", Address=0x78E74, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Missile (Mickey Mouse room)", Address=0x78F30, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Missile (lower Norfair above fire flea room)", Address=0x78FCA, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=true, GravityOkay=true, Region='LowerNorfair', Name="Power Bomb (lower Norfair above fire flea room)", Address=0x78FD2, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Power Bomb (above Ridley)", Address=0x790C0, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Missile (lower Norfair near Wave Beam)", Address=0x79100, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Energy Tank (Ridley)", Address=0x79108, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessLowerNorfair(have) and have.Contains(ItemType.ChargeBeam) and EnergyReserveCount(have) >= 4 end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Screw Attack", Address=0x79110, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=true, Region='LowerNorfair', Name="Energy Tank (lower Norfair fire flea room)", Address=0x79184, CanAccess=function(have) return CanAccessLowerNorfair(have) end},
	{NoHidden=false, GravityOkay=false, Region='WreckedShip', Name="Missile (Wrecked Ship middle)", Address=0x7C265, CanAccess=function(have) return CanAccessWs(have) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Reserve Tank (Wrecked Ship)", Address=0x7C2E9, ItemStorageType='Chozo', CanAccess=function(have) return CanDefeatPhantoon(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=true, GravityOkay=true, Region='WreckedShip', Name="Missile (Gravity Suit)", Address=0x7C2EF, CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Missile (Wrecked Ship top)", Address=0x7C319, CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Energy Tank (Wrecked Ship)", Address=0x7C337, CanAccess=function(have) return CanDefeatPhantoon(have) and have.Contains(ItemType.GravitySuit) and (have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Super Missile (Wrecked Ship left)", Address=0x7C357, CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Super Missile (Wrecked Ship right)", Address=0x7C365, CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=false, GravityOkay=true, Region='WreckedShip', Name="Gravity Suit", Address=0x7C36D, ItemStorageType='Chozo', CanAccess=function(have) return CanDefeatPhantoon(have) end},
	{NoHidden=true, GravityOkay=true, Region='Maridia', Name="Missile (green Maridia shinespark)", Address=0x7C437, CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Super Missile (green Maridia)", Address=0x7C43D, CanAccess=function(have) return CanAccessOuterMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Energy Tank (green Maridia)", Address=0x7C47D, CanAccess=function(have) return CanAccessOuterMaridia(have) and (have.Contains(ItemType.SpeedBooster) or have.Contains(ItemType.GrappleBeam) or have.Contains(ItemType.SpaceJump)) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (green Maridia tatori)", Address=0x7C483, ItemStorageType='Hidden', CanAccess=function(have) return CanAccessOuterMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Super Missile (yellow Maridia)", Address=0x7C4AF, CanAccess=function(have) return CanAccessInnerMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (yellow Maridia super missile)", Address=0x7C4B5, CanAccess=function(have) return CanAccessInnerMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (yellow Maridia false wall)", Address=0x7C533, CanAccess=function(have) return CanAccessInnerMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Plasma Beam", Address=0x7C559, ItemStorageType='Chozo', CanAccess=function(have) return CanDefeatDraygon(have) and have.Contains(ItemType.SpaceJump) and (have.Contains(ItemType.ScrewAttack) or have.Contains(ItemType.PlasmaBeam)) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (left Maridia sand pit room)", Address=0x7C5DD, CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.SpringBall) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Reserve Tank (Maridia)", Address=0x7C5E3, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.SpringBall) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (right Maridia sand pit room)", Address=0x7C5EB, CanAccess=function(have) return CanAccessOuterMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Power Bomb (right Maridia sand pit room)", Address=0x7C5F1, CanAccess=function(have) return CanAccessOuterMaridia(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (pink Maridia)", Address=0x7C603, CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Super Missile (pink Maridia)", Address=0x7C609, CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.SpeedBooster) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Spring Ball", Address=0x7C6E5, ItemStorageType='Chozo', CanAccess=function(have) return CanAccessOuterMaridia(have) and have.Contains(ItemType.GrappleBeam) and have.Contains(ItemType.SpaceJump) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Missile (Draygon)", Address=0x7C74D, ItemStorageType='Hidden', CanAccess=function(have) return CanDefeatDraygon(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Energy Tank (Botwoon)", Address=0x7C755, CanAccess=function(have) return CanDefeatBotwoon(have) end},
	{NoHidden=false, GravityOkay=true, Region='Maridia', Name="Space Jump", Address=0x7C7A7, ItemStorageType='Chozo', CanAccess=function(have) return CanDefeatDraygon(have) end},
}
--]]

local function shuffle(x)
	local y = {}
	while #x > 0 do table.insert(y, table.remove(x, math.random(#x))) end
	while #y > 0 do table.insert(x, table.remove(y, math.random(#y))) end
	return y
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
	ETANK = 0xeed7,
	MISSILE = 0xeedb,
	SUPER = 0xeedf,
	PB = 0xeee3,
	BOMBS = 0xeee7,
	CHARGE = 0xeeeb,
	ICE = 0xeeef,
	HIJUMP = 0xeef3,
	SPEED_BOOSTER = 0xeef7,
	WAVE_BEAM = 0xeefb,
	SPAZER = 0xeeff,
	SPRING = 0xef03,
	VARIA = 0xef07,
	PLASMA = 0xef13,
	GRAPPLE = 0xef17,
	MORPHBALL = 0xef23,
	RESERVE = 0xef27,
	GRAVITY = 0xef0b,
	XRAY = 0xef0f,
	SPACE_JUMP = 0xef1b,
	SCREW_ATTACK = 0xef1f,
	CHOZO_ETANK = 0xef2b,
	CHOZO_MISSILE = 0xef2f,
	CHOZO_SUPER = 0xef33,
	CHOZO_PB = 0xef37,
	CHOZO_BOMB = 0xef3b,
	CHOZO_CHARGE = 0xef3f,
	CHOZO_ICE = 0xef43,
	CHOZO_HIJUMP = 0xef47,
	CHOZO_SPEED = 0xef4b,
	CHOZO_WAVE = 0xef4f,
	CHOZO_SPAZER = 0xef53,
	CHOZO_SPRING = 0xef57,
	CHOZO_VARIA = 0xef5b,
	CHOZO_GRAVITY = 0xef5f,
	CHOZO_XRAY = 0xef63,
	CHOZO_PLASMA = 0xef67,
	CHOZO_GRAPPLE = 0xef6b,
	CHOZO_SPACE_JUMP = 0xef6f,
	CHOZO_SCREW_ATTACK = 0xef73,
	CHOZO_MORPH = 0xef77,
	CHOZO_RESERVE = 0xef7b,
	HIDDEN_ETANK = 0xef7f,
	HIDDEN_MISSILE = 0xef83,
	HIDDEN_SUPER = 0xef87,
	HIDDEN_PB = 0xef8b,
	HIDDEN_BOMBS = 0xef8f,
	HIDDEN_CHARGE = 0xef93,
	HIDDEN_ICE = 0xef97,
	HIDDEN_SPEED = 0xef9f,
	HIDDEN_WAVE = 0xefa3,
	HIDDEN_SPAZER = 0xefa7,
	HIDDEN_SPRING = 0xefab,
	HIDDEN_VARIA = 0xefaf,
	HIDDEN_GRAV = 0xefb3,
	HIDDEN_XRAY = 0xefb7,
	HIDDEN_PLASMA = 0xefbb,
	HIDDEN_GRAPPLE = 0xefbf,
	HIDDEN_SPACE = 0xefc3,
	HIDDEN_MORPH = 0xefc7,
	HIDDEN_RESERVE = 0xefcf,
}
local itemTypeForValue = itemTypes:map(function(v,k) return k,v end)
--local itemTypeValues = itemTypes:map(function(v,k,t) return v,#t+1 end)

--local countsForType = table()
local itemInsts = table()

-- [[ build from addresses
local function check(addr)
	local value = rd2b(addr)
	for name,v in pairs(itemTypes) do
		if value == v then
			itemInsts:insert{addr=addr, value=value, name=name}
			--countsForType[name] = (countsForType[name] or 0) + 1
			--print(tolua(itemInsts:last()))
			break
		end
	end
end
for addr=0x78000,0x79192,2 do check(addr) end
for addr=0x7c215,0x7c7bb,2 do check(addr) end
--]]
--[[ build from the loc database
itemInsts = locations:map(function(loc)
	local addr = loc.Address
	local value = rd2b(addr)
	return {addr=addr, value=value, name=itemTypeForValue[value]}
end)
--]]

-- [[ filter out bombs and morph ball, so we know the run is possible 
itemInsts = itemInsts:filter(function(item)
	return item.value ~= itemTypes.MORPHBALL
	and item.value ~= itemTypes.CHOZO_MORPH
	and item.value ~= itemTypes.HIDDEN_MORPH
	and item.value ~= itemTypes.BOMBS
	and item.value ~= itemTypes.CHOZO_BOMB
	and item.value ~= itemTypes.HIDDEN_BOMBS
end)
--]]
print('found '..#itemInsts..' items')
--print(tolua(countsForType))

local itemInstValues = itemInsts:map(function(item) return item.value end)
shuffle(itemInstValues)


for i,item in ipairs(itemInsts) do
	wr2b(item.addr, itemInstValues[i])
end

file[outfilename] = header .. rom

print('done converting '..infilename..' => '..outfilename)
