# HTTP API Usage Examples

This document provides examples of how to use the HTTP API to extract Path of Building calculation data.

## Starting the API

The HTTP API automatically starts when Path of Building is run in development mode or when explicitly enabled.

### Automatic Start (Dev Mode)
```bash
# Run PoB from a git repository (dev mode auto-enabled)
cd PathOfBuilding
lua src/Launch.lua
```

### Manual Enable
```lua
-- In Launch.lua, set apiMode before starting
launch.apiMode = true
launch.apiPort = 8080  -- Optional, defaults to 8080
```

## API Endpoints

### Health Check
```bash
curl http://localhost:8080/status
```

Response:
```json
{
  "status": "ok",
  "timestamp": "2025-01-20T15:30:45Z",
  "version": "2.0.0",
  "build_loaded": true
}
```

### Get All Stats (Compact Mode)
```bash
curl "http://localhost:8080/calcs?mode=compact"
```

Response:
```json
{
  "timestamp": "2025-01-20T15:30:45Z",
  "mode": "compact",
  "category": "all",
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
    "hitChance": 95.2,
    "mainHand": {
      "physicalDPS": 1000,
      "elementalDPS": 500,
      "totalDPS": 1500
    }
  },
  "defensive": {
    "life": 6500,
    "energyShield": 2000,
    "mana": 1200,
    "resistances": {
      "fire": 75,
      "cold": 76,
      "lightning": 75,
      "chaos": 15
    },
    "physicalMaxHit": 5000,
    "fireMaxHit": 3000
  },
  "character": {
    "strength": 150,
    "dexterity": 200,
    "intelligence": 300
  }
}
```

### Get Defensive Stats Only
```bash
curl "http://localhost:8080/calcs/defensive?mode=compact"
```

### Get Full Breakdown Data
```bash
curl "http://localhost:8080/calcs/defensive?mode=full"
```

Response:
```json
{
  "timestamp": "2025-01-20T15:30:45Z",
  "mode": "full",
  "category": "defensive",
  "character": {
    "level": 90,
    "class": "Witch",
    "ascendancy": "Necromancer"
  },
  "defensive": {
    "life": {
      "total": 6500,
      "breakdown": [
        {
          "type": "BASE",
          "value": 484,
          "source": "Base",
          "sourceName": "Base life at level 90"
        },
        {
          "type": "INC",
          "value": 180,
          "source": "Tree",
          "sourceName": "Life nodes",
          "nodeName": "Constitution",
          "nodeId": 26725,
          "nodePosition": {"x": 100, "y": 200}
        },
        {
          "type": "BASE",
          "value": 79,
          "source": "Item",
          "sourceName": "Rare Gold Ring",
          "itemName": "Rare Gold Ring",
          "itemRarity": "RARE",
          "itemSlot": "Ring",
          "itemId": 15
        }
      ]
    },
    "energyShield": {
      "total": 2000,
      "breakdown": [
        {
          "type": "BASE",
          "value": 120,
          "source": "Item",
          "sourceName": "Rare Hubris Circlet",
          "itemName": "Rare Hubris Circlet",
          "itemRarity": "RARE",
          "itemSlot": "Helmet",
          "itemId": 12
        }
      ]
    }
  }
}
```

## Query Parameters

### mode
- `compact` (default): Essential values only
- `full`: Complete breakdown with modifier sources

### category
- `all` (default): All stat categories
- `offensive`: Damage, crit, hit chance, etc.
- `defensive`: Life, ES, resistances, max hit taken, etc.
- `character`: Attributes, level, class
- `minion`: Minion stats (if applicable)

### sources (full mode only)
- Filter breakdown data by source type
- Comma-separated list: `item,tree,skill,pantheon`

## Error Responses

### 400 Bad Request
```json
{
  "error": "Invalid mode. Must be 'compact' or 'full'",
  "timestamp": "2025-01-20T15:30:45Z"
}
```

### 503 Service Unavailable
```json
{
  "error": "No build data available",
  "timestamp": "2025-01-20T15:30:45Z"
}
```

## Integration Examples

### External DPS Calculator
```javascript
// Get essential DPS data for external processing
fetch('http://localhost:8080/calcs/offensive?mode=compact')
  .then(response => response.json())
  .then(data => {
    console.log('Total DPS:', data.offensive.totalDPS);
    console.log('Crit Chance:', data.offensive.critChance);
  });
```

### Build Optimization Tool
```python
import requests
import json

# Get detailed defensive breakdown
response = requests.get('http://localhost:8080/calcs/defensive?mode=full')
data = response.json()

# Analyze life sources
life_breakdown = data['defensive']['life']['breakdown']
for source in life_breakdown:
    if source['source'] == 'Item':
        print(f"Item {source['itemName']} contributes {source['value']} life")
    elif source['source'] == 'Tree':
        print(f"Passive node {source['nodeName']} contributes {source['value']} life")
```

### Passive Tree Analyzer
```bash
# Get all tree contributions for heat map generation
curl "http://localhost:8080/calcs?mode=full&sources=tree" | \
  jq '.[] | .breakdown[]? | select(.source == "Tree") | {nodeId, value, sourceName}'
```

## CORS Support

The API includes CORS headers for browser-based applications:
- `Access-Control-Allow-Origin: *`
- `Access-Control-Allow-Methods: GET, POST, OPTIONS`
- `Access-Control-Allow-Headers: Content-Type`

## Local Development

For local development and testing:

1. Enable dev mode by running PoB from git repository
2. API starts automatically on http://localhost:8080
3. Check status: `curl http://localhost:8080/status`
4. Test with browser: Open http://localhost:8080/calcs in browser

## Notes

- API only binds to localhost (127.0.0.1) for security
- No authentication required (local access only)
- Calculations update in real-time as build changes
- Server handles one request at a time (sufficient for local use)
- Mock server mode available if LuaSocket not installed