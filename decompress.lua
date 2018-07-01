-- http://www.romhacking.net/documents/243/
-- http://pikensoft.com/docs/Zelda_LTTP_compression_(Piken).txt

local ffi = require 'ffi'

ffi.cdef[[
typedef union {
	uint8_t v;
	struct {
		uint8_t len : 5;
		uint8_t cmd : 3;
	};
} compressCmd_t;
]]

assert(ffi.sizeof'compressCmd_t' == 1)

local function hexdump(ptr,len)
	return ffi.string(ptr,len):gsub('.', function(c) return (' %02x'):format(c:byte()) end)
end

local function decompress(addr, maxlen)
--local function dprint(s) print('  '..s) end
local function dprint() end
dprint'decompressing:'	
	local startaddr = addr
	local bank = bit.band(0xff0000, addr)
	local buffer = table()
	
	local function exec(cmd, len, recurse)
		if cmd == 0 then	-- 000b: direct copy
dprint('direct copy '..(len+1)..' bytes: '..hexdump(rom+addr, len+1))
			for i=0,len do	-- len+1 bytes are copied
				buffer:insert(rom[addr]) addr=addr+1
			end
		elseif cmd == 1 then	-- 001b: byte fill
dprint('byte fill '..(len+1)..' bytes: '..hexdump(rom+addr,1))
			local v = rom[addr] addr=addr+1
			for i=0,len do
				buffer:insert(v)
			end
		elseif cmd == 2 then	-- 010b: word fill
dprint('word fill '..(len+1)..' bytes: '..hexdump(rom+addr,2))
			local v1 = rom[addr] addr=addr+1
			local v2 = rom[addr] addr=addr+1
			for i=0,len do
				buffer:insert(v1)
				buffer:insert(v2)
			end
		elseif cmd == 3 then	-- 011b: incremental fill
dprint('incremental fill '..(len+1)..' bytes: '..hexdump(rom+addr,1))
			local v = rom[addr] addr=addr+1
			for i=0,len do
				buffer:insert(v)
				v = ffi.cast('uint8_t', v+1)
			end
		elseif cmd == 4 then	-- 100b: external copy 
dprint('external copy '..(len+1)..' bytes: addr='..hexdump(rom+addr,2))
			local srcaddr = bank + ffi.cast('uint16_t*', rom+addr)[0] addr=addr+2
dprint(' data: '..hexdump(rom+srcaddr, len+1))
			for i=0,len do
				buffer:insert( rom[srcaddr] ) srcaddr=srcaddr+1
			end
		elseif cmd == 5 then	-- 101b: xor fill
dprint('xor fill '..(len+1)..' bytes: '..hexdump(rom+addr,2))
			local srcaddr = bank + ffi.cast('uint16_t*', rom+addr)[0] addr=addr+2
dprint(' data: '..hexdump(rom+srcaddr, len+1))
			for i=0,len do
				buffer:insert( bit.bxor(rom[srcaddr], 0xff) ) srcaddr=srcaddr+1
			end
		elseif cmd == 6 then	-- 110b: previous copy
dprint('previous copy '..(len+1)..' bytes: offset='..hexdump(rom+addr,1))
			local v = rom[addr] addr=addr+1
			for i=0,len do
				buffer:insert(buffer[#buffer-1-v]) addr=addr+1
			end
		elseif cmd == 7 then	-- 111b: extended command or terminator
			if rom[addr-1]  == 0xff then -- terminator
dprint('done!')
				return true
			end
			-- extended cmd
			local v = rom[addr] addr=addr+1
dprint('extended cmd '..cmd..' '..len..' next byte '..('0x%02x'):format(v))
			local newcmd = bit.rshift(len, 2)
			local newlen = bit.bor(v, bit.lshift(bit.band(len, 0x3), 8))
dprint(' newcmd='..newcmd..' newlen='..newlen)
assert(not recurse, "I found two ecmds in a row")
			return exec(newcmd, newlen, true)
		end
	end

	local done
	repeat 
dprint('next 5 bytes: '..hexdump(rom+addr,5))	
		local c = ffi.cast('compressCmd_t*', rom + addr) addr=addr+1
		local cmd = c[0].cmd
		local len = c[0].len
		done = exec(cmd, len)
		assert(addr < startaddr + maxlen, "compressed data exceeded boundary")
	until done
dprint('compressed data size: '..(addr-startaddr))
	return buffer
end

return decompress
