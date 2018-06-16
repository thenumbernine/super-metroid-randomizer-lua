-- port of SMLib/ROMHandler.cs
-- https://github.com/tewtal/smlib
-- with some extra from metroidconstruction.com/SMMM

local ffi = require 'ffi'
local makestruct = require 'makestruct'

-- check where the PLM bank is
local plmBank = rom[0x204ac]

local scrollBank = 0x8f

local name = ffi.string(rom + 0x7fc0, 0x15)
print(name)


-- defined in section 6
local mdb_t = makestruct'mdb_t'{
	{index = 'uint8_t'},
	{region = 'uint8_t'},
	{x = 'uint8_t'},
	{y = 'uint8_t'},
	{width = 'uint8_t'},
	{height = 'uint8_t'},
	{upScroller = 'uint8_t'},	
	{downScroller = 'uint8_t'},	
	{gfxFlags = 'uint8_t'},	
	{doors = 'uint16_t'},	-- offset at bank  ... 9f?
}

local roomstate_t = makestruct'roomstate_t'{
	{data = 'uint24_t'},
	{gfxSet = 'uint8_t'},
	{music = 'uint16_t'},
	{fx1 = 'uint16_t'},
	{enemyPop = 'uint16_t'},
	{enemySet = 'uint16_t'},
	{layer2scrollData = 'uint16_t'},
	{scroll = 'uint16_t'},
	{unused = 'uint16_t'},
	{fx2 = 'uint16_t'},
	{bgDataPtr = 'uint16_t'},
	{layerHandling = 'uint16_t'},
}

for x=0x8000,0xffff do
	local addr = 0x70000 + x
	local data = rom + addr
	local function read(ctype)
		local result = ffi.cast(ctype..'*', data)
		data = data + ffi.sizeof(ctype)
		return result
	end
	local mdb = {
		roomStates = table(),
	}
	mdb.ptr = ffi.cast('mdb_t*', data)
	if (
		(data[12] == 0xE5 or data[12] == 0xE6) 
		and data[1] < 8 
		and (data[4] ~= 0 and data[4] < 20) 
		and (data[5] ~= 0 and data[5] < 20)
		and data[6] ~= 0 
		and data[7] ~= 0 
		and data[8] < 0x10 
		and data[10] > 0x7F
	) then
		data = data + 11

		local testCode
		local testValue, testValueDoor
		while true do
			testCode = read'uint16_t'
			if testCode == 0xe5e6 then break end
			if testCode == 0xffff then break end

			if testCode == 0xE612 or testCode == 0xE629 then
				testValue = read'uint8_t'
			elseif testCode == 0xE5EB then
				testValueDoor = read'uint16_t'
			end

			local roomStatePtr = read'uint16_t'
			mdb:roomStates:insert{
				testCode = testCode,
				testValue = testValue,
				testValueDoor = testValueDoor,
				ptr = roomStatePtr,
			}
		end
	
		if testCode ~= 0xffff then

			local roomState = ffi.cast('roomstate_t*', data)
			data = data + ffi.sizeof'roomstate_t'

			local ds = {}
			ds.ptr = roomState
			
			mdb.roomStates:insert(ds)
		end
	end
end

os.exit()



