local M = {}

function M.test(name, run)
	local ok, err = pcall(run)
	if not ok then
		print("FAIL: " .. name)
		print(err)
	else
		print("PASS: " .. name)
	end
end

return M
