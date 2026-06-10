local enabled = Config.EnabledByDefault
local lastEntity = 0
local lastPrintedKey = nil
local loggedUnknown = {}
local currentHit = nil
local statusText = nil

local function rotToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function raycastFromCamera(distance)
    local camCoord = GetGameplayCamCoord()
    local camRot = GetGameplayCamRot(2)
    local direction = rotToDirection(camRot)
    local destination = camCoord + (direction * distance)

    local rayHandle = StartShapeTestRay(
        camCoord.x, camCoord.y, camCoord.z,
        destination.x, destination.y, destination.z,
        -1,
        PlayerPedId(),
        0
    )

    local _, hit, endCoords, surfaceNormal, entityHit = GetShapeTestResult(rayHandle)
    return hit == 1, endCoords, surfaceNormal, entityHit, camCoord
end

local function drawText2D(x, y, text, scale)
    SetTextFont(4)
    SetTextScale(scale or 0.34, scale or 0.34)
    SetTextColour(255, 255, 255, 230)
    SetTextOutline()
    SetTextDropShadow()
    SetTextJustification(0)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawText3D(coords, text)
    local onScreen, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not onScreen then return end

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextColour(255, 255, 255, 235)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function formatVec3(coords)
    return ('vector3(%.3f, %.3f, %.3f)'):format(coords.x, coords.y, coords.z)
end

local function toUnsigned32(num)
    num = tonumber(num) or 0
    if num < 0 then
        return num + 4294967296
    end
    return num
end

local function toSigned32(num)
    num = toUnsigned32(num)
    if num >= 2147483648 then
        return num - 4294967296
    end
    return num
end

local function hashHex(num)
    return ('0x%08X'):format(toUnsigned32(num))
end

local function hashLine(num)
    return ('dec: %s | hex: %s | signed: %s'):format(tostring(num), hashHex(num), tostring(toSigned32(num)))
end

local function getArchetypeName(entity)
    -- FiveM has GetEntityArchetypeName in newer builds. This is the best chance
    -- of getting real custom prop/map model names without a manual hash list.
    if type(GetEntityArchetypeName) == 'function' then
        local ok, result = pcall(GetEntityArchetypeName, entity)
        if ok and result and result ~= '' and result ~= 'NULL' then
            return result
        end
    end

    return nil
end

local function resolveName(entity, model)
    local archetype = getArchetypeName(entity)
    if archetype then return archetype, 'archetype' end

    local lookup = PropNames and PropNames[model] or nil
    if lookup then return lookup, 'lookup' end

    return nil, 'unknown'
end

local function getType0NameOnlyInfo(entity, hitCoords)
    -- Type 0 can be a pseudo/world/collision hit. Do not run normal entity
    -- natives like coords, heading, model, etc. Some of those can hard-crash.
    local name = nil

    if Config.Type0NameOnly and entity and entity ~= 0 and DoesEntityExist(entity) then
        name = getArchetypeName(entity)
    end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local dist = hitCoords and #(playerCoords - hitCoords) or 0.0

    return {
        entity = entity or 0,
        model = nil,
        name = name,
        nameSource = name and 'archetype-type0-name-only' or 'type0-world-hit',
        coords = hitCoords,
        hitCoords = hitCoords,
        heading = nil,
        distance = dist,
        type = 0,
        type0NameOnly = true,
    }
end

local function getEntityInfo(entity, hitCoords)
    local model = GetEntityModel(entity)
    local name, source = resolveName(entity, model)
    local coords = GetEntityCoords(entity)
    local heading = GetEntityHeading(entity)
    local dist = #(GetEntityCoords(PlayerPedId()) - coords)
    local entityType = GetEntityType(entity)

    return {
        entity = entity,
        model = model,
        name = name,
        nameSource = source,
        coords = coords,
        hitCoords = hitCoords,
        heading = heading,
        distance = dist,
        type = entityType,
    }
end


