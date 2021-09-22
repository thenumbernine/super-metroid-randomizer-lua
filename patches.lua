local ffi = require 'ffi'
local class = require 'ext.class'
local table = require 'ext.table'

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

the goal is:
1) x-ray doesn't freeze the game (80%)
2) x-ray always on (50%)
3) change x-ray shape (0%)

ok a breakdown of calls:

90:C4B5 = handle switching HUD selection
+-	90:C5AE = switched to HUD item handler - x-ray ... clear charge vars, clear carry on success

90:DD3D = standard HUD selection handler
+-	90:DDC8 = hud selection handler - xray
	+-	90:B80D = hud selection handler - nothing / power bombs
	+-	91:CAD6 = x-ray handler
		+-	91:E16D = x-ray setup ... clc means already running and no need to spawn HDMA for x-ray
		+-	88:8435 = spawn x-ray HDMA, pass it values: $41, $28, $D223

90:DD3D has some weird code to it at DD4D-DD55: "if time is frozen, execute x-ray handler"
... but the pointers to each HUD handler jsr are at DD61  
... why not just call whatever we are selected on?
... and that seems to be th default branch at DD57-DD5B: "execute handler for current HUD selection", whih the specifically-handle x-ray handler skips
....soooo....
if we just remove that x-ray-specific block, will x-ray always run?

91:D223 = HDMA object instruction list - x-ray ... time to read up on how the HDMA object handler works
here's some gleaned addresses ... are they run once per frame or something?
... 91:D27F = pre-instruction - x-ray - init
... 91:CAF9 = x-ray setup stage 1
... 91:CB1C = x-ray setup stage 2
... 91:CB57 = x-ray setup stage 3
... 91:CB8E = x-ray setup stage 4
... 91:D0D3 = x-ray setup stage 5
... 91:D173 = x-ray setup stage 6
... 91:D1A0 = x-ray setup stage 7
... 91:D2BC = x-ray setup stage 8
... 88:86EF = pre-instruction - x-ray - main
... then goto 91:D277 , which is the previous pre-instruction call 

91:D27F = pre-instruction - x-ray - init
+-	check FX room type to fireflea room type
+-	91:D143 = can x-ray show blocks?
+-	if we can show blocks then set the subscreen backdrop color ... some kind of fade in maybe? idk.
+-	random fact, the fireflea stuff is tacked after the RTL, but branches back to the RTL when it's done

	91:D143 = check if x-ray should show any blocks
	+-	does a few compares.  zero is set if we can't show blocks, zero is cleared if we can. 

91:CAF9 = x-ray setup stage 1 - freeze time and backup BG2 registers
+-	freeze time
+-	backup BG2 X scroll, Y scroll, address, and size

91:CB1C = x-ray setup stage 2 - read BG1 tilemap - 2nd screen
+-	queue transfer of 800h bytes from vram BG1 tilemap base + 400h to $7E:6800
$91:CB1C 08          PHP						} push(processorFlags)
$91:CB1D C2 30       REP #$30					} processorFlags &= ~0x30
$91:CB1F AE 60 03    LDX $0360  [$7E:0360]		\
$91:CB22 A5 58       LDA $58    [$7E:0058]		| auto v = (VRAMReadTableEntry_t*)((uint8_t*)VRAMReadTable + *VRAMReadStackOffset)
$91:CB24 29 FC 00    AND #$00FC					|   
$91:CB27 EB          XBA						|
$91:CB28 18          CLC						|
$91:CB29 69 00 04    ADC #$0400					|
$91:CB2C 9D 40 03    STA $0340,x[$7E:0340]		/ v->srcAddr = BG1TilemapBaseAddrAndSize->base << 8 + 0x400
$91:CB2F A9 81 00    LDA #$0081					\
$91:CB32 9D 42 03    STA $0342,x[$7E:0342]		/ v->DMAControl = 0x81
$91:CB35 A9 39 00    LDA #$0039					\
$91:CB38 9D 43 03    STA $0343,x[$7E:0343]		/ v->DMATarget = 0x39
$91:CB3B A9 00 68    LDA #$6800					\ v->destAddr24 = add24_t{
$91:CB3E 9D 44 03    STA $0344,x[$7E:0344]		|	.bank = 0x7E,
$91:CB41 A9 7E 00    LDA #$007E					|	.ofs = 0x6800,
$91:CB44 9D 46 03    STA $0346,x[$7E:0346]		/ }
$91:CB47 A9 00 08    LDA #$0800					\
$91:CB4A 9D 47 03    STA $0347,x[$7E:0347]		/ v->size = 0x800
$91:CB4D 8A          TXA						\
$91:CB4E 18          CLC						|
$91:CB4F 69 09 00    ADC #$0009					|
$91:CB52 8D 60 03    STA $0360  [$7E:0360]		/ *VRAMReadStackOffset += 9 // == sizeof(VRAMReadTableEntry_t)
$91:CB55 28          PLP						} pop(processorFlags)
$91:CB56 6B          RTL						} return //from long jump


