-- this holds the enemies[] table, used by rooms, items, etc
-- TODO call this 'enemies.lua'
-- and call 'enemies.lua' => 'randomize_enemies.lua'

local ffi = require 'ffi'
local struct = require 'struct'
local config = require 'config'

itemDrop_t_fields = table{
	{smallEnergy = 'uint8_t'},
	{largeEnergy = 'uint8_t'},
	{missile = 'uint8_t'},
	{nothing = 'uint8_t'},
	{superMissile = 'uint8_t'},
	{powerBomb = 'uint8_t'},
}
struct'itemDrop_t'(itemDrop_t_fields)


weakness_t_fields = table{
	{normal = 'uint8_t'},
	{wave = 'uint8_t'},
	{ice = 'uint8_t'},
	{ice_wave = 'uint8_t'},
	{spazer = 'uint8_t'},
	{wave_spazer = 'uint8_t'},
	{ice_spazer = 'uint8_t'},
	{wave_ice_spazer = 'uint8_t'},
	{plasma = 'uint8_t'},
	{wave_plasma = 'uint8_t'},
	{ice_plasma = 'uint8_t'},
	{wave_ice_plasma = 'uint8_t'},
	{missile = 'uint8_t'},
	{supermissile = 'uint8_t'},
	{bomb = 'uint8_t'},
	{powerbomb = 'uint8_t'},
	{speed = 'uint8_t'},
	{sparkcharge = 'uint8_t'},
	{screwattack = 'uint8_t'},
	{hyper = 'uint8_t'},	-- also charge
	{pseudo_screwattack = 'uint8_t'},
	{unknown = 'uint8_t'},
}
struct'weakness_t'(weakness_t_fields)


-- one array is from 0xf8000 +0xcebf to +0xf0ff
local enemyStart = topc(0x9f, 0xcebf)
local enemyCount = (0xf0ff - 0xcebf) / 0x40 + 1
-- another is from +0xf153 to +0xf793 (TODO)
local enemy2Start = topc(0x9f, 0xf153)
local enemy2Count = (0xf793 - 0xf153) / 0x40 + 1

enemy_t_fields = table{
	{tileDataSize = 'uint16_t'},
	{palette = 'uint16_t'},
	{health = 'uint16_t'},
	{damage = 'uint16_t'},
	{width = 'uint16_t'},
	{height = 'uint16_t'},
	{aiBank = 'uint8_t'},
	{hurtTime = 'uint8_t'},
	{sound = 'uint16_t'},
	{bossValue = 'uint16_t'},
	{initiationAI = 'uint16_t'},
	{numberOfParts = 'uint16_t'},
	{unused_extraAI_1 = 'uint16_t'},
	{mainAI = 'uint16_t'},
	{grappleAI = 'uint16_t'},
	{hurtAI = 'uint16_t'},
	{frozenAI = 'uint16_t'},
	{xrayAI = 'uint16_t'},
	{deathEffect = 'uint16_t'},	-- explosions upon death. valued 0-4
	{unused_extraAI_2 = 'uint16_t'},
	{unused_extraAI_3 = 'uint16_t'},
	{powerbombAI = 'uint16_t'},
	{unused_extraAI_4 = 'uint16_t'},
	{unused_extraAI_5 = 'uint16_t'},
	{unused_extraAI_6 = 'uint16_t'},
	{touchAI = 'uint16_t'},
	{shotAI = 'uint16_t'},
	{unused_extraAI_7 = 'uint16_t'},
	{graphicsPtr = 'uint24_t'},	-- aka tile data
	{layerPriority = 'uint8_t'},
	{itemdrop = 'uint16_t'},	-- pointer 
	{weakness = 'uint16_t'},	-- pointer 
	{name = 'uint16_t'},		-- pointer
}
struct'enemy_t'(enemy_t_fields)


local Enemy = class()

-- get the pointer to the weakness_t
-- TODO weakness_t is defined in EnemyWeaknessTable:init
--  so an instance must be created for this typecast to work
-- maybe I should separate out the typecase definition from the Table init ...
function Enemy:getWeakness()
	local addr = self.ptr.weakness
	if addr == 0 then return end
	local ptr = rom + topc(0xb4, addr)
	return ffi.cast('weakness_t*', ptr)
end

