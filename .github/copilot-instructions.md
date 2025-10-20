# Path of Building Community Fork - AI Agent Guide

## Architecture Overview

**Path of Building** is a Lua-based offline build planner for Path of Exile. The application uses a custom 2D graphics host (SimpleGraphic) and follows a modular calculation engine architecture.

### Core Components

- **Launch.lua**: Entry point handling updates, dev mode detection, and initialization
- **Main.lua**: Application controller managing two modes: BUILD and LIST (build selection)
- **Calculation Engine**: ModDB → ModList → CalcPerform pipeline for stat computations
- **UI System**: Control-based hierarchy with tab management (Tree, Skills, Items, Calcs, etc.)

### Key Architectural Patterns

**ModDB/ModList System**: The heart of PoB's calculations. ModDB stores modifiers by stat name, ModList processes them with conditions/flags. All game mechanics flow through this:
```lua
modDB:AddMod(mod("Damage", "INC", 50, "Source"))
local totalInc = modDB:Sum("INC", skillCfg, "Damage")
```

**Tab Architecture**: Each game aspect is a separate tab class (`TreeTab.lua`, `ItemsTab.lua`, `SkillsTab.lua`) inheriting from base controls, managing their own state and UI.

**Calculation Flow**: `CalcSetup.lua` → `CalcPerform.lua` → `CalcOffence.lua`/`CalcDefence.lua` → final stats. Environment (`env`) object carries context between calculation phases.

## Development Conventions

**File Organization**:
- `src/Classes/`: UI controls and core classes (Item, ModDB, PassiveTree)  
- `src/Modules/`: Business logic (calculation engine, data loading)
- `src/Data/`: Game data (skills, items, mods) - mostly generated from GGPK exports
- `spec/System/`: Busted tests for calculations and game mechanics

**Naming Patterns**:
- Classes use PascalCase with "Class" suffix: `ItemClass`, `ModDBClass`
- Modules use snake_case for functions: `calcs.buildModListForNode()`
- UI controls end with "Control": `ButtonControl`, `EditControl`
- Configuration uses descriptive keys: `Cond:UsingFlask`, `Flag:DualWielding`

**ModDB Integration**: When adding game mechanics, always work through ModDB:
```lua
-- Add modifier
modDB:NewMod("Damage", "INC", value, "MySource", { type = "Hit" })
-- Check conditions  
if modDB:Flag(cfg, "Crit") then ...
-- Scale calculations
local mult = modDB:More(cfg, "Damage", "Spell")
```

## Testing & Validation

**Test Structure**: Use Busted framework. Test builds are in `spec/TestBuilds/` as XML + expected output Lua files.

**Running Tests**: 
```bash
docker-compose run busted-tests
# OR for specific tests
docker-compose run busted-tests --pattern="TestSkills"
```

**Adding Calculation Tests**: Create build XMLs with `spec/GenerateBuilds.lua`, verify outputs in `TestBuilds_spec.lua`.

## Critical Development Workflows

**Build System**: No traditional build - Lua files are loaded dynamically. Use dev mode (`launch.devMode = true`) for development.

**Data Updates**: Game data comes from GGPK exports. Run `ModParser.lua` to regenerate `ModCache` after data changes.

**Debugging**: Use `ConPrintf()` for console output. Enable breakdown analysis in Calcs tab for modifier debugging.

**Version Management**: `manifest.xml` tracks file checksums for auto-updates. Run `update_manifest.py` when adding new files.

## Integration Points

**Path of Exile Data**: Game mechanics are reverse-engineered from GGPK files. Critical files:
- `ActiveSkills.dat`, `GrantedEffects.dat` → skill definitions
- `PassiveSkills.dat` → passive tree data  
- `Mods.dat` → item modifiers

**External Build Sharing**: Import/Export system supports PoEPlanner, pastebin links via base64 encoding in `ImportTab.lua`.

**Party Integration**: `PartyTab.lua` handles auras, curses, and buffs affecting party members with separate ModDB instances.

When modifying calculations, always test with multiple build archetypes and verify against in-game tooltips. The calculation system is the application's core value proposition.

## Project-Specific Development Goals

**HTTP API Integration**: This fork focuses on adding a non-intrusive HTTP API module to expose application state for external tools. The design philosophy is minimal modification of existing files to maintain easy upstream updates.

**Core API Features**:
1. Export calculation results in JSON format from `build.calcsTab.mainOutput`
2. Query/modify configuration options from `ConfigOptions.lua`
3. Import builds from URLs

**Development Principles**:
- Minimize changes to existing core files - prefer adding new modules over modifying existing ones
- Use composition/extension patterns rather than direct modification
- Keep API as a separate, optional layer that doesn't affect normal PoB operation
- Structure code for easy upstream merging by isolating API functionality

**Key Implementation Areas**:
- Create `src/Modules/HttpAPI.lua` for main API logic
- Add HTTP server initialization in `Launch.lua` with minimal changes
- Export calculation data from `build.calcsTab.mainOutput` and `build.calcsTab.calcsOutput`
- Access config system through existing `build.configTab` interface

## Usage Examples for AI Agents

**Common Development Tasks**:
```
"Add a new modifier calculation for skill X"
"Fix damage calculation bug in elemental conversion"  
"Add HTTP endpoint to export DPS calculations"
"Update passive tree data after game patch"
"Add config option for new game mechanic"
```

**Calculation Debugging**:
```
"Why is this build's DPS calculation incorrect?"
"Debug ModDB entries for this specific modifier"
"Trace calculation flow for minion damage"
```

**API Development**:
```
"Add JSON export for all offensive stats"
"Create endpoint to modify enemy resistance configs"  
"Implement build import from pastebin URL"
```

**Implementation Reference**: See `HTTP_API_PLAN.md` for detailed implementation strategy, architectural decisions, and step-by-step development workflow for the HTTP API features.