91:CB57 = x-ray setup stage 3 - read BG1 tilemap - 1st screen
+-	queue transfer of 800h bytes from VRAM BG1 tilemap base to $7E:6000

91:CB8E = x-ray setup stage 4
+-	some kind of loop over all blocks or something
	+-	91:CCF1
		+-	load and store some variables
+-	some other loop
	+-	91:CD42
		+-	91:CDD6 = handle x-rayed block
+-	some other loop
	+-	91:CDBE
		+-	91:CDD6 = handle x-rayed block
		+-	JMP to 91:CF36
		+-	91:CFBF
			+- ...
		+-	JMP back to CDCB
	+-	84:831A = load x-ray blocks
		
	84:831A = load x-ray blocks
	+-	cycle through PLMs and change x-ray blocks
	+-	80:818E = see if this item (based on PLM arg?) has been picked up
	+-	84:8290 = calculate PLM block coordinate
	+-	91:D04C = load blocks to x-ray tilemap
		+-	if block screen X < 1 then return 
		+-	if block screen X >= 10h then return 
		+-	if block screen Y < 1 then return
		+-	if block screen Y >= 10h then return
		+-	accum = mem16[7E:0028] is the current tile index of what we are drawing
		+-	if tile index & 0800h == 0 then then block is not flipped vertically so call ...
		+-	91:CFC1 = copy individual block to x-ray tilemaps (accum is the tileIndex)
			+-	does some reading and writing to mem locations
		+- 	else call ...
		+-	91:D0A6
			+-	likewise
	... and then at the end of the function is drawing instructions per block type.  these are sets of 3 uint16_t's that must be passed to one of the called functions:
	A30F = 0001, B08E, 0000 \
	A31B = 0001, B090, 0000 |
	A327 = 0001, B092, 0000 } Misc. items in loaded order
	A333 = 0001, B094, 0000 /
	A2DF = 0001, B04A, 0000 Energy tank
	A2F1 = 0001, B04D, 0000 Missile tank
	A2FD = 0001, B04F, 0000 Super missile tank
	A303 = 0001, B050, 0000 Power bomb tank

	91:CDD6 = handle x-rayed block

91:CFC1 = copy x-ray block to vram
{
$91:CFC1 0A          ASL A						\ uint16_t tileIndex = accum; // function argument
$91:CFC2 0A          ASL A						| uint16_t tileOffset = tileIndex * sizeof(tileBlock_t) // i.e. << 3 
$91:CFC3 0A          ASL A						| memcpy(XRayTilemapViewableBG1 + tileOffset, tileTable + tileOffset, sizeof(tileBlock_t))
$91:CFC4 AA          TAX						/ ... or, the long spelled out way ...
$91:CFC5 BF 00 A0 7E LDA $7EA000,x[$7E:A7F8]	\
$91:CFC9 48          PHA						/ uint16_t tmp3 = mem16[0x7EA000 + tileOffset];
$91:CFCA BF 02 A0 7E LDA $7EA002,x[$7E:A7FA]	\ 
$91:CFCE 48          PHA						/ uint16_t tmp4 = mem16[0x7EA002 + tileOffset];
$91:CFCF BF 04 A0 7E LDA $7EA004,x[$7E:A7FC]	\ 
$91:CFD3 48          PHA						/ uint16_t tmp5 = mem16[0x7EA004 + tileOffset];
$91:CFD4 BF 06 A0 7E LDA $7EA006,x[$7E:A7FE]	\
$91:CFD8 A6 16       LDX $16    [$7E:0016]		| uint16_t tmp2 = mem16[0x7E0016]
$91:CFDA 9F 42 40 7E STA $7E4042,x[$7E:4042]	/ mem16[0x7E4042 + tmp2] = mem16[0x7EA006 + tileOffset];
$91:CFDE 68          PLA						\ 
$91:CFDF 9F 40 40 7E STA $7E4040,x[$7E:4040]	/ mem16[0x7E4040 + tmp2] = tmp5;
$91:CFE3 68          PLA						\
$91:CFE4 9F 02 40 7E STA $7E4002,x[$7E:4002]	/ mem16[0x7E4002 + tmp2] = tmp4;
$91:CFE8 68          PLA						\
$91:CFE9 9F 00 40 7E STA $7E4000,x[$7E:4000]	/ mem16[0x7E4000 + tmp2] = tmp3;
$91:CFED 60          RTS						return;
}

