#!/usr/bin/env lua

-- Simple test runner for HTTP API
-- Run this from the PathOfBuilding root directory

package.path = package.path .. ";src/?.lua;runtime/lua/?.lua"

-- Load test module
local testModule = dofile("spec/System/TestHttpAPI_spec.lua")

-- Run tests
local success = testModule.runAll()

if success then
	print("\n🎉 All tests passed!")
	os.exit(0)
else
	print("\n❌ Some tests failed!")
	os.exit(1)
end