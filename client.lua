-- client.lua
local QBCore = exports['qb-core']:GetCoreObject()
local onJob = false
local currentBlip = nil
local deliveryCoords = nil
local deliveryPed = nil
local nuiOpen = false

-- Simple notify wrapper: prefer ox_lib's lib.notify when available, otherwise fallback to QBCore.Functions.Notify
local function notifyClient(params)
    local ok, _ = pcall(function()
        if lib and lib.notify then
            lib.notify({ type = params.type or "success", description = params.text or "" })
            return true
        end
    end)
    if not ok then
        QBCore.Functions.Notify(params.text or "", params.type or "primary")
    end
end

RegisterNetEvent('qb-pizzajob:client:notify', function(data)
    if data and data.text then
        notifyClient({ type = data.type or "success", text = data.text })
    end
end)

-- Create Start NPC
Citizen.CreateThread(function()
    RequestModel(Config.PizzaPed)
    while not HasModelLoaded(Config.PizzaPed) do Wait(10) end
    local npc = CreatePed(4, Config.PizzaPed, Config.PizzaStart.x, Config.PizzaStart.y, Config.PizzaStart.z-1, 250.0, false, true)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
end)

-- Marker and interaction at start location:
Citizen.CreateThread(function()
    while true do
        Wait(1)
        local pos = GetEntityCoords(PlayerPedId())
        local dist = #(pos - Config.PizzaStart)
        if dist < 2.5 then
            DrawMarker(2, Config.PizzaStart.x, Config.PizzaStart.y, Config.PizzaStart.z+0.2, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.3, 255, 140, 0, 200, false, true, 2, false, nil, nil, false)
            if not onJob then
                QBCore.Functions.DrawText3D(Config.PizzaStart.x, Config.PizzaStart.y, Config.PizzaStart.z+1.0, '[E] Start Pizza Job')
            else
                if not deliveryCoords then
                    QBCore.Functions.DrawText3D(Config.PizzaStart.x, Config.PizzaStart.y, Config.PizzaStart.z+1.0, '[E] Get Pizza')
                else
                    QBCore.Functions.DrawText3D(Config.PizzaStart.x, Config.PizzaStart.y, Config.PizzaStart.z+1.0, '[E] Stop Pizza Job')
                end
            end

            if IsControlJustReleased(0, 38) then
                if not onJob then
                    StartPizzaJob()
                else
                    if not deliveryCoords then
                        TriggerServerEvent('qb-pizzajob:server:givePizza', false)
                    else
                        EndPizzaJob()
                    end
                end
            end
        else
            Wait(500)
        end
    end
end)

function StartPizzaJob()
    onJob = true
    notifyClient({ type = "success", text = 'Pizza job started! Vehicle spawned. Getting pizza...' })
    QBCore.Functions.SpawnVehicle(Config.PizzaVehicle, function(veh)
        TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1)
        SetVehicleNumberPlateText(veh, "PIZZA"..tostring(math.random(100,999)))
        SetEntityAsMissionEntity(veh, true, true)
    end, Config.PizzaStart, true)
    TriggerServerEvent('qb-pizzajob:server:givePizza', true)
end

