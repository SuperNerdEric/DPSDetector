local _, ns = ...

-- Warcraft Logs parse colors:
--   0-24  grey (common)
--  25-49  green (uncommon)
--  50-74  blue (rare)
--  75-94  purple (epic)
--  95-98  orange (legendary)
--     99  pink (astounding)
--    100  gold (perfect)

local TIERS = {
    { min = 100, r = 0.898, g = 0.800, b = 0.502 }, -- #e5cc80
    { min = 99,  r = 0.886, g = 0.408, b = 0.659 }, -- #e268a8
    { min = 95,  r = 1.000, g = 0.502, b = 0.000 }, -- #ff8000
    { min = 75,  r = 0.639, g = 0.208, b = 0.933 }, -- #a335ee
    { min = 50,  r = 0.000, g = 0.439, b = 0.867 }, -- #0070dd
    { min = 25,  r = 0.118, g = 1.000, b = 0.000 }, -- #1eff00
    { min = 0,   r = 0.400, g = 0.400, b = 0.400 }, -- #666666
}

function ns.GetParseColor(percentile)
    percentile = tonumber(percentile) or 0
    for i = 1, #TIERS do
        local tier = TIERS[i]
        if percentile >= tier.min then
            return tier.r, tier.g, tier.b
        end
    end
    return 0.4, 0.4, 0.4
end

function ns.WrapParseText(text, percentile)
    local r, g, b = ns.GetParseColor(percentile)
    return format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, text)
end
