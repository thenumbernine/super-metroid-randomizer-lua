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

-- TODO replace this with shaders
local useBakedLayer3Background = true


--local cmdline = require 'ext.cmdline'(...)
local infilename = ... or 'sm.sfc'

local App = class(require 'glapp.orbit'(require 'imguiapp'))

App.title = 'Super Metroid Viewer'


local blockSizeInPixels = SM.blockSizeInPixels
local blocksPerRoom = SM.blocksPerRoom
local graphicsTileSizeInPixels = SM.graphicsTileSizeInPixels 
local graphicsTileSizeInBytes = SM.graphicsTileSizeInBytes 
local roomSizeInPixels = SM.roomSizeInPixels 

-- how do we want to pack our tile textures?
-- this is arbitrary, but pick something squareish so we don't reach the tex dim limit
local tileSetRowWidth = 32

-- global, for gui / table access
editorDrawForeground = true
editorDrawLayer2 = true
editorDrawPLMs = true
editorDrawEnemySpawnSets = true
editorDrawDoors = true

-- [==[ can't get rid of this yet until I store the tilemaps separately as well
-- but turns out baking the palette was the biggest slowdown
do
	local old = SM.mapGetBitmapForTileSetAndTileMap
	function SM:mapGetBitmapForTileSetAndTileMap(...)
		local tileSet, tilemap = ...
		local bgBmp = old(self, ...)
		if not bgBmp.tex then
			bgBmp.tex = GLTex2D{
				width = graphicsTileSizeInPixels * tilemap.width,
				height = graphicsTileSizeInPixels * tilemap.height,
				data = bgBmp.dataBmp,
				format = gl.GL_RED,
				internalFormat = gl.GL_RED,
				type = gl.GL_UNSIGNED_BYTE,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
			}
		end
		return bgBmp
	end
end
--]==]


