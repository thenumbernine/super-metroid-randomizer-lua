--[[
65816 disasm based on https://github.com/pelrun/Dispel/blob/master/65816.c
help from:
https://wiki.superfamicom.org/65816-reference
https://www.westerndesigncenter.com/wdc/documentation/w65c816s.pdf


typedef struct {
	uint8_t carry : 1;
	uint8_t zero : 1;
	uint8_t interrupt_disable : 1;
	uint8_t decimal : 1;
	uint8_t index_register_is_8bit : 1;		//set to 0 for using 16 bit 
	uint8_t memory_register_is_8bit : 1;
	uint8_t overflow : 1;
	uint8_t negative : 1;
} flags_t flags;

struct {
	uint16_t accum;		//aka "C"
	struct {
		uint8_t a;
		uint8_t b;
	};
};

uint8_t x, y;
uint8_t stack;			//aka "S"
uint8_t data_bank;		//aka "DBR" / "DB"
uint8_t direct_page;	//aka "D" / "DP"
uint8_t program_bank;	//aka "PB" / "PBR"
uint8_t flags;			//aka "status" / "P"
uint8_t pc;				//program counter


uint8_t mem[];

typedef uint8_t uint24_t[3];

uint24_t addr24(uint8_t bank, uint16_t offset) {
	return ((bank & 0x7f) << 15) | (offset & 0x7fff);
}

uint8_t* data_bank_ptr = mem + addr24(data_bank, 0);

uint16_t& mem16(uint8_t bank, uint16_t offset) {
	return *(uint16_t*)(mem + add24(bank, offset));
}

--]]

local ffi = require 'ffi'
local bit = require 'bit'
local table = require 'ext.table'

local byteArraySubset = require 'util'.byteArraySubset

-- idk what this is.  should jmps turn into gotos?  or should this be emulation-equivalents where jmps assign pc?
local tryToPrintCEquiv = false

