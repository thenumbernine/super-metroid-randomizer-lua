#!/usr/bin/env luajit
	
--[[
useful pages:
http://wiki.metroidconstruction.com/doku.php?id=super:enemy:list_of_enemies
http://wiki.metroidconstruction.com/doku.php?id=super:technical_information:list_of_enemies
http://metroidconstruction.com/SMMM/
https://gamefaqs.gamespot.com/snes/588741-super-metroid/faqs/39375%22
http://deanyd.net/sm/index.php?title=List_of_rooms
--]]

local file = require 'ext.file'
local table = require 'ext.table'
local tolua = require 'ext.tolua'
local cmdline = require 'ext.cmdline'(...)

local pc = require 'pc'
local topc = pc.to
local frompc = pc.from

local tableToByteArray = require 'util'.tableToByteArray
local hexStrToByteArray = require 'util'.hexStrToByteArray

local timerIndent = 0
function timer(name, callback, ...)
	print('TIMER '..(' '):rep(timerIndent)..name..' begin...')
	timerIndent = timerIndent + 1
	local startTime = os.clock()
	local results = table.pack(callback(...))
	local endTime = os.clock()
	timerIndent = timerIndent - 1
	print('TIMER '..(' '):rep(timerIndent)..name..' done, took '..(endTime - startTime)..'s')
	return results:unpack()
end