function App:initGL()
	App.super.initGL(self)

	local romstr = file[infilename]
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
			show = true,--index==0,
			ofs = vec2f(0,0),
			xmin = math.huge,
			xmax = -math.huge,
			ymin = math.huge,
			ymax = -math.huge,
		}
	end)
	for _,m in ipairs(self.sm.rooms) do
		local index = m.obj.region+1
		local region = self.regions[index]
		region.rooms:insert(m)
		region.xmin = math.min(region.xmin, m.obj.x)
		region.ymin = math.min(region.ymin, m.obj.y)
		region.xmax = math.min(region.xmax, m.obj.x + m.obj.width)
		region.ymax = math.min(region.ymax, m.obj.y + m.obj.height)
	end

	self:setRegionOffsets(1)

	self.roomCurrentRoomStates = {}


	-- graphics init


	-- half tempted to write a shader that reads the bits as is ....
	for _,palette in ipairs(self.sm.tileSetPalettes) do
		local img = Image(256, 1, 4, 'unsigned char')
		img:clear()
		for paletteIndex=0,math.min(palette.count,256)-1 do
			local src = palette.data[paletteIndex]
			img.buffer[0 + 4 * paletteIndex] = math.floor(src.r*255/31)
			img.buffer[1 + 4 * paletteIndex] = math.floor(src.g*255/31)
			img.buffer[2 + 4 * paletteIndex] = math.floor(src.b*255/31)
			img.buffer[3 + 4 * paletteIndex] = bit.band(paletteIndex, 0xf) > 0 and 255 or 0
		end
		palette.tex = GLTex2D{
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
	
	for _,tileSet in ipairs(self.sm.tileSets) do
		--[[
		make a texture out of the tileSet graphicsTiles ... 
		graphicsTileSizeInPixels * graphicsTileSizeInPixels packed into a higher size
		higher size is (graphicsTileSizeInPixels * tilemapElemSizeX) * (whatever's left)
		--]]
		local numGraphicTiles = tileSet.graphicsTileVec.size / graphicsTileSizeInBytes
		local tilemapElemSizeX = 16
		local tilemapElemSizeY = math.floor(numGraphicTiles / tilemapElemSizeX)
		assert(tilemapElemSizeX * tilemapElemSizeY == numGraphicTiles)
		local tilemap = ffi.new('tilemapElem_t[?]', tilemapElemSizeX * tilemapElemSizeY)
		for i=0,numGraphicTiles-1 do
			tilemap[i].graphicsTileIndex = i
			tilemap[i].colorIndexHi = 0
			tilemap[i].xflip = 0
			tilemap[i].yflip = 0
		end
		local imgwidth = graphicsTileSizeInPixels * tilemapElemSizeX
		local imgheight = graphicsTileSizeInPixels * tilemapElemSizeY
		local img = Image(imgwidth, imgheight, 1, 'unsigned char')
		self.sm:convertTilemapToBitmap(
			img.buffer,						-- dst uint8_t[graphicsTileSizeInPixels][numGraphicTiles * graphicsTileSizeInPixels]
			tilemap,						-- tilemap = tilemapElem_t[numGraphicTiles * graphicsTileSizeInPixels]
			tileSet.graphicsTileVec.v,		-- graphicsTiles = 
			tilemapElemSizeX,				-- tilemapElemSizeX
			tilemapElemSizeY,				-- tilemapElemSizeY
			1)								-- count
		
		-- alright now that we have this, we can store the tilemap as a uint16 per graphicstile
		-- instead of as a rendered bitmap
		tileSet.graphicsTileTex = GLTex2D{
			width = img.width,
			height = img.height,
			data = img.buffer,
			format = gl.GL_RED,
			internalFormat = gl.GL_RED,
			type = gl.GL_UNSIGNED_BYTE,
			magFilter = gl.GL_NEAREST,
			minFilter = gl.GL_NEAREST,
			generateMipmap = false,
		}

		-- make a texture out of the tileSet tilemap ... 1 uint16 per 8x8 tile


		-- tileGfxBmp is from combining the common room data and the tileset data
		if tileSet.tileGfxBmp then
			local img = Image(
				blockSizeInPixels * tileSetRowWidth,
				blockSizeInPixels * math.ceil(tileSet.tileGfxCount / tileSetRowWidth),
				1,
				'unsigned char')
			for tileIndex=0,tileSet.tileGfxCount-1 do
				local xofs = tileIndex % tileSetRowWidth
				local yofs = math.floor(tileIndex / tileSetRowWidth)
				for i=0,blockSizeInPixels-1 do
					for j=0,blockSizeInPixels-1 do
						local srcIndex = i + blockSizeInPixels * (j + blockSizeInPixels * tileIndex)
						local paletteIndex = tileSet.tileGfxBmp[srcIndex]
						local dstIndex = i + blockSizeInPixels * xofs + img.width * (j + blockSizeInPixels * yofs)
						img.buffer[dstIndex] = paletteIndex
					end
				end
			end
			tileSet.tex = GLTex2D{
				width = img.width,
				height = img.height,
				data = img.buffer,
				format = gl.GL_RED,
				internalFormat = gl.GL_RED,
				type = gl.GL_UNSIGNED_BYTE,
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

	for _,tilemap in ipairs(self.sm.bgTilemaps) do
		if not tilemap.tex then
			local img = Image(tilemap.width, tilemap.height, 1, 'unsigned short')
			ffi.copy(img.buffer, tilemap.data, tilemap:sizeof())
			tilemap.tex = GLTex2D{
				width = img.width,
				height = img.height,
				data = img.buffer,
				format = gl.GL_RED,
				internalFormat = gl.GL_R16,
				type = gl.GL_UNSIGNED_SHORT,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
			}
		end
	end

	if useBakedLayer3Background then
-- [==[
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
--]==]
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
	float index = texture2D(tex, tc).r * 255.;
	gl_FragColor = texture2D(palette, vec2((index + .5)/256., .5));
}
]],
		uniforms = {
			tex = 0,
			palette = 1,
		},
	}
	self.indexShader:useNone()

