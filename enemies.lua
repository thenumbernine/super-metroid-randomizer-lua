return function(rom)
local ffi = require 'ffi'
local template = require 'template'

local config = require 'config'
local randomizeEnemyProps = config.randomizeEnemyProps


local bank_b4 = 0x198000


local function pickRandom(t)
	return t[math.random(#t)]
end

local function defineFields(name)
	return function(fields)
		local code = template([[
typedef union {
	struct {
<? 
local ffi = require 'ffi'
local size = 0
for _,kv in ipairs(fields) do
	local name, ctype = next(kv)
	size = size + ffi.sizeof(ctype)
?>		<?=ctype?> <?=name?>;
<? 
end
?>	} __attribute__((packed));
	uint8_t ptr[<?=size?>];
} <?=name?>;
]], {name=name, fields=fields})
		ffi.cdef(code)

		local mt = ffi.metatype(name, {
			__tostring = function(ptr)
				local t = table()
				for _,field in ipairs(fields) do
					local name, ctype = next(field)
					t:insert(name..'='..tostring(ptr[name]))
				end
				return '{'..t:concat', '..'}'
			end,
			__concat = function(a,b) return tostring(a) .. tostring(b) end,
		})
	end
end


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

local enemyFields = table{
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
	{powerbombAI = 'uint16_t'},	-- aka 'power bomb reaction'
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
defineFields'enemy_t'(enemyFields)

local Enemy = class()

-- get the pointer to the weakness_t
function Enemy:getWeakness()
	local addr = self.ptr[0].weakness
	if addr == 0 then return end
	local ptr = rom + bank_b4 + addr
	return ffi.cast('weakness_t*', ptr)
end

-- global for now ...
enemies = table{
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
	{addr=0xD9FF, name="Big Sidehopper (Tourian)"},
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

enemyForName = enemies:map(function(enemy)
	return enemy, enemy.name
end)

for _,enemy in ipairs(enemies) do
	enemy.ptr = ffi.cast('enemy_t*', rom + enemy.addr + addrbase)
end



local ROMTable = class()

function ROMTable:init()
	defineFields(self.structName)(self.fields)
	self.structSize = ffi.sizeof(self.structName)
	self.fieldNameMaxLen = self.fields:map(function(kv)
		return #next(kv)
	end):sup()
end


-- this is a table that the Enemy table uses .. like weaknesses or item drops
local EnemyAuxTable = class(ROMTable)

EnemyAuxTable.showDistribution = true

function EnemyAuxTable:randomize()
	self.addrs = enemies:map(function(enemy)
		return true, enemy.ptr[0][self.enemyField]
	end):keys():sort()

	local distr
	if self.showDistribution then
		distr = table()
	end
	
	print()
	print(self.name..':')
	for _,addr in ipairs(self.addrs) do
		-- concise:
		--io.write('  '..('0x%04x'):format(addr)..' ')
		-- verbose:
		print(('0x%04x'):format(addr)..' ')
		if addr ~= 0 then
			local values = self:getRandomizedValues(addr)
			assert(#values == #self.fields)
		
			local ptrtype = self.structName..'*'
			local entry = ffi.cast(ptrtype, rom + bank_b4 + addr)
			
			for i,field in ipairs(self.fields) do
				local name = next(field)
			
				if randomizeEnemyProps[self.enemyField] then
					local value = values[i]
					entry[0][name] = value
				end
				
				local value = entry[0][name]
				
				if self.showDistribution then
					distr[value] = (distr[value] or 0) + 1
				end
				-- concise:
				--io.write( (' %02x'):format(value) )
				-- verbose:
				print('  '..name..' '.. ('.'):rep(self.fieldNameMaxLen-#name+5)..' '..('0x%02x'):format(value))
			end
		end
		-- concise:
		--print()
	end

	if self.showDistribution then
		print'...distribution of values:'
		for _,k in ipairs(distr:keys():sort()) do
			print('  '..k..' x'..distr[k])
		end
		print()
	end
end

-- preserveZeros means if an enemy[field] has a zero before then it will have a zero after
function EnemyAuxTable:randomizeEnemy(enemy, preserveZeros, disableWrite)
	local field = self.enemyField
	
	if randomizeEnemyProps[field] 
	and not disableWrite
	then
		if not preserveZeros then
			enemy.ptr[0][field] = pickRandom(self.addrs)
		else
			if enemy.ptr[0][field] ~= 0 then
				enemy.ptr[0][field] = self.addrs[math.random(#self.addrs-1)+1]
			end	
		end
	end

	io.write(' '..field..'='..('0x%04x'):format(enemy.ptr[0][field]))
	local addr = enemy.ptr[0][field]
	if addr ~= 0 then
		io.write('  ')
		for i=0,self.structSize-1 do
			io.write( (' %02x'):format(rom[bank_b4+addr+i]) )
		end
	end
	print()
end


local EnemyItemDropTable = class(EnemyAuxTable)

EnemyItemDropTable.name = 'enemy item drop table'
EnemyItemDropTable.enemyField = 'itemdrop'	-- field in enemy_t to get addresses from
EnemyItemDropTable.structName = 'itemDrop_t'	-- structure at the address
EnemyItemDropTable.fields = table{
	{smallEnergy = 'uint8_t'},
	{largeEnergy = 'uint8_t'},
	{missile = 'uint8_t'},
	{nothing = 'uint8_t'},
	{superMissile = 'uint8_t'},
	{powerBomb = 'uint8_t'},
}

-- returns a list of bytes that are written to the structure
-- TODO I could use the ffi info and return arbitrary values that are correctly cast into the structure ...
function EnemyItemDropTable:getRandomizedValues(addr)
	-- 6 percentages (of 0xff):
	-- small energy, large energy, missile, nothing, super missile, power bomb
	local values = range(self.structSize):map(function()
		return math.random() <= randomizeEnemyProps.itemDropZeroChance and 0 or math.random()
	end)
	-- now normalize
	local sum = values:sum()
	-- ... should I allow for monsters to not drop anything?
	-- ... should I have special exception for bosses?
	if sum > 0 then
		values = values:map(function(value) return math.ceil(value * 0xff / sum) end)
	end
	--- TODO should always add up to 0xff here ...but if I was lazy, would floor() or ceil() be better?			
	return values
end


local EnemyWeaknessTable = class(EnemyAuxTable)

EnemyWeaknessTable.name = 'enemy weakness table'
EnemyWeaknessTable.enemyField = 'weakness'
EnemyWeaknessTable.structName = 'weakness_t'
EnemyWeaknessTable.fields = table{
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
	{hyper = 'uint8_t'},
	{pseudo_screwattack = 'uint8_t'},
	{unknown = 'uint8_t'},
}

local ShaktoolWeaknessAddr = 0xef1e

function EnemyWeaknessTable:getRandomizedValues(addr)
	local values = range(#self.fields):map(function()
		return math.random() <= randomizeEnemyProps.weaknessImmunityChance 
			and 0 or math.random(0,255)
	end)
	
	-- make sure there's at least one nonzero weakness within the first 20
	local found
	for i=1,20 do
		if values[i] ~= 0 then
			found = true
			break
		end
	end
	if not found then
		values[math.random(20)] = math.random(1,255)
	end

	-- make sure Shaktool is immune to powerbombs
	if addr == ShaktoolWeaknessAddr then
		values[16] = 0
	end

	return values
end

function EnemyWeaknessTable:randomizeEnemy(enemy, preserveZeros, disableWrite)
	-- NOTICE
	-- if (for item placement to get past canKill constraints)
	-- we choose to allow re-rolling of weaknesses
	-- then they will have to work around the fact that these certain enemies shouldn't re-roll
	
	-- don't randomize Kraid's weaknesses ... for now
	-- leave this at 0
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (body)"]) 
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (body)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (arm)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (top belly spike)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (middle belly spike)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (bottom belly spike)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (leg)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (claw)"])
	disableWrite = disableWrite or (enemy == enemyForName["Kraid (??? belly spike)"])

	-- don't randomize Shaktool -- leave it at its default weakness entry (which is unshared by default)
	disableWrite = disableWrite or (enemy == enemyForName.Shaktool)

	EnemyWeaknessTable.super.randomizeEnemy(self, enemy, preserveZeros, disableWrite)
end

--[[
here's the distribution of original values:
  0x00 x385
  0x01 x17
  0x02 x488
  0x04 x67
  0x80 x235
  0x81 x8
  0x82 x152
  0x84 x26
  0xff x52

I'm suspicious the last 0x80 is a bitflag of some sort
and who knows what 0xff is ...

kraid is at 0xe2bf
and has a weakness address 0xf15a <-> 0x1a715a :  
82 82 82 82 82 
82 82 82 82 82 
82 82 82 82 80 
80 80 80 80 02 
80 80

looks like all beams/missiles have 82 (hyper has 02)
and all else has 80
I'm thinking 0x80 must be a bitflag
otherwise 2 = normal damage, 0 = no damage

metroidconstruction.com says:

    0 = no damage to enemy.
    1 = 0.5x damage to enemy.
    2 = default (1x) damage to enemy.
    3 = 1.5x damage to enemy.
    4 = 2x damage to enemy.
    5 = 2.5x damage to enemy.
    4-F = higher damage to enemy.

but no one explains what high nibbles are for.
--]]


-- exponentially weighted
local function expRand(min, max)
	local logmin, logmax = math.log(min), math.log(max)
	return math.exp(math.random() * (logmax - logmin) + logmin)
end



local enemyItemDropTable = EnemyItemDropTable()
enemyItemDropTable:randomize()

local enemyWeaknessTable = EnemyWeaknessTable()
enemyWeaknessTable:randomize()


local allEnemyFieldValues = {}
for _,field in ipairs{
	'sound',
	
	-- don't pick from previous values here
	--  because only 0,2,3,4 are used, but 1 is valid
	--'deathEffect',

	--[[ randomize AI?  
	-- maybe only for certain monsters ... among only certain values ...
	-- just doing everything causes it to freeze very often
	'aiBank',
	'initiationAI',
	'mainAI',
	'grappleAI',
	'hurtAI',
	'frozenAI',
	'xrayAI',
	--]]

} do
	if randomizeEnemyProps[field] then
		allEnemyFieldValues[field] = allEnemyFieldValues[field] or {
			distr = {},
		}
		local values = allEnemyFieldValues[field]
		for _,enemy in ipairs(enemies) do
			local value = enemy.ptr[0][field]
			values.distr[value] = (values.distr[value] or 0) + 1
		end
		values.values = table.keys(values.distr):sort()
		-- [[ TODO print distribution *after* randomization
		print('enemy '..field..' distribution:')
		for _,value in ipairs(values.values) do
			print('  '..value..' x'..values.distr[value])
		end
		--]]
	end
end

local typeinfo = {
	uint8_t = {range={0,0xff}},
	uint16_t = {range={0,0xffff}},
}

local function randomizeFieldExp(enemy, fieldname)
	if randomizeEnemyProps[fieldname] then
		local value = expRand(table.unpack(randomizeEnemyProps[fieldname..'ScaleRange'])) * enemy[0][fieldname]
		local field = select(2, enemyFields:find(nil, function(field) return next(field) == fieldname end))
		local fieldtype = select(2, next(field))
		local fieldrange = typeinfo[fieldtype].range
		value = math.clamp(value, fieldrange[1], fieldrange[2])
		enemy[0][fieldname] = value
	end
	print(' '..fieldname..'='..enemy[0][fieldname])
end

print'enemies:'
for i,enemy in ipairs(enemies) do
	print(('0x%04x'):format(enemy.addr)..': '..enemy.name)

	if randomizeEnemyProps.deathEffect then
		enemy.ptr[0].deathEffect = math.random(0,4)
	end
	print(' deathEffect='..enemy.ptr[0].deathEffect)

	randomizeFieldExp(enemy.ptr, 'hurtTime')
	randomizeFieldExp(enemy.ptr, 'health')
	randomizeFieldExp(enemy.ptr, 'damage')

	for field,values in pairs(allEnemyFieldValues) do
		if randomizeEnemyProps[field] then
			enemy.ptr[0][field] = pickRandom(values.values)
		end
		print(' '..field..'='..('0x%x'):format(enemy.ptr[0][field]))
	end

	-- TODO for this one, null ptr means doesn't take damage ...
	-- so I should preserve nulls to nulls and non-nulls to non-nulls
	-- ...and bosses should never be null
	enemyWeaknessTable:randomizeEnemy(enemy)
	
	enemyItemDropTable:randomizeEnemy(enemy)
end

-- TODO make sure bosses can be killed 
-- ... especially Kraid from the looks of it
-- TODO make sure the monster outside the sand outside springball canNOT be powerbomb'd

end
