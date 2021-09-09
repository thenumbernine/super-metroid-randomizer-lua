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
local math = require 'ext.math'
local file = require 'ext.file'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'
local SM = require 'sm'

-- TODO replace this with shaders
local useBakedLayer3Background = true


--local cmdline = require 'ext.cmdline'(...)
local infilename = ... or 'Super Metroid (JU) [!].smc'

local App = class(require 'glapp.orbit'(require 'imguiapp'))

App.title = 'Super Metroid Viewer'


local blockSizeInPixels = SM.blockSizeInPixels
local blocksPerRoom = SM.blocksPerRoom
local graphicsTileSizeInPixels = SM.graphicsTileSizeInPixels 
local graphicsTileSizeInBytes = SM.graphicsTileSizeInBytes 
local roomSizeInPixels = SM.roomSizeInPixels 

-- TODO this should match the region tilemap sizes
local mapMaxWidth = 64
local mapMaxHeight = 32

-- how do we want to pack our tile textures?
-- this is arbitrary, but pick something squareish so we don't reach the tex dim limit
local tileSetRowWidth = 32

-- global, for gui / table access
editorDrawForeground = true
editorDrawLayer2 = true
editorDrawPLMs = true
editorDrawEnemySpawnSets = true
editorDrawDoors = true
editorHideFilledMapBlocks = true
editorShowRegionBorders = false
editorShowRoomBorders = false

local editorModes = {
	'pan',
	'moveRegions',
	'moveRooms',
}
for k,v in pairs(editorModes) do
	editorModes[v] = k
end
editorMode = 1

