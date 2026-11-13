FacilityData = { units = {}, containers = {}, doors = {}, barriers = {}, sites = {}, siteByKey = {}, unitSite = {} }

local ORDER = { 'paleto', 'sandy', 'cypress' }

local keys, seen = {}, {}
for _, k in ipairs(ORDER) do
    if FacilitySites and FacilitySites[k] then keys[#keys + 1] = k; seen[k] = true end
end
local extra = {}
for k in pairs(FacilitySites or {}) do if not seen[k] then extra[#extra + 1] = k end end
table.sort(extra)
for _, k in ipairs(extra) do keys[#keys + 1] = k end

for _, k in ipairs(keys) do
    local s = FacilitySites[k]
    local site = { key = k, label = s.label, reception = s.reception, trade = s.trade, gate = s.gate, lot = s.lot }
    FacilityData.sites[#FacilityData.sites + 1] = site
    FacilityData.siteByKey[k] = site
    for _, list in ipairs({ 'units', 'containers', 'doors', 'barriers' }) do
        for _, e in ipairs(s[list] or {}) do
            e.site = k
            local dst = FacilityData[list]
            dst[#dst + 1] = e
        end
    end
    for _, u in ipairs(s.units or {}) do FacilityData.unitSite[u.id] = k end
    for _, c in ipairs(s.containers or {}) do FacilityData.unitSite[c.id] = k end
end

local MainKinds = { shutter = true, cdoor = true }
FacilityData.mainDoors, FacilityData.hatches = {}, {}
for _, d in ipairs(FacilityData.doors) do
    if MainKinds[d.kind] then
        FacilityData.mainDoors[d.unit] = FacilityData.mainDoors[d.unit] or {}
        table.insert(FacilityData.mainDoors[d.unit], d.id)
    elseif d.kind == 'hatch' then
        FacilityData.hatches[#FacilityData.hatches + 1] = d
    end
end

function FacilityData.overHatch(unit, pos, margin)
    margin = margin or 0.3
    for _, d in ipairs(FacilityData.hatches) do
        if d.unit == unit then
            local r = math.rad(d.heading)
            local dx, dy = pos.x - d.coords.x, pos.y - d.coords.y
            local lx = dx * math.cos(r) + dy * math.sin(r)
            local ly = -dx * math.sin(r) + dy * math.cos(r)
            if math.abs(lx) <= d.w / 2 + margin and ly <= margin and ly >= -d.d - margin then return true end
        end
    end
    return false
end
