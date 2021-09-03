--[[
65816 disasm based on https://github.com/pelrun/Dispel/blob/master/65816.c
--]]

local ffi = require 'ffi'
local bit = require 'bit'

local instrsForNames = {
	ADC = {0x69, 0x6D, 0x6F, 0x65, 0x72, 0x67, 0x7D, 0x7F, 0x79, 0x75, 0x61, 0x71, 0x77, 0x63, 0x73},
	AND = {0x29, 0x2D, 0x2F, 0x25, 0x32, 0x27, 0x3D, 0x3F, 0x39, 0x35, 0x21, 0x31, 0x37, 0x23, 0x33},
	ASL = {0x0A, 0x0E, 0x06, 0x1E, 0x16},
	BCC = {0x90},
	BCS = {0xB0},
	BEQ = {0xF0},
	BNE = {0xD0},
	BMI = {0x30},
	BPL = {0x10},
	BVC = {0x50},
	BVS = {0x70},
	BRA = {0x80},
	BRL = {0x82},
	BIT = {0x89, 0x2C, 0x24, 0x3C, 0x34},
	BRK = {0x00},
	CLC = {0x18},
	CLD = {0xD8},
	CLI = {0x58},
	CLV = {0xB8},
	SEC = {0x38},
	SED = {0xF8},
	SEI = {0x78},
	CMP = {0xC9, 0xCD, 0xCF, 0xC5, 0xD2, 0xC7, 0xDD, 0xDF, 0xD9, 0xD5, 0xC1, 0xD1, 0xD7, 0xC3, 0xD3},
	COP = {0x02},
	CPX = {0xE0, 0xEC, 0xE4},
	CPY = {0xC0, 0xCC, 0xC4},
	DEC = {0x3A, 0xCE, 0xC6, 0xDE, 0xD6},
	DEX = {0xCA},
	DEY = {0x88},
	EOR = {0x49, 0x4D, 0x4F, 0x45, 0x52, 0x47, 0x5D, 0x5F, 0x59, 0x55, 0x41, 0x51, 0x57, 0x43, 0x53},
	INC = {0x1A, 0xEE, 0xE6, 0xFE, 0xF6},
	INX = {0xE8},
	INY = {0xC8},
	JMP = {0x4C, 0x6C, 0x7C, 0x5C, 0xDC},
	JSR = {0x22, 0x20, 0xFC},
	LDA = {0xA9, 0xAD, 0xAF, 0xA5, 0xB2, 0xA7, 0xBD, 0xBF, 0xB9, 0xB5, 0xA1, 0xB1, 0xB7, 0xA3, 0xB3},
	LDX = {0xA2, 0xAE, 0xA6, 0xBE, 0xB6},
	LDY = {0xA0, 0xAC, 0xA4, 0xBC, 0xB4},
	LSR = {0x4A, 0x4E, 0x46, 0x5E, 0x56},
	MVN = {0x54},
	MVP = {0x44},
	NOP = {0xEA},
	ORA = {0x09, 0x0D, 0x0F, 0x05, 0x12, 0x07, 0x1D, 0x1F, 0x19, 0x15, 0x01, 0x11, 0x17, 0x03, 0x13},
	PEA = {0xF4},
	PEI = {0xD4},
	PER = {0x62},
	PHA = {0x48},
	PHP = {0x08},
	PHX = {0xDA},
	PHY = {0x5A},
	PLA = {0x68},
	PLP = {0x28},
	PLX = {0xFA},
	PLY = {0x7A},
	PHB = {0x8B},
	PHD = {0x0B},
	PHK = {0x4B},
	PLB = {0xAB},
	PLD = {0x2B},
	REP = {0xC2},
	ROL = {0x2A, 0x2E, 0x26, 0x3E, 0x36},
	ROR = {0x6A, 0x6E, 0x66, 0x7E, 0x76},
	RTI = {0x40},
	RTL = {0x6B},
	RTS = {0x60},
	SBC = {0xE9, 0xED, 0xEF, 0xE5, 0xF2, 0xE7, 0xFD, 0xFF, 0xF9, 0xF5, 0xE1, 0xF1, 0xF7, 0xE3, 0xF3},
	SEP = {0xE2},
	STA = {0x8D, 0x8F, 0x85, 0x92, 0x87, 0x9D, 0x9F, 0x99, 0x95, 0x81, 0x91, 0x97, 0x83, 0x93},
	STP = {0xDB},
	STX = {0x8E, 0x86, 0x96},
	STY = {0x8C, 0x84, 0x94},
	STZ = {0x9C, 0x64, 0x9E, 0x74},
	TAX = {0xAA},
	TAY = {0xA8},
	TXA = {0x8A},
	TYA = {0x98},
	TSX = {0xBA},
	TXS = {0x9A},
	TXY = {0x9B},
	TYX = {0xBB},
	TCD = {0x5B},
	TDC = {0x7B},
	TCS = {0x1B},
	TSC = {0x3B},
	TRB = {0x1C, 0x14},
	TSB = {0x0C, 0x04},
	WAI = {0xCB},
	WDM = {0x42},
	XBA = {0xEB},
	XCE = {0xFB},
}