91:D0D3 = x-ray setup stage 5
+-	91:D143 = can x-ray show blocks.  if we can ....
+-	set BG1 x scroll
+-	set BG1 y scroll
+-	set BG2 X scroll
+-	set BG2 Y scroll
+-	BG2TilemapBaseAddrAndSize->width64 = true		//  set BG2 tilemap size ... to 64x32
+-	BG2TilemapBaseAddrAndSize->height64 = false
+-	BG2TilemapBaseAddrAndSize->base = 0x12 = 0x4800/0x400	// set BG2 tilemap address ... to 7E:4800 (the x-ray tilemaps)
+-											
+-	if we can't ... queue transfer of 800h bytes from VRAM BG2 tilemap base + 400h to $7E:5800		(does this copy back what was backed up in the previous setup stage?)
( but if stage 2 and 3 copied VRAM to 7E:6000 and 7E:6800 ... 
	... then how come we're copying back from 7E:5800 and 7E:4000 ?)

91:D173 = x-ray setup stage 6
+-	91:D143 = can x-ray show blocks? if not then return.
+-	queue transfer of 800h bytes from $7E:4000 to VRAM BG2 tilemap base

91:D1A0 = x-ray setup stage 7
+-	91:D143 = can x-ray show blocks?
+-	if so, do some stuff?  if not, do some stuff?  
+-	clear some variables
	mem16[0A88..92] = E4h
	mem16[9800] = E4h
	mem16[98C8] = E4h
	mem16[9990] = 0
	mem16[0A7A] = 0 
	mem16[0A7C] = 0
	mem16[0A7E] = 0
	mem16[0A84] = 0
	mem16[0A86] = 0
+-	initialize the x-ray angle: 40h if facing right, C0h if facing left 

91:D2BC = x-ray setup stage 8
+-	set backdrop color to (3,3,3)

88:86EF = pre-instruction - x-ray - main (called by HDMA object every frame after the HDMA x-ray init)
+-	check FX room type to fireflea room type
+-	91:D143 = can x-ray show blocks. BEQ skips showing blocks (is that CLC or SEC?)
+-	if we can show blocks then set the subscreen backdrop color
+-	call one of the following, indexed by x-ray state: 
	+- 88:8732 = handle x-ray scope - x-ray state = 0 (no beam)
	+- 88:8754 = handle x-ray scope - x-ray state = 1 (beam is widening)
	+- 88:87AB = handle x-ray scope - x-ray state = 2 (full beam)
	+- 88:8934 = handle x-ray scope - x-ray state = 3 (deactivate beam - restore BG2 - first half)
	+- 88:89BA = handle x-ray scope - x-ray state = 4 (deactivate beam - restore BG2 - second half)
	+- 88:8A08 = handle x-ray scope - x-ray state = 5 (deactivate beam - finish)

88:8732 = handle x-ray scope - x-ray state = 0 (no beam)
+-	if not holding run then x-ray state = 3 and return
+-	88:8896 = calculate x-ray HDMA data table
+-	set x-ray state to 1

88:8754 = handle x-ray scope - x-ray state = 1 (beam is widening)
+-	88:8753 = call NOP
+-	if not holding run then x-ray state = 3 return
+-	grow x-ray beam angle.  if it's at max then set x-ray state to 2
+-	88:8896 = calculate x-ray HDMA data table

88:87AB = handle x-ray scope - x-ray state = 2 (full beam)
+-	if holding run then ....
+-	88:87C5 = handle moving x-ray up/down ... test buttons and determine which to call:
	+-	88:87E0 = move x-ray up
		+-	...
	+-	88:8835 = move x-ray down
		+-	...
+-	88:8896 = calculate x-ray HDMA data table
+-	88:8753 = call NOP
+-	... otherwise, if not holding run, then set x-ray state = 3

88:8934 = handle x-ray scope - x-ray state = 3 (deactivate beam - restore BG2 - first half)
+-	do some stuff
+-	91:D143 = can x-ray show blocks.
+-	restore BG2 X scroll, Y scroll, address, size
+-	queue transfer 800h bytes from $7E:5000 to VRAM BG2 tilemap base
+-	inc x-ray state to 4

88:89BA = handle x-ray scope - x-ray state = 4 (deactivate beam - restore BG2 - second half)
+-	91:D143 = can x-ray show blocks
+-	queue transfer 800h bytes from $7E:5800 to vram BG2 tilemap base + 400h
+-	set x-ray state to 5

88:8A08 = handle x-ray scope - x-ray state = 5 (deactivate beam - finish)
+-	91:D143 = can x-ray show blocks
+-	change layer blending window 2 configuration
+-	if time isn't frozen retur
+-	clear x-ray variables: state, angular width delta, angular subwidth delta, angle, angular width, angular subwidth
+-	91:E2AD = x-ray stand up glitch / something to do with samus sequences
+-	80:9049 = queue sound Ah
+-	something about subscreen backdrop color
+-	if auto-cancel then set HUD index to nothing

88:8896 = calculate x-ray HDMA data table
+-	determine standing vs crouching, etc
+-	if origin is on screen...
+-	91:C54B = calculate x-ray HDMA data table - x-ray origin is on screen
	+-	do some x-ray angle tests
	+-	call one of the following:
	+-	91:C5FF
	+-	91:C6C1
	+-	91:C822
	+-	91:C660
	+-	91:C998

+-	if origin is off screen...
+-	91:BE11 = calculate x-ray HDMA data table - x-ray origin is off screen

--]]
--[[

struct VRAMReadTableEntry_t {
	uint16_t	srcAddr;		//+00
	uint8_t		DMAControl;		//+02 ... usually 0x81
	uint8_t		DMATarget;		//+03 ... usually 0x39
	addr24_t	destAddr24;		//+04
	uint16_t	size;			//+07
};								//+09
static_assert(sizeof(VRAMReadTableEntry_t) == 9);

struct tilemapAddrAndSize_t {
	uint8_t width64 : 1;	// true => width == 64, false => width == 32
	uint8_t height64 : 1;	// same
	uint8_t base : 6;		// tilemap base address = base * 0x400
};

using tileBlock_t = tilemapElem_t[2][2];
static_assert(sizeof(tilemapElem_t) == 8);

breakdown of RAM:
bank 7E:
0058 = tilemapAddrAndSize_t BG1TilemapBaseAddrAndSize
0059 = tilemapAddrAndSize_t BG2TilemapBaseAddrAndSize 
005A = tilemapAddrAndSize_t BG3TilemapBaseAddrAndSize 
005B = tilemapAddrAndSize_t GameplayBG3TilemapBaseAddrAndSize 
005C = tilemapAddrAndSize_t BG4TilemapBaseAddrAndSize 
0074 = subscreen backdrop color
0075 = subscreen backdrop color
0076 = subscreen backdrop color
008B = buttons down?
0340 = VRAMReadTableEntry_t VRAMReadTable[0x20/9 == 3.5 or so VRAMReadTableEntry_t here since it's a 9-byte structure in 32 bytes of memory]
0360 = VRAMReadStackOffset
09B6 = custom controls?
09D2 = current HUD selection
0A78 = whether x-ray has set "time is frozen" flag
0A7A = x-ray state
0A7C = x-ray angle width delta
0A7E = x-ray angle subwidth delta
0A82 = x-ray angle
0A84 = x-ray angle width
0A86 = x-ray angle subwidth
0D32 = something with firing grappling beam
196E = room FX type, $0024 = fireflea room
4000 = uint8_t XRayTilemapsViewableBG1[0x1000]
5000 = uint8_t XRayBG2Backup[0x1000]
6000 = uint8_t XRayBG1Backup[0x1000]
A000 = tilemapElem_t tileTable[0x2000/8] ... is this only for the map tiles?
--]]
function Patches:beefUpXRay()
	local function write(...) return self:write(...) end

--[[ make x-ray always on
	-- handle x-ray scope - x-ray state = 0 
	write(0x88, 0x8735,
		0x80, 0x0d)		-- BRA +$0D [$88:8744]
	-- handle x-ray scope - x-ray state = 1
	write(0x88, 0x8757,
		0x80, 0x0d)		-- BRA +$0D [$88:8766]
	-- handle x-ray scope - x-ray state = 2
	write(0x88, 0x87ae,
		0x80, 0x05)		-- BRA +$05 [$88:87B5]
	-- x-ray handler
	write(0x91, 0xcae3,
		0x80, 0x03)		-- BRA +$03 [$91:CAE8]
-- TODO so far it only doesn't turn off, but I need to do somethign else to make it always on
-- TODO TODO what i really want is it to turn on and off upon selection
--]]
--[[ make x-ray always on v2 based solely on 90:DD3D ... eh not so effective
	write(0x90, 0xdd4d,
		0x80, 0x08)	-- BRA +$08 [$90:DD57]
--]]


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
-- [==[ nah, don't modify the state-changing stuff, instead update the per-state code itself
-- but can I do that here also?
-- ok this is the pre-instruction x-ray main ...
-- it calls (8726,x), which points to the four x-ray state functions
-- how about instead I just call them all?
-- but won't I have to change x-ray HDMA in page 91 to also call all its functions?
-- old:
-- $88:871C AD 7A 0A    LDA $0A7A
-- $88:871F 0A          ASL A
-- $88:8720 AA          TAX
-- $88:8721 FC 26 87    JSR ($8726,x)
-- new:
	write(0x88, 0x871c, 
		0x4c, 0x32, 0xee,				-- JMP $ee32
		0xea, 0xea, 0xea, 0xea, 0xea)	-- nops	
	-- use some free space.  hopefully no one else is ...
	local code = table{
		-- original programming
		0xad, 0x7a, 0x0a,	-- LDA $0A7A
		0x0a,				-- ASL A
		0xaa,				-- TAX
		0xfc, 0x26, 0x87,	-- JSR ($8726,x)
		--[[ call all at once.  bad idea.
		0x20, 0x32, 0x87,	-- JSR $8732	-- state 0 = no beam
		0x20, 0x54, 0x87,	-- JSR $8754	-- state 1 = beam is widening
		0x20, 0xab, 0x87,	-- JSR $87ab	-- state 2 = full beam
		0x20, 0x34, 0x89,	-- JSR $8934	-- state 3 = deactivate beam (restore bg2 first half)
		0x20, 0xba, 0x89,	-- JSR $89ba	-- state 4 = deactivate beam (restore b22 second half)
		0x20, 0x08, 0x8a,	-- JSR $8a08	-- state 5 = deactivate beam finish
		--]]
		-- [[ call the HDMA x-ray handler, since that usually just runs through once and then inf loops til it dies
		--0x22, 0x7f, 0xd2, 0x91,	-- JSR $91d27f	-- pre-instruction
		

		--0x22, 0xf9, 0xca, 0x91,	-- JSR $91caf9	-- x-ray setup stage 1 -- messes up controls after the first x-ray
		-- instead I'll inline:
--$91:CAFA E2 30       SEP #$30
--$91:CAFC A9 01       LDA #$01               ;\
--$91:CAFE 8D 78 0A    STA $0A78  [$7E:0A78]  ;} Freeze time
0xa5, 0xb5,			-- LDA $B5    [$7E:00B5]  ;\
0x9d, 0x14, 0x19,	-- STA $1914,x[$7E:1918]  ;|
0xa5, 0xb6,			-- LDA $B6    [$7E:00B6]  ;} Backup BG2 X scroll
0x9d, 0x15, 0x19,	-- STA $1915,x[$7E:1919]  ;/
0xa5, 0xb7,			-- LDA $B7    [$7E:00B7]  ;\
0x9d, 0x20, 0x19,	-- STA $1920,x[$7E:1924]  ;|
0xa5, 0xb8,			-- LDA $B8    [$7E:00B8]  ;} Backup BG2 Y scroll
0x9d, 0x21, 0x19,	-- STA $1921,x[$7E:1925]  ;/
0xa5, 0x59,			-- LDA $59    [$7E:0059]  ;\
0x9d, 0x2c, 0x19,	-- STA $192C,x[$7E:1930]  ;} Backup BG2 address/size


		--0x22, 0x1c, 0xcb, 0x9a,	-- JSR $91cb1c	-- x-ray setup stage 2	-- read bg1 tilemap 2nd screen	-- screen goes black
		--0x22, 0x57, 0xcb, 0x91,	-- JSR $91cb57	-- x-ray setup stage 3	-- read bg1 tilemap 1st screen
		--0x22, 0x8e, 0xcb, 0x91,	-- JSR $91cb8e	-- x-ray setup stage 4	-- calc xray block graphics lookup. .. freezes when run from main
		
		--0x22, 0xd3, 0xd0, 0x91,	-- JSR $91d0d3	-- x-ray setup stage 5	-- calc xray bg2 base
		--0x22, 0x73, 0xd1, 0x91,	-- JSR $91d173	-- x-ray setup stage 6	-- queue transfer of blocks
		
-- [=[
		--0x22, 0xa0, 0xd1, 0x91,	-- JSR $91d1a0	-- x-ray setup stage 7	-- queue transfer of blocks / reset angle.  
		-- the reset angle part screws a lot of things up
		-- so I will inline it and pick what I want:
--0x08,					--PHP
0xc2, 0x30,				--REP #$30
0x22, 0x43, 0xd1, 0x91,	--JSL $91D143[$91:D143]	 ;\
0xf0, 0x26,				--BEQ $26    [$D1CF]     ;} If x-ray should not show any blocks: return
0xae, 0x30, 0x03,		--LDX $0330  [$7E:0330]  ;\
0xa9, 0x00, 0x08,		--LDA #$0800             ;|
0x95, 0xd0,				--STA $D0,x  [$7E:00D0]  ;|
0xa9, 0x00, 0x48,		--LDA #$4800             ;|
0x95, 0xd2,				--STA $D2,x  [$7E:00D2]  ;|
0xa9, 0x7e, 0x00,		--LDA #$007E             ;|
0x95, 0xd4,				--STA $D4,x  [$7E:00D4]  ;|
0xa5, 0x59,				--LDA $59    [$7E:0059]  ;|
0x29, 0xfc, 0x00,		--AND #$00FC             ;} Queue transfer of 800h bytes from $7E:4800 to VRAM BG2 tilemap base + 400h
0xeb,					--XBA                    ;|
0x18,					--CLC                    ;|
0x69, 0x00, 0x04,		--ADC #$0400             ;|
0x95, 0xd5,				--STA $D5,x  [$7E:00D5]  ;|
0x8a,					--TXA                    ;|
0x18,					--CLC                    ;|
0x69, 0x07, 0x00,		--ADC #$0007             ;|
0x8d, 0x30, 0x03,		--STA $0330  [$7E:0330]  ;/

0xa9, 0xe4, 0x00,		--LDA #$00E4             ;\
0x8d, 0x88, 0x0a,		--STA $0A88  [$7E:0A88]  ;|
0xa9, 0x00, 0x98,		--LDA #$9800             ;|
0x8d, 0x89, 0x0a,		--STA $0A89  [$7E:0A89]  ;|
0xa9, 0xe4, 0x00,		--LDA #$00E4             ;|
0x8d, 0x8b, 0x0a,		--STA $0A8B  [$7E:0A8B]  ;|
0xa9, 0xc8, 0x98,		--LDA #$98C8             ;} $0A88..92 = E4h,$9800, E4h,$98C8, 98h,$9990, 00,00
0x8d, 0x8c, 0x0a,		--STA $0A8C  [$7E:0A8C]  ;|
0xa9, 0x98, 0x00,		--LDA #$0098             ;|
0x8d, 0x8e, 0x0a,		--STA $0A8E  [$7E:0A8E]  ;|
0xa9, 0x90, 0x99,		--LDA #$9990             ;|
0x8d, 0x8f, 0x0a,		--STA $0A8F  [$7E:0A8F]  ;|
0x9c, 0x91, 0x0a,		--STZ $0A91  [$7E:0A91]  ;/
--0x9c, 0x7a, 0x0a,		--STZ $0A7A  [$7E:0A7A]  ; $0A7A = 0
--0x9c, 0x7c, 0x0a,		--STZ $0A7C  [$7E:0A7C]  ; $0A7C = 0
--0x9c, 0x7e, 0x0a,		--STZ $0A7E  [$7E:0A7E]  ; $0A7E = 0
--0xa9, 0x00, 0x00,		--LDA #$0000             ;\
--0x8d, 0x84, 0x0a,		--STA $0A84  [$7E:0A84]  ;} $0A84 = 0
--0x9c, 0x86, 0x0a,		--STZ $0A86  [$7E:0A86]  ; $0A86 = 0
--0xad, 0x1e, 0x0a,		--LDA $0A1E  [$7E:0A1E]  ;\
--0x29, 0xff, 0x00,		--AND #$00FF             ;|
--0xc9, 0x04, 0x00,		--CMP #$0004             ;} If Samus is facing right:
--0xf0, 0x08,			--BEQ $08    [$D21B]     ;/
--0xa9, 0x40, 0x00,		--LDA #$0040             ;\
--0x8d, 0x82, 0x0a,		--STA $0A82  [$7E:0A82]  ;} X-ray angle = 40h
--0x80, 0x06,			--BRA $06    [$D221]     ; Return

--0xa9, 0xc0, 0x00,		--LDA #$00C0             ;\
--0x8d, 0x82, 0x0a,		--STA $0A82  [$7E:0A82]  ;} X-ray angle = C0h

