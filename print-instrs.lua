#!/usr/bin/env luajit
local ffi = require 'ffi'
local table = require 'ext.table'
local SMCode = require 'super_metroid_randomizer.sm-code'
SMCode.tryToPrintCEquiv = true
local topc = require 'super_metroid_randomizer.pc'.to
for i=0,255 do
	local tmpmem = ffi.new('uint8_t[4]', i, 0xF0, 0xF1, 0xF2)
	local instr = SMCode.instrClasses[i]{addr=topc(0x7e, 0x8000), ptr=tmpmem}
	
	local flag = ffi.new('uint8_t[1]', 0x00)
	local flagstack = table()
	
	local s = instr:getLineStr(flag, flagstack)
	print(s)
end
