#!/usr/bin/env luajit
--[[
whereas 'run.lua' is the console randomizer,
this is the OpenGL/imgui visualizer

TODO replace the rgb conversion with a shader that takes in the indexed 8-bit image and the palette

--]]
local ffi = require 'ffi'
local ig = require 'imgui'
local gl = require 'gl'
local glreport = require 'gl.report'
local GLTex2D = require 'gl.tex2d'
local GLProgram = require 'gl.program'
local GLGeometry = require 'gl.geometry'
local GLSceneObject = require 'gl.sceneobject'
local class = require 'ext.class'
local table = require 'ext.table'
local range = require 'ext.range'
local math = require 'ext.math'
local path = require 'ext.path'
local vec2f = require 'vec-ffi.vec2f'
local Image = require 'image'
local SM = require 'super_metroid_randomizer.sm'

local topc = require 'super_metroid_randomizer.pc'.to
local frompc = require 'super_metroid_randomizer.pc'.from

-- TODO replace this with shaders
local useBakedGraphicsTileTextures = true 
--local useBakedGraphicsTileTextures = false


--local cmdline = require 'ext.cmdline'(...)
local infilename = ... or 'Super Metroid (JU) [!].smc'

require 'glapp.view'.useBuiltinMatrixMath = true

local App = require 'imguiapp.withorbit'()

App.title = 'Super Metroid Viewer'


local blockSizeInPixels = SM.blockSizeInPixels
local blocksPerRoom = require 'super_metroid_randomizer.roomblocks'.blocksPerRoom
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
	'Pan',
	'Regions',
	'Rooms',
	'Doors',
}
for k,v in pairs(editorModes) do
	editorModes[v] = k
end
editorMode = 1



local ObjectSelector = class()

ObjectSelector.snap = 1 

function ObjectSelector:init()
	self.selectedObjDown = vec2f()
end

function ObjectSelector:updateMouse(app)
	if app.mouse.leftDown then
		-- left pressing down
		if not app.mouse.lastLeftDown then
			self.movingSelection = false

			local obj = self:getObjUnderPos(app, app.mouseViewPos:unpack())
			self.selected = table{obj}
			app[self.selectedField] = obj
			if obj then
				self.selObjMoveDownX = assert(app.mouseViewPos.x)
				self.selObjMoveDownY = assert(app.mouseViewPos.y)
				self.selectedObjDown:set(self:getObjPos(obj))
			else
				-- here - start a selection rectangle
				-- then on mouseup, select all touching rooms
				self.selRectDownX = assert(app.mouseViewPos.x)
				self.selRectDownY = assert(app.mouseViewPos.y)
			end
		
		-- left holding down
		else
			local obj = app[self.selectedField]
			if obj then
				local deltaX = app.mouseViewPos.x - self.selObjMoveDownX
				local deltaY = app.mouseViewPos.y - self.selObjMoveDownY
				
				if math.abs(deltaX) > 5
				or math.abs(deltaY) > 5
				then
					-- notice this 'movingSelection' means 'moving'
					self.movingSelection = true
				end
				
				
				if self.movingSelection then
					deltaX = math.round(deltaX / self.snap) * self.snap
					deltaY = math.round(deltaY / self.snap) * self.snap

					self:setObjPos(
						obj,
						self.selectedObjDown.x + deltaX,
						self.selectedObjDown.y - deltaY
					)
				end
			else
				-- selecting rectangle
			end
			
			-- if we are dragging then don't let orbit control view
			app.view.orthoSize = app.viewBeforeSize
			app.view.pos.x = app.viewBeforeX
			app.view.pos.y = app.viewBeforeY
		end
	else
		if app.mouse.lastLeftDown then
			-- TODO don't just drag 'obj, but drag *all objects* that were selected, which is 'self.selected'
			if not self.movingSelection then
				self:onClick(app)
			end
--[[ only recalc bounds on mouseup			
			if m then
				m.region:calcBounds()
			end
--]]
			local obj = app[self.selectedField]
			if obj then
			else
				-- rect select ... set 'self.selected' to a table of all objects touching the rectangle
			end

			self.selObjMoveDownX = nil
			self.selObjMoveDownY = nil
			self.selRectDownX = nil
			self.selRectDownY = nil
		else
			app[self.mouseOverField] = self:getObjUnderPos(app, app.mouseViewPos:unpack())
		end
	end
end

function ObjectSelector:onClick(app)
end


local RegionSelector = class(ObjectSelector)

