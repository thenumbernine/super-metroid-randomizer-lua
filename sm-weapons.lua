local ffi = require 'ffi'
local table = require 'ext.table'

local SMWeapons = {}

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
	
	-- hyper?
	--{addr=0x983bf, name='?'},	-- 1000

-- $93:8431
	{addr=0x98431, name="normal"},						-- 20
	{addr=0x98447, name="spazer"},						-- 40
	{addr=0x9845d, name="spazer_ice"},					-- 60
	{addr=0x98473, name="spazer_wave_ice"},				-- 100
	{addr=0x98489, name="plasma_wave_ice"},				-- 300
	{addr=0x9849f, name="ice"},							-- 30
	{addr=0x984b5, name="wave"},						-- 50
	{addr=0x984cb, name="plasma"},						-- 150
	{addr=0x984e1, name="wave_ice"},					-- 60
	{addr=0x984f7, name="spazer_wave"},					-- 70
	{addr=0x9850d, name="plasma_wave"},					-- 250
	{addr=0x98523, name="plasma_ice"},					-- 200
	
	{addr=0x98539, name="charge_normal"},				-- 60
	{addr=0x9854f, name="charge_spazer"},				-- 120
	{addr=0x98565, name="charge_spazer_ice"},			-- 180
	{addr=0x9857b, name="charge_spazer_wave_ice"},		-- 300
	{addr=0x98591, name="charge_plasma_wave_ice"},		-- 900
	{addr=0x985a7, name="charge_ice"},					-- 90
	{addr=0x985bd, name="charge_plasma"},				-- 450
	{addr=0x985d3, name="charge_wave"},					-- 150
	{addr=0x985e9, name="charge_wave_ice"},				-- 180
	{addr=0x985ff, name="charge_spazer_wave"},			-- 210
	{addr=0x98615, name="charge_plasma_ice"},			-- 600
	{addr=0x9862b, name="charge_plasma_wave"},			-- 750
	
	{addr=0x98641, name="missile"},						-- 100
	
	{addr=0x98657, name="supermissile"},				-- 300
	
	-- speed booster?
	--{addr=0x9866d, name="?"},	-- 300
	
	{addr=0x98671, name="powerbomb"},					-- 200
	
	{addr=0x98675, name="bomb"},						-- 30 (my guess of address based on value that matches an online datasheet)

	-- speed booster?
	--{addr=0x98685, name="?"},	-- 300
	--{addr=0x98689, name="?"},	-- 300
	--{addr=0x9868d, name="?"},	-- 300
	--{addr=0x986ab, name="?"},	-- 300

	-- screw attack?
	--{addr=0x980fb, name='?'},	-- 2000

--[[
shinespark			300 per frame ... (spark echoes deal 4096 per frame)
screwattack			2000 per frame
hyper				1000
pseudo_screwattack	200
--]]

	{addr=topc(0x93, 0x85a7), name="ice_sba"},			-- 90?
	{addr=topc(0x93, 0x8685), name="plasma_sba"},		-- 300?
	{addr=topc(0x93, 0x8689), name="wave_sba"},			-- 300?
	{addr=topc(0x93, 0x86ab), name="spazer_sba"},		-- 300?
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
