local QBCore = exports['qb-core']:GetCoreObject()

-- Simple server-side cooldown tracker (per source)
local lastGive = {}

-- Utility: attempt many admin checks (ACE, ox_core-like exports, fallback citizenid whitelist)
local function isAdmin(src)
    if src == 0 then return true end

    -- ACE permission check (wrapped)
    local ok, aceAllowed = pcall(function()
        return IsPlayerAceAllowed(src, Config.AdminPermission)
    end)
    if ok and aceAllowed then
        return true
    end

    -- Try common admin-export checks (pcall to avoid runtime errors)
    local tryExports = {
        function() if exports['ox_core'] and exports['ox_core'].IsPlayerAdmin then return exports['ox_core'].IsPlayerAdmin(src) end end,
        function() if exports['ox_core'] and exports['ox_core'].isAdmin then return exports['ox_core'].isAdmin(src) end end,
        function() if exports['ox_core'] and exports['ox_core'].IsAdmin then return exports['ox_core'].IsAdmin(src) end end,
        function() if exports['sAdmin'] and exports['sAdmin'].IsAdmin then return exports['sAdmin'].IsAdmin(src) end end,
    }
    for _, fn in ipairs(tryExports) do
        local ok2, res = pcall(fn)
        if ok2 and res then
            return true
        end
    end

    -- Fallback to citizenid whitelist (if configured)
    local Player = QBCore.Functions.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.citizenid and Config.AdminCitizenIds then
        for _, cid in ipairs(Config.AdminCitizenIds) do
            if tostring(cid) == tostring(Player.PlayerData.citizenid) then
                return true
            end
        end
    end

    return false
end

-- Ensure DB table if using DB (attempts CREATE TABLE; safe pcall)
local function ensureTableCreatedIfNeeded()
    if not Config.UseDatabase then return end
    local tableName = tostring(Config.DatabaseTable or "qb_pizzajob_deliveries")
    local createQuery = [[
        CREATE TABLE IF NOT EXISTS ]] .. tableName .. [[ (
            id INT AUTO_INCREMENT PRIMARY KEY,
            ts DATETIME NOT NULL,
            src INT NOT NULL,
            citizenid VARCHAR(64),
            identifiers TEXT,
            outcome VARCHAR(32),
            base INT,
            tip INT,
            total INT,
            x DOUBLE,
            y DOUBLE,
            z DOUBLE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]]
    if exports and exports.oxmysql then
        local ok, err = pcall(function()
            exports.oxmysql:execute(createQuery, {})
        end)
        if not ok then
            print(("^1[qb-pizzajob] Failed to create/check DB table %s: %s^0"):format(tableName, tostring(err)))
        else
            print(("^2[qb-pizzajob] Ensured DB table %s exists (or creation attempted).^0"):format(tableName))
        end
    else
        print("^3[qb-pizzajob] oxmysql not found; DB logging disabled, will fallback to file logs.^0")
    end
end

-- Inventory helper wrappers: try ox_inventory exports first, fallback to QBCore Player functions
local function givePizzaItem(src, amount)
    amount = amount or 1
    if exports and exports.ox_inventory then
        local ok, err = pcall(function()
            exports.ox_inventory:AddItem(src, Config.PizzaItem, amount)
        end)
        if ok then return true end
        print(("^1[qb-pizzajob] ox_inventory:AddItem failed: %s^0"):format(tostring(err)))
        return false
    else
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            Player.Functions.AddItem(Config.PizzaItem, amount, false)
            return true
        end
        return false
    end
end

local function removePizzaItem(src, amount)
    amount = amount or 1
    if exports and exports.ox_inventory then
        local ok, res = pcall(function()
            return exports.ox_inventory:RemoveItem(src, Config.PizzaItem, amount)
        end)
        if ok then
            if res == nil then return true end
            return res == true
        end
        print(("^1[qb-pizzajob] ox_inventory:RemoveItem failed: %s^0"):format(tostring(res)))
        return false
    else
        local Player = QBCore.Functions.GetPlayer(src)
        if Player then
            local removed = Player.Functions.RemoveItem(Config.PizzaItem, amount, false)
            return removed
        end
        return false
    end
end

-- Logging helper (DB preferred, fallback to file)
local function logDelivery(src, Player, outcome, base, tip, total, coords)
    local tableName = tostring(Config.DatabaseTable or "qb_pizzajob_deliveries")
    local citizenid = ""
    local identifiers_json = nil
    if Player and Player.PlayerData then
        citizenid = Player.PlayerData.citizenid or ""
        if Player.PlayerData.identifiers then
            local ok, enc = pcall(function() return json.encode(Player.PlayerData.identifiers) end)
            if ok then identifiers_json = enc end
        else
            local ok, enc = pcall(function() return json.encode({}) end)
            if ok then identifiers_json = enc end
        end
    end

    if Config.UseDatabase and exports and exports.oxmysql then
        local x, y, z = nil, nil, nil
        if coords then
            x = tonumber(coords.x) or nil
            y = tonumber(coords.y) or nil
            z = tonumber(coords.z) or nil
        end
        local sql = "INSERT INTO " .. tableName .. " (ts, src, citizenid, identifiers, outcome, base, tip, total, x, y, z) VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        local params = { src, citizenid, identifiers_json, outcome or "", base or 0, tip or 0, total or ((base or 0) + (tip or 0)), x, y, z }
        local ok, err = pcall(function()
            exports.oxmysql:execute(sql, params, function(affected) end)
        end)
        if ok then return end
        print(("^1[qb-pizzajob] oxmysql insert failed (falling back to file): %s^0"):format(tostring(err)))
    end

    local logFile = tostring(GetCurrentResourceName() or "resource") .. "_deliveries.log"
    local entry = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        src = src,
        citizenid = citizenid,
        identifiers = identifiers_json,
        outcome = outcome or "",
        base = base or 0,
        tip = tip or 0,
        total = total or ((base or 0) + (tip or 0)),
        coords = (coords and { x = coords.x, y = coords.y, z = coords.z }) or nil
    }
    local ok, err = pcall(function()
        local f, ferr = io.open(logFile, "a")
        if not f then
            print(("^1[qb-pizzajob] Could not open log file %s: %s^0"):format(logFile, tostring(ferr)))
            return
        end
        f:write(json.encode(entry) .. "\n")
        f:close()
    end)
    if not ok then
        print(("^1[qb-pizzajob] Failed to write delivery log to file: %s^0"):format(tostring(err)))
    end
