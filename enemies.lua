local ffi = require 'ffi'
local config = require 'config'
local randomizeEnemyProps = config.randomizeEnemyProps


local bank_86 = 0x28000
local bank_9f = 0xf8000
local bank_b4 = 0x198000


local function pickRandom(t)
	return t[math.random(#t)]
end

local makestruct = require 'makestruct'

--]]


-- one array is from 0xf8000 +0xcebf to +0xf0ff
local enemyStart = bank_9f + 0xcebf
local enemyCount = (0xf0ff - 0xcebf) / 0x40 + 1
-- another is from +0xf153 to +0xf793 (TODO)
local enemy2Start = bank_9f + 0xf153
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
makestruct'enemy_t'(enemyFields)

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
	enemy.ptr = ffi.cast('enemy_t*', rom + enemy.addr + bank_9f)
end



local ROMTable = class()

function ROMTable:init()
	makestruct(self.structName)(self.fields)
	self.structSize = ffi.sizeof(self.structName)
	self.fieldNameMaxLen = self.fields:map(function(kv)
		return #next(kv)
	end):sup()
end


-- this is a table that the Enemy table uses .. like weaknesses or item drops
local EnemyAuxTable = class(ROMTable)

EnemyAuxTable.showDistribution = true

function EnemyAuxTable:init()
	EnemyAuxTable.super.init(self)
	
	self.addrs = enemies:map(function(enemy)
		return true, enemy.ptr[0][self.enemyField]
	end):keys():sort()

	print(self.name..' has '..#self.addrs..' unique addrs:')
	print(' '..self.addrs:map(function(addr) return ('%04x'):format(addr) end):concat', ')
end

function EnemyAuxTable:randomize()
	local ptrtype = self.structName..'*'
	
	for _,addr in ipairs(self.addrs) do
		if addr ~= 0 then
			-- return nil to not randomize this entry
			local values = self:getRandomizedValues(addr)
			if values then
				assert(#values == #self.fields)
			end

			local entry = ffi.cast(ptrtype, rom + bank_b4 + addr)
			
			for i,field in ipairs(self.fields) do
				local name = next(field)
		
				-- if we are randomizing the enemy field ... then randomize the table associated with it
				if randomizeEnemyProps[self.enemyField] 
				and values 
				then
					local value = values[i]
					entry[0][name] = value
				end
			end
		end
	end
end

function EnemyAuxTable:print()
	local ptrtype = self.structName..'*'

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
		print(('0x%04x'):format(addr))
		print('used by: '..enemies:filter(function(enemy)
			return enemy.ptr[0][self.enemyField] == addr
		end):map(function(enemy)
			return enemy.name
		end):concat', ')
		if addr ~= 0 then
			local entry = ffi.cast(ptrtype, rom + bank_b4 + addr)
			for i,field in ipairs(self.fields) do
				local name = next(field)
				local value = entry[0][name]
				
				if self.showDistribution then
					local value = entry[0][name]
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

function EnemyAuxTable:randomizeEnemy(enemy)
	local field = self.enemyField
	if not randomizeEnemyProps[field] then return end
	enemy.ptr[0][field] = pickRandom(self.addrs)
end

function EnemyAuxTable:printEnemy(enemy)
	local field = self.enemyField
	
	io.write(' ',field,'=',('0x%04x'):format(enemy.ptr[0][field]))
	local addr = enemy.ptr[0][field]
	if addr ~= 0 then
		io.write(' ',tostring(ffi.cast(self.structName..'*', rom+bank_b4+addr) ))	
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


--[[
t is value => percentage
returns a value at random, weighted by percentage
--]]
local function pickWeighted(t)
	local r = math.random() * table.sum(t)
	for value,prob in pairs(t) do
		r = r - prob
		if r <= 0 then
			return value
		end
	end
	error("shouldn't get here")
end

local dontChangeWeaknessSet = {
	["Kraid (body)"] = true, 
	["Kraid (body)"] = true,
	["Kraid (arm)"] = true,
	["Kraid (top belly spike)"] = true,
	["Kraid (middle belly spike)"] = true,
	["Kraid (bottom belly spike)"] = true,
	["Kraid (leg)"] = true,
	["Kraid (claw)"] = true,
	["Kraid (??? belly spike)"] = true,
	Metroid = true,
}

function EnemyWeaknessTable:getRandomizedValues(addr)
	local values = range(#self.fields):map(function()
		return math.random() <= randomizeEnemyProps.weaknessImmunityChance 
			and 0 
--[[
here's possible values:    
	0 = no damage to enemy.
    1 = 0.5x damage to enemy.
    2 = default (1x) damage to enemy.
    3 = 1.5x damage to enemy.
    4 = 2x damage to enemy.
    5 = 2.5x damage to enemy.
    4-F = higher damage to enemy.

in addition, the 0x80 bitflag is used for something
--]]
		
		
		-- instead of 0-255 ... 0 is
			or bit.bor(
				pickRandom{0, 0x80},	--bit.lshift(math.random(0,15), 4),
				
				-- exp(-x/7) has the following values for 0-15:
				-- 1.0, 0.86687789975018, 0.75147729307529, 0.65143905753106, 0.56471812200776, 0.48954165955695, 0.42437284567695, 0.36787944117144, 0.31890655732397, 0.27645304662956, 0.23965103644178, 0.2077481871436, 0.18009231214795, 0.15611804531597, 0.13533528323661, 0.11731916609425
				pickWeighted(range(0,15):map(function(x) return math.exp(-x/7) end))
			)
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

	-- don't change kraid's part's weaknesses
	-- until I know how to keep the game from crashing
	for name,_ in pairs(dontChangeWeaknessSet) do
		if enemyForName[name].ptr[0].weakness == addr then
			return
		end
	end

	-- make sure Shaktool weakness entry is immune to powerbombs
	--if addr == ShaktoolWeaknessAddr then	-- local ShaktoolWeaknessAddr = 0xef1e
	if addr == enemyForName.Shaktool.ptr[0].weakness then
		values[16] = 0
	end

	return values
end

function EnemyWeaknessTable:randomizeEnemy(enemy)
	-- NOTICE
	-- if (for item placement to get past canKill constraints)
	-- we choose to allow re-rolling of weaknesses
	-- then they will have to work around the fact that these certain enemies shouldn't re-roll
	
	-- don't randomize Kraid's weaknesses ... for now
	-- leave this at 0
	if dontChangeWeaknessSet[enemy.name] 
	-- don't randomize Shaktool -- leave it at its default weakness entry (which is unshared by default)
	or enemy.name == Shaktool
	then
		print('NOT WRITING WEAKNESS OF '..enemy.name)
		return
	end

	EnemyWeaknessTable.super.randomizeEnemy(self, enemy)
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
local enemyWeaknessTable = EnemyWeaknessTable()


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
		--[[ TODO print distribution *after* randomization
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

local function randomizeFieldExp(enemyPtr, fieldname)
	if randomizeEnemyProps[fieldname] then
		local value = expRand(table.unpack(randomizeEnemyProps[fieldname..'ScaleRange'])) * enemyPtr[0][fieldname]
		local field = select(2, enemyFields:find(nil, function(field) return next(field) == fieldname end))
		local fieldtype = select(2, next(field))
		local fieldrange = typeinfo[fieldtype].range
		value = math.clamp(value, fieldrange[1], fieldrange[2])
		enemyPtr[0][fieldname] = value
	end
end

makestruct'enemyShot_t'{
	{initAI = 'uint16_t'},
	{firstAI = 'uint16_t'},
	{graphicsAI = 'uint16_t'},
	{halfWidth = 'uint8_t'},
	{halfHeight = 'uint8_t'},
	
	{damageAndFlags = 'uint16_t'},
--[[ flags:
0x8000 = can be shot by samus
0x4000 = shot doesn't die when it hits samus
0x2000 = don't collide with samus
0x1000 = invisible
0x0fff = damage
--]]

	{touchAI = 'uint16_t'},	-- AI to run when samus gets hit
	{shootAI = 'uint16_t'},	-- AI to run if samus shoots the shot
}
-- addr is bank $86
local enemyShots = table{
	{addr=0xD02E, name="Kago's bugs (enemy $E7FF)"},
	{addr=0xA17B, name="Space pirate's eye lasers"},
	{addr=0xA189, name="Claws that fighting space pirates throw at Samus"},
	{addr=0xCF26, name="Kihunter acid, going right (enemies $EABF, $EB3F, $EBBF)"},
	{addr=0xCF18, name="Kihunter acid, going left (enemies $EABF, $EB3F, $EBBF)"},
	{addr=0x9E90, name="Walking dragon's fireballs (enemy $E9BF)"},
	{addr=0xB5CB, name="Lava dragon's fireballs (enemy $D4BF)"},
	{addr=0x8BC2, name="Skree's debris #1 (enemy $DB7F)"},
	{addr=0x8BD0, name="Skree's debris #2 (enemy $DB7F)"},
	{addr=0x8BDE, name="Skree's debris #3 (enemy $DB7F)"},
	{addr=0x8BEC, name="Skree's debris #4 (enemy $DB7F)"},
	{addr=0x8BFA, name="Metalee's debris #1 (enemy $D67F)"},
	{addr=0x8C08, name="Metalee's debris #2 (enemy $D67F)"},
	{addr=0x8C16, name="Metalee's debris #3 (enemy $D67F)"},
	{addr=0x8C24, name="Metalee's debris #4 (enemy $D67F)"},
	{addr=0xDAFE, name="Cactus' needles, projectile runs once for each of the five needles (enemy $CFFF)"},
	{addr=0xDFBC, name="Eyed version of Name & Fune's fireball (enemy $E73F)"},
	{addr=0xDFCA, name="Eyeless version of Name & Fune's fireball (enemy $E6FF)"},
	{addr=0xE0E0, name="Lava clumps thrown by lavaman (enemy $E83F)"},
	{addr=0xD298, name="Puu's debris when it explodes (enemy $E8BF)"},
	{addr=0xD2D0, name="Wrecked ship robot's ring lasers, travelling up right (enemy $E8FF)"},
	{addr=0xD2B4, name="Wrecked ship robot's ring lasers, travelling left (enemy $E8FF)"},
	{addr=0xD2A6, name="Wrecked ship robot's ring lasers, travelling up left (enemy $E8FF)"},
	{addr=0xD2C2, name="Wrecked ship robot's ring lasers, travelling down right (enemy $E8FF)"},
	{addr=0xD2DE, name="Wrecked ship robot's ring lasers, travelling down left (enemy $E8FF)"},
	{addr=0xF498, name="Wrecked ship's falling green sparks (enemy $EA3F)"},
	{addr=0xBD5A, name="Flying rocky debris in Norfair (enemy $D1FF)"},
	{addr=0x9DB0, name="Rocks that mini Kraid spits (enemy $E0FF)"},
	{addr=0x9DBE, name="Mini Kraid's belly spikes, facing left (enemy $E0FF)"},
	{addr=0x9DCC, name="Mini Kraid's belly spikes, facing right (enemy $E0FF)"},
	{addr=0xA985, name="Bomb Torizo's explosive hand swipe (enemy $EEFF)"},
	{addr=0xAEA8, name="Bomb Torizo's crescent projectile (enemy $EEFF)"},
	{addr=0xAD5E, name="Orbs that Bomb Torizo spits (enemy $EEFF)"},
	{addr=0xDE6C, name="Spore spawners? (enemy $DF3F)"},
	{addr=0xDE88, name="Spore spawners? (enemy $DF3F)"},
	{addr=0xDE7A, name="Spore Spawn's spores (enemy $DF3F)"},
	{addr=0x9C6F, name="Rocks when Kraid rises (enemy $E2BF)"},
	{addr=0x9C61, name="Rocks when Kraid rises again (enemy $E2BF)"},
	{addr=0x9C45, name="Rocks that Kraid spits (enemy $E2BF)"},
	{addr=0x9C53, name="Rocks that fall when Kraid's ceiling crumbles (enemy $E2BF) (Kraid's flying claws and belly spike platforms aren't enemy projectiles.)"},
	{addr=0x8F8F, name="Glowing orbs that Crocomire spits (enemy $DDBF)"},
	{addr=0x8F9D, name="Blocks crumbling underneath Crocomire (enemy $DDBF)"},
	{addr=0x90C1, name="Crocomire's spike wall when it crumbles (enemy $DDBF)"},
	{addr=0x9C37, name="Phantoon's starting fireballs (enemy $E4BF)"},
	{addr=0x9C29, name="All of Phantoon's other fireballs (enemy $E4BF)"},
	{addr=0xEBA0, name="Botwoon's wall? (enemy $F293)"},
	{addr=0xEC48, name="Botwoon's green spit (enemy $F293)"},
	{addr=0x8E5E, name="Draygon's wall turret projectiles (enemy $DE3F)"},
	{addr=0x8E50, name="Draygon gunk (enemy $DE3F)"},
	{addr=0xB428, name="Golden Torizo's eye beam (enemy $EF7F)"},
	{addr=0xAFE5, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
	{addr=0xAFF3, name="Golden Torizo preparing to attack; equipment check? (enemy $EF7F)"},
	{addr=0xAD7A, name="Orbs that Golden Torizo spits  (enemy $EF7F)"},
	{addr=0xAEB6, name="Golden Torizo's crescent projectile; doesn't run if Samus's ammo is too low (enemy $EF7F)"},
	{addr=0xB31A, name="Super missile that Golden Torizo throws at Samus (enemy $EF7F)"},
	{addr=0xB1C0, name="Hatchlings that Golden Torizo uses when it's almost dead (enemy $EF7F)"},
	{addr=0x9642, name="Ridley's fireball (enemy $E17F)"},
	{addr=0x965E, name="Something for Ridley (enemy $E17F)"},
	{addr=0x9688, name="Something for Ridley (enemy $E17F)"},
	{addr=0x9696, name="Something for Ridley (enemy $E17F)"},
	{addr=0xC17E, name="Something for Mother Brain; spawning turrets? (enemy $EC3F)"},
	{addr=0xC18C, name="Mother Brain's turret bullets (enemy $EC3F)"},
	{addr=0xCEFC, name="Mother Brain's glass shattering (enemy $EC3F)"},
	{addr=0xCF0A, name="Mother Brain's glass shards falling (enemy $EC3F)"},
	{addr=0xCB91, name="Mother Brain's mother brain's saliva (enemy $EC3F)"},
	{addr=0xCB2F, name="Mother Brain's purple breath, larger puff (enemy $EC3F)"},
	{addr=0xCB3D, name="Mother Brain's purple breath, smaller puff (enemy $EC3F)"},
	{addr=0xCB4B, name="Mother Brain's blue ring lasers (enemy $EC3F)"},
	{addr=0xA17B, name="Mother Brain's space pirate eye laser (enemy $EC3F)"},
	{addr=0xCB59, name="Mother Brain's bomb as it spawns from her mouth (enemy $EC3F)"},
	{addr=0x9650, name="Mother Brain's bomb as it bounces on ground (enemy $EC3F)"},
	{addr=0x966C, name="Mother Brain's bomb as it explodes (enemy $EC3F)"},
	{addr=0x967A, name="Mother Brain's bomb as it explodes again (enemy $EC3F)"},
	{addr=0xCB67, name="Mother Brain's orange chain explosion beam starting (enemy $EC3F)"},
	{addr=0xCB75, name="Mother Brain's orange chain explosion beam running (enemy $EC3F)"},
	{addr=0xCB83, name="Animated graphics in front of Mother Brain's eye while rainbow beam attack charges (enemy $EC3F)"},
	{addr=0xCBAD, name="Mother Brain's rainbow beam firing, runs while beam is active (enemy $EC3F)"},
	{addr=0xB743, name="Eye door projectiles (PLMs $DB48 and $DB56)"},
	{addr=0xD904, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xD912, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xD920, name="Created by the glass Maridia tube exploding (PLM $D70C, enemy $F0BF)"},
	{addr=0xF345, name="Enemy death graphics (different types of explosions, particles, etc.)"},
	{addr=0xF337, name="Unknown/varies. Spawning larger quantities of energy/ammo drops?"},
	{addr=0xE509, name="Unknown/varies. Used by boulder enemies, Kraid, Crocomire, Ridley, Mother Brain."},
	{addr=0xEC95, name="Unknown/varies. Runs when rooms with acid are loaded."},
}
for _,shot in ipairs(enemyShots) do
	shot.ptr = ffi.cast('enemyShot_t*', rom + bank_86 + shot.addr)
end


-- do the randomizing


if config.randomizeEnemies then
	enemyItemDropTable:randomize()
	enemyWeaknessTable:randomize()

	for i,enemy in ipairs(enemies) do
		if randomizeEnemyProps.deathEffect then
			enemy.ptr[0].deathEffect = math.random(0,4)
		end

		randomizeFieldExp(enemy.ptr, 'hurtTime')
		randomizeFieldExp(enemy.ptr, 'health')
		randomizeFieldExp(enemy.ptr, 'damage')

		for field,values in pairs(allEnemyFieldValues) do
			if randomizeEnemyProps[field] then
				enemy.ptr[0][field] = pickRandom(values.values)
			end
		end

		enemyWeaknessTable:randomizeEnemy(enemy)
		enemyItemDropTable:randomizeEnemy(enemy)
	end

	if randomizeEnemyProps.shotDamage then
		for _,shot in ipairs(enemyShots) do
			local value = shot.ptr[0].damageAndFlags
			local flags = bit.band(0xf000, value)
			local damage = bit.band(0xfff, value)
			damage = expRand(table.unpack(randomizeEnemyProps.shotDamageScaleRange)) * damage
			damage = math.clamp(damage, 0, 0xfff)
			shot.ptr[0].damageAndFlags = bit.bor(damage, flags)
		end
	end
end


-- do the printing


enemyItemDropTable:print()
enemyWeaknessTable:print()

print'enemies:'
for i,enemy in ipairs(enemies) do
	print(('0x%04x'):format(enemy.addr)..': '..enemy.name)
	print(' deathEffect='..enemy.ptr[0].deathEffect)

	for _,field in ipairs{'hurtTime', 'health', 'damage'} do
		print(' '..field..'='..enemy.ptr[0][field])
	end
	
	for field,values in pairs(allEnemyFieldValues) do
		print(' '..field..'='..('0x%x'):format(enemy.ptr[0][field]))
	end
	
	enemyWeaknessTable:printEnemy(enemy)
	enemyItemDropTable:printEnemy(enemy)
end


print'enemy shot table:'
for _,shot in ipairs(enemyShots) do
	print(shot.addr, shot.ptr[0])
end