--[==[
	self.tilemapShader = GLProgram{
		vertexCode = [[
#version 300

varying vec2 tc;
void main() {
	tc = gl_MultiTexCoord0.xy;
	gl_Position = ftransform();
}
]],
		fragmentCode = [[
#version 300

varying vec2 tc;
uniform usampler2D tilemap;
uniform usampler2D graphicsTiles;
uniform usampler2D palette;
void main() {
	//TODO lookup uint16 plz
	uint tileIndex = texture(tilemap, tc).r;
	bool pimask = (value & 0x400) == 0x400;
	bool pjmask = (value & 0x800) == 0x800;
	tileIndex &= 0x3ff;

	//1) determine which subtile 8x8 graphics tile we are in
	
	//2) 
}
]],
		uniforms = {
			tilemap = 0,
			graphicsTiles = 1,
			palette = 2,
		},
	}
	self.tilemapShader:useNone()
--]==]

	gl.glEnable(gl.GL_BLEND)
	gl.glBlendFunc(gl.GL_SRC_ALPHA, gl.GL_ONE_MINUS_SRC_ALPHA)
glreport'here'

	self.mouseViewPos = vec2f()
end

local predefinedRegionOffsets = {
-- default arrangement.  too bad crateria right of wrecked ship isn't further right to fit wrecked ship in
	{
		name = 'Original',
		ofs = {
			{0, 0},
			{-3, 19},
			{28, 39},
			{34, -10},
			{25, 19},
			{-3, 1},
			{15, -18},
			{0, 0},
		},
	},
	{
		name = 'Vitality',
		ofs = {
			{21, 43},
			{15, 23},
			{57, 12},
			{16, -1},
			{-27, 28},
			{40, 59},
			{0, 0},
			{0, 0},
		},
	},
	{
		name = 'Golden Dawn',
		ofs = {
			{0, 0},
			{-54, -3},
			{4, 9},
			{-48, -38},
			{-33, -16},
			{-11, -32},
			{15, -18},
			{-4, -32},
		},
	},
	{
		name = 'Metroid Super Zero Mission',
		ofs = {
			{0,0},
			{-1,23},
			{27,33},
			{33,-15},
			{47,14},
			{-15,13},
			{0,0},
			{0,0},
		},
	},
}

function App:setRegionOffsets(index)
	local predef = predefinedRegionOffsets[index]
	for i,ofs in ipairs(predef.ofs) do
		self.regions[i].ofs:set(ofs[1], ofs[2])
	end
end

