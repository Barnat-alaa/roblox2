--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TestEZ = require(ReplicatedStorage.Packages.TestEZ)
local tests = ReplicatedStorage:WaitForChild("Tests")

local results = TestEZ.TestBootstrap:run({ tests }, TestEZ.Reporters.TextReporter)

if results.failureCount > 0 then
	error(string.format("TestEZ failed: %d test(s) failed", results.failureCount))
end

print(string.format("TestEZ passed: %d test(s)", results.successCount))
