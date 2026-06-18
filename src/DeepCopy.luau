local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, nestedValue in value do
		copy[deepCopy(key)] = deepCopy(nestedValue)
	end

	return copy
end

return deepCopy
