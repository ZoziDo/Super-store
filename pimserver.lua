local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local computer = require("computer")
local math = require("math")
local os = require("os")
local unicode = require("unicode")
local TIMEZONE_OFFSET = 3 * 3600

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

local tmpfs = component.proxy(computer.tmpAddress())
local function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

local function getRealTimeString()
    return os.date("%H:%M:%S", getRealTimestamp())
end

local function getRealDateTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

-- Базы данных
local ADMINS_PATH = "/home/admins.db"
local DB_PATH = "/home/players.db"
local STATS_PATH = "/home/global_stats.db"
local REPORTS_PATH = "/home/reports.log"
local FEEDBACKS_PATH = "/home/feedbacks.db"
local admins = {}
local players = {}
local globalStats = { totalReports = 0, totalBuys = 0, totalSells = 0 }
local lastReportCount = 0
local lastReportCheckTime = 0

-- Загрузка админов
if filesystem.exists(ADMINS_PATH) then
    local file = io.open(ADMINS_PATH, "r")
    if file then
        local raw = file:read("*a")
        file:close()
        if raw and #raw > 0 then
            local success, data = pcall(serialization.unserialize, raw)
            if success and type(data) == "table" then admins = data end
        end
    end
end
if #admins == 0 then
    admins = {"ZoziDo"}
    local file = io.open(ADMINS_PATH, "w")
    file:write(serialization.serialize(admins))
    file:close()
end

-- Загрузка игроков
if filesystem.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then players = data end
    end
end

-- Загрузка статистики
if filesystem.exists(STATS_PATH) then
    local file = io.open(STATS_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then
            globalStats.totalReports = data.totalReports or 0
            globalStats.totalBuys = data.totalBuys or 0
            globalStats.totalSells = data.totalSells or 0
        end
    end
end

-- Подсчёт репортов для индикатора
local function countReports()
    local count = 0
    if filesystem.exists(REPORTS_PATH) then
        local file = io.open(REPORTS_PATH, "r")
        if file then
            for _ in file:lines() do
                count = count + 1
            end
            file:close()
        end
    end
    return count
end
lastReportCount = countReports()
lastReportCheckTime = os.time()

local function saveDB()
    local file = io.open(DB_PATH, "w")
    file:write(serialization.serialize(players))
    file:close()
end

local function saveGlobalStats()
    local file = io.open(STATS_PATH, "w")
    file:write(serialization.serialize(globalStats))
    file:close()
end

local function isAdmin(playerName)
    if not playerName then return false end
    for _, name in ipairs(admins) do
        if name == playerName then return true end
    end
    return false
end

local function addAdmin(playerName)
    if not playerName or playerName == "" then return false end
    if isAdmin(playerName) then return false end
    table.insert(admins, playerName)
    local file = io.open(ADMINS_PATH, "w")
    if file then
        file:write(serialization.serialize(admins))
        file:close()
        return true
    end
    return false
end

local function removeAdmin(playerName)
    if not playerName or playerName == "" then return false end
    if #admins <= 1 then return false end
    for i, name in ipairs(admins) do
        if name == playerName then
            table.remove(admins, i)
            local file = io.open(ADMINS_PATH, "w")
            if file then
                file:write(serialization.serialize(admins))
                file:close()
                return true
            end
        end
    end
    return false
end

local sessions = {}
local markets = {}
local owner = nil
local marketConnected = false
local shopPaused = false
local SESSION_TIMEOUT = 31536000
local ACCESS_PASSWORD = "secret"

local function validateSession(playerName, token)
    if not playerName or not token then return false end
    local session = sessions[playerName]
    if not session or not session.token then return false end
    if session.token ~= token then return false end
    return true
end

-- Логи с буферизацией
local logQueue = {}
local function addLog(text, fg)
    local entry = {text = text, color = fg or "\27[37m"}
    table.insert(logQueue, entry)
end

-- Пакетная отправка логов
local internet = require("internet")
local WEB_URL = "https://upfront-dinginess-impulsive.ngrok-free.dev"

local function toJson(val)
    if type(val) == "string" then return '"' .. val:gsub('"', '\\"') .. '"'
    elseif type(val) == "number" or type(val) == "boolean" then return tostring(val)
    elseif type(val) == "table" then
        local parts = {}
        for k, v in pairs(val) do
            table.insert(parts, '"' .. k .. '":' .. toJson(v))
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

local function sendToWeb(endpoint, jsonData)
    pcall(function()
        internet.request(WEB_URL .. endpoint, jsonData, {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close"
        })
    end)
end

local function flushLogs()
    if #logQueue == 0 then return end
    local batch = {}
    for _, entry in ipairs(logQueue) do
        local level = "INFO"
        local text = entry.text
        if text:find("ERROR") or text:find("❌") then level = "ERROR"
        elseif text:find("WARN") or text:find("⚠") then level = "WARN"
        elseif text:find("SUCCESS") or text:find("✅") then level = "SUCCESS"
        elseif text:find("IMPORTANT") then level = "IMPORTANT" end
        local cleanText = text:gsub("%[%d+:%d+:%d+%] ", "")
        table.insert(batch, { time = getRealTimeString(), text = cleanText, level = level })
    end
    local json = toJson({ logs = batch })
    sendToWeb("/api/logs_batch", json)
    logQueue = {}
end

event.timer(2, flushLogs, math.huge)

-- Транзакции (последние 100)
local transactions = {}
local function addTransaction(type, playerName, item, qty, value_coin, value_ema)
    table.insert(transactions, {
        time = getRealDateTimeString(),
        type = type,
        player = playerName,
        item = item,
        qty = qty,
        coin = value_coin or 0,
        ema = value_ema or 0
    })
    while #transactions > 100 do table.remove(transactions, 1) end
end

-- Чтение файла с товарами с PimMarket через модем
local function getItemsFromMarket(filePath)
    local items = {}
    -- Пытаемся прочитать файл на PimServer (если он есть)
    if filesystem.exists(filePath) then
        local ok, data = pcall(dofile, filePath)
        if ok and type(data) == "table" then
            return data
        end
    end
    -- Если файла нет, пробуем запросить у терминалов
    for addr in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({
            op = "get_file",
            path = filePath,
            requestId = "items_" .. os.time()
        }))
    end
    return items