RegionSelector.selectedField = 'selectedRegion'
RegionSelector.mouseOverField = 'mouseOverRegion'

RegionSelector.snap = blocksPerRoom

function RegionSelector:getObjUnderPos(app, x, y)
	for _,region in ipairs(app.regions) do
		if region.show then
			for _,m in ipairs(region.rooms) do
				local xmin = m:obj().x + region.ofs.x
				local ymin = m:obj().y + region.ofs.y
				local xmax = xmin + m:obj().width
				local ymax = ymin + m:obj().height
				if x >= xmin * blocksPerRoom
				and x <= xmax * blocksPerRoom
				and y >= -ymax * blocksPerRoom
				and y <= -ymin * blocksPerRoom
				then
--					local roomKey = bit.bor(bit.lshift(m:obj().region, 8), m:obj().index)
--					local currentRoomStateIndex = app.roomCurrentRoomStates[roomKey] or 0
--					local rs = m.roomStates[currentRoomStateIndex+1]
--					if not editorHideFilledMapBlocks
--					or bit.band(rs.roomBlockData.roomAllSolidFlags[i+w*j], 1) == 0
--					then
					return region
--					end
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




local RoomSelector = class(ObjectSelector)

RoomSelector.selectedField = 'selectedRoom'
RoomSelector.mouseOverField = 'mouseOverRoom'

RoomSelector.snap = blocksPerRoom

function RoomSelector:getObjUnderPos(app, x, y)
	for _,region in ipairs(app.regions) do
		if region.show then
			for _,m in ipairs(region.rooms) do
				local xmin = m:obj().x + region.ofs.x
				local ymin = m:obj().y + region.ofs.y
				local xmax = xmin + m:obj().width
				local ymax = ymin + m:obj().height
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
		(m:obj().x + m.region.ofs.x) * blocksPerRoom,
		(m:obj().y + m.region.ofs.y) * blocksPerRoom
end

function RoomSelector:setObjPos(m, x, y)
	x = x / blocksPerRoom
    y = y / blocksPerRoom
	x = x - m.region.ofs.x
	y = y - m.region.ofs.y
	x = math.clamp(x, 0, mapMaxWidth - m:obj().width)
	y = math.clamp(y, 0, mapMaxHeight - m:obj().height) 
	if x ~= m:obj().x
	or y ~= m:obj().y
	then
		m:obj().x = x
		m:obj().y = y
		
-- [[ recalc bounds while you drag					
		m.region:calcBounds()
--]]
	end
end

function RoomSelector:onClick(app)
	local m = app.selectedRoom
	if m then
		app.selectedRoomIndex = (app.sm.rooms:find(m) or 1)-1
		local roomKey = bit.bor(bit.lshift(m:obj().region, 8), m:obj().index)
		local currentRoomStateIndex = app.roomCurrentRoomStates[roomKey] or 0
		currentRoomStateIndex = (currentRoomStateIndex+1) % #m.roomStates
		app.roomCurrentRoomStates[roomKey] = currentRoomStateIndex 
