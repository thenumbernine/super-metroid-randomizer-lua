#!/usr/bin/env luajit
--[[
whereas 'run.lua' is the console randomizer,
this is the OpenGL/imgui visualizer

TODO replace the rgb conversion with a shader that takes in the indexed 8-bit image and the palette

--]]
local ffi = require 'ffi'
local ig = require 'ffi.imgui'
local gl = require 'gl'
local glreport = require 'gl.report'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local file = require 'ext.file'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'
local SM = require 'sm'

local cmdline = require 'ext.cmdline'(...)

local App = class(require 'glapp.orbit'(require 'imguiapp'))

App.title = 'Super Metroid Viewer'

local blockSizeInPixels = SM.blockSizeInPixels
local graphicsTileSizeInPixels = SM.graphicsTileSizeInPixels 
local roomSizeInPixels = SM.roomSizeInPixels 

-- how do we want to pack our tile textures?
-- this is arbitrary, but pick something squareish so we don't reach the tex dim limit
local tileSetRowWidth = 32

-- global, for gui / table access
editorDrawLayer2 = true
editorDrawForeground = true

do
	local old = SM.mapGetBitmapForTileSetAndTileMap
	function SM:mapGetBitmapForTileSetAndTileMap(...)
		local tileSet, tilemap = ...
		local bgBmp = old(self, ...)
		if not bgBmp.tex then
			local img = Image(graphicsTileSizeInPixels * tilemap.width, graphicsTileSizeInPixels * tilemap.height, 3, 'unsigned char')
			img:clear()
			for y=0,graphicsTileSizeInPixels*tilemap.height-1 do
				for x=0,graphicsTileSizeInPixels*tilemap.width-1 do
					local offset = x + img.width * y
					local paletteIndex = bgBmp.dataBmp[offset]
					if bit.band(paletteIndex, 0xf) > 0 then 
						local rgb = tileSet.palette.data[paletteIndex]
						local dst = img.buffer + 3 * offset
						dst[0] = math.floor(rgb.r*255/31)
						dst[1] = math.floor(rgb.g*255/31)
						dst[2] = math.floor(rgb.b*255/31)
					end
				end
			end
			bgBmp.tex = GLTex2D{
				image = img,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
				wrap = {
					s = gl.GL_REPEAT,
					t = gl.GL_REPEAT,
				},
			}
		end
		return bgBmp
	end
end


