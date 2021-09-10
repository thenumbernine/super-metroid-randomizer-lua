local ffi = require 'ffi'
local class = require 'ext.class'

local topc = require 'pc'.to

local Patches = class()

function Patches:init(rom)
	self.rom = rom
end

function Patches:write(bank, pageofs, ...)
	local addr = topc(bank, pageofs)
	for i=1,select('#', ...) do
		self.rom[addr+i-1] = select(i, ...)
	end
end

function Patches:skipIntro()
	-- 82:eed9: LDA #$001e => LDA #$001f
	self:write(0x82, 0xeeda, 0x1f)

	-- loading game:
	-- 82:8067; JSL $a09784 (immediate RTL)
	--   		=> JSL $80ff00 (to be provided)
	self:write(0x82, 0x8067,
		0x22, 0x00, 0xff, 0x80)

	--[[
	$80:cd8e..ffbf is free space
	$80:ffc0 is the ROM header
	this is writing 0x31 bytes to 0xff00, so it won't overwrite the ROM header
	--]]
	self:write(0x80, 0xff00,
--	$80:FF00 AF 98 09 7E LDA $7E:0998
		0xaf, 0x98, 0x09, 0x7e,
--	$80:FF04 C9 1F 00    CMP #$001F
		0xc9, 0x1f, 0x00,
--	$80:FF07 D0 24       BNE $7F2D
		0xd0, 0x24,
--	$80:FF09 AF E2 D7 7E LDA $7E:D7E2
		0xaf, 0xe2, 0xd7, 0x7e,
--	$80:FF0D D0 1E       BNE $7F2D
		0xd0, 0x1e,
--	$80:FF0F AF B6 D8 7E LDA $7E:D8B6
		0xaf, 0xb6, 0xd8, 0x7e,
--	$80:FF13 09 04 00    ORA #$0004
		0x09, 0x04, 0x00,
--	$80:FF16 8F B6 D8 7E STA $7E:D8B6
		0x8f, 0xb6, 0xd8, 0x7e,
--	$80:FF1A AF B2 D8 7E LDA $7E:D8B2
		0xaf, 0xb2, 0xd8, 0x7e,
--	$80:FF1E 09 01 00    ORA #$0001
		0x09, 0x01, 0x00,
--	$80:FF21 8F B2 D8 7E STA $7E:D8B2
		0x8f, 0xb2, 0xd8, 0x7e,
--	$80:FF25 AF 52 09 7E LDA $7E:0952
		0xaf, 0x52, 0x09, 0x7e,
--	$80:FF29 22 00 80 81 JSR $81:8000
		0x22, 0x00, 0x80, 0x81,
--	$80:FF2D A9 00 00    LDA #$0000
		0xa9, 0x00, 0x00,
--	$80:FF30 6B          RTL
		0x6b
	)
end

--[[
this is a WIP that I'm doing just for educational reasons
--]]
function Patches:beefUpXRay()
	local function write(...) return self:write(...) end

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
function Patches:wakeZebesEarly()
	local rom = self.rom

	--wakeZebesEarlyDoorCode = 0xe51f	-- DONT USE THIS - THIS IS WHERE SOME CERES DOOR CODE IS.  right after the last door code
	--wakeZebesEarlyDoorCode = 0xe99b	-- somewhere further out
	
	--[[
	original location of the patch.  works.
	will re-compressing the plms and tiles affect this?
	yeah probably since this is marked as "free space" in the room/door bank.
	--]]
	wakeZebesEarlyDoorCode = 0xff00		
	
	--patching offset 018eb4 size 0002
	--local i = 0x018eb4	-- change the far right door code to $ff00
	--rom[i] = bit.band(0xff, wakeZebesEarlyDoorCode) i=i+1
	--rom[i] = bit.band(0xff, bit.rshift(wakeZebesEarlyDoorCode, 8)) i=i+1
	
	--patching offset 07ff00 size 0015
	self:write(0x8f, wakeZebesEarlyDoorCode, 
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
		0x60					-- RTS
	)
	
	-- NOTICE run.lua does some writing with this later
	self.wakeZebesEarlyDoorCode = wakeZebesEarlyDoorCode 
end
--]=]

