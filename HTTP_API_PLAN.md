# HTTP API Implementation Plan

## Overview
Create a minimal HTTP API module for Path of Building that exposes calculation results and configuration without modifying core application logic.

## Architecture Decisions

### 1. HTTP Server Choice
**Decision**: Use LuaSocket for HTTP server
**Rationale**: 
- Already available in PoB runtime environment
- Lightweight and suitable for local API
- Non-blocking operation possible
**Alternative**: External HTTP proxy, but adds complexity

### 2. API Integration Point  
**Decision**: Hook into existing calculation refresh cycle
**Rationale**:
- Calculations are already cached in `build.calcsTab.mainOutput`
- Minimal disruption to existing flow
- Data consistency with UI
**Alternative**: Direct ModDB access, but requires reimplementing calculation logic

### 3. JSON Serialization
**Decision**: Custom JSON encoder using existing `dkjson.lua` 
**Rationale**:
- Already included in PoB runtime
- Handles Lua table structures well
**Alternative**: Manual string building, but error-prone

## Feature 1: Export Calculations in JSON Format

### Implementation Plan

#### Step 1: Create HTTP API Module
- **File**: `src/Modules/HttpAPI.lua`
- **Purpose**: Main HTTP server and routing logic
- **Key Functions**:
  - `startServer(port)` - Initialize HTTP server
  - `handleCalcsExport(request)` - Export calculations endpoint
  - `serializeCalcsOutput(output)` - Convert calculations to JSON

#### Step 2: Data Export Strategy

**Export Modes**: Two API modes to balance usability vs. detail
- **Compact Mode**: Essential values only for external tool integrations
- **Full Mode**: Complete breakdown data with all sources and modifiers

**Source Data**: 
- `build.calcsTab.mainOutput` and `build.calcsTab.calcsOutput` for final values
- `build.calcsTab.calcsEnv.player.breakdown` and `build.calcsTab.calcsEnv.minion.breakdown` for detailed source tracking
- Individual mod sources from ModDB with source categorization

**Key Output Categories**:
- **Offensive Stats**: DPS, hit damage, crit chance, accuracy
- **Defensive Stats**: Life, ES, resistances, armour, evasion  
- **Character Stats**: Attributes, charges, life/mana reservations
- **Skill Stats**: Cast/attack speed, mana costs, area of effect
- **Minion Stats**: If applicable, all minion calculations

**JSON Structure Examples**:

**Compact Mode**:
```json
{
  "timestamp": "2025-10-20T...",
  "mode": "compact",
  "character": {
    "level": 90,
    "class": "Witch",
    "ascendancy": "Necromancer"
  },
  "offensive": {
    "totalDPS": 1234567.89,
    "averageHit": 12345.67,
    "critChance": 75.5,
    "critMultiplier": 450,
    "hitChance": 95.2
  },
  "defensive": {
    "life": 6500,
    "energyShield": 2000,
    "resistances": {
      "fire": 75,
      "cold": 76,
      "lightning": 75,
      "chaos": 15
    }
  }
}
```

**Full Mode with Breakdown**:
```json
{
  "timestamp": "2025-10-20T...",
  "mode": "full",
  "character": {
    "level": 90,
    "class": "Witch",
    "ascendancy": "Necromancer"
  },
  "defensive": {
    "energyShield": {
      "total": 2000,
      "breakdown": {
        "base": [
          {
            "value": 120,
            "source": "Item",
            "sourceName": "Rare Hubris Circlet",
            "sourceSlot": "Helmet",
            "itemId": 15
          },
          {
            "value": 200,
            "source": "Item", 
            "sourceName": "Rare Vaal Regalia",
            "sourceSlot": "Body Armour",
            "itemId": 12
          }
        ],
        "increased": [
          {
            "value": 150,
            "source": "Tree",
            "sourceName": "Energy Shield node cluster",
            "nodeId": 48958
          },
          {
            "value": 45,
            "source": "Item",
            "sourceName": "Rare Diamond Ring",
            "sourceSlot": "Ring 1",
            "modifier": "45% increased maximum Energy Shield"
          }
        ],
        "more": [
          {
            "value": 15,
            "source": "Skill",
            "sourceName": "Discipline",
            "skillId": "Discipline"
          }
        ],
        "flat": [
          {
            "value": 89,
            "source": "Item",
            "sourceName": "Rare Sapphire Ring",
            "sourceSlot": "Ring 2", 
            "modifier": "+89 to maximum Energy Shield"
          }
        ]
      }
    },
    "life": {
      "total": 6500,
      "breakdown": {
        "base": [
          {
            "value": 484,
            "source": "Base",
            "sourceName": "Base life at level 90"
          }
        ],
        "flat": [
          {
            "value": 79,
            "source": "Item",
            "sourceName": "Rare Gold Ring", 
            "sourceSlot": "Ring 1",
            "modifier": "+79 to maximum Life"
          }
        ],
        "increased": [
          {
            "value": 180,
            "source": "Tree", 
            "sourceName": "Life nodes",
            "nodeId": 26725
          }
        ]
      }
    }
  }
}
```