-- 1 gl unit = 1 tile
function App:update()

	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	local view = self.view
	local aspectRatio = self.width / self.height
	local viewxmin, viewxmax, viewymin, viewymax = view:getBounds(aspectRatio )
	viewxmin = view.pos.x - view.orthoSize * aspectRatio
	viewxmax = view.pos.x + view.orthoSize * aspectRatio
	viewymin = view.pos.y - view.orthoSize
	viewymax = view.pos.y + view.orthoSize


	for i,region in ipairs(self.regions) do
		local rooms = region.rooms
		local index = i-1
		if region.show 
		and (
			blocksPerRoom * region.xmax >= viewxmin
			or blocksPerRoom * region.xmin <= viewxmax
			or blocksPerRoom * -region.ymax >= viewymin
			or blocksPerRoom * -region.ymin <= viewymax
		)
		then
			for _,m in ipairs(rooms) do
				local w = m.obj.width
				local h = m.obj.height
				
				-- in room block units
				local roomxmin = m.obj.x + region.ofs.x
				local roomymin = m.obj.y + region.ofs.y
				local roomxmax = roomxmin + w
				local roomymax = roomymin + h
				if blocksPerRoom * roomxmax >= viewxmin
				or blocksPerRoom * roomxmin <= viewxmax
				or blocksPerRoom * -roomymax >= viewymin
				or blocksPerRoom * -roomymin <= viewymax
				then
					local roomIndex = bit.bor(bit.lshift(m.obj.region, 8), m.obj.index)
					local currentRoomStateIndex = self.roomCurrentRoomStates[roomIndex] or 1
					local rs = m.roomStates[
						(currentRoomStateIndex % #m.roomStates) + 1
					]
						
					local tileSet = rs.tileSet
					local roomBlockData = rs.roomBlockData
				
					-- TODO instead of finding the first, hold a current index for each room 
					local _, bg = rs.bgs:find(nil, function(bg) return bg.tilemap end)
					local bgTilemap = bg and bg.tilemap
					local bgTilemapTex = bgTilemap and bgTilemap.tex

					if tileSet
					and tileSet.tex
					and tileSet.palette
					and roomBlockData 
					then
if useBakedLayer3Background then
						local bgBmp = bgTilemap and self.sm:mapGetBitmapForTileSetAndTileMap(tileSet, bgTilemap)
						local bgTex = bgBmp and bgBmp.tex
						if bgTex then
	
							self.indexShader:use()
							
							bgTex:bind(0)
							tileSet.palette.tex:bind(1)
							
							gl.glBegin(gl.GL_QUADS)
							for j=0,h-1 do
								for i=0,w-1 do
									if blocksPerRoom * (roomxmin + i + 1) >= viewxmin
									or blocksPerRoom * (roomxmin + i) <= viewxmax
									or blocksPerRoom * -(roomymin + j + 1) >= viewymin
									or blocksPerRoom * -(roomymin + j) <= viewymax
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
							
							tileSet.palette.tex:unbind(1)
							bgTex:unbind(0)
							
							self.indexShader:useNone()
					
						end
end
--[==[
						if bgTilemapTex then
							self.tilemapShader:use()
							
							bgTilemapTex:bind(0)
							tileSet.graphicsTileTex:bind(1)
							tileSet.palette.tex:bind(2)
							
							gl.glBegin(gl.GL_QUADS)
							for j=0,h-1 do
								for i=0,w-1 do
									if blocksPerRoom * (roomxmin + i + 1) >= viewxmin
									or blocksPerRoom * (roomxmin + i) <= viewxmax
									or blocksPerRoom * -(roomymin + j + 1) >= viewymin
									or blocksPerRoom * -(roomymin + j) <= viewymax
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
							
							tileSet.palette.tex:unbind(2)
							tileSet.graphicsTileTex:unbind(1)
							bgTilemapTex:unbind(0)
							
							self.tilemapShader:useNone()
						end
--]==]

						self.indexShader:use()

						local tex = tileSet.tex
						local paletteTex = tileSet.palette.tex
						tex:bind(0)
						paletteTex:bind(1)
						gl.glBegin(gl.GL_QUADS)
						
						local blocks12 = roomBlockData:getBlocks12()
						local blocks3 = roomBlockData:getBlocks3()
						local layer2blocks = roomBlockData:getLayer2Blocks()
						for j=0,h-1 do
							for i=0,w-1 do
								if blocksPerRoom * (roomxmin + i + 1) >= viewxmin
								or blocksPerRoom * (roomxmin + i) <= viewxmax
								or blocksPerRoom * -(roomymin + j + 1) >= viewymin
								or blocksPerRoom * -(roomymin + j) <= viewymax
								then
									for ti=0,blocksPerRoom-1 do
										for tj=0,blocksPerRoom-1 do
											-- draw layer2 background if it's there
											if editorDrawLayer2
											and layer2blocks 
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
											if editorDrawForeground 
											and blocks12
											and blocks3
											then
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
						paletteTex:unbind(1)
						tex:unbind(0)

						self.indexShader:useNone()
					
						-- draw roomstate plms here
						if editorDrawPLMs
						and rs.plmset 
						then
							gl.glColor3f(0,1,1)
							for _,plm in ipairs(rs.plmset.plms) do
								local x = plm.x + blocksPerRoom * roomxmin
								local y = -(plm.y + blocksPerRoom * roomymin)
								gl.glBegin(gl.GL_LINES)
								gl.glVertex2f(x-.5, y)
								gl.glVertex2f(x+.5, y)
								gl.glVertex2f(x, y-.5)
								gl.glVertex2f(x, y+.5)
								gl.glEnd()
							end
						end
						
						if editorDrawEnemySpawnSets 
						and rs.enemySpawnSet 
						then
							gl.glColor3f(1,0,1)
							for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
								local x = enemySpawn.x / 16 + blocksPerRoom * roomxmin
								local y = -(enemySpawn.y / 16 + blocksPerRoom * roomymin)
								gl.glBegin(gl.GL_LINES)
								gl.glVertex2f(x-.5, y)
								gl.glVertex2f(x+.5, y)
								gl.glVertex2f(x, y-.5)
								gl.glVertex2f(x, y+.5)
								gl.glEnd()
							end
						end
					
						-- doors
						-- segfaulting in vitality
						if editorDrawDoors
						and roomBlockData 
						then
							for exitIndex,blockpos in pairs(roomBlockData.blocksForExit) do
								-- TODO lifts will mess up the order of this, maybe?
								local door = m.doors[exitIndex+1]
								if not door then
								elseif door.type ~= 'door_t' then
									-- TODO handle lifts?
								else
									local dstRoom = assert(door.destRoom)
								
									-- draw an arrow or something on the map where the door drops us off at
									-- door.destRoom is the room
									-- draw it at door.obj.screenX by door.obj.screenY
									-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

									local i = door.obj.screenX
									local j = door.obj.screenY
									local dir = bit.band(door.obj.direction, 3)	-- 0-based
									local ti, tj = 0, 0	--table.unpack(doorPosForDir[dir])
										
									local k = 2
										
									local pi, pj = 0, 0
									if dir == 0 then		-- enter from left
										pi = k
										pj = bit.rshift(blocksPerRoom, 1)
									elseif dir == 1 then	-- enter from right
										pi = blocksPerRoom - k
										pj = bit.rshift(blocksPerRoom, 1)
									elseif dir == 2 then	-- enter from top
										pi = bit.rshift(blocksPerRoom, 1)
										pj = k
									elseif dir == 3 then	-- enter from bottom
										pi = bit.rshift(blocksPerRoom, 1)
										pj = blocksPerRoom - k
									end
								
									-- here's the pixel x & y of the door destination
									local dstregion = self.regions[dstRoom.obj.region+1]
									local x1 = pi + ti + blocksPerRoom * (i + dstRoom.obj.x + dstregion.ofs.x)
									local y1 = pj + tj + blocksPerRoom * (j + dstRoom.obj.y + dstregion.ofs.y)

									for _,pos in ipairs(blockpos) do
										-- now for src block pos
										local x2 = .5 + pos[1] + blocksPerRoom * roomxmin
										local y2 = .5 + pos[2] + blocksPerRoom * roomymin
										gl.glColor3f(1,1,1)
										gl.glBegin(gl.GL_LINES)
										gl.glVertex2f(x1,-y1)
										gl.glVertex2f(x2,-y2)
										gl.glEnd()
									end
								end
							end
						end
					end
				end
			end
		end
	end

	App.super.update(self)
end

function App:event(...)
	local viewBeforeSize = self.view.orthoSize
	local viewBeforeX = self.view.pos.x
	local viewBeforeY = self.view.pos.y

	App.super.event(self, ...)


	local view = self.view
	local aspectRatio = self.width / self.height
	local viewxmin, viewxmax, viewymin, viewymax = view:getBounds(aspectRatio )
	viewxmin = view.pos.x - view.orthoSize * aspectRatio
	viewxmax = view.pos.x + view.orthoSize * aspectRatio
	viewymin = view.pos.y - view.orthoSize
	viewymax = view.pos.y + view.orthoSize

	self.mouseViewPos:set(
		(1 - self.mouse.pos.x) * viewxmin + self.mouse.pos.x * viewxmax,
		(1 - self.mouse.pos.y) * viewymin + self.mouse.pos.y * viewymax
	)
	
	if self.mouse.leftDown then
		if not self.mouse.lastLeftDown then
print('self.mouseViewPos', self.mouseViewPos)			
			self.mouseDownOnRegion = nil
			for _,region in ipairs(self.regions) do
				for _,m in ipairs(region.rooms) do
					local w = m.obj.width
					local h = m.obj.height
					
					-- in room block units
					local roomxmin = m.obj.x + region.ofs.x
					local roomymin = m.obj.y + region.ofs.y
					local roomxmax = roomxmin + w
					local roomymax = roomymin + h
					if self.mouseViewPos.x >= roomxmin * blocksPerRoom
					and self.mouseViewPos.x <= roomxmax * blocksPerRoom
					and self.mouseViewPos.y >= -roomymax * blocksPerRoom
					and self.mouseViewPos.y <= -roomymin * blocksPerRoom
					then
print('clicking on region', region.index)						
						self.mouseDownOnRegion = region
						break
					end
				end
				if self.mouseDownOnRegion then break end
			end
		else
			local mouseDeltaX = self.mouse.deltaPos.x * (viewxmax - viewxmin)
			local mouseDeltaY = self.mouse.deltaPos.y * (viewymax - viewymin)
			if self.mouseDownOnRegion then
				self.mouseDownOnRegion.ofs.x = self.mouseDownOnRegion.ofs.x + mouseDeltaX / blocksPerRoom
				self.mouseDownOnRegion.ofs.y = self.mouseDownOnRegion.ofs.y - mouseDeltaY / blocksPerRoom
			
				-- if we are dragging then don't let orbit control view
				self.view.orthoSize = viewBeforeSize
				self.view.pos.x = viewBeforeX
				self.view.pos.y = viewBeforeY
			end
		end
	else
		-- TODO highlight region under mouse?
	end
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
	ig.igSameLine()
	checkboxTooltip('Draw PLMs', _G, 'editorDrawPLMs')
	ig.igSameLine()
	checkboxTooltip('Draw Enemy Spawns', _G, 'editorDrawEnemySpawnSets')
	ig.igSameLine()
	checkboxTooltip('Draw Doors', _G, 'editorDrawDoors')

	for i,info in ipairs(predefinedRegionOffsets) do
		if ig.igButton(info.name) then
			self:setRegionOffsets(i)
		end
	end

	if ig.igCollapsingHeader'regions' then
		ig.igPushIDStr'regions'
		for i,region in ipairs(self.regions) do
			if ig.igCollapsingHeader('region '..region.index) then
				ig.igPushIDInt(i)
				checkboxTooltip('Show Region '..region.index, region, 'show')
				inputFloatToolkit('xofs', region.ofs, 'x')
				inputFloatToolkit('yofs', region.ofs, 'y')
				if i < #self.regions then
					ig.igSeparator()
				end
				ig.igPopID()
			end
		end
		ig.igPopID()
	end	

	if ig.igCollapsingHeader'tilesets' then
		ig.igPushIDStr'tilesets'
		for i,tileSet in ipairs(self.sm.tileSets) do
			ig.igButton(' ')
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
			ig.igSameLine()
			ig.igButton(' ')
			if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
				ig.igBeginTooltip()
				ig.igText('tileset '..tileSet.index..' palette')
				local paletteTex = tileSet.palette.tex
				if paletteTex then
					local texIDPtr = ffi.cast('void*',ffi.cast('intptr_t',paletteTex.id))
					ig.igImage(
						texIDPtr,
						ig.ImVec2(paletteTex.width, 16),
						ig.ImVec2(0, 0),
						ig.ImVec2(1, 1)
					)
				end
				ig.igEndTooltip()
			end
			ig.igSameLine()
			ig.igButton(' ')
			if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
				ig.igBeginTooltip()
				ig.igText('tileset '..tileSet.index..' graphicsTiles')
				if tileSet.graphicsTileTex then
					local texIDPtr = ffi.cast('void*',ffi.cast('intptr_t',tileSet.graphicsTileTex.id))
					ig.igImage(
						texIDPtr,
						ig.ImVec2(tileSet.graphicsTileTex.width, tileSet.graphicsTileTex.height),
						ig.ImVec2(0, -1),
						ig.ImVec2(1, 0)
					)			
				end
				ig.igEndTooltip()
			end
		end
		ig.igPopID()
	end
end

App():run()