end

-- Fetch recent logs (DB or file fallback)
local function fetchRecentLogs(limit, cb)
    limit = tonumber(limit) or tonumber(Config.LogFetchLimit) or 50
    local tableName = tostring(Config.DatabaseTable or "qb_pizzajob_deliveries")

    if Config.UseDatabase and exports and exports.oxmysql then
        local q = "SELECT ts, src, citizenid, outcome, base, tip, total, x, y, z FROM " .. tableName .. " ORDER BY ts DESC LIMIT ?"
        local ok, err = pcall(function()
            exports.oxmysql:execute(q, { limit }, function(rows)
                if not rows then
                    cb(false, "db_no_rows")
                else
                    cb(true, rows)
                end
            end)
        end)
        if not ok then
            print(("^1[qb-pizzajob] oxmysql query failed fetching logs: %s^0"):format(tostring(err)))
            cb(false, "db_query_failed")
        end
        return
    end

    local logFile = tostring(GetCurrentResourceName() or "resource") .. "_deliveries.log"
    local ok, out = pcall(function()
        local f = io.open(logFile, "r")
        if not f then return {} end
        local contents = f:read("*a")
        f:close()
        if not contents or contents == "" then return {} end
        local all = {}
        for line in contents:gmatch("[^\n]+") do table.insert(all, line) end
        local rows = {}
        local start = #all - limit + 1
        if start < 1 then start = 1 end
        for i = #all, start, -1 do
            local s = all[i]
            local ok2, decoded = pcall(function() return json.decode(s) end)
            if ok2 and decoded then table.insert(rows, decoded) end
        end
        return rows
    end)
    if not ok then cb(false, "file_read_failed"); return end
    cb(true, out or {})
end

-- Init: ensure DB table (if possible)
CreateThread(function()
    Wait(1000)
    ensureTableCreatedIfNeeded()
end)