print('room '..('%04x'):format(roomKey)..' now showing state '..currentRoomStateIndex..' of '..#m.roomStates)
	end
end



local DoorSelector = class(ObjectSelector)

DoorSelector.selectedField = 'selectedDoor'
DoorSelector.mouseOverField = 'mouseOverDoor'

-- TODO snap function vs snap value
DoorSelector.snap = 1

function DoorSelector:getObjUnderPos(app, x, y)
	for _,region in ipairs(app.regions) do
		if region.show then
			for _,m in ipairs(region.rooms) do
				local roomKey = bit.bor(bit.lshift(m:obj().region, 8), m:obj().index)
				local currentRoomStateIndex = app.roomCurrentRoomStates[roomKey] or 0
				local rs = m.roomStates[currentRoomStateIndex+1]
		
				for exitIndex,blockpos in pairs(rs.roomBlockData.blocksForExit) do
					local door = m.doors[exitIndex+1]
					for _,pos in ipairs(blockpos) do
						local adx = math.abs(x - pos[1])
						local ady = math.abs(y - pos[2])
						if adx < .5 and ady < .5 then
							return {m=m, door=door, pos=pos}
						end
					end
				end
			end
		end
	end
end

function DoorSelector:getObjPos(roomAndDoor)
	local m, door, pos = roomAndDoor.m, roomAndDoor.door, room.pos
	return
		(m:obj().x + m.region.ofs.x) * blocksPerRoom + pos[1],
		(m:obj().y + m.region.ofs.y) * blocksPerRoom + pos[2]
end

function DoorSelector:setObjPos(roomAndDoor, x, y)
	-- TODO ... this shouldn't be dragging
	-- doors are associated with tile positions
end


-- TODO how come when I make these member variables it goes incredibly slow?
local roomSelector = RoomSelector()
local regionSelector = RegionSelector()
local doorSelector = DoorSelector()






local function glMakeU8Tex(image)
	assert(ffi.sizeof(image.format) == 1)
	assert(image.channels == 1)
	return GLTex2D{
		width = image.width,
		height = image.height,
		data = image.buffer,
		format = gl.GL_RED,
		internalFormat = gl.GL_R8,	-- gl.GL_R8UI,
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

-- [==[ can't get rid of this yet until I store the tilemaps separately as well
-- but turns out baking the palette was the biggest slowdown
do
	local old = SM.mapGetBitmapForTileSetAndTileMap
	function SM:mapGetBitmapForTileSetAndTileMap(...)
		local tileSet, tilemap = ...
		local bgBmp = old(self, ...)
		if not bgBmp.tex then
			bgBmp.tex = glMakeU8Tex(bgBmp.dataBmp)
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
		self.xmin = math.min(self.xmin, m:obj().x)
		self.ymin = math.min(self.ymin, m:obj().y)
		self.xmax = math.max(self.xmax, m:obj().x + m:obj().width)
		self.ymax = math.max(self.ymax, m:obj().y + m:obj().height)
	end
end

function App:initGL()
	App.super.initGL(self)

	local romstr = assert(path(infilename):read())
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
		local index = m:obj().region+1
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
		-- [[ convert to RGBA8	
		local img = Image(256, 1, 4, 'unsigned char')
		img:clear()
		for paletteIndex=0,math.min(palette.count,256)-1 do
			local src = palette.v[paletteIndex]
			img.buffer[0 + 4 * paletteIndex] = math.floor(src.r*255/31)
			img.buffer[1 + 4 * paletteIndex] = math.floor(src.g*255/31)
			img.buffer[2 + 4 * paletteIndex] = math.floor(src.b*255/31)
			img.buffer[3 + 4 * paletteIndex] = bit.band(paletteIndex, 0xf) > 0 and 255 or 0
		end
		palette.tex = GLTex2D{
			width = img.width,
			height = img.height,
			data = img.buffer,
			format = gl.GL_RGBA,
			internalFormat = gl.GL_RGBA8,
			type = gl.GL_UNSIGNED_BYTE,
			magFilter = gl.GL_NEAREST,
			minFilter = gl.GL_NEAREST,
			generateMipmap = false,
			wrap = {
				s = gl.GL_REPEAT,
				t = gl.GL_REPEAT,
			},
		}
		--]]
		--[[ try to upload and operate on 1555 as-is
		local img = Image(256, 1, 4, 'uint16_t')
		img:clear()
		ffi.copy(img.buffer, palette.v, math.min(palette.count,256)*2)
		palette.tex = GLTex2D{
			width = img.width,
			height = img.height,
			data = img.buffer,
			format = gl.GL_RGBA,
			internalFormat = gl.GL_RGB5_A1_OES,
			--internalFormat = gl.GL_RGB5_A1,			-- doesn't work:
			--internalFormat = gl.GL_RGB5,				-- works, but no alpha:
			--internalFormat = gl.GL_RGBA8,				-- doesn't work:
			--internalFormat = gl.GL_RGBA,				-- doesn't work:
			type = gl.GL_UNSIGNED_SHORT_1_5_5_5_REV,	-- doesn't work with RGB5_A1:
			--type = gl.GL_UNSIGNED_SHORT_5_5_5_1,		-- works with RGB5_A1, but is backwards
			magFilter = gl.GL_NEAREST,
			minFilter = gl.GL_NEAREST,
			generateMipmap = false,
			wrap = {
				s = gl.GL_REPEAT,
				t = gl.GL_REPEAT,
			},
		}
		--]]
		-- another TODO would be to use glColorTables,
		-- and that would mean putting the palette data inside glBuffers
		-- as a GL_PIXEL_UNPACK_BUFFER
		-- but then I also can't use the palette data as a texture itself
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
			tileSet.tex = glMakeU8Tex(img)
		end
	end

	for _,tilemap in ipairs(self.sm.bgTilemaps) do
		if not tilemap.tex then
			tilemap.tex = GLTex2D{
				width = tilemap.width,
				height = tilemap.height,
				data = tilemap.buffer,
				format = gl.GL_RED,
				internalFormat = gl.GL_R16,
				type = gl.GL_UNSIGNED_SHORT,
				magFilter = gl.GL_NEAREST,
				minFilter = gl.GL_NEAREST,
				generateMipmap = false,
			}
		end
	end

	if useBakedGraphicsTileTextures then
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
	end

	-- make textures of the region maps
	self.pauseScreenTileTex = self:graphicsTilesToTex(self.sm.pauseScreenTiles.v, self.sm.pauseScreenTiles:sizeof())
	self.itemTileTex = self:graphicsTilesToTex(self.sm.itemTiles.v, self.sm.itemTiles:sizeof(), 8)
	
	self.view.ortho = true
	self.view.znear = -1e+4
	self.view.zfar = 1e+4
	self.view.orthoSize = 256
	self.view.pos.x = 128
	self.view.pos.y = -128

	
	self.indexShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = [[
in vec4 vertex;
in vec2 tca;
out vec2 tcv;
uniform mat4 mvProjMat;
void main() {
	tcv = tca.xy;
	gl_Position = mvProjMat * vertex;
}
]],
		fragmentCode = [[
in vec2 tcv;
out vec4 fragColor;
uniform sampler2D tex;
uniform sampler2D paletteTex;
void main() {
	float paletteIndex = floor(texture(tex, tcv).x * 255. + .5);
	vec2 paletteTC;
	paletteTC.x = (paletteIndex + .5) / 256.;
	paletteTC.y = .5;
	fragColor = texture(paletteTex, paletteTC);
}
]],
		uniforms = {
			tex = 0,
			paletteTex = 1,
		},
	}
	self.indexShader:useNone()

if not useBakedGraphicsTileTextures then
	self.tilemapShader = GLProgram{
		version = 'latest',
		precision = 'best',
		vertexCode = [[
in vec4 vertex;
in vec2 tca;

out vec2 tcv;

uniform mat4 mvProjMat;

void main() {
	tcv = tca.xy;
	gl_Position = mvProjMat * vertex;
}
]],
		fragmentCode = [[
in vec2 tcv;

out vec4 fragColor;

uniform sampler2D tilemap;

uniform vec2 graphicsTilesTexSizeInTiles;
uniform sampler2D graphicsTiles;

uniform sampler2D paletteTex;

void main() {
	vec2 withinGraphicsTile = tcv - floor(tcv);
	
	float tileIndex = floor(texture(tilemap, tcv).r * 65535. + .5);
	
	bool flipy = false;
	if (tileIndex >= 32768.) {
		flipy = true;
		tileIndex -= 32768.;
	}
	
	bool flipx = false;
	if (tileIndex >= 16384.) {
		flipx = true;
		tileIndex -= 16384.;
	}

	float colorIndexHi = floor(tileIndex / 1024. + .5);
	tileIndex -= colorIndexHi * 1024.;

	//1) determine which subtile 8x8 graphics tile we are in
	//assume graphicsTiles is tiles of 8x8
	vec2 graphicsTC;
	graphicsTC.x = floor(mod(tileIndex, graphicsTilesTexSizeInTiles.x)) / graphicsTilesTexSizeInTiles.x;
	graphicsTC.y = floor(tileIndex / graphicsTilesTexSizeInTiles.x) / graphicsTilesTexSizeInTiles.y;
	if (flipx) withinGraphicsTile.x = 1. - withinGraphicsTile.x;
	if (flipy) withinGraphicsTile.y = 1. - withinGraphicsTile.y;
	graphicsTC += withinGraphicsTile / graphicsTilesTexSizeInTiles;
	
	float paletteIndex = floor(texture(graphicsTiles, graphicsTC).r * 255. + .5);
	fragColor.a = (paletteIndex == 0.) ? 0. : 1.;
	paletteIndex += colorIndexHi * 16.;

	//2) 
	vec2 paletteTC;
	paletteTC.x = (paletteIndex + .5) / 256.;
	paletteTC.y = .5;
	fragColor.rgb = texture(paletteTex, paletteTC).rgb;
}
]],
		uniforms = {
			tilemap = 0,
			graphicsTiles = 1,
			paletteTex = 2,
		},
	}
	self.tilemapShader:useNone()
end

-- [=[ unit quad filled geom
	self.quadGeom = GLGeometry{
		mode = gl.GL_TRIANGLE_STRIP,
		vertexes = {
			data = {
				0, 0,
				1, 0,
				0, 1,
				1, 1,
			},
			dim = 2,
			count = 4,
		},
	}

	self.drawRoomBakedSceneObj = GLSceneObject{
		program = self.indexShader,
		geometry = self.quadGeom,
	}
--]=]

-- [=[ line loop unit quad for drawing arbitrary rectangles
-- seems to no longer work with this after switching from immediate mode
-- ... despite the line width range saying it is valid ....
	self.outlineQuadGeom = GLGeometry{
		mode = gl.GL_LINE_LOOP,
		vertexes = {
			data = {
				0, 0,
				1, 0,
				1, 1,
				0, 1,
			},
			dim = 2,
			count = 4,
		},
	}

	self.outlineSceneObj = GLSceneObject{
		program = {
			version = 'latest',
			precision = 'best',
			vertexCode = [[
in vec2 vertex;
uniform vec4 bbox;	//xyzw = [x1,y1], [x2,y2]
uniform mat4 mvProjMat;
void main() {
	vec2 rvtx = vertex * (bbox.zw - bbox.xy) + bbox.xy;
	gl_Position = mvProjMat * vec4(rvtx, 0., 1.);
}
]],
			fragmentCode = [[
uniform vec4 color;
out vec4 fragColor;
void main() {
	fragColor = color;
}
]],
		},
		geometry = self.outlineQuadGeom,
	}
--]=]

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
	return glMakeU8Tex(img)
end



App.predefinedRegionOffsets = {
-- default arrangement.  too bad crateria right of wrecked ship isn't further right to fit wrecked ship in
	{
		name = 'Original',
		md5s = {
			'21f3e98df4780ee1c667b84e57d88675',		-- JU
			'3d64f89499a403d17d530388854a7da5',		-- E
			'f24904a32f1f6fc40f5be39086a7fa7c',		-- JU with some memcheck and pal bits changed
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
	{
		name = 'Super Metroid - Airy - Rev 3',
		md5s = {
			'bce01c9dbc1be915b3abdd3af63c341a',
		},
		ofs = {
			{0,0},
			{8,5},
			{-36,23},
			{52,39},
			{2,31},
			{5,6},
			{15,-18},
			{0,0},
		},
	},
--[[
what won't load?
- Redesigned 2.3
- Redesigned Axiel Edition
- Ascent
- Dependence 1.87
- Ice Metal 1.24
--]]
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

	self.indexShader:use()
	gl.glUniformMatrix4fv(self.indexShader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.view.mvProjMat.ptr)
	self.indexShader:useNone()
	if self.tilemapShader then
		self.tilemapShader:use()
		gl.glUniformMatrix4fv(self.tilemapShader.uniforms.mvProjMat.loc, 1, gl.GL_FALSE, self.view.mvProjMat.ptr)
		self.tilemapShader:useNone()
	end

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
			if editorShowRegionBorders
			or region == self.mouseOverRegion
			then
				local x1, y1 = blocksPerRoom * (region.xmin + region.ofs.x), blocksPerRoom * (region.ymin + region.ofs.y)
				local x2, y2 = blocksPerRoom * (region.xmax + region.ofs.x), blocksPerRoom * (region.ymax + region.ofs.y)
				gl.glLineWidth(4)
				self.outlineSceneObj:draw{
					mvProjMat = self.view.mvProjMat.ptr,
					color = region == self.mouseOverRegion and {1,1,1,1} or{1,0,1,1},
					bbox = {x1, -y1, x2, -y2},
				}
				gl.glLineWidth(1)
			end

			for _,m in ipairs(rooms) do
				local w = m:obj().width
				local h = m:obj().height
				
				-- in room block units
				local roomxmin = m:obj().x + region.ofs.x
				local roomymin = m:obj().y + region.ofs.y
				local roomxmax = roomxmin + w
				local roomymax = roomymin + h
				if blocksPerRoom * roomxmax >= viewxmin
				or blocksPerRoom * roomxmin <= viewxmax
				or blocksPerRoom * -roomymax >= viewymin
				or blocksPerRoom * -roomymin <= viewymax
				then
					if editorShowRoomBorders
					or m == self.mouseOverRoom
					or m == self.selectedRoom
					then
						local x1, y1 = blocksPerRoom * roomxmin, blocksPerRoom * roomymin
						local x2, y2 = blocksPerRoom * roomxmax, blocksPerRoom * roomymax
						gl.glLineWidth(4)
						self.outlineSceneObj:draw{
							mvProjMat = self.view.mvProjMat.ptr,
							color = self.mouseOverRoom == m and {1,1,1,1} or{1,1,0,1},
							bbox = {x1, -y1, x2, -y2},
						}
						gl.glLineWidth(1)				
					end

					local roomKey = bit.bor(bit.lshift(m:obj().region, 8), m:obj().index)
					local currentRoomStateIndex = self.roomCurrentRoomStates[roomKey] or 0
					local rs = m.roomStates[currentRoomStateIndex+1]
						
					local tileSet = rs.tileSet
					local roomBlockData = rs.roomBlockData
				
					-- TODO instead of finding the first, hold a current index for each room 
					local _, bg = rs.bgs:find(nil, function(bg) return bg.tilemap end)
					local bgTilemap = bg and bg.tilemap

					if tileSet
					and tileSet.tex
					and tileSet.palette
					and roomBlockData 
					then
-- TODO get the tilemap shader working and then turn this off
if useBakedGraphicsTileTextures then
						
						self.indexShader:use()
						
						local bgBmp = bgTilemap and self.sm:mapGetBitmapForTileSetAndTileMap(tileSet, bgTilemap)
						local bgTex = bgBmp and bgBmp.tex
						if bgTex then
							
							--self.drawRoomBakedSceneObj.texs[1] = bgTex
							--self.drawRoomBakedSceneObj.texs[2] = tileSet.palette.tex
							
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

										gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty1)
										gl.glVertex2f(x1, -y1)
										gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty1)
										gl.glVertex2f(x2, -y1)
										gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty2)
										gl.glVertex2f(x2, -y2)
										gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty2)
										gl.glVertex2f(x1, -y2)
									end
								end
							end
							gl.glEnd()
							
							tileSet.palette.tex:unbind(1)
							bgTex:unbind(0)
							
						end


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
												
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty1)	gl.glVertex2f(x1, -y1)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty1)	gl.glVertex2f(x2, -y1)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty2)	gl.glVertex2f(x2, -y2)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty2)	gl.glVertex2f(x1, -y2)
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
												
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty1)	gl.glVertex2f(x, -y)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty1)	gl.glVertex2f(x+1, -y)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx2, ty2)	gl.glVertex2f(x+1, -y-1)
												gl.glVertexAttrib2f(self.indexShader.attrs.tca.loc, tx1, ty2)	gl.glVertex2f(x, -y-1)
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