local instrsForNames = {
	ADC = {
		instrs = {0x69, 0x6D, 0x6F, 0x65, 0x72, 0x67, 0x7D, 0x7F, 0x79, 0x75, 0x61, 0x71, 0x77, 0x63, 0x73},
	},
	AND = {
		instrs = {0x29, 0x2D, 0x2F, 0x25, 0x32, 0x27, 0x3D, 0x3F, 0x39, 0x35, 0x21, 0x31, 0x37, 0x23, 0x33},
	},
	ASL = {
		instrs = {0x0A, 0x0E, 0x06, 0x1E, 0x16},
	},
	BCC = {
		instrs = {0x90},
	},
	BCS = {
		instrs = {0xB0},
	},
	BEQ = {
		instrs = {0xF0},
	},
	BNE = {
		instrs = {0xD0},
	},
	BMI = {
		instrs = {0x30},
	},
	BPL = {
		instrs = {0x10},
	},
	BVC = {
		instrs = {0x50},
	},
	BVS = {
		instrs = {0x70},
	},
	BRA = {
		instrs = {0x80},
	},
	BRL = {
		instrs = {0x82},
	},
	BIT = {
		instrs = {0x89, 0x2C, 0x24, 0x3C, 0x34},
	},
	BRK = {
		instrs = {0x00},
	},
	CLC = {
		instrs = {0x18},
	},
	CLD = {
		instrs = {0xD8},
	},
	CLI = {
		instrs = {0x58},
	},
	CLV = {
		instrs = {0xB8},
	},
	SEC = {
		instrs = {0x38},
	},
	SED = {
		instrs = {0xF8},
	},
	SEI = {
		instrs = {0x78},
	},
	CMP = {
		instrs = {0xC9, 0xCD, 0xCF, 0xC5, 0xD2, 0xC7, 0xDD, 0xDF, 0xD9, 0xD5, 0xC1, 0xD1, 0xD7, 0xC3, 0xD3},
	},
	COP = {
		instrs = {0x02},
	},
	CPX = {
		instrs = {0xE0, 0xEC, 0xE4},
	},
	CPY = {
		instrs = {0xC0, 0xCC, 0xC4},
	},
	DEC = {
		instrs = {0x3A, 0xCE, 0xC6, 0xDE, 0xD6},
	},
	DEX = {
		instrs = {0xCA},
	},
	DEY = {
		instrs = {0x88},
	},
	EOR = {
		instrs = {0x49, 0x4D, 0x4F, 0x45, 0x52, 0x47, 0x5D, 0x5F, 0x59, 0x55, 0x41, 0x51, 0x57, 0x43, 0x53},
	},
	INC = {
		instrs = {0x1A, 0xEE, 0xE6, 0xFE, 0xF6},
	},
	INX = {
		instrs = {0xE8},
	},
	INY = {
		instrs = {0xC8},
	},
	JMP = {
		instrs = {0x4C, 0x6C, 0x7C, 0x5C, 0xDC},
	},
	JSR = {
		instrs = {0x22, 0x20, 0xFC},
	},
	LDA = {
		instrs = {0xA9, 0xAD, 0xAF, 0xA5, 0xB2, 0xA7, 0xBD, 0xBF, 0xB9, 0xB5, 0xA1, 0xB1, 0xB7, 0xA3, 0xB3},
	},
	LDX = {
		instrs = {0xA2, 0xAE, 0xA6, 0xBE, 0xB6},
	},
	LDY = {
		instrs = {0xA0, 0xAC, 0xA4, 0xBC, 0xB4},
	},
	LSR = {
		instrs = {0x4A, 0x4E, 0x46, 0x5E, 0x56},
	},
	MVN = {
		instrs = {0x54},
	},
	MVP = {
		instrs = {0x44},
	},
	NOP = {
		instrs = {0xEA},
	},
	ORA = {
		instrs = {0x09, 0x0D, 0x0F, 0x05, 0x12, 0x07, 0x1D, 0x1F, 0x19, 0x15, 0x01, 0x11, 0x17, 0x03, 0x13},
	},
	PEA = {
		instrs = {0xF4},
	},
	PEI = {
		instrs = {0xD4},
	},
	PER = {
		instrs = {0x62},
	},
	PHA = {
		instrs = {0x48},
	},
	PHP = {
		instrs = {0x08},
	},
	PHX = {
		instrs = {0xDA},
	},
	PHY = {
		instrs = {0x5A},
	},
	PLA = {
		instrs = {0x68},
	},
	PLP = {
		instrs = {0x28},
	},
	PLX = {
		instrs = {0xFA},
	},
	PLY = {
		instrs = {0x7A},
	},
	PHB = {
		instrs = {0x8B},
	},
	PHD = {
		instrs = {0x0B},
	},
	PHK = {
		instrs = {0x4B},
	},
	PLB = {
		instrs = {0xAB},
	},
	PLD = {
		instrs = {0x2B},
	},
	REP = {
		instrs = {0xC2},
	},
	ROL = {
		instrs = {0x2A, 0x2E, 0x26, 0x3E, 0x36},
	},
	ROR = {
		instrs = {0x6A, 0x6E, 0x66, 0x7E, 0x76},
	},
	RTI = {
		instrs = {0x40},
	},
	RTL = {
		instrs = {0x6B},
	},
	RTS = {
		instrs = {0x60},
	},
	SBC = {
		instrs = {0xE9, 0xED, 0xEF, 0xE5, 0xF2, 0xE7, 0xFD, 0xFF, 0xF9, 0xF5, 0xE1, 0xF1, 0xF7, 0xE3, 0xF3},
	},
	SEP = {
		instrs = {0xE2},
	},
	STA = {
		instrs = {0x8D, 0x8F, 0x85, 0x92, 0x87, 0x9D, 0x9F, 0x99, 0x95, 0x81, 0x91, 0x97, 0x83, 0x93},
	},
	STP = {
		instrs = {0xDB},
	},
	STX = {
		instrs = {0x8E, 0x86, 0x96},
	},
	STY = {
		instrs = {0x8C, 0x84, 0x94},
	},
	STZ = {
		instrs = {0x9C, 0x64, 0x9E, 0x74},
	},
	TAX = {
		instrs = {0xAA},
	},
	TAY = {
		instrs = {0xA8},
	},
	TXA = {
		instrs = {0x8A},
	},
	TYA = {
		instrs = {0x98},
	},
	TSX = {
		instrs = {0xBA},
	},
	TXS = {
		instrs = {0x9A},
	},
	TXY = {
		instrs = {0x9B},
	},
	TYX = {
		instrs = {0xBB},
	},
	TCD = {
		instrs = {0x5B},
	},
	TDC = {
		instrs = {0x7B},
	},
	TCS = {
		instrs = {0x1B},
	},
	TSC = {
		instrs = {0x3B},
	},
	TRB = {
		instrs = {0x1C, 0x14},
	},
	TSB = {
		instrs = {0x0C, 0x04},
	},
	WAI = {
		instrs = {0xCB},
	},
	WDM = {
		instrs = {0x42},
	},
	XBA = {
		instrs = {0xEB},
	},
	XCE = {
		instrs = {0xFB},
	},
}

