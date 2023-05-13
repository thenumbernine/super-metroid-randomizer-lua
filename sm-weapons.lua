local ffi = require 'ffi'
local table = require 'ext.table'
local topc = require 'super_metroid_randomizer.pc'.to
local frompc = require 'super_metroid_randomizer.pc'.from

local SMWeapons = {}

local weaponBank = 0x93

--[[
expected damage of each:
normal				20
wave				50
ice					30
ice_wave			60
spazer				40
wave_spazer			70
ice_spazer			60
wave_ice_spazer		100
plasma				150
wave_plasma			250
ice_plasma			200
wave_ice_plasma		300
missile				100
supermissile		300
bomb				30
powerbomb			200 (per flash, power bombs hit x2 to close objects)
speed				(? same as shinespark?) 300 per frame
shinespark			300 per frame ... (spark echoes deal 4096 per frame)
screwattack			2000 per frame
hyper				1000
pseudo_screwattack	200
unknown

power bomb charge + wave 	= 300 per shot, for 4 shots
power bomb charge + ice 	= 90 per shot, for 4 shots
power bomb charge + spazer 	= 300 per shot, for 2 shots
power bomb charge + plasma = 300 per shot, for 4 shots
--]]
-- Taken from https://jathys.zophar.net/supermetroid/kejardon/EnemyResistence.txt
-- but in the original there were some duplicated addresses for the plasma+charge entries
SMWeapons.weaponDamages = table{

--[[
TODO these aren't just uint16_t's of damage
they are a struct:
struct weapon_t {
	uint16_t damage;
	uint16_t upFacingRightAddr;
	uint16_t diagUpRightAddr;
	uint16_t rightAddr;
	uint16_t diagDownRightAddr;
	uint16_t downFacingRightAddr;
	uint16_t downFacingLeftAddr;
	uint16_t diagDownLeftAddr;
	uint16_t leftAddr;
	uint16_t upFacingLeftAddr;
}
--]]

	-- hyper?
	--{addr=topc(weaponBank, 0x83bf), name='?'},	-- 1000

	{addr=topc(weaponBank, 0x8431), name="normal"},						-- 20
	{addr=topc(weaponBank, 0x8447), name="spazer"},						-- 40
	{addr=topc(weaponBank, 0x845d), name="spazer_ice"},					-- 60
	{addr=topc(weaponBank, 0x8473), name="spazer_wave_ice"},				-- 100
	{addr=topc(weaponBank, 0x8489), name="plasma_wave_ice"},				-- 300
	{addr=topc(weaponBank, 0x849f), name="ice"},							-- 30
	{addr=topc(weaponBank, 0x84b5), name="wave"},						-- 50
	{addr=topc(weaponBank, 0x84cb), name="plasma"},						-- 150
	{addr=topc(weaponBank, 0x84e1), name="wave_ice"},					-- 60
	{addr=topc(weaponBank, 0x84f7), name="spazer_wave"},					-- 70
	{addr=topc(weaponBank, 0x850d), name="plasma_wave"},					-- 250
	{addr=topc(weaponBank, 0x8523), name="plasma_ice"},					-- 200
	
	{addr=topc(weaponBank, 0x8539), name="charge_normal"},				-- 60
	{addr=topc(weaponBank, 0x854f), name="charge_spazer"},				-- 120
	{addr=topc(weaponBank, 0x8565), name="charge_spazer_ice"},			-- 180
	{addr=topc(weaponBank, 0x857b), name="charge_spazer_wave_ice"},		-- 300
	{addr=topc(weaponBank, 0x8591), name="charge_plasma_wave_ice"},		-- 900
	{addr=topc(weaponBank, 0x85a7), name="charge_ice"},					-- 90		-- also ice_sba
	{addr=topc(weaponBank, 0x85bd), name="charge_plasma"},				-- 450
	{addr=topc(weaponBank, 0x85d3), name="charge_wave"},					-- 150
	{addr=topc(weaponBank, 0x85e9), name="charge_wave_ice"},				-- 180
	{addr=topc(weaponBank, 0x85ff), name="charge_spazer_wave"},			-- 210
	{addr=topc(weaponBank, 0x8615), name="charge_plasma_ice"},			-- 600
	{addr=topc(weaponBank, 0x862b), name="charge_plasma_wave"},			-- 750
	
	{addr=topc(weaponBank, 0x8641), name="missile"},						-- 100
	{addr=topc(weaponBank, 0x8657), name="supermissile"},				-- 300

	-- the next block is not the weapon_t struct, instead just two uint16_t's

	--{addr=topc(weaponBank, 0x866d), name="?"},	-- 300	-- speed booster? "super missile related" by patrickjohnson.org
	{addr=topc(weaponBank, 0x8671), name="powerbomb"},					-- 200
	{addr=topc(weaponBank, 0x8675), name="bomb"},						-- 30 (my guess of address based on value that matches an online datasheet)
	
	--[[
	{addr=topc(weaponBank, 0x8679), name="dead bomb"},
	{addr=topc(weaponBank, 0x867d), name="dead (super) missile"},
	{addr=topc(weaponBank, 0x8681), name="ice_sba?"},		-- ?? or is charge_ice used by ice_sba ?
	{addr=topc(weaponBank, 0x8685), name="plasma_sba"},		-- 300
	{addr=topc(weaponBank, 0x8689), name="wave_sba"},		-- 300
	{addr=topc(weaponBank, 0x868d), name="?"},				-- 300
	{addr=topc(weaponBank, 0x8691), name="?"},				-- 300

	-- now back to weapon_t's:

	{addr=topc(weaponBank, 0x8695), name="?"},
	{addr=topc(weaponBank, 0x86ab), name="spazer_sba"},		-- 300?
	{addr=topc(weaponBank, 0x86c1), name="shinespark_echo"},
	
	-- and a last dword
	{addr=topc(weaponBank, 0x86d7), name="shinespark_beam?"},
	--]]
	
	-- screw attack?
	--{addr=topc(weaponBank, 0x80fb), name='?'},	-- 2000

--[[
shinespark			300 per frame ... (spark echoes deal 4096 per frame)
screwattack			2000 per frame
hyper				1000
pseudo_screwattack	200
--]]

}
SMWeapons.weaponDamageForName = SMWeapons.weaponDamages:mapi(function(v) return v, v.name end)
SMWeapons.weaponDamageForAddr = SMWeapons.weaponDamages:mapi(function(v) return v, v.addr end)

function SMWeapons:weaponsInit()
	local rom = self.rom
	for _,dmg in ipairs(self.weaponDamages) do
		dmg.ptr = ffi.cast('uint16_t*', rom + dmg.addr)
	end
end

function SMWeapons:weaponsBuildMemoryMap(mem)
	for _,dmg in ipairs(self.weaponDamages) do
		mem:add(dmg.addr, ffi.sizeof'uint16_t', 'weapon damage')
	end
end

return SMWeapons
