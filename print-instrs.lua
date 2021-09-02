#!/usr/bin/env luajit
local ffi = require 'ffi'
local disasm = require 'disasm'
for i=0,255 do
	local flag = ffi.new('uint8_t[1]', 0)
	local instr = disasm.instrInfo[i]
	local addr = 0x8000
	local code = {0xf0, 0xf1, 0xf2}
	local instrstr, n = instr.eat(code, addr, flag)
	
	local bank = 0x7e
	local instrofs = addr
	local s = ('$%02X:%04X'):format(bank, instrofs)
	for j=0,3 do
		if j < n then
			s = s .. (' %02X'):format(j==0 and i or code[j])
		else
			s = s .. '   '
		end
	end
	s = s ..' '..instr.name..' '..instrstr
	print(s)
end