-- wtf does mdb stand for?
local mdbs = table{
	{addr=0x791F8},
	{addr=0x792B3},
	{addr=0x792FD},
	{addr=0x793AA},
	{addr=0x793D5},
	{addr=0x793FE},
	{addr=0x79461},
	{addr=0x7948C},
	{addr=0x794CC},
	{addr=0x794FD},
	{addr=0x79552},
	{addr=0x7957D},
	{addr=0x795A8},
	{addr=0x795D4},
	{addr=0x795FF},
	{addr=0x7962A},
	{addr=0x7965B},
	{addr=0x7968F},
	{addr=0x796BA},
	{addr=0x7975C},
	{addr=0x797B5},
	{addr=0x79804},
	{addr=0x79879},
	{addr=0x798E2},
	{addr=0x7990D},
	{addr=0x79938},
	{addr=0x79969},
	{addr=0x79994},
	{addr=0x799BD},
	{addr=0x799F9},
	{addr=0x79A44},
	{addr=0x79A90},
	{addr=0x79AD9},
	{addr=0x79B5B},
	{addr=0x79B9D},
	{addr=0x79BC8},
	{addr=0x79C07},
	{addr=0x79C35},
	{addr=0x79C5E},
	{addr=0x79C89},
	{addr=0x79CB3},
	{addr=0x79D19},
	{addr=0x79D9C},
	{addr=0x79DC7},
	{addr=0x79E11},
	{addr=0x79E52},
	{addr=0x79E9F},
	{addr=0x79F11},
	{addr=0x79F64},
	{addr=0x79FBA},
	{addr=0x79FE5},
	{addr=0x7A011},
	{addr=0x7A051},
	{addr=0x7A07B},
	{addr=0x7A0A4},
	{addr=0x7A0D2},
	{addr=0x7A107},
	{addr=0x7A130},
	{addr=0x7A15B},
	{addr=0x7A184},
	{addr=0x7A1AD},
	{addr=0x7A1D8},
	{addr=0x7A201},
	{addr=0x7A22A},
	{addr=0x7A253},
	{addr=0x7A293},
	{addr=0x7A2CE},
	{addr=0x7A2F7},
	{addr=0x7A322},
	{addr=0x7A37C},
	{addr=0x7A3AE},
	{addr=0x7A3DD},
	{addr=0x7A408},
	{addr=0x7A447},
	{addr=0x7A471},
	{addr=0x7A4B1},
	{addr=0x7A4DA},
	{addr=0x7A521},
	{addr=0x7A56B},
	{addr=0x7A59F},
	{addr=0x7A5ED},
	{addr=0x7A618},
	{addr=0x7A641},
	{addr=0x7A66A},
	{addr=0x7A6A1},
	{addr=0x7A6E2},
	{addr=0x7A70B},
	{addr=0x7A734},
	{addr=0x7A75D},
	{addr=0x7A788},
	{addr=0x7A7B3},
	{addr=0x7A7DE},
	{addr=0x7A815},
	{addr=0x7A865},
	{addr=0x7A890},
	{addr=0x7A8B9},
	{addr=0x7A8F8},
	{addr=0x7A923},
	{addr=0x7A98D},
	{addr=0x7A9E5},
	{addr=0x7AA0E},
	{addr=0x7AA41},
	{addr=0x7AA82},
	{addr=0x7AAB5},
	{addr=0x7AADE},
	{addr=0x7AB07},
	{addr=0x7AB3B},
	{addr=0x7AB64},
	{addr=0x7AB8F},
	{addr=0x7ABD2},
	{addr=0x7AC00},
	{addr=0x7AC2B},
	{addr=0x7AC5A},
	{addr=0x7AC83},
	{addr=0x7ACB3},
	{addr=0x7ACF0},
	{addr=0x7AD1B},
	{addr=0x7AD5E},
	{addr=0x7ADAD},
	{addr=0x7ADDE},
	{addr=0x7AE07},
	{addr=0x7AE32},
	{addr=0x7AE74},
	{addr=0x7AEB4},
	{addr=0x7AEDF},
	{addr=0x7AF14},
	{addr=0x7AF3F},
	{addr=0x7AF72},
	{addr=0x7AFA3},
	{addr=0x7AFCE},
	{addr=0x7AFFB},
	{addr=0x7B026},
	{addr=0x7B051},
	{addr=0x7B07A},
	{addr=0x7B0B4},
	{addr=0x7B0DD},
	{addr=0x7B106},
	{addr=0x7B139},
	{addr=0x7B167},
	{addr=0x7B192},
	{addr=0x7B1BB},
	{addr=0x7B1E5},
	{addr=0x7B236},
	{addr=0x7B283},
	{addr=0x7B2DA},
	{addr=0x7B305},
	{addr=0x7B32E},
	{addr=0x7B37A},
	{addr=0x7B3A5},
	{addr=0x7B3E1},
	{addr=0x7B40A},
	{addr=0x7B457},
	{addr=0x7B482},
	{addr=0x7B4AD},
	{addr=0x7B4E5},
	{addr=0x7B510},
	{addr=0x7B55A},
	{addr=0x7B585},
	{addr=0x7B5D5},
	{addr=0x7B62B},
	{addr=0x7B656},
	{addr=0x7B698},
	{addr=0x7B6C1},
	{addr=0x7B6EE},
	{addr=0x7B741},
	{addr=0x7C98E},
	{addr=0x7CA08},
	{addr=0x7CA52},
	{addr=0x7CAAE},
	{addr=0x7CAF6},
	{addr=0x7CB8B},
	{addr=0x7CBD5},
	{addr=0x7CC27},
	{addr=0x7CC6F},
	{addr=0x7CCCB},
	{addr=0x7CD13},
	{addr=0x7CD5C},
	{addr=0x7CDA8},
	{addr=0x7CDF1},
	{addr=0x7CE40},
	{addr=0x7CE8A},
	{addr=0x7CED2},
	{addr=0x7CEFB},
	{addr=0x7CF54},
	{addr=0x7CF80},
	{addr=0x7CFC9},
	{addr=0x7D017},
	{addr=0x7D055},
	{addr=0x7D08A},
	{addr=0x7D0B9},
	{addr=0x7D104},
	{addr=0x7D13B},
	{addr=0x7D16D},
	{addr=0x7D1A3},
	{addr=0x7D1DD},
	{addr=0x7D21C},
	{addr=0x7D252},
	{addr=0x7D27E},
	{addr=0x7D2AA},
	{addr=0x7D2D9},
	{addr=0x7D30B},
	{addr=0x7D340},
	{addr=0x7D387},
	{addr=0x7D3B6},
	{addr=0x7D3DF},
	{addr=0x7D408},
	{addr=0x7D433},
	{addr=0x7D461},
	{addr=0x7D48E},
	{addr=0x7D4C2},
	{addr=0x7D4EF},
	{addr=0x7D51E},
	{addr=0x7D54D},
	{addr=0x7D57A},
	{addr=0x7D5A7},
	{addr=0x7D5EC},
	{addr=0x7D617},
	{addr=0x7D646},
	{addr=0x7D69A},
	{addr=0x7D6D0},
	{addr=0x7D6FD},
	{addr=0x7D72A},
	{addr=0x7D765},
	{addr=0x7D78F},
	{addr=0x7D7E4},
	{addr=0x7D81A},
	{addr=0x7D845},
	{addr=0x7D86E},
	{addr=0x7D898},
	{addr=0x7D8C5},
	{addr=0x7D913},
	{addr=0x7D95E},
	{addr=0x7D9AA},
	{addr=0x7D9D4},
	{addr=0x7D9FE},
	{addr=0x7DA2B},
	{addr=0x7DA60},
	{addr=0x7DAAE},
	{addr=0x7DAE1},
	{addr=0x7DB31},
	{addr=0x7DB7D},
	{addr=0x7DBCD},
	{addr=0x7DC19},
	{addr=0x7DC65},
	{addr=0x7DCB1},
	{addr=0x7DCFF},
	{addr=0x7DD2E},
	{addr=0x7DD58},
	{addr=0x7DDC4},
	{addr=0x7DDF3},
	{addr=0x7DE23},
	{addr=0x7DE4D},
	{addr=0x7DE7A},
	{addr=0x7DEA7},
	{addr=0x7DEDE},
	{addr=0x7DF1B},
	{addr=0x7DF45},
	{addr=0x7DF8D},
	{addr=0x7DFD7},
	{addr=0x7E021},
	{addr=0x7E06B},
	{addr=0x7E0B5},
	{addr=0x7E82C},
}