--0x28,					--PLP
--0x6b,					--RTL
--]=]


		--0x22, 0xbc, 0xd2, 0x91,	-- JSR $91d2bc	-- x-ray setup stage 8 	-- backdrop color
		--0x22, 0xef, 0x86, 0x88	-- JSR $8886ef	-- pre-instruction x-ray main ... which is where I'm calling this from ...
		--]]
		0x4c, 0x24, 0x87	-- JMP 8724 and pick up where we left off

	}
	assert(#code <= 0xffff - 0xee2d)
	write(0x88, 0xee32, code:unpack())
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
what it was:
$90:DDC8 A5 8B       LDA $8B    [$7E:008B]  ;\
$90:DDCA 2C B6 09    BIT $09B6  [$7E:09B6]  ;} If not holding run:
$90:DDCD D0 04       BNE $04    [$DDD3]     ;/
$90:DDCF 20 0D B8    JSR $B80D  [$90:B80D]  ; HUD selection handler - nothing / power bombs
$90:DDD2 60          RTS
$90:DDD3 22 D6 CA 91 JSL $91CAD6[$91:CAD6]  ; Execute x-ray handler
$90:DDD7 60          RTS
--]]
-- [[
	write(0x90, 0xddc8,
		0x20, 0x0d, 0xb8,		-- JSR $B80D	<- do HUD selection handler for nothing / power bombs
		0xa5, 0x8b,				-- LDA $8B		\
		0x2c, 0xb6, 0x09,		-- BIT $09B6	| If holding run ...
		0xf0, 0x04,				-- BEQ $04		/
		0x22, 0xd6, 0xca, 0x91,	-- JSL $91CAD6	<- ... do x-ray handler
		0x60)					-- RTS
--]]
--[[ or just cancel x-ray altogether.  yup, this does just that.
	write(0x90, 0xddc8, 0x60)
--]]


