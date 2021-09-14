local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'
local tolua = require 'ext.tolua'

--[[
alright, I'm just going to make plms as pure lua objects
so I can add optional extra data like scrollmod directly to the plm
expected fields (from plm_t, so just use plm_t:toLua()):
	cmd
	x
	y
	args
	ptr
	scrollmod (optional)

I'm doing this so I can insert new PLMs without needing to assign them an address
--]]
local PLM = class()

function PLM:init(args)
	for k,v in pairs(args) do
		self[k] = v
	end
	assert(self.cmd)
	assert(self.x)
	assert(self.y)
	assert(self.args)
end

function PLM:getName()
	return sm.plmCmdNameForValue[self.cmd]
end

function PLM:toC()
	--return ffi.new('plm_t', self)
	return ffi.new('plm_t', {
		cmd = self.cmd,
		x = self.x,
		y = self.y,
		args = self.args,
	})
end

function PLM.__eq(a,b)
	--return a:toC() == b:toC()
	return a.cmd == b.cmd
		and a.x == b.x
		and a.y == b.y
		and a.args == b.args
end

function PLM.__concat(a,b) 
	return tostring(a) .. tostring(b) 
end

function PLM:__tostring()
	local s = '{'
		..('cmd=%04x'):format(self.cmd)
		..(', x=%02x'):format(self.x)
		..(', y=%02x'):format(self.y)
		..(', args=%04x'):format(self.args)
	if self.scrollmod then
		s = s .. ', scrollmod='.. tolua(self.scrollmod)
	end
	s = s .. '}'
	return s
end

return PLM
