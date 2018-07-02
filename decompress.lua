-- http://www.romhacking.net/documents/243/
-- http://pikensoft.com/docs/Zelda_LTTP_compression_(Piken).txt

local ffi = require 'ffi'

local function hexdump(ptr,len)
	return ffi.string(ptr,len):gsub('.', function(c) return (' %02x'):format(c:byte()) end)
end

local function decompress(addr, maxlen)
--local function dprint(s) print('  '..s) end
--dprint'decompressing:'	
	local startaddr = addr
	local bank = bit.band(0xff0000, addr)
	local buffer = table()

	local function readbyte()
		assert(addr >= 0 and addr < #romstr)
		local v = rom[addr]
		addr = addr + 1
		return v
	end

	local function lzdecompress(len, bytes, mask, absolute)
		assert(bytes == 1 or bytes == 2)
		assert(mask == 0 or mask == 0xff)
		local from = readbyte()
		if bytes == 2 then
			from = bit.bor(from, bit.lshift(readbyte(), 8))
		end
		if not absolute then
			from = #buffer - from
		end
		if from >= 0 and from < #buffer then
			for i=0,len-1 do
				local ofsi = from+i+1
				assert(ofsi >= 1 and ofsi <= #buffer)
				buffer:insert(
					bit.bxor(buffer[ofsi], mask)
				)
			end
		else
			error'here'
		end
	end

	while true do
		assert(addr < startaddr + maxlen, "compressed data exceeded boundary")
--dprint('next 5 bytes: '..hexdump(rom+addr,5))	
		local c = readbyte()
		if c == 0xff then break end
		local cmd = bit.band(bit.rshift(c, 5), 7)
		local len = bit.band(c, 0x1f)
		if bit.band(c, 0xe0) == 0xe0 then	-- 1110:0000
			-- extended cmd
			local v = readbyte()
--dprint('extended cmd '..cmd..' '..len..' next byte '..('0x%02x'):format(v))
			cmd = bit.band(bit.rshift(c, 2), 7)
			len = bit.bor(v, bit.lshift(bit.band(len, 0x3), 8))
--dprint(' cmd='..cmd..' len='..len)
--dprint(' cmd='..cmd..' len='..len)
		end
		len=len+1
		if cmd == 0 then	-- 000b: direct copy
--dprint('direct copy '..len..' bytes: '..hexdump(rom+addr, len))
			for i=0,len-1 do
				buffer:insert(readbyte())
			end
		elseif cmd == 1 then	-- 001b: byte fill
--dprint('byte fill '..len..' bytes: '..hexdump(rom+addr,1))
			local v = readbyte()
			for i=0,len-1 do
				buffer:insert(v)
			end
		elseif cmd == 2 then	-- 010b: word fill
--dprint('word fill '..len..' bytes: '..hexdump(rom+addr,2))
			local v1 = readbyte()
			local v2 = readbyte()
			for i=0,len-1 do
				buffer:insert(bit.band(i,1)==0 and v1 or v2)
			end
		elseif cmd == 3 then	-- 011b: incremental fill
--dprint('incremental fill '..len..' bytes: '..hexdump(rom+addr,1))
			local v = readbyte()
			for i=0,len-1 do
				buffer:insert(v)
				v = ffi.cast('uint8_t', v+1)
			end
		elseif cmd == 4 then	-- 100b: 
			lzdecompress(len, 2, 0, true)
		elseif cmd == 5 then	-- 101b: 
			lzdecompress(len, 2, 0xff, true)
		elseif cmd == 6 then	-- 110b: 
			lzdecompress(len, 1, 0, false)
		elseif cmd == 7 then	-- 111b: 
			lzdecompress(len, 1, 0xff, false)
		end
	end

--dprint('compressed data length: '..(addr-startaddr))
	return buffer
end

--[[
03 = 000:00011 = copy the next 3 bytes
--]]
--[[
local function string(t)
	for i=1,#t do
		rom[i-1] = t[i]
	end
	return 0, #t+1
end
print(decompress(string{0x03, 0x12, 0x34, 0x56}):map(function(x) return (' %02x'):format(x) end):concat', ')
os.exit()
--]]

return decompress