-- Give pizza (server enforces cooldown) uses givePizzaItem wrapper
RegisterNetEvent('qb-pizzajob:server:givePizza', function(bypassCooldown)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end
    bypassCooldown = bypassCooldown == true

    local now = os.time()
    local last = lastGive[src] or 0
    local diff = now - last
    local cd = tonumber(Config.StartCooldown) or 30

    if not bypassCooldown and diff < cd then
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = 'Please wait ' .. tostring(cd - diff) .. 's before requesting another pizza.' })
        return
    end

    local gave = givePizzaItem(src, 1)
    if gave then
        TriggerClientEvent('inventory:client:ItemBox', src, { item = Config.PizzaItem, type = "add" })
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "success", text = 'You received a pizza box. Deliver it to the customer!' })
        lastGive[src] = now
        TriggerClientEvent('qb-pizzajob:client:gotPizza', src)
    else
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = 'Failed to give pizza (inventory error).' })
    end
end)

-- Delivery attempt event
RegisterNetEvent('qb-pizzajob:server:deliverPizza', function(coords)
    local src = source
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then return end

    if removePizzaItem(src, 1) then
        local rand = math.random(1, 100)
        if Config.RefuseChance and rand <= Config.RefuseChance then
            local speech = nil
            if Config.RefusePhrases and #Config.RefusePhrases > 0 then
                speech = Config.RefusePhrases[math.random(#Config.RefusePhrases)]
            end

            logDelivery(src, Player, "refuse", 0, 0, 0, coords)

            TriggerClientEvent('qb-pizzajob:client:deliveryResult', src, { result = 'refuse', amount = 0, tip = 0, speech = speech })
            TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = 'Customer refused to pay.' })
            return
        end

        local base = tonumber(Config.Payment) or 100
        local tip = 0
        local tipRoll = math.random(1, 100)
        if Config.TipChance and tipRoll <= Config.TipChance then
            tip = math.random(tonumber(Config.TipMin) or 10, tonumber(Config.TipMax) or 50)
        end

        local total = base + tip
        Player.Functions.AddMoney('cash', total, "pizza-delivery")

        local speech = nil
        if tip > 0 and Config.TipPhrases and #Config.TipPhrases > 0 then
            speech = Config.TipPhrases[math.random(#Config.TipPhrases)]
        elseif Config.SuccessPhrases and #Config.SuccessPhrases > 0 then
            speech = Config.SuccessPhrases[math.random(#Config.SuccessPhrases)]
        end

        logDelivery(src, Player, "success", base, tip, total, coords)

        TriggerClientEvent('qb-pizzajob:client:deliveryResult', src, { result = 'success', amount = base, tip = tip, speech = speech })
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "success", text = 'Pizza delivered! You earned $'..tostring(total) })
    else
        logDelivery(src, Player, "no_item", 0, 0, 0, coords)
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = 'You have no pizza to deliver!' })
    end
end)

-- Server handler: client requests recent logs (server enforces authorization) and returns via client event
RegisterNetEvent('qb-pizzajob:server:requestLogs', function(limit)
    local src = source
    if not isAdmin(src) then
        TriggerClientEvent('qb-pizzajob:client:displayLogs', src, { success = false, error = "not_authorized" })
        return
    end

    fetchRecentLogs(limit, function(ok, rowsOrErr)
        if not ok then
            TriggerClientEvent('qb-pizzajob:client:displayLogs', src, { success = false, error = rowsOrErr or "fetch_failed" })
            return
        end
        TriggerClientEvent('qb-pizzajob:client:displayLogs', src, { success = true, rows = rowsOrErr })
    end)
end)

-- Admin action endpoint (teleport / other admin ops)
RegisterNetEvent('qb-pizzajob:server:adminAction', function(actionData)
    local src = source
    if not isAdmin(src) then
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = "You are not authorized to perform admin actions." })
        return
    end

    if not actionData or not actionData.action then
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = "Invalid admin action." })
        return
    end

    if actionData.action == "teleport" and actionData.coords then
        TriggerClientEvent('qb-pizzajob:client:teleportTo', src, actionData.coords)
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "success", text = "Teleported to delivery location." })
    else
        TriggerClientEvent('qb-pizzajob:client:notify', src, { type = "error", text = "Unknown admin action." })
    end
end)