-- [==[ something in here is needed for samus pain animation to work while x-raying
	write(0x90, 0xde04, 0xea, 0xea)			-- write(0x90, 0xde01, 0xa9, 0x00, 0x00)
	write(0x90, 0xdff0, 0x80)				-- write(0x90, 0xdfed, 0xa9, 0x00, 0x00)
	write(0x90, 0xe761, 0xea, 0xea)			-- write(0x90, 0xe75e, 0xa9, 0x00, 0x00)
	write(0x90, 0xe9d1, 0x80)				-- write(0x90, 0xe9d1, 0xa9, 0x00, 0x00)
	write(0x90, 0xea50, 0xea, 0xea)			-- write(0x90, 0xea4d, 0xa9, 0x00, 0x00)
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
	-- instead 91:d277 going to 91:d277, have it go back to 91:d223
	--write(0x91, 0xd27d, 0x23)	-- goto start of x-ray HDMA object instruction list -- beam doesn't fully open and never turns off
	--write(0x91, 0xd27d, 0x29)	-- same
	-- OK what this did?  only opens the beam a little bit, but does let the normal view scroll and follow you while the x-ray part lags behind, 
	--write(0x91, 0xd27d, 0x29)


	write(0x91, 0xdf69, 0xea, 0xea)			-- write(0x91, 0xdf66, 0xa9, 0x00, 0x00)
--]=]
--]]

	-- x-ray setup carry clear does nothing (no opt-out of xray)
	-- is great for letting you move around during scope, but monsters are still frozen.
	-- also if you start xraying while standing still, then you go into xray mode and can't move much.
	-- hmm, after all my other changes, seems this doesn't matter anymore
