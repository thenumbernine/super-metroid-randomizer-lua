return {
	writeOutImage = true,
	
	randomizeEnemies = true,

	-- TODO still run constraints to make sure the game is playable even if we're not randomizing items?
	-- ... to make sure enemies aren't impossible
	-- and same with doors
	--
	-- TODO new idea, possibly a separate algo:
	-- 0) make a connectivity graph of all rooms.  maybe derive it from the room mdb_t's and door_t's themselves.
	-- 1) remove the door tests from 'can access' code.  instead just pick an item location arbitrarily.
	-- 2) then chart an arbitrary route through our graph from the start/last item location to the new item location.  it doesn't have to be optimal, it should be random in fact.
	-- 3) then - if our path includes doors (edges) which haven't been touched yet - then change the doors along the way to be colored based on whatever items we already have. 
	-- 		no harm in throwing in gates as well.  also no harm in tagging block regions to be changed as well... maybe...
	randomizeItems = true,

	-- TODO the item placement doesn't validate that the door colors are possible to pass
--	randomizeDoors = true,

	randomizeWeapons = true, 

	weaponDamageScaleRange = {1/3, 2},	-- new weapon damage range is 33% to 200% of original

	-- skips the intro cutscene
	skipIntro = true,

	-- wake zebes when you go through the room to the right of the first blue brinstar room.
	-- notice that even if zebes is asleep, you can still get the two items in the room above the first missile... but you can't get the powerbomb behind the powerbomb walls behind morph ball.
	wakeZebesEarly = true,

	-- skip item fanfare
	skipItemFanfare = true,

	-- force certain weakness values on all monsters:
	forceEnemyWeakness = {
--		screwattack = 0,	-- make all monsters immune to screw attack
	},

	-- used by enemy randomization
	randomizeEnemyProps = {
	
		--palette = true,

		weakness = true,
		weaknessImmunityChance = .75,
		chanceToFreeze = 2/3,
		chanceToInstaFreeze = .05,

		itemdrop = true,
		itemDropZeroChance = .75,	-- % of item drop percentage fields that are 0%

		health = true,
		healthScaleRange = {1/3, 3},	-- new health = 33% to 300% the old health

		damage = true,
		damageScaleRange = {1/3, 3},

		-- hmm, these can't strictly be scaled always, because some enemies have 0 as values.  that doesn't scale well.
		hurtTime = true,
		hurtTimeScaleRange = {1/3, 3},

		-- effects
		deathEffect = true,
		sound = true,
		
		--[[ randomize the AI 
		-- hmm, mixing and matching individaul routines causes lots of crashes
		-- but what if I randomize the sets of routines, to completely swap out one monster with another?
		aiBank = true,	
		initiationAI = true,
		mainAI = true,
		grappleAI = true,
		hurtAI = true,
		frozenAI = true,
		xrayAI = true,
		--]]
	
		shotDamage = true,
		shotDamageScaleRange = {1/3, 3},
	},

	randomizeDoorProps = {
		-- set this to override the # colored doors placed throughout the world
		-- TODO one idea for overlapping door ids: make sure they have matching colors
		numColoredDoors = 128,
	},

	-- used by item randomization
	-- what skills does the player know?
	playerSkills = {
		
		-- this one covers a wide range
		-- there's the lower green Brinstar power bomb item, which has always required touch-and-go
		-- but there are several other locations which requier different degrees of skill of touch-and-go:
		-- 1) accessing upper red Brinstar, you need either hijump, spacejump, ice ... or you can just use touch-and-go (super missiles help, for clearing the monsters out of the way)
		-- 2) accessing Kraid without hijump or spacejump
		-- 3) lots more
		touchAndGo = true,
		touchAndGoToBoulderRoom = true,
		touchAndGoUpAlcatraz = true,
		touchAndGoUpToGauntlet = true,	-- you can do this with high jump disabled

		bombTechnique = true,

		jumpAndMorph = true,

		damageBoostToBrinstarEnergy = true,	--true,	-- with high damage, this guarantees you to be killed

		-- whether the player knows to use mockball to get into the green Brinstar item area
		-- I think that's the only place it's really necessary
		mockball = true,

		maridiaSuitSwap = true,

		-- if you want to bother freeze the crab to jump up the maridia start area
		suitlessMaridiaFreezeCrabs = true,
		
		-- speed boost by tapping 'a' at first, cuts off a block or two. maybe this isn't the right name.
		shortSpeedBoost = true,

		-- whether you want to run through the lava rooms of norfair without a suit
		hellrun = true,
		
		-- if you want to bother do that stupid freeze-the-mocktroid glitch to jump through the wall
		freezeTheMocktroidToGetToBotwoon = false,

		-- I've seen people do this in reverse boss videos ...
		-- to get out of draygon's chamber without gravity suit - you can get a blue spark from a crystal flash, or something
		DraygonCrystalFlashBlueSparkWhatever = false,

		-- whether you know how to get through gates using super missiles
		superMissileGateGlitch = false,

		-- touch and go across the moat.  I've seen this done ... does it require high jump? either way...
		canJumpAcrossEntranceToWreckedShip = false,
		
		-- how to get out of lower norfair
		preciseTouchAndGoLowerNorfair = false,
		lowerNorfairSuitSwap = true,
	},