-- I got this from SMILE.  no idea what the data description is.
local rooms = table{
	{addr=0x2142BB},
	{addr=0x2156E8},
	{addr=0x215BC4},
	{addr=0x216977},
	{addr=0x216B45},
	{addr=0x218E1F},
	{addr=0x218FFE},
	{addr=0x219BFC},
	{addr=0x219DB8},
	{addr=0x21ACDB},
	{addr=0x21B1BA},
	{addr=0x21BB9B},
	{addr=0x21BCD2},
	{addr=0x21BD6D},
	{addr=0x21C145},
	{addr=0x21C301},
	{addr=0x21C80C},
	{addr=0x21C998},
	{addr=0x21D9F7},
	{addr=0x21DF23},
	{addr=0x21E0D0},
	{addr=0x21E16E},
	{addr=0x21E232},
	{addr=0x21E2FC},
	{addr=0x21E985},
	{addr=0x21EB35},
	{addr=0x21EE60},
	{addr=0x21F4D3},
	{addr=0x22011E},
	{addr=0x220232},
	{addr=0x2271CE},
	{addr=0x228BD5},
	{addr=0x229642},
	{addr=0x229755},
	{addr=0x229B00},
	{addr=0x229CAC},
	{addr=0x22A15F},
	{addr=0x22B54D},
	{addr=0x22CBA7},
	{addr=0x22CE34},
	{addr=0x22D18F},
	{addr=0x22D559},
	{addr=0x22DED5},
	{addr=0x22E63A},
	{addr=0x22E86F},
	{addr=0x22ECAE},
	{addr=0x22EF71},
	{addr=0x22F057},
	{addr=0x22F43E},
	{addr=0x22F4C9},
	{addr=0x22F778},
	{addr=0x22FD50},
	{addr=0x22FE1B},
	{addr=0x2301C2},
	{addr=0x230318},
	{addr=0x230437},
	{addr=0x2304EE},
	{addr=0x2311E3},
	{addr=0x231BF9},
	{addr=0x231D70},
	{addr=0x231F4B},
	{addr=0x23331F},
	{addr=0x23358C},
	{addr=0x233739},
	{addr=0x23391C},
	{addr=0x233CC7},
	{addr=0x233D83},
	{addr=0x234469},
	{addr=0x234630},
	{addr=0x234DB9},
	{addr=0x2352CB},
	{addr=0x235620},
	{addr=0x23588D},
	{addr=0x235EE0},
	{addr=0x236355},
	{addr=0x2364A4},
	{addr=0x2365F5},
	{addr=0x236CB9},
	{addr=0x2372E1},
	{addr=0x2378C1},
	{addr=0x2382ED},
	{addr=0x2384A3},
	{addr=0x2385D6},
	{addr=0x238A47},
	{addr=0x238CFA},
	{addr=0x239D71},
	{addr=0x23A036},
	{addr=0x23A18D},
	{addr=0x23AA70},
	{addr=0x23AEB3},
	{addr=0x23B28B},
	{addr=0x23B3E7},
	{addr=0x23B780},
	{addr=0x23BB6B},
	{addr=0x23BECB},
	{addr=0x23CD91},
	{addr=0x23CFCD},
	{addr=0x23D13C},
	{addr=0x23D4FE},
	{addr=0x23D66F},
	{addr=0x23D895},
	{addr=0x23E08C},
	{addr=0x23EAA8},
	{addr=0x23EC03},
	{addr=0x23FF02},
	{addr=0x240532},
	{addr=0x24065C},
	{addr=0x240953},
	{addr=0x24143A},
	{addr=0x241D5D},
	{addr=0x241FE3},
	{addr=0x2422CF},
	{addr=0x242A89},
	{addr=0x242BED},
	{addr=0x24315B},
	{addr=0x2434F9},
	{addr=0x243853},
	{addr=0x2439CF},
	{addr=0x243B21},
	{addr=0x243DE8},
	{addr=0x244165},
	{addr=0x2444D3},
	{addr=0x24559C},
	{addr=0x24609D},
	{addr=0x246900},
	{addr=0x246BFD},
	{addr=0x246DCE},
	{addr=0x24701F},
	{addr=0x24740B},
	{addr=0x24758B},
	{addr=0x247CC5},
	{addr=0x248222},
	{addr=0x2484D3},
	{addr=0x24899F},
	{addr=0x2494BA},
	{addr=0x249CE2},
	{addr=0x249E7B},
	{addr=0x24A88C},
	{addr=0x24B1C7},
	{addr=0x24B4AB},
	{addr=0x24C30D},
	{addr=0x24C428},
	{addr=0x24C706},
	{addr=0x220322},
	{addr=0x221D2E},
	{addr=0x221EAE},
	{addr=0x222720},
	{addr=0x2229AC},
	{addr=0x225187},
	{addr=0x2253EE},
	{addr=0x225883},
	{addr=0x22614E},
	{addr=0x22658C},
	{addr=0x2266A5},
	{addr=0x22694E},
	{addr=0x226A8F},
	{addr=0x2270A1},
	{addr=0x24DB52},
	{addr=0x24E6AE},
	{addr=0x24E809},
	{addr=0x24F225},
	{addr=0x250EFF},
	{addr=0x252113},
	{addr=0x252F99},
	{addr=0x25324F},
	{addr=0x254E42},
	{addr=0x255474},
	{addr=0x255BC8},
	{addr=0x256458},
	{addr=0x25759C},
	{addr=0x2583DB},
	{addr=0x25883A},
	{addr=0x2589E0},
	{addr=0x258BD4},
	{addr=0x259792},
	{addr=0x25A0D0},
	{addr=0x25A878},
	{addr=0x25C64F},
	{addr=0x25CD9F},
	{addr=0x25DCF3},
	{addr=0x25DE8F},
	{addr=0x25E472},
	{addr=0x25E899},
	{addr=0x25EC32},
	{addr=0x25F580},
	{addr=0x25FEC8},
	{addr=0x2600B8},
	{addr=0x2602A8},
	{addr=0x26213B},
	{addr=0x26234A},
	{addr=0x262C48},
	{addr=0x263843},
	{addr=0x263D31},
	{addr=0x26422F},
	{addr=0x2649F1},
	{addr=0x2665B1},
	{addr=0x266E0C},
	{addr=0x267A8D},
	{addr=0x267B88},
	{addr=0x267D75},
	{addr=0x268A37},
	{addr=0x26950E},
	{addr=0x26991E},
	{addr=0x269B28},
	{addr=0x26A00D},
	{addr=0x26B19D},
	{addr=0x26C4FE},
	{addr=0x26C8DC},
	{addr=0x26CDA0},
	{addr=0x26D02D},
	{addr=0x26D3E5},
	{addr=0x26D5EB},
	{addr=0x26D7C4},
	{addr=0x26D930},
	{addr=0x26DBF8},
	{addr=0x26DEDE},
	{addr=0x26E20F},
	{addr=0x26E518},
	{addr=0x26E914},
	{addr=0x26EB5B},
	{addr=0x26ED7A},
	{addr=0x26F534},
	{addr=0x26B846},
	{addr=0x26BBFE},
	{addr=0x26BD78},
	{addr=0x26BFC9},
	{addr=0x26C330},
	{addr=0x26C43F},
	{addr=0x2703C3},
	{addr=0x2706BD},
	{addr=0x2709B6},
	{addr=0x270CB3},
	{addr=0x270FA6},
	{addr=0x2712CB},
	{addr=0x2715C2},
	{addr=0x2718DC},
	{addr=0x271BE9},
	{addr=0x271EF6},
	{addr=0x272201},
	{addr=0x272823},
	{addr=0x272B31},
	{addr=0x272E3E},
	{addr=0x2FD581},
	{addr=0x2FE000},
	{addr=0x2FF000},
}