local function addNearbyEntity(results, origin, entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    local entityType = GetEntityType(entity)
    if entityType == 0 then return end

    local coords = GetEntityCoords(entity)
    local dist = #(origin - coords)
    if dist > (Config.NearbyRadius or 6.0) then return end

    local model = GetEntityModel(entity)
    local name, source = resolveName(entity, model)

    results[#results + 1] = {
        entity = entity,
        model = model,
        name = name,
        nameSource = source,
        coords = coords,
        heading = GetEntityHeading(entity),
        distance = dist,
        type = entityType,
    }
end

local function collectFromEnumerator(results, origin, firstFn, nextFn, endFn)
    local handle, entity = firstFn()
    if not handle or handle == -1 then return end

    local success = true
    repeat
        addNearbyEntity(results, origin, entity)
        success, entity = nextFn(handle)
    until not success

    endFn(handle)
end

local function collectNearbyObjects(origin, radius, maxObjects)
    local results = {}
    if not Config.PrintNearbyObjects or not origin then return results end

    collectFromEnumerator(results, origin, FindFirstObject, FindNextObject, EndFindObject)
    collectFromEnumerator(results, origin, FindFirstVehicle, FindNextVehicle, EndFindVehicle)
    collectFromEnumerator(results, origin, FindFirstPed, FindNextPed, EndFindPed)

    table.sort(results, function(a, b)
        return a.distance < b.distance
    end)

    local limited = {}
    for i = 1, math.min(#results, maxObjects or #results) do
        limited[i] = results[i]
    end

    return limited
end

local function printInfo(info, reason)
    local displayName = info.name or 'UNKNOWN_NAME'
    print(('^3[dev-propinspector]^7 %s'):format(reason or 'Prop'))
    print(('  Name: %s'):format(displayName))
    print(('  Name source: %s'):format(info.nameSource or 'unknown'))
    print(('  Entity: %s'):format(info.entity or 0))
    print(('  Entity type: %s  (0=name-only/world hit, 1=ped, 2=vehicle/train/trailer, 3=object/prop)'):format(info.type or 'unknown'))

    if info.model then
        print(('  Hash: %s'):format(hashLine(info.model)))
        print(('  XML search: %s  (search the 0x value in ModelHash fields)'):format(hashHex(info.model):lower()))
    else
        print('  Hash: unavailable in type 0 name-only mode')
    end

    if info.coords then
        print(('  Coords: %s'):format(formatVec3(info.coords)))
    end

    if info.heading then
        print(('  Heading: %.3f'):format(info.heading))
    end

    if info.distance then
        print(('  Distance: %.2fm'):format(info.distance))
    end

    if info.type0NameOnly then
        print('  Type 0 mode: name-only. Normal entity inspection was skipped to avoid native crashes.')
    elseif not info.name and info.model then
        print(('  Add to prop_names.lua if known: PropNames[%s] = "your_prop_name_here"'):format(hashHex(info.model)))
    end

    if Config.PrintNearbyObjects then
        local nearby = collectNearbyObjects(info.hitCoords or info.coords, Config.NearbyRadius or 6.0, Config.MaxNearbyObjects or 12)
        if #nearby > 0 then
            print(('  Nearby real entities within %.1fm of hit point:'):format(Config.NearbyRadius or 6.0))
            for i, obj in ipairs(nearby) do
                print(('    %02d) %s | %s | type:%s | source:%s | dist:%.2fm | coords:%s'):format(
                    i,
                    obj.name or 'UNKNOWN_NAME',
                    hashLine(obj.model),
                    obj.type or 'unknown',
                    obj.nameSource or 'unknown',
                    obj.distance,
                    formatVec3(obj.coords)
                ))
            end
        else
            print(('  Nearby entity scan: none found within %.1fm. This was probably pure world/collision geometry.'):format(Config.NearbyRadius or 6.0))
        end
    end
end

RegisterCommand(Config.ToggleCommand, function()
    enabled = not enabled
    currentHit = nil
    lastEntity = 0
    lastPrintedKey = nil
    print(('[dev-propinspector] %s'):format(enabled and 'Enabled' or 'Disabled'))
end, false)

RegisterKeyMapping(Config.ToggleCommand, 'Toggle Dev Prop Inspector', 'keyboard', Config.ToggleKey)

CreateThread(function()
    while true do
        local wait = 500
        currentHit = nil
        statusText = nil

        if enabled then
            local ped = PlayerPedId()
            local selectedWeapon = GetSelectedPedWeapon(ped)
            local hasRequiredWeapon = selectedWeapon == Config.RequiredWeapon
            local isAiming = IsPlayerFreeAiming(PlayerId()) or IsAimCamActive() or IsControlPressed(0, 25)

            if hasRequiredWeapon then
                if (not Config.RequireAiming or isAiming) then
                    wait = Config.ScanIntervalMs

                    local hit, hitCoords, _, entity, camCoord = raycastFromCamera(Config.MaxDistance)
                    if hit and entity and entity ~= 0 and DoesEntityExist(entity) then
                        local entityType = GetEntityType(entity)

                        if Config.DrawDebugLine and camCoord and hitCoords then
                            DrawLine(camCoord.x, camCoord.y, camCoord.z, hitCoords.x, hitCoords.y, hitCoords.z, 255, 215, 0, 180)
                        end

                        if entityType == 0 and Config.Type0NameOnly then
                            local info = getType0NameOnlyInfo(entity, hitCoords)
                            currentHit = info

                            if Config.PrintOnChange and entity ~= lastEntity then
                                lastEntity = entity
                                local key = 'type0:' .. tostring(entity) .. ':' .. tostring(info.name or 'unknown')
                                if key ~= lastPrintedKey then
                                    lastPrintedKey = key
                                    printInfo(info, 'Type 0 name-only hit')
                                end
                            end
                        elseif Config.AllowedEntityTypes and Config.AllowedEntityTypes[entityType] then
                            local info = getEntityInfo(entity, hitCoords)
                            currentHit = info

                            if Config.PrintOnChange and entity ~= lastEntity then
                                lastEntity = entity
                                local key = tostring(info.model) .. ':' .. tostring(entity)
                                if key ~= lastPrintedKey then
                                    lastPrintedKey = key
                                    printInfo(info, 'New entity aimed at')
                                end
                            end

                            if Config.LogUnknownProps and not info.name and info.model and not loggedUnknown[info.model] then
                                loggedUnknown[info.model] = true
                                print(('^1[dev-propinspector]^7 Unknown entity hash: %s | type: %s | coords: %s'):format(hashLine(info.model), info.type, formatVec3(info.coords)))
                            end
                        else
                            lastEntity = 0
                            statusText = ('Hit entity type %s - not enabled in Config.AllowedEntityTypes'):format(entityType)
                        end
                    elseif hit and hitCoords then
                        lastEntity = 0
                        statusText = ('World/collision hit at %.3f, %.3f, %.3f - press E if a nearby real entity is listed'):format(hitCoords.x, hitCoords.y, hitCoords.z)
                    else
                        lastEntity = 0
                        statusText = 'No entity hit'
                    end
                else
                    statusText = 'Hold right-click / aim with pistol'
                end
            else
                statusText = 'Equip WEAPON_PISTOL'
            end
        end

        Wait(wait)
    end
end)

CreateThread(function()
    while true do
        if enabled and currentHit then
            local info = currentHit
            local displayName = info.name or '~r~UNKNOWN_NAME~s~'

            if Config.DrawOnScreen then
                local sx = Config.ScreenTextX or 0.055
                local sy = Config.ScreenTextY or 0.72

                drawText2D(sx, sy, '~y~PROP INSPECTOR~s~', 0.38)
                drawText2D(sx, sy + 0.030, ('Name: %s'):format(displayName), 0.32)
                drawText2D(sx, sy + 0.055, ('Source: %s | Type: %s'):format(info.nameSource or 'unknown', info.type), 0.32)
                drawText2D(sx, sy + 0.080, ('Hash: %s'):format(info.model and hashHex(info.model) or 'type 0 / unavailable'), 0.32)
                if info.coords then
                    drawText2D(sx, sy + 0.105, ('Coords: %.3f, %.3f, %.3f'):format(info.coords.x, info.coords.y, info.coords.z), 0.32)
                end
                drawText2D(sx, sy + 0.130, ('Heading: %s | Dist: %.2fm'):format(info.heading and ('%.2f'):format(info.heading) or 'n/a', info.distance or 0.0), 0.32)
                drawText2D(sx, sy + 0.160, ('Press ~y~E~s~ to print current hit to F8 | ~y~%s~s~ toggle'):format(Config.ToggleKey), 0.30)
            end

            if Config.DrawOnEntity and info.coords then
                local drawCoords = info.coords + vector3(0.0, 0.0, 0.55)
                drawText3D(drawCoords, ('~y~%s~s~\n%s | type %s'):format(displayName, info.model and hashHex(info.model) or 'name-only', info.type))
            end

            if IsControlJustPressed(0, Config.PrintControl) then
                printInfo(info, 'Manual print')
            end

            Wait(0)
        elseif enabled and Config.ShowNoHitStatus and statusText then
            drawText2D(Config.ScreenTextX or 0.055, 0.88, ('~y~PROP INSPECTOR~s~: %s'):format(statusText), 0.30)
            Wait(0)
        else
            Wait(250)
        end
    end
end)
