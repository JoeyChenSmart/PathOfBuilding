-- Path of Building
--
-- Module: HttpAPI
-- Provides HTTP API endpoints for exposing calculation results and configuration
--
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local type = type
local pcall = pcall
local tonumber = tonumber
local string = string
local table = table
local math = math
local os = os

local httpAPI = { }

-- Import JSON library
local json = require("dkjson")

-- Global reference to the main build object
local currentBuild = nil

-- HTTP server state
local server = nil
local serverPort = 8080
local isRunning = false

-- MIME types for responses
local MIME_TYPES = {
	json = "application/json",
	text = "text/plain",
	html = "text/html"
}

-- HTTP status codes
local HTTP_STATUS = {
	OK = 200,
	BAD_REQUEST = 400,
	NOT_FOUND = 404,
	INTERNAL_ERROR = 500,
	SERVICE_UNAVAILABLE = 503
}

-- Simple HTTP response builder
local function createResponse(status, contentType, body)
	local response = {
		"HTTP/1.1 " .. status .. " " .. (status == 200 and "OK" or "Error"),
		"Content-Type: " .. contentType,
		"Content-Length: " .. #body,
		"Connection: close",
		"Access-Control-Allow-Origin: *",
		"Access-Control-Allow-Methods: GET, POST, OPTIONS",
		"Access-Control-Allow-Headers: Content-Type",
		"",
		body
	}
	return table.concat(response, "\r\n")
end

-- Simple HTTP request parser
local function parseRequest(request)
	local lines = {}
	for line in request:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	
	if #lines == 0 then
		return nil
	end
	
	-- Parse request line
	local method, path, version = lines[1]:match("(%w+)%s+([^%s]+)%s+(HTTP/[%d%.]+)")
	if not method then
		return nil
	end
	
	-- Parse query parameters
	local queryParams = {}
	local pathOnly, queryString = path:match("([^%?]+)%??(.*)")
	if queryString and queryString ~= "" then
		for param in queryString:gmatch("[^&]+") do
			local key, value = param:match("([^=]+)=?(.*)")
			if key then
				queryParams[key] = value and value:gsub("%%(%x%x)", function(hex)
					return string.char(tonumber(hex, 16))
				end) or ""
			end
		end
	end
	
	return {
		method = method,
		path = pathOnly or path,
		query = queryParams,
		version = version
	}
end

-- Safely access nested table values
local function safeGet(table, ...)
	local current = table
	for _, key in ipairs({...}) do
		if type(current) ~= "table" or current[key] == nil then
			return nil
		end
		current = current[key]
	end
	return current
end

-- Handle NaN and infinite values for JSON serialization
local function sanitizeValue(value)
	if type(value) == "number" then
		if value ~= value then  -- NaN check
			return 0
		elseif value == math.huge then
			return "Infinity"
		elseif value == -math.huge then
			return "-Infinity"
		end
	end
	return value
end

-- Recursively sanitize all values in a table
local function sanitizeTable(tbl)
	if type(tbl) ~= "table" then
		return sanitizeValue(tbl)
	end
	
	local sanitized = {}
	for key, value in pairs(tbl) do
		sanitized[key] = sanitizeTable(value)
	end
	return sanitized
end

-- Get current timestamp in ISO format
local function getTimestamp()
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

-- Extract character information
local function extractCharacterInfo(build)
	if not build or not build.calcsTab or not build.calcsTab.mainEnv then
		return {}
	end
	
	local env = build.calcsTab.mainEnv
	local character = {}
	
	-- Basic character info
	if env.build and env.build.characterLevel then
		character.level = env.build.characterLevel
	end
	
	if env.build and env.build.className then
		character.class = env.build.className
	end
	
	if env.build and env.build.ascendClassName then
		character.ascendancy = env.build.ascendClassName
	end
	
	return character
end

-- Extract compact stats (essential values only)
local function extractCompactStats(output)
	if not output then
		return {}
	end
	
	return extractDetailedStats(output, nil, nil, "compact")
end

