local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local keyboard = require("keyboard")
local computer = require("computer")
local fs = require("filesystem")
local shell = require("shell")
local internet = require("internet")
local math = require("math")
local os = require("os")
local TIMEZONE_OFFSET = 3 * 3600

-- ============================================================
-- ★★★  ЗАЩИТА ★★★123
-- ============================================================
pcall(function()
    event.ignore("interrupted", function() end)
    event.ignore("terminate", function() end)
end)

if not event.shouldInterrupt then
    function event.shouldInterrupt()
        return false
    end
end

originalExit = os.exit
os.exit = function(code)
    if code == 0 then return else originalExit(code) end
end

-- ============================================================
-- ВРЕМЯ
-- ============================================================

tmpfs = component.proxy(computer.tmpAddress())
function getRealTimestamp()
    local handle = tmpfs.open("/time", "w")
    tmpfs.write(handle, "time")
    tmpfs.close(handle)
    return tmpfs.lastModified("/time") / 1000 + TIMEZONE_OFFSET
end

function getRealTimeString()
    return os.date("%d.%m.%Y %H:%M:%S", getRealTimestamp())
end

function getRealTimeHM()
    return os.date("%H:%M:%S", getRealTimestamp())
end

-- ============================================================
-- ВЕБ-ИНТЕГРАЦИЯ
-- ============================================================

WEB_URL = "https://upfront-dinginess-impulsive.ngrok-free.dev"

function toJson(val)
    if type(val) == "string" then
        return '"' .. val:gsub('"', '\\"') .. '"'
    elseif type(val) == "number" or type(val) == "boolean" then
        return tostring(val)
    elseif type(val) == "table" then
        local isArray = true
        local count = 0
        for k, _ in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            count = count + 1
        end
        if isArray and count == #val then
            local parts = {}
            for i = 1, #val do
                table.insert(parts, toJson(val[i]))
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                table.insert(parts, '"' .. k .. '":' .. toJson(v))
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    else
        return "null"
    end
end

function sendToWeb(endpoint, jsonData)
    pcall(function()
        internet.request(WEB_URL .. endpoint, jsonData, {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close"
        })
    end)
end

-- ============================================================
-- ОТПРАВКА ЛОГОВ НА ВЕБ (С НАКОПЛЕНИЕМ)
-- ============================================================

logQueue = {}

function addLogEntry(text, level)
    if not text then text = "?" end
    level = level or "INFO"
    local entry = {
        text = text,
        time = getRealTimeHM(),
        level = level
    }
    table.insert(logQueue, entry)

    if #logQueue >= 50 then
        local batch = {}
        for _, e in ipairs(logQueue) do
            table.insert(batch, {
                time = e.time,
                text = e.text,
                level = e.level
            })
        end
        sendToWeb("/api/logs_batch", toJson({logs = batch}))
        logQueue = {}
    end
end

LOG_FLUSH_INTERVAL = 15
function flushLogQueue()
    if #logQueue == 0 then return end
    local batch = {}
    for _, e in ipairs(logQueue) do
        table.insert(batch, { time = e.time, text = e.text, level = e.level })
    end
    sendToWeb("/api/logs_batch", toJson({ logs = batch }))
    logQueue = {}
end
event.timer(LOG_FLUSH_INTERVAL, flushLogQueue, math.huge)

function addLog(text)
    addLogEntry(text, "INFO")
end

-- ============================================================
-- ОТПРАВКА ОШИБОК НА ВЕБ
-- ============================================================

function sendErrorToWeb(error_msg, level)
    level = level or "ERROR"
    local timestamp = getRealTimeHM()
    sendToWeb("/api/error_log", toJson({
        error = error_msg,
        level = level,
        time = timestamp
    }))
end

-- ============================================================
-- ДЕТАЛЬНОЕ ЛОГИРОВАНИЕ ОШИБОК
-- ============================================================

ERROR_LOG = "/home/errors.log"

function writeErrorLog(msg)
    -- Локальное логирование в файл ОТКЛЮЧЕНО (чтобы не забивать диск)
    -- Ошибки всё равно отправляются на веб-сервер и в очередь логов
    addLogEntry(msg, "ERROR")
    sendErrorToWeb(msg, "ERROR")
end

function writeDebugLog(msg)
    -- Отладочные логи полностью отключены
end

function safeCall(func, ...)
    local args = {...}
    local ok, err = pcall(func, table.unpack(args))
    if not ok then
        local debugInfo = debug.getinfo(func, "l")
        local line = debugInfo and debugInfo.currentline or "?"
        local errorMsg = "ОШИБКА в строке " .. line .. ": " .. tostring(err)
        print(errorMsg)
        writeErrorLog(errorMsg)
        if type(err) == "string" and err:find("nil") then
            writeErrorLog("  → Возможно, переменная равна nil")
        end
        return false, err
    end
    return true, ok
end

-- ============================================================
-- ИГНОРИРОВАНИЕ СОБЫТИЙ
-- ============================================================

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

originalExit = os.exit
os.exit = function(code)
    if code == 0 then return else originalExit(code) end
end

-- ============================================================
-- ПЕРЕМЕННАЯ ДЛЯ ТЕРМИНАЛОВ
-- ============================================================

markets = {}

-- ============================================================
-- ЦВЕТА
-- ============================================================

colors = {
    bg_main = 0x0A0A0F,
    bg_secondary = 0x14141F,
    bg_button = 0x1F1F2E,
    accent_main = 0x8B5CF6,
    accent_secondary = 0x00E5C9,
    text_main = 0xD0D0E0,
    text_bright = 0xF0F0FF,
    success = 0x00FFAA,
    error = 0xFF4D7A,
    inactive = 0x555566,
    star_glow = 0xC8C8FF,
    black_fon = 0x000000,
    tomato = 0xFF6347,
    white = 0xFFFFFF
}

-- ============================================================
-- UI БАЗОВЫЕ ФУНКЦИИ
-- ============================================================

function clear()
    writeDebugLog("clear() вызвана")
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
end

function drawCenteredText(y, text, color)
    writeDebugLog("drawCenteredText: y=" .. tostring(y) .. ", text=" .. tostring(text))
    if not text then
        writeErrorLog("❌ drawCenteredText: text = nil!")
        text = ""
    end
    gpu.setForeground(color or colors.text_main)
    local x = math.floor((80 - unicode.len(text)) / 2) + 1
    gpu.set(x, y, text)
end

function drawButton(btn)
    if not btn then
        writeErrorLog("❌ drawButton: btn = nil!")
        return
    end
    writeDebugLog("drawButton: " .. (btn.text or "?"))
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, text)
    gpu.setBackground(colors.bg_main)
end

function drawFlexButton(btn)
    if not btn then
        writeErrorLog("❌ drawFlexButton: btn = nil!")
        return
    end
    writeDebugLog("drawFlexButton: " .. (btn.text or "?"))
    gpu.setBackground(btn.bg)
    gpu.fill(btn.x, btn.y, btn.xs, btn.ys, " ")
    gpu.setForeground(btn.fg)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    gpu.set(textX, textY, text)
    gpu.setBackground(colors.bg_main)
end

function drawPopupBorder(x, y, w, h, color)
    writeDebugLog("drawPopupBorder: x=" .. tostring(x) .. ", y=" .. tostring(y) .. ", w=" .. tostring(w) .. ", h=" .. tostring(h))
    gpu.setForeground(color or colors.accent_secondary)
    gpu.fill(x, y, w, 1, "─")
    gpu.fill(x, y + h - 1, w, 1, "─")
    for i = 1, h - 2 do
        gpu.set(x, y + i, "│")
        gpu.set(x + w - 1, y + i, "│")
    end
    gpu.set(x, y, "┌")
    gpu.set(x + w - 1, y, "┐")
    gpu.set(x, y + h - 1, "└")
    gpu.set(x + w - 1, y + h - 1, "┘")
end

function drawScreenBorder()
    writeDebugLog("drawScreenBorder()")
    local left = 1
    local right = 80
    local top = 1
    local bottom = 24
    gpu.setForeground(colors.accent_secondary)
    gpu.fill(left, top, right - left + 1, 1, "─")
    gpu.fill(left, bottom, right - left + 1, 1, "─")
    for y = top + 1, bottom - 1 do
        gpu.set(left, y, "│")
        gpu.set(right, y, "│")
    end
    gpu.set(left, top, "┌")
    gpu.set(right, top, "┐")
    gpu.set(left, bottom, "└")
    gpu.set(right, bottom, "┘")
end

function drawTempMessage()
    if tempMessage ~= "" and tempMessage then
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
        gpu.setForeground(colors.success)
        local x = math.floor((80 - unicode.len(tempMessage)) / 2) + 1
        gpu.set(x, 25, tempMessage)
    else
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
    end
end

function drawTextMessage(msg, color)
    writeDebugLog("drawTextMessage: " .. tostring(msg))
    if msg and msg ~= "" then
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
        gpu.setForeground(color or colors.success)
        local x = math.floor((80 - unicode.len(msg)) / 2) + 1
        gpu.set(x, 25, msg)
    else
        gpu.setBackground(colors.bg_main)
        gpu.fill(1, 25, 80, 1, " ")
    end
end

function drawAccountLoading()
    writeDebugLog("drawAccountLoading()")
    clear()
    drawScreenBorder()
    drawCenteredText(12, "Загрузка данных аккаунта...", colors.text_main)
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(backButton)
    drawTempMessage()
end

drawcountLoading = drawAccountLoading

function isButtonClicked(btn, x, y)
    if not btn then
        writeErrorLog("❌ isButtonClicked: btn = nil!")
        return false
    end
    return y >= btn.y and y < btn.y + btn.ys and x >= btn.x and x < btn.x + btn.xs
end

-- ============================================================
-- БАЗЫ ДАННЫХ
-- ============================================================

ADMINS_PATH = "/home/admins.db"
DB_PATH = "/home/players.db"
STATS_PATH = "/home/global_stats.db"
FEEDBACKS_PATH = "/home/feedbacks.db"
REPORTS_PATH = "/home/reports.log"
PENDING_FILE = "/home/pending_changes.lua"  -- ★ НОВЫЙ БУФЕР ИЗМЕНЕНИЙ ★

admins = {}
players = {}
globalStats = { totalReports = 0, totalBuys = 0, totalSells = 0, totalRevenue = 0, totalBalance = 0 }
transactions = {}
pending_buffer = {}  -- ★ БУФЕР ДЛЯ ДЕЛЬТ ★
retry_delay = 10     -- ★ НАЧАЛЬНАЯ ЗАДЕРЖКА ДЛЯ ОТПРАВКИ ★

-- ============================================================
-- ФУНКЦИИ ДЛЯ БУФЕРА ИЗМЕНЕНИЙ
-- ============================================================

function load_pending_buffer()
    if fs.exists(PENDING_FILE) then
        local ok, data = pcall(dofile, PENDING_FILE)
        if ok and type(data) == "table" then
            pending_buffer = data
            writeDebugLog("📂 Загружен буфер изменений: " .. #pending_buffer .. " записей")
        else
            pending_buffer = {}
        end
    else
        pending_buffer = {}
    end
end

function save_pending_buffer()
    local tmp = PENDING_FILE .. ".tmp"
    local file = io.open(tmp, "w")
    if file then
        file:write(serialization.serialize(pending_buffer))
        file:close()
        fs.rename(tmp, PENDING_FILE)
        return true
    else
        writeErrorLog("❌ Не удалось сохранить буфер изменений")
        return false
    end
end

function add_pending_change(change)
    if not change.id then
        change.id = "chg_" .. os.time() .. "_" .. math.random(100000)
    end
    table.insert(pending_buffer, change)
    save_pending_buffer()
    if #pending_buffer >= 50 then
        send_pending_changes()
    end
end

function clear_pending_changes(ids)
    -- ★★★ ЕСЛИ ID НЕ ПЕРЕДАНЫ — ОЧИЩАЕМ ВСЁ ★★★
    if not ids then
        pending_buffer = {}
        save_pending_buffer()
        writeDebugLog("🗑️ Буфер полностью очищен")
        return
    end
    
    -- ★★★ ЕСЛИ ПЕРЕДАН ПУСТОЙ СПИСОК — ТОЖЕ ОЧИЩАЕМ ВСЁ ★★★
    if type(ids) == "table" and #ids == 0 then
        pending_buffer = {}
        save_pending_buffer()
        writeDebugLog("🗑️ Буфер полностью очищен (пустой список)")
        return
    end
    
    local new_buffer = {}
    local removed_count = 0
    local ids_set = {}
    for _, id in ipairs(ids) do ids_set[id] = true end
    
    for _, change in ipairs(pending_buffer) do
        if ids_set[change.id] then
            removed_count = removed_count + 1
        else
            table.insert(new_buffer, change)
        end
    end
    
    pending_buffer = new_buffer
    save_pending_buffer()
    if removed_count > 0 then
        writeDebugLog("🗑️ Удалено из буфера: " .. removed_count .. " записей")
    end
end
-- ============================================================
-- ОТПРАВКА БУФЕРА ИЗМЕНЕНИЙ НА СЕРВЕР (ДЕЛЬТА)
-- ============================================================

function send_pending_changes()
    if #pending_buffer == 0 then
        retry_delay = 10
        return
    end

    local changes_to_send = {}
    for _, ch in ipairs(pending_buffer) do
        table.insert(changes_to_send, ch)
    end

    local payload = { changes = changes_to_send }
    local json_payload = toJson(payload)

    writeDebugLog("📤 Отправка дельты: " .. #changes_to_send .. " изменений")

    -- ★★★ ОТПРАВЛЯЕМ ЗАПРОС ★★★
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/delta", json_payload, {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close"
        })
    end)

    -- ★★★ ОЧИЩАЕМ БУФЕР СРАЗУ, НЕ ДОЖИДАЯСЬ ОТВЕТА ★★★
    pending_buffer = {}
    save_pending_buffer()
    writeDebugLog("🗑️ Буфер очищен (дельты отправлены)")

    -- ★★★ ПЫТАЕМСЯ ПРОЧИТАТЬ ОТВЕТ (НО НЕ ЖДЁМ ЕГО) ★★★
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.status == "ok" then
            writeDebugLog("✅ Дельта подтверждена сервером")
            retry_delay = 10
        else
            writeDebugLog("⚠️ Сервер вернул ошибку, но буфер уже очищен")
            retry_delay = math.min(retry_delay * 2, 120)
        end
    else
        writeDebugLog("⚠️ Ошибка соединения, но буфер уже очищен")
        retry_delay = math.min(retry_delay * 2, 120)
    end
end

-- Запускаем таймер для периодической отправки буфера
event.timer(10, function()
    if #pending_buffer > 0 then
        send_pending_changes()
    end
    return true
end, math.huge)

-- ============================================================
-- ФУНКЦИИ ДЛЯ РАБОТЫ С ФАЙЛАМИ (СОХРАНЕНИЕ)
-- ============================================================

function ensureFileExists(path, defaultData)
    writeDebugLog("ensureFileExists: " .. path)
    if not fs.exists(path) then
        print("📁 Создаём файл: " .. path)
        writeErrorLog("📁 Создаём файл: " .. path)
        local file = io.open(path, "w")
        if file then
            if type(defaultData) == "string" then
                file:write(defaultData)
            else
                file:write(serialization.serialize(defaultData))
            end
            file:close()
            return true
        end
        return false
    end
    return true
end

ensureFileExists(ADMINS_PATH, {"ZoziDo"})
ensureFileExists(DB_PATH, {})
ensureFileExists(STATS_PATH, { totalReports = 0, totalBuys = 0, totalSells = 0, totalRevenue = 0, totalBalance = 0 })
ensureFileExists(FEEDBACKS_PATH, {})
ensureFileExists(REPORTS_PATH, "")
ensureFileExists(PENDING_FILE, {})

-- Загрузка админов
if fs.exists(ADMINS_PATH) then
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
if fs.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then players = data end
    end
end