timer('everything', function()
	function I(...) return ... end
	local ffi = require 'ffi'
	local config = require 'config'

	for k,v in pairs(cmdline) do
		if not ({
			seed=1,
			['in']=1,
			out=1,
		})[k] then
			error("got unknown cmdline argument "..k)
		end
	end

	local seed = cmdline.seed
	if seed then
		seed = tonumber(seed, 16)
	else
		seed = os.time() 
		math.randomseed(seed)
		for i=1,100 do math.random() end
		seed = math.random(0,0x7fffffff)
	end
	print('seed', ('%x'):format(seed))
	math.randomseed(seed)


	--[[
	f24904a32f1f6fc40f5be39086a7fa7c  Super Metroid (JU) [!] PAL.smc
	21f3e98df4780ee1c667b84e57d88675  Super Metroid (JU) [!].smc
	3d64f89499a403d17d530388854a7da5  Super Metroid (E) [!].smc
	
	so what version is "Metroid 3" ? if it's not JU or E?
	"Metroid 3" matches "Super Metroid (JU)" except for:
			"Metroid 3"		"Super Metroid (JU)"
	$60d	a9				89
	$60e	00				10
	<- 89 10 = BIT #$10 = set bit (this is patrickjohnston.org's)
	<- a9 00 = LDA #$00 = clear bit 

	$617	a9				89
	$618	00				10
	<- 89 10 = BIT #$10 = set bit (this is patrickjohnston.org's)
	<- a9 00 = LDA #$00 = clear bit 
	
	$6cb	ea				d0
	$6cc	ea				16
	<- ea ea = NOP NOP		<- skip the check altogether
	<- d0 16 = BNE +16		<- jump if SRAM check fails

	that's it.
	and between JU and E? a lot.
	
	so which does patrickjohnston.org use? 
	
	--]]
	local infilename = cmdline['in'] or 'Super Metroid (JU) [!].smc'
	
	local outfilename = cmdline.out or 'sm-random.smc'

	function exec(s)
		print('>'..s)
		local results = table.pack(os.execute(s))
		print('results', table.unpack(results, 1, results.n))
		return table.unpack(results, 1, results.n)
	end

	-- [[ apply patches -- do this before removing any rom header
	file.__tmp = file[infilename]
	local function applyPatch(patchfilename)
		exec('luajit ../ips/ips.lua __tmp patches/'..patchfilename..' __tmp2 show')
		file.__tmp = file.__tmp2
		file.__tmp2 = nil
	end
	
	if config.skipItemFanfare then
		applyPatch'itemsounds.ips'
	end
	
	--applyPatch'SuperMissiles.ips'	-- shoot multiple super missiles!... and it glitched the game when I shot one straight up in the air ...
	
	romstr = file.__tmp
	file.__tmp = nil
	--]]
	--[[
	local romstr = file[infilename]
	--]]


	local header = ''
	if bit.band(#romstr, 0x7fff) ~= 0 then
		print('skipping rom file header')
		header = romstr:sub(1,512)
		romstr = romstr:sub(513)
	end
	assert(bit.band(#romstr, 0x7fff) == 0, "rom is not bank-aligned")

	-- global so other files can see it
	local rom = ffi.cast('uint8_t*', romstr) 


	-- global stuff

	if config.skipIntro then 
		--applyPatch'introskip_doorflags.ips' 
		ffi.copy(rom + 0x016eda, hexStrToByteArray'1f')
		ffi.copy(rom + 0x010067, hexStrToByteArray'2200ff80')
		ffi.copy(rom + 0x007f00, hexStrToByteArray'af98097ec91f00d024afe2d77ed01eafb6d87e0904008fb6d87eafb2d87e0901008fb2d87eaf52097e22008081a900006b')
	end

	if config.beefUpXRay then
		local function write(bank, pageofs, ...)
			local addr = topc(bank, pageofs)
			for i=1,select('#', ...) do
				rom[addr+i-1] = select(i, ...)
			end
		end

-- this all works fine for making the beam bigger
--[[
		-- set max angle to nearly 180' (can't go past that, and can't get it to aim above or below the vertical half-plane.  how to get rid of the vertical limit...
		write(0x88, 0x8792, 0x3f)		-- was 0x0b
		write(0x88, 0x879a, 0x3f)		-- was 0x0a
		
		-- set angle delta to as fast as possible:
		write(0x88, 0x8770, 0xff, 0xff)

		-- x-ray acts like it is off-screen (and that makes it fill the whole screen)
		write(0x88, 0x8919, 0x11, 0xbe)
--]]
		-- or better yet, crystal flash (88:8b69) ... doesn't work, but try to figure out how to put a radius of x-ray always around you regardless of pushing 'a' button

		-- change state 0 x-ray warmup beam time, make it go straight to full...
		-- this code usually inc's the x-ray state at $7e0a7a ... i'm just going to set it to 1
		--[[
		write(0x88, 0x8747, 
			0xa9, 0x02, 0x00,		-- $88:8747	lda #$0002		\ xRayState = mem[$73:0a7a] = 2	-- skip widening state 1, go to state 2
			0x8d, 0x7a, 0x0a,		-- $88:874a	sta $0a7a		/
			0xea,					-- $88:874d	nop				
			0xea,					-- $88:874e	nop				\
			0xea,					-- $88:874f	nop				| this was a jsr to a rts ... so ...
			0xea					-- $88:8750	nop				/
			-- TODO I also have to write our x-ray max size (0x3f now) into $7e:0a84 ... soo ...
		)
		--]]
		--[[ so why not just do that with this function and jump from state 1 into state 2 ...
		write(0x88, 0x8747,
			-- jump from $8747 to $8766
			0x80, 0x1d		-- $88:8748	bra $1d
			-- and let that routine do the plp rts itself
		)
		--]]
	
-- works fine.  this makes the scope insta-full
--[[ better yet, why not change state 1 to instantly set the beam to max width?
		-- $7e:0998 = main gameplay state (might need to fix this)
		-- $7e:0a78 = time is frozen flag.  1 = x-ray active, #$8000 = samus dying / autoreserve filling
		-- $7e:0a7a = x-ray state.  0 = none, 1 = opening, 2 = full, 3..5 = closing (one state per frame)
		-- $7e:0a7c = x-ray angular width delta (when opening/closing)
		-- $7e:0a7e = x-ray angular subwidth delta (")
		-- $7e:0a80 = set to 1 when x-ray reaches max size, set to #$ffff when beam is ending
		-- $7e:0a82 = x-ray angle
		-- $7e:0a84 = x-ray angular width
		-- $7e:0a86 = x-ray angular subwidth
		-- $7e:0a88 = x-ray indirect HDMA table
		write(0x88, 0x876b,
			-- at $8766 is rep #$20 ... what is that?  something to do with register bits 8 vs 16
			-- lda #$0002	\ xRayState = mem[$7e:0a7a] = #$0002
			-- sta $0a7a	/
			-- lda #$0001	\ xRayFull = mem[$7e:0a80] = #$0001
			-- sta $0a80	/
			-- lda #$003f	\ xRayAngularWidth = mem[$7e:0a84] = #$003f = full width
			-- sta $0a84	/
			-- stz $0a86	} xRayAngularSubWidth = mem[$7e:0a86] = #$0000 = ... is subwidth needed?
			-- we can just branch straight from 0x876b to $8796
			0x80, 0x29		-- $88:876b	bra $29		-- jump to $8796
		)
--]]

		
		-- make x-ray state 2 jump to x-ray state 0 to regen the x-ray tiles?
		--  hmm, sadly, this does make the whole game stutter
		--  and this doesn't regen the tiles
		--write(0x88, 0x87bb, 0x4c, 0x44, 0x87)	-- jmp $8744


		-- make x-ray always on...
		-- freeze-time is stored at 7e:0a78, but it is used in a lot of the detection of whether x-ray is active or not, so just removing code that sets this won't make time continue -- it has side-effects
		-- actually -- fixing it always-on using zsnes causes the x-ray effect to glitch, but while you turn left and right back and forth while using x-ray, enemies will continue to move.  side effects: can't open doors, sometimes freezes.
		-- in x-ray setup stage 1:
		-- write(0x91, 0xcafd, 0x00)		-- causes freeze-ups
		-- in x-ray setup:
		-- write(0x91, 0xe218, 0x00)	-- doesn't cause freeze-ups, but doens't do anything.  
		-- looks like the 0a78 mem loc isn't just used for freezing but also for x-ray state

-- [==[ 
		-- maybe it's better to just jump past all the 'if time is frozen' (lda $0a78 bne $wherever) branches ...
		-- TODO in all these, instead of clearing the branch after LDA $whatever, just change the LDA to LDA #$0000
		-- TODO TODO the lda idea was simpler -- no need to assign dif instructions dependending on bne vs beq
		-- but the SNES says otherwise ... seems some code only works with the branch forced rather than the A reg forced. (why?)
		-- TODO this might be why the xray no longer seems to initialize upon its first press
		-- before I'm pretty sure the xray grahics would reset upon pressing x-ray button
		-- but now you just get one clean init per room, and even that seems to have its graphics off
-- [=[ I tried changing the 0x80 page branches to off into LDA's of zero , but that froze up input
		write(0x80, 0x9c8d, 0xea, 0xea)	--> bne => nop		-- write(0x80, 0x9c8a, 0xa9, 0x00, 0x00)	--> lda $0a78 => lda #$0000
		
		-- NOTICE this is needed for x-ray depress to reset blocks correctly
		-- BUT this also causes x-ray to screw up when used outside the first screen of the room
		-- "Calculate layer 2 position and BG scrolls and update BG graphics when scrolling"
		-- so maybe I can fix this layer-1 and layer-2 data somewhere else?
		--write(0x80, 0xa3ae, 0x80)		--> beq => bra		-- write(0x80, 0xa3ab, 0xa9, 0x00, 0x00)

-- NOTICE the next two can't replace the lda $0a78 ora $0a79 with two lda #$0000's ...

--not needed for graphics update on unpress
-- but one may be shooting while x-raying	
		write(0x80, 0xa532, 0x80)		-- beq => bra
-- this is lda $0a78 ora $0a79 ... soo .. needs two replaced
-- but here's the weird thing, this replacement locks all controls up.
-- does LDA set the BEQ bit?


-- not needed for graphics update on unpress
-- but one may be shooting while x-raying	
		write(0x80, 0xa73b, 0x80)		-- beq => bra
--]=]

-- [[ not needed for graphics update on unpress
-- but one may be shooting while x-raying	
		write(0x84, 0xeeae, 0xea, 0xea)	--> bne => nop		-- write(0x84, 0xeeab, 0xa9, 0x00, 0x00)

		write(0x86, 0x842f, 0xea, 0xea)	--> bne => nop		-- write(0x86, 0x842c, 0xa9, 0x00, 0x00)
--]]
--]==]
-- [==[ 

		-- hdma object handler:
		write(0x88, 0x84c4, 0xea, 0xea)	-- bne => nop
	
		-- handle x-ray scope
		-- "if time is not frozen then return" as part of deactivate beam
		--write(0x88, 0x8a29, 0xea, 0xea)	-- bne $xx => nop nop
		write(0x88, 0x8a29, 0x80)	-- bne => bra
	
		-- spawn power bomb explosion
		write(0x88, 0x8aa7, 0xea, 0xea)

		-- scrolling sky
		write(0x88, 0xadb7, 0x80)
		write(0x88, 0xadbf, 0x80)
		write(0x88, 0xafa6, 0x80)
--]==]	
-- [==[
		-- fireflea
		write(0x88, 0xb0ce, 0xea, 0xea)
		-- 
		write(0x88, 0xb3ba, 0x80)

-- [[ 
		write(0x88, 0xb4df, 0xea, 0xea)
		write(0x88, 0xc498, 0x80)
		write(0x88, 0xc593, 0xea, 0xea)
		write(0x88, 0xd9af, 0x80)
		write(0x88, 0xda55, 0x80)
		write(0x88, 0xdb44, 0x80)
		write(0x88, 0xdc7b, 0xea, 0xea)

		write(0x8f, 0xc134, 0xea, 0xea)
		write(0x8f, 0xc186, 0xea, 0xea)
--]]
--]==]

-- [[ 
		
-- [==[ needed for movement while 'a'
		write(0x90, 0xa33a, 0xea, 0xea)			-- write(0x90, 0xa337, 0xa9, 0x00, 0x00)
		write(0x90, 0xac1f, 0xea, 0xea)			-- write(0x90, 0xac1c, 0xa9, 0x00, 0x00)
		write(0x90, 0xb6b2, 0x80)				-- write(0x90, 0xb6af, 0xa9, 0x00, 0x00)
--]==]
		
		write(0x90, 0xdcfe, 0xea, 0xea)			-- write(0x90, 0xdcfb, 0xa9, 0x00, 0x00)

--[==[ causes 'a'-to-x-ray to work without x-ray selected
		write(0x90, 0xdd50, 0xea, 0xea)			-- write(0x90, 0xdd4d, 0xa9, 0x00, 0x01)	-- this "time is frozen" condition I'm having it always hit, so opposite the rest: beq => nop
		write(0x90, 0xdd50, 0x80)	
--]==]
		
		-- to get shots working instead make the x-ray handler 91:cad6 jump into the normal handler 90:b80d
--[[ 
what it is:
$90:DDC8 A5 8B       LDA $8B    [$7E:008B]  ;\
$90:DDCA 2C B6 09    BIT $09B6  [$7E:09B6]  ;} If not holding run:
$90:DDCD D0 04       BNE $04    [$DDD3]     ;/
$90:DDCF 20 0D B8    JSR $B80D  [$90:B80D]  ; HUD selection handler - nothing / power bombs
$90:DDD2 60          RTS
$90:DDD3 22 D6 CA 91 JSL $91CAD6[$91:CAD6]  ; Execute x-ray handler
$90:DDD7 60          RTS

what I want:
20 0d b8	jsr $b80d		<- nothing/power bomb handler
a5 8b		lda $8b
2c b6 09	bit $09b6
f0 04		beq g:
22 d6 ca 91	jsl $91:cad6
g:
60			rts
--]]
		write(0x90, 0xddc8,
			0x20, 0x0d, 0xb8,
			0xa5, 0x8b,
			0x2c, 0xb6, 0x09,
			0xf0, 0x04,
			0x22, 0xd6, 0xca, 0x91,
			0x60)



-- [==[ something in here is needed for samus pain animation to work while x-raying 
		write(0x90, 0xde04, 0xea, 0xea)			-- write(0x90, 0xde01, 0xa9, 0x00, 0x00)
		write(0x90, 0xdff0, 0x80)				-- write(0x90, 0xdfed, 0xa9, 0x00, 0x00)
		write(0x90, 0xe761, 0xea, 0xea)			-- write(0x90, 0xe75e, 0xa9, 0x00, 0x00)
		write(0x90, 0xe9d1, 0x80)				-- write(0x90, 0xe9d1, 0xa9, 0x00, 0x00)
		write(0x90, 0xea50, 0xea, 0xea)			-- write(0x90, 0xea4d, 0xa9, 0x00, 0x00)	-- 
--]==]

	-- [=[ something in here needed for movement while xraying ... 
	-- with this commented, i could move without x-ray, but got a lockup upon stopping x-ray
		write(0x91, 0x808d, 0xea, 0xea)			-- write(0x91, 0x808a, 0xa9, 0x00, 0x00)
		write(0x91, 0x8175, 0xea, 0xea)			-- write(0x91, 0x8172, 0xa9, 0x00, 0x00)
	
		--write(0x91, 0xcadc, 0xa9, 0x00, 0x00)	-- causes our lockups
		--write(0x91, 0xcadf, 0xea, 0xea)	-- causes our lockups
		-- why is this locking up?  it's repeatedly calling the $88:8435 "spawn x-ray HDMA object" routine
		-- maybe if I change it to "spawn HDMA object to slot X" routine at $88:8477 instead?
		--write(0x91, 0xcaef, 0x77)
		-- nope.  mind you, 8477 requires some extra stuff to be set compared to 8435
		--write(0x91, 0xcaef, 0x1b)
		-- same with 841b
		-- ok how about this, 83e2 is unused, and spawns a HDMA into a specific slot, so ... can I use that?
		-- well, gotta adjust the stack after the call, because 841b uses [s+1]+3, while 8435 uses [s+1]+1
		-- maybe i can change the x-ray HDMA instructions?
		-- instead 91:d277 going to 91:d277, have it go back to 91:d233
		--write(0x91, 0xd27d, 0xa3)	-- still locking up
		-- OK what this did?  only opens the beam a little bit, but does let the normal view scroll and follow you while the x-ray part lags behind, 
		--write(0x91, 0xd27d, 0x29)


		write(0x91, 0xdf69, 0xea, 0xea)			-- write(0x91, 0xdf66, 0xa9, 0x00, 0x00)
	--]=]
--]]

		-- x-ray setup carry clear does nothing (no opt-out of xray)
		-- is great for letting you move around during scope, but monsters are still frozen.
		-- also if you start xraying while standing still, then you go into xray mode and can't move much.
		write(0x91, 0xcaec, 0xea, 0xea)

		-- change sta to stz so we clear the freeze flag
		--  causes freeze
		--write(0x91, 0xcafe, 0x9c)	

		-- x-ray works in fireflea room
		-- TODO fire-flea is rendered all with layer 3 bg, so ... does this have to do with it?
		--write(0x91, 0xd156, 0xea, 0xea)
		-- x-ray works in all rooms (just have 91:d143 immediately return)
		write(0x91, 0xd143, 0x6b)

		write(0x91, 0xe1a8, 0xea, 0xea)	-- skip game state test for x-ray setup

		-- does what it's supposed to, lets you move with x-ray
		write(0x91, 0xe1f1, 0xea, 0xea, 0xea)	-- don't write facing right x-ray standing state
		write(0x91, 0xe1f9, 0xea, 0xea, 0xea)	-- don't write facing left x-ray standing state
		write(0x91, 0xe20c, 0xea, 0xea, 0xea)	-- don't write facing right x-ray crouching state
		write(0x91, 0xe214, 0xea, 0xea, 0xea)	-- don't write facing left x-ray crouching state

--		write(0x91, 0xe21d, 0xea, 0xea, 0xea, 0xea, 0xea, 0xea)	-- don't do mem[$0a30] = $0005

		write(0x91, 0xe231, 0xea, 0xea, 0xea, 0xea)	-- don't disable enemy projectiles
		write(0x91, 0xe235, 0xea, 0xea, 0xea, 0xea)	-- don't disable PLMs 
		write(0x91, 0xe239, 0xea, 0xea, 0xea, 0xea)	-- don't disable animated tile objects
		write(0x91, 0xe23d, 0xea, 0xea, 0xea, 0xea)	-- don't disable palette fx objects

--		write(0x91, 0xe241, 0xea, 0xea, 0xea, 0xea, 0xea, 0xea)	-- don't do mem[$0a88] = $0001
--		write(0x91, 0xe256, 0xea, 0xea, 0xea, 0xea, 0xea, 0xea)	-- don't do mem[$0a8e] = $0098

-- [[ not needed for movement while xraying
		-- if not standing then branch => always branch
		-- hmm, with this i can't morph
		--write(0x91, 0xeeac, 0x80)
		-- return if not running => nop if not running
		write(0x91, 0xeebd, 0xea)
		-- sta $0a58 after a lda #$e94f, which is the x-ray handler
		write(0x91, 0xef01, 0xea, 0xea, 0xea)
		-- sta $0a60 after a lda #$e918, which is the x-ray handler
		write(0x91, 0xef07, 0xea, 0xea, 0xea)
		-- sta $0acc after lda #$0008	<- something about timer and xray
		write(0x91, 0xef0d, 0xea, 0xea, 0xea)
		-- sta $0ad0 after lda #$0001 
		write(0x91, 0xef13, 0xea, 0xea, 0xea)
		-- stz $0ace
		write(0x91, 0xef16, 0xea, 0xea, 0xea)
		-- stz $0a68
		write(0x91, 0xef19, 0xea, 0xea, 0xea)
		-- here's $90:e918 itself ... having it jump into normal update: e913
		-- but TODO then fcaf isn't called and the xray doesn't update ... so maybe i need to jump at the end ...
		write(0x90, 0xe918, 0x80, 0xf9, 0xea)
		-- here's $90:e94f, x-ray callback of some sort, gonna try to bypass it to normal = $a337 
		-- seems to work with or without replacing this
		--write(0x90, 0xe94f, 0x4c, 0x37, 0xa3)
--]]

-- [[ this is needed for enemies to move while x-ray
		write(0xa0, 0x8697, 0xea, 0xea)		-- write(0xa0, 0x8694, 0xa9, 0x00, 0x00)
		write(0xa0, 0x903c, 0xea, 0xea)		-- write(0xa0, 0x9036, 0xa9, 0x00, 0x00)
		write(0xa0, 0x9060, 0x80)			-- write(0xa0, 0x905a, 0xa9, 0x00, 0x00)
		write(0xa0, 0x90ac, 0xea, 0xea)		-- write(0xa0, 0x90a6, 0xa9, 0x00, 0x00)
		write(0xa0, 0x9126, 0xea, 0xea)		-- write(0xa0, 0x9120, 0xa9, 0x00, 0x00)
		write(0xa0, 0x9731, 0xea, 0xea)		-- write(0xa0, 0x972b, 0xa9, 0x00, 0x00)
--]]	

		-- mother brain and pause state $0a78
		write(0xa9, 0x87a2, 0xa9, 0x00, 0x00)
		write(0xa9, 0x92af, 0xa9, 0x00, 0x00)
--]==]
	end


	-- [=[ using the ips contents of wake_zebes.ips
	-- if I skip writing the plms back then all works fine
	if config.wakeZebesEarly then
		
		--wakeZebesEarlyDoorCode = 0xe51f	-- DONT USE THIS - THIS IS WHERE SOME CERES DOOR CODE IS.  right after the last door code
		--wakeZebesEarlyDoorCode = 0xe99b	-- somewhere further out
		wakeZebesEarlyDoorCode = 0xff00		-- original location of the patch.  works.  will re-compressing the plms and tiles affect this?
		
		--patching offset 018eb4 size 0002
		--local i = 0x018eb4	-- change the far right door code to $ff00
		--rom[i] = bit.band(0xff, wakeZebesEarlyDoorCode) i=i+1
		--rom[i] = bit.band(0xff, bit.rshift(wakeZebesEarlyDoorCode, 8)) i=i+1
		
		--patching offset 07ff00 size 0015
		local data = tableToByteArray{
	--[[ this is testing whether you have morph
	-- morph is item index 26, which is in oct 032, so the 3rd bit on the offset +3 byte 
	-- so I'm guessing our item bitflags start at $7e:d86f
	-- this only exists because multiple roomStates of the first blue brinstar room have different items
	-- the morph item is only in the intro roomstate, so if you wake zebes without getting morph you'll never get it again
	-- I'm going to fix this by manually merging the two plmsets of the two roomstates below
			0xaf, 0x72, 0xd8, 0x7e,	-- LDA $7e:d872 
			0x89, 0x00, 0x04,		-- BIT #$0004
			0xf0, 0x0b, 			-- BEQ $0b (to the RTS at the end)
	--]]	
			0xaf, 0x20, 0xd8, 0x7e,	-- LDA $7e:d820
			0x09, 0x01, 0x00,		-- ORA #$0001
			0x8f, 0x20, 0xd8, 0x7e, -- STA $7e:d820
			0x60,					-- RTS
		}
		ffi.copy(rom + 0x070000 + wakeZebesEarlyDoorCode, data)
	end
	--]=]


-- [===[ skip all the randomization stuff

	-- make a single object for the representation of the ROM
	-- this way I can call stuff on it -- like making a memory map -- multiple times
	local SM = require 'sm'

	-- global for now
	timer('read ROM', function()
		sm = SM(rom, #romstr)
	end)

	-- write out unaltered stuff
	if config.mapSaveImageInformative then
		timer('write original ROM info images', function()
			sm:mapSaveImageInformative'map'
		end)
	end
	if config.mapSaveImageTextured then
		timer('write original ROM textured image', function()
			sm:mapSaveImageTextured'map'
		end)
	end
	if config.mapSaveDumpworldImage then
		timer('write original ROM output images', function()
			sm:mapSaveDumpworldImage()
		end)
	end
	if config.mapSaveGraphicsMode7 then
		timer('write original ROM map mode7 images', function()
			sm:mapSaveGraphicsMode7()
		end)
	end
	if config.mapSaveGraphicsTileSets then
		timer('write original ROM map tileset images', function()
			sm:mapSaveGraphicsTileSets()
		end)
	end
	if config.mapSaveGraphicsBGs then
		timer('write original ROM map backgrounds', function()
			sm:mapSaveGraphicsBGs()
		end)
	end
	if config.mapSaveGraphicsLayer2BGs then
		timer('write original ROM map layer 2 backgrounds', function()
			sm:mapSaveGraphicsLayer2BGs()
		end)
	end
	if config.graphicsSavePauseScreenImages then
		timer('write out pause screen images', function()
			sm:graphicsSavePauseScreenImages()
		end)
	end
	if config.samusSaveImages then
		timer('write out samus images', function()
			sm:samusSaveImages()
		end)
	end
	timer('write original ROM memory map', function()
		-- http://wiki.metroidconstruction.com/doku.php?id=super:data_maps:rom_map:bank8f
		sm:buildMemoryMap():print'memorymap.txt'
	end)

	if config.writeOutDisasm then
		timer('write out disasm', function()
			for _,bank in ipairs(table{
				0x80,	-- system routines
				0x81,	-- SRAM
				0x82,	-- top level main game routines
				0x83,	-- (data) fx and door definitions 
				0x84,	-- plms
				0x85,	-- message boxes
				0x86,	-- enemy projectiles
				0x87,	-- animated tiles
				0x88,	-- hdma
			}:append(range(0x89, 0xdf))) do
				-- you know, data could mess this up 
				local addr = topc(bank, 0x8000)
				file[('bank/%02X.txt'):format(bank)] = require 'disasm'.disasm(addr, rom+addr, 0x8000)
			end
		end)
	end

	--[[
	for verificaiton: there is one plm per item throughout the game
	however some rooms have multiple room states where some roomstates have items and some don't 
	... however if ever multiple roomStates have items, they are always stored in the same plmset
	and in the case that different roomStates have different items (like the first blue brinstar room, intro roomState has morph, gameplay roomState has powerbomb)
	 there is still no duplicating those roomStates.

	but here's the problem: a few rooms have roomStates where the item comes and goes
	for example, the first blue brinstar room, where the item is morph the first time and powerbomb the second time.
	how can we get around this ...
	one easy way: merge those two plmsets
	how often do we have to merge separate plmsets if we only want to consolidate all items?
		
		this is safe, the item appears after wake-zebes:
	00/13 = Crateria former mother brain room, one plmset has nothing, the other has a missile (and space pirates)
		idk when these happen but they are safe
	00/15 = Crateria chozo boss, there is a state where there is no bomb item ... 
	00/1f = Crateria first missiles after bombs, has a state without the item
		
	!!!! here is the one problem child:
	01/0e = Brinstar first blue room.  one state has morph, the other has powerbombs (behind the powerbomb wall).
		
		these are safe, the items come back when triggered after killing Phantoon:
	03/00 = Wrecked Ship, reserve + missile in one state, not in the other
	03/03 = Wrecked Ship, missile in one state, not in the other
	03/07 = Wrecked Ship, energy in one state, not in the other (water / chozo holding energy?)
	03/0c = Wrecked Ship, super missile in one state, not in the other
	03/0d = Wrecked Ship, super missile in one state, not in the other
	03/0e = Wrecked Ship, gravty in one state, not in the other

	So how do we work around this, keeping a 1-1 copy of all items while not letting the player enter a game state where they can't get an essential item?
	By merging the two roomstates of 01/0e together.
	What do we have to do in order to merge them?
	the two roomstate_t's differ...
	- musicTrack: normal has 09, intro has 06
	- musicControl: normal has 05, intro has 07
	- fx1: normal has 81f4, intro has 8290
	- enemySpawn: normal has 9478, intro has 94fb
	- enemySet: normal has 83b5, intro has 83d1
	- plm: normal has 86c3, intro has 8666 (stupid evil intro plmset that's what screwed everything up ... this is the one i will delete)
	- layerHandling: normal has 91bc, intro has 91d5
	the two plmsets differ...
	- only normal has:
	   plm_t: door_grey_left: {cmd=c848, x=01, y=26, args=0c31}
	   plm_t: item_powerbomb: {cmd=eee3, x=28, y=2a, args=001a}
	- only intro has:
	   plm_t: item_morph: {cmd=ef23, x=45, y=29, args=0019}
	--]]
	-- [[
	if config.wakeZebesEarly then
		local m = assert(sm:mapFindRoom(1, 0x0e))
		assert(#m.roomStates == 2)
		local rsNormal = m.roomStates[1]
		local rsIntro = m.roomStates[2]
		rsIntro.obj.musicTrack = rsNormal.obj.musicTrack
		rsIntro.obj.musicControl = rsNormal.obj.musicControl
	-- the security cameras stay there, and if I update these then their palette gets messed up
	-- but changing this - only for the first time you visit the room - will remove the big sidehoppers from behind the powerbomb wall 
	-- however there's no way to get morph + powerbomb all in one go for the first time you're in the room, so I think I'll leave it this way for now
	--	rsIntro.obj.fx1PageOffset = rsNormal.obj.fx1PageOffset
	--	rsIntro.obj.enemySpawnPageOffset = rsNormal.obj.enemySpawnPageOffset
	--	rsIntro.obj.enemySet = rsNormal.obj.enemySet
		rsIntro.obj.layerHandlingPageOffset = rsNormal.obj.layerHandlingPageOffset
		local rsIntroPLMSet = rsIntro.plmset
		rsIntro:setPLMSet(rsNormal.plmset)
		-- TODO remove the rsIntroPLMSet from the list of all PLMSets
		--  notice that, if you do this, you have to reindex all the items plmsetIndexes
		--  also, if you don't do this, then the map write will automatically do it for you, so no worries
		-- now add those last plms into the new plm set
		local lastIntroPLM = rsIntroPLMSet.plms:remove()
		assert(lastIntroPLM.cmd == sm.plmCmdValueForName.item_morph)
		rsNormal.plmset.plms:insert(lastIntroPLM)
		-- and finally, adjust the item randomizer plm indexes and sets
		local _, morphBallItem = sm.items:find(nil, function(item)
			return item.name == 'Morphing Ball'
		end)
		assert(morphBallItem)
		morphBallItem.plmsetIndex = 56	-- same as blue brinstar powerbomb item
		morphBallItem.plmIndex = 19		-- one past the powerbomb
	end
	--]]



	-- [[ manually change the wake condition instead of using the wake_zebes.ips patch
	-- hmm sometimes it is only waking up the brinstar rooms, but not the crateria rooms (intro items were super x2, power x1, etank x2, speed)
	-- it seems Crateria won't wake up until you get your first missile tank ...
	if config.wakeZebesEarly then
		--[=[ 00/00 = first room ... doesn't seem to work
		-- maybe this has to be set only after the player walks through old mother brain room?
		local m = sm:mapFindRoom(0, 0x00)
		for _,door in ipairs(m.doors) do
			door.code = assert(wakeZebesEarlyDoorCode)
		end
		--]=]
		-- [=[ change the lift going down into blue brinstar
		-- hmm, in all cases it seems the change doesn't happen until after you leave the next room
		local m = sm:mapFindRoom(0, 0x14)
		assert(m.doors[2].addr == 0x8b9e)
		m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
		--]=]
		--[=[ 01/0e = blue brinstar first room
		locla m = sm:mapFindRoom(1, 0x0e)
		m.doors[2].ptr.code = assert(wakeZebesEarlyDoorCode)
		--]=]
	end
	--]]

	-- also (only for wake zebes early?) open the grey door from old mother brain so you don't need morph to get back?
	if config.removeGreyDoorInOldMotherBrainRoom then
		local m = sm:mapFindRoom(0, 0x13)
		local rs = m.roomStates[2]	-- sleeping old mother brain
		local plmset = rs.plmset
		local plm = plmset.plms:remove(4)		-- remove the grey door
		assert(plm.cmd == sm.plmCmdValueForName.door_grey_left)
	end


	-- also while I'm here, lets remove the unfinished/unused rooms
	-- notice, when using recursive room building, this skips them anyways
	if config.removeUnusedRooms then
		timer('removing unused rooms', function()
			sm:mapRemoveRoom(sm:mapFindRoom(2, 0x3d))
			sm:mapRemoveRoom(sm:mapFindRoom(7, 0x00))
		end)
	end

	--[[ redirect our doors to cut out the toned-down rooms (like the horseshoe shaped room before springball)
	local merging424and425 = true
	do
		local m4_24 = assert(sm:mapFindRoom(4, 0x24))
		local m4_25 = assert(sm:mapFindRoom(4, 0x25))
		local m4_30 = assert(sm:mapFindRoom(4, 0x30))
		
		-- clear the code on the door in 04/24 that points back to itself?
		local door = assert(m4_24:findDoorTo(m4_24))
		local doorToSelfDoorCode = door.ptr.code
		door.ptr.code = 0
		
		local door = assert(m4_24:findDoorTo(m4_24))
		door.ptr.code = 0
		
		for _,m in ipairs{m4_24, m4_30} do
			-- find the door that points to 4/25, redirect it to 4/24
			local door = assert(m:findDoorTo(m4_25))
			door:setDestRoom(m4_24)
	--		door.ptr.code = doorToSelfDoorCode -- this is in the other door that points to itself in this room
			door.ptr.code = 0
			if m == m4_24 then
				assert(door.ptr.screenX == 0)
				assert(door.ptr.screenY == 2)
				door.ptr.screenX = 1
				door.ptr.screenY = 3
				assert(door.ptr.capY == 0x26)
				door.ptr.capY = 0x36
			elseif m == m4_30 then
				assert(door.ptr.screenX == 0)
				assert(door.ptr.screenY == 1)
				door.ptr.screenX = 1
				door.ptr.screenY = 2
			else
				error'here'
			end
		end

		-- change the scroll data of the room from 0 to 1?
		-- if you leave all original then walking through the door from 0,3 to 1,3 messes up the scroll effect
		-- if you change the starting room to 0 then walking into 0,3 messes up the scroll effect
		-- if you set 0,3 to 1 then it works, but you can see the room that you're walking into.
		-- (maybe I should make the door somehow fix the scrolldata when you walk through it?) 
		for _,rs in ipairs(m4_24.roomStates) do
			rs.scrollData[1+1+2*2] = 2
			rs.scrollData[1+1+2*3] = 1
		end
		
		-- and now remove 04/25
		sm:mapRemoveRoom(m4_25)
	end
	--]]

	if config.fillInOOBMapBlocksWithSolid then
		timer('filling in OOB map blocks with solid', function()
			-- also for the sake of the item randomizer, lets fill in some of those empty room regions with solid
			local fillSolidInfo = table{
				--[[
				-- TODO this isn't so straightforward.  looks like filling in the elevators makes them break. 
				-- I might have to just excise regions from the item-scavenger instead
				{1, 0x00, 0,0,16,32+6},			-- brinstar left elevator to crateria.  another option is to make these hollow ...
				{1, 0x0e, 16*5, 0, 16, 32+2},	-- brinstar middle elevator to crateria
				{1, 0x24, 0,0,16,32+6},			-- brinstar right elevator to crateria.
				{1, 0x34, 0,16,16,16},			-- brinstar elevator to norfair / entrance to kraid
				{2, 0x03, 0,0,16,32},			-- brinstar elevator to norfair
				{2, 0x26, 0,16-6,16,6},			-- norfair elevator to lower norfair
				{2, 0x36, 64,0,16,32+6},		-- norfair elevator to lower norfair
				{4, 0x18, 0, 0, 16, 10*16},		-- maridia pipe room
				{5, 0x00, 0,0,16,32},			-- tourian elevator shaft
				--]]
				
				{0, 0x00, 0,0,16,32},			-- crateria first room empty regions
				{0, 0x00, 0,48,16,16},			-- "
				
				{0, 0x1c, 0,7*16-5,16,5},		-- crateria bottom of green pirate room 

				{1, 0x18, 0,16-3,16,3},			-- brinstar first missile room

				{2, 0x48, 2, 3*16-4, 1,1},		-- return from lower norfair spade room
				{2, 0x48, 16-2, 3*16-4, 1,1},	-- "

				{4, 0x04, 29, 11, 3, 3},		-- maridia big room - under top door pillars
				{4, 0x08, 1, 11, 3, 4},			-- maridia next big room - under top door pillars
				{4, 0x08, 5, 13, 1, 4},			-- "
				{4, 0x08, 5*16, 2*16, 16,16},	-- maridia next big room - debug area not fully developed
				{4, 0x0b, 16, 0, 16, 16},		-- maridia top left room to missile and super
				{4, 0x0e, 1,16+3,1,2},			-- maridia crab room before refill
				{4, 0x0e, 14,16+3,1,2},			-- "
				{4, 0x0e, 1,16+11,1,2},			-- "
				{4, 0x0e, 14,16+11,1,2},		-- "
				{4, 0x1a, 4*16-4, 16-5, 4, 4},	-- maridia first sand area pillars under door on right side 
				{4, 0x1b, 0, 32-5, 16, 4},		-- maridia green pipe in the middle pillars underneath
				{4, 0x1c, 0, 16-5, 4, 4},		-- maridia second sand area pillars under door on left side 
				{4, 0x1c, 3*16-4, 16-5, 4, 4},	-- maridia second sand area pillars under door on right side 
				{4, 0x24, 0, 64-5, 4, 4},		-- maridia lower right sand area
				{4, 0x24, 16-4, 64-5, 8, 4},	-- "
				{4, 0x24, 32-4, 64-5, 4, 4},	-- "
				{4, 0x26, 0, 32-5, 32, 5},		-- maridia spring ball room
			} 
			if not merging424and425 then
				fillSolidInfo:append{
					{4, 0x25, 0, 48-5, 4, 4},		-- you could merge this room into the previous 
					{4, 0x25, 16-4, 48-5, 4, 4},	-- "
				}
			end
			for _,info in ipairs(fillSolidInfo) do
				local region, index, x1,y1,w,h = table.unpack(info)
				local m = assert(sm:mapFindRoom(region, index))
				local roomBlockData = m.roomStates[1].roomBlockData	-- TODO assert all roomStates have matching rooms?
				local blocks12 = roomBlockData:getBlocks12()
				for j=0,h-1 do
					local y = y1 + j
					assert(y >= 0 and y < roomBlockData.height)
					for i=0,w-1 do
						local x = x1 + i
						assert(x >= 0 and x < roomBlockData.width)
						local bi = 1 + 2 * (x + roomBlockData.width * y)
						blocks12[bi] = bit.bor(bit.band(blocks12[bi], 0x0f), 0x80)
					end
				end
			end
		end)
	end

	-- randomize rooms?  still working on this
	-- *) enemy placement
	-- *) door placement
	-- *) item placement
	-- *) refinancin

	-- do the enemy field randomization
	if config.randomizeEnemies then
		timer('randomizing enemies', function()
			require 'enemies'
		end)
	end

	if config.randomizeWeapons then
		timer('randomizing weapons', function()
			require 'weapons'
		end)
	end

	-- this is just my testbed for map modification code
	--require 'rooms'

	if config.randomizeDoors then
		timer('randomizing doors', function()
			require 'doors'	-- still experimental.  this just adds colored doors, but doesn't test for playability.
		end)
	end

	if config.randomizeItems then
		timer('randomizing items', function()
			require 'items'
		end)
	end

	if config.randomizeItemsScavengerHunt then
		timer('applying item-scavenger', function()
			require 'item-scavenger'
		end)
	end

	if config.mapRecompress then
		timer('write map changes to ROM', function()
			-- write back changes
			sm:mapWrite()
		end)
	end
	
	-- write out altered stuff
	sm:print()
	
	-- TODO split this into writing the info map, the mask map, and the textured map
	-- I don't need a new textured map (unless I'm changin textures)
	--  but the other two are very useful in navigating the randomized map
	-- TODO FIXME remember the bmps are cached from the previous write of unmodified data, so 
	if config.writeOutModifiedMapImage then
		timer('write modified ROM output image', function()
			sm:mapSaveImageInformative'map-random'
		end)
	end
	
	timer('write modified ROM memory map', function()
		sm:buildMemoryMap():print()
	end)
--]===]

	-- write back out
	file[outfilename] = header .. ffi.string(rom, #romstr)

	print('done converting '..infilename..' => '..outfilename)

	if not config.randomizeEnemies then
		print()
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
		print'!!!!!!!!!!! NOT RANDOMIZING ENEMIES !!!!!!!!!'
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	end
	if not config.randomizeItems and not config.randomizeItemsScavengerHunt then
		print()
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
		print'!!!!!!!!!!! NOT RANDOMIZING ITEMS !!!!!!!!!!!'
		print'!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
	end
	print()
end)
