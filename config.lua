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
		DraygonCrystalFlashBlueSparkWhatever = false,

		-- whether you know how to get through gates using super missiles
		superMissileGateGlitch = false,

		-- I've seen this done ... does it require high jump? either way...
		canJumpAcrossEntranceToWreckedShip = false,
		
		-- how to get out of lower norfair
		preciseTouchAndGoLowerNorfair = false,
		lowerNorfairSuitSwap = true,
	},
}
