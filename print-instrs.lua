#!/usr/bin/env luajit
local ffi = require 'ffi'
local SMCode = require 'sm-code'
local topc = require 'pc'.to
for i=0,255 do
	local flag = ffi.new('uint8_t[1]', 0x30)
	local s = SMCode:codeGetLineStr(
		topc(0x7e, 0x8000),
		flag, 
		i, 0xF0, 0xF1, 0xF2)
	print(s)
end
