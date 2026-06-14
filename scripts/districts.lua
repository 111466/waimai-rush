-- ============================================================================
-- Waimai Rush - district rules
-- ============================================================================

local M = {}

M.defs = {
    downtown = {
        id = "downtown",
        name = "Downtown",
        roadColor = Color(0.78, 0.80, 0.84, 1.0),
        palette = {
            Color(0.55, 0.66, 0.78, 1.0),
            Color(0.72, 0.78, 0.84, 1.0),
            Color(0.84, 0.77, 0.72, 1.0),
            Color(0.62, 0.58, 0.78, 1.0),
        },
        buildingChance = 0.86,
        buildingDensity = 1.20,
        heightMin = 4.5,
        heightMax = 12.0,
        obstacleSpacing = 0.92,
        reward = 1.10,
        orderTime = 1.00,
        pickupInterval = 0.92,
    },
    residential = {
        id = "residential",
        name = "Residential",
        roadColor = Color(0.82, 0.79, 0.73, 1.0),
        palette = {
            Color(0.80, 0.84, 0.74, 1.0),
            Color(0.90, 0.80, 0.72, 1.0),
            Color(0.74, 0.80, 0.88, 1.0),
            Color(0.86, 0.70, 0.72, 1.0),
        },
        buildingChance = 0.68,
        buildingDensity = 0.88,
        heightMin = 2.8,
        heightMax = 6.2,
        obstacleSpacing = 1.10,
        reward = 0.95,
        orderTime = 1.08,
        pickupInterval = 1.05,
    },
    market = {
        id = "market",
        name = "Market",
        roadColor = Color(0.80, 0.71, 0.63, 1.0),
        palette = {
            Color(0.94, 0.68, 0.40, 1.0),
            Color(0.86, 0.56, 0.40, 1.0),
            Color(0.38, 0.82, 0.78, 1.0),
            Color(0.94, 0.83, 0.44, 1.0),
        },
        buildingChance = 0.82,
        buildingDensity = 1.04,
        heightMin = 3.5,
        heightMax = 8.8,
        obstacleSpacing = 0.88,
        reward = 1.25,
        orderTime = 0.93,
        pickupInterval = 0.88,
    },
    park = {
        id = "park",
        name = "Park",
        roadColor = Color(0.74, 0.80, 0.70, 1.0),
        palette = {
            Color(0.62, 0.76, 0.62, 1.0),
            Color(0.70, 0.82, 0.74, 1.0),
            Color(0.84, 0.88, 0.72, 1.0),
            Color(0.72, 0.78, 0.86, 1.0),
        },
        buildingChance = 0.56,
        buildingDensity = 0.74,
        heightMin = 2.4,
        heightMax = 5.2,
        obstacleSpacing = 1.18,
        reward = 0.90,
        orderTime = 1.12,
        pickupInterval = 1.12,
    },
    construction = {
        id = "construction",
        name = "Construction",
        roadColor = Color(0.82, 0.75, 0.60, 1.0),
        palette = {
            Color(0.86, 0.70, 0.28, 1.0),
            Color(0.84, 0.60, 0.32, 1.0),
            Color(0.60, 0.60, 0.64, 1.0),
            Color(0.90, 0.52, 0.28, 1.0),
        },
        buildingChance = 0.80,
        buildingDensity = 1.00,
        heightMin = 3.8,
        heightMax = 9.5,
        obstacleSpacing = 0.82,
        reward = 1.35,
        orderTime = 0.86,
        pickupInterval = 0.86,
    },
}

function M.Get(id)
    return M.defs[id] or M.defs.downtown
end

function M.ByGrid(gx, gz, gridSize)
    local center = math.ceil(gridSize / 2)
    if math.abs(gx - center) <= 0.55 or math.abs(gz - center) <= 0.55 then
        return M.defs.downtown
    end
    if gx < center and gz < center then
        return M.defs.residential
    end
    if gx > center and gz < center then
        return M.defs.market
    end
    if gx < center and gz > center then
        return M.defs.park
    end
    return M.defs.construction
end

return M