-- Extract breakdown information from calculation environment  
local function extractBreakdown(breakdown, statName)
	if not breakdown or not breakdown[statName] then
		return nil
	end
	
	local breakdownData = breakdown[statName]
	local sources = {}
	
	-- Handle different breakdown structures
	if type(breakdownData) == "table" then
		-- Check if it's a modDB breakdown with rowList
		if breakdownData.rowList then
			for _, row in ipairs(breakdownData.rowList) do
				local source = categorizeSource(row.mod and row.mod.source)
				local sourceData = {
					type = (row.mod and row.mod.type) or "unknown",
					value = sanitizeValue(row.value or 0),
					source = source,
					sourceName = row.sourceName or (row.mod and row.mod.source) or "Unknown"
				}
				
				-- Add additional metadata if available
				if row.mod then
					if row.mod.flags and row.mod.flags ~= 0 then
						sourceData.flags = row.flags
					end
					if row.tags then
						sourceData.tags = row.tags
					end
				end
				
				table.insert(sources, sourceData)
			end
		else
			-- Handle simple breakdown structures
			for key, value in pairs(breakdownData) do
				if type(value) == "number" then
					table.insert(sources, {
						type = key,
						value = sanitizeValue(value),
						source = "Calculated",
						sourceName = key
					})
				elseif type(value) == "table" and value.value then
					table.insert(sources, {
						type = key,
						value = sanitizeValue(value.value),
						source = value.source or "Unknown",
						sourceName = value.name or key
					})
				end
			end
		end
	end
	
	return #sources > 0 and sources or nil
end

-- Categorize modifier sources
local function categorizeSource(sourceStr)
	if not sourceStr or type(sourceStr) ~= "string" then
		return "Unknown"
	end
	
	local sourceType = sourceStr:match("^([^:]+):")
	if sourceType then
		return sourceType
	end
	
	local lower = sourceStr:lower()
	if lower:find("item") or lower:find("gear") then
		return "Item"
	elseif lower:find("tree") or lower:find("passive") or lower:find("node") then
		return "Tree"
	elseif lower:find("skill") or lower:find("gem") or lower:find("aura") then
		return "Skill"
	elseif lower:find("pantheon") then
		return "Pantheon"
	elseif lower:find("config") or lower:find("custom") then
		return "Config"
	elseif lower:find("base") then
		return "Base"
	elseif lower:find("ascend") then
		return "Ascendancy"
	else
		return "Other"
	end
end

-- Extract source metadata for enrichment
local function extractSourceMetadata(source, build)
	if not source or not build then
		return {}
	end
	
	local metadata = {}
	
	-- Parse different source types
	if source:match("^Item:") then
		-- Extract item information: "Item:123:Helmet"
		local itemId, slot = source:match("Item:(%d+):?(.*)") 
		if itemId and build.itemsTab and build.itemsTab.items then
			local item = build.itemsTab.items[tonumber(itemId)]
			if item then
				metadata.itemName = item.name
				metadata.itemRarity = item.rarity
				metadata.itemSlot = slot or item.type
				metadata.itemId = tonumber(itemId)
			end
		end
	elseif source:match("^Tree:") then
		-- Extract passive tree node: "Tree:12345"
		local nodeId = source:match("Tree:(%d+)")
		if nodeId and build.spec then
			local nodeIdNum = tonumber(nodeId)
			local node = build.spec.nodes[nodeIdNum] or 
			            (build.spec.tree and build.spec.tree.nodes[nodeIdNum]) or
			            (build.latestTree and build.latestTree.nodes[nodeIdNum])
			if node then
				metadata.nodeName = node.dn
				metadata.nodeId = nodeIdNum
				if node.x and node.y then
					metadata.nodePosition = {x = node.x, y = node.y}
				end
			end
		end
	elseif source:match("^Skill:") then
		-- Extract skill information: "Skill:SkillName"
		local skillName = source:match("Skill:(.+)")
		if skillName and build.data and build.data.skills then
			local skill = build.data.skills[skillName]
			if skill then
				metadata.skillName = skill.name
				metadata.skillId = skillName
			end
		end
	elseif source:match("^Pantheon:") then
		-- Extract pantheon information: "Pantheon:GodName"
		local pantheonName = source:match("Pantheon:(.+)")
		if pantheonName then
			metadata.pantheonName = pantheonName
		end
	end
	
	return metadata