-- [==[ can't get rid of this yet until I store the tilemaps separately as well
-- but turns out baking the palette was the biggest slowdown
do
	local old = SM.mapGetBitmapForTileSetAndTileMap
	function SM:mapGetBitmapForTileSetAndTileMap(...)
		local tileSet, tilemap = ...
		local bgBmp = old(self, ...)
		if not bgBmp.tex then
			bgBmp.tex = GLTex2D{
				width = bgBmp.dataBmp.width,
				height = bgBmp.dataBmp.height,
				data = bgBmp.dataBmp.buffer,
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


local Region = class()

function Region:init(index)
	self.rooms = table()
	self.index = index
	self.show = true	--index==0
	self.ofs = vec2f(0,0)
end

function Region:calcBounds()
	self.xmin = math.huge
	self.ymin = math.huge
	self.xmax = -math.huge
	self.ymax = -math.huge
	for _,m in ipairs(self.rooms) do
		self.xmin = math.min(self.xmin, m.obj.x)
		self.ymin = math.min(self.ymin, m.obj.y)
		self.xmax = math.max(self.xmax, m.obj.x + m.obj.width)
		self.ymax = math.max(self.ymax, m.obj.y + m.obj.height)
	end
end

function App:initGL()
	App.super.initGL(self)

	local romstr = file[infilename]
	local header = ''
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print('skipping rom file header')
		header = romstr:sub(1,512)
		romstr = romstr:sub(513)
	end
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print("WARNING - rom is not bank-aligned")
	end

	-- global so other files can see it
	self.rom = ffi.cast('uint8_t*', romstr) 
	self.sm = SM(self.rom, #romstr)

	self.regions = range(0,7):mapi(function(index)
		return Region(index)
	end)
	for _,m in ipairs(self.sm.rooms) do
		local index = m.obj.region+1
		local region = self.regions[index]
		region.rooms:insert(m)
		-- TODO move the 'region' object in SM?
		m.region = region
	end
	for _,region in ipairs(self.regions) do
		region:calcBounds()
	end


	do
		local targetoffset
		for i,ofs in ipairs(self.predefinedRegionOffsets) do
			for _,md5 in ipairs(ofs.md5s) do
				if md5 == self.sm.md5hash then
					targetoffset = i
					break
				end
			end
			if targetoffset then break end
		end
		self:setRegionOffsets(targetoffset or 1)
	end

	-- TODO use this for switching which state is being displayed
	-- since roomstates can have fully different tilesets blocks etc
	self.roomCurrentRoomStates = {}

-- [[ keep track of which roomblock mapblocks are all solid, for occlusion
	for _,roomBlockData in ipairs(self.sm.roomblocks) do
		local w = roomBlockData.width / blocksPerRoom
		local h = roomBlockData.height / blocksPerRoom
		local blocks12 = roomBlockData:getBlocks12()
		local layer2blocks = roomBlockData:getLayer2Blocks()
		roomBlockData.roomAllSolidFlags = ffi.new('uint8_t[?]', w*h)	-- one bit per byte ... so wasteful
		for j=0,h-1 do
			for i=0,w-1 do
				local index = blocksPerRoom * (i + w * blocksPerRoom * j)
				local allSolid = 3
				local firstTileIndex = bit.band(ffi.cast('uint16_t*', blocks12)[index], 0x3ff)
				local firstLayer2TileIndex
				if layer2blocks then
					firstLayer2TileIndex = bit.band(ffi.cast('uint16_t*', layer2blocks)[index], 0x3ff)
				end
				for ti=0,blocksPerRoom-1 do
					for tj=0,blocksPerRoom-1 do
						local dx = ti + blocksPerRoom * i
						local dy = tj + blocksPerRoom * j
						local di = dx + blocksPerRoom * w * dy
						
						local tileIndex = bit.band(ffi.cast('uint16_t*', blocks12)[di], 0x3ff)
						if tileIndex ~= firstTileIndex then
							allSolid = bit.band(allSolid, bit.bnot(1))
						end
												
						if layer2blocks then
							local tileIndex = bit.band(ffi.cast('uint16_t*', layer2blocks)[di], 0x3ff)
							if tileIndex ~= firstLayer2TileIndex then
								allSolid = bit.band(allSolid, bit.bnot(2))
							end
						end
						if allSolid == 0 then break end
					end
					if allSolid == 0 then break end
				end
				roomBlockData.roomAllSolidFlags[i+w*j] = allSolid
			end
		end
	end
--]]

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
		-- make a texture out of the tileSet tilemap ... 1 uint16 per 8x8 tile
		tileSet.graphicsTileTex = self:graphicsTilesToTex(tileSet.graphicsTileVec.v, tileSet.graphicsTileVec.size)

		-- tileGfxBmp is from combining the common room data and the tileset data
		if tileSet.tileGfxBmp then
			local img = Image(
				blockSizeInPixels * tileSetRowWidth,
				blockSizeInPixels * math.ceil(tileSet.tileGfxCount / tileSetRowWidth),
				1, 'uint8_t')
			for tileIndex=0,tileSet.tileGfxCount-1 do
				local xofs = tileIndex % tileSetRowWidth
				local yofs = math.floor(tileIndex / tileSetRowWidth)
				for i=0,blockSizeInPixels-1 do
					for j=0,blockSizeInPixels-1 do
						local srcIndex = i + blockSizeInPixels * (j + blockSizeInPixels * tileIndex)
						local paletteIndex = tileSet.tileGfxBmp.buffer[srcIndex]
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

	-- make textures of the region maps
	self.pauseScreenTileTex = self:graphicsTilesToTex(self.sm.pauseScreenTiles.data, self.sm.pauseScreenTiles:sizeof())
	self.itemTileTex = self:graphicsTilesToTex(self.sm.itemTiles.data, self.sm.itemTiles:sizeof(), 8)
	
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

--[[
make a texture out of the graphicsTiles ... 
ptr = pointer to graphics tiles (32 bytes per 8x8 tile)
size = size of buffer in bytes
graphicsTileSizeInPixels * graphicsTileSizeInPixels packed into a higher size
higher size is (graphicsTileSizeInPixels * tilemapElemSizeX) * (whatever's left)
--]]
function App:graphicsTilesToTex(ptr, size, tilemapElemSizeX)
	tilemapElemSizeX = tilemapElemSizeX or 16
	assert(size % graphicsTileSizeInBytes == 0, "size should be aligned to "..graphicsTileSizeInBytes)
	local numGraphicTiles = size / graphicsTileSizeInBytes
	local tilemapElemSizeY = math.floor(numGraphicTiles / tilemapElemSizeX)
	if tilemapElemSizeX * tilemapElemSizeY ~= numGraphicTiles then
		error(require 'ext.tolua'{
			tilemapElemSizeX = tilemapElemSizeX,
			tilemapElemSizeY = tilemapElemSizeY, 
			numGraphicTiles = numGraphicTiles,
		})
	end
	local tilemap = ffi.new('tilemapElem_t[?]', tilemapElemSizeX * tilemapElemSizeY)
	for i=0,numGraphicTiles-1 do
		tilemap[i].graphicsTileIndex = i
		tilemap[i].colorIndexHi = 0
		tilemap[i].xflip = 0
		tilemap[i].yflip = 0
	end
	
	local img = self.sm:graphicsConvertTilemapToBitmap(
		tilemap,			-- tilemap = tilemapElem_t[numGraphicTiles * graphicsTileSizeInPixels]
		tilemapElemSizeX,	-- tilemapElemSizeX
		tilemapElemSizeY,	-- tilemapElemSizeY
		ptr)				-- graphicsTiles

	-- alright now that we have this, we can store the tilemap as a uint16 per graphicstile
	-- instead of as a rendered bitmap
	return GLTex2D{
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
end



App.predefinedRegionOffsets = {
-- default arrangement.  too bad crateria right of wrecked ship isn't further right to fit wrecked ship in
	{
		name = 'Original',
		md5s = {
			'f24904a32f1f6fc40f5be39086a7fa7c',
			'21f3e98df4780ee1c667b84e57d88675',
			'3d64f89499a403d17d530388854a7da5',
		},
		ofs = {
			{0, 0},
			{-3, 18},
			{28, 37},
			{29, -3},	--{34, -10},	-- the commented offset is where it would go if the rhs of crateria was pushed further right
			{25, 18},
			{-3, 0},
			{15, -18},
			{0, 0},
		},
	},
	{
		name = 'Vitality',
		md5s = {
			'6092a3ea09347e1800e330ea27efbef2',
		},
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
		md5s = {
			'083a857c6f5251762d241202e5f46808',
		},
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
		name = 'Metroid Super Zero Mission 2.3',
		md5s = {
			'8c04220c2e0f78abb9bb7cbbc7cfbbde',
		},
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
	{
		name = 'Metroid Rotation Hack',
		md5s = {
			'606a6edb8826354edff97d505d478b3a',
		},
		ofs = {
			{16,0},
			{-19,-1},
			{-34,25},
			{53,6},
			{12,28},
			{-7,2},
			{15,-18},
			{0,0},
		},
	},
}

function App:setRegionOffsets(index)
	local predef = self.predefinedRegionOffsets[index]
	for i,ofs in ipairs(predef.ofs) do
		self.regions[i].ofs:set(ofs[1], ofs[2])
	end
end

-- 1 gl unit = 1 tile
function App:update()

	gl.glClear(bit.bor(gl.GL_COLOR_BUFFER_BIT, gl.GL_DEPTH_BUFFER_BIT))

	local view = self.view
	local aspectRatio = self.width / self.height
	local viewxmin, viewxmax, viewymin, viewymax = view:getBounds(aspectRatio)
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
			if editorShowRegionBorders then
				local x1, y1 = blocksPerRoom * (region.xmin + region.ofs.x), blocksPerRoom * (region.ymin + region.ofs.y)
				local x2, y2 = blocksPerRoom * (region.xmax + region.ofs.x), blocksPerRoom * (region.ymax + region.ofs.y)
				gl.glColor3f(1,0,1)
				gl.glLineWidth(4)
				gl.glBegin(gl.GL_LINE_LOOP)
				gl.glVertex2f(x1, -y1)
				gl.glVertex2f(x1, -y2)
				gl.glVertex2f(x2, -y2)
				gl.glVertex2f(x2, -y1)
				gl.glEnd()
				gl.glLineWidth(1)
			end

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
					if editorShowRoomBorders then
						local x1, y1 = blocksPerRoom * roomxmin, blocksPerRoom * roomymin
						local x2, y2 = blocksPerRoom * roomxmax, blocksPerRoom * roomymax
						gl.glColor3f(1,1,0)
						gl.glLineWidth(4)
						gl.glBegin(gl.GL_LINE_LOOP)
						gl.glVertex2f(x1, -y1)
						gl.glVertex2f(x1, -y2)
						gl.glVertex2f(x2, -y2)
						gl.glVertex2f(x2, -y1)
						gl.glEnd()
						gl.glLineWidth(1)				
					end

					local roomIndex = bit.bor(bit.lshift(m.obj.region, 8), m.obj.index)
					local currentRoomStateIndex = self.roomCurrentRoomStates[roomIndex] or 1
					local rs = m.roomStates[
						((currentRoomStateIndex - 1) % #m.roomStates) + 1
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
-- TODO get the tilemap shader working and then turn this off
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
									if (
										blocksPerRoom * (roomxmin + i + 1) >= viewxmin
										or blocksPerRoom * (roomxmin + i) <= viewxmax
										or blocksPerRoom * -(roomymin + j + 1) >= viewymin
										or blocksPerRoom * -(roomymin + j) <= viewymax
									) 
									-- [[
									and (
										not editorHideFilledMapBlocks
										or bit.band(roomBlockData.roomAllSolidFlags[i+w*j], 1) == 0
									)
									--]]
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
						local layer2blocks = roomBlockData:getLayer2Blocks()
						for j=0,h-1 do
							for i=0,w-1 do
								if (
									blocksPerRoom * (roomxmin + i + 1) >= viewxmin
									or blocksPerRoom * (roomxmin + i) <= viewxmax
									or blocksPerRoom * -(roomymin + j + 1) >= viewymin
									or blocksPerRoom * -(roomymin + j) <= viewymax
								) then
									
									local drawLayer2 = 
										editorDrawLayer2
										and layer2blocks
										-- [[
										and (
											not editorHideFilledMapBlocks
											or bit.band(roomBlockData.roomAllSolidFlags[i+w*j], 2) == 0
										)
										--]]

									local drawLayer1 = 
										editorDrawForeground 
										and blocks12
										-- [[
										and (
											not editorHideFilledMapBlocks
											or bit.band(roomBlockData.roomAllSolidFlags[i+w*j], 1) == 0
										)
										--]]

									for ti=0,blocksPerRoom-1 do
										for tj=0,blocksPerRoom-1 do
											-- draw layer2 background if it's there
											if drawLayer2 then
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
											if drawLayer1 then
												local dx = ti + blocksPerRoom * i
												local dy = tj + blocksPerRoom * j
												local di = dx + blocksPerRoom * w * dy
												
												local tileIndex = ffi.cast('uint16_t*', blocks12)[di]
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
								local x = .5 + plm.x + blocksPerRoom * roomxmin
								local y = .5 + (plm.y + blocksPerRoom * roomymin)
								gl.glBegin(gl.GL_LINES)
								gl.glVertex2f(x-.5, -y)
								gl.glVertex2f(x+.5, -y)
								gl.glVertex2f(x, -y-.5)
								gl.glVertex2f(x, -y+.5)
								gl.glEnd()
							end
						end
						
						if editorDrawEnemySpawnSets 
						and rs.enemySpawnSet 
						then
							gl.glColor3f(1,0,1)
							for _,enemySpawn in ipairs(rs.enemySpawnSet.enemySpawns) do
								local x = enemySpawn.x / 16 + blocksPerRoom * roomxmin
								local y = enemySpawn.y / 16 + blocksPerRoom * roomymin
								gl.glBegin(gl.GL_LINES)
								gl.glVertex2f(x-.5, -y)
								gl.glVertex2f(x+.5, -y)
								gl.glVertex2f(x, -y-.5)
								gl.glVertex2f(x, -y+.5)
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


local ObjectSelector = class()

ObjectSelector.snap = 1 

function ObjectSelector:init()
	self.selectedObjDown = vec2f()
end

function ObjectSelector:updateMouse(app)
	if app.mouse.leftDown then
		if not app.mouse.lastLeftDown then
			self.dragging = false

			app[self.selectedField] = self:getObjUnderPos(app, app.mouseViewPos:unpack())
			if app[self.selectedField] then
				app.mouseDownX = app.mouseViewPos.x
				app.mouseDownY = app.mouseViewPos.y
				self.selectedObjDown:set(self:getObjPos(app[self.selectedField]))
			else
				-- TODO here - start a selection rectangle
				-- then on mouseup, select all touching rooms
			end
		else
			local obj = app[self.selectedField]
			if obj then
				local deltaX = app.mouseViewPos.x - app.mouseDownX
				local deltaY = app.mouseViewPos.y - app.mouseDownY
				
				if math.abs(deltaX) > 5
				or math.abs(deltaY) > 5
				then
					self.dragging = true
				end
				

				deltaX = math.round(deltaX / self.snap) * self.snap
				deltaY = math.round(deltaY / self.snap) * self.snap

				self:setObjPos(
					obj,
					self.selectedObjDown.x + deltaX,
					self.selectedObjDown.y - deltaY
				)
			
				-- if we are dragging then don't let orbit control view
				app.view.orthoSize = app.viewBeforeSize
				app.view.pos.x = app.viewBeforeX
				app.view.pos.y = app.viewBeforeY
			end
		end
	else
		if app.mouse.lastLeftDown then
			if not self.dragging then
				self:onClick(app)
			end
--[[ only recalc bounds on mouseup			
			if m then
				m.region:calcBounds()
			end
--]]
		end
	end
end

function ObjectSelector:onClick(app)
end


local RegionSelector = class(ObjectSelector)

RegionSelector.selectedField = 'selectedRegion'

RegionSelector.snap = blocksPerRoom

function RegionSelector:getObjUnderPos(app, x, y)
	for _,region in ipairs(app.regions) do
		if region.show then
			for _,m in ipairs(region.rooms) do
				local w = m.obj.width
				local h = m.obj.height
				local i = math.floor(x / blocksPerRoom - m.obj.x + region.ofs.x)
				local j = math.floor(-y / blocksPerRoom - m.obj.y + region.ofs.y)
				if i >= 0 and i < w
				and j >= 0 and j < h
				then
					if not editorHideFilledMapBlocks
					or bit.band(roomBlockData.roomAllSolidFlags[i+w*j], 1) == 0
					then
						return region
					end
				end
			end
		end
	end
end

function RegionSelector:getObjPos(region)
	return 
		region.ofs.x * blocksPerRoom,
		region.ofs.y * blocksPerRoom
end

function RegionSelector:setObjPos(region, x,y)
	region.ofs:set(
		x / blocksPerRoom,
		y / blocksPerRoom
	)
end


local regionSelector = RegionSelector()


local RoomSelector = class(ObjectSelector)

RoomSelector.selectedField = 'selectedRoom'

RoomSelector.snap = blocksPerRoom

function RoomSelector:getObjUnderPos(app, x, y)
	for _,region in ipairs(app.regions) do
		if region.show then
			for _,m in ipairs(region.rooms) do
				local xmin = m.obj.x + region.ofs.x
				local ymin = m.obj.y + region.ofs.y
				local xmax = xmin + m.obj.width
				local ymax = ymin + m.obj.height
				if x >= xmin * blocksPerRoom
				and x <= xmax * blocksPerRoom
				and y >= -ymax * blocksPerRoom
				and y <= -ymin * blocksPerRoom
				then
					return m
				end
			end
		end
	end
end

function RoomSelector:getObjPos(m)
	return
		(m.obj.x + m.region.ofs.x) * blocksPerRoom,
		(m.obj.y + m.region.ofs.y) * blocksPerRoom
end

function RoomSelector:setObjPos(m, x, y)
	x = x / blocksPerRoom
    y = y / blocksPerRoom
	x = x - m.region.ofs.x
	y = y - m.region.ofs.y
	x = math.clamp(x, 0, mapMaxWidth - m.obj.width)
	y = math.clamp(y, 0, mapMaxHeight - m.obj.height) 
	if x ~= m.obj.x
	or y ~= m.obj.y
	then
		m.obj.x = x
		m.obj.y = y
		
-- [[ recalc bounds while you drag					
		m.region:calcBounds()
--]]
	end
end

function RoomSelector:onClick(app)
	local m = app.selectedRoom
	if m then
		local roomIndex = bit.bor(bit.lshift(m.obj.region, 8), m.obj.index)
		local currentRoomStateIndex = app.roomCurrentRoomStates[roomIndex] or 1
		currentRoomStateIndex = (currentRoomStateIndex % #m.roomStates) + 1
		app.roomCurrentRoomStates[roomIndex] = currentRoomStateIndex 
print('room '..('%04x'):format(roomIndex)..' now showing state '..currentRoomStateIndex..' of '..#m.roomStates)
	end
end

local roomSelector = RoomSelector()


function App:event(...)
	self.viewBeforeSize = self.view.orthoSize
	self.viewBeforeX = self.view.pos.x
	self.viewBeforeY = self.view.pos.y

	App.super.event(self, ...)


	local view = self.view
	local aspectRatio = self.width / self.height
	local viewxmin, viewxmax, viewymin, viewymax = view:getBounds(aspectRatio)
	viewxmin = view.pos.x - view.orthoSize * aspectRatio
	viewxmax = view.pos.x + view.orthoSize * aspectRatio
	viewymin = view.pos.y - view.orthoSize
	viewymax = view.pos.y + view.orthoSize

	self.mouseViewPos:set(
		(1 - self.mouse.pos.x) * viewxmin + self.mouse.pos.x * viewxmax,
		(1 - self.mouse.pos.y) * viewymin + self.mouse.pos.y * viewymax
	)


	if editorMode == editorModes.pan then
		-- just use default orbit behavior
	elseif editorMode == editorModes.moveRegions then
		regionSelector:updateMouse(self)
	elseif editorMode == editorModes.moveRooms then
		roomSelector:updateMouse(self)
	end
end

local function hoverTooltip(name)
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igBeginTooltip()
		ig.igText(name)
		ig.igEndTooltip()
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
	hoverTooltip(name)
	ig.igPopID()
	return result
end

local float = ffi.new('float[1]')
local function inputFloatTooltip(name, t, k)
	ig.igPushIDStr(name)
	float[0] = tonumber(t[k]) or 0
	local result = ig.igInputFloat('', float)
	if result then
		t[k] = float[0]
	end
	hoverTooltip(name)
	ig.igPopID()
	return result
end

local function buttonTooltip(name, ...)
	ig.igPushIDStr(name)
	local result = ig.igButton(' ', ...)
	hoverTooltip(name)
	ig.igPopID()
	return result
end

local function makeTooltipImage(name, tex, w, h, color)
	w = w or tex.width
	h = h or tex.height
	ig.igButton(' ')
	if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) then
		ig.igBeginTooltip()
		ig.igText(name)
		local texIDPtr = ffi.cast('void*',ffi.cast('intptr_t',tex.id))
		ig.igImage(
			texIDPtr,
			ig.ImVec2(w, h),
			ig.ImVec2(0, -1),
			ig.ImVec2(1, 0),
			color or ig.ImVec4(1,1,1,1)
		)
		ig.igEndTooltip()
	end
end

local int = ffi.new('int[1]', 0)
local function radioTooltip(name, t, k, v)
	ig.igPushIDStr(name)
	local result = ig.igRadioButtonIntPtr('', int, v)
	hoverTooltip(name)
	ig.igPopID()
	if result then
		t[k] = int[0]
	end
end

local function radioTooltipsFromTable(names, t, k)
	int[0] = t[k]
	for v,name in ipairs(names) do
		radioTooltip(name, t, k, v)
		if v < #names then
			ig.igSameLine()
		end
	end
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
	ig.igSameLine()
	checkboxTooltip('Hide MapBlocks Of Solid Tiles', _G, 'editorHideFilledMapBlocks')
	ig.igSameLine()
	checkboxTooltip('Show Region Borders', _G, 'editorShowRegionBorders')
	ig.igSameLine()
	checkboxTooltip('Show Room Borders', _G, 'editorShowRoomBorders')

	radioTooltipsFromTable(editorModes, _G, 'editorMode')

	if ig.igCollapsingHeader'Set Region Offsets To Predefined:' then
		for i,info in ipairs(self.predefinedRegionOffsets) do
			if buttonTooltip(info.name) then
				self:setRegionOffsets(i)
			end
			if i < #self.predefinedRegionOffsets then
				ig.igSameLine()
			end
		end
	end

	makeTooltipImage(
		'pause screen tiles',
		self.pauseScreenTileTex,
		nil, nil,
		ig.ImVec4(255,255,255,1)
	)
	ig.igSameLine()
	makeTooltipImage(
		'item tiles',
		self.itemTileTex,
		nil, nil,
		ig.ImVec4(255,255,255,1)
	)


	if ig.igCollapsingHeader'regions' then
		ig.igPushIDStr'regions'
		for i,region in ipairs(self.regions) do
			if ig.igCollapsingHeader('region '..region.index) then
				ig.igPushIDInt(i)
				checkboxTooltip('Show Region '..region.index, region, 'show')
				inputFloatTooltip('xofs', region.ofs, 'x')
				inputFloatTooltip('yofs', region.ofs, 'y')
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
			if tileSet.tex then 
				makeTooltipImage(
					'tileset '..tileSet.index,
					tileSet.tex
				)
				ig.igSameLine()
			end
			if tileSet.palette.tex then
				makeTooltipImage(
					'tileset '..tileSet.index..' palette',
					tileSet.palette.tex,
					tileSet.palette.width, 16
				)
				ig.igSameLine()
			end
			if tileSet.graphicsTileTex then
				makeTooltipImage(
					'tileset '..tileSet.index..' graphicsTiles',
					tileSet.graphicsTileTex,
					nil, nil,
					ig.ImVec4(255,255,255,1)
				)
			end
		end
		ig.igPopID()
	end
end

App():run()
