#!/usr/bin/env luajit
--[[
whereas 'run.lua' is the console randomizer,
this is the OpenGL/imgui visualizer
--]]
local ffi = require 'ffi'
local ig = require 'ffi.imgui'
local class = require 'ext.class'
local file = require 'ext.file'
local SM = require 'sm'

local App = class(require 'glapp.orbit'(require 'imguiapp'))

App.title = 'Super Metroid Viewer'

function App:initGL()
	
	local romstr = file['sm.sfc']	
	local header = ''
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print('skipping rom file header')
		header = romstr:sub(1,512)
		romstr = romstr:sub(513)
	end
	assert(bit.band(#romstr, 0x7fff) == 0, "rom is not bank-aligned")

	-- global so other files can see it
	local rom = ffi.cast('uint8_t*', romstr) 
	local sm = SM(rom)

	App.super.initGL(self)
end

function App:updateGUI()
	ig.igText'here'
end

App():run()
