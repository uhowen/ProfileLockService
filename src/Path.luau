local function getAtPath(root, path, fallback)
	local current = root

	for _, segment in path do
		if type(current) ~= "table" then
			return fallback
		end

		current = current[segment]

		if current == nil then
			return fallback
		end
	end

	return current
end

local function setAtPath(root, path, value)
	local current = root

	for index = 1, #path - 1 do
		local segment = path[index]
		local nextValue = current[segment]

		if type(nextValue) ~= "table" then
			nextValue = {}
			current[segment] = nextValue
		end

		current = nextValue
	end

	current[path[#path]] = value
	return root
end

local function removeAtPath(root, path)
	local current = root

	for index = 1, #path - 1 do
		current = current[path[index]]

		if type(current) ~= "table" then
			return false
		end
	end

	local lastSegment = path[#path]

	if current[lastSegment] == nil then
		return false
	end

	current[lastSegment] = nil
	return true
end

local function incrementAtPath(root, path, amount)
	local currentValue = getAtPath(root, path, 0)
	local nextValue = currentValue + amount
	setAtPath(root, path, nextValue)
	return nextValue
end

local function updateAtPath(root, path, updater, fallback)
	local currentValue = getAtPath(root, path, fallback)
	local nextValue = updater(currentValue)
	setAtPath(root, path, nextValue)
	return nextValue
end

return {
	getAtPath = getAtPath,
	setAtPath = setAtPath,
	removeAtPath = removeAtPath,
	incrementAtPath = incrementAtPath,
	updateAtPath = updateAtPath,
}