end

-- Отправка статистики
local function sendStats()
    local playerList = {}
    local totalBalance = 0
    for name, data in pairs(players) do
        local bal = (data.balance or 0) + (data.emaBalance or 0)
        totalBalance = totalBalance + bal
        table.insert(playerList, {
            name = name,
            balance = data.balance or 0,
            emaBalance = data.emaBalance or 0,
            transactions = data.transactions or 0,
            banned = data.banned or false
        })
    end
    
    local online = 0
    for _, s in pairs(sessions) do
        if type(s) == "table" and s.token then online = online + 1 end
    end
    
    local feedbacksList = {}
    if filesystem.exists(FEEDBACKS_PATH) then
        local file = io.open(FEEDBACKS_PATH, "r")
        if file then
            local data = file:read("*a")
            file:close()
            if data and #data > 0 then
                local ok, result = pcall(serialization.unserialize, data)
                if ok and type(result) == "table" then feedbacksList = result end
            end
        end
    end
    
    local reportsList = {}
    if filesystem.exists(REPORTS_PATH) then
        local file = io.open(REPORTS_PATH, "r")
        if file then
            for line in file:lines() do
                local time = line:match("%[([^%]]+)%]")
                local name = line:match("%] (%w+):")
                local text = line:match("%] %w+: (.+)")
                if time and name and text then
                    table.insert(reportsList, {time = time, name = name, text = text})
                end
            end
            file:close()
        end
    end
    
    -- Проверяем новые репорты
    local currentReportCount = #reportsList
    local hasNewReports = currentReportCount > lastReportCount
    if hasNewReports then
        lastReportCount = currentReportCount
    end
    
    -- Загружаем товары
    local buyItems = {}
    if filesystem.exists("/home/buy_items.lua") then
        local ok, data = pcall(dofile, "/home/buy_items.lua")
        if ok and type(data) == "table" then buyItems = data end
    end
    
    local sellItems = {}
    if filesystem.exists("/home/shop_items.lua") then
        local ok, data = pcall(dofile, "/home/shop_items.lua")
        if ok and type(data) == "table" and data.sellItems then
            sellItems = data.sellItems
        end
    end
    
    sendToWeb("/api/update", toJson({
        players = playerList,
        admins = admins,
        total = #playerList,
        total_balance = totalBalance,
        total_transactions = (globalStats.totalBuys or 0) + (globalStats.totalSells or 0),
        total_reports = globalStats.totalReports or 0,
        total_feedbacks = #feedbacksList,
        online = online,
        paused = shopPaused,
        feedbacks = feedbacksList,
        reports = reportsList,
        transactions = transactions,
        has_new_reports = hasNewReports,
        buy_items = buyItems,
        sell_items = sellItems
    }))