function App:initGL()
	App.super.initGL(self)

	local romstr = file[cmdline['in'] or 'sm.sfc']	
	local header = ''
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print('skipping rom file header')
		header = romstr:sub(1,512)
		romstr = romstr:sub(513)
	end
	assert(bit.band(#romstr, 0x7fff) == 0, "rom is not bank-aligned")

	-- global so other files can see it
	self.rom = ffi.cast('uint8_t*', romstr) 
	self.sm = SM(self.rom)

	self.regions = range(0,7):mapi(function(index)
		return {
			rooms = table(),
			index = index,
			show = index==0,
			ofs = vec2f(0,0),
		}
	end)
	for _,m in ipairs(self.sm.rooms) do
		local i = m.obj.region+1
		self.regions[i].rooms:insert(m)
	end

	self.regions[1].ofs:set(0, 0)
	self.regions[2].ofs:set(-3, 19)
	self.regions[3].ofs:set(28, 39)
	self.regions[4].ofs:set(34, -10)
	self.regions[5].ofs:set(25, 19)
	self.regions[6].ofs:set(-3, 1)
	self.regions[7].ofs:set(15, -18)
	self.regions[8].ofs:set(0, 0)

	for _,tileSet in ipairs(self.sm.tileSets) do
		if tileSet.tileGfxBmp then
			local img = Image(
				blockSizeInPixels * tileSetRowWidth,
				blockSizeInPixels * math.ceil(tileSet.tileGfxCount / tileSetRowWidth),
				4,
				'unsigned char')
			for tileIndex=0,tileSet.tileGfxCount-1 do
				local xofs = tileIndex % tileSetRowWidth
				local yofs = math.floor(tileIndex / tileSetRowWidth)
				for i=0,blockSizeInPixels-1 do
					for j=0,blockSizeInPixels-1 do
						local dstIndex = i + blockSizeInPixels * xofs + img.width * (j + blockSizeInPixels * yofs)
						local srcIndex = i + blockSizeInPixels * (j + blockSizeInPixels * tileIndex)
						local paletteIndex = tileSet.tileGfxBmp[srcIndex]
						local src = tileSet.palette.data[paletteIndex]
						img.buffer[0 + 4 * dstIndex] = math.floor(src.r*255/31)
						img.buffer[1 + 4 * dstIndex] = math.floor(src.g*255/31)
						img.buffer[2 + 4 * dstIndex] = math.floor(src.b*255/31)
						img.buffer[3 + 4 * dstIndex] = bit.band(paletteIndex, 0xf) > 0 and 255 or 0 
					end
				end
			end
	
			tileSet.tex = GLTex2D{
				image = img,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
				wrap = {
					s = gl.GL_REPEAT,
					t = gl.GL_REPEAT,
				},
			}
		end
		if tileSet.palette then
			local img = Image(tileSet.palette.count, 1, 4, 'unsigned char', function(paletteIndex)
				local src = tileSet.palette.data[paletteIndex]
				return
					math.floor(src.r*255/31),
					math.floor(src.g*255/31),
					math.floor(src.b*255/31),
					bit.band(paletteIndex, 0xf) > 0 and 255 or 0 
			end)
			tileSet.paletteTex = GLTex2D{
				image = img,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
				wrap = {
					s = gl.GL_REPEAT,
					t = gl.GL_REPEAT,
				},
			}
		end
	end

	-- precache all roomstate bgs
	-- TODO indexed palette renderer so this isn't needed
	for _,m in ipairs(self.sm.rooms) do
		for _,rs in ipairs(m.roomStates) do
			for _,bg in ipairs(rs.bgs) do
				if bg.tilemap then
					self.sm:mapGetBitmapForTileSetAndTileMap(rs.tileSet, bg.tilemap)			
				end
			end
		end
	end
	
	self.view.ortho = true
	self.view.znear = -1e+4
	self.view.zfar = 1e+4
	self.view.orthoSize = 256
	self.view.pos.x = 128
	self.view.pos.y = -128

	
	self.indexShader = GLProgram{
		vertexCode = [[
varying vec2 tc;
void main() {
	tc = gl_MultiTexCoord0.xy;
	gl_Position = ftransform();
}
]],
		fragmentCode = [[
varying vec2 tc;
uniform sampler2D tex;
uniform sampler2D palette;
void main() {
	gl_FragColor = texture2D(tex, tc);
}
]],
		uniforms = {
			tex = 0,
			palette = 1,
		},
	}

	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)
glreport'here'
end

-- 1 gl unit = 1 tile
function App:update()

	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	local blocksPerRoom = SM.blocksPerRoom

	local view = self.view
	local aspectRatio = self.width / self.height
	local viewxmin, viewxmax, viewymin, viewymax = view:getBounds(aspectRatio )
	viewxmin = view.pos.x - view.orthoSize * aspectRatio
	viewxmax = view.pos.x + view.orthoSize * aspectRatio
	viewymin = view.pos.y - view.orthoSize
	viewymax = view.pos.y + view.orthoSize

	GLTex2D:enable()

	for i,region in ipairs(self.regions) do
		local rooms = region.rooms
		local index = i-1
		if region.show then
			for _,m in ipairs(rooms) do
				local w = m.obj.width
				local h = m.obj.height
				
				-- in room block units
				local roomxmin = m.obj.x + region.ofs.x
				local roomymin = m.obj.y + region.ofs.y
				local roomxmax = roomxmin + w
				local roomymax = roomymin + h
				if blocksPerRoom * roomxmax >= viewxmin
				and blocksPerRoom * roomxmin <= viewxmax
				and blocksPerRoom * -roomymax >= viewymin
				and blocksPerRoom * -roomymin <= viewymax
				then
					for _,rs in ipairs(m.roomStates) do
						local tileSet = rs.tileSet
						local roomBlockData = rs.roomBlockData
					
						-- TODO instead of finding the first, hold a current index for each room 
						local _, bg = rs.bgs:find(nil, function(bg) return bg.tilemap end)
						local bgTilemap = bg and bg.tilemap
						local bgBmp = bgTilemap and self.sm:mapGetBitmapForTileSetAndTileMap(tileSet, bgTilemap)
						local bgTex = bgBmp and bgBmp.tex

						if tileSet
						and tileSet.tex
						and roomBlockData 
						then
							if bgTex then
								bgTex:bind()
								gl.glBegin(gl.GL_QUADS)
								for j=0,h-1 do
									for i=0,w-1 do
										if blocksPerRoom * (roomxmin + i + 1) >= viewxmin
										and blocksPerRoom * (roomxmin + i) <= viewxmax
										and blocksPerRoom * -(roomymin + j + 1) >= viewymin
										and blocksPerRoom * -(roomymin + j) <= viewymax
										then
											local x1 = blocksPerRoom * (i + roomxmin)
											local y1 = blocksPerRoom * (j + roomymin)
											local x2 = x1 + blocksPerRoom 
											local y2 = y1 + blocksPerRoom 

											local tx1 = i * roomSizeInPixels / bgTex.width
											local ty1 = j * roomSizeInPixels / bgTex.height
											local tx2 = (i+1) * roomSizeInPixels / bgTex.width
											local ty2 = (j+1) * roomSizeInPixels / bgTex.height

											gl.glTexCoord2f(tx1, ty1)	gl.glVertex2f(x1, -y1)
											gl.glTexCoord2f(tx2, ty1)	gl.glVertex2f(x2, -y1)
											gl.glTexCoord2f(tx2, ty2)	gl.glVertex2f(x2, -y2)
											gl.glTexCoord2f(tx1, ty2)	gl.glVertex2f(x1, -y2)
										end
									end
								end
								gl.glEnd()
								bgTex:unbind()
							end


							local tex = tileSet.tex
							tex:bind()
							gl.glBegin(gl.GL_QUADS)
							
							local blocks12 = roomBlockData:getBlocks12()
							local blocks3 = roomBlockData:getBlocks3()
							local layer2blocks = roomBlockData:getLayer2Blocks()
							for j=0,h-1 do
								for i=0,w-1 do
									if blocksPerRoom * (roomxmin + i + 1) >= viewxmin
									and blocksPerRoom * (roomxmin + i) <= viewxmax
									and blocksPerRoom * -(roomymin + j + 1) >= viewymin
									and blocksPerRoom * -(roomymin + j) <= viewymax
									then
										for ti=0,blocksPerRoom-1 do
											for tj=0,blocksPerRoom-1 do
												-- draw layer2 background if it's there
												if layer2blocks 
												and editorDrawLayer2
												then
													local tileIndex = ffi.cast('uint16_t*', layer2blocks)[ti + blocksPerRoom * i + blocksPerRoom * w * (tj + blocksPerRoom * j)]
													local pimask = bit.band(tileIndex, 0x400) ~= 0
													local pjmask = bit.band(tileIndex, 0x800) ~= 0
													tileIndex = bit.band(tileIndex, 0x3ff)
												
													
													local tx1 = tileIndex % tileSetRowWidth
													local ty1 = math.floor(tileIndex / tileSetRowWidth)

													tx1 = tx1 / tileSetRowWidth
													ty1 = ty1 / (tex.height / blockSizeInPixels)

													local tx2 = tx1 + blockSizeInPixels/tex.width
													local ty2 = ty1 + blockSizeInPixels/tex.height

													if pimask then tx1,tx2 = tx2,tx1 end
													if pjmask then ty1,ty2 = ty2,ty1 end

													local x1 = ti + blocksPerRoom * (i + roomxmin)
													local y1 = tj + blocksPerRoom * (j + roomymin)
													local x2 = x1 + 1
													local y2 = y1 + 1
													
													gl.glTexCoord2f(tx1, ty1)	gl.glVertex2f(x1, -y1)
													gl.glTexCoord2f(tx2, ty1)	gl.glVertex2f(x2, -y1)
													gl.glTexCoord2f(tx2, ty2)	gl.glVertex2f(x2, -y2)
													gl.glTexCoord2f(tx1, ty2)	gl.glVertex2f(x1, -y2)
												end
												
												-- draw tile
												if editorDrawForeground then
													local dx = ti + blocksPerRoom * i
													local dy = tj + blocksPerRoom * j
													local di = dx + blocksPerRoom * w * dy
													
													local d1 = blocks12[0 + 2 * di]
													local d2 = blocks12[1 + 2 * di]
													local d3 = blocks3[di]
														
													local tileIndex = bit.bor(d1, bit.lshift(bit.band(d2, 0x03), 8))
													local pimask = bit.band(d2, 4) ~= 0
													local pjmask = bit.band(d2, 8) ~= 0


													local tx1 = tileIndex % tileSetRowWidth
													local ty1 = math.floor(tileIndex / tileSetRowWidth)

													tx1 = tx1 / tileSetRowWidth
													ty1 = ty1 / (tex.height / blockSizeInPixels)

													local tx2 = tx1 + blockSizeInPixels/tex.width
													local ty2 = ty1 + blockSizeInPixels/tex.height

													if pimask then tx1,tx2 = tx2,tx1 end
													if pjmask then ty1,ty2 = ty2,ty1 end

													local x = ti + blocksPerRoom * (i + roomxmin)
													local y = tj + blocksPerRoom * (j + roomymin)
													
													gl.glTexCoord2f(tx1, ty1)	gl.glVertex2f(x, -y)
													gl.glTexCoord2f(tx2, ty1)	gl.glVertex2f(x+1, -y)
													gl.glTexCoord2f(tx2, ty2)	gl.glVertex2f(x+1, -y-1)
													gl.glTexCoord2f(tx1, ty2)	gl.glVertex2f(x, -y-1)
												end
											end
										end
									end
								end
							end
							gl.glEnd()
							tex:unbind()
						end
					end
				end
			end
		end
	end

	GLTex2D:disable()

	App.super.update(self)
end

local bool = ffi.new('bool[1]')
local function checkboxTooltip(name, t, k)
	ig.igPushIDStr(name)
	bool[0] = not not t[k]
	local result = ig.igCheckbox('', bool)
	if result then
		t[k] = bool[0]
	end
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igBeginTooltip()
		ig.igText(name)
		ig.igEndTooltip()
	end
	ig.igPopID()
	return result
end

local float = ffi.new('float[1]')
local function inputFloatToolkit(name, t, k)
	ig.igPushIDStr(name)
	float[0] = tonumber(t[k]) or 0
	local result = ig.igInputFloat('', float)
	if result then
		t[k] = float[0]
	end
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igBeginTooltip()
		ig.igText(name)
		ig.igEndTooltip()
	end
	ig.igPopID()
	return result
end

function App:updateGUI()
	checkboxTooltip('Draw Foreground', _G, 'editorDrawForeground')
	ig.igSameLine()
	checkboxTooltip('Draw Layer 2 Background', _G, 'editorDrawLayer2')

	ig.igPushIDStr'regions'
	for i,region in ipairs(self.regions) do
		if ig.igCollapsingHeader('region '..region.index) then
			ig.igPushIDInt(i)
			checkboxTooltip('Show Region '..region.index, region, 'show')
			if i < #self.regions then
				inputFloatToolkit('xofs', region.ofs, 'x')
				inputFloatToolkit('yofs', region.ofs, 'y')
				ig.igSeparator()
			end
			ig.igPopID()
		end
	end
	ig.igPopID()
	
	ig.igSeparator()

	ig.igPushIDStr'tilesets'
	for i,tileSet in ipairs(self.sm.tileSets) do
		ig.igPushIDInt(i)
		ig.igCheckbox('', bool)
		bool[0] = false
		if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
			ig.igBeginTooltip()
			ig.igText('tileset '..tileSet.index)
			local tex = tileSet.tex
			if tex then
				local texIDPtr = ffi.cast('void*',ffi.cast('intptr_t',tex.id))
				ig.igImage(
					texIDPtr,
					ig.ImVec2(tex.width, tex.height),
					ig.ImVec2(0, -1),
					ig.ImVec2(1, 0)
				)
			end
			ig.igEndTooltip()
		end
		ig.igPopID()
		if tileSet.index % 8 < 7 then
			ig.igSameLine()
		end
	end
	ig.igPopID()
end

App():run()