-- Загрузка статистики
if fs.exists(STATS_PATH) then
    local file = io.open(STATS_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then
            globalStats.totalReports = data.totalReports or 0
            globalStats.totalBuys = data.totalBuys or 0
            globalStats.totalSells = data.totalSells or 0
            globalStats.totalRevenue = data.totalRevenue or 0
            globalStats.totalBalance = data.totalBalance or 0
        end
    end
end

-- Загрузка буфера изменений
load_pending_buffer()

-- Отложенное сохранение БД (не чаще раза в 5 секунд)
dbDirty = false
SAVE_DB_INTERVAL = 5

function saveDB()
    writeDebugLog("saveDB() – сохраняем " .. #players .. " игроков")
    for name, data in pairs(players) do
        if data.transactionsList then
            writeDebugLog("   " .. name .. " имеет " .. #data.transactionsList .. " транзакций")
        end
    end
    local file = io.open(DB_PATH, "w")
    file:write(serialization.serialize(players))
    file:close()
end

function saveDBDeferred()
    dbDirty = true
end

function flushDB()
    if not dbDirty then return end
    saveDB()
    dbDirty = false
end

event.timer(SAVE_DB_INTERVAL, flushDB, math.huge)

function saveGlobalStats()
    writeDebugLog("saveGlobalStats()")
    local file = io.open(STATS_PATH, "w")
    file:write(serialization.serialize(globalStats))
    file:close()
end

function isAdmin(playerName)
    if not playerName then return false end
    for _, name in ipairs(admins) do
        if name == playerName then return true end
    end
    return false
end

function addAdmin(playerName)
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

function removeAdmin(playerName)
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

-- ============================================================
-- ДОБАВЛЕНИЕ ТРАНЗАКЦИИ (С ЗАПИСЬЮ В БУФЕР)
-- ============================================================

function addTransaction(type, playerName, item, qty, value_coin, value_ema)
    writeDebugLog("addTransaction: " .. type .. " " .. (playerName or "?"))
    
    if type == "sell" then
        globalStats.totalSells = (globalStats.totalSells or 0) + 1
        globalStats.totalRevenue = (globalStats.totalRevenue or 0) + (value_coin or 0) + (value_ema or 0)
    elseif type == "buy" then
        globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
    end
    saveGlobalStats()
    
    -- Создаём запись транзакции
    local transactionRecord = {
        time = getRealTimeHM(),
        type = type,
        item = item or "?",
        qty = qty or 0,
        coin = value_coin or 0,
        ema = value_ema or 0
    }
    
    -- Добавляем в глобальный список (для истории)
    table.insert(transactions, {
        time = transactionRecord.time,
        type = type,
        player = playerName or "?",
        item = item or "?",
        qty = qty or 0,
        coin = value_coin or 0,
        ema = value_ema or 0
    })
    while #transactions > 100 do table.remove(transactions, 1) end
    
    -- ★ СОЗДАЁМ ИЛИ ОБНОВЛЯЕМ ИГРОКА ★
    if playerName and playerName ~= "?" then
        if not players[playerName] then
            players[playerName] = {
                balance = 0,
                emaBalance = 0,
                transactions = 0,
                banned = false,
                agreed = false,
                hasFeedback = false,
                transactionsList = {},
                regDate = getRealTimeString()
            }
            writeDebugLog("➕ Создан новый игрок в addTransaction: " .. playerName)
        end
        
        players[playerName].transactions = (players[playerName].transactions or 0) + 1
        if not players[playerName].transactionsList then
            players[playerName].transactionsList = {}
        end
        table.insert(players[playerName].transactionsList, transactionRecord)
        saveDBDeferred()
        writeDebugLog("📊 Транзакции игрока " .. playerName .. ": " .. players[playerName].transactions)
        writeDebugLog("📋 Список теперь содержит " .. #players[playerName].transactionsList .. " записей")
    else
        writeErrorLog("⚠️ Некорректное имя игрока при добавлении транзакции: " .. tostring(playerName))
    end
    
    -- ★ ДОБАВЛЯЕМ ИЗМЕНЕНИЕ В ОБЩИЙ БУФЕР ★
    local change = {
        id = "txn_" .. os.time() .. "_" .. math.random(100000),
        type = type,  -- "buy" или "sell"
        data = {
            player = playerName,
            item = item,
            qty = qty,
            coin = value_coin or 0,
            ema = value_ema or 0
        }
    }
    add_pending_change(change)
end

-- ============================================================
-- ФУНКЦИИ ДЛЯ ТЕРМИНАЛОВ
-- ============================================================

function broadcastUpdate()
    writeDebugLog("📢 Рассылка обновления терминалам")
    local msg = serialization.serialize({
        op = "update_market",
        type = "reload_items"
    })
    for addr in pairs(markets) do
        pcall(modem.send, addr, 0xffef, msg)
    end
end

function broadcastKill()
    writeDebugLog("💀 Рассылка команды завершения терминалам")
    local msg = serialization.serialize({op="kill_market"})
    for addr in pairs(markets) do
        pcall(modem.send, addr, 0xffef, msg)
    end
end

-- ============================================================
-- ОТПРАВКА СТАТИСТИКИ (ПОЛНЫЙ ДАМП – РЕЗЕРВ)
-- ============================================================

function sendStats()
    writeDebugLog("📊 sendStats() начат (резервный дамп)")
    
    local playerList = {}
    local totalBalance = 0
    local playerCount = 0
    local allPlayerTransactions = {}
    
    for _ in pairs(players) do playerCount = playerCount + 1 end
    writeDebugLog("📊 Всего игроков в памяти: " .. playerCount)
    
    for name, data in pairs(players) do
        writeDebugLog("   👤 " .. name .. ": Coin=" .. tostring(data.balance or 0) .. ", EMA=" .. tostring(data.emaBalance or 0))
        local bal = (data.balance or 0) + (data.emaBalance or 0)
        totalBalance = totalBalance + bal
        
        if not data.transactionsList then
            data.transactionsList = {}
        end
        
        if data.transactionsList then
            for _, t in ipairs(data.transactionsList) do
                local tCopy = {
                    time = t.time,
                    type = t.type,
                    player = name,
                    item = t.item,
                    qty = t.qty,
                    coin = t.coin,
                    ema = t.ema
                }
                table.insert(allPlayerTransactions, tCopy)
            end
        end
        
        table.insert(playerList, {
            name = name,
            balance = data.balance or 0,
            emaBalance = data.emaBalance or 0,
            transactions = data.transactions or 0,
            banned = data.banned or false,
            transactionsList = data.transactionsList
        })
    end
    
    table.sort(allPlayerTransactions, function(a, b)
        return a.time > b.time
    end)
    
    writeDebugLog("👥 Игроков отправлено: " .. #playerList)
    writeDebugLog("📋 Всего транзакций отправлено: " .. #allPlayerTransactions)
    globalStats.totalBalance = totalBalance
    saveGlobalStats()
    
    local feedbacksList = {}
    if fs.exists(FEEDBACKS_PATH) then
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
    
    local buyItems = {}
    if fs.exists("/home/buy_items.lua") then
        local ok, data = pcall(dofile, "/home/buy_items.lua")
        if ok and type(data) == "table" then 
            buyItems = data 
            writeDebugLog("📦 Загружены buy_items: " .. #buyItems .. " товаров")
        else
            writeErrorLog("❌ Ошибка загрузки buy_items.lua")
        end
    else
        writeErrorLog("⚠️ Файл /home/buy_items.lua не найден")
    end
    
    local sellItems = {}
    if fs.exists("/home/shop_items.lua") then
        local ok, data = pcall(dofile, "/home/shop_items.lua")
        if ok and type(data) == "table" and data.sellItems then
            sellItems = data.sellItems
            writeDebugLog("📦 Загружены sell_items: " .. #sellItems .. " товаров")
        else
            writeErrorLog("❌ Ошибка загрузки shop_items.lua")
        end
    else
        writeErrorLog("⚠️ Файл /home/shop_items.lua не найден")
    end
    
    local payload = {
        players = playerList,
        admins = admins,
        total = #playerList,
        total_balance = totalBalance,
        total_transactions = (globalStats.totalBuys or 0) + (globalStats.totalSells or 0),
        total_reports = globalStats.totalReports or 0,
        total_feedbacks = #feedbacksList,
        total_revenue = globalStats.totalRevenue or 0,
        online = 0,
        paused = shopPaused,
        feedbacks = feedbacksList,
        transactions = allPlayerTransactions,
        buy_items = buyItems,
        sell_items = sellItems
    }
    
    local jsonData = toJson(payload)
    writeDebugLog("📤 Размер JSON: " .. #jsonData .. " байт")
    writeDebugLog("📤 Отправлены данные: " .. #playerList .. " игроков, " .. #buyItems .. " товаров покупки, " .. #sellItems .. " товаров продажи")
    
    sendToWeb("/api/update", jsonData)
end

-- Резервный дамп раз в час (на случай, если дельта-обновления пропущены)
event.timer(60, sendStats, math.huge)

-- ============================================================
-- ЗАГРУЗКА ТОВАРОВ И СОГЛАШЕНИЯ
-- ============================================================

function safeDoFile(path)
    writeDebugLog("safeDoFile: " .. path)
    if not fs.exists(path) then
        writeErrorLog("⚠️ Файл не найден: " .. path)
        return {}
    end
    local ok, result = pcall(dofile, path)
    if not ok then
        writeErrorLog("❌ Ошибка загрузки файла " .. path .. ": " .. tostring(result))
        return {}
    end
    return result
end

shopData = safeDoFile("/home/shop_items.lua")
sellItems = shopData.sellItems or {}
vanillaItems = shopData.vanillaItems or {}

buyItemsData = safeDoFile("/home/buy_items.lua")
buyItemMap = {}
for _, item in ipairs(buyItemsData) do
    local dmg = item.damage or 0
    local key = item.internalName .. ":" .. dmg
    buyItemMap[key] = item
end

-- ============================================================
-- PIM И МОДЕМ
-- ============================================================

modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

event.listen("modem_message", function(_, _, from, port, _, _, data)
    if port == 0xffef then
        local ok, msg = pcall(serialization.unserialize, data)
        if ok and msg and msg.op == "register" then
            markets[from] = true
            writeDebugLog("📡 Терминал зарегистрирован: " .. from)
        end
    end
end)

function getPimAddr()
    for addr in component.list("pim") do
        return addr
    end
    return nil
end

PUSH_DIRECTION = "down"
PULL_DIRECTION = "up"

function normalizeName(name)
    if not name then return "" end
    local lastColon = name:match(".*:([^:]+)$")
    return lastColon or name
end

function namesMatch(name1, name2)
    if not name1 or not name2 then return false end
    if name1 == name2 then return true end
    local short1 = normalizeName(name1)
    local short2 = normalizeName(name2)
    return short1 == short2
end

selector = nil
for addr in component.list("openperipheral_selector") do
    selector = component.proxy(addr)
    break
end
if not selector then
    for addr in component.list("item_selector") do
        selector = component.proxy(addr)
        break
    end
end

-- ============================================================
-- СОСТОЯНИЕ МАГАЗИНА
-- ============================================================

currentPlayer, currentToken = nil, nil
pimOwner = nil
coinBalance = 0.0
emaBalance = 0.0
playerTransactions = 0
playerRegDate = ""
playerAgreed = false
currentScreen = "welcome"
authStartTime = 0
AUTH_TIMEOUT = 3
alreadyAuthorized = false

shopItems = {}
shopSearch = ""
searchActive = false
searchInput = ""
currentShopMode = "buy"
shopPaused = false

blacklist = {
    ["customnpcs:npcMoney"] = true,
}

listScroll = 1
visibleRows = 15
selectedIndex = 0
hoveredIndex = 0
filteredItems = {}
selectedItem = nil
horizontalScroll = 1
maxItemWidth = 0
purchaseQuantity = 1
purchaseItem = nil
sellConfirmItem = nil
foundAmount = 0
showSellPopup = false

showPartialPopup = false
partialExtracted = 0
partialRequested = 0
partialRefundCoin = 0
partialRefundEma = 0
partialItem = nil

showInsufficientPopup = false
insufficientBalanceCoin = 0
insufficientBalanceEma = 0

showInventoryFullPopup = false

reportInput = ""
lastReportTime = nil
showShopDenied = false

tempMessage = ""
tempMessageTimer = nil

feedbacks = {}
feedbacksPage = 1
feedbacksTotalPages = 1
feedbackInput = ""
feedbackEditMode = false
playerHasFeedback = false

-- ============================================================
-- НАДЁЖНЫЙ JSON ПАРСЕР
-- ============================================================

function parseJSON(json_str)
    if not json_str or json_str == "" then 
        writeDebugLog("parseJSON: пустая строка")
        return nil 
    end

    local str = json_str
    local pos = 1
    local len = #str

    local parseValue, parseArray, parseObject

    local function skipSpace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then break end
            pos = pos + 1
        end
    end

    local function parseString()
        if str:sub(pos, pos) ~= '"' then return nil end
        pos = pos + 1
        local start = pos
        local result = ""
        while pos <= len do
            local ch = str:sub(pos, pos)
            if ch == '"' then
                result = result .. str:sub(start, pos-1)
                pos = pos + 1
                return result
            elseif ch == '\\' then
                result = result .. str:sub(start, pos-1)
                pos = pos + 1
                if pos > len then return nil end
                local esc = str:sub(pos, pos)
                local map = {['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t'}
                result = result .. (map[esc] or '\\'..esc)
                pos = pos + 1
                start = pos
            else
                pos = pos + 1
            end
        end
        return nil
    end

    local function parseNumber()
        local start = pos
        while pos <= len do
            local ch = str:sub(pos, pos)
            if not ch:match("[%d%.%-%+eE]") then break end
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos-1))
    end

    function parseArray()
        if str:sub(pos, pos) ~= '[' then return nil end
        pos = pos + 1
        local arr = {}
        skipSpace()
        if str:sub(pos, pos) == ']' then
            pos = pos + 1
            return arr
        end
        while true do
            local val = parseValue()
            if val == nil then break end
            table.insert(arr, val)
            skipSpace()
            local ch = str:sub(pos, pos)
            if ch == ',' then pos = pos + 1
            elseif ch == ']' then pos = pos + 1; break
            else break end
        end
        return arr
    end

    function parseObject()
        if str:sub(pos, pos) ~= '{' then return nil end
        pos = pos + 1
        local obj = {}
        skipSpace()
        if str:sub(pos, pos) == '}' then
            pos = pos + 1
            return obj
        end
        while true do
            skipSpace()
            local key = parseString()
            if not key then break end
            skipSpace()
            if str:sub(pos, pos) ~= ':' then break end
            pos = pos + 1
            skipSpace()
            local val = parseValue()
            if val == nil then break end
            obj[key] = val
            skipSpace()
            local ch = str:sub(pos, pos)
            if ch == ',' then pos = pos + 1
            elseif ch == '}' then pos = pos + 1; break
            else break end
        end
        return obj
    end

    function parseValue()
        skipSpace()
        if pos > len then return nil end
        local ch = str:sub(pos, pos)

        if ch == '"' then
            return parseString()
        elseif ch == '{' then
            return parseObject()
        elseif ch == '[' then
            return parseArray()
        elseif ch == 't' and str:sub(pos, pos+3) == 'true' then
            pos = pos + 4
            return true
        elseif ch == 'f' and str:sub(pos, pos+4) == 'false' then
            pos = pos + 5
            return false
        elseif ch == 'n' and str:sub(pos, pos+3) == 'null' then
            pos = pos + 4
            return nil
        elseif ch:match("[%d%-]") then
            return parseNumber()
        end
        writeDebugLog("parseValue: неизвестный символ " .. ch)
        return nil
    end

    skipSpace()
    local result = parseValue()
    writeDebugLog("parseJSON результат: " .. (result and "таблица" or "nil"))
    return result
end

-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================

function isPimOwner(playerName)
    if not playerName or not pimOwner then return false end
    return playerName == pimOwner
end

function syncCurrentPlayer()
    if not currentPlayer then return end
    
    writeDebugLog("🔄 Синхронизация игрока: " .. currentPlayer)
    
    if players[currentPlayer] then
        coinBalance = players[currentPlayer].balance or 0
        emaBalance = players[currentPlayer].emaBalance or 0
        playerTransactions = players[currentPlayer].transactions or 0
        playerRegDate = players[currentPlayer].regDate or ""
        playerAgreed = players[currentPlayer].agreed or false
        
        writeDebugLog("✅ Синхронизирован: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        return true
    end
    
    writeDebugLog("⚠️ Игрок не найден при синхронизации: " .. currentPlayer)
    return false
end

function updateSelectorDisplay(item)
    if not selector then return end
    if not item then
        pcall(selector.setSlot, 0, nil)
        pcall(selector.setSlot, 1, nil)
        return
    end
    local raw = item.internalName or item.name or item.displayName
    if not raw then return end
    local id = raw
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local dmg = item.damage or 0
    local stack = { id = id, dmg = dmg }
    pcall(selector.setSlot, 0, stack)
    pcall(selector.setSlot, 1, stack)
end

function sortableName(name)
    if not name then return "" end
    local lower = string.lower(name)
    local result = lower:gsub("(%d+)", function(d)
        return string.format("%08d", tonumber(d))
    end)
    return result
end

function toLowerCase(str)
    if not str then return "" end
    str = string.lower(str)
    str = str:gsub("А", "а"):gsub("Б", "б"):gsub("В", "в"):gsub("Г", "г"):gsub("Д", "д")
    str = str:gsub("Е", "е"):gsub("Ё", "ё"):gsub("Ж", "ж"):gsub("З", "з"):gsub("И", "и")
    str = str:gsub("Й", "й"):gsub("К", "к"):gsub("Л", "л"):gsub("М", "м"):gsub("Н", "н")
    str = str:gsub("О", "о"):gsub("П", "п"):gsub("Р", "р"):gsub("С", "с"):gsub("Т", "т")
    str = str:gsub("У", "у"):gsub("Ф", "ф"):gsub("Х", "х"):gsub("Ц", "ц"):gsub("Ч", "ч")
    str = str:gsub("Ш", "ш"):gsub("Щ", "щ"):gsub("Ъ", "ъ"):gsub("Ы", "ы"):gsub("Ь", "ь")
    str = str:gsub("Э", "э"):gsub("Ю", "ю"):gsub("Я", "я")
    return str
end

function canSendReport()
    if not lastReportTime then return true end
    local now = getRealTimestamp()
    local reportDate = os.date("*t", lastReportTime)
    local nowDate = os.date("*t", now)
    if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
        return true
    end
    return false
end

function getActualItemQuantity(internalName, damage)
    if not component.isAvailable("me_interface") then return 0 end
    local me = component.me_interface
    local items = me.getItemsInNetwork()
    local total = 0
    for _, meItem in ipairs(items) do
        if meItem.name == internalName and (meItem.damage or 0) == (damage or 0) then
            total = total + (meItem.size or 0)
        end
    end
    return total
end

function showTempMessage(msg, duration)
    writeDebugLog("showTempMessage: " .. tostring(msg))
    tempMessage = msg or ""
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
    end
    tempMessageTimer = event.timer(duration or 2, function()
        tempMessage = ""
        tempMessageTimer = nil
        if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
            drawBuyStatic()
            drawBuyItemsList()
            drawBuyButtons()
        elseif currentScreen == "menu" then
            drawMainMenu()
        elseif currentScreen == "shop" then
            drawShopMenu()
        elseif currentScreen == "account" then
            drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
        elseif currentScreen == "feedbacks" then
            drawFeedbacksList()
        else
            drawTempMessage()
        end
    end)
    drawTempMessage()
end

-- ============================================================
-- ЗАГРУЗКА ТОВАРОВ (С КЕШИРОВАНИЕМ)
-- ============================================================

cachedBuyItems = nil
cacheTimestamp = 0
CACHE_TTL = 30

function loadBuyItems(forceRefresh)
    writeDebugLog("loadBuyItems()" .. (forceRefresh and " (принудительное обновление)" or ""))
    if not forceRefresh and cachedBuyItems and (os.clock() - cacheTimestamp) < CACHE_TTL then
        shopItems = cachedBuyItems
        writeDebugLog("loadBuyItems: использован кеш (" .. #shopItems .. " товаров)")
        return
    end
    
    if not component.isAvailable("me_interface") then 
        writeErrorLog("❌ ME интерфейс недоступен!")
        return 
    end
    local me = component.me_interface
    local rawItems = me.getItemsInNetwork()
    local tempShopItems = {}
    local knownKeys = {}
    for _, item in ipairs(shopItems) do
        local key = item.internalName .. ":" .. (item.damage or 0)
        knownKeys[key] = true
    end
    local newFound = {}

    for _, meItem in ipairs(rawItems) do
        local name = meItem.name
        if blacklist[name] then goto continue end
        local qty = meItem.size or 0
        if qty == 0 then goto continue end

        local damage = meItem.damage or 0
        local mapKey = name .. ":" .. damage
        local mapping = buyItemMap[mapKey]
        if not mapping then goto continue end

        local displayName = mapping.displayName
        local priceCoin = mapping.price_coin or mapping.price or 0
        local priceEma = mapping.price_ema or 0
        if priceCoin <= 0 and priceEma <= 0 then goto continue end

        local key = name .. ":" .. damage
        if tempShopItems[key] then
            tempShopItems[key].qty = tempShopItems[key].qty + qty
        else
            tempShopItems[key] = {
                internalName = name,
                displayName = displayName,
                qty = qty,
                priceCoin = priceCoin,
                priceEma = priceEma,
                damage = damage,
                canBuy = true
            }
        end
        ::continue::
    end

    local newShopItems = {}
    for key, itemData in pairs(tempShopItems) do
        table.insert(newShopItems, itemData)
        if not knownKeys[key] and itemData.qty > 0 then
            table.insert(newFound, {name = itemData.displayName, qty = itemData.qty})
        end
    end

    shopItems = newShopItems
    table.sort(shopItems, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)
    writeDebugLog("loadBuyItems: загружено " .. #shopItems .. " товаров")
    
    cachedBuyItems = shopItems
    cacheTimestamp = os.clock()
end

function loadSellItems()
    writeDebugLog("loadSellItems()")
    shopItems = {}
    for _, item in ipairs(sellItems) do
        local internal = item.internalName or item.name
        if internal then
            table.insert(shopItems, {
                displayName = item.displayName or item.name or internal,
                internalName = internal,
                qty = item.qty or 0,
                price = item.price or 0,
                damage = item.damage or 0
            })
        end
    end
    writeDebugLog("loadSellItems: загружено " .. #shopItems .. " товаров")
end

-- ============================================================
-- СКАН И ИЗЪЯТИЕ
-- ============================================================

function scanPlayerInventory(targetName, targetDamage)
    writeDebugLog("scanPlayerInventory: " .. tostring(targetName))
    local pimAddr = getPimAddr()
    if not pimAddr then 
        writeErrorLog("❌ PIM адрес не найден!")
        return 0 
    end
    targetDamage = targetDamage or 0
    local total = 0
    for slot = 1, 36 do
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    total = total + qty
                end
            end
        end
    end
    writeDebugLog("scanPlayerInventory: найдено " .. total)
    return total
end

function extractToME(targetName, amount, targetDamage)
    writeDebugLog("extractToME: " .. tostring(targetName) .. " x" .. tostring(amount))
    local pimAddr = getPimAddr()
    if not pimAddr or amount <= 0 then return 0 end
    targetDamage = targetDamage or 0
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then break end
        local stack = component.invoke(pimAddr, "getStackInSlot", slot)
        if stack then
            local qty = stack.size or stack.qty or 0
            if qty > 0 then
                local rawName = stack.name or stack.label or ""
                local cleanName = rawName:gsub("§.", "")
                local damage = stack.damage or 0
                if namesMatch(cleanName, targetName) and damage == targetDamage then
                    local toTake = math.min(qty, amount - extracted)
                    if toTake > 0 then
                        local moved = component.invoke(pimAddr, "pushItem", PUSH_DIRECTION, slot, toTake)
                        if type(moved) == "number" and moved > 0 then
                            extracted = extracted + moved
                        end
                    end
                end
            end
        end
    end
    writeDebugLog("extractToME: извлечено " .. extracted)
    return extracted
end

-- ============================================================
-- UI МАГАЗИНА (ПОЛНОСТЬЮ СОХРАНЁН)
-- ============================================================

function drawBalanceLine(x, y)
    writeDebugLog("drawBalanceLine: x=" .. tostring(x) .. ", y=" .. tostring(y))
    
    local coin = coinBalance or 0.0
    local ema = emaBalance or 0.0
    
    if coinBalance == nil then
        writeErrorLog("⚠️ coinBalance = nil в drawBalanceLine, установлен 0")
        coinBalance = 0.0
    end
    if emaBalance == nil then
        writeErrorLog("⚠️ emaBalance = nil в drawBalanceLine, установлен 0")
        emaBalance = 0.0
    end
    
    gpu.setForeground(colors.white)
    gpu.set(x, y, "Баланс: ")
    local coinStr = string.format("%.2f", coin) .. " Coina ₵"
    gpu.setForeground(colors.accent_main)
    gpu.set(x + unicode.len("Баланс: "), y, coinStr)
    gpu.setForeground(colors.white)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr), y, " | ")
    local emaStr = "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞"
    gpu.setForeground(colors.tomato)
    gpu.set(x + unicode.len("Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr)
end

function redrawSearchField()
    writeDebugLog("redrawSearchField()")
    local searchX = 42
    local searchText = ""
    if searchActive then
        searchText = (searchInput or "") .. "_"
    else
        searchText = (shopSearch == "" and "Поиск..." or (shopSearch or ""))
    end
    gpu.setBackground(colors.bg_button)
    gpu.fill(searchX, 3, 23, 1, " ")
    gpu.setForeground(colors.accent_main)
    gpu.set(searchX + 1, 3, unicode.sub(searchText, 1, 21))

    local clearText = "[ СТЕРЕТЬ ]"
    local clearWidth = unicode.len(clearText) + 2
    local clearX = searchX + 23 + 1
    gpu.setBackground(colors.error)
    gpu.fill(clearX, 3, clearWidth, 1, " ")
    gpu.setForeground(colors.accent_secondary)
    local textX = clearX + math.floor((clearWidth - unicode.len(clearText)) / 2)
    gpu.set(textX, 3, clearText)
    gpu.setBackground(colors.accent_secondary)
end

function drawBuyStatic()
    writeDebugLog("drawBuyStatic()")
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if currentShopMode == "buy" then
        gpu.setForeground(colors.accent_secondary)
        gpu.set(3, 3, "Магазин продаёт")
    else
        gpu.setForeground(colors.accent_secondary)
        gpu.set(3, 3, "Магазин покупает")
    end

    redrawSearchField()

    gpu.setBackground(colors.bg_button)
    gpu.fill(2, 5, 76, 1, " ")
    gpu.setForeground(colors.text_bright)
    gpu.set(3, 5, "Название")
    gpu.set(42, 5, "Кол-во")
    if currentShopMode == "buy" then
        gpu.set(55, 5, "Coina")
        gpu.set(67, 5, "ЭМЫ")
    else
        gpu.set(65, 5, "Цена")
    end
    gpu.setBackground(colors.bg_main)

    drawTempMessage()
end

function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    writeDebugLog("drawSingleRow: y=" .. tostring(y) .. ", itemIndex=" .. tostring(itemIndex))
    
    if not item then
        writeErrorLog("❌ item = nil в drawSingleRow!")
        return
    end
    
    if not item.displayName then
        writeErrorLog("⚠️ item.displayName = nil, устанавливаем 'Неизвестно'")
        item.displayName = "Неизвестно"
    end
    if not item.internalName then
        writeErrorLog("⚠️ item.internalName = nil, устанавливаем 'unknown'")
        item.internalName = "unknown"
    end
    if item.qty == nil then
        writeErrorLog("⚠️ item.qty = nil, устанавливаем 0")
        item.qty = 0
    end
    if item.price == nil then
        item.price = 0
    end
    if item.priceCoin == nil then
        item.priceCoin = 0
    end
    if item.priceEma == nil then
        item.priceEma = 0
    end
    
    local bg, fg
    if currentShopMode == "buy" and item.qty == 0 then
        bg = colors.bg_secondary
        fg = colors.inactive
    elseif isSelected then
        bg = 0x225577
    elseif isHovered then
        bg = 0x446688
    elseif itemIndex and itemIndex % 2 == 1 then
        bg = colors.bg_secondary
    else
        bg = 0x1a1a1a
    end
    
    if currentShopMode == "buy" then
        if item.qty > 0 then
            fg = colors.accent_main
        else
            fg = colors.inactive
        end
    else
        fg = colors.accent_main
    end
    
    gpu.setBackground(bg)
    gpu.fill(2, y, 76, 1, " ")
    gpu.setForeground(fg)
    
    local name = item.displayName or "Неизвестно"
    if unicode.len(name) > 37 then
        name = unicode.sub(name, (horizontalScroll or 1), (horizontalScroll or 1) + 36)
    end
    gpu.set(3, y, name)
    
    if currentShopMode == "buy" then
        if item.qty > 0 then
            gpu.setForeground(colors.text_bright)
        else
            gpu.setForeground(colors.inactive)
        end
    else
        gpu.setForeground(colors.text_bright)
    end
    gpu.set(42, y, tostring(item.qty or 0))

    if currentShopMode == "sell" then
        if item.internalName == "customnpcs:npcMoney" then
            gpu.setForeground(colors.tomato)
            local priceStr = string.format("%.2f", item.price or 0) .. " ۞"
            gpu.set(65, y, priceStr)
        else
            gpu.setForeground(colors.text_bright)
            local priceStr = string.format("%.2f", item.price or 0) .. " ₵"
            gpu.set(65, y, priceStr)
        end
    else
        if item.priceCoin and item.priceCoin > 0 then
            gpu.setForeground(colors.accent_main)
            local coinStr = string.format("%.2f", item.priceCoin)
            gpu.set(55, y, coinStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(55, y, "0")
        end
        if item.priceEma and item.priceEma > 0 then
            gpu.setForeground(colors.tomato)
            local emaStr = string.format("%.2f", item.priceEma)
            gpu.set(67, y, emaStr)
        else
            gpu.setForeground(colors.inactive)
            gpu.set(67, y, "0")
        end
    end
    gpu.setBackground(colors.bg_main)
end

function drawScrollBar()
    local total = #filteredItems
    local barX = 78
    local barY = 7
    local barHeight = 15
    gpu.setBackground(colors.bg_main)
    gpu.fill(barX, barY, 2, barHeight, " ")
    if total <= visibleRows then return end
    gpu.setBackground(colors.bg_secondary)
    gpu.fill(barX, barY, 2, barHeight, " ")
    local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
    thumbPos = math.min(thumbPos, maxPos + 1)
    gpu.setBackground(colors.accent_main)
    gpu.fill(barX, barY + thumbPos - 1, 2, thumbHeight, " ")
    gpu.setBackground(colors.bg_main)
end

function getFilteredItems()
    writeDebugLog("getFilteredItems()")
    local filtered = {}
    local searchLower = toLowerCase(shopSearch or "")
    local searchWords = {}
    if searchLower ~= "" then
        for word in searchLower:gmatch("%S+") do
            table.insert(searchWords, word)
        end
    end

    for _, item in ipairs(shopItems) do
        if not item then goto continue end
        local nameLower = toLowerCase(item.displayName or item.internalName or "")
        local matchesSearch = false
        if #searchWords == 0 then
            matchesSearch = true
        else
            for _, word in ipairs(searchWords) do
                if string.find(nameLower, word, 1, true) then
                    matchesSearch = true
                    break
                end
            end
        end
        if matchesSearch then
            table.insert(filtered, item)
        end
        ::continue::
    end

    table.sort(filtered, function(a, b)
        return sortableName(a.displayName) < sortableName(b.displayName)
    end)

    maxItemWidth = 0
    for _, item in ipairs(filtered) do
        local len = unicode.len(item.displayName or item.internalName or "")
        if len > maxItemWidth then maxItemWidth = len end
    end
    writeDebugLog("getFilteredItems: найдено " .. #filtered .. " товаров")
    return filtered
end

function drawBuyItemsList()
    writeDebugLog("drawBuyItemsList()")
    filteredItems = getFilteredItems()
    local maxScroll = math.max(1, #filteredItems - visibleRows + 1)
    listScroll = math.max(1, math.min(listScroll or 1, maxScroll))

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 7, 78, visibleRows, " ")

    if #filteredItems == 0 then
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        local msgX = math.floor((80 - unicode.len(msg)) / 2) + 1
        local msgY = 14
        gpu.setForeground(colors.error)
        gpu.set(msgX, msgY, msg)
    else
        for i = 1, visibleRows do
            local itemIndex = listScroll + i - 1
            local item = filteredItems[itemIndex]
            if not item then break end
            local y = 6 + i
            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            drawSingleRow(y, item, isHovered, isSelected, itemIndex)
        end
    end

    drawScrollBar()
    if selectedItem then
        updateSelectorDisplay(selectedItem)
    end
end

function smoothScroll(steps)
    writeDebugLog("smoothScroll: " .. tostring(steps))
    local filtered = filteredItems
    local total = #filtered
    local maxScroll = math.max(1, total - visibleRows + 1)
    local newScroll = (listScroll or 1) + steps
    newScroll = math.max(1, math.min(newScroll, maxScroll))
    if newScroll == listScroll then return end
    if math.abs(steps) == 1 and total > visibleRows then
        if steps > 0 then
            gpu.copy(2, 8, 76, visibleRows - 1, 0, -1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 21, 76, 1, " ")
            local newIdx = newScroll + visibleRows - 1
            if newIdx <= total then
                drawSingleRow(21, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        else
            gpu.copy(2, 7, 76, visibleRows - 1, 0, 1)
            gpu.setBackground(colors.bg_main)
            gpu.fill(2, 7, 76, 1, " ")
            local newIdx = newScroll
            if newIdx >= 1 then
                drawSingleRow(7, filtered[newIdx], (newIdx == hoveredIndex), (newIdx == selectedIndex), newIdx)
            end
        end
    else
        drawBuyItemsList()
        return
    end
    listScroll = newScroll
    drawScrollBar()
end

function drawBuyButtons()
    writeDebugLog("drawBuyButtons()")
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    local nextButton = {}
    if currentShopMode == "buy" then
        nextButton.text = "[ КУПИТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    else
        nextButton.text = "[ ПРОДАТЬ ]"
        nextButton.xs = unicode.len(nextButton.text) + 2
    end
    nextButton.x = 59
    nextButton.y = 24
    nextButton.ys = 1
    nextButton.bg = colors.bg_button
    nextButton.fg = colors.inactive

    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextButton.fg = colors.accent_secondary
    else
        nextButton.fg = colors.inactive
    end

    drawFlexButton(backButton)
    drawFlexButton(nextButton)
    drawTempMessage()
end

-- ============================================================
-- ЭКРАНЫ
-- ============================================================

menuButtons = {
    shop    = {x=32, xs=20, y=9,  ys=3, text="🛒 Магазин",     tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    account = {x=32, xs=20, y=17, ys=3, text="👤 Аккаунт",      tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main}
}

shopMenuButtons = {
    buy    = {x=32, xs=20, y=9,  ys=3, text="🛍 Покупка",     tx=6, ty=1, bg=colors.bg_button, fg=colors.accent_main},
    sell   = {x=32, xs=20, y=17, ys=3, text="💰 Пополнение",  tx=5, ty=1, bg=colors.bg_button, fg=colors.accent_main},
}

function drawWelcomeScreen()
    writeDebugLog("drawWelcomeScreen()")
    
    -- Очистка экрана
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
    
    -- ====================== НОВАЯ РАМКА ======================
    local border_color = 0x4477BB      -- Голубая рамка
    local text_color = 0x00FFCC        -- Бирюзовый текст
    local sub_color = 0xFFFF00         -- Жёлтый подзаголовок
    local hint_color = 0xAAAAAA        -- Серый подсказка
    
    -- Рамка
    gpu.setForeground(border_color)
    gpu.set(1, 1, "┌" .. string.rep("─", 78) .. "┐")
    gpu.set(1, 24, "└" .. string.rep("─", 78) .. "┘")
    for y = 2, 23 do
        gpu.set(1, y, "│")
        gpu.set(80, y, "│")
    end
    
    -- ====================== АЛМАЗ ======================
    local diamond = {
        "             ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓            ",
        "           ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓          ",
        "        ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓        ",
        "      ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▓      ",
        "     ▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▓▓▓▒▒     ",
        "     ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▒▒▒▒▒▒▓▓      ",
        "       ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓       ",
        "        ▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▒▓▓▓▓         ",
        "          ▓▒▒▒▒▒▒▒▒▓▓▓▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓          ",
        "            ▓▒▒▒▒▒▓▓▓▓▓▒▒▓▓▓▓▓▓▓▓▓▓▓            ",
        "             ▓▒▒▒▒▒▓▓▓▓▒▒▓▓▓▓▓▒▓▓▓▓             ",
        "               ▓▒▒▒▒▓▓▓▒▒▓▓▓▓▓▓▓▓               ",
        "                 ▓▒▒▒▓▓▒▒▓▓▓▓▓▓▓                ",
        "                  ▓▒▒▒▓▓▒▓▓▓▓▓                  ",
        "                    ▓▒▒▒▒▓▒▓▓                   ",
        "                      ▓▒▒▒▓▓                    ",
        "                        ▒▓                      ",
    }
    
    -- Градиент для алмаза
    local gradient = {
        0x112244, 0x223366, 0x335599, 0x4477BB,
        0x5599DD, 0x77BBFF, 0x99CCFF, 0xBBDDFF
    }
    
    local diamX = 17
    local diamY = 3
    
    for i, line in ipairs(diamond) do
        local color = gradient[math.min(math.floor((i-1) / 2) + 1, #gradient)]
        gpu.setForeground(color)
        gpu.set(diamX, diamY + i - 1, line)
    end
    
    -- ====================== ТЕКСТ ======================
    local cx = 41
    
    -- Основной текст
    gpu.setForeground(text_color)
    gpu.set(cx - 2, 21, "VIP SHOP")
    
    -- Подзаголовок
    gpu.setForeground(sub_color)
    gpu.set(cx - 6, 22, "◆ McSkill HiTech ◆")
    
    -- Подсказка
    gpu.setForeground(hint_color)
    gpu.set(cx - 10, 23, "Встаньте на ПИМ для входа")
    
    -- ====================== СОСТОЯНИЕ МАГАЗИНА ======================
    if shopPaused then
        gpu.setForeground(colors.error)
        drawCenteredText(18, "РЕЖИМ ОБСЛУЖИВАНИЯ", colors.error)
        drawCenteredText(19, "Магазин временно закрыт", colors.error)
        drawCenteredText(20, "Пожалуйста, зайдите позже", colors.text_main)
    else
        gpu.setForeground(colors.success)
        drawCenteredText(18, "↓   Встаньте на PIM   ↓", colors.accent_main)
        drawCenteredText(19, "━━━━━━━━━━━━━━━━━━━", colors.accent_main)
    end
    
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

function drawAuthScreen()
    writeDebugLog("drawAuthScreen()")
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
    
    -- Рамка
    gpu.setForeground(0x4477BB)
    gpu.set(1, 1, "┌" .. string.rep("─", 78) .. "┐")
    gpu.set(1, 24, "└" .. string.rep("─", 78) .. "┘")
    for y = 2, 23 do
        gpu.set(1, y, "│")
        gpu.set(80, y, "│")
    end
    
    -- ====================== АЛМАЗ ======================
    local diamond = {
        "             ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓            ",
        "           ▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▓          ",
        "        ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓        ",
        "      ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▒▒▒▒▒▒▒▒▒▓      ",
        "     ▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▒▒▒▒▒▒▓▓▓▓▒▒▒▒▓▓▓▒▒     ",
        "     ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓▒▒▒▒▒▒▓▓      ",
        "       ▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▓       ",
        "        ▓▓▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▓▓▓▓▓▒▓▓▓▓         ",
        "          ▓▒▒▒▒▒▒▒▒▓▓▓▒▒▒▒▒▓▓▓▓▓▓▓▓▓▓▓          ",
        "            ▓▒▒▒▒▒▓▓▓▓▓▒▒▓▓▓▓▓▓▓▓▓▓▓            ",
        "             ▓▒▒▒▒▒▓▓▓▓▒▒▓▓▓▓▓▒▓▓▓▓             ",
        "               ▓▒▒▒▒▓▓▓▒▒▓▓▓▓▓▓▓▓               ",
        "                 ▓▒▒▒▓▓▒▒▓▓▓▓▓▓▓                ",
        "                  ▓▒▒▒▓▓▒▓▓▓▓▓                  ",
        "                    ▓▒▒▒▒▓▒▓▓                   ",
        "                      ▓▒▒▒▓▓                    ",
        "                        ▒▓                      ",
    }
    
    local gradient = {
        0x112244, 0x223366, 0x335599, 0x4477BB,
        0x5599DD, 0x77BBFF, 0x99CCFF, 0xBBDDFF
    }
    
    local diamX = 17
    local diamY = 2
    
    for i, line in ipairs(diamond) do
        local color = gradient[math.min(math.floor((i-1) / 2) + 1, #gradient)]
        gpu.setForeground(color)
        gpu.set(diamX, diamY + i - 1, line)
    end
    
    -- Текст
    local cx = 41
    gpu.setForeground(0x00FFCC)
    gpu.set(cx - 2, 20, "VIP SHOP")
    gpu.setForeground(0xFFFF00)
    gpu.set(cx - 6, 21, "◆ McSkill HiTech ◆")
    
    if shopPaused then
        gpu.setForeground(colors.error)
        drawCenteredText(17, "РЕЖИМ ОБСЛУЖИВАНИЯ", colors.error)
        drawCenteredText(18, "Магазин временно закрыт", colors.error)
        drawCenteredText(19, "Пожалуйста, зайдите позже", colors.text_main)
    else
        gpu.setForeground(colors.text_bright)
        drawCenteredText(17, "АВТОРИЗАЦИЯ", 0x00FFCC)
        gpu.setForeground(colors.text_main)
        drawCenteredText(18, "Пожалуйста, подождите...", colors.text_main)
    end
    
    gpu.setBackground(colors.bg_main)
    drawTempMessage()
end

function drawMainMenu()
    writeDebugLog("drawMainMenu()")
    clear()
    drawScreenBorder()
    if currentPlayer then
        local hello1 = "Добро пожаловать, "
        local hello2 = currentPlayer .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((80 - unicode.len(full1))/2) + 2
        gpu.setForeground(colors.success)
        gpu.set(x1, 4, hello1)
        gpu.setForeground(colors.text_bright)
        gpu.set(x1 + unicode.len(hello1), 4, hello2)

        local coin = coinBalance or 0.0
        local ema = emaBalance or 0.0
        
        gpu.setForeground(colors.white)
        local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
        local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
        gpu.set(balanceX, 5, "Баланс: ")
        gpu.setForeground(colors.accent_main)
        gpu.set(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", coin) .. " Coina ₵")
        gpu.setForeground(colors.white)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 5, " | ")
        gpu.setForeground(colors.tomato)
        gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")

        if not playerAgreed then
            gpu.setForeground(colors.accent_secondary)
            if showShopDenied then
                drawCenteredText(7, "Доступ запрещён. Примите соглашение [Соглашение]", colors.error)
            else
                drawCenteredText(7, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", colors.accent_secondary)
            end
        end

        for _, btn in pairs(menuButtons) do
            drawButton(btn)
        end
        
        gpu.setForeground(colors.error)
        gpu.set(4, 24, "[ ПОДДЕРЖКА ]")
        gpu.set(35, 24, "[ СОГЛАШЕНИЕ ]")
        gpu.set(68, 24, "[ ОТЗЫВЫ ]")
    else
        drawWelcomeScreen()
    end
    drawTempMessage()
end

function drawShopMenu()
    writeDebugLog("drawShopMenu()")
    clear()
    drawScreenBorder()
    drawCenteredText(6, "МАГАЗИН", colors.accent_secondary)
    if not playerAgreed then
        drawCenteredText(9, "Доступ запрещён.", colors.error)
        drawCenteredText(10, "Примите соглашение, нажав [Соглашение] в главном меню.", colors.accent_main)
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.accent_secondary
        }
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end
    for _, btn in pairs(shopMenuButtons) do
        drawButton(btn)
    end
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(backButton)
    drawTempMessage()
end

function drawAccount(data)
    writeDebugLog("drawAccount()")
    clear()
    drawScreenBorder()
    drawCenteredText(10, (currentPlayer or "Игрок") .. ":", colors.text_bright)
    
    local coin = (data and data.balance) or coinBalance or 0.0
    local ema = (data and data.emaBalance) or emaBalance or 0.0
    local agreed = (data and data.agreed) or playerAgreed or false
    
    gpu.setForeground(colors.white)
    local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
    local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
    gpu.set(balanceX, 12, "Баланс: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(balanceX + unicode.len("Баланс: "), 12, string.format("%.2f", coin) .. " Coina ₵")
    gpu.setForeground(colors.white)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 12, " | ")
    gpu.setForeground(colors.tomato)
    gpu.set(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 12, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")

    local transLabel = "Совершенно транзакций: "
    local transCount = tostring((data and data.transactions) or playerTransactions or 0)
    local fullTrans = transLabel .. transCount
    local transX = math.floor((80 - unicode.len(fullTrans)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(transX, 13, transLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(transX + unicode.len(transLabel), 13, transCount)

    local regLabel = "Регистрация: "
    local regDate = (data and data.regDate) or playerRegDate or "Неизвестно"
    local fullReg = regLabel .. regDate
    local regX = math.floor((80 - unicode.len(fullReg)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(regX, 14, regLabel)
    gpu.setForeground(colors.text_bright)
    gpu.set(regX + unicode.len(regLabel), 14, regDate)

    local agreeLabel = "Соглашение: "
    local agreeStatus = agreed and "ознакомлен" or "не ознакомлен"
    local agreeColor = agreed and colors.text_bright or colors.error
    local fullAgree = agreeLabel .. agreeStatus
    local agreeX = math.floor((80 - unicode.len(fullAgree)) / 2) + 1
    gpu.setForeground(colors.success)
    gpu.set(agreeX, 15, agreeLabel)
    gpu.setForeground(agreeColor)
    gpu.set(agreeX + unicode.len(agreeLabel), 15, agreeStatus)

    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(backButton)
    drawTempMessage()
end

function drawReportScreen()
    writeDebugLog("drawReportScreen()")
    currentScreen = "report"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "РЕПОРТ", colors.accent_secondary)
    gpu.setForeground(colors.text_main)
    local help1 = "Опишите проблему: баг, предложение, жалоба."
    local helpX = math.floor((80 - unicode.len(help1)) / 2) + 1
    gpu.set(helpX, 7, help1)

    if not canSendReport() then
        drawCenteredText(9, "Вы уже отправляли репорт сегодня.", colors.error)
        drawCenteredText(10, "Лимит: 1 сообщение в сутки (сброс в 00:00 МСК).", colors.error)
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.accent_secondary
        }
        drawFlexButton(backButton)
        drawTempMessage()
        return
    end

    gpu.setBackground(colors.black_fon)
    gpu.fill(10, 9, 60, 3, " ")
    gpu.setForeground(colors.text_bright)
    if reportInput and reportInput ~= "" then
        gpu.set(11, 10, unicode.sub(reportInput, -58))
    else
        gpu.setForeground(colors.inactive)
        gpu.set(11, 10, "Введите текст сообщения...")
    end
    gpu.setBackground(colors.bg_main)

    local sendBtn = {x=33, y=14, xs=17, ys=1, text="[ ОТПРАВИТЬ ]", bg=colors.bg_button, fg=colors.success}
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(sendBtn)
    drawFlexButton(backButton)
    gpu.setForeground(colors.text_main)
    drawCenteredText(16, "Ограничение: 1 репорт в сутки (сброс в 00:00 МСК)", colors.text_main)
    drawTempMessage()
end

-- ============================================================
-- ПОП-АПЫ
-- ============================================================

function drawSellPopup()
    writeDebugLog("drawSellPopup()")
    if not sellConfirmItem then
        writeErrorLog("❌ drawSellPopup: sellConfirmItem = nil!")
        return
    end
    
    local popupWidth = 40
    local popupHeight = 10
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 10

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY+2, popupWidth, popupHeight-4, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")

    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.accent_secondary)

    local name = sellConfirmItem.displayName or "Неизвестно"
    local totalFound = foundAmount or 0
    local value = totalFound * (sellConfirmItem.price or 0)

    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+14, popupY, "Подтверждение")

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+3, "Магазин заберёт: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len("Магазин заберёт: "), popupY+3, tostring(totalFound))

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+4, name .. " x")
    gpu.setForeground(colors.text_bright)
    gpu.set(popupX+3 + unicode.len(name .. " x"), popupY+4, tostring(totalFound))

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Вы получите: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ۞")
    else
        gpu.setForeground(colors.accent_main)
        gpu.set(popupX+3 + unicode.len("Вы получите: "), popupY+5, string.format("%.2f", value) .. " ₵")
    end

    local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1, text="[ Принять ]", bg=colors.bg_button, fg=colors.success}
    local noBtn  = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1, text="[ Отмена ]", bg=colors.bg_button, fg=colors.error}
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    drawTempMessage()
end

function drawSellScanScreen()
    writeDebugLog("drawSellScanScreen()")
    if not sellConfirmItem then
        writeErrorLog("❌ drawSellScanScreen: sellConfirmItem = nil!")
        return
    end
    
    currentScreen = "sell_scan"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    gpu.setForeground(colors.success)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 3, sellConfirmItem.displayName or "Неизвестно")

    gpu.setForeground(colors.success)
    gpu.set(55, 3, "Цена: ")
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        gpu.setForeground(colors.tomato)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price or 0) .. " ۞")
    else
        gpu.setForeground(colors.accent_main)
        gpu.set(62, 3, string.format("%.2f", sellConfirmItem.price or 0) .. " ₵")
    end

    gpu.setForeground(colors.success)
    gpu.set(3, 5, "Можно продать: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 5, tostring(sellConfirmItem.qty or 0))

    gpu.setForeground(colors.accent_secondary)
    local scanText = "Сканировать на наличие предмета:"
    local scanX = math.floor((80 - unicode.len(scanText)) / 2)
    gpu.set(scanX, 11, scanText)

    local allBtn  = {x=30, y=13, xs=20, ys=1, text="Весь инвентарь", bg=colors.bg_button, fg=colors.success}
    drawFlexButton(allBtn)
    
    local backButton = {
        text = "[ НАЗАД ]",
        x = 37, y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(backButton)

    if showSellPopup and sellConfirmItem then
        drawSellPopup()
    end
    drawTempMessage()
end

function drawPurchaseScreen()
    writeDebugLog("drawPurchaseScreen()")
    currentScreen = "purchase"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if not purchaseItem then
        writeErrorLog("❌ drawPurchaseScreen: purchaseItem = nil!")
        drawCenteredText(10, "Ошибка: предмет не выбран", colors.error)
        local backBtn = {x = 37, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
        drawFlexButton(backBtn)
        drawTempMessage()
        return
    end

    gpu.setForeground(colors.success)
    gpu.set(3, 3, "Имя предмета: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(18, 3, purchaseItem.displayName or "Неизвестно")

    gpu.setForeground(colors.success)
    gpu.set(55, 3, "Доступно: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(66, 3, tostring(purchaseItem.qty or 0))

    local qty = purchaseQuantity or 1
    local totalCoin = (purchaseItem.priceCoin or 0) * qty
    local totalEma = (purchaseItem.priceEma or 0) * qty

    gpu.setForeground(colors.success)
    gpu.set(3, 5, "На сумму: ")
    local sumY = 5
    if totalCoin > 0 then
        gpu.setForeground(colors.error)
        gpu.set(14, sumY, string.format("%.2f", totalCoin) .. " ₵")
        sumY = sumY + 1
    end
    if totalEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(14, sumY, string.format("%.2f", totalEma) .. " ۞")
    end

    gpu.setForeground(colors.success)
    gpu.set(55, 5, "Цена: ")
    local priceY = 5
    if purchaseItem.priceCoin and purchaseItem.priceCoin > 0 then
        gpu.setForeground(colors.accent_main)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceCoin) .. " ₵")
        priceY = priceY + 1
    end
    if purchaseItem.priceEma and purchaseItem.priceEma > 0 then
        gpu.setForeground(colors.tomato)
        gpu.set(62, priceY, string.format("%.2f", purchaseItem.priceEma) .. " ۞")
    end

    gpu.setForeground(colors.success)
    gpu.set(3, 7, "Кол-во: ")
    gpu.setForeground(colors.text_bright)
    gpu.set(12, 7, tostring(qty))

    local keys = {
        {"1","2","3"},
        {"4","5","6"},
        {"7","8","9"},
        {"<","0","C"}
    }
    local startX = 34
    local startY = 11
    local btnW = 3
    local btnH = 1
    local spacing = 2
    for row = 1, 4 do
        for col = 1, 3 do
            local x = startX + (col-1)*(btnW + spacing)
            local y = startY + (row-1)*(btnH + 1)
            local text = keys[row][col]
            gpu.setBackground(colors.bg_button)
            gpu.fill(x, y, btnW, btnH, " ")
            gpu.setForeground(colors.accent_main)
            local tx = x + math.floor((btnW - unicode.len(text)) / 2)
            local ty = y
            gpu.set(tx, ty, text)
        end
    end
    local backBtn = {x = 19, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local buyBtn  = {x = 51, y = 24, xs = unicode.len("[ КУПИТЬ ]") + 2, ys = 1, text = "[ КУПИТЬ ]", bg = colors.bg_button, fg = colors.success}
    drawFlexButton(backBtn)
    drawFlexButton(buyBtn)
    drawTempMessage()
end

function drawFeedbacksList()
    writeDebugLog("drawFeedbacksList()")
    local feedbacks = {}
    if fs.exists(FEEDBACKS_PATH) then
        local file = io.open(FEEDBACKS_PATH, "r")
        if file then
            local data = file:read("*a")
            file:close()
            if data and #data > 0 then
                local ok, result = pcall(serialization.unserialize, data)
                if ok and type(result) == "table" then feedbacks = result end
            end
        end
    end
    
    clear()
    drawScreenBorder()

    local line = string.rep("═", 15)
    local title = " ОТЗЫВЫ "
    local line2 = string.rep("═", 15)
    local fullStr = line .. title .. line2
    local x = math.floor((80 - unicode.len(fullStr)) / 2) + 1
    gpu.setForeground(colors.accent_main)
    gpu.set(x, 2, line)
    gpu.setForeground(colors.text_bright)
    gpu.set(x + unicode.len(line), 2, title)
    gpu.setForeground(colors.accent_main)
    gpu.set(x + unicode.len(line) + unicode.len(title), 2, line2)

    if #feedbacks == 0 then
        drawCenteredText(10, "Пока нет ни одного отзыва.", colors.text_main)
        drawCenteredText(11, "Будьте первым, кто оставит отзыв!", colors.accent_main)
        if not playerHasFeedback then
            drawCenteredText(12, "Нажмите [ДОБАВИТЬ] чтобы оставить отзыв", colors.text_main)
        end
    else
        local startIdx = (feedbacksPage - 1) * 3 + 1
        local endIdx = math.min(startIdx + 2, #feedbacks)
        local y = 5

        for i = startIdx, endIdx do
            local fb = feedbacks[i]
            if fb then
                gpu.setForeground(colors.accent_secondary)
                gpu.fill(5, y, 70, 3, " ")
                gpu.setBackground(colors.bg_secondary)
                gpu.fill(6, y+1, 68, 1, " ")

                gpu.setForeground(colors.accent_main)
                gpu.set(7, y+1, fb.name or "Аноним")
                gpu.setForeground(colors.inactive)
                local timeStr = fb.time or ""
                gpu.set(7 + unicode.len(fb.name or "Аноним") + 2, y+1, timeStr)

                gpu.setForeground(colors.text_bright)
                local shortText = unicode.sub(fb.text or "", 1, 62)
                gpu.set(7, y+2, shortText)

                y = y + 4
            end
        end

        local feedbacksTotalPages = math.max(1, math.ceil(#feedbacks / 3))
        local pageInfo = "Страница " .. feedbacksPage .. " из " .. feedbacksTotalPages
        local x = math.floor((80 - unicode.len(pageInfo)) / 2) + 1
        gpu.setForeground(colors.text_main)
        gpu.set(x, 22, pageInfo)
    end

    local backBtn = {x = 5, y = 24, xs = 11, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
    local addBtn = {x = 36, y = 24, xs = 14, ys = 1, text = "[ ДОБАВИТЬ ]", bg = colors.bg_button, fg = colors.success}
    local prevBtn = {x = 59, y = 24, xs = 7, ys = 1, text = "[ < ]", bg = colors.bg_button, fg = colors.accent_main}
    local nextBtn = {x = 69, y = 24, xs = 7, ys = 1, text = "[ > ]", bg = colors.bg_button, fg = colors.accent_main}

    if not playerHasFeedback then
        drawFlexButton(addBtn)
    end
    drawFlexButton(backBtn)
    if #feedbacks > 3 then
        drawFlexButton(prevBtn)
        drawFlexButton(nextBtn)
    end

    drawTempMessage()
end

function drawFeedbackInputScreen()
    writeDebugLog("drawFeedbackInputScreen()")
    if playerHasFeedback then
        showTempMessage("Вы уже оставляли отзыв!", 2)
        goBackToMenu()
        return
    end
    currentScreen = "feedback_input"
    clear()
    drawScreenBorder()
    drawCenteredText(4, "ОСТАВИТЬ ОТЗЫВ", colors.accent_secondary)

    gpu.setForeground(colors.text_main)
    drawCenteredText(7, "Ваше имя: " .. (currentPlayer or "Игрок"), colors.accent_main)
    drawCenteredText(9, "Оставьте свой отзыв о магазине:", colors.text_main)
    drawCenteredText(10, "Ваше мнение поможет нам стать лучше!", colors.inactive)

    gpu.setBackground(colors.black_fon)
    gpu.fill(10, 12, 60, 3, " ")
    gpu.setForeground(colors.text_bright)
    if feedbackEditMode then
        if feedbackInput and feedbackInput ~= "" then
            gpu.set(11, 13, unicode.sub(feedbackInput, -58) .. "_")
        else
            gpu.setForeground(colors.inactive)
            gpu.set(11, 13, "Введите ваш отзыв..._")
        end
    else
        if feedbackInput and feedbackInput ~= "" then
            gpu.set(11, 13, unicode.sub(feedbackInput, -58))
        else
            gpu.setForeground(colors.inactive)
            gpu.set(11, 13, "Введите ваш отзыв...")
        end
    end

    local cancelBtn = {x = 20, y = 24, xs = 12, ys = 1, text = "[ ОТМЕНА ]", bg = colors.bg_button, fg = colors.error}
    local sendBtn = {x = 46, y = 24, xs = 15, ys = 1, text = "[ ОТПРАВИТЬ ]", bg = colors.bg_button, fg = colors.success}

    drawFlexButton(cancelBtn)
    drawFlexButton(sendBtn)
    drawTempMessage()
end

function drawInsufficientPopup()
    writeDebugLog("drawInsufficientPopup()")
    local popupWidth = 52
    local popupHeight = 11
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 7

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "НЕДОСТАТОЧНО СРЕДСТВ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local line1a = "Пополни баланс, не можешь купить"
    local line1aX = popupX + math.floor((popupWidth - unicode.len(line1a)) / 2)
    gpu.set(line1aX, popupY+2, line1a)

    local line1b = "хотя бы 1 штуку предмета."
    local line1bX = popupX + math.floor((popupWidth - unicode.len(line1b)) / 2)
    gpu.set(line1bX, popupY+3, line1b)

    gpu.setForeground(colors.success)
    gpu.set(popupX+3, popupY+5, "Твой баланс Coin: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(popupX+3 + unicode.len("Твой баланс Coin: "), popupY+5, string.format("%.2f", insufficientBalanceCoin or 0) .. " ₵")
    if insufficientBalanceEma and insufficientBalanceEma > 0 then
        gpu.setForeground(colors.success)
        gpu.set(popupX+3, popupY+6, "Твой баланс ЭМЫ: ")
        gpu.setForeground(colors.tomato)
        gpu.set(popupX+3 + unicode.len("Твой баланс ЭМЫ: "), popupY+6, string.format("%.2f", insufficientBalanceEma) .. " ۞")
    end

    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+8,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

function drawPartialPopup()
    writeDebugLog("drawPartialPopup()")
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "НЕ ПОЛНАЯ ВЫДАЧА"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local line1 = "Не хватило места в инвентаре!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)

    local line2 = "Выдано " .. (partialExtracted or 0) .. " из " .. (partialRequested or 0)
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)

    local spentLabelCoin = "Списано Coin: "
    local spentValueCoin = string.format("%.2f", partialRefundCoin or 0) .. " ₵"
    local fullSpentTextCoin = spentLabelCoin .. spentValueCoin
    local spentStartXCoin = popupX + math.floor((popupWidth - unicode.len(fullSpentTextCoin)) / 2)
    gpu.setForeground(colors.success)
    gpu.set(spentStartXCoin, popupY+4, spentLabelCoin)
    gpu.setForeground(colors.accent_main)
    gpu.set(spentStartXCoin + unicode.len(spentLabelCoin), popupY+4, spentValueCoin)

    if partialRefundEma and partialRefundEma > 0 then
        local spentLabelEma = "Списано ЭМЫ: "
        local spentValueEma = string.format("%.2f", partialRefundEma) .. " ۞"
        local fullSpentTextEma = spentLabelEma .. spentValueEma
        local spentStartXEma = popupX + math.floor((popupWidth - unicode.len(fullSpentTextEma)) / 2)
        gpu.setForeground(colors.success)
        gpu.set(spentStartXEma, popupY+5, spentLabelEma)
        gpu.setForeground(colors.tomato)
        gpu.set(spentStartXEma + unicode.len(spentLabelEma), popupY+5, spentValueEma)
    end

    local okBtnText = "[ ПРИНЯТЬ ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+6,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

function drawInventoryFullPopup()
    writeDebugLog("drawInventoryFullPopup()")
    local popupWidth = 52
    local popupHeight = 9
    local popupX = math.floor((80 - popupWidth) / 2)
    local popupY = 9

    gpu.setBackground(colors.black_fon)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    gpu.fill(popupX+1, popupY+1, popupWidth-2, popupHeight-2, " ")
    drawPopupBorder(popupX, popupY, popupWidth, popupHeight, colors.error)

    gpu.setForeground(colors.error)
    local title = "ПРЕДУПРЕЖДЕНИЕ"
    local titleX = popupX + math.floor((popupWidth - unicode.len(title)) / 2)
    gpu.set(titleX, popupY, title)

    gpu.setForeground(colors.text_main)
    local line1 = "Ваш инвентарь полон!"
    local line1X = popupX + math.floor((popupWidth - unicode.len(line1)) / 2)
    gpu.set(line1X, popupY+2, line1)

    local line2 = "Освободите его и повторите попытку."
    local line2X = popupX + math.floor((popupWidth - unicode.len(line2)) / 2)
    gpu.set(line2X, popupY+3, line2)

    local okBtnText = "[ ПОНЯТНО ]"
    local okBtnWidth = unicode.len(okBtnText) + 2
    local okBtn = {
        x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
        y = popupY+6,
        xs = okBtnWidth,
        ys = 1,
        text = okBtnText,
        bg = colors.bg_button,
        fg = colors.success
    }
    drawFlexButton(okBtn)
    drawTempMessage()
end

-- ============================================================
-- НАВИГАЦИЯ
-- ============================================================

function goBackToMenu()
    writeDebugLog("goBackToMenu()")
    showShopDenied = false
    currentScreen = "menu"
    drawMainMenu()
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
end

function goToShop()
    writeDebugLog("goToShop()")
    currentScreen = "shop"
    drawShopMenu()
end

function goToBuy()
    writeDebugLog("goToBuy()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
        return
    end
    currentScreen = "shop_buy"
    currentShopMode = "buy"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""
    loadBuyItems()
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

function goToSell()
    writeDebugLog("goToSell()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        os.sleep(3)
        drawMainMenu()
        return
    end

    currentScreen = "shop_sell"
    currentShopMode = "sell"
    listScroll = 1
    horizontalScroll = 1
    selectedIndex = 0
    hoveredIndex = 0
    selectedItem = nil
    shopSearch = ""
    searchActive = false
    searchInput = ""

    loadSellItems()
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

function goToSellConfirm(item)
    writeDebugLog("goToSellConfirm()")
    if not item then
        writeErrorLog("❌ goToSellConfirm: item = nil!")
        return
    end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    drawSellScanScreen()
end

function goToPurchase(item)
    writeDebugLog("goToPurchase()")
    if not item then
        writeErrorLog("❌ goToPurchase: item = nil!")
        return
    end
    purchaseItem = item
    purchaseQuantity = 1
    drawPurchaseScreen()
end

function goToReport()
    writeDebugLog("goToReport()")
    currentScreen = "report"
    reportInput = ""
    drawReportScreen()
end

function goToHelp()
    writeDebugLog("goToHelp()")
    currentScreen = "agreement"
    if type(drawAgreementScreen) == "function" then
        drawAgreementScreen()
    else
        drawCenteredText(10, "СОГЛАШЕНИЕ НЕ ЗАГРУЖЕНО", colors.error)
        drawCenteredText(12, "Файл agreement.lua отсутствует", colors.text_main)
        drawCenteredText(14, "Нажмите [НАЗАД] для возврата", colors.text_main)
        
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.accent_secondary
        }
        drawFlexButton(backButton)
        drawTempMessage()
        
        while currentScreen == "agreement" do
            local ev = {event.pull(0.5)}
            if ev[1] == "touch" then
                local x = tonumber(ev[3]) or 0
                local y = tonumber(ev[4]) or 0
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    break
                end
            end
        end
    end
end

function goToAccount()
    writeDebugLog("goToAccount()")
    if not currentToken then
        drawCenteredText(12, "Ошибка: нет авторизации", colors.error)
        return
    end
    currentScreen = "account_loading"
    drawAccountLoading()
    local player = players[currentPlayer]
    if player then
        currentScreen = "account"
        drawAccount({
            balance = player.balance or 0,
            emaBalance = player.emaBalance or 0,
            transactions = player.transactions or 0,
            regDate = playerRegDate or "Неизвестно",
            agreed = playerAgreed
        })
    end
end

function handleQuantityButtonClick(btnText)
    writeDebugLog("handleQuantityButtonClick: " .. tostring(btnText))
    if btnText == "C" then
        purchaseQuantity = 0
    elseif btnText == "<" then
        purchaseQuantity = math.floor((purchaseQuantity or 1) / 10)
    elseif tonumber(btnText) then
        local digit = tonumber(btnText)
        if purchaseQuantity == 0 then
            purchaseQuantity = digit
        else
            purchaseQuantity = (purchaseQuantity or 1) * 10 + digit
        end
        if purchaseItem and purchaseQuantity > (purchaseItem.qty or 0) then
            purchaseQuantity = purchaseItem.qty
        end
    end
    drawPurchaseScreen()
end

-- ============================================================
-- ВЫПОЛНЕНИЕ ПОКУПКИ И ПРОДАЖИ (С ДОБАВЛЕНИЕМ В БУФЕР)
-- ============================================================

function performSell()
    if not playerAgreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", colors.error)
        os.sleep(2)
        currentScreen = "menu"
        drawMainMenu()
        return
    end

    -- ★★★ ЗАЩИТА ОТ ДУБЛИРОВАНИЯ ★★★
    if sellConfirmItem and sellConfirmItem._processing then
        writeDebugLog("⚠️ Продажа уже выполняется, пропускаем")
        return
    end
    
    if sellConfirmItem and sellConfirmItem._processed then
        writeDebugLog("⚠️ Продажа уже обработана, пропускаем")
        return
    end

    showSellPopup = false
    drawSellScanScreen()
    drawCenteredText(17, "Выполняется пополнение...", colors.accent_main)
    os.sleep(0.2)

    -- ★ ПОМЕЧАЕМ, ЧТО ПРОДАЖА НАЧАЛАСЬ ★
    sellConfirmItem._processing = true

    local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount, sellConfirmItem.damage or 0)
    if realExtracted == 0 then
        sellConfirmItem._processing = false
        drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", colors.error)
        os.sleep(2)
        currentScreen = "shop_sell"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end

    local value = realExtracted * sellConfirmItem.price
    if sellConfirmItem.internalName == "customnpcs:npcMoney" then
        emaBalance = emaBalance + value
    else
        coinBalance = coinBalance + value
    end
    playerTransactions = playerTransactions + 1

    -- ★ ДОБАВЛЯЕМ ТРАНЗАКЦИЮ ★
    addTransaction("sell", currentPlayer, sellConfirmItem.displayName, realExtracted, value, 0)

    -- ★ ПОМЕЧАЕМ, ЧТО ПРОДАЖА ЗАВЕРШЕНА ★
    sellConfirmItem._processed = true
    sellConfirmItem._processing = false

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 17, 78, 1, " ")
    local currencySymbol = (sellConfirmItem.internalName == "customnpcs:npcMoney") and "۞" or "₵"
    drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencySymbol, colors.success)
    os.sleep(0.8)

    currentScreen = "shop_sell"
    showSellPopup = false
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

function performBuy()
    if not playerAgreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        os.sleep(2)
        currentScreen = "menu"
        drawMainMenu()
        return
    end

    if not purchaseItem then
        writeErrorLog("❌ performBuy: purchaseItem = nil!")
        return
    end

    local me = component.me_interface
    local item = purchaseItem

    local actualQty = getActualItemQuantity(item.internalName, item.damage)
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", colors.error)
        os.sleep(0.8)
        loadBuyItems(true)
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        currentScreen = "shop_buy"
        return
    end

    local qty = purchaseQuantity
    if qty > actualQty then
        qty = actualQty
        purchaseQuantity = qty
        drawPurchaseScreen()
    end

    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", colors.error)
        os.sleep(0.8)
        currentScreen = "shop_buy"
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
        return
    end

    local totalCoin = (item.priceCoin or 0) * qty
    local totalEma = (item.priceEma or 0) * qty
    if coinBalance < totalCoin or emaBalance < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = coinBalance
        insufficientBalanceEma = emaBalance
        drawPurchaseScreen()
        drawInsufficientPopup()
        return
    end

    drawCenteredText(20, "Выполняется покупка...", colors.accent_main)
    os.sleep(0.4)

    local id = item.internalName
    if not id:find(":") then
        id = "minecraft:" .. id
    end
    local fingerprint = { id = id, dmg = item.damage or 0 }

    local maxStackSize = 64
    local ok, detail = pcall(me.getItemDetail, me, item.internalName, item.damage)
    if ok and detail and detail.maxSize then
        maxStackSize = detail.maxSize
    end

    local remaining = qty
    local extracted = 0
    local lastError = nil

    while remaining > 0 do
        local toTake = math.min(remaining, maxStackSize)
        local success, result = pcall(function()
            return me.exportItem(fingerprint, PULL_DIRECTION, toTake)
        end)

        local got = 0
        if success then
            if type(result) == "number" then
                got = result
            elseif type(result) == "boolean" and result == true then
                got = toTake
            elseif type(result) == "table" then
                if result.count then
                    got = result.count
                elseif result.amount then
                    got = result.amount
                elseif result.size then
                    got = result.size
                else
                    got = toTake
                end
            else
                lastError = "неизвестный ответ: " .. tostring(result)
            end
        else
            lastError = tostring(result)
        end

        if got > 0 then
            extracted = extracted + got
            remaining = remaining - got
        else
            if lastError == nil then
                lastError = "не удалось выдать (вернулось 0 или false)"
            end
            break
        end
    end

    if extracted == 0 then
        showInventoryFullPopup = true
        drawPurchaseScreen()
        drawInventoryFullPopup()
        return
    end

    -- ★ ЧАСТИЧНАЯ ВЫДАЧА ★
    if extracted < qty then
        local actuallySpentCoin = extracted * (item.priceCoin or 0)
        local actuallySpentEma = extracted * (item.priceEma or 0)
        coinBalance = coinBalance - actuallySpentCoin
        emaBalance = emaBalance - actuallySpentEma
        playerTransactions = playerTransactions + 1

        if currentPlayer and players[currentPlayer] then
            players[currentPlayer].balance = coinBalance
            players[currentPlayer].emaBalance = emaBalance
            players[currentPlayer].transactions = playerTransactions
            saveDB()
            writeDebugLog("💾 Баланс сохранён (част.) для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        end

        addTransaction("buy", currentPlayer, item.displayName, extracted, actuallySpentCoin, actuallySpentEma)

        partialExtracted = extracted
        partialRequested = qty
        partialRefundCoin = actuallySpentCoin
        partialRefundEma = actuallySpentEma
        partialItem = item
        showPartialPopup = true
        drawPurchaseScreen()
        drawPartialPopup()
        return
    end

    -- ★ ПОЛНАЯ ВЫДАЧА ★
    coinBalance = coinBalance - totalCoin
    emaBalance = emaBalance - totalEma
    playerTransactions = playerTransactions + 1

    if currentPlayer and players[currentPlayer] then
        players[currentPlayer].balance = coinBalance
        players[currentPlayer].emaBalance = emaBalance
        players[currentPlayer].transactions = playerTransactions
        saveDB()
        writeDebugLog("💾 Баланс сохранён (полн.) для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
    end

    addTransaction("buy", currentPlayer, item.displayName, extracted, totalCoin, totalEma)

    gpu.setBackground(colors.bg_main)
    gpu.fill(2, 20, 78, 1, " ")
    local priceStr = ""
    if totalCoin > 0 then priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵" end
    if totalEma > 0 then
        if priceStr ~= "" then priceStr = priceStr .. " + " end
        priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
    end
    drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. priceStr, colors.success)

    loadBuyItems(true)
    for _, newItem in ipairs(shopItems) do
        if newItem.internalName == item.internalName and newItem.damage == item.damage then
            purchaseItem = newItem
            break
        end
    end
    os.sleep(0.8)
    currentScreen = "shop_buy"
    drawBuyStatic()
    drawBuyItemsList()
    drawBuyButtons()
end

-- ============================================================
-- ИНКРЕМЕНТАЛЬНОЕ ПРИМЕНЕНИЕ ИЗМЕНЕНИЙ (ДЛЯ ТОВАРОВ)
-- ============================================================

function applyIncrementalChanges(itemsFile, changes, itemType)
    writeDebugLog("📦 Применение инкрементальных изменений к " .. itemType)
    writeDebugLog("📦 Файл: " .. itemsFile)
    writeDebugLog("📦 Количество изменений: " .. (#changes or 0))

    if not changes or type(changes) ~= "table" or #changes == 0 then
        writeDebugLog("ℹ️ Нет изменений для применения")
        return true
    end

    local isShopFile = string.find(itemsFile, "shop_items") ~= nil

    local fileData = {}
    local sellItemsList = {}

    if fs.exists(itemsFile) then
        local ok, data = pcall(dofile, itemsFile)
        if ok and type(data) == "table" then
            fileData = data
            if isShopFile and fileData.sellItems and type(fileData.sellItems) == "table" then
                sellItemsList = fileData.sellItems
                writeDebugLog("📦 Загружены sell_items из shop_items.lua: " .. #sellItemsList .. " товаров")
            elseif not isShopFile then
                sellItemsList = data
                writeDebugLog("📦 Загружены buy_items: " .. #sellItemsList .. " товаров")
            else
                writeDebugLog("⚠️ В shop_items.lua нет поля sellItems, создаём новое")
                sellItemsList = {}
                fileData.sellItems = sellItemsList
                fileData.vanillaItems = fileData.vanillaItems or {}
            end
        else
            writeDebugLog("⚠️ Не удалось загрузить " .. itemsFile .. ", создаём новый")
            if isShopFile then
                fileData = { sellItems = {}, vanillaItems = {} }
                sellItemsList = fileData.sellItems
            else
                sellItemsList = {}
                fileData = sellItemsList
            end
        end
    else
        writeDebugLog("⚠️ Файл не существует: " .. itemsFile .. ", создаём новый")
        if isShopFile then
            fileData = { sellItems = {}, vanillaItems = {} }
            sellItemsList = fileData.sellItems
        else
            sellItemsList = {}
            fileData = sellItemsList
        end
    end

    local itemMap = {}
    for i, item in ipairs(sellItemsList) do
        local key = (item.internalName or "") .. ":" .. (item.damage or 0)
        itemMap[key] = i
    end

    local appliedCount = 0

    for _, change in ipairs(changes) do
        if not change or not change.item then
            writeDebugLog("⚠️ Пропускаем пустое изменение")
            goto next
        end

        local item = change.item
        local key = (item.internalName or "") .. ":" .. (item.damage or 0)
        writeDebugLog("🔍 Обработка: " .. key .. ", action=" .. (change.action or "?"))

        if change.action == "add" then
            table.insert(sellItemsList, item)
            appliedCount = appliedCount + 1
            writeDebugLog("➕ Добавлен: " .. (item.displayName or key))

        elseif change.action == "update" then
            local idx = itemMap[key]
            if idx then
                for k, v in pairs(item) do
                    if k ~= "internalName" and k ~= "damage" then
                        sellItemsList[idx][k] = v
                    end
                end
                appliedCount = appliedCount + 1
                writeDebugLog("🔄 Обновлён: " .. (item.displayName or key))
            else
                table.insert(sellItemsList, item)
                appliedCount = appliedCount + 1
                writeDebugLog("➕ Добавлен как новый: " .. (item.displayName or key))
            end

        elseif change.action == "delete" then
            local idx = itemMap[key]
            if idx then
                table.remove(sellItemsList, idx)
                appliedCount = appliedCount + 1
                writeDebugLog("❌ Удалён: " .. key)
            else
                writeDebugLog("⚠️ Не найден для удаления: " .. key)
            end
        end

        ::next::
    end

    if appliedCount == 0 then
        writeDebugLog("⚠️ Ни одно изменение не применено")
        return true
    end

    writeDebugLog("💾 Сохраняем файл: " .. itemsFile)
    local file = io.open(itemsFile, "w")
    if not file then
        writeErrorLog("❌ Не удалось открыть файл для записи: " .. itemsFile)
        return false
    end

    local serialized
    if isShopFile then
        serialized = serialization.serialize(fileData)
    else
        serialized = serialization.serialize(sellItemsList)
    end

    file:write("return " .. serialized)
    file:close()
    writeDebugLog("✅ Сохранено " .. appliedCount .. " изменений в " .. itemsFile)

    if isShopFile then
        sellItems = sellItemsList
        shopData.sellItems = sellItemsList
        shopData.vanillaItems = fileData.vanillaItems or {}
        writeDebugLog("📦 sellItems обновлён, товаров: " .. #sellItems)
    else
        buyItemsData = sellItemsList
        buyItemMap = {}
        for _, item in ipairs(buyItemsData) do
            local dmg = item.damage or 0
            local key = item.internalName .. ":" .. dmg
            buyItemMap[key] = item
        end
        writeDebugLog("📦 buyItemsData обновлена, товаров: " .. #buyItemsData)
    end

    if currentScreen == "shop_buy" then
        loadBuyItems(true)
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif currentScreen == "shop_sell" then
        loadSellItems()
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    end

    broadcastUpdate()
    return true
end

function checkWebCommands()
    if currentPlayer then syncCurrentPlayer() end
    writeDebugLog("🔍 checkWebCommands() запущена в " .. getRealTimeHM())

    local success, err = pcall(function()
        local url = WEB_URL .. "/api/commands"
        writeDebugLog("📡 Запрос к: " .. url)

        local response = internet.request(url)
        if not response then
            writeDebugLog("⚠️ Нет ответа от сервера")
            return
        end

        local status = response.getStatus and response:getStatus() or response.code or response.status
        if status then
            if status == 200 or status == 204 then
                writeDebugLog("✅ Статус ответа: " .. tostring(status))
            else
                writeErrorLog("⚠️ Сервер вернул HTTP " .. tostring(status) .. " на запрос " .. url)
                return
            end
        else
            writeDebugLog("⚠️ Не удалось получить статус ответа, продолжаем...")
        end

        if status == 204 then
            writeDebugLog("⚠️ Сервер вернул 204 No Content, пропускаем")
            return
        end

        local body = ""
        for chunk in response do
            body = body .. chunk
        end

        writeDebugLog("📥 Получено " .. #body .. " байт")

        if #body < 10 then
            writeDebugLog("⚠️ Ответ слишком короткий, пропускаем")
            return
        end

        local data = parseJSON(body)
        if data then
            writeDebugLog("✅ Распарсено: " .. serialization.serialize(data))
        else
            writeDebugLog("❌ data = nil после парсинга!")
            writeErrorLog("❌ Ошибка парсинга JSON: " .. string.sub(body, 1, 300))
            return
        end

        if not data.commands or #data.commands == 0 then
            writeDebugLog("⚠️ Нет команд в ответе")
            return
        end

        writeDebugLog("📨 Найдено команд: " .. #data.commands)

        for _, cmd in ipairs(data.commands) do
            local d = cmd.data or cmd
            local requestId = cmd.requestId or os.time()
        
            local function sendResult(success, msg)
                writeDebugLog("📤 [" .. (cmd.command or "unknown") .. "] " .. (success and "✅" or "❌") .. " " .. (msg or ""))
                sendToWeb("/api/command_result", toJson({
                    requestId = requestId,
                    success = success,
                    message = msg or "",
                    command = cmd.command
                }))
            end
        
            writeDebugLog("🔧 Выполняем команду: " .. (cmd.command or "unknown"))
            writeDebugLog("📨 Данные команды: " .. serialization.serialize(d))
        
            -- ==================== ОБНОВЛЕНИЕ ИГРОКА ====================
            if cmd.command == "update_player" or cmd.command == "set_balance" then
                local playerName = d.name or d.player
                if not playerName then
                    sendResult(false, "Нет имени игрока")
                    goto continue
                end
                
                -- ★★★ ПРИМЕНЯЕМ ИЗМЕНЕНИЕ В OC ★★★
                if players[playerName] then
                    if d.balance then
                        players[playerName].balance = tonumber(d.balance) or 0
                    end
                    if d.emaBalance then
                        players[playerName].emaBalance = tonumber(d.emaBalance) or 0
                    end
                    saveDBDeferred()
                    addLog("💰 Баланс обновлён: " .. playerName)
                    
                    -- Отправляем дельту на сервер
                    local balance_change = {
                        id = "bal_" .. os.time() .. "_" .. math.random(100000),
                        type = "update_balance",
                        data = {
                            player = playerName,
                            balance = players[playerName].balance,
                            emaBalance = players[playerName].emaBalance
                        }
                    }
                    add_pending_change(balance_change)
                    
                    sendResult(true, "Баланс обновлён")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end
            
            -- ==================== ИНКРЕМЕНТАЛЬНОЕ ОБНОВЛЕНИЕ ТОВАРОВ ====================
            if cmd.command == "save_buy_items_incremental" then
                writeDebugLog("📥 save_buy_items_incremental получен")
                local changes = d.changes
                local ok = applyIncrementalChanges("/home/buy_items.lua", changes, "buy_items")
                if ok and changes then
                    local item_change = {
                        id = "items_" .. os.time() .. "_" .. math.random(100000),
                        type = "update_items",
                        data = {
                            file = "buy_items",
                            changes = changes
                        }
                    }
                    add_pending_change(item_change)
                end
                sendResult(ok, ok and "Товары покупки обновлены" or "Ошибка обновления buy_items")
                goto continue
            end
            
            if cmd.command == "save_shop_items_incremental" then
                writeDebugLog("📥 save_shop_items_incremental получен")
                local changes = d.changes
                local ok = applyIncrementalChanges("/home/shop_items.lua", changes, "shop_items")
                if ok and changes then
                    local item_change = {
                        id = "items_" .. os.time() .. "_" .. math.random(100000),
                        type = "update_items",
                        data = {
                            file = "sell_items",
                            changes = changes
                        }
                    }
                    add_pending_change(item_change)
                end
                sendResult(ok, ok and "Магазин обновлён" or "Ошибка обновления shop_items")
                goto continue
            end
            
            -- ==================== РЕЖИМ ОБСЛУЖИВАНИЯ ====================
            if cmd.command == "toggle_pause" then
                if d.paused ~= nil then
                    shopPaused = d.paused
                    writeDebugLog("📥 Установлен режим обслуживания: " .. tostring(shopPaused) .. " (из данных)")
                else
                    shopPaused = not shopPaused
                    writeDebugLog("📥 Переключён режим обслуживания: " .. tostring(shopPaused))
                end
                
                addLog(shopPaused and "⏸️ Магазин переведён в режим обслуживания" or "🟢 Магазин открыт")
                sendToWeb("/api/new_log", toJson({
                    time = getRealTimeHM(),
                    level = "INFO",
                    text = shopPaused and "⏸️ Магазин переведён в режим обслуживания" or "🟢 Магазин открыт"
                }))
                
                local msg = serialization.serialize({op = "shop_paused", paused = shopPaused})
                for addr in pairs(markets or {}) do
                    pcall(modem.send, addr, 0xffef, msg)
                end
                
                sendStats()
                
                if currentScreen == "welcome" then
                    drawWelcomeScreen()
                elseif currentScreen == "auth" then
                    drawAuthScreen()
                elseif currentScreen == "menu" then
                    drawMainMenu()
                elseif currentScreen == "shop" then
                    drawShopMenu()
                elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
                    currentScreen = "menu"
                    drawMainMenu()
                end
                
                sendResult(true, shopPaused and "Магазин на паузе" or "Магазин активен")
                goto continue
            end
            
            if cmd.command == "update_market" then
                broadcastUpdate()
                sendResult(true, "Обновление разослано")
                goto continue
            end
            
            if cmd.command == "kill_market" then
                broadcastKill()
                sendResult(true, "Терминалы будут завершены")
                goto continue
            end
            
            -- ==================== БАН / РАЗБАН ====================
            if cmd.command == "toggle_ban" then
                local playerName = d.name
                local banned = d.banned
                local reason = d.reason or "Без причины"
                
                if not playerName then
                    sendResult(false, "Нет имени игрока")
                    goto continue
                end
                
                writeDebugLog("📥 toggle_ban: " .. playerName .. " -> " .. tostring(banned))
                
                if banned then
                    if players[playerName] then
                        players[playerName].banned = true
                        players[playerName].banReason = reason
                        players[playerName].banAdmin = "Система"
                        players[playerName].banDate = getRealTimeString()
                        players[playerName].banExpires = nil
                        saveDB()
                        writeDebugLog("🔒 Игрок забанен: " .. playerName)
                    else
                        writeErrorLog("⚠️ Игрок не найден для бана: " .. playerName)
                    end
                    local ban_change = {
                        id = "ban_" .. os.time() .. "_" .. math.random(100000),
                        type = "ban",
                        data = {
                            player = playerName,
                            reason = reason,
                            admin = "Система"
                        }
                    }
                    add_pending_change(ban_change)
                    sendResult(true, "Игрок забанен")
                else
                    if players[playerName] then
                        players[playerName].banned = false
                        players[playerName].banReason = nil
                        players[playerName].banAdmin = nil
                        players[playerName].banDate = nil
                        players[playerName].banExpires = nil
                        saveDB()
                        writeDebugLog("🔓 Игрок разбанен: " .. playerName)
                    end
                    local unban_change = {
                        id = "unban_" .. os.time() .. "_" .. math.random(100000),
                        type = "unban",
                        data = {
                            player = playerName
                        }
                    }
                    add_pending_change(unban_change)
                    sendResult(true, "Игрок разбанен")
                end
                
                if currentPlayer == playerName then
                    if banned then
                        drawCenteredText(20, "ВЫ ЗАБАНЕНЫ!", colors.error)
                        os.sleep(2)
                        currentPlayer = nil
                        currentToken = nil
                        alreadyAuthorized = false
                        currentScreen = "welcome"
                        drawWelcomeScreen()
                    end
                end
                goto continue
            end
            
            -- ==================== УДАЛЕНИЕ ОТЗЫВА ====================
            if cmd.command == "delete_feedback" then
                local index = d.index
                writeDebugLog("🗑️ Удаление отзыва: индекс " .. tostring(index))
                
                local feedbacks = {}
                if fs.exists(FEEDBACKS_PATH) then
                    local file = io.open(FEEDBACKS_PATH, "r")
                    if file then
                        local data = file:read("*a")
                        file:close()
                        if data and #data > 0 then
                            local ok, result = pcall(serialization.unserialize, data)
                            if ok and type(result) == "table" then feedbacks = result end
                        end
                    end
                end
                
                local ocIndex = index + 1
                if type(index) == "number" and ocIndex >= 1 and ocIndex <= #feedbacks then
                    table.remove(feedbacks, ocIndex)
                    local file = io.open(FEEDBACKS_PATH, "w")
                    if file then
                        file:write(serialization.serialize(feedbacks))
                        file:close()
                        writeDebugLog("✅ Отзыв удалён из OC")
                        sendResult(true, "Отзыв удалён")
                    else
                        writeErrorLog("❌ Не удалось открыть файл для записи")
                        sendResult(false, "Ошибка записи")
                    end
                else
                    writeDebugLog("⚠️ Индекс не найден: " .. tostring(index) .. " (OC индекс: " .. tostring(ocIndex) .. "), всего отзывов: " .. #feedbacks)
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end
            
            -- ==================== ОТМЕТКА ОТЗЫВА КАК ПРОСМОТРЕННОГО ====================
            if cmd.command == "feedback_viewed" then
                local index = d.index
                writeDebugLog("📌 Отметка отзыва как просмотренного: индекс " .. tostring(index))
                
                local feedbacks = {}
                if fs.exists(FEEDBACKS_PATH) then
                    local file = io.open(FEEDBACKS_PATH, "r")
                    if file then
                        local data = file:read("*a")
                        file:close()
                        if data and #data > 0 then
                            local ok, result = pcall(serialization.unserialize, data)
                            if ok and type(result) == "table" then feedbacks = result end
                        end
                    end
                end
                
                local ocIndex = index + 1
                if type(index) == "number" and ocIndex >= 1 and ocIndex <= #feedbacks then
                    feedbacks[ocIndex].viewed = true
                    local file = io.open(FEEDBACKS_PATH, "w")
                    if file then
                        file:write(serialization.serialize(feedbacks))
                        file:close()
                        writeDebugLog("✅ Отзыв отмечен как просмотренный в OC")
                        sendResult(true, "Отзыв отмечен")
                    else
                        writeErrorLog("❌ Не удалось открыть файл для записи")
                        sendResult(false, "Ошибка записи")
                    end
                else
                    writeDebugLog("⚠️ Индекс не найден: " .. tostring(index) .. " (OC индекс: " .. tostring(ocIndex) .. "), всего отзывов: " .. #feedbacks)
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end
            
            sendResult(false, "Неизвестная команда: " .. tostring(cmd.command))
            
            ::continue::
        end  
     end)

    if not success then
        writeErrorLog("❌ Критическая ошибка в checkWebCommands: " .. tostring(err))
    end
end

event.timer(10, checkWebCommands, math.huge)

-- ============================================================
-- СОГЛАШЕНИЕ (заглушка, если файл не загружен)
-- ============================================================

drawAgreementScreen = nil
if fs.exists("/home/agreement.lua") then
    local ok, func = pcall(dofile, "/home/agreement.lua")
    if ok and type(func) == "function" then
        drawAgreementScreen = func
        writeDebugLog("✅ agreement.lua загружен")
    else
        writeErrorLog("❌ Ошибка загрузки agreement.lua")
    end
end
if not drawAgreementScreen then
    drawAgreementScreen = function()
        writeDebugLog("drawAgreementScreen (заглушка)")
        clear()
        drawScreenBorder()
        drawCenteredText(6, "ПОЛЬЗОВАТЕЛЬСКОЕ СОГЛАШЕНИЕ", colors.accent_secondary)
        drawCenteredText(8, "Файл agreement.lua не найден!", colors.error)
        drawCenteredText(9, "Создайте его в папке /home/", colors.text_main)
        drawCenteredText(11, "Нажмите [НАЗАД] для возврата", colors.text_main)
        
        local backButton = {
            text = "[ НАЗАД ]",
            x = 37, y = 24,
            xs = unicode.len("[ НАЗАД ]") + 2,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.accent_secondary
        }
        drawFlexButton(backButton)
        drawTempMessage()
        
        while currentScreen == "agreement" do
            local ev = {event.pull(0.5)}
            if ev[1] == "touch" then
                local x = tonumber(ev[3]) or 0
                local y = tonumber(ev[4]) or 0
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    break
                end
            end
        end
    end
end

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ (С ДОБАВЛЕННОЙ ПРОВЕРКОЙ БАНА ПРИ ВХОДЕ)
-- ============================================================

gpu.setResolution(80, 25)
gpu.setBackground(colors.bg_main)

lastMouseMoveTime = 0
MOUSE_DEBOUNCE = 0.05

function main()
    writeDebugLog("🚀 main() запущен")
    drawWelcomeScreen()

    while true do
        local ev = {event.pull(0.5)}
        local e = ev[1]

        if e == "key_down" then
            local _, _, _, code, char = table.unpack(ev)
            if char == 3 then
                goto continue
            end
        end

        if currentScreen == "auth" then
            if os.clock() - authStartTime >= AUTH_TIMEOUT then
                currentScreen = "menu"
                drawMainMenu()
            end
        end

                if e == "touch" then
            local x = tonumber(ev[3]) or 0
            local y = tonumber(ev[4]) or 0
            local playerName = ev[6] or "Неизвестный"
            
            if not isPimOwner(playerName) then
                goto continue
            end

            if currentScreen == "menu" then
                for name, btn in pairs(menuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "shop" then
                            if playerAgreed then
                                goToShop()
                            else
                                showShopDenied = true
                                drawMainMenu()
                            end
                        elseif name == "account" then
                            showShopDenied = false
                            goToAccount()
                        end
                        goto continue
                    end
                end
                if y == 24 then
                    if x >= 4 and x <= 25 then
                        showShopDenied = false
                        goToReport()
                        goto continue
                    elseif x >= 35 and x <= 47 then
                        showShopDenied = false
                        goToHelp()
                        goto continue
                    elseif x >= 68 and x <= 78 then
                        currentScreen = "feedbacks"
                        drawFeedbacksList()
                        goto continue
                    end
                end
                goto continue
            end

            if currentScreen == "shop" then
                for name, btn in pairs(shopMenuButtons) do
                    if x >= btn.x and x < btn.x + btn.xs and y >= btn.y and y < btn.y + btn.ys then
                        if name == "buy" then
                            goToBuy()
                        elseif name == "sell" then
                            goToSell()
                        end
                        goto continue
                    end
                end
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
            end

            if currentScreen == "shop_buy" or currentScreen == "shop_sell" then
                if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                    local relativeRow = y - 6
                    local clickedIndex = (listScroll or 1) + relativeRow - 1
                    local item = filteredItems[clickedIndex]
                    if item and (currentShopMode ~= "buy" or item.qty > 0) then
                        selectedIndex = clickedIndex
                        selectedItem = item
                        hoveredIndex = 0
                        updateSelectorDisplay(selectedItem)
                        drawBuyItemsList()
                        drawBuyButtons()
                    end
                    goto continue
                end

                if x >= 78 and y >= 7 and y <= 21 then
                    local total = #filteredItems
                    if total > visibleRows then
                        local clickPos = y - 6
                        listScroll = math.floor((clickPos - 1) * (total - visibleRows) / visibleRows) + 1
                        drawBuyItemsList()
                    end
                    goto continue
                end

                if y == 3 and x >= 42 and x <= 64 then
                    searchActive = true
                    searchInput = shopSearch or ""
                    redrawSearchField()
                    drawBuyItemsList()
                    goto continue
                end

                if y == 3 and x >= 66 and x <= 78 then
                    shopSearch = ""
                    searchInput = ""
                    searchActive = false
                    redrawSearchField()
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                end

                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                local nextButton = {}
                if currentShopMode == "buy" then
                    nextButton.text = "[ КУПИТЬ ]"
                    nextButton.xs = unicode.len(nextButton.text) + 2
                else
                    nextButton.text = "[ ПРОДАТЬ ]"
                    nextButton.xs = unicode.len(nextButton.text) + 2
                end
                nextButton.x = 59
                nextButton.y = 24
                nextButton.ys = 1
                nextButton.bg = colors.bg_button
                nextButton.fg = colors.inactive

                if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                    nextButton.fg = colors.accent_secondary
                else
                    nextButton.fg = colors.inactive
                end

                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop"
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    updateSelectorDisplay(nil)
                    drawShopMenu()
                    goto continue
                end

                if isButtonClicked(nextButton, x, y) then
                    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
                        if currentShopMode == "buy" then
                            local needCoin = selectedItem.priceCoin or 0
                            local needEma = selectedItem.priceEma or 0
                            if (needCoin > 0 and coinBalance < needCoin) or (needEma > 0 and emaBalance < needEma) then
                                showInsufficientPopup = true
                                insufficientBalanceCoin = coinBalance
                                insufficientBalanceEma = emaBalance
                                drawBuyStatic()
                                drawBuyItemsList()
                                drawBuyButtons()
                                drawInsufficientPopup()
                                goto continue
                            end
                            goToPurchase(selectedItem)
                        else
                            goToSellConfirm(selectedItem)
                        end
                    end
                    goto continue
                end

                if searchActive then
                    shopSearch = searchInput or ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                end

            elseif showSellPopup and currentScreen == "sell_scan" then
                local popupWidth = 40
                local popupHeight = 10
                local popupX = math.floor((80 - popupWidth) / 2)
                local popupY = 10
                local yesBtn = {x=popupX+5, y=popupY+7, xs=13, ys=1}
                local noBtn  = {x=popupX+popupWidth-16, y=popupY+7, xs=12, ys=1}
                if isButtonClicked(yesBtn, x, y) then
                    performSell()
                elseif isButtonClicked(noBtn, x, y) then
                    showSellPopup = false
                    drawSellScanScreen()
                elseif not (x >= popupX and x < popupX + popupWidth and y >= popupY and y < popupY + popupHeight) then
                    showSellPopup = false
                    drawSellScanScreen()
                end
                goto continue

            elseif currentScreen == "purchase" then
                if (y >= 24 and y <= 24) and (x >= 19 and x <= 28) then
                    if currentShopMode == "buy" then
                        currentScreen = "shop_buy"
                        drawBuyStatic()
                        drawBuyItemsList()
                        drawBuyButtons()
                    else
                        currentScreen = "shop_sell"
                        drawBuyStatic()
                        drawBuyItemsList()
                        drawBuyButtons()
                    end
                    goto continue
                elseif (y >= 24 and y <= 24) and (x >= 51 and x <= 61) then
                    performBuy()
                    goto continue
                end

                local startX = 34
                local startY = 11
                local btnW = 3
                local btnH = 1
                local spacing = 2
                local keys = {
                    {"1","2","3"},
                    {"4","5","6"},
                    {"7","8","9"},
                    {"<","0","C"}
                }
                for row = 1, 4 do
                    for col = 1, 3 do
                        local bx = startX + (col-1)*(btnW + spacing)
                        local by = startY + (row-1)*(btnH + 1)
                        if x >= bx and x < bx+btnW and y >= by and y < by+btnH then
                            handleQuantityButtonClick(keys[row][col])
                            goto continue
                        end
                    end
                end

            elseif currentScreen == "sell_scan" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                if isButtonClicked(backButton, x, y) then
                    currentScreen = "shop_sell"
                    showSellPopup = false
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                    goto continue
                elseif y == 13 and x >= 30 and x <= 50 then
                    drawCenteredText(17, "Сканирование...", colors.accent_secondary)
                    os.sleep(0.6)
                    if not sellConfirmItem then
                        writeErrorLog("❌ sellConfirmItem = nil при сканировании!")
                        goto continue
                    end
                    foundAmount = scanPlayerInventory(sellConfirmItem.internalName, sellConfirmItem.damage or 0)
                    if foundAmount > 0 then
                        showSellPopup = true
                        drawSellScanScreen()
                    else
                        drawCenteredText(17, "Предмет не найден!", colors.error)
                        os.sleep(0.8)
                        drawSellScanScreen()
                    end
                    goto continue
                end

            elseif currentScreen == "report" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
                if canSendReport() then
                local sendBtn = {x=33, y=14, xs=17, ys=1}
                if isButtonClicked(sendBtn, x, y) and reportInput and reportInput ~= "" then
                    sendToWeb("/api/new_report", toJson({
                        time = getRealTimeString(),
                        name = currentPlayer or "?",
                        text = reportInput
                    }))
                    
                    local file = io.open(REPORTS_PATH, "a")
                    if file then
                        file:write("[" .. getRealTimeString() .. "] " .. (currentPlayer or "?") .. ": " .. reportInput .. "\n")
                        file:close()
                    end
                    
                    addLog("📩 Репорт от " .. (currentPlayer or "?"))
                    lastReportTime = getRealTimestamp()
                    globalStats.totalReports = (globalStats.totalReports or 0) + 1
                    saveGlobalStats()
                    
                    drawCenteredText(18, "Сообщение успешно отправлено! Ожидайте ответа.", colors.success)
                    os.sleep(0.8)
                    goBackToMenu()
                    goto continue
                end
            end


            elseif currentScreen == "feedbacks" then
                local backBtn = {x=5, y=24, xs=11, ys=1}
                if isButtonClicked(backBtn, x, y) then
                    currentScreen = "menu"
                    drawMainMenu()
                    goto continue
                end
                local addBtn = {x=36, y=24, xs=14, ys=1}
                if isButtonClicked(addBtn, x, y) then
                    if playerHasFeedback then
                        showTempMessage("Вы уже оставляли отзыв!", 2)
                    else
                        feedbackInput = ""
                        feedbackEditMode = true
                        drawFeedbackInputScreen()
                    end
                    goto continue
                end
                if isButtonClicked({x=59, y=24, xs=7, ys=1}, x, y) and feedbacksPage > 1 then
                    feedbacksPage = feedbacksPage - 1
                    drawFeedbacksList()
                    goto continue
                end
                if isButtonClicked({x=69, y=24, xs=7, ys=1}, x, y) and feedbacksPage < feedbacksTotalPages then
                    feedbacksPage = feedbacksPage + 1
                    drawFeedbacksList()
                    goto continue
                end

            elseif currentScreen == "feedback_input" then
                if isButtonClicked({x=20, y=24, xs=12, ys=1}, x, y) then
                    feedbackEditMode = false
                    feedbackInput = ""
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end
                if isButtonClicked({x=46, y=24, xs=15, ys=1}, x, y) and feedbackInput and feedbackInput ~= "" then
                    local feedbacks = {}
                    if fs.exists(FEEDBACKS_PATH) then
                        local file = io.open(FEEDBACKS_PATH, "r")
                        if file then
                            local data = file:read("*a")
                            file:close()
                            if data and #data > 0 then
                                local ok, result = pcall(serialization.unserialize, data)
                                if ok and type(result) == "table" then feedbacks = result end
                            end
                        end
                    end
                    table.insert(feedbacks, 1, {
                        name = currentPlayer or "Аноним",
                        text = feedbackInput,
                        time = getRealTimeString()
                    })
                    local file = io.open(FEEDBACKS_PATH, "w")
                    if file then
                        file:write(serialization.serialize(feedbacks))
                        file:close()
                    end
                    playerHasFeedback = true
                    showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    feedbackEditMode = false
                    feedbackInput = ""
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                    goto continue
                end

            elseif currentScreen == "agreement" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
                local btnText = "[ ПОНЯТНО ]"
                local btnW = unicode.len(btnText) + 4
                local btnX = math.floor((80 - btnW)/2) + 2
                if y == 22 and x >= btnX and x <= btnX + btnW then
                    playerAgreed = true
                    local player = players[currentPlayer]
                    if player then
                        player.agreed = true
                        saveDBDeferred()
                    end
                    showTempMessage("✅ Спасибо! Теперь вам доступен магазин.", 2)
                    goBackToMenu()
                    goto continue
                end

            elseif currentScreen == "account" or currentScreen == "account_loading" then
                local backButton = {
                    text = "[ НАЗАД ]",
                    x = 37, y = 24,
                    xs = unicode.len("[ НАЗАД ]") + 2,
                    ys = 1,
                    bg = colors.bg_button,
                    fg = colors.accent_secondary
                }
                if isButtonClicked(backButton, x, y) then
                    goBackToMenu()
                    goto continue
                end
            end

            if showInsufficientPopup then
                local popupWidth = 52
                local popupHeight = 11
                local popupX = math.floor((80 - popupWidth) / 2)
                local popupY = 7
                local okBtnText = "[ ПОНЯТНО ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+8,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showInsufficientPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            end

            if showPartialPopup then
                local popupWidth = 52
                local popupHeight = 9
                local popupX = math.floor((80 - popupWidth) / 2)
                local popupY = 9
                local okBtnText = "[ ПРИНЯТЬ ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+6,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showPartialPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            end

            if showInventoryFullPopup then
                local popupWidth = 52
                local popupHeight = 9
                local popupX = math.floor((80 - popupWidth) / 2)
                local popupY = 9
                local okBtnText = "[ ПОНЯТНО ]"
                local okBtnWidth = unicode.len(okBtnText) + 2
                local okBtn = {
                    x = popupX + math.floor((popupWidth - okBtnWidth) / 2),
                    y = popupY+6,
                    xs = okBtnWidth,
                    ys = 1
                }
                if isButtonClicked(okBtn, x, y) then
                    showInventoryFullPopup = false
                    currentScreen = "shop_buy"
                    drawBuyStatic()
                    drawBuyItemsList()
                    drawBuyButtons()
                end
                goto continue
            end

            goto continue
        end   -- <-- ЭТОТ END ЗАКРЫВАЕТ if e == "touch"

        -- ===== ОТДЕЛЬНЫЕ ОБРАБОТЧИКИ (без elseif) =====
        if e == "scroll" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            local playerName = ev[6] or "Неизвестный"
            if not isPimOwner(playerName) then
                goto continue
            end
            local direction = ev[5] or 0
            local x = ev[3] or 0
            local y = ev[4] or 0
            if x >= 2 and x <= 78 and y >= 7 and y <= 21 then
                if direction == -1 then
                    smoothScroll(1)
                elseif direction == 1 then
                    smoothScroll(-1)
                end
            end
            goto continue
        end

        if e == "mouse_move" and (currentScreen == "shop_buy" or currentScreen == "shop_sell") then
            if not pimOwner then
                goto continue
            end
            local now = os.clock()
            if now - lastMouseMoveTime < MOUSE_DEBOUNCE then
                goto continue
            end
            lastMouseMoveTime = now
            
            local x, y = ev[3], ev[4]
            if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
                local rel = y - 6
                local newHover = (listScroll or 1) + rel - 1
                if newHover <= #filteredItems and newHover ~= hoveredIndex then
                    hoveredIndex = newHover
                    drawBuyItemsList()
                end
            else
                if hoveredIndex ~= 0 then
                    hoveredIndex = 0
                    drawBuyItemsList()
                end
            end
            goto continue
        end

        if e == "key_down" then
            local playerName = ev[5] or "Неизвестный"
            local keyCode = ev[3] or 0
            
            if keyCode == 18 or keyCode == 17 or keyCode == 16 or keyCode == 91 or keyCode == 93 then
                goto continue
            end
            
            if not isPimOwner(playerName) then
                goto continue
            end
            
            if currentScreen == "report" and canSendReport() then
                local ch = ev[3]
                if ch == 13 then
                    drawReportScreen()
                elseif ch == 8 then
                    reportInput = unicode.sub(reportInput or "", 1, -2)
                    drawReportScreen()
                elseif ch >= 32 then
                    reportInput = (reportInput or "") .. unicode.char(ch)
                    drawReportScreen()
                end
            elseif (currentScreen == "shop_buy" or currentScreen == "shop_sell") and searchActive then
                local ch = ev[3]
                if ch == 13 then
                    shopSearch = searchInput or ""
                    searchActive = false
                    listScroll = 1
                    selectedIndex = 0
                    selectedItem = nil
                    hoveredIndex = 0
                    drawBuyItemsList()
                    drawBuyButtons()
                elseif ch == 8 then
                    searchInput = unicode.sub(searchInput or "", 1, -2)
                    shopSearch = searchInput or ""
                    redrawSearchField()
                    drawBuyItemsList()
                elseif ch >= 32 then
                    searchInput = (searchInput or "") .. unicode.char(ch)
                    shopSearch = searchInput or ""
                    redrawSearchField()
                    drawBuyItemsList()
                end
                goto continue
            elseif currentScreen == "feedback_input" and feedbackEditMode then
                local ch = ev[3]
                if ch == 13 then
                    if feedbackInput and feedbackInput ~= "" then
                        local feedbacks = {}
                        if fs.exists(FEEDBACKS_PATH) then
                            local file = io.open(FEEDBACKS_PATH, "r")
                            if file then
                                local data = file:read("*a")
                                file:close()
                                if data and #data > 0 then
                                    local ok, result = pcall(serialization.unserialize, data)
                                    if ok and type(result) == "table" then feedbacks = result end
                                end
                            end
                        end
                        table.insert(feedbacks, 1, {
                            name = currentPlayer or "Аноним",
                            text = feedbackInput,
                            time = getRealTimeString()
                        })
                        local file = io.open(FEEDBACKS_PATH, "w")
                        if file then
                            file:write(serialization.serialize(feedbacks))
                            file:close()
                        end
                        playerHasFeedback = true
                        showTempMessage("✅ Отзыв отправлен! Спасибо!", 10)
                    end
                    feedbackEditMode = false
                    feedbackInput = ""
                    currentScreen = "feedbacks"
                    drawFeedbacksList()
                elseif ch == 8 then
                    feedbackInput = unicode.sub(feedbackInput or "", 1, -2)
                    drawFeedbackInputScreen()
                elseif ch >= 32 then
                    if unicode.len(feedbackInput or "") < 200 then
                        feedbackInput = (feedbackInput or "") .. unicode.char(ch)
                        drawFeedbackInputScreen()
                    end
                end
                goto continue
            end
            goto continue
        end

        if e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = ev[2] or "Игрок"
            writeDebugLog("player_on: " .. playerName)
            
            if shopPaused then
                writeDebugLog("Режим обслуживания активен, вход запрещён для: " .. playerName)
                gpu.setBackground(colors.bg_main)
                gpu.fill(1, 1, 80, 25, " ")
                drawBigTitle()
                gpu.setForeground(colors.error)
                drawCenteredText(17, "РЕЖИМ ОБСЛУЖИВАНИЯ", colors.error)
                drawCenteredText(18, "Магазин временно закрыт", colors.error)
                drawCenteredText(19, "Пожалуйста, зайдите позже", colors.text_main)
                gpu.setForeground(colors.text_main)
                drawCenteredText(22, "--===============|VIP SHOP|===============--", colors.text_main)
                drawTempMessage()
                
                while shopPaused do
                    local ev2 = {event.pull(1)}
                    if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                        writeDebugLog("👤 Игрок ушёл с PIM: " .. playerName)
                        drawWelcomeScreen()
                        break
                    end
                end
                goto continue
            end
            
            if not pimOwner then
                pimOwner = playerName
            end
            currentPlayer = playerName:match("^%s*(.-)%s*$") or playerName
            
            -- ★★★ ПРОВЕРКА БАНА ЧЕРЕЗ СЕРВЕР ★★★
            local banInfo = nil
            local success, response = pcall(function()
                return internet.request(WEB_URL .. "/api/check_ban?name=" .. currentPlayer)
            end)
            if success and response then
                local body = ""
                for chunk in response do
                    body = body .. chunk
                end
                local data = parseJSON(body)
                if data and data.banned then
                    banInfo = data
                end
            end

            if banInfo then
            -- ★★★ ПОЛНОСТЬЮ ОЧИЩАЕМ ЭКРАН БЕЗ VIP SHOP ★★★
            gpu.setBackground(colors.bg_main)
            gpu.fill(1, 1, 80, 25, " ")
            
            -- Рисуем баннер БЕЗ drawBigTitle()
            gpu.setForeground(colors.error)
            drawCenteredText(6, "╔══════════════════════════════════════════════════════════════╗", colors.error)
            drawCenteredText(7, "║                     ВЫ ЗАБЛОКИРОВАНЫ                         ║", colors.error)
            drawCenteredText(8, "╚══════════════════════════════════════════════════════════════╝", colors.error)
            
            drawCenteredText(10, "Причина: " .. (banInfo.reason or "Не указана"), colors.text_main)
            drawCenteredText(11, "Администратор: " .. (banInfo.admin or "Система"), colors.text_main)
            drawCenteredText(12, "Дата: " .. (banInfo.date or ""), colors.text_main)
            
            if banInfo.expires then
                drawCenteredText(13, "Срок истекает: " .. banInfo.expires, colors.text_main)
            else
                drawCenteredText(13, "Бессрочный бан", colors.text_main)
            end
            
            drawCenteredText(15, "Доступ запрещён", colors.error)
            
            -- Рисуем нижнюю границу
            gpu.setForeground(colors.accent_secondary)
            drawCenteredText(22, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", colors.accent_secondary)
            
            drawTempMessage()
            
            while true do
                local ev2 = {event.pull(1)}
                if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                    writeDebugLog("👤 Игрок ушёл с PIM: " .. playerName)
                    drawWelcomeScreen()
                    break
                end
            end
            currentPlayer = nil
            pimOwner = nil
            alreadyAuthorized = false
            currentScreen = "welcome"
            goto continue
        end
            
            if alreadyAuthorized then
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    drawMainMenu()
                end
            elseif currentToken then
                alreadyAuthorized = true
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    drawMainMenu()
                end
            else
                writeDebugLog("Новый вход: " .. playerName)
                coinBalance = 0.0
                emaBalance = 0.0
                playerAgreed = false
                currentScreen = "auth"
                authStartTime = os.clock()
                drawAuthScreen()
                
                local player = players[currentPlayer]
                if not player then
                    player = { 
                        balance = 0, 
                        emaBalance = 0, 
                        transactions = 0, 
                        banned = false, 
                        agreed = false, 
                        hasFeedback = false,
                        transactionsList = {},
                        regDate = getRealTimeString()
                    }
                    players[currentPlayer] = player
                    saveDBDeferred()
                    addLog("✅ Новый игрок: " .. currentPlayer)
                    writeDebugLog("Создан новый игрок: " .. currentPlayer)
                    sendToWeb("/api/new_log", toJson({
                        time = getRealTimeHM(),
                        level = "SUCCESS",
                        text = "Новый игрок: " .. currentPlayer
                    }))
                    
                    -- ★★★ ОТПРАВЛЯЕМ ДЕЛЬТУ НА СЕРВЕР ★★★
                    local change = {
                        id = "new_" .. os.time() .. "_" .. math.random(100000),
                        type = "new_player",
                        data = {
                            name = currentPlayer,
                            balance = 0,
                            emaBalance = 0
                        }
                    }
                    add_pending_change(change)
                end
                
                if player.banned then
                    drawCenteredText(20, "Вы забанены!", colors.error)
                    os.sleep(2)
                    currentPlayer = nil
                    currentScreen = "welcome"
                    drawWelcomeScreen()
                else
                    currentToken = tostring(math.floor(math.random() * 900000000 + 100000000))
                    coinBalance = player.balance or 0
                    emaBalance = player.emaBalance or 0
                    playerTransactions = player.transactions or 0
                    playerAgreed = player.agreed or false
                    playerRegDate = player.regDate or getRealTimeString()
                    alreadyAuthorized = true
                    
                    writeDebugLog("Вход выполнен: " .. currentPlayer .. ", баланс: " .. coinBalance .. ", agreed: " .. tostring(playerAgreed))
                    
                    if selector then
                        addLog("🖥 Селектор доступен")
                    end
                    
                    currentScreen = "menu"
                    drawMainMenu()
                    addLog("👤 Вход: " .. currentPlayer)
                    sendToWeb("/api/new_log", toJson({
                        time = getRealTimeHM(),
                        level = "INFO",
                        text = "Вход: " .. currentPlayer
                    }))
                end
            end
            goto continue
        end

        if e == "player_off" or e == "pim_player_leave" then
            local playerName = ev[2] or "Игрок"
            writeDebugLog("player_off: " .. playerName)
            addLog("👤 Выход: " .. playerName)
            sendToWeb("/api/new_log", toJson({
                time = getRealTimeHM(),
                level = "INFO",
                text = "Выход: " .. playerName
            }))
            
            if playerName == pimOwner then
                pimOwner = nil
            end
            
            -- ★★★ ПОЛНЫЙ СБРОС СОСТОЯНИЯ ★★★
            currentPlayer = nil
            currentToken = nil
            alreadyAuthorized = false
            currentScreen = "welcome"
            shopPaused = false
            
            -- Сброс выбранных предметов
            selectedItem = nil
            hoveredIndex = 0
            selectedIndex = 0
            filteredItems = {}
            shopSearch = ""
            searchActive = false
            searchInput = ""
            
            -- Сброс покупки/продажи
            purchaseItem = nil
            purchaseQuantity = 1
            sellConfirmItem = nil
            foundAmount = 0
            showSellPopup = false
            
            -- Сброс поп-апов
            showPartialPopup = false
            partialExtracted = 0
            partialRequested = 0
            partialRefundCoin = 0
            partialRefundEma = 0
            partialItem = nil
            showInsufficientPopup = false
            insufficientBalanceCoin = 0
            insufficientBalanceEma = 0
            showInventoryFullPopup = false
            
            -- Сброс скролла
            listScroll = 1
            horizontalScroll = 1
            
            -- Сброс временных сообщений
            tempMessage = ""
            if tempMessageTimer then
                event.cancel(tempMessageTimer)
                tempMessageTimer = nil
            end
            
            -- Очистка селектора
            pcall(updateSelectorDisplay, nil)
            pcall(selector.setSlot, 0, nil)
            pcall(selector.setSlot, 1, nil)
            
            drawWelcomeScreen()
            goto continue
        end

        ::continue::
    end
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

while true do
    local ok, err = pcall(main)
    if not ok then
        local msg = "💥 ГЛОБАЛЬНАЯ ОШИБКА: " .. tostring(err)
        print(msg)
        writeErrorLog(msg)
        local stack = debug.traceback()
        writeErrorLog("Стек вызовов:\n" .. stack)
        print(stack)
        os.sleep(5)
    end
end
