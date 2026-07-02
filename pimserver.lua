local component = require("component")
local event = require("event")
local serialization = require("serialization")
local filesystem = require("filesystem")
local gpu = component.gpu
local math = require("math")
local os = require("os")
local unicode = require("unicode")
local computer = require("computer")
local internet = require("internet")
local modem = component.modem

-- ============================================
-- НАСТРОЙКИ
-- ============================================
local TELEGRAM_TOKEN = "8780133006:AAF2Zg7Dv_mr-E1-bgVuGDVsKYvyuwizuaE"
local TELEGRAM_CHAT_ID = "492178371"
local ACCESS_PASSWORD = "secret"
local TIMEZONE_OFFSET = 3 * 3600
local ADMINS_PATH = "/home/admins.db"
local DB_PATH = "/home/players.db"
local STATS_PATH = "/home/global_stats.db"

-- ============================================
-- ОТКРЫВАЕМ МОДЕМ
-- ============================================
modem.open(0xffef)
modem.open(0xfffe)

print("")
print("═══════════════════════════════════════════")
print("🚀 PIM MARKET СЕРВЕР (УПРОЩЕННЫЙ)")
print("═══════════════════════════════════════════")
print("")
print("📡 Адрес модема: " .. modem.address)
print("")

-- ============================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================

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

local function saveData(path, data)
    local file = io.open(path, "w")
    if file then
        file:write(serialization.serialize(data))
        file:close()
        return true
    end
    return false
end

local function loadData(path, default)
    if not filesystem.exists(path) then return default or {} end
    local file = io.open(path, "r")
    if not file then return default or {} end
    local raw = file:read("*a")
    file:close()
    if not raw or #raw == 0 then return default or {} end
    local success, data = pcall(serialization.unserialize, raw)
    if success and data then return data end
    return default or {}
end

-- ============================================
-- ЗАГРУЗКА ДАННЫХ
-- ============================================

local admins = loadData(ADMINS_PATH, {})
if #admins == 0 then admins = {"ZoziDo"} end

local players = loadData(DB_PATH, {})
local globalStats = loadData(STATS_PATH, { totalReports = 0, totalBuys = 0, totalSells = 0 })

local sessions = {}
local markets = {}
local shopPaused = false
local lastUpdateId = 0

-- ============================================
-- ОСНОВНЫЕ ФУНКЦИИ
-- ============================================

local function saveDB()
    saveData(DB_PATH, players)
end

local function saveGlobalStats()
    saveData(STATS_PATH, globalStats)
end

local function saveAdmins()
    saveData(ADMINS_PATH, admins)
end

local function isAdmin(name)
    for _, a in ipairs(admins) do
        if a == name then return true end
    end
    return false
end

local function getOrCreatePlayer(name)
    if not players[name] then
        players[name] = {
            balance = 0,
            emaBalance = 0,
            transactions = 0,
            regDate = getRealDateTimeString(),
            agreed = false,
            banned = false,
            hasFeedback = false
        }
        saveDB()
        sendTelegram("🆕 **Новый игрок!**\n👤 " .. name)
    end
    return players[name]
end

local function validateSession(name, token)
    local s = sessions[name]
    return s and s.token == token and os.time() - (s.lastAction or 0) < 31536000
end

local function broadcastUpdate()
    local sent = 0
    for addr in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="update_market"}))
        sent = sent + 1
    end
    return sent
end

local function broadcastKill()
    local sent = 0
    for addr in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="kill_market"}))
        sent = sent + 1
    end
    return sent
end

-- ============================================
-- TELEGRAM ФУНКЦИИ
-- ============================================

local function sendTelegram(text, keyboard)
    if not text then return false end
    local encodedText = text:gsub(" ", "%%20"):gsub("\n", "%%0A"):gsub("#", "%%23"):gsub("&", "%%26")
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/sendMessage"
    local postData = "chat_id=" .. TELEGRAM_CHAT_ID .. "&text=" .. encodedText
    if keyboard then postData = postData .. "&reply_markup=" .. keyboard end
    
    local success = pcall(function()
        internet.request(url, postData, {["Content-Type"] = "application/x-www-form-urlencoded"})
    end)
    return success
end

local function getMainKeyboard()
    return '{"keyboard": [["👥 Игроки", "📊 Статистика"], ["💰 Баланс", "👑 Админы"], ["📦 Добавить предмет", "🔄 Обновить"], ["⏸️ Пауза", "🚫 Закрыть"]], "resize_keyboard": true}'
end

local function getPlayersKeyboard(playersList)
    local keyboard = '{"keyboard": ['
    local row = {}
    for i, name in ipairs(playersList) do
        table.insert(row, '"' .. name .. '"')
        if #row == 2 then
            keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
            row = {}
        end
    end
    if #row > 0 then
        keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
    end
    keyboard = keyboard .. '["🔙 Назад"]], "resize_keyboard": true}'
    return keyboard
end

-- ============================================
-- ОБРАБОТКА КОМАНД
-- ============================================

local function handleTelegramCommand(text)
    if not text or text == "" then return
    
    if text == "/start" or text == "🔙 Назад" then
        sendTelegram("🛒 **PIM Market Admin**\nВыберите действие:", getMainKeyboard())
        return
    end
    
    if text == "👥 Игроки" then
        local msg = "👥 **Список игроков:**\n═══════════════════\n"
        local keys = {}
        for name, data in pairs(players) do
            msg = msg .. (#keys + 1) .. ". " .. name
            if data.banned then msg = msg .. " 🚫"
            msg = msg .. "\n"
            table.insert(keys, name)
        end
        if #keys == 0 then msg = msg .. "Нет игроков"
        sendTelegram(msg, getPlayersKeyboard(keys))
        return
    end
    
    if text == "📊 Статистика" then
        local totalPlayers = 0
        local totalTransactions = 0
        local bannedCount = 0
        for _, p in pairs(players) do
            totalPlayers = totalPlayers + 1
            totalTransactions = totalTransactions + (p.transactions or 0)
            if p.banned then bannedCount = bannedCount + 1
        end
        local msg = "📊 **Статистика**\n"
        msg = msg .. "👥 Игроков: " .. totalPlayers .. "\n"
        msg = msg .. "💰 Транзакций: " .. totalTransactions .. "\n"
        msg = msg .. "🚫 Забанов: " .. bannedCount .. "\n"
        msg = msg .. "👑 Админов: " .. #admins .. "\n"
        msg = msg .. "⏸️ Пауза: " .. (shopPaused and "🔴 Включена" or "🟢 Выключена")
        sendTelegram(msg, getMainKeyboard())
        return
    end
    
    if text == "👑 Админы" then
        local msg = "👑 **Администраторы:**\n═══════════════════\n"
        for i, name in ipairs(admins) do
            msg = msg .. i .. ". " .. name .. "\n"
        end
        if #admins == 0 then msg = msg .. "Нет администраторов"
        sendTelegram(msg, getMainKeyboard())
        return
    end
    
    if text == "⏸️ Пауза" then
        shopPaused = not shopPaused
        for addr in pairs(markets) do
            modem.send(addr, 0xffef, serialization.serialize({op="shop_paused", paused=shopPaused}))
        end
        sendTelegram("⏸️ Магазин **" .. (shopPaused and "🔴 ПРИОСТАНОВЛЕН" or "🟢 ВОЗОБНОВЛЕН") .. "**", getMainKeyboard())
        return
    end
    
    if text == "🔄 Обновить" then
        local sent = broadcastUpdate()
        sendTelegram("✅ **Обновление отправлено** " .. sent .. " терминалам!", getMainKeyboard())
        return
    end
    
    if text == "🚫 Закрыть" then
        local sent = broadcastKill()
        sendTelegram("🚫 **Магазин закрыт!** " .. sent .. " терминалов отключены.", getMainKeyboard())
        return
    end
    
    if text == "📦 Добавить предмет" then
        local msg = "📦 **Добавление предмета**\n"
        msg = msg .. "Отправьте команду:\n"
        msg = msg .. "`/additem internalName displayName цена_coin цена_ema`\n"
        msg = msg .. "Пример: `/additem minecraft:diamond Алмаз 10 5`"
        sendTelegram(msg, getMainKeyboard())
        return
    end
    
    if text:match("^/additem") then
        local parts = {}
        for part in text:gmatch("%S+") do table.insert(parts, part) end
        if #parts >= 4 then
            local internal = parts[2]
            local display = parts[3]
            local coin = tonumber(parts[4]) or 0
            local ema = tonumber(parts[5]) or 0
            if coin == 0 and ema == 0 then
                sendTelegram("❌ Цена не может быть нулевой", getMainKeyboard())
                return
            end
            local buyItems = loadData("/home/buy_items.lua", {})
            table.insert(buyItems, { internalName = internal, displayName = display, price_coin = coin, price_ema = ema, damage = 0 })
            saveData("/home/buy_items.lua", buyItems)
            broadcastUpdate()
            local msg = "✅ **Предмет добавлен!**\n📦 " .. display .. "\n💰 " .. coin .. " ₵\n💚 " .. ema .. " ۞"
            sendTelegram(msg, getMainKeyboard())
        else
            sendTelegram("❌ Формат: `/additem internalName displayName цена_coin цена_ema`", getMainKeyboard())
        end
        return
    end
    
    if text == "💰 Баланс" then
        sendTelegram("💰 **Баланс игрока**\nВведите имя игрока:", '{"keyboard": [["🔙 Назад"]], "resize_keyboard": true}')
        return
    end
    
    -- Проверка имени игрока
    if not text:match("^/") and text ~= "🔙 Назад" and text ~= "👥 Игроки" and text ~= "📊 Статистика" and text ~= "👑 Админы" and text ~= "⏸️ Пауза" and text ~= "🔄 Обновить" and text ~= "🚫 Закрыть" and text ~= "📦 Добавить предмет" and text ~= "💰 Баланс" then
        for name, data in pairs(players) do
            if name:lower() == text:lower() then
                local msg = "👤 **" .. name .. "**\n═══════════════════\n"
                msg = msg .. "💰 Coina: " .. string.format("%.2f", data.balance or 0) .. " ₵\n"
                msg = msg .. "💚 ЭМЫ: " .. string.format("%.2f", data.emaBalance or 0) .. " ۞\n"
                msg = msg .. "📊 Транзакций: " .. (data.transactions or 0) .. "\n"
                if data.banned then msg = msg .. "🚫 **Забанен**" else msg = msg .. "✅ **Активен**"
                sendTelegram(msg, getMainKeyboard())
                return
            end
        end
        sendTelegram("❌ Игрок **" .. text .. "** не найден!", getMainKeyboard())
        return
    end
end

local function checkTelegramUpdates()
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/getUpdates?offset=" .. (lastUpdateId + 1) .. "&timeout=5"
    local success, response = pcall(function() return internet.request(url) end)
    if not success then return
    if type(response) == "table" then
        local responseData = ""
        while true do
            local chunk = response()
            if not chunk then break
            responseData = responseData .. chunk
        end
        local ok, parsed = pcall(serialization.unserialize, responseData)
        if ok and parsed and parsed.result then
            for _, update in ipairs(parsed.result) do
                if update.update_id then lastUpdateId = update.update_id
                if update.message and update.message.text then
                    handleTelegramCommand(update.message.text)
                end
            end
        end
    end
end

-- ============================================
-- ВЕБ-АДМИН ОБРАБОТЧИК
-- ============================================

local function handleWebCommand(msg, from)
    if not isAdmin(msg.admin_name) then
        modem.send(from, 0xffef, serialization.serialize({op="web_response", error="Доступ запрещен"}))
        return
    end
    
    if msg.command == "get_players" then
        local playerList = {}
        for name, data in pairs(players) do
            table.insert(playerList, { name = name, balance = data.balance or 0, emaBalance = data.emaBalance or 0, transactions = data.transactions or 0, banned = data.banned or false, agreed = data.agreed or false })
        end
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="players", players=playerList, admins=admins, total=#playerList}))
        
    elseif msg.command == "set_balance" then
        local player = players[msg.name]
        if player then
            if msg.coin then player.balance = msg.coin end
            if msg.ema then player.emaBalance = msg.ema end
            saveDB()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="balance", success=true}))
        end
        
    elseif msg.command == "toggle_ban" then
        local player = players[msg.name]
        if player then
            player.banned = not player.banned
            saveDB()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="ban", success=true, banned=player.banned}))
        end
        
    elseif msg.command == "reset_player" then
        local player = players[msg.name]
        if player then
            player.balance = 0
            player.emaBalance = 0
            player.transactions = 0
            saveDB()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="reset", success=true}))
        end
        
    elseif msg.command == "add_item" then
        if msg.internal and msg.display then
            local buyItems = loadData("/home/buy_items.lua", {})
            table.insert(buyItems, { internalName = msg.internal, displayName = msg.display, price_coin = msg.price_coin or 0, price_ema = msg.price_ema or 0, damage = msg.damage or 0 })
            saveData("/home/buy_items.lua", buyItems)
            broadcastUpdate()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="add_item", success=true}))
        end
        
    elseif msg.command == "get_admins" then
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="admins", admins=admins}))
        
    elseif msg.command == "add_admin" then
        if msg.name and not isAdmin(msg.name) then
            table.insert(admins, msg.name)
            saveAdmins()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="add_admin", success=true}))
        end
        
    elseif msg.command == "remove_admin" then
        if msg.name and #admins > 1 then
            for i, name in ipairs(admins) do
                if name == msg.name then
                    table.remove(admins, i)
                    saveAdmins()
                    break
                end
            end
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="remove_admin", success=true}))
        end
        
    elseif msg.command == "toggle_pause" then
        shopPaused = not shopPaused
        for addr in pairs(markets) do
            modem.send(addr, 0xffef, serialization.serialize({op="shop_paused", paused=shopPaused}))
        end
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="pause", success=true, paused=shopPaused}))
        
    elseif msg.command == "get_stats" then
        local totalPlayers = 0
        local totalTransactions = 0
        local bannedCount = 0
        for _, p in pairs(players) do
            totalPlayers = totalPlayers + 1
            totalTransactions = totalTransactions + (p.transactions or 0)
            if p.banned then bannedCount = bannedCount + 1
        end
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="stats", totalPlayers=totalPlayers, totalTransactions=totalTransactions, bannedCount=bannedCount, adminsCount=#admins, shopPaused=shopPaused}))
        
    elseif msg.command == "update_market" then
        broadcastUpdate()
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="update", success=true}))
        
    elseif msg.command == "kill_market" then
        broadcastKill()
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="kill", success=true}))
        
    elseif msg.command == "get_logs" then
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="logs", logs={}}))
    end
end

-- ============================================
-- ОСНОВНОЙ ЦИКЛ (ПРОСТОЙ И РАБОЧИЙ!)
-- ============================================

-- Отправляем приветствие
sendTelegram("🤖 **PIM Market Бот запущен!**\nНажмите /start для начала работы.", getMainKeyboard())
print("✅ Бот запущен, жду команды...")
print("")

local lastCheck = 0

while true do
    -- Проверка Telegram каждые 2 секунды
    if os.time() - lastCheck > 2 then
        lastCheck = os.time()
        pcall(checkTelegramUpdates)
    end
    
    local ev = {event.pull(0.5)}
    local etype = ev[1]
    
    if etype == "modem_message" then
        local from = ev[3]
        local raw = ev[6]
        local success, msg = pcall(serialization.unserialize, raw)
        if not success or not msg or type(msg) ~= "table" then
            goto next_event
        end
        
        if msg.op == "register" then
            if msg.password ~= ACCESS_PASSWORD then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Неверный пароль"}))
                goto next_event
            end
            markets[from] = true
            modem.send(from, 0xffef, serialization.serialize({op="welcome", shopPaused=shopPaused}))
            
        elseif msg.op == "enter" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto next_event
            end
            local playerName = msg.name
            if not playerName or playerName == "" then goto next_event end
            
            local player = getOrCreatePlayer(playerName)
            if player.banned then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Вы забанены"}))
                goto next_event
            end
            
            local token = tostring(math.floor(math.random() * 900000000 + 100000000))
            sessions[playerName] = {token = token, lastAction = os.time()}
            
            modem.send(from, 0xffef, serialization.serialize({
                op="welcome",
                status="ok",
                token=token,
                balance=player.balance or 0,
                emaBalance=player.emaBalance or 0,
                transactions=player.transactions,
                regDate=player.regDate,
                agreed=player.agreed or false,
                shopPaused=shopPaused
            }))
            
        elseif msg.op == "sell" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto next_event
            end
            if not validateSession(msg.name, msg.token) then goto next_event end
            local player = players[msg.name]
            if not player or player.banned then goto next_event end
            
            local qty = tonumber(msg.qty) or 0
            local value = tonumber(msg.value) or 0
            local internalName = msg.internalName
            
            if internalName == "customnpcs:npcMoney" then
                player.emaBalance = (player.emaBalance or 0) + value
                sendTelegram("💰 **Пополнение!**\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. qty .. "\n💚 +" .. string.format("%.2f", value) .. " ۞")
            else
                player.balance = (player.balance or 0) + value
                sendTelegram("💰 **Пополнение!**\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. qty .. "\n💰 +" .. string.format("%.2f", value) .. " ₵")
            end
            player.transactions = (player.transactions or 0) + 1
            sessions[msg.name].lastAction = os.time()
            globalStats.totalSells = (globalStats.totalSells or 0) + 1
            saveGlobalStats()
            saveDB()
            
        elseif msg.op == "buy" then
            if shopPaused then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                goto next_event
            end
            if not validateSession(msg.name, msg.token) then goto next_event end
            local player = players[msg.name]
            if not player or player.banned then goto next_event end
            
            local value_coin = tonumber(msg.value_coin) or 0
            local value_ema = tonumber(msg.value_ema) or 0
            
            if player.balance < value_coin or player.emaBalance < value_ema then
                modem.send(from, 0xffef, serialization.serialize({op="error", message="Недостаточно средств"}))
                goto next_event
            end
            
            player.balance = player.balance - value_coin
            player.emaBalance = player.emaBalance - value_ema
            player.transactions = (player.transactions or 0) + 1
            sessions[msg.name].lastAction = os.time()
            globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
            saveGlobalStats()
            saveDB()
            
            local priceStr = ""
            if value_coin > 0 then priceStr = priceStr .. string.format("%.2f", value_coin) .. "₵"
            if value_ema > 0 then
                if priceStr ~= "" then priceStr = priceStr .. " + "
                priceStr = priceStr .. string.format("%.2f", value_ema) .. "۞"
            end
            sendTelegram("🛒 **Покупка!**\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. (msg.qty or 0) .. "\n💳 " .. priceStr)
            
        elseif msg.op == "report" then
            if not validateSession(msg.name, msg.token) then goto next_event end
            globalStats.totalReports = (globalStats.totalReports or 0) + 1
            saveGlobalStats()
            sendTelegram("📩 **Репорт!**\n👤 " .. msg.name .. "\n📝 " .. (msg.text or ""))
            
        elseif msg.op == "agree" then
            if not validateSession(msg.name, msg.token) then
                modem.send(from, 0xffef, serialization.serialize({op="agree", error=true, message="Токен устарел"}))
                goto next_event
            end
            local player = players[msg.name]
            if player then
                player.agreed = true
                saveDB()
                sessions[msg.name].lastAction = os.time()
                sendTelegram("📝 **Соглашение принято!**\n👤 " .. msg.name)
                modem.send(from, 0xffef, serialization.serialize({op="agree", success=true, agreed=true}))
            end
            
        elseif msg.op == "web_command" then
            handleWebCommand(msg, from)
        end
    end
    
    ::next_event::
end