local formatsAndSizesInfo = {
	--[[
	absolute-a:
	address = data_bank:mem[2]:mem[1]
	
	the asm format of "absolute-a" matches the format of "program counter relative", "stack (program counter relative)", and "stack (absolute)"
	--]]
	{
		instrs = {0x0C, 0x0D, 0x0E, 0x1C, 0x20, 0x2C, 0x2D, 0x2E, 0x4C, 0x4D, 0x4E, 0x6D, 0x6E, 0x8C, 0x8D, 0x8E, 0x9C, 0xAC, 0xAD, 0xAE, 0xCC, 0xCD, 0xCE, 0xEC, 0xED, 0xEE},
		address = 'absolute-a',
		eat = function(addr, flag, mem)
			return ("$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, 
	
	--[[
	absolute indexed indirect-(a,x):
	address = (mem[2]:mem[1])+x
	pc = *(uint16_t*)(mem + address)	<- in the first 0xffff bytes
	used with JMP and JSR
	--]]
	{
		instrs = {0x7C, 0xFC},
		address = 'absolute indexed indirect-(a,x)',
		eat = function(addr, flag, mem)
			return ("($%04X,X)"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, 

	--[[
	absolute indexed with X-a,x
	address = data_bank:((mem[2]:mem[1])+x)
	--]]
	{
		instrs = {0x1D, 0x1E, 0x3C, 0x3D, 0x3E, 0x5D, 0x5E, 0x7D, 0x7E, 0x9D, 0x9E, 0xBC, 0xBD, 0xDD, 0xDE, 0xFD, 0xFE},
		address = 'absolute indexed with X-a,x',
		eat = function(addr, flag, mem)
			return ("$%04X,X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, 
	
	--[[
	absolute indexed with Y-a,y
	address = data_bank:((mem[2]:mem[1])+y)
	--]]
	{
		instrs = {0x19, 0x39, 0x59, 0x79, 0x99, 0xB9, 0xBE, 0xD9, 0xF9},
		address = 'absolute indexed with Y-a,y',
		eat = function(addr, flag, mem)
			return ("$%04X,Y"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	},

	--[[
	absolute indirect-(a)
	address = mem[2]:mem[1]
	pc = *(uint16_t*)(mem + address);
	--]]
	{
		instrs = {0x6C},
		address = 'absolute indirect-(a)',
		eat = function(addr, flag, mem)
			return ("($%04X)"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	},

	-- absolute indirect long?
	{
		instrs = {0xDC},
		eat = function(addr, flag, mem)
			return ("[$%04X]"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	}, 

	--[[
	absolute long-al
	--]]
	{
		instrs = {0x0F, 0x22, 0x2F, 0x4F, 0x5C, 0x6F, 0x8F, 0xAF, 0xCF, 0xEF},
		address = 'absolute long-al',
		eat = function(addr, flag, mem)
			return ("$%02X:%04X"):format(mem[3],  bit.bor(mem[1], bit.lshift(mem[2], 8))), 4
		end,
	},

	--[[
	absolute long indexed with x-al,x
	--]]
	{
		instrs = {0x1F, 0x3F, 0x5F, 0x7F, 0x9F, 0xBF, 0xDF, 0xFF},
		address = 'absolute long indexed with x-al,x',
		eat = function(addr, flag, mem)
			return ("$%02X:%04X,X"):format(mem[3], bit.bor(mem[1], bit.lshift(mem[2], 8))), 4
		end,
	}, 

	--[[
	accumulator-a
	--]]
	{
		instrs = {0x0A, 0x1A, 0x2A, 0x3A, 0x4A, 0x6A},
		address = 'accumulator-a',
		eat = function(addr, flag, mem)
			return string.format("A"), 1
		end,
	},

	{
		instrs = {0x44, 0x54},
		eat = function(addr, flag, mem)
			return ("$%02X,$%02X"):format(mem[1],mem[2]), 3
		end,
	}, {
		instrs = {0x04, 0x05, 0x06, 0x14, 0x24, 0x25, 0x26, 0x45, 0x46, 0x64, 0x65, 0x66, 0x84, 0x85, 0x86, 0xA4, 0xA5, 0xA6, 0xC4, 0xC5, 0xC6, 0xE4, 0xE5, 0xE6},
		eat = function(addr, flag, mem)
			return ("$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x15, 0x16, 0x34, 0x35, 0x36, 0x55, 0x56, 0x74, 0x75, 0x76, 0x94, 0x95, 0xB4, 0xB5, 0xD5, 0xD6, 0xF5, 0xF6},
		eat = function(addr, flag, mem)
			return ("$%02X,X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x96, 0xB6},
		eat = function(addr, flag, mem)
			return ("$%02X,Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x12, 0x32, 0x52, 0x72, 0x92, 0xB2, 0xD2, 0xF2},
		eat = function(addr, flag, mem)
			return ("($%02X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x07, 0x27, 0x47, 0x67, 0x87, 0xA7, 0xC7, 0xE7},
		eat = function(addr, flag, mem)
			return ("[$%02X]"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x01, 0x21, 0x41, 0x61, 0x81, 0xA1, 0xC1, 0xE1},
		eat = function(addr, flag, mem)
			return ("($%02X,X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x11, 0x31, 0x51, 0x71, 0x91, 0xB1, 0xD1, 0xF1},
		eat = function(addr, flag, mem)
			return ("($%02X),Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x17, 0x37, 0x57, 0x77, 0x97, 0xB7, 0xD7, 0xF7},
		eat = function(addr, flag, mem)
			return ("[$%02X],Y"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x28, 0x2B, 0x68, 0x7A, 0xAB, 0xFA, 0x08, 0x0B, 0x48, 0x4B, 0x5A, 0x8B, 0xDA, 0x6B, 0x60, 0x40, 0x18, 0x1B, 0x38, 0x3B, 0x58, 0x5B, 0x78, 0x7B, 0x88, 0x8A, 0x98, 0x9A, 0x9B, 0xA8, 0xAA, 0xB8, 0xBA, 0xBB, 0xC8, 0xCA, 0xCB, 0xD8, 0xDB, 0xE8, 0xEA, 0xEB, 0xF8, 0xFB},
		eat = function(addr, flag, mem) return "", 1 end,
	},

	--[[
	program counter relative:
	--]]
	{
		instrs = {0x10, 0x30, 0x50, 0x70, 0x80, 0x90, 0xB0, 0xD0, 0xF0},
		eat = function(addr, flag, mem)
			local sval = (mem[1]>127) and (mem[1]-256) or mem[1]
			return ("$%04X"):format(bit.band(addr+sval+2, 0xFFFF)), 2
		end,
	},
	
	--[[
	stack (program counter relative long):
	--]]
	{
		instrs = {0x62, 0x82},
		eat = function(addr, flag, mem)
			local sval = bit.bor(mem[1], bit.lshift(mem[2], 8))
			sval = (sval>32767) and (sval-65536) or sval
			return ("$%04X"):format(bit.band(addr+sval+3, 0xFFFF)), 3
		end,
	},

	{
		instrs = {0x13, 0x33, 0x53, 0x73, 0x93, 0xB3, 0xD3, 0xF3},
		eat = function(addr, flag, mem)
			return ("($%02X,S),Y"):format(mem[1]), 2
		end,
	},

	--[[
	stack (absolute):
	--]]
	{
		instrs = {0xF4},
		eat = function(addr, flag, mem)
			return ("$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
		end,
	},

	{
		instrs = {0xD4},
		eat = function(addr, flag, mem)
			return ("($%02X)"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x03, 0x23, 0x43, 0x63, 0x83, 0xA3, 0xC3, 0xE3},
		eat = function(addr, flag, mem)
			return ("$%02X,S"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x42, 0x00, 0x02},
		eat = function(addr, flag, mem)
			return ("$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0xC2},
		eat = function(addr, flag, mem)
			flag[0] = bit.band(flag[0], bit.bnot(mem[1]))
			return ("#$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0xE2},
		eat = function(addr, flag, mem)
			flag[0] = bit.bor(flag[0], mem[1])
			return ("#$%02X"):format(mem[1]), 2
		end,
	}, {
		instrs = {0x09, 0x29, 0x49, 0x69, 0x89, 0xA9, 0xC9, 0xE9},
		eat = function(addr, flag, mem)
			if bit.band(flag[0], 0x20) ~= 0 then
				return ("#$%02X"):format(mem[1]), 2
			else
				return ("#$%04X"):format(bit.bor(mem[1], bit.lshift(mem[2], 8))), 3
			end
		end,
	}, {
		instrs = {0xA0, 0xA2, 0xC0, 0xE0},
		eat = function(addr, flag, mem)
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

	eatcstr = function like eat but produces c-like pseudocode
--]]
local instrInfo = {}
for name, instrs in pairs(instrsForNames) do
	for _,instr in ipairs(instrs.instrs) do
		instrInfo[instr] = {name=name}
	end
end
for _,info in ipairs(formatsAndSizesInfo) do
	for _,instr in ipairs(info.instrs) do
		for k,v in pairs(info) do
			instrInfo[instr][k] = v
		end

		-- making this for my c friends who don't like asm
		-- hopefully it's right ... shows how well i remember asm programming
		-- notice 'flag' might become modified, but don't trust its value
		-- you can write 'flag' beforehand but don't read it afterwards.
		instrInfo[instr].eatcstr = function(self, addr, flag, mem)
			local arg = self.eatc 
				and self.eatc(addr, flag, mem)
				or self.eat(addr, flag, mem)
			local readmem
			if arg:match'^#%$' then
				arg = '0x'..arg:match'^#%$(.*)$' 
			elseif arg == 'A' then
				arg = 'accum'
			else
				readmem = true
				-- not everyone needs this
				--arg = 'mem['..arg..']'
			end
			
			if self.address then
				readmem = false
				if self.address == 'absolute-a' then
					--arg = 'mem[addr24(data_bank, x + '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..')]'
					arg = 'data_bank_ptr[x + '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..']'
				elseif self.address == 'absolute indexed indirect-(a,x)' then
					arg = 'mem16(0, x + '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..')'
				elseif self.address == 'absolute indexed with X-a,x' then
					arg = 'mem16(data_bank, x + '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..')'
				elseif self.address == 'absolute indexed with Y-a,y' then
					arg = 'mem16(data_bank, y + '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..')'
				elseif self.address == 'absolute indirect-(a)' then
					arg = 'mem16(0, '..('0x%04X'):format(ffi.cast('uint16_t*',mem+1)[0])..')'
				elseif self.address == 'absolute long indexed with x-al,x' then
					arg = 'mem[addr24('
						..('0x%02X'):format(mem[3])
						..', '
						..('0x%04X'):format(bit.bor(mem[1], bit.lshift(mem[2], 8)))
						..') + x]'
				elseif self.address == 'absolute long-al' then
					arg = 'mem[addr24('
						..('0x%02X'):format(mem[3])
						..', '
						..('0x%04X'):format(bit.bor(mem[1], bit.lshift(mem[2], 8)))
						..')]'			
				elseif self.address == 'accumulator-a' then
					arg = 'accum'
				end
			end

			-- TODO put these cases in 'instrsForNames'
			if self.name == 'ADC' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum += '..arg..' + carry;'
			elseif self.name == 'AND' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum &= '..arg..';'
			elseif self.name == 'ASL' then	-- superfamicom.org doesn't say, but i'm guessing this saves to accum?
				if readmem then arg = 'mem['..arg..']' end
				return 'accum = '..arg..' << 1;'
			elseif self.name == 'BCC' then
				return 'if (!carry) goto '..arg..';'
			elseif self.name == 'BCS' then
				return 'if (carry) goto '..arg..';'
			elseif self.name == 'BEQ' then
				return 'if (zero) goto '..arg..';'
			elseif self.name == 'BIT' then
				if readmem then arg = 'mem['..arg..']' end
				return 'setflags(accum & '..arg..');'
			elseif self.name == 'BMI' then
				return 'if (negative) goto '..arg..';'
			elseif self.name == 'BNE' then
				return 'if (!zero) goto '..arg..';'
			elseif self.name == 'BPL' then
				return 'if (!negative) goto '..arg..';'
			elseif self.name == 'BRA' then
				return 'goto '..arg..';'
			elseif self.name == 'BRK' then	-- "Causes a software break. The PC is loaded from a vector table from somewhere around $FFE6."
				-- TODO
				return 'BRK '..arg
			elseif self.name == 'BRL' then	-- how is this different from BRA?
				return 'goto '..arg..';'
			elseif self.name == 'BVC' then
				return 'if (!overflow) goto '..arg..';'
			elseif self.name == 'BVS' then
				return 'if (overflow) goto '..arg..';'
			elseif self.name == 'CLC' then
				return 'carry = 0;'
			elseif self.name == 'CLD' then
				return 'decimal = 0;'
			elseif self.name == 'CLI' then
				return 'interrupt_disable = 0;'
			elseif self.name == 'CLV' then
				return 'overflow = 0;'
			
			-- "carry is clear when borrow is required; that is, if the register is less than the operand"
			elseif self.name == 'CMP' then
				if readmem then arg = 'mem['..arg..']' end
				return 'setflags(accum - '..arg..');'
			elseif self.name == 'CPX' then
				if readmem then arg = 'mem['..arg..']' end
				return 'setflags(x - '..arg..');'
			elseif self.name == 'CPY' then
				if readmem then arg = 'mem['..arg..']' end
				return 'setflags(y - '..arg..');'
			elseif self.name == 'COP' then	-- "Causes a software interrupt using a vector."
				-- TODO
				return 'coprocessor_enable();'
			elseif self.name == 'DEC' then
				return 'accum--;'
			elseif self.name == 'DEX' then
				return 'x--;'
			elseif self.name == 'DEY' then
				return 'y--;'
			elseif self.name == 'EOR' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum ^= '..arg..';'
			elseif self.name == 'INC' then
				return 'accum++;'
			elseif self.name == 'INX' then
				return 'x++;'
			elseif self.name == 'INY' then
				return 'y++;'
			elseif self.name == 'JMP' then
				-- TODO how about mem here, except that $ means immediate
				-- also TODO what's the dif between BRA, BRL, and JMP ?
				--return 'goto '..arg..';'
				return 'pc = '..arg..';'
			elseif self.name == 'JSR' then
				-- TODO in C syntax?  this would be (arg)()
				--return 'call '..arg
				return '('..arg..')();'
			elseif self.name == 'LDA' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum = '..arg..';'
			elseif self.name == 'LDX' then
				if readmem then arg = 'mem['..arg..']' end
				return 'x = '..arg..';'
			elseif self.name == 'LDY' then
				if readmem then arg = 'mem['..arg..']' end
				return 'y = '..arg..';'
			elseif self.name == 'LSR' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum = '..arg..' >> 1;'
			elseif self.name == 'MVN' then
				return 'memcpy('
					.. 'mem + addr24('..('0x%02X'):format(mem[1])..', x-accum-1), '
					.. 'mem + addr24('..('0x%02X'):format(mem[1])..', y-accum-1), '
					.. 'accum+1'
				..');'
			elseif self.name == 'MVP' then
				return 'memcpy('
					.. 'mem + addr24('..('0x%02X'):format(mem[1])..', x), '
					.. 'mem + addr24('..('0x%02X'):format(mem[1])..', y), '
					.. 'accum+1'
				..');'
			elseif self.name == 'NOP' then
				return ';'
			elseif self.name == 'ORA' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum |= '..arg..';'
			elseif self.name == 'PEA' then
				-- "The instruction is very misleading because you are really pushing an immediate onto the stack. eg."
				return 'push('..arg:gsub('%$', '0x')..');'
			elseif self.name == 'PEI' then
				if readmem then arg = 'mem['..arg..']' end
				return 'push('..arg..')'
			elseif self.name == 'PER' then
				if readmem then arg = 'mem['..arg..']' end
				return 'push(pc + '..arg..');'
			elseif self.name == 'PHA' then
				return 'push(accum);'
			elseif self.name == 'PHB' then
				return 'push(data_bank);'
			elseif self.name == 'PHD' then
				return 'push(direct_page);'
			elseif self.name == 'PHK' then
				return 'push(program_bank);'
			elseif self.name == 'PHP' then
				return 'push(flags);'
			elseif self.name == 'PHX' then
				return 'push(x);'
			elseif self.name == 'PHY' then
				return 'push(y);'
			elseif self.name == 'PLA' then
				return 'accum = pop();'
			elseif self.name == 'PLB' then
				return 'data_bank = pop();'
			elseif self.name == 'PLD' then
				return 'direct_page = pop();'
			elseif self.name == 'PLP' then
				return 'flags = pop();'
			elseif self.name == 'PLX' then
				return 'x = pop();'
			elseif self.name == 'PLY' then
				return 'y = pop();'
			elseif self.name == 'REP' then
				return 'flags &= ~'..('0x%02X'):format(mem[1])..';'
			elseif self.name == 'ROL' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum = ('..arg..' << 1) | carry;'
			elseif self.name == 'ROR' then
				if readmem then arg = 'mem['..arg..']' end
				return 'accum = ('..arg..' >> 1) | (carry << msb);'
			elseif self.name == 'RTI' then
				return 'return from interrupt;'
			elseif self.name == 'RTS' then
				return 'return;'
			elseif self.name == 'RTL' then
				return 'return;'
			elseif self.name == 'SBC' then	-- "subtracts an additional 1 if carry is clear."
				if readmem then arg = 'mem['..arg..']' end
				return 'accum -= '..arg..' + !carry;'
			elseif self.name == 'SEC' then
				return 'carry = 1;'
			elseif self.name == 'SED' then
				return 'decimal = 1;'
			elseif self.name == 'SEI' then
				return 'interrupt_disable = 1;'
			elseif self.name == 'SEP' then
				return 'flags |= '..('0x%02X'):format(mem[1])..';'
			elseif self.name == 'STA' then
				if readmem then arg = 'mem['..arg..']' end
				return arg..' = accum;'
			elseif self.name == 'STX' then
				if readmem then arg = 'mem['..arg..']' end
				return arg..' = x;'
			elseif self.name == 'STY' then
				if readmem then arg = 'mem['..arg..']' end
				return arg..' = y;'
			elseif self.name == 'STP' then
				return 'exit(0);'
			elseif self.name == 'STZ' then
				if readmem then arg = 'mem['..arg..']' end
				return arg..' = 0;'
			elseif self.name == 'TAX' then
				return 'x = accum;'
			elseif self.name == 'TAY' then
				return 'y = accum;'
			elseif self.name == 'TCD' then
				-- TODO
				return 'direct_page = accum;'
			elseif self.name == 'TCS' then
				return 'stack = accum;'
			elseif self.name == 'TDC' then
				-- TODO
				return 'accum = direct_page;'
			elseif self.name == 'TSC' then
				return 'accum = stack;'
			elseif self.name == 'TSX' then
				return 'x = stack;'
			elseif self.name == 'TXA' then
				return 'accum = x;'
			elseif self.name == 'TXS' then
				return 'stack = x;'
			elseif self.name == 'TXY' then
				return 'y = x;'
			elseif self.name == 'TYA' then
				return 'accum = y;'
			elseif self.name == 'TYX' then
				return 'x = y;'
			elseif self.name == 'TRB' then
				-- TODO couldn't be more vague in superfamicom.org
				arg = arg:gsub('%$', '0x')
				return 'setflags(flags & '..arg..'); flags &= ~'..arg..';'
			elseif self.name == 'TSB' then
				return 'setflags(flags & '..arg..'); flags |= '..arg..';'
			elseif self.name == 'WAI'then
				return 'wait_for_hardware_interrupt();'
			elseif self.name == 'WDM' then
				return 'WDM();'	-- "reserved for future expansion"
			elseif self.name == 'XBA'then
				-- notice, b is the upper byte of a , or a is really ((b<<8)|a)
				return 'swap(a,b);'	
				--return 'a = ((a >> 8) & 0xff) | ((a & 0xff) << 8);'
			elseif self.name == 'XCE'then
				return 'exchange carry with emulation;'
			end
			return ''
		end
	end
end



local frompc = require 'pc'.from

local flag = ffi.new('uint8_t[1]', 0)
local pushflag = ffi.new('uint8_t[1]', 0)

-- making all this seamless soon
local tmpmem = ffi.new('uint8_t[4]')

local function getLineStr(addr, flag, ...)
	local code0, code1, code2, code3 = ...
	tmpmem[0] = code0
	tmpmem[1] = code1
	tmpmem[2] = code2
	tmpmem[3] = code3
	local instr = instrInfo[code0]
	pushflag[0] = flag[0]	-- store state for instrcstr
	local instrstr, n = instr.eat(
		addr,	-- TODO ... 0000 vs 8000 here, and BEQ resolving the correct address ...
		flag,	-- or maybe I just shouldn't use 'frompc' next:
		tmpmem
	)

	local instrcstr
	if tryToPrintCEquiv then
		-- trying out c-like pseudocode for kicks
		instrcstr = instr:eatcstr(
			addr,
			pushflag,
			tmpmem
		)
	end

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
	linestr = linestr ..' '..instr.name ..' '..instrstr
	if tryToPrintCEquiv then
		linestr = linestr
			-- if we are also showing n00b c pseudocode
			..(' '):rep(16-#instrstr)
			..instrcstr
	end	
	return linestr, n
end

-- code is lua table, 1-based
local function disasm(addr, ptr, maxlen)
--[[ TODO
	local bank, ofs = frompc(addr)
	local maxlen = 0x10000 - ofs	-- don't read past the page boundary
--]]	
	flag[0] = 0
	local ss = table()
	local i = 0
	while i < maxlen do
		local str, n = getLineStr(
			addr+i,
			flag,
			-- TODO ... how about reading over the end ...
			-- seems like I should always pad the incoming buffer by 3 bytes
			-- until then, i'll pad the next function
			ptr[i],
			i+1 < maxlen and ptr[i+1] or 0x00,
			i+2 < maxlen and ptr[i+2] or 0x00,
			i+3 < maxlen and ptr[i+3] or 0x00
		)
		ss:insert(str)
		i = i + n
	end
	return ss:concat'\n'
end

--[[
reads instructions, stops at RTS, returns contents in a Lua table
(TODO return a uint8_t[] instead?)
(TODO generate the disasm string as you go?)
(TODO follow branches, create a jump/call graph)
--]]
local function readUntilRet(addr, rom)
	local bank, ofs = frompc(addr)
	local maxlen = 0x10000 - ofs	-- don't read past the page boundary
	
	flag[0] = 0
	ptr = rom + addr
	local i = 0
	while i < maxlen do
		local instr = instrInfo[ptr[i]]
		local _, n = instr.eat(
			addr+i,
			flag,
			ptr+i
		)
		i = i + n
		if instr.name == 'RTS' then break end
	end
	return byteArraySubset(rom, addr, i)
end

return {
	disasm = disasm,
	readUntilRet = readUntilRet,
	instrInfo = instrInfo,
	getLineStr = getLineStr,
}