-- defined in section 6
local mdb_t = makestruct'mdb_t'{
	{index = 'uint8_t'},
	{region = 'uint8_t'},
	{x = 'uint8_t'},
	{y = 'uint8_t'},
	{width = 'uint8_t'},
	{height = 'uint8_t'},
	{upScroller = 'uint8_t'},	
	{downScroller = 'uint8_t'},	
	{gfxFlags = 'uint8_t'},	
	{doors = 'uint16_t'},	-- offset at bank  ... 9f?

--	{events = 'uint16_t'},	-- offset ... 'testCode' in SMLib
--	{eventTrigger = 'uint8_t'},
--	{eventRoomPtr = 'uint16_t'},

--[[
	{standard1ptr = 'uint16_t'},
	{level1dataptr ' uint24_t'},
	{tileset = 'uint8_t'},
	{songset = 'uint8_t'},
	{playindex = 'uint8_t'},
	{fxptr = 'uint16_t'},
	{enemySetPtr = 'uint16_t'},
	{enemyGfxPtr = 'uint16_t'},
	{bgScrollX = 'uint8_t'},
	{bgScrollY = 'uint8_t'},
	{roomScrollPtr = 'uint16_t'},
	{unused = 'uint16_t'},
	{mainASMPtr = 'uint16_t'},
	{PLMSetPtr = 'uint16_t'},
	{bgPtr = 'uint16_t'},
	{setupASMPtr = 'uint16_t'},
--]]
}