--	write(0x91, 0xcaec, 0xea, 0xea)

	-- change sta to stz so we clear the freeze flag
	--  causes freeze
	--  so alternatiely, I've modified nearly all the "if x-ray freeze flag" scattered throughout the code to treat the freeze flag as if it is off
	--write(0x91, 0xcafe, 0x9c)	

	-- x-ray works in fireflea room
	-- TODO fire-flea is rendered all with layer 3 bg, so ... does this have to do with it?
	--write(0x91, 0xd156, 0xea, 0xea)
	-- x-ray works in all rooms (just have 91:d143 immediately return)
	write(0x91, 0xd143, 0x6b)

	write(0x91, 0xe1a8, 0xea, 0xea)	-- skip game state test for x-ray setup

	-- this lets you move with x-ray
	-- TODO make the x-ray angle change when you move left or right
	write(0x91, 0xe1f1, 0xea, 0xea, 0xea)	-- don't write facing right x-ray standing state, i.e. mem[0x7e0a2a] = 0x00d5
	write(0x91, 0xe1f9, 0xea, 0xea, 0xea)	-- don't write facing left x-ray standing state, i.e. mem[0x7e0a2a] = 0x00d6
	write(0x91, 0xe20c, 0xea, 0xea, 0xea)	-- don't write facing right x-ray crouching state, i.e. mem[0x7e0a2a] = 0x00d9
	write(0x91, 0xe214, 0xea, 0xea, 0xea)	-- don't write facing left x-ray crouching state, i.e. mem[0x7e0a2a] = 0x00da

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