**Source Type Categories**:
- **Item**: Equipment with item name, rarity, slot, and specific modifier text
- **Tree**: Passive tree nodes with node name and ID for location lookup
- **Skill**: Active skills, auras, buffs with skill name and ID
- **Pantheon**: Pantheon powers with god name
- **Config**: Configuration settings and custom modifiers
- **Base**: Character base stats (life, attributes)
- **Ascendancy**: Ascendancy passive effects

#### Step 3: Minimal Core Integration
**File**: `src/Launch.lua` (minimal changes)
- Add optional HTTP server initialization
- Check for dev mode or explicit API enable flag
- Fail gracefully if HTTP not available

**Changes**:
```lua
-- Near end of Launch.lua OnInit()
if launch.devMode or launch.apiMode then
    local httpAPI = LoadModule("Modules/HttpAPI")
    if httpAPI then
        httpAPI.startServer(launch.apiPort or 8080)
    end
end
```

#### Step 4: Data Extraction Functions
**Key Challenge**: Extract nested calculation data with complete source tracking
**Solution**: Dual-mode extraction with breakdown integration

**Core Functions needed**:
- `extractNumericStats(output, category, mode)` - Get calculations (compact/full)
- `extractBreakdownData(breakdown, statName)` - Extract modifier sources and values
- `categorizeModifierSources(modList)` - Group by Item/Tree/Skill/etc.
- `flattenNestedStats(output)` - Handle MainHand/OffHand structures
- `sanitizeForJSON(value)` - Handle NaN, infinite values
- `buildSourceMetadata(source, build)` - Enrich source data with names/tooltips

**Breakdown Processing**:
- Parse `breakdown.slots` tables for gear-based stats (ES, Armor, Life)
- Extract `breakdown.modList` for modifier source tracking
- Handle source type categorization: "Item:123:Helmet" → Item metadata
- Process flags and tags for conditional modifiers
- Include mod value calculations (base, increased, more, flat)

**Source Metadata Enhancement**:
- **Items**: Extract rarity, name, slot, specific modifier text from `build.itemsTab.items[itemId]`
- **Tree Nodes**: Get node name and coordinates from `build.spec.nodes[nodeId]` 
- **Skills**: Map skill IDs to display names from `build.data.skills[skillId]`
- **Pantheon**: Extract god and power names from source strings

#### Step 5: Endpoint Routing
**Routes**:
- `GET /calcs?mode=compact` - Essential calculations only (default)
- `GET /calcs?mode=full` - Complete calculations with breakdown sources
- `GET /calcs/offensive?mode=full` - Offensive stats with all modifier sources
- `GET /calcs/defensive?mode=full` - Defensive stats with gear/tree/skill sources  
- `GET /calcs/minion?mode=full` - Minion stats with breakdown (if applicable)
- `GET /status` - API health check

**Query Parameters**:
- `mode=compact|full` - Control level of detail in response
- `category=offensive|defensive|character|minion` - Filter specific stat categories
- `sources=item|tree|skill|pantheon` - Filter breakdown by source types (full mode only)

### Error Handling Strategy
- Return HTTP 500 for calculation errors
- Return HTTP 404 for non-existent data (e.g., minion stats on non-minion build)
- Return HTTP 503 if calculations not ready/valid
- Log errors to console without breaking main application

### Development Workflow
1. Create basic HTTP server module with health check endpoint
2. Add calculation data access (read-only from existing structures)  
3. Implement JSON serialization for core stats
4. Add specific stat category endpoints
5. Add error handling and edge cases
6. Test with various build types (attack, spell, minion, hybrid)

### Testing Approach
- Test with builds from `spec/TestBuilds/` directory  
- Verify JSON output matches expected calculation values in both modes
- Ensure breakdown data correctly maps sources to modifiers
- Test source metadata enrichment (item names, node names, skill names)
- Validate that compact mode provides essential data efficiently  
- Verify full mode includes comprehensive source tracking
- Ensure API doesn't interfere with normal PoB operation
- Test server startup/shutdown gracefully
- Test with various build types (attack, spell, minion, hybrid, CI, LL)

### Example API Usage Scenarios

**External DPS Calculator Integration** (Compact Mode):
```bash
curl "http://localhost:8080/calcs/offensive?mode=compact"
# Returns just final DPS numbers for external tool processing
```

**Build Optimization Tool** (Full Mode):
```bash  
curl "http://localhost:8080/calcs/defensive?mode=full&sources=item,tree"
# Returns complete life/ES breakdown showing which gear and passive 
# nodes contribute how much, enabling optimization suggestions
```

**Passive Tree Analyzer**:
```bash
curl "http://localhost:8080/calcs?mode=full&sources=tree"
# Returns all stat contributions from passive tree with node IDs
# for creating passive tree heat maps or efficiency analysis
```

### Future Feature Integration Points
- **Feature 2** (Config modification): Extend routing to handle POST/PUT to `/config/*`
- **Feature 3** (URL import): Add `POST /import` endpoint with URL parameter

### Deployment Considerations
- API only enabled in dev mode by default
- Optional command-line flag to enable in production builds
- Configurable port (default 8080)
- Only bind to localhost for security
- No authentication initially (local access only)

This approach maintains the core principle of minimal modification while providing robust calculation export functionality that external tools can consume.