local formatsAndSizesInfo = {
	{
		instrs = {0x0C, 0x0D, 0x0E, 0x1C, 0x20, 0x2C, 0x2D, 0x2E, 0x4C, 0x4D, 0x4E, 0x6D, 0x6E, 0x8C, 0x8D, 0x8E, 0x9C, 0xAC, 0xAD, 0xAE, 0xCC, 0xCD, 0xCE, 0xEC, 0xED, 0xEE},
		function(addr, flag, mem)
			return ("$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0x7C, 0xFC},
		function(addr, flag, mem)
			return ("($%04X,X)"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0x1D, 0x1E, 0x3C, 0x3D, 0x3E, 0x5D, 0x5E, 0x7D, 0x7E, 0x9D, 0x9E, 0xBC, 0xBD, 0xDD, 0xDE, 0xFD, 0xFE},
		function(addr, flag, mem)
			return ("$%04X,X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0x19, 0x39, 0x59, 0x79, 0x99, 0xB9, 0xBE, 0xD9, 0xF9},
		function(addr, flag, mem)
			return ("$%04X,Y"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0x6C},
		function(addr, flag, mem)
			return ("($%04X)"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0xDC},
		function(addr, flag, mem)
			return ("[$%04X]"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0x0F, 0x22, 0x2F, 0x4F, 0x5C, 0x6F, 0x8F, 0xAF, 0xCF, 0xEF},
		function(addr, flag, mem)
			return ("$%02X:%04X"):format(mem[3],  bit.bor(mem[1], bit.lshift(mem[2], 8))), 4
		end,
	}, {
		instrs = {0x1F, 0x3F, 0x5F, 0x7F, 0x9F, 0xBF, 0xDF, 0xFF},
		function(addr, flag, mem)
			return ("$%02X:%04X,X"):format(mem[3], bit.bor(mem[1], bit.lshift(mem[2], 8))), 4
		end,
	}, {
		instrs = {0x0A, 0x1A, 0x2A, 0x3A, 0x4A, 0x6A},
		function(addr, flag, mem)
			return string.format("A"), 1
		end,
	}, {
		instrs = {0x44, 0x54},
		function(addr, flag, mem)
			return ("$%02X,$%02X"):format(mem[1],mem[2]), 3
		end,
	}, {
		instrs = {0x04, 0x05, 0x06, 0x14, 0x24, 0x25, 0x26, 0x45, 0x46, 0x64, 0x65, 0x66, 0x84, 0x85, 0x86, 0xA4, 0xA5, 0xA6, 0xC4, 0xC5, 0xC6, 0xE4, 0xE5, 0xE6},
		function(addr, flag, mem)
			return ("$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x15, 0x16, 0x34, 0x35, 0x36, 0x55, 0x56, 0x74, 0x75, 0x76, 0x94, 0x95, 0xB4, 0xB5, 0xD5, 0xD6, 0xF5, 0xF6},
		function(addr, flag, mem)
			return ("$%02X,X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x96, 0xB6},
		function(addr, flag, mem)
			return ("$%02X,Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x12, 0x32, 0x52, 0x72, 0x92, 0xB2, 0xD2, 0xF2},
		function(addr, flag, mem)
			return ("($%02X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x07, 0x27, 0x47, 0x67, 0x87, 0xA7, 0xC7, 0xE7},
		function(addr, flag, mem)
			return ("[$%02X]"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x01, 0x21, 0x41, 0x61, 0x81, 0xA1, 0xC1, 0xE1},
		function(addr, flag, mem)
			return ("($%02X,X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x11, 0x31, 0x51, 0x71, 0x91, 0xB1, 0xD1, 0xF1},
		function(addr, flag, mem)
			return ("($%02X),Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x17, 0x37, 0x57, 0x77, 0x97, 0xB7, 0xD7, 0xF7},
		function(addr, flag, mem)
			return ("[$%02X],Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x28, 0x2B, 0x68, 0x7A, 0xAB, 0xFA, 0x08, 0x0B, 0x48, 0x4B, 0x5A, 0x8B, 0xDA, 0x6B, 0x60, 0x40, 0x18, 0x1B, 0x38, 0x3B, 0x58, 0x5B, 0x78, 0x7B, 0x88, 0x8A, 0x98, 0x9A, 0x9B, 0xA8, 0xAA, 0xB8, 0xBA, 0xBB, 0xC8, 0xCA, 0xCB, 0xD8, 0xDB, 0xE8, 0xEA, 0xEB, 0xF8, 0xFB},
		function(addr, flag, mem) return "", 1 end,
	}, {
		instrs = {0x10, 0x30, 0x50, 0x70, 0x80, 0x90, 0xB0, 0xD0, 0xF0},
		function(addr, flag, mem)
			local sval = (mem[1]>127) and (mem[1]-256) or mem[1]
			return ("$%04X"):format(bit.band(addr+sval+2, 0xFFFF)), 2
		end,
	}, {
		instrs = {0x62, 0x82},
		function(addr, flag, mem)
			local sval = bit.bor(mem[1], bit.lshift(mem[2], 8))
			sval = (sval>32767) and (sval-65536) or sval
			return ("$%04X"):format(bit.band(addr+sval+3, 0xFFFF)), 3
		end,
	}, {
		instrs = {0x13, 0x33, 0x53, 0x73, 0x93, 0xB3, 0xD3, 0xF3},
		function(addr, flag, mem)
			return ("($%02X,S),Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0xF4},
		function(addr, flag, mem)
			return ("$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, {
		instrs = {0xD4},
		function(addr, flag, mem)
			return ("($%02X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x03, 0x23, 0x43, 0x63, 0x83, 0xA3, 0xC3, 0xE3},
		function(addr, flag, mem)
			return ("$%02X,S"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x42, 0x00, 0x02},
		function(addr, flag, mem)
			return ("$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0xC2},
		function(addr, flag, mem)
			flag[0] = bit.band(flag[0], bit.bnot(mem[1]))
			return ("#$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0xE2},
		function(addr, flag, mem)
			flag[0] = bit.bor(flag[0], mem[1])
			return ("#$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x09, 0x29, 0x49, 0x69, 0x89, 0xA9, 0xC9, 0xE9},
		function(addr, flag, mem)
			if bit.band(flag[0], 0x20) ~= 0 then
				return ("#$%02X"):format(mem[1]), 2
			else
				return ("#$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
			end
		end,
	}, {
		instrs = {0xA0, 0xA2, 0xC0, 0xE0},
		function(addr, flag, mem)
			if bit.band(flag[0], 0x10) ~= 0 then
				return ("#$%02X"):format(mem[1]), 2
			else
				return ("#$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
			end
		end,
	}
}

--[[
stores:
	name = 3-letter caps name of the instruction
	eat = function that takes:
			addr = address, the first 16 bits are used
			flag = table/cdata with [0] pointing to the flag state of the chip
			mem = array of the next 3 bytes in memory
		returns:
			string generated for the instruction arguments,
			number of bytes that were read / to advance

	eatcname = function like eat but produces c-like pseudocode
--]]
local instrInfo = {}
for name, instrs in pairs(instrsForNames) do
	for _,instr in ipairs(instrs) do
		instrInfo[instr] = {name=name}
	end
end
for _,info in ipairs(formatsAndSizesInfo) do
	for _,instr in ipairs(info.instrs) do
		instrInfo[instr].eat = info[1]
	end
end



local frompc = require 'pc'.from

local flag = ffi.new('uint8_t[1]', 0)

local function getLineStr(addr, flag, ...)
	local code0, code1, code2, code3 = ...
	local instr = instrInfo[code0]
	local instrstr, n = instr.eat(
		addr,	-- TODO ... 0000 vs 8000 here, and BEQ resolving the correct address ...
		flag,	-- or maybe I just shouldn't use 'frompc' next:
		{
			code1,
			code2,
			code3
		}	-- TODO just use ptrs
	)
	local bank, instrofs = frompc(addr)
	-- notice frompc is snes based so it's only using 15 bits and setting the 15th
	-- so wrt addresses, 0x0000-1 = 0xffff, but 0x0000 will show up as address 0x8000 (15th bit goes into the bank) 
	local linestr = ('$%02X:%04X'):format(bank, instrofs)
	for j=0,3 do
		if j < n then
			linestr = linestr .. (' %02X'):format(select(j+1, ...) or 0x00)
		else
			linestr = linestr .. '   '
		end
	end
	linestr = linestr ..' '..instr.name..' '..instrstr
	return linestr, n
end

-- code is lua table, 1-based
local function disasm(addr, code)
	flag[0] = 0
	local ss = table()
	local ofs = 0
	local maxlen = #code
	while ofs < maxlen do
		local str, n = getLineStr(
			addr+ofs,
			flag,
			code[ofs+1],
			ofs+1 < maxlen and code[ofs+2] or 0x00,
			ofs+2 < maxlen and code[ofs+3] or 0x00,
			ofs+3 < maxlen and code[ofs+4] or 0x00
		)
		ss:insert(str)
		ofs = ofs + n
	end
	return ss:concat'\n'
end

--[[
reads instructions, stops at RTS, returns contents in a Lua table
(TODO return a uint8_t[] instead?)
(TODO generate the disasm string as you go?)
--]]
local function readCode(addr, rom, maxlen)
	flag[0] = 0
	ptr = rom + addr
	local ofs = 0
	while ofs < maxlen do
		local instr = instrInfo[ptr[ofs]]
		local _ , n = instr.eat(
			addr+ofs,
			flag,
			{
				ofs+1 < maxlen and ptr[ofs+1] or 0x00,
				ofs+2 < maxlen and ptr[ofs+2] or 0x00,
				ofs+3 < maxlen and ptr[ofs+3] or 0x00
			}	-- TODO just pass the ptr
		)
		ofs = ofs + n
		if instr.name == 'RTS' then break end
	end
	-- can't do this, because it uses sizeof(ptr), and rom is just a uint8_t*, not uint8_t[]
	--local code = byteArraySubset(rom, addr, ofs)	-- TODO (rom+addr, ofs)
	local code = ffi.new('uint8_t[?]', ofs)
	ffi.copy(code, rom + addr, ofs)
	return byteArrayToTable(code)
end

return {
	disasm = disasm,
	readCode = readCode,
	instrInfo = instrInfo,
	getLineStr = getLineStr,
}