function SetNewDelivery()
    if deliveryPed and DoesEntityExist(deliveryPed) then
        SetEntityAsMissionEntity(deliveryPed, true, true)
        DeleteEntity(deliveryPed)
        deliveryPed = nil
    end
    if currentBlip then
        RemoveBlip(currentBlip)
        currentBlip = nil
    end

    deliveryCoords = Config.DeliveryLocations[math.random(#Config.DeliveryLocations)]

    currentBlip = AddBlipForCoord(deliveryCoords)
    SetBlipSprite(currentBlip, 1)
    SetBlipColour(currentBlip, 2)
    SetBlipScale(currentBlip, 0.8)
    SetBlipRoute(currentBlip, true)

    RequestModel(Config.DeliveryPed)
    while not HasModelLoaded(Config.DeliveryPed) do Wait(10) end
    deliveryPed = CreatePed(4, Config.DeliveryPed, deliveryCoords.x, deliveryCoords.y, deliveryCoords.z-1, math.random(0,360), false, true)
    FreezeEntityPosition(deliveryPed, false)
    SetEntityInvincible(deliveryPed, true)
    SetBlockingOfNonTemporaryEvents(deliveryPed, true)

    notifyClient({ type = "primary", text = 'Deliver the pizza to the marked customer!' })
end

-- Server confirms pizza was given successfully; client then spawns delivery
RegisterNetEvent('qb-pizzajob:client:gotPizza', function()
    if not onJob then
        notifyClient({ type = "success", text = 'You received a pizza box.' })
        return
    end
    if not deliveryCoords then
        SetNewDelivery()
    end
end)

-- Delivery result handler (animations & popup)
RegisterNetEvent('qb-pizzajob:client:deliveryResult', function(data)
    local ped = deliveryPed
    local pedCoords = deliveryCoords

    local playerPed = PlayerPedId()
    local animDict = "mp_common"
    local anim = "givetake1_a"
    RequestAnimDict(animDict)
    local timeout = GetGameTimer() + 2000
    while not HasAnimDictLoaded(animDict) and GetGameTimer() < timeout do Wait(10) end
    if HasAnimDictLoaded(animDict) then
        TaskPlayAnim(playerPed, animDict, anim, 8.0, -8.0, 1800, 48, 0, false, false, false)
        Wait(1100)
        ClearPedTasks(playerPed)
    end

    if ped and DoesEntityExist(ped) and data.speech then
        pcall(function() PlayPedAmbientSpeechNative(ped, data.speech, "SPEECH_PARAMS_FORCE") end)
    end

    if ped and DoesEntityExist(ped) then
        ClearPedTasksImmediately(ped)
        if data.result == 'refuse' then
            TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_IMPATIENT", 0, true)
        else
            if data.tip and data.tip > 0 then
                TaskStartScenarioInPlace(ped, "WORLD_HUMAN_CHEERING", 0, true)
            else
                TaskStartScenarioInPlace(ped, "WORLD_HUMAN_STAND_MOBILE", 0, true)
            end
        end
    end

    local popupText = ""
    if data.result == 'success' then
        local total = (data.amount or 0) + (data.tip or 0)
        if data.tip and data.tip > 0 then
            popupText = '+$' .. tostring(total) .. ' (+' .. tostring(data.tip) .. ' tip)'
        else
            popupText = '+$' .. tostring(total)
        end
        notifyClient({ type = "success", text = 'Pizza delivered! You earned $'..tostring(total) })
    elseif data.result == 'refuse' then
        popupText = 'Customer refused to pay'
        notifyClient({ type = "error", text = 'Customer refused to pay...' })
    else
        popupText = 'Delivery'
    end

    local drawTime = 3500
    local start = GetGameTimer()
    while GetGameTimer() - start < drawTime do
        if ped and DoesEntityExist(ped) then
            local ppos = GetEntityCoords(ped)
            QBCore.Functions.DrawText3D(ppos.x, ppos.y, ppos.z + 1.2, popupText)
        elseif pedCoords then
            QBCore.Functions.DrawText3D(pedCoords.x, pedCoords.y, pedCoords.z + 1.2, popupText)
        end
        Wait(0)
    end

    if ped and DoesEntityExist(ped) then ClearPedTasksImmediately(ped) end

    if deliveryPed and DoesEntityExist(deliveryPed) then
        SetEntityAsMissionEntity(deliveryPed, true, true)
        DeleteEntity(deliveryPed)
        deliveryPed = nil
    end
    if currentBlip then RemoveBlip(currentBlip); currentBlip = nil end
    deliveryCoords = nil
end)

Citizen.CreateThread(function()
    while true do
        Wait(1500)
        if onJob and deliveryCoords and deliveryPed and DoesEntityExist(deliveryPed) then
            local pedPos = GetEntityCoords(deliveryPed)
            local pos = GetEntityCoords(PlayerPedId())
            if #(pos - pedPos) < 3.0 then
                QBCore.Functions.DrawText3D(pedPos.x, pedPos.y, pedPos.z+1.0, '[E] Deliver Pizza')
                if IsControlJustReleased(0, 38) then
                    local playerPos = GetEntityCoords(PlayerPedId())
                    local coordsTable = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
                    TriggerServerEvent('qb-pizzajob:server:deliverPizza', coordsTable)
                end
            end
        else
            Wait(2000)
        end
    end
end)

function EndPizzaJob()
    onJob = false
    if currentBlip then RemoveBlip(currentBlip); currentBlip = nil end
    if deliveryPed and DoesEntityExist(deliveryPed) then
        SetEntityAsMissionEntity(deliveryPed, true, true)
        DeleteEntity(deliveryPed)
        deliveryPed = nil
    end
    deliveryCoords = nil
    notifyClient({ type = "error", text = 'Pizza job ended!' })
end

-- Client-side command: request logs from server
RegisterCommand("pizzalogs", function(source, args, raw)
    local limit = tonumber(args[1]) or tonumber(Config.LogFetchLimit) or 50
    TriggerServerEvent('qb-pizzajob:server:requestLogs', limit)
end, false)

-- Teleport helper called from server admin action (server ensures permission)
RegisterNetEvent('qb-pizzajob:client:teleportTo', function(coords)
    if not coords then return end
    local ped = PlayerPedId()
    local x = tonumber(coords.x) or 0
    local y = tonumber(coords.y) or 0
    local z = tonumber(coords.z) or 0
    local foundZ = false
    local newZ = z
    for i = 0, 50 do
        local testZ = z + (i * 0.5)
        local success, groundZ = GetGroundZFor_3dCoord(x, y, testZ, 0)
        if success then
            newZ = groundZ + 0.5
            foundZ = true
            break
        end
    end
    if not foundZ then newZ = z end
    SetEntityCoordsNoOffset(ped, x, y, newZ, false, false, false)
end)

-- Handle server returned logs: open ox_lib context menu with actionable params or fallback
RegisterNetEvent('qb-pizzajob:client:displayLogs', function(result)
    if not result then notifyClient({ type = "error", text = "Failed to fetch logs (no response)." }); return end
    if not result.success then
        if result.error == "not_authorized" then
            notifyClient({ type = "error", text = "You are not authorized to view pizza logs." })
        else
            notifyClient({ type = "error", text = "Failed to fetch pizza logs: " .. tostring(result.error) })
        end
        return
    end

    local rows = result.rows or {}
    if #rows == 0 then notifyClient({ type = "info", text = "No pizza log entries found." }); return end

    local menu = {}
    table.insert(menu, { id = 'header', title = "Pizza Delivery Logs", description = ("Showing %d entries"):format(#rows) })

    for i = 1, #rows do
        local r = rows[i]
        local ts = r.ts or r.timestamp or ""
        local src = r.src or r.player or ""
        local citizenid = r.citizenid or ""
        local outcome = r.outcome or ""
        local base = r.base or 0
        local tip = r.tip or 0
        local total = r.total or ((base or 0) + (tip or 0))
        local coords = ""
        local coordObj = nil
        if r.x and r.y and r.z then
            coords = ("%.2f, %.2f, %.2f"):format(tonumber(r.x), tonumber(r.y), tonumber(r.z))
            coordObj = { x = tonumber(r.x), y = tonumber(r.y), z = tonumber(r.z) }
        elseif r.coords and r.coords.x and r.coords.y and r.coords.z then
            coords = ("%.2f, %.2f, %.2f"):format(tonumber(r.coords.x), tonumber(r.coords.y), tonumber(r.coords.z))
            coordObj = { x = tonumber(r.coords.x), y = tonumber(r.coords.y), z = tonumber(r.coords.z) }
        end

        local header = ("%s — %s"):format(ts, outcome)
        local txt = ("src:%s  cid:%s  total:$%s\nloc:%s"):format(tostring(src), tostring(citizenid), tostring(total), coords)

        table.insert(menu, {
            id = i,
            title = header,
            description = txt,
            event = 'qb-pizzajob:client:menuAction',
            args = { entry = r, coord = coordObj }
        })
    end

    table.insert(menu, { id = 'close', title = "Close", description = "" })

    local opened = false
    local ok = pcall(function()
        if lib and lib.showContext then
            lib.showContext(menu)
            opened = true
        end
    end)
    if not ok or not opened then
        TriggerEvent('chat:addMessage', { args = { "[PizzaLogs]", ("Showing %d most recent entries:"):format(#rows) } })
        for i = 1, #rows do
            local r = rows[i]
            local ts = r.ts or r.timestamp or ""
            local src = r.src or r.player or ""
            local citizenid = r.citizenid or ""
            local outcome = r.outcome or ""
            local base = r.base or 0
            local tip = r.tip or 0
            local total = r.total or ((base or 0) + (tip or 0))
            local coords = ""
            if r.x and r.y and r.z then
                coords = ("(%.2f, %.2f, %.2f)"):format(tonumber(r.x), tonumber(r.y), tonumber(r.z))
            elseif r.coords and r.coords.x and r.coords.y and r.coords.z then
                coords = ("(%.2f, %.2f, %.2f)"):format(tonumber(r.coords.x), tonumber(r.coords.y), tonumber(r.coords.z))
            end
            local msg = ("[%s] src:%s cid:%s outcome:%s total:%s loc:%s"):format(ts, tostring(src), tostring(citizenid), tostring(outcome), tostring(total), tostring(coords))
            TriggerEvent('chat:addMessage', { args = { "[PizzaLogs]", msg } })
        end
    end
end)

-- Menu action: open submenu of actions for a selected log entry
RegisterNetEvent('qb-pizzajob:client:menuAction', function(data)
    if not data or not data.entry then return end
    local entry = data.entry
    local coord = data.coord

    local actions = {}
    table.insert(actions, { id = 'copy', title = "Copy CitizenID", description = tostring(entry.citizenid or ""), event = 'qb-pizzajob:client:menuActionSelect', args = { action = 'copy', citizenid = entry.citizenid } })
    table.insert(actions, { id = 'details', title = "View Details", description = "Open details window", event = 'qb-pizzajob:client:menuActionSelect', args = { action = 'details', data = entry } })
    if coord then
        table.insert(actions, { id = 'teleport', title = "Teleport To Location", description = "Admin teleport to delivery", event = 'qb-pizzajob:client:menuActionSelect', args = { action = 'teleport', coords = coord } })
    end
    table.insert(actions, { id = 'cancel', title = "Cancel", description = "" })

    local ok, _ = pcall(function()
        if lib and lib.showContext then
            lib.showContext(actions)
            return
        end
    end)
    if not ok then
        notifyClient({ type = "error", text = "Context menu unavailable." })
    end
end)

-- Processes the selected submenu action
RegisterNetEvent('qb-pizzajob:client:menuActionSelect', function(params)
    if not params or not params.action then return end
    local action = params.action
    if action == 'copy' then
        local cid = tostring(params.citizenid or "")
        SendNUIMessage({ type = "copy", text = cid })
        notifyClient({ type = "success", text = "CitizenID copied to clipboard." })
    elseif action == 'details' then
        SendNUIMessage({ type = "openDetails", data = params.data or {} })
        SetNuiFocus(true, true)
        nuiOpen = true
    elseif action == 'teleport' then
        TriggerServerEvent('qb-pizzajob:server:adminAction', { action = "teleport", coords = params.coords })
    end
end)

-- NUI callbacks
RegisterNUICallback('close', function(data, cb)
    SetNuiFocus(false, false)
    nuiOpen = false
    cb('ok')
end)

RegisterNUICallback('copied', function(data, cb)
    cb('ok')
end)