end

-- Отправка обновления терминалам
local function broadcastUpdate()
    for addr in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="update_market"}))
    end
end

local function broadcastKill()
    for addr in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="kill_market"}))
    end
end

local function deleteFeedback(index)
    local feedbacks = {}
    if filesystem.exists(FEEDBACKS_PATH) then
        local file = io.open(FEEDBACKS_PATH, "r")
        local data = file:read("*a")
        file:close()
        if data and #data > 0 then
            local ok, result = pcall(serialization.unserialize, data)
            if ok and type(result) == "table" then feedbacks = result end
        end
    end
    if index < 1 or index > #feedbacks then return false end
    table.remove(feedbacks, index)
    local file = io.open(FEEDBACKS_PATH, "w")
    file:write(serialization.serialize(feedbacks))
    file:close()
    return true
end

-- Проверка команд от веб-панели
local function checkWebCommands()
    pcall(function()
        local response = internet.request(WEB_URL .. "/api/commands")
        if response then
            local body = ""
            for chunk in response do body = body .. chunk end
            local ok, data = pcall(serialization.unserialize, body)
            if ok and data and data.commands then
                for _, cmd in ipairs(data.commands) do
                    local d = cmd.data or {}
                    local requestId = cmd.requestId
                    local function reply(success, msg)
                        sendToWeb("/api/command_result", toJson({
                            requestId = requestId,
                            success = success,
                            message = msg or ""
                        }))
                    end

                    if cmd.command == "toggle_pause" then
                        shopPaused = not shopPaused
                        for addr in pairs(markets) do
                            modem.send(addr, 0xffef, serialization.serialize({op="shop_paused", paused=shopPaused}))
                        end
                        reply(true, shopPaused and "Магазин на паузе" or "Магазин активен")
                    
                    elseif cmd.command == "update_market" then
                        broadcastUpdate()
                        reply(true, "Обновление разослано")
                    
                    elseif cmd.command == "kill_market" then
                        broadcastKill()
                        reply(true, "Терминалы завершены")
                    
                    elseif cmd.command == "set_balance" then
                        local player = players[d.name]
                        if player then
                            if d.coin then player.balance = d.coin end
                            if d.ema then player.emaBalance = d.ema end
                            saveDB()
                            reply(true, "Баланс обновлён")
                        else
                            reply(false, "Игрок не найден")
                        end
                    
                    elseif cmd.command == "toggle_ban" then
                        local player = players[d.name]
                        if player then
                            player.banned = not player.banned
                            saveDB()
                            reply(true, player.banned and "Забанен" or "Разбанен")
                        else
                            reply(false, "Игрок не найден")
                        end
                    
                    elseif cmd.command == "reset_player" then
                        local player = players[d.name]
                        if player then
                            player.balance = 0
                            player.emaBalance = 0
                            player.transactions = 0
                            saveDB()
                            reply(true, "Игрок сброшен")
                        else
                            reply(false, "Игрок не найден")
                        end
                    
                    elseif cmd.command == "add_admin" then
                        if addAdmin(d.name) then
                            reply(true, "Админ добавлен")
                        else
                            reply(false, "Уже админ или ошибка")
                        end
                    
                    elseif cmd.command == "remove_admin" then
                        if removeAdmin(d.name) then
                            reply(true, "Админ удалён")
                        else
                            reply(false, "Нельзя удалить")
                        end
                    
                    elseif cmd.command == "delete_feedback" then
                        if deleteFeedback(d.index) then
                            reply(true, "Отзыв удалён")
                        else
                            reply(false, "Неверный индекс")
                        end
                    
                    -- РАБОТА С ТОВАРАМИ
                    elseif cmd.command == "get_buy_items" then
                        local items = {}
                        if filesystem.exists("/home/buy_items.lua") then
                            local ok, data = pcall(dofile, "/home/buy_items.lua")
                            if ok and type(data) == "table" then items = data end
                        end
                        sendToWeb("/api/buy_items_data", toJson({ items = items }))
                        reply(true, "Данные отправлены")
                    
                    elseif cmd.command == "get_shop_items" then
                        local items = {}
                        if filesystem.exists("/home/shop_items.lua") then
                            local ok, data = pcall(dofile, "/home/shop_items.lua")
                            if ok and type(data) == "table" and data.sellItems then
                                items = data.sellItems
                            end
                        end
                        sendToWeb("/api/shop_items_data", toJson({ items = items }))
                        reply(true, "Данные отправлены")
                    
                    elseif cmd.command == "save_buy_items" then
                        local ok, items = pcall(serialization.unserialize, d.items)
                        if ok and type(items) == "table" then
                            local file = io.open("/home/buy_items.lua", "w")
                            if file then
                                file:write("return " .. serialization.serialize(items))
                                file:close()
                                broadcastUpdate()
                                reply(true, "buy_items.lua обновлён (" .. #items .. " товаров)")
                            else
                                reply(false, "Ошибка записи файла")
                            end
                        else
                            reply(false, "Неверный формат данных")
                        end
                    
                    elseif cmd.command == "save_shop_items" then
                        local ok, items = pcall(serialization.unserialize, d.items)
                        if ok and type(items) == "table" then
                            local out = "local items = {}\nitems.sellItems = " .. serialization.serialize(items) .. "\nitems.vanillaItems = {}\nreturn items"
                            local file = io.open("/home/shop_items.lua", "w")
                            if file then
                                file:write(out)
                                file:close()
                                broadcastUpdate()
                                reply(true, "shop_items.lua обновлён (" .. #items .. " товаров)")
                            else
                                reply(false, "Ошибка записи файла")
                            end
                        else
                            reply(false, "Неверный формат данных")
                        end
                    
                    else
                        reply(false, "Неизвестная команда")
                    end
                end
            end
        end
    end)
end

-- Таймеры
event.timer(10, sendStats, math.huge)
event.timer(3, checkWebCommands, math.huge)

-- Главный цикл
local function main()
    print("=" .. string.rep("=", 58))
    print("🚀 PIM Server запущен")
    print("📡 Web URL: " .. WEB_URL)
    print("👑 Админы: " .. table.concat(admins, ", "))
    print("📦 Товары: /home/buy_items.lua и /home/shop_items.lua")
    print("=" .. string.rep("=", 58))
    
    while true do
        local ev = {event.pull(0.5)}
        if ev[1] == "modem_message" then
            local from = ev[3]
            local raw = ev[6]
            local success, msg = pcall(serialization.unserialize, raw)
            if not success or not msg or type(msg) ~= "table" then
                goto continue
            end
            
            local last = sessions["__modem_"..from] or 0
            if os.time() - last < 0.5 then
                addLog("WARN: Спам от " .. from)
                goto continue
            end
            sessions["__modem_"..from] = os.time()

            if msg.op == "register" then
                if msg.password ~= ACCESS_PASSWORD then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Неверный пароль"}))
                else
                    marketConnected = true
                    if not owner then owner = from end
                    markets[from] = true
                    modem.send(from, 0xffef, serialization.serialize({op="welcome", owner=(from==owner), shopPaused=shopPaused}))
                    addLog("✅ Терминал зарегистрирован: " .. from)
                end
            
            elseif msg.op == "enter" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                else
                    local playerName = msg.name
                    if not playerName or playerName == "" then
                        addLog("WARN: Вход без имени")
                    else
                        local player = players[playerName]
                        if not player then
                            player = { balance = 0, emaBalance = 0, transactions = 0, banned = false, agreed = false, hasFeedback = false }
                            players[playerName] = player
                            saveDB()
                            addLog("✅ Новый игрок: " .. playerName)
                        end
                        if player.banned then
                            modem.send(from, 0xffef, serialization.serialize({op="error", message="Вы забанены"}))
                        else
                            local token = tostring(math.floor(math.random() * 900000000 + 100000000))
                            sessions[playerName] = {token = token, lastAction = os.time()}
                            modem.send(from, 0xffef, serialization.serialize({
                                op="welcome", status="ok", token=token,
                                balance=player.balance, emaBalance=player.emaBalance,
                                transactions=player.transactions, regDate=os.date(),
                                agreed = player.agreed, shopPaused = shopPaused
                            }))
                            addLog("👤 Вход: " .. playerName)
                        end
                    end
                end
            
            elseif msg.op == "sell" then
                local player = players[msg.name]
                if player and not player.banned and validateSession(msg.name, msg.token) then
                    local value = tonumber(msg.value) or 0
                    if msg.internalName == "customnpcs:npcMoney" then
                        player.emaBalance = (player.emaBalance or 0) + value
                    else
                        player.balance = (player.balance or 0) + value
                    end
                    player.transactions = (player.transactions or 0) + 1
                    sessions[msg.name].lastAction = os.time()
                    globalStats.totalSells = (globalStats.totalSells or 0) + 1
                    saveGlobalStats()
                    saveDB()
                    addTransaction("sell", msg.name, msg.item or "?", msg.qty or 0, 0, value)
                    addLog("💰 Продажа: " .. msg.name .. " " .. (msg.item or "?") .. " x" .. (msg.qty or 0))
                end
            
            elseif msg.op == "buy" then
                local player = players[msg.name]
                if player and not player.banned and validateSession(msg.name, msg.token) then
                    local coin = tonumber(msg.value_coin) or 0
                    local ema = tonumber(msg.value_ema) or 0
                    if player.balance >= coin and player.emaBalance >= ema then
                        player.balance = player.balance - coin
                        player.emaBalance = player.emaBalance - ema
                        player.transactions = (player.transactions or 0) + 1
                        sessions[msg.name].lastAction = os.time()
                        globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
                        saveGlobalStats()
                        saveDB()
                        addTransaction("buy", msg.name, msg.item or "?", msg.qty or 0, coin, ema)
                        addLog("🛒 Покупка: " .. msg.name .. " " .. (msg.item or "?") .. " x" .. (msg.qty or 0))
                    else
                        modem.send(from, 0xffef, serialization.serialize({op="error", message="Недостаточно средств"}))
                    end
                end
            
            elseif msg.op == "report" then
                if validateSession(msg.name, msg.token) then
                    globalStats.totalReports = (globalStats.totalReports or 0) + 1
                    saveGlobalStats()
                    local file = io.open(REPORTS_PATH, "a")
                    if file then
                        file:write("[" .. msg.time .. "] " .. msg.name .. ": " .. msg.text .. "\n")
                        file:close()
                        addLog("📩 Новый репорт от " .. msg.name)
                        -- Отправляем сигнал о новом репорте
                        sendToWeb("/api/new_report", toJson({
                            time = msg.time,
                            name = msg.name,
                            text = msg.text
                        }))
                    end
                end
            
            elseif msg.op == "agree" then
                if validateSession(msg.name, msg.token) then
                    local player = players[msg.name]
                    if player then
                        player.agreed = true
                        saveDB()
                        sessions[msg.name].lastAction = os.time()
                        modem.send(from, 0xffef, serialization.serialize({ op = "agree", success = true, agreed = true }))
                        addLog("✅ Соглашение принято: " .. msg.name)
                    end
                end
            
            elseif msg.op == "add_feedback" then
                if validateSession(msg.name, msg.token) then
                    local player = players[msg.name]
                    if player and not player.hasFeedback then
                        local feedbacks = {}
                        if filesystem.exists(FEEDBACKS_PATH) then
                            local file = io.open(FEEDBACKS_PATH, "r")
                            local data = file:read("*a")
                            file:close()
                            if data and #data > 0 then
                                local ok, result = pcall(serialization.unserialize, data)
                                if ok and type(result) == "table" then feedbacks = result end
                            end
                        end
                        table.insert(feedbacks, 1, {name = msg.name, text = msg.text, time = msg.time})
                        local file = io.open(FEEDBACKS_PATH, "w")
                        if file then
                            file:write(serialization.serialize(feedbacks))
                            file:close()
                            player.hasFeedback = true
                            saveDB()
                            modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=true}))
                            addLog("📝 Новый отзыв от " .. msg.name)
                        end
                    end
                end
            
            elseif msg.op == "get_feedbacks" then
                if validateSession(msg.name, msg.token) then
                    local feedbacks = {}
                    if filesystem.exists(FEEDBACKS_PATH) then
                        local file = io.open(FEEDBACKS_PATH, "r")
                        local data = file:read("*a")
                        file:close()
                        if data and #data > 0 then
                            local ok, result = pcall(serialization.unserialize, data)
                            if ok and type(result) == "table" then feedbacks = result end
                        end
                    end
                    modem.send(from, 0xffef, serialization.serialize({
                        op = "feedbacks_list", feedbacks = feedbacks,
                        hasFeedback = players[msg.name] and players[msg.name].hasFeedback
                    }))
                end
            
            -- Ответ от терминала с файлом
            elseif msg.op == "file_response" then
                if msg.path and msg.data then
                    -- Сохраняем полученный файл на PimServer
                    local file = io.open(msg.path, "w")
                    if file then
                        file:write(msg.data)
                        file:close()
                        addLog("📁 Файл получен: " .. msg.path)
                    end
                end
            end
        end
        ::continue::
    end
end

-- Запуск с защитой
while true do
    local ok, err = pcall(main)
    if not ok then
        print("❌ Crash: " .. tostring(err))
        os.sleep(5)
    end
end