end

-- Extract minion stats if available
local function extractMinionStats(build, mode)
	if not build or not build.calcsTab or not build.calcsTab.mainEnv then
		return nil
	end
	
	local env = build.calcsTab.mainEnv
	if not env.minion or not env.minion.output then
		return nil
	end
	
	local minionOutput = env.minion.output
	local minionStats = {}
	
	-- Basic minion stats
	if minionOutput.TotalDPS then
		minionStats.totalDPS = sanitizeValue(minionOutput.TotalDPS)
	end
	if minionOutput.Life then
		minionStats.life = sanitizeValue(minionOutput.Life)
	end
	if minionOutput.EnergyShield then
		minionStats.energyShield = sanitizeValue(minionOutput.EnergyShield)
	end
	
	-- Add breakdown for full mode
	if mode == "full" and env.minion.breakdown then
		local breakdown = {}
		
		-- Process common minion stats
		local commonStats = {"Life", "EnergyShield", "TotalDPS", "AverageDamage"}
		for _, stat in ipairs(commonStats) do
			local breakdownData = extractBreakdown(env.minion.breakdown, stat)
			if breakdownData then
				breakdown[stat:lower()] = {
					total = sanitizeValue(minionOutput[stat]),
					breakdown = breakdownData
				}
			end
		end
		
		if next(breakdown) then
			minionStats.breakdown = breakdown
		end
	end
	
	return next(minionStats) and minionStats or nil
end