else -- useBakedGraphicsTileTextures 
							
						self.tilemapShader:use()
						
						local bgTilemapTex = bgTilemap and bgTilemap.tex
						if bgTilemapTex then
							
							bgTilemapTex:bind(0)
							tileSet.graphicsTileTex:bind(1)
							tileSet.palette.tex:bind(2)

							gl.glUniform2f(
								self.tilemapShader.uniforms.graphicsTilesTexSizeInTiles.loc,
								tileSet.graphicsTileTex.width,
								tileSet.graphicsTileTex.height)
							
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

										local tx1 = i * roomSizeInPixels / bgTilemapTex.width
										local ty1 = j * roomSizeInPixels / bgTilemapTex.height
										local tx2 = (i+1) * roomSizeInPixels / bgTilemapTex.width
										local ty2 = (j+1) * roomSizeInPixels / bgTilemapTex.height

										gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty1)	gl.glVertex2f(x1, -y1)
										gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty1)	gl.glVertex2f(x2, -y1)
										gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty2)	gl.glVertex2f(x2, -y2)
										gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty2)	gl.glVertex2f(x1, -y2)
									end
								end
							end
							gl.glEnd()
							
							tileSet.palette.tex:unbind(2)
							tileSet.graphicsTileTex:unbind(1)
							bgTilemapTex:unbind(0)
						end


						local tex = tileSet.tex
						tex:bind(0)
						tileSet.graphicsTileTex:bind(1)
						tileSet.palette.tex:bind(2)
						
						gl.glUniform2f(
							self.tilemapShader.uniforms.graphicsTilesTexSizeInTiles.loc,
							tileSet.graphicsTileTex.width / 8,
							tileSet.graphicsTileTex.height / 8)

						local blocks12 = roomBlockData:getBlocks12()
						local layer2blocks = roomBlockData:getLayer2Blocks()
						
						gl.glBegin(gl.GL_QUADS)
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
												
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty1)	gl.glVertex2f(x1, -y1)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty1)	gl.glVertex2f(x2, -y1)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty2)	gl.glVertex2f(x2, -y2)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty2)	gl.glVertex2f(x1, -y2)
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
												
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty1)	gl.glVertex2f(x, -y)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty1)	gl.glVertex2f(x+1, -y)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx2, ty2)	gl.glVertex2f(x+1, -y-1)
												gl.glVertexAttrib2f(self.tilemapShader.attrs.tca.loc, tx1, ty2)	gl.glVertex2f(x, -y-1)
											end
										end
									end
								end
							end
						end
						gl.glEnd()
						
						tileSet.palette.tex:unbind(2)
						tileSet.graphicsTileTex:unbind(1)
						tex:unbind(0)

						self.tilemapShader:useNone()

