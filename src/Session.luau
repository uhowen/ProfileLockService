local DeepCopy = require(script.Parent.DeepCopy)

local Session = {}

function Session.create()
	return {
		placeId = game.PlaceId,
		jobId = game.JobId,
		acquiredAt = os.time(),
	}
end

function Session.clone(session)
	return DeepCopy(session)
end

function Session.isSame(a, b)
	if not a or not b then
		return false
	end

	return a.placeId == b.placeId and a.jobId == b.jobId
end

function Session.age(session)
	if not session then
		return math.huge
	end

	return os.time() - (session.acquiredAt or 0)
end

function Session.isStale(session, timeoutSeconds)
	return Session.age(session) >= timeoutSeconds
end

function Session.describe(session)
	if not session then
		return "unknown-session"
	end

	return `{session.placeId}:{session.jobId}`
end

return Session