-- skip the "load x-ray blocks" function
--	write(0x84, 0x831a, 0x6b)	

-- skip "handle layer blending x-ray - can't show blocks"
--	write(0x88, 0x817b, 0x60)	

-- skip "handle layer blending x-ray - can show blocks"
--	write(0x88, 0x81a4, 0x60)	

-- make "check if x-ray should show any blocks" always return false
	write(0x91, 0xd143, 	
		-- return false: A=0, so zero bit is set, so x-ray never shows blocks
		--0xa9, 0x00, 0x00, 	-- LDA #$0000
		-- return true: A=1, so zero bit is cleared, so x-ray *always* shows blocks
		0xa9, 0x01, 0x00, 	-- LDA #$0001
		0x6b)				-- RTL
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
	self:write(0x84, 0xefd3, 
		0xad, 0xd7, 0x05, 0xc9, 0x02, 0x00, 0xf0, 0x0e, 0xa9, 0x00, 0x00, 0x22, 0xf7, 0x8f, 0x80, 0xad, 0xf5, 0x07, 0x22, 0xc1, 0x8f, 0x80, 0xa9, 0x00, 0x00, 0x8d, 0xd7, 0x05, 0x6b, 0xa9, 0x01, 0x00, 0x8d, 0xd7, 0x05, 0x22, 0x17, 0xbe, 0x82, 0xa9, 0x00, 0x00, 0x60, 0x20, 0x19, 0xf0, 0x29, 0xff, 0x00, 0x22, 0x49, 0x90, 0x80, 0x60, 0x20, 0x19, 0xf0, 0x22, 0xcb, 0x90, 0x80, 0x60, 0x20, 0x19, 0xf0, 0x22, 0x4d, 0x91, 0x80, 0x60, 0xa9, 0x02, 0x00, 0x8d, 0xd7, 0x05, 0xb9, 0x00, 0x00, 0xc8, 0x60)
	
	self:write(0x85, 0x8089, 0x80, 0x02)
	self:write(0x85, 0x8491, 0x20, 0x00)
end

return Patches