end -- useBakedGraphicsTileTextures
					
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
								
								if self.mouseOverDoor and door == self.mouseOverDoor.door
								or self.selectedDoor and door == self.selectedDoor.door
								then
									gl.glLineWidth(3)
								end
								gl.glColor3f(1,1, self.selectedDoor and door == self.selectedDoor.door and 0 or 1)

								if not door 
								or door.type ~= 'door_t' 
								then
									-- TODO handle lifts?
									-- are they lifts, or are they loadStation debug destinations that have no exit, only an entrance?
									
									for _,pos in ipairs(blockpos) do
										-- now for src block pos
										local x = .5 + pos[1] + blocksPerRoom * roomxmin
										local y = .5 + pos[2] + blocksPerRoom * roomymin
										gl.glBegin(gl.GL_LINES)
										gl.glVertex2f(x-.5,-y)
										gl.glVertex2f(x+.5,-y)
										gl.glVertex2f(x,-y-.5)
										gl.glVertex2f(x,-y+.5)
										gl.glEnd()
									end
								else
									local dstRoom = assert(door.destRoom)
								
									-- draw an arrow or something on the map where the door drops us off at
									-- door.destRoom is the room
									-- draw it at door:obj().screenX by door:obj().screenY
									-- and offset it according to direciton&3 and distToSpawnSamus (maybe)

									local i = door:obj().screenX
									local j = door:obj().screenY
									local dir = bit.band(door:obj().direction, 3)	-- 0-based
									local ti, tj = 0, 0	--table.unpack(doorPosForDir[dir])
										
									local k = 2
										
									-- [[
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
									--]]
									-- TODO how to deal with capX capY and distToSpawnSamus ...
									--[[
									local pi = door:obj().capX / 16
									local pj = door:obj().capY / 16
									--]]

									-- here's the pixel x & y of the door destination
									local dstregion = self.regions[dstRoom:obj().region+1]
									local x1 = pi + ti + blocksPerRoom * (i + dstRoom:obj().x + dstregion.ofs.x)
									local y1 = pj + tj + blocksPerRoom * (j + dstRoom:obj().y + dstregion.ofs.y)

									for _,pos in ipairs(blockpos) do
										-- now for src block pos
										local x2 = .5 + pos[1] + blocksPerRoom * roomxmin
										local y2 = .5 + pos[2] + blocksPerRoom * roomymin
										gl.glBegin(gl.GL_LINES)
										gl.glVertex2f(x1,-y1)
										gl.glVertex2f(x2,-y2)
										gl.glEnd()
									end
								end
								
								gl.glLineWidth(1)
							end
						end
					end
				end
			end
		end
	end

	for _,selector in ipairs{roomSelector, regionSelector, doorSelector} do
		if selector.selRectDownX and selector.selRectDownY then
			self.outlineSceneObj:draw{
				mvProjMat = self.view.mvProjMat.ptr,
				color = {1,1,0,1},
				bbox = {
					selector.selRectDownX, selector.selRectDownY,
					self.mouseViewPos.x, self.mouseViewPos.y,
				},
			}
		end
	end

	App.super.update(self)
