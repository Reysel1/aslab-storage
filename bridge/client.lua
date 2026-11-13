Bridge = {}

local function running(name)
    local s = GetResourceState(name)
    return s == 'started' or s == 'starting'
end

local function detect(setting, list)
    if setting and setting ~= 'auto' then return setting end
    for _, name in ipairs(list) do if running(name) then return name end end
end

local Icons = {
    rent = 'fas fa-key',
    sale = 'fas fa-tag',
    stash = 'fas fa-box-open',
    panel = 'fas fa-th-large',
    code = 'fas fa-keyboard',
    raise = 'fas fa-arrow-up',
    lower = 'fas fa-arrow-down',
    police = 'fas fa-shield-alt',
    lockpick = 'fas fa-unlock',
    reception = 'fas fa-concierge-bell',
    trade = 'fas fa-balance-scale',
    open = 'fas fa-door-open',
    close = 'fas fa-door-closed',
    archive = 'fas fa-archive',
    move = 'fas fa-arrows-alt',
    dismantle = 'fas fa-tools',
    take = 'fas fa-hand-paper',
}

local fwName, fwObj

local function framework()
    if fwName ~= nil then return fwName, fwObj end
    fwName = detect(Config.Framework, { 'qbx_core', 'qb-core', 'es_extended' }) or false
    if fwName == 'qb-core' then fwObj = exports['qb-core']:GetCoreObject()
    elseif fwName == 'es_extended' then fwObj = exports.es_extended:getSharedObject() end
    return fwName, fwObj
end

function Bridge.job()
    local name, obj = framework()
    local job
    if name == 'qbx_core' then job = (exports.qbx_core:GetPlayerData() or {}).job
    elseif name == 'qb-core' then job = (obj.Functions.GetPlayerData() or {}).job
    elseif name == 'es_extended' then job = (obj.GetPlayerData() or {}).job end
    job = job or {}
    local grade = type(job.grade) == 'table' and job.grade.level or job.grade
    return job.name, tonumber(grade) or 0, job.onduty ~= false and job.onDuty ~= false
end

local notifyKind = { primary = 'inform', info = 'inform', success = 'success', error = 'error' }

function Bridge.notify(kind, text)
    lib.notify({ description = text, type = notifyKind[kind] or 'inform' })
end

local target

local function targetName()
    if target ~= nil then return target end
    target = detect(Config.Target, { 'ox_target', 'qb-target' }) or false
    return target
end

function Bridge.waitTarget()
    for _ = 1, 120 do
        local t = targetName()
        if t and GetResourceState(t) == 'started' then return true end
        target = nil
        Wait(500)
    end
    print(('^1[%s] no supported target resource is running^7'):format(GetCurrentResourceName()))
    return false
end

local function oxOptions(options)
    local out = {}
    for i, o in ipairs(options) do
        out[i] = { name = o.name, label = o.label, description = o.description, distance = o.distance,
                   icon = Icons[o.icon] or o.icon, canInteract = o.canInteract,
                   onSelect = function() CreateThread(o.onSelect) end }
    end
    return out
end

local function qbOptions(options)
    local out, dist = {}, 1.5
    for i, o in ipairs(options) do
        dist = math.max(dist, o.distance or 0)
        out[i] = { label = o.label, icon = Icons[o.icon] or o.icon,
                   canInteract = function() return not o.canInteract or o.canInteract() end,
                   action = function() CreateThread(o.onSelect) end }
    end
    return { options = out, distance = dist }
end

function Bridge.addZone(name, coords, radius, options)
    if targetName() == 'qb-target' then
        exports['qb-target']:AddCircleZone(name, coords, radius, { name = name, useZ = true, debugPoly = false }, qbOptions(options))
        return name
    end
    return exports.ox_target:addSphereZone({ name = name, coords = coords, radius = radius, options = oxOptions(options) })
end

function Bridge.removeZone(id)
    local t = targetName()
    if not id or not t then return end
    if t == 'qb-target' then return exports['qb-target']:RemoveZone(id) end
    exports.ox_target:removeZone(id)
end

function Bridge.addEntity(ent, options)
    if targetName() == 'qb-target' then return exports['qb-target']:AddTargetEntity(ent, qbOptions(options)) end
    exports.ox_target:addLocalEntity(ent, oxOptions(options))
end

function Bridge.removeEntity(ent)
    if targetName() == 'qb-target' then return exports['qb-target']:RemoveTargetEntity(ent) end
    exports.ox_target:removeLocalEntity(ent)
end

function Bridge.progress(label, duration, anim)
    local data = {
        duration = duration, label = label, position = 'bottom', useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = anim,
    }
    if Config.Progress == 'bar' then return lib.progressBar(data) == true end
    return lib.progressCircle(data) == true
end

function Bridge.askCode(title)
    local input = lib.inputDialog(title, {
        { type = 'input', label = locale('code_label'), password = true, required = true, min = 4, max = 4, icon = 'lock' },
    })
    local value = input and input[1] and tostring(input[1])
    if not value or value == '' then return nil end
    if not value:match('^%d%d%d%d$') then
        Bridge.notify('error', locale('code_digits'))
        return nil
    end
    return value
end

local textShown = false

function Bridge.showText(text)
    textShown = true
    lib.showTextUI(text, { position = 'left-center' })
end

function Bridge.hideText()
    if not textShown then return end
    textShown = false
    lib.hideTextUI()
end

RegisterNetEvent('ssf:legacyStash', function(id, slots, weight, label)
    TriggerServerEvent('inventory:server:OpenInventory', 'stash', id, { maxweight = weight, slots = slots, label = label })
    TriggerEvent('inventory:client:SetCurrentStash', id)
end)

RegisterNetEvent('ssf:dispatch', function(unit)
    local D = Config.Dispatch
    exports['ps-dispatch']:CustomAlert({
        message = locale('dispatch_title'),
        information = locale('dispatch_info', unit),
        code = D.code,
        icon = 'fas fa-warehouse',
        priority = 2,
        coords = GetEntityCoords(cache.ped),
        sprite = D.blip.sprite,
        color = D.blip.color,
        scale = D.blip.scale,
        length = 3,
    })
end)

RegisterNetEvent('ssf:policeBlip', function(unit, coords)
    local B = Config.Dispatch.blip
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, B.sprite)
    SetBlipColour(blip, B.color)
    SetBlipScale(blip, B.scale)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('dispatch_blip', unit))
    EndTextCommandSetBlipName(blip)
    SetTimeout(B.seconds * 1000, function() RemoveBlip(blip) end)
end)