local door_t = makestruct'door_t'(range(0,11):map(function(i)
	return {['_'..i] = 'uint8_t'} 
end))

local bank_83 = 0x10000
local bank_8f = 0x70000

for _,mdb in ipairs(mdbs) do
	mdb.ptr = ffi.cast('mdb_t*', rom + mdb.addr)
	
	print(('0x%06x: '):format(mdb.addr)..mdb.ptr[0])

	local doorlistaddr = bank_8f + mdb.ptr[0].doors
	local ptr = ffi.cast('uint16_t*', rom+doorlistaddr)
	local done
	for i=0,31 do
		--[[
		io.write((' %04x'):format(ptr[0]))
		--]]	
		--[[
		local dooraddr = bank_83 + ptr[0] 
		print((' 0x%06x:'):format(dooraddr))
		local doorptr = ffi.cast('door_t*', rom + dooraddr)
		print('  '..doorptr[0])
		--]]
		-- [[
		local dooraddr = bank_83 + ptr[0] 
		print((' 0x%06x:'):format(dooraddr))
		local doorptr = rom + dooraddr
		io.write' '
		for i=0,11 do
			io.write((' %02x'):format(doorptr[i]))
		end
		print()
		--]]

		ptr = ptr + 1
		if ptr[0] == 0 then 
			done = true
			break 
		end
	end
	if not done then print' ...' end
	print()
end