glreport'here'
end



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


	if editorMode == editorModes.Pan then
		-- just use default orbit behavior
	elseif editorMode == editorModes.Regions then
		regionSelector:updateMouse(self)
	elseif editorMode == editorModes.Rooms then
		roomSelector:updateMouse(self)
	elseif editorMode == editorModes.Doors then
		doorSelector:updateMouse(self)
	end
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

local function radioTooltipsFromTable(names, t, k)
	for v,name in ipairs(names) do
		ig.luatableTooltipRadioButton(name, t, k, v)
		if v < #names then
			ig.igSameLine()
		end
	end
end


-- TODO make this 1-based
local function comboTooltip(name, t, k, values)
	t[k] = t[k] + 1
	local result = table.pack(ig.luatableTooltipCombo(name, t, k, values))
	t[k] = t[k] - 1
	return result:unpack()
end


function App:updateGUI()
	local sm = self.sm

	ig.luatableTooltipCheckbox('Draw Foreground', _G, 'editorDrawForeground')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Draw Layer 2 Background', _G, 'editorDrawLayer2')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Draw PLMs', _G, 'editorDrawPLMs')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Draw Enemy Spawns', _G, 'editorDrawEnemySpawnSets')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Draw Doors', _G, 'editorDrawDoors')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Hide MapBlocks Of Solid Tiles', _G, 'editorHideFilledMapBlocks')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Show Region Borders', _G, 'editorShowRegionBorders')
	ig.igSameLine()
	ig.luatableTooltipCheckbox('Show Room Borders', _G, 'editorShowRoomBorders')

	radioTooltipsFromTable(editorModes, _G, 'editorMode')

	if ig.igCollapsingHeader'Set Region Offsets To Predefined:' then
		for i,info in ipairs(self.predefinedRegionOffsets) do
			if ig.tooltipButton(info.name) then
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
		if not self.selectedRegion then self.selectedRegion = self.regions[1] end
		local tmp = {self.selectedRegion.index}
		if comboTooltip('region', tmp, 1, self.regions:mapi(function(region)
			return 'region '..region.index
		end)) then
			self.selectedRegion = self.regions[tmp[1]+1]
		end
		
		local region = self.selectedRegion
		if region then
			ig.luatableTooltipCheckbox('Show Region '..region.index, region, 'show')
			ig.luatableTooltipInputFloat('xofs', region.ofs, 'x')
			ig.luatableTooltipInputFloat('yofs', region.ofs, 'y')

			local lsr = sm.loadStationsForRegion[region.index+1]
			if not lsr then
				error("couldn't find loadStations for region "..region.index)
			end

			if not self.currentLoadStationIndex then self.currentLoadStationIndex = 0 end
			comboTooltip('loadStation', self, 'currentLoadStationIndex', lsr.stations:mapi(function(ls)
				return ('%02x:%04x'):format(frompc(ls.addr))
			end))
			
			local ls = lsr.stations[self.currentLoadStationIndex+1]
			if ls then
				if ig.igButton('door '
					..(ls.door and ('%02x:%04x'):format(frompc(ls.door.addr)) or '')
				) then
					-- redirect door
				end
				if ig.igIsItemHovered(ig.ImGuiHoveredFlags_None) 
				and ls.door
				then
					self.mouseOverDoor = {door=ls.door}
					self.mouseOverRoom = ls.door and ls.door.destRoom
				end

				for name,ctype,field in sm.loadStation_t:fielditer() do
					ig.igText(name..' = '..ls:obj():fieldToString(name,ctype))
				end
			end
		end
	end	

	if ig.igCollapsingHeader'rooms' then
		if not self.selectedRoomIndex then self.selectedRoomIndex = 0 end
		local tmp = {self.selectedRoomIndex}
		local changed = comboTooltip('room', tmp, 1, self.sm.rooms:mapi(function(room) return room:getIdentStr() end)) 
		if changed then
			self.selectedRoomIndex = tmp[1]
		end
		local room = self.sm.rooms[self.selectedRoomIndex+1]
		if room then
			for name, ctype, field in sm.Room.room_t:fielditer() do
				ig.igText(name..' = '..room:obj():fieldToString(name, ctype))
			end
		
			if ig.igCollapsingHeader'roomstates' then
				-- roomstates ...
				-- roomblocks ...
				local roomKey = bit.bor(bit.lshift(room:obj().region, 8), room:obj().index)
				self.roomCurrentRoomStates[roomKey] = self.roomCurrentRoomStates[roomKey] or 0
				comboTooltip('roomstate', self.roomCurrentRoomStates, roomKey, room.roomStates:mapi(function(roomState)
					return (('%02x:%04x'):format(frompc(roomState.addr)))
				end))

				local rs = room.roomStates[self.roomCurrentRoomStates[roomKey]+1]
				if rs then
					for name,ctype,field in sm.RoomState.roomstate_t:fielditer() do
						ig.igText(name..' = '..rs:obj():fieldToString(name,ctype))
					end
				end
			end
		end
	end

	if ig.igCollapsingHeader'tilesets' then
		self.currentTileSetIndex = self.currentTileSetIndex or 0
		comboTooltip('tileset', self, 'currentTileSetIndex', sm.tileSets:mapi(function(tileSet)
			return 'tileset '..tileSet.index
		end))
	
		local tileSet = sm.tileSets[self.currentTileSetIndex+1]
		if tileSet then
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
					tileSet.palette.count * 8, 16
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
	end
end

return App():run()
