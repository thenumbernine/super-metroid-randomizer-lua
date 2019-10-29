-- exponentially weighted
local function expRand(min, max)
	local logmin, logmax = math.log(min), math.log(max)
	return math.exp(math.random() * (logmax - logmin) + logmin)
end
return expRand
