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
M.delivery = nil
M.arrow = nil
M.crossroads = nil

function M.CreatePBRMaterial(diffuseColor, metallic, roughness)
    local mat = Material:new()
    mat:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTexture.xml"))
    mat:SetShaderParameter("MatDiffColor", diffuseColor)
    mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
    mat:SetShaderParameter("Roughness", Variant(roughness or 0.8))
    return mat
end

function M.Init()
    M.road = M.CreatePBRMaterial(Color(0.85, 0.85, 0.82, 1.0), 0.0, 0.9)
    M.laneLine = M.CreatePBRMaterial(Color(0.6, 0.75, 0.88, 1.0), 0.0, 0.7)
    M.sidewalk = M.CreatePBRMaterial(Color(0.92, 0.88, 0.78, 1.0), 0.0, 0.85)
    M.curb = M.CreatePBRMaterial(Color(0.65, 0.72, 0.68, 1.0), 0.0, 0.75)
    M.buildingBase = M.CreatePBRMaterial(Color(0.55, 0.78, 0.82, 1.0), 0.0, 0.7)
    M.obstacleBlock = M.CreatePBRMaterial(Color(0.95, 0.45, 0.35, 1.0), 0.1, 0.6)
    M.obstacleLow = M.CreatePBRMaterial(Color(0.95, 0.75, 0.25, 1.0), 0.0, 0.7)
    M.obstacleHigh = M.CreatePBRMaterial(Color(0.85, 0.35, 0.75, 1.0), 0.1, 0.6)
    M.pickup = M.CreatePBRMaterial(Color(0.3, 0.9, 0.4, 1.0), 0.2, 0.5)
    M.delivery = M.CreatePBRMaterial(Color(1.0, 0.85, 0.2, 1.0), 0.3, 0.4)
    M.arrow = M.CreatePBRMaterial(Color(0.2, 0.9, 1.0, 1.0), 0.3, 0.4)
    M.crossroads = M.CreatePBRMaterial(Color(0.78, 0.80, 0.76, 1.0), 0.0, 0.85)
end

return M
