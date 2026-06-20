-- ============================================================================
-- 外卖冲冲冲 - 材质模块
-- ============================================================================

local M = {}

-- 材质缓存
M.road = nil
M.laneLine = nil
M.sidewalk = nil
M.curb = nil
M.buildingBase = nil
M.obstacleBlock = nil
M.obstacleLow = nil
M.obstacleHigh = nil
M.pickup = nil
M.pickupAccent = nil
M.pickupHandle = nil
M.delivery = nil
M.deliveryAccent = nil
M.deliveryMarker = nil
M.powerupBase = nil
M.powerupShield = nil
M.powerupClock = nil
M.arrow = nil
M.crossroads = nil
M.shadow = nil

function M.CreatePBRMaterial(diffuseColor, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", diffuseColor)
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.8))
    return mat
end

function M.Init()
    M.road = M.CreatePBRMaterial(Color(0.13, 0.19, 0.23, 1.0), 0.0, 0.82)
    M.laneLine = M.CreatePBRMaterial(Color(0.96, 0.99, 1.0, 1.0), 0.0, 0.62)
    M.sidewalk = M.CreatePBRMaterial(Color(1.0, 0.94, 0.74, 1.0), 0.0, 0.82)
    M.curb = M.CreatePBRMaterial(Color(0.60, 0.88, 0.92, 1.0), 0.0, 0.75)
    M.buildingBase = M.CreatePBRMaterial(Color(0.32, 0.72, 0.86, 1.0), 0.0, 0.68)
    M.obstacleBlock = M.CreatePBRMaterial(Color(0.95, 0.37, 0.44, 1.0), 0.1, 0.55)
    M.obstacleLow = M.CreatePBRMaterial(Color(1.0, 0.83, 0.28, 1.0), 0.0, 0.62)
    M.obstacleHigh = M.CreatePBRMaterial(Color(1.0, 0.53, 0.10, 1.0), 0.1, 0.55)
    M.pickup = M.CreatePBRMaterial(Color(1.0, 0.53, 0.10, 1.0), 0.18, 0.46)
    M.pickupAccent = M.CreatePBRMaterial(Color(1.0, 0.85, 0.28, 1.0), 0.1, 0.42)
    M.pickupHandle = M.CreatePBRMaterial(Color(0.74, 0.36, 0.05, 1.0), 0.08, 0.56)
    M.delivery = M.CreatePBRMaterial(Color(0.17, 0.72, 0.94, 1.0), 0.22, 0.34)
    M.deliveryAccent = M.CreatePBRMaterial(Color(0.18, 0.55, 1.0, 1.0), 0.22, 0.34)
    M.deliveryMarker = M.CreatePBRMaterial(Color(1.0, 0.83, 0.28, 1.0), 0.18, 0.36)
    M.powerupBase = M.CreatePBRMaterial(Color(0.09, 0.16, 0.22, 1.0), 0.1, 0.5)
    M.powerupShield = M.CreatePBRMaterial(Color(0.18, 0.55, 1.0, 1.0), 0.2, 0.34)
    M.powerupClock = M.CreatePBRMaterial(Color(1.0, 0.83, 0.28, 1.0), 0.15, 0.36)
    M.arrow = M.CreatePBRMaterial(Color(0.07, 0.77, 0.70, 1.0), 0.24, 0.36)
    M.crossroads = M.CreatePBRMaterial(Color(0.13, 0.19, 0.23, 1.0), 0.0, 0.82)
    M.shadow = M.CreatePBRMaterial(Color(0.07, 0.12, 0.16, 1.0), 0.0, 1.0)
end

return M
