local deepCopy = require(script.Parent.DeepCopy)

local function deepMerge(defaults, incoming)
	if type(defaults) ~= "table" then
		if incoming == nil then
			return defaults
		end

		return incoming
	end

	local result = {}
	local source = if type(incoming) == "table" then incoming else nil

	for key, defaultValue in defaults do
		local nextValue = if source then source[key] else nil

		if type(defaultValue) == "table" then
			result[key] = deepMerge(defaultValue, nextValue)
		elseif nextValue == nil then
			result[key] = deepCopy(defaultValue)
		else
			result[key] = nextValue
		end
	end

	if source then
		for key, value in source do
			if result[key] == nil then
				result[key] = deepCopy(value)
			end
		end
	end

	return result
end

return deepMerge