-- return the function that builds the structures
local SMEnemies = {}
function SMEnemies:initEnemies()
	self.enemies = table{
		{addr=0xCEBF, name="Boyon"},
		{addr=0xCEFF, name="Mini-Crocomire [unused]"},
		{addr=0xCF3F, name="Tatori"},
		{addr=0xCF7F, name="Young Tatori"},
		{addr=0xCFBF, name="Puyo"},
		{addr=0xCFFF, name="Cacatac"},
		{addr=0xD03F, name="Owtch"},
		{addr=0xD07F, name="Samus' ship (piece #1)"},
		{addr=0xD0BF, name="Samus' ship (piece #2)"},
		{addr=0xD0FF, name="Mellow"},
		{addr=0xD13F, name="Mella"},
		{addr=0xD17F, name="Memu"},
		{addr=0xD1BF, name="Multiviola"},
		{addr=0xD1FF, name="Polyp"},
		{addr=0xD23F, name="Rinka"},
		{addr=0xD27F, name="Rio"},
		{addr=0xD2BF, name="Squeept"},
		{addr=0xD2FF, name="Geruta"},
		{addr=0xD33F, name="Holtz"},
		{addr=0xD37F, name="Oum"},
		{addr=0xD3BF, name="Chute"},
		{addr=0xD3FF, name="Gripper"},
		{addr=0xD43F, name="Ripper II"},
		{addr=0xD47F, name="Ripper"},
		{addr=0xD4BF, name="Dragon"},
		{addr=0xD4FF, name="Shutter (vertical)"},
		{addr=0xD53F, name="Shutter (vertical)"},
		{addr=0xD57F, name="Shutter (horizontal)"},
		{addr=0xD5BF, name="Destructible Shutter (vertical)"},
		{addr=0xD5FF, name="Kamer (vertical)"},
		{addr=0xD63F, name="Waver"},
		{addr=0xD67F, name="Metaree"},
		{addr=0xD6BF, name="Fireflea"},
		{addr=0xD6FF, name="Skultera"},
		{addr=0xD73F, name="Elevator"},
		{addr=0xD77F, name="Sciser"},
		{addr=0xD7BF, name="Zero"},
		{addr=0xD7FF, name="Tripper"},
		{addr=0xD83F, name="Kamer (horizontal)"},
		{addr=0xD87F, name="Bug"},
		{addr=0xD8BF, name="Glitched bug [unused]"},
		{addr=0xD8FF, name="Mochtroid"},
		{addr=0xD93F, name="Sidehopper"},
		{addr=0xD97F, name="Desgeega"},
		{addr=0xD9BF, name="Big Sidehopper"},
		{addr=0xD9FF, name="Big Sidehopper (Tourian)"},	-- this doesn't obey its weaknesses.  maybe the original table pointer is hardcoded into the AI, and must be used?
		{addr=0xDA3F, name="Big Desgeega"},
		{addr=0xDA7F, name="Zoa"},
		{addr=0xDABF, name="Viola"},
		{addr=0xDAFF, name="[Debug enemy]"},
		{addr=0xDB3F, name="Bang [unused]"},
		{addr=0xDB7F, name="Skree"},
		{addr=0xDBBF, name="Yard"},
		{addr=0xDBFF, name="Reflec [unused]"},
		{addr=0xDC3F, name="“Samus” Geemer"},
		{addr=0xDC7F, name="Zeela"},
		{addr=0xDCBF, name="Norfair Geemer"},
		{addr=0xDCFF, name="Geemer"},
		{addr=0xDD3F, name="Grey Geemer"},
		{addr=0xDD7F, name="Metroid"},
		{addr=0xDDBF, name="Crocomire"},
		{addr=0xDDFF, name="Crocomire (skeleton)"},
		{addr=0xDE3F, name="Draygon (body)"},
		{addr=0xDE7F, name="Draygon (eye)"},
		{addr=0xDEBF, name="Draygon (tail)"},
		{addr=0xDEFF, name="Draygon (arms)"},
		{addr=0xDF3F, name="Spore Spawn"},
		{addr=0xDF7F, name="??? (related to Spore Spawn)"},
		{addr=0xDFBF, name="Boulder"},
		{addr=0xDFFF, name="Kzan"},
		{addr=0xE03F, name="??? (related to Kzan)"},
		{addr=0xE07F, name="Hibashi"},
		{addr=0xE0BF, name="Puromi"},
		{addr=0xE0FF, name="Mini-Kraid"},
		{addr=0xE13F, name="Ceres Ridley"},
		{addr=0xE17F, name="Ridley"},
		{addr=0xE1BF, name="??? (related to Ridley)"},
		{addr=0xE1FF, name="Smoke"},
		{addr=0xE23F, name="Ceres door"},
		{addr=0xE27F, name="Zebetite"},
		{addr=0xE2BF, name="Kraid (body)"},
		{addr=0xE2FF, name="Kraid (arm)"},
		{addr=0xE33F, name="Kraid (top belly spike)"},
		{addr=0xE37F, name="Kraid (middle belly spike)"},
		{addr=0xE3BF, name="Kraid (bottom belly spike)"},
		{addr=0xE3FF, name="Kraid (leg)"},
		{addr=0xE43F, name="Kraid (claw)"},
		{addr=0xE47F, name="Kraid (??? belly spike)"},
		{addr=0xE4BF, name="Phantoon (body)"},
		{addr=0xE4FF, name="Phantoon (piece#1)"},
		{addr=0xE53F, name="Phantoon (piece#2)"},
		{addr=0xE57F, name="Phantoon (piece#3)"},
		{addr=0xE5BF, name="Etecoon"},
		{addr=0xE5FF, name="Dachora"},
		{addr=0xE63F, name="Evir"},
		{addr=0xE67F, name="Evir (bullet)"},
		{addr=0xE6BF, name="Eye (security system)"},
		{addr=0xE6FF, name="Fune"},
		{addr=0xE73F, name="Namihe"},
		{addr=0xE77F, name="Coven"},
		{addr=0xE7BF, name="Yapping Maw"},
		{addr=0xE7FF, name="Kago"},
		{addr=0xE83F, name="Magdollite"},
		{addr=0xE87F, name="Beetom"},
		{addr=0xE8BF, name="Powamp"},
		{addr=0xE8FF, name="Work Robot"},
		{addr=0xE93F, name="Work Robot (disabled)"},
		{addr=0xE97F, name="Bull"},
		{addr=0xE9BF, name="Alcoon"},
		{addr=0xE9FF, name="Atomic"},
		{addr=0xEA3F, name="Sparks (Wrecked Ship)"},
		{addr=0xEA7F, name="Koma"},
		{addr=0xEABF, name="Green Kihunter"},
		{addr=0xEAFF, name="Green Kihunter (wing)"},
		{addr=0xEB3F, name="Greenish Kihunter"},
		{addr=0xEB7F, name="Greenish Kihunter (wing)"},
		{addr=0xEBBF, name="Red Kihunter"},
		{addr=0xEBFF, name="Red Kihunter (wing)"},
		{addr=0xEC3F, name="Mother Brain"},
		{addr=0xEC7F, name="Mother Brain (w/ body)"},
		{addr=0xECBF, name="??? (related to Mother Brain)"},
		{addr=0xECFF, name="??? (related to Mother Brain)"},
		{addr=0xED3F, name="Torizo (Drained by metroids)"},
		{addr=0xED7F, name="Big Sidehopper (Drained by metroids)"},
		{addr=0xEDBF, name="??? (related to drained enemies)"},
		{addr=0xEDFF, name="Geemer (Drained by metroids)"},
		{addr=0xEE3F, name="Ripper (Drained by metroids)"},
		{addr=0xEE7F, name="Skree (Drained by metroids)"},
		{addr=0xEEBF, name="Super Metroid"},
		{addr=0xEEFF, name="Grey Torizo"},
		{addr=0xEF3F, name="??? (Torizo's orb)"},
		{addr=0xEF7F, name="Gold Torizo"},
		{addr=0xEFBF, name="??? (Gold Torizo's orb)"},
		{addr=0xEFFF, name="??? (4 Statues flying thing)"},
		{addr=0xF03F, name="??? (4 Statues)"},
		{addr=0xF07F, name="Shaktool"},
		{addr=0xF0BF, name="Shattering Glass (Maridian tube)"},
		{addr=0xF0FF, name="Walking Chozo Statue"},
		{addr=0xF153, name="??? (wierd spining orb)"},
		{addr=0xF193, name="Zeb"},
		{addr=0xF1D3, name="Zebbo"},
		{addr=0xF213, name="Gamet"},
		{addr=0xF253, name="Geega"},
		{addr=0xF293, name="Botwoon"},
		{addr=0xF2D3, name="Etecoon (Escape)"},
		{addr=0xF313, name="Dachora (Escape)"},
		{addr=0xF353, name="Grey Zebesian (Wall)"},
		{addr=0xF393, name="Green Zebesian (Wall)"},
		{addr=0xF3D3, name="Red Zebesian (Wall)"},
		{addr=0xF413, name="Gold Zebesian (Wall)"},
		{addr=0xF453, name="Pink Zebesian (Wall)"},
		{addr=0xF493, name="Black Zebesian (Wall)"},
		{addr=0xF4D3, name="Grey Zebesian (Fighter)"},
		{addr=0xF513, name="Green Zebesian (Fighter)"},
		{addr=0xF553, name="Red Zebesian (Fighter)"},
		{addr=0xF593, name="Gold Zebesian (Fighter)"},
		{addr=0xF5D3, name="Pink Zebesian (Fighter)"},
		{addr=0xF613, name="Black Zebesian (Fighter)"},
		{addr=0xF653, name="Grey Zebesian"},
		{addr=0xF693, name="Green Zebesian"},
		{addr=0xF6D3, name="Red Zebesian"},
		{addr=0xF713, name="Gold Zebesian"},
		{addr=0xF753, name="Pink Zebesian"},
		{addr=0xF793, name="Black Zebesian"},
	}:map(function(enemy)
		return setmetatable(enemy, Enemy)
	end)

	self.enemyForName = self.enemies:map(function(enemy)
		return enemy, enemy.name
	end)

	self.enemyForAddr = self.enemies:map(function(enemy)
		return enemy, enemy.addr
	end)

	for _,enemy in ipairs(self.enemies) do
		local addr = topc(0x9f, enemy.addr)
		enemy.ptr = ffi.cast('enemy_t*', rom + addr)
	end
end

function SMEnemies:buildMemoryMapEnemies()
	for _,enemy in ipairs(self.enemies) do
		local addr = topc(0x9f, enemy.addr)
		insertUniqueMemoryRange(addr, ffi.sizeof'enemy_t', 'enemy_t')
	end
end

return SMEnemies
