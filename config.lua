return {
	randomizeEnemies = true,
  
	randomizeItems = true,
	-- TODO still run constraints to make sure the game is playable even if we're not randomizing items?
	-- ... to make sure enemies aren't impossible

	-- skips the intro cutscene
	skipIntro = true,

	-- wake zebes when you go through the room to the right.
	-- but experimenting with this when I got morph ball -> power bombs, 
	-- it seems I did wake up the monsters in the rooms in blue brinstar, 
	-- but the space pirates in old mother brain are still not there.  hmm.
	-- it did allow the item left of morph ball behind the power bomb wall to be spawned fwiw.
	-- so with this enabled, now i can't go up through old mother brain *AND* I can't go left without killing the sidehoppers
	-- note: I just did another run and the space pirates did spawn.  hmm.
	wakeZebesEarly = true,

	-- used by enemy randomization
	randomizeEnemyProps = {
		
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

		damageBoostToBrinstarEnergy = true,

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

		-- I've seen this done ... does it require high jump? either way...
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
		{fromLoc='Spring Ball', to='missile'},
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
		{fromLoc='Energy Tank (pink Brinstar top)', to='missile'},
		
		-- is this possible?  maybe you can't kill the golden chozo without charge, or a lot of super missiles ... or a lot of restocking on 5 super missiles and shooting them all off at him
		--{from='charge', to='missile'},

		-- ice isn't possible without changing around metroids damage ...
--]=]
	},
--]]
--[[
	itemChanges = {
		{from='missile', to='supermissile'},						-- turn all missiles into super missiles (one is already left -- the first missile tank)
		{from='powerbomb', to='supermissile', leave=1}, 		-- turn all but one power bombs into super missiles
		{from='spazer', to='supermissile'},
		{from='hijump', to='supermissile'},
		{from='springball', to='supermissile'},
		{from='reserve', to='supermissile'},
		{from='xray', to='supermissile'},	-- no need for these
		{from='energy' to='supermissile', leave=7},
	},
--]]

	-- every item type priority defaults to 0
	-- however you can override any you want to see sooner
	itemPlacementPriority = {
		supermissile = .1,
		energy 		= -.1,
		missile 	= 0,
		powerbomb	= .1,
		bomb		= -1,
		charge		= .1,
		ice			= .1,
		hijump		= -1,
		speed		= -1,
		wave		= .1,
		spazer 		= .1,
		springball	= -1,
		varia		= .1,
		plasma		= -.1,
		grappling	= .1,
		morph		= -.5,
		reserve		= .5,
		gravity		= -1,
		xray		= 10,
		spacejump 	= -1,
		screwattack	= .1,
	},
	-- 10^ to get percent of chance of placement
	-- the higher this is, the stronger the priority influences the placement
	itemPlacementPriorityPower = 100,
}
