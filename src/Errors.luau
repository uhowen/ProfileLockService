local function create(code, message, details)
	return {
		code = code,
		message = message,
		details = details,
	}
end

return {
	create = create,
}