function Patches:skipItemFanfare()
	local rom = self.rom
	
	self:write(0x82, 0xe126, 0x22, 0xd3, 0xef, 0x84, 0x80, 0x08)
	
	self:write(0x84, 0x8bf2, 0x20, 0xf0, 0xef)
	self:write(0x84, 0xe0b3, 0x09, 0xf0, 0x01)
	self:write(0x84, 0xe0d8, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe0fd, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe122, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe14f, 0x09, 0xf0, 0x07)
	self:write(0x84, 0xe17d, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe1ab, 0x11, 0xf0, 0x0a)
	self:write(0x84, 0xe1d9, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xe207, 0x11, 0xf0, 0x0f)
	self:write(0x84, 0xe235, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe263, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe291, 0x11, 0xf0, 0x04)
	self:write(0x84, 0xe2c3, 0xfe, 0xef)
	self:write(0x84, 0xe2f8, 0x09, 0xf0, 0x0f)
	self:write(0x84, 0xe32d, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe35a, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe388, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe3b5, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xe3e3, 0x09, 0xf0, 0x0b)
	self:write(0x84, 0xe411, 0xfe, 0xef)
	self:write(0x84, 0xe43f, 0x09, 0xf0, 0x01)
	self:write(0x84, 0xe46f, 0x09, 0xf0, 0x01)
	self:write(0x84, 0xe4a1, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe4d3, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe505, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe53f, 0x09, 0xf0, 0x07)
	self:write(0x84, 0xe57a, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe5b5, 0x11, 0xf0, 0x0a)
	self:write(0x84, 0xe5f0, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xe62b, 0x11, 0xf0, 0x0f)
	self:write(0x84, 0xe66f, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe6aa, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe6e5, 0x11, 0xf0, 0x04)
	self:write(0x84, 0xe720, 0xfe, 0xef)
	self:write(0x84, 0xe762, 0x09, 0xf0, 0x0f)
	self:write(0x84, 0xe7a4, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe7de, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xe819, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe853, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xe88e, 0x09, 0xf0, 0x0b)
	self:write(0x84, 0xe8c9, 0xfe, 0xef)
	self:write(0x84, 0xe904, 0x09, 0xf0, 0x01)
	self:write(0x84, 0xe93a, 0x09, 0xf0, 0x01)
	self:write(0x84, 0xe972, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe9aa, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xe9e2, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xea22, 0x09, 0xf0, 0x07)
	self:write(0x84, 0xea63, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xeaa4, 0x11, 0xf0, 0x0a)
	self:write(0x84, 0xeae5, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xeb26, 0x11, 0xf0, 0x0f)
	self:write(0x84, 0xeb67, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xeba8, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xebe9, 0x11, 0xf0, 0x04)
	self:write(0x84, 0xec2a, 0xfe, 0xef)
	self:write(0x84, 0xec72, 0x09, 0xf0, 0x0f)
	self:write(0x84, 0xecba, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xecfa, 0x09, 0xf0, 0x26)
	self:write(0x84, 0xed3b, 0xfe, 0xef, 0x37)
	self:write(0x84, 0xed7b, 0xfe, 0xef, 0x2a)
	self:write(0x84, 0xedbc, 0x09, 0xf0, 0x0b)
	self:write(0x84, 0xedfd, 0xfe, 0xef)
	self:write(0x84, 0xee3e, 0x09, 0xf0, 0x01)
	-- this is the free space at the end of bank $84
	self:write(0x84, 0xefd3, 0xad, 0xd7, 0x05, 0xc9, 0x02, 0x00, 0xf0, 0x0e, 0xa9, 0x00, 0x00, 0x22, 0xf7, 0x8f, 0x80, 0xad, 0xf5, 0x07, 0x22, 0xc1, 0x8f, 0x80, 0xa9, 0x00, 0x00, 0x8d, 0xd7, 0x05, 0x6b, 0xa9, 0x01, 0x00, 0x8d, 0xd7, 0x05, 0x22, 0x17, 0xbe, 0x82, 0xa9, 0x00, 0x00, 0x60, 0x20, 0x19, 0xf0, 0x29, 0xff, 0x00, 0x22, 0x49, 0x90, 0x80, 0x60, 0x20, 0x19, 0xf0, 0x22, 0xcb, 0x90, 0x80, 0x60, 0x20, 0x19, 0xf0, 0x22, 0x4d, 0x91, 0x80, 0x60, 0xa9, 0x02, 0x00, 0x8d, 0xd7, 0x05, 0xb9, 0x00, 0x00, 0xc8, 0x60)
	
	self:write(0x85, 0x8089, 0x80, 0x02)
	self:write(0x85, 0x8491, 0x20, 0x00)
end

return Patches