-- Enhanced stats extraction with detailed breakdown
local function extractDetailedStats(output, calcsOutput, breakdown, mode)
	local stats = {
		offensive = {},
		defensive = {},
		character = {}
	}
	
	-- Enhanced defensive stats processing
	local defensiveStats = {
		{key = "Life", field = "life"},
		{key = "EnergyShield", field = "energyShield"},
		{key = "Mana", field = "mana"},
		{key = "FireResist", field = "fireResist"},
		{key = "ColdResist", field = "coldResist"},
		{key = "LightningResist", field = "lightningResist"},
		{key = "ChaosResist", field = "chaosResist"}
	}
	
	for _, stat in ipairs(defensiveStats) do
		local value = output[stat.key]
		if value then
			if mode == "full" and breakdown then
				local breakdownData = extractBreakdown(breakdown, stat.key)
				if breakdownData then
					-- Enrich breakdown data with metadata
					for _, sourceData in ipairs(breakdownData) do
						local metadata = extractSourceMetadata(sourceData.sourceName, currentBuild)
						for key, val in pairs(metadata) do
							sourceData[key] = val
						end
					end
					
					stats.defensive[stat.field] = {
						total = sanitizeValue(value),
						breakdown = breakdownData
					}
				else
					stats.defensive[stat.field] = sanitizeValue(value)
				end
			else
				stats.defensive[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	-- Enhanced offensive stats processing
	local offensiveStats = {
		{key = "TotalDPS", field = "totalDPS"},
		{key = "AverageDamage", field = "averageHit"},
		{key = "CritChance", field = "critChance"},
		{key = "CritMultiplier", field = "critMultiplier"},
		{key = "HitChance", field = "hitChance"}
	}
	
	for _, stat in ipairs(offensiveStats) do
		local value = output[stat.key]
		if value then
			if mode == "full" and breakdown then
				local breakdownData = extractBreakdown(breakdown, stat.key)
				if breakdownData then
					-- Enrich breakdown data with metadata
					for _, sourceData in ipairs(breakdownData) do
						local metadata = extractSourceMetadata(sourceData.sourceName, currentBuild)
						for key, val in pairs(metadata) do
							sourceData[key] = val
						end
					end
					
					stats.offensive[stat.field] = {
						total = sanitizeValue(value),
						breakdown = breakdownData
					}
				else
					stats.offensive[stat.field] = sanitizeValue(value)
				end
			else
				stats.offensive[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	-- Enhanced character stats
	local characterStats = {
		{key = "Str", field = "strength"},
		{key = "Dex", field = "dexterity"},
		{key = "Int", field = "intelligence"}
	}
	
	for _, stat in ipairs(characterStats) do
		local value = output[stat.key]
		if value then
			if mode == "full" and breakdown then
				local breakdownData = extractBreakdown(breakdown, stat.key)
				if breakdownData then
					-- Enrich breakdown data with metadata
					for _, sourceData in ipairs(breakdownData) do
						local metadata = extractSourceMetadata(sourceData.sourceName, currentBuild)
						for key, val in pairs(metadata) do
							sourceData[key] = val
						end
					end
					
					stats.character[stat.field] = {
						total = sanitizeValue(value),
						breakdown = breakdownData
					}
				else
					stats.character[stat.field] = sanitizeValue(value)
				end
			else
				stats.character[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	-- Add weapon-specific stats if available
	if output.MainHand then
		stats.offensive.mainHand = {}
		local weaponStats = {
			{key = "PhysicalDPS", field = "physicalDPS"},
			{key = "ElementalDPS", field = "elementalDPS"},
			{key = "TotalDPS", field = "totalDPS"},
			{key = "PhysicalHitAverage", field = "physicalHitAverage"},
			{key = "ElementalHitAverage", field = "elementalHitAverage"}
		}
		
		for _, stat in ipairs(weaponStats) do
			local value = output.MainHand[stat.key]
			if value then
				stats.offensive.mainHand[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	if output.OffHand then
		stats.offensive.offHand = {}
		local weaponStats = {
			{key = "PhysicalDPS", field = "physicalDPS"},
			{key = "ElementalDPS", field = "elementalDPS"},
			{key = "TotalDPS", field = "totalDPS"},
			{key = "PhysicalHitAverage", field = "physicalHitAverage"},
			{key = "ElementalHitAverage", field = "elementalHitAverage"}
		}
		
		for _, stat in ipairs(weaponStats) do
			local value = output.OffHand[stat.key]
			if value then
				stats.offensive.offHand[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	-- Additional calcsOutput stats
	if calcsOutput then
		local additionalDefensive = {
			{key = "PhysicalMaximumHitTaken", field = "physicalMaxHit"},
			{key = "FireMaximumHitTaken", field = "fireMaxHit"},
			{key = "ColdMaximumHitTaken", field = "coldMaxHit"},
			{key = "LightningMaximumHitTaken", field = "lightningMaxHit"},
			{key = "ChaosMaximumHitTaken", field = "chaosMaxHit"}
		}
		
		for _, stat in ipairs(additionalDefensive) do
			local value = calcsOutput[stat.key]
			if value then
				stats.defensive[stat.field] = sanitizeValue(value)
			end
		end
	end
	
	return stats
end

-- Extract full stats with breakdown
local function extractFullStats(output, calcsOutput, breakdown)
	return extractDetailedStats(output, calcsOutput, breakdown, "full")
end

-- Main stats extraction function
local function extractStats(mode, category, sources)
	if not currentBuild or not currentBuild.calcsTab then
		return nil, "No build data available"
	end
	
	local output = currentBuild.calcsTab.mainOutput
	local calcsOutput = currentBuild.calcsTab.calcsOutput
	local breakdown = nil
	
	if currentBuild.calcsTab.mainEnv and currentBuild.calcsTab.mainEnv.player then
		breakdown = currentBuild.calcsTab.mainEnv.player.breakdown
	end
	
	local stats
	if mode == "full" then
		stats = extractFullStats(output, calcsOutput, breakdown)
	else
		stats = extractCompactStats(output)
	end
	
	-- Add minion stats if requested or if category is "all"
	if category == "minion" or category == "all" then
		local minionStats = extractMinionStats(currentBuild, mode)
		if minionStats then
			stats.minion = minionStats
		elseif category == "minion" then
			return nil, "No minion data available for this build"
		end
	end
	
	-- Filter by category if specified
	if category and category ~= "all" then
		local filtered = {}
		if stats[category] then
			filtered[category] = stats[category]
		else
			return nil, "Category '" .. category .. "' not found or not available"
		end
		stats = filtered
	end
	
	-- Filter by sources if specified (only applicable in full mode)
	if sources and mode == "full" then
		-- TODO: Implement source filtering
		-- This would filter breakdown data by source type (item, tree, skill, etc.)
	end
	
	return stats, nil
end

-- API endpoint handlers
local function handleStatus(request)
	local status = {
		status = "ok",
		timestamp = getTimestamp(),
		version = launch and launch.versionNumber or "unknown",
		build_loaded = currentBuild ~= nil
	}
	
	local body = json.encode(status)
	return createResponse(HTTP_STATUS.OK, MIME_TYPES.json, body)
end

local function handleCalcs(request)
	local mode = request.query.mode or "compact"
	local category = request.query.category or "all"
	local sources = request.query.sources
	
	-- Validate mode
	if mode ~= "compact" and mode ~= "full" then
		local error = {
			error = "Invalid mode. Must be 'compact' or 'full'",
			timestamp = getTimestamp()
		}
		local body = json.encode(error)
		return createResponse(HTTP_STATUS.BAD_REQUEST, MIME_TYPES.json, body)
	end
	
	-- Validate category
	local validCategories = {all = true, offensive = true, defensive = true, character = true, minion = true}
	if not validCategories[category] then
		local error = {
			error = "Invalid category. Must be one of: all, offensive, defensive, character, minion",
			timestamp = getTimestamp()
		}
		local body = json.encode(error)
		return createResponse(HTTP_STATUS.BAD_REQUEST, MIME_TYPES.json, body)
	end
	
	local stats, err = extractStats(mode, category, sources)
	if not stats then
		local error = {
			error = err or "Failed to extract stats",
			timestamp = getTimestamp()
		}
		local body = json.encode(error)
		return createResponse(HTTP_STATUS.SERVICE_UNAVAILABLE, MIME_TYPES.json, body)
	end
	
	local response = {
		timestamp = getTimestamp(),
		mode = mode,
		category = category,
		character = extractCharacterInfo(currentBuild)
	}
	
	-- Merge stats into response
	for key, value in pairs(stats) do
		response[key] = value
	end
	
	local body = json.encode(response)
	return createResponse(HTTP_STATUS.OK, MIME_TYPES.json, body)
end

local function handleCalcsOffensive(request)
	request.query.category = "offensive"
	return handleCalcs(request)
end

local function handleCalcsDefensive(request)
	request.query.category = "defensive"
	return handleCalcs(request)
end

local function handleCalcsCharacter(request)
	request.query.category = "character"
	return handleCalcs(request)
end

local function handleCalcsMinion(request)
	request.query.category = "minion"
	return handleCalcs(request)
end

-- Route mapping
local routes = {
	["/status"] = handleStatus,
	["/calcs"] = handleCalcs,
	["/calcs/offensive"] = handleCalcsOffensive,
	["/calcs/defensive"] = handleCalcsDefensive,
	["/calcs/character"] = handleCalcsCharacter,
	["/calcs/minion"] = handleCalcsMinion,
}

-- Simple HTTP server using basic socket operations
-- Note: This is a minimal implementation for local API access
local function handleRequest(clientSocket)
	local request = ""
	local timeout = 5  -- 5 second timeout
	local startTime = os.clock()
	
	-- Read request in chunks
	while true do
		local chunk, err = clientSocket:receive(1024)
		if chunk then
			request = request .. chunk
			-- Check if we have a complete request (simplified)
			if request:find("\r\n\r\n") then
				break
			end
		elseif err == "timeout" then
			-- Continue reading on timeout
		else
			-- Connection closed or error
			break
		end
		
		-- Check timeout
		if os.clock() - startTime > timeout then
			break
		end
	end
	
	if request == "" then
		clientSocket:close()
		return
	end
	
	local parsedRequest = parseRequest(request)
	if not parsedRequest then
		local errorResponse = createResponse(HTTP_STATUS.BAD_REQUEST, MIME_TYPES.text, "Bad Request")
		clientSocket:send(errorResponse)
		clientSocket:close()
		return
	end
	
	-- Handle OPTIONS for CORS
	if parsedRequest.method == "OPTIONS" then
		local optionsResponse = createResponse(HTTP_STATUS.OK, MIME_TYPES.text, "")
		clientSocket:send(optionsResponse)
		clientSocket:close()
		return
	end
	
	-- Route request
	local handler = routes[parsedRequest.path]
	if handler then
		local success, response = pcall(handler, parsedRequest)
		if success then
			clientSocket:send(response)
		else
			ConPrintf("HttpAPI: Error handling request: %s", tostring(response))
			local errorResponse = createResponse(HTTP_STATUS.INTERNAL_ERROR, MIME_TYPES.text, "Internal Server Error")
			clientSocket:send(errorResponse)
		end
	else
		local notFoundResponse = createResponse(HTTP_STATUS.NOT_FOUND, MIME_TYPES.text, "Not Found")
		clientSocket:send(notFoundResponse)
	end
	
	clientSocket:close()
end

-- Initialize HTTP server using coroutines for non-blocking operation
function httpAPI.startServer(port, build)
	if isRunning then
		ConPrintf("HttpAPI: Server already running on port %d", serverPort)
		return false
	end
	
	serverPort = port or 8080
	currentBuild = build
	
	-- Try to require socket library
	local socketOk, socket = pcall(require, "socket")
	if not socketOk then
		ConPrintf("HttpAPI: LuaSocket not available, using mock server for testing")
		isRunning = true
		ConPrintf("HttpAPI: Mock server started on port %d", serverPort)
		return true
	end
	
	-- Create server socket
	local success, err = pcall(function()
		server = socket.tcp()
		server:bind("127.0.0.1", serverPort)
		server:listen(5)
		server:settimeout(0) -- Non-blocking
	end)
	
	if not success then
		ConPrintf("HttpAPI: Failed to start server: %s", tostring(err))
		return false
	end
	
	isRunning = true
	ConPrintf("HttpAPI: Server started on http://127.0.0.1:%d", serverPort)
	
	-- Create coroutine for handling connections
	httpAPI.serverCoroutine = coroutine.create(function()
		while isRunning do
			local client, err = server:accept()
			if client then
				client:settimeout(5)
				-- Handle request in separate coroutine
				local requestCoroutine = coroutine.create(function()
					handleRequest(client)
				end)
				coroutine.resume(requestCoroutine)
			end
			-- Yield to allow other operations
			coroutine.yield()
		end
	end)
	
	return true
end

-- Process server requests (should be called regularly)
function httpAPI.processRequests()
	if isRunning and httpAPI.serverCoroutine then
		local status = coroutine.status(httpAPI.serverCoroutine)
		if status ~= "dead" then
			coroutine.resume(httpAPI.serverCoroutine)
		end
	end
end

-- Stop HTTP server
function httpAPI.stopServer()
	if not isRunning then
		return false
	end
	
	isRunning = false
	if server then
		server:close()
		server = nil
	end
	httpAPI.serverCoroutine = nil
	
	ConPrintf("HttpAPI: Server stopped")
	return true
end

-- Update build reference
function httpAPI.setBuild(build)
	currentBuild = build
end

-- Check if server is running
function httpAPI.isRunning()
	return isRunning
end

-- Get server status
function httpAPI.getStatus()
	return {
		running = isRunning,
		port = serverPort,
		build_loaded = currentBuild ~= nil
	}
end

-- Expose internal functions for testing
function httpAPI.extractStats(mode, category, sources)
	return extractStats(mode, category, sources)
end

function httpAPI.handleStatus(request)
	return handleStatus(request)
end

function httpAPI.handleCalcs(request)
	return handleCalcs(request)
end

return httpAPI