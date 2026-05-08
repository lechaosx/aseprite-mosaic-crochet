-- Minimal 2D integer vector with arithmetic metamethods.
-- Construct with vec2(x, y). Supports +, -, *, == and vec2.min, vec2.max, vec2.clamp.
-- Components accessible as vec.x / vec.y or vec[1] / vec[2].

local Vec2Metatable = {}

Vec2Metatable.__index = function(vector, key)
	if key == "x" then return rawget(vector, 1)
	elseif key == "y" then return rawget(vector, 2)
	end
end

local function newVec2(x, y)
	return setmetatable({x, y}, Vec2Metatable)
end

function Vec2Metatable.__add(leftOperand, rightOperand)
	return newVec2(leftOperand[1] + rightOperand[1], leftOperand[2] + rightOperand[2])
end

function Vec2Metatable.__sub(leftOperand, rightOperand)
	return newVec2(leftOperand[1] - rightOperand[1], leftOperand[2] - rightOperand[2])
end

function Vec2Metatable.__mul(leftOperand, rightOperand)
	if type(leftOperand) == "number" then
		return newVec2(leftOperand * rightOperand[1], leftOperand * rightOperand[2])
	else
		return newVec2(leftOperand[1] * rightOperand, leftOperand[2] * rightOperand)
	end
end

function Vec2Metatable.__eq(leftOperand, rightOperand)
	return leftOperand[1] == rightOperand[1] and leftOperand[2] == rightOperand[2]
end

local Vec2Module = setmetatable({}, {
	__call = function(_, x, y) return newVec2(x, y) end
})

function Vec2Module.min(leftOperand, rightOperand)
	return newVec2(math.min(leftOperand[1], rightOperand[1]), math.min(leftOperand[2], rightOperand[2]))
end

function Vec2Module.max(leftOperand, rightOperand)
	return newVec2(math.max(leftOperand[1], rightOperand[1]), math.max(leftOperand[2], rightOperand[2]))
end

function Vec2Module.clamp(vector, minVector, maxVector)
	return Vec2Module.max(minVector, Vec2Module.min(maxVector, vector))
end

return Vec2Module
