-- Test module for HTTP API functionality
-- This module can be used to test the HTTP API without running the full GUI

local tests = {}

-- Load required modules
local json = require("dkjson")

-- Test helper function to create a mock build
local function createMockBuild()
	return {
		calcsTab = {
			mainOutput = {
				TotalDPS = 12345.67,
				AverageDamage = 1234.56,
				CritChance = 75.5,
				CritMultiplier = 450,
				HitChance = 95.2,
				Life = 6500,
				EnergyShield = 2000,
				Mana = 1200,
				FireResist = 75,
				ColdResist = 76,
				LightningResist = 75,
				ChaosResist = 15,
				Str = 150,
				Dex = 200,
				Int = 300,
				MainHand = {
					PhysicalDPS = 1000,
					ElementalDPS = 500,
					TotalDPS = 1500,
					PhysicalHitAverage = 200,
					ElementalHitAverage = 100
				}
			},
			calcsOutput = {
				PhysicalMaximumHitTaken = 5000,
				FireMaximumHitTaken = 3000,
				ColdMaximumHitTaken = 3000,
				LightningMaximumHitTaken = 3000,
				ChaosMaximumHitTaken = 2000
			},
			mainEnv = {
				player = {
					breakdown = {
						Life = {
							rowList = {
								{
									value = 484,
									mod = {
										source = "Base",
										type = "BASE"
									},
									sourceName = "Base life"
								},
								{
									value = 180,
									mod = {
										source = "Tree:12345",
										type = "INC"
									},
									sourceName = "Life nodes"
								},
								{
									value = 79,
									mod = {
										source = "Item:1:Ring",
										type = "BASE"
									},
									sourceName = "Rare Gold Ring"
								}
							}
						}
					}
				}
			}
		}
	}
end

-- Test JSON serialization
function tests.testJSONSerialization()
	local httpAPI = LoadModule("Modules/HttpAPI")
	local mockBuild = createMockBuild()
	
	httpAPI.setBuild(mockBuild)
	
	-- Test compact mode
	local request = {
		query = {
			mode = "compact",
			category = "all"
		}
	}
	
	local stats, err = httpAPI.extractStats("compact", "all", nil)
	assert(stats ~= nil, "Stats extraction failed: " .. (err or "unknown error"))
	assert(stats.offensive ~= nil, "Offensive stats missing")
	assert(stats.defensive ~= nil, "Defensive stats missing")
	assert(stats.character ~= nil, "Character stats missing")
	
	print("✓ Compact mode stats extraction successful")
	
	-- Test full mode
	local fullStats, fullErr = httpAPI.extractStats("full", "all", nil)
	assert(fullStats ~= nil, "Full stats extraction failed: " .. (fullErr or "unknown error"))
	
	print("✓ Full mode stats extraction successful")
	
	-- Test JSON encoding
	local jsonString = json.encode(stats)
	assert(jsonString ~= nil, "JSON encoding failed")
	assert(type(jsonString) == "string", "JSON result is not a string")
	
	print("✓ JSON serialization successful")
	
	-- Test JSON decoding (to verify structure)
	local decoded = json.decode(jsonString)
	assert(decoded ~= nil, "JSON decoding failed")
	assert(decoded.offensive ~= nil, "Decoded offensive stats missing")
	
	print("✓ JSON structure validation successful")
	
	return true
end

-- Test individual endpoints
function tests.testEndpoints()
	local httpAPI = LoadModule("Modules/HttpAPI")
	local mockBuild = createMockBuild()
	
	httpAPI.setBuild(mockBuild)
	
	-- Test status endpoint
	local statusRequest = { query = {} }
	local statusResponse = httpAPI.handleStatus(statusRequest)
	assert(statusResponse ~= nil, "Status endpoint failed")
	assert(statusResponse:find("application/json"), "Status response not JSON")
	
	print("✓ Status endpoint working")
	
	-- Test calcs endpoint
	local calcsRequest = { 
		query = { 
			mode = "compact",
			category = "defensive"
		} 
	}
	local calcsResponse = httpAPI.handleCalcs(calcsRequest)
	assert(calcsResponse ~= nil, "Calcs endpoint failed")
	assert(calcsResponse:find("application/json"), "Calcs response not JSON")
	
	print("✓ Calcs endpoint working")
	
	return true
end

-- Test error handling
function tests.testErrorHandling()
	local httpAPI = LoadModule("Modules/HttpAPI")
	
	-- Test with no build loaded
	httpAPI.setBuild(nil)
	
	local stats, err = httpAPI.extractStats("compact", "all", nil)
	assert(stats == nil, "Should fail with no build")
	assert(err ~= nil, "Should return error message")
	
	print("✓ Error handling working")
	
	-- Test invalid mode
	local mockBuild = createMockBuild()
	httpAPI.setBuild(mockBuild)
	
	local invalidRequest = {
		query = {
			mode = "invalid",
			category = "all"
		}
	}
	
	local invalidResponse = httpAPI.handleCalcs(invalidRequest)
	assert(invalidResponse:find("400"), "Should return 400 error for invalid mode")
	
	print("✓ Invalid parameter handling working")
	
	return true
end

-- Run all tests
function tests.runAll()
	print("Starting HTTP API tests...")
	
	local success, err = pcall(tests.testJSONSerialization)
	if not success then
		print("✗ JSON Serialization test failed: " .. err)
		return false
	end
	
	success, err = pcall(tests.testEndpoints)
	if not success then
		print("✗ Endpoints test failed: " .. err)
		return false
	end
	
	success, err = pcall(tests.testErrorHandling)
	if not success then
		print("✗ Error handling test failed: " .. err)
		return false
	end
	
	print("✓ All HTTP API tests passed!")
	return true
end

return tests