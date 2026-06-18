local Constants = require(script.Parent.Constants)

local function waitForAttempt(attempt, retryDelay, retryDelayCap)
	local delayAmount = math.min(retryDelay * attempt, retryDelayCap)
	task.wait(delayAmount)
end

return {
	waitForAttempt = waitForAttempt,
	defaultRetryDelay = Constants.DefaultRetryDelay,
	defaultRetryDelayCap = Constants.DefaultRetryDelayCap,
}