--[[ list of items to change (and how many to leave)
	-- in case you want a tougher challenge ... get rid of a few of the items
	itemChanges = {
		{from='supermissile', to='missile', leave=1},	-- turn all (but one) super missiles into missiles
		{from='powerbomb', to='missile', leave=1},	 	-- turn all (but one) power bombs into missiles
		{from='energy', to='missile', leave=6},
		{from='reserve', to='missile'},
-- [=[ this makes for an interesting challenge...
		-- is this possible?  you will have a hard time escaping Draygon's room
		--{from='gravity', to='missile'},

		-- only possible if you have enough e-tanks before hell runs
		-- what this means is ... if the randomizer doesn't come up with a varia suit before hell run ... then it will be forced to place *all* energy tanks before hell run ... which might make a game that's too easy
		{from='varia', to='missile'},
		
		{from='xray', to='missile'},
		{from='hijump', to='missile'},
		{from='bomb', to='missile'},
		{from='springball', to='missile'},
		{from='spacejump', to='missile'},

		-- speed?  needed in maridia before botwoon, or you can freeze glitch ...
--]=]
--[=[ these items are a bit more necessary
		-- grappling is only absolutely required to get into springball...
		{from='grappling', to='missile'},
		{remove='Spring Ball', to='missile'},
		{from='screwattack', to='missile'},
--]=]
--[=[ this is more dangerous / might not randomize, since enemies have so few weakness rolls...
		{from='spazer', to='missile'},

		-- removing plasma means you must keep screwattack, or else you can't escape the plasma room and it'll stall the randomizer
		-- the other fix is to just not consider the plasma location, and put something innocuous there ...
		{from='plasma', to='missile'},
		
		-- this will stall the randomizer because of pink Brinstar energy tank
		-- so lets remove it and write it as a missile
		{from='wave', to='missile'},
		{remove='Energy Tank (pink Brinstar top)', to='missile'},
		
		-- is this possible?  maybe you can't kill the golden chozo without charge, or a lot of super missiles ... or a lot of restocking on 5 super missiles and shooting them all off at him
		--{from='charge', to='missile'},

		-- ice isn't possible without changing around metroids damage ...
--]=]
	},
--]]
--[[
	itemChanges = {
		{from='missile', to='supermissile'},						-- turn all missiles into super missiles
		{from='powerbomb', to='supermissile', leave=1}, 		-- turn all but one power bombs into super missiles
		{from='spazer', to='supermissile'},
		{from='hijump', to='supermissile'},
		{from='reserve', to='supermissile'},
		{from='xray', to='supermissile'},	-- no need for these
		{from='energy', to='supermissile', leave=7},
		
		-- get rid of unaccessible items -- remove them from the search:
--		{remove='Spring Ball', to='supermissile'},
--		{remove='Plasma Beam', to='supermissile'},
--		{remove='Missile (Gold Torizo)', to='supermissile'},
--		{remove='Super Missile (Gold Torizo)', to='supermissile'},
--		{remove='Screw Attack', to='supermissile'},
	},
--]]

	-- every item type probability defaults to 1
	-- however you can override any you want to see sooner
-- [[
	itemPlacementProbability = {
		bomb = .01,
		charge = 1.5848931924611,
		energy = .63095734448019,
		grappling = .1,	--1.5848931924611,
		gravity = .01,
		hijump = .01,
		ice = 1.5848931924611,
		missile = 10,
		morph = .01,
		plasma = .63095734448019,
		powerbomb = .01,
		reserve = 10,
		screwattack = .01,
		--screwattack = 100,	-- screw attack first! and make all monsters immune to it! 
		spacejump = .01,
		spazer = 1.5848931924611,
		speed = .01,
		springball = .01,
		supermissile = .01,
		varia = 1.5848931924611,
		wave = 1.0471285480509,
		xray = 1e+20,
	},
--]]	

--[=[ enable this with damage boost and wake early and it is pretty interesting
	itemPlacementProbability = {
		supermissile = 1e+10,
	},
--]=]

--[=[ here's an item scheme I'm working on:
	itemChanges = {
		{from='missile', to='morph', leave=1},
		{from='powerbomb', to='morph', leave=1},
		{from='supermissile', to='morph', leave=1},
		{from='reserve', to='morph'},
		{from='xray', to='morph'},	-- no need for these
		{from='energy', to='morph', leave=7},
		{from='springball', to='morph'},
--		{from='spacejump', to='morph'},
-- why can't I remove hijump? it is exclusive with spacejump or grappling
		{from='hijump', to='morph'},

		-- without space jump, these aren't accessible:
		{remove='Missile (Gold Torizo)', to='morph'},
		{remove='Super Missile (Gold Torizo)', to='morph'},
		{remove='Screw Attack', to='morph'},

-- if you also want to get rid of grappling:	
--		{from='grappling', to='morph'},
		-- without spring ball, grappling isn't essential
--		{remove='Spring Ball', to='morph'},
	},
	itemPlacementProbability = {
		bomb = .01,
		charge = .01,
		energy = .01,
		grappling = .01,
		gravity = .01,
		hijump = .01,	-- replaced
		ice = .01,
		missile = .01,
		morph = 1,
		plasma = .01,
		powerbomb = .01,
		reserve = .01,	-- replaced
		screwattack = .01,	-- replaced
		spacejump = 0,
		spazer = .01,
		speed = .01,
		springball = .01,
		supermissile = .01,
		varia = .01,
		wave = .01,
		xray = 1000,	-- replaced
	},
--]=]


}
