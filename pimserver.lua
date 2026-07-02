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
local TIMEZONE_OFFSET = 3 * 3600 

local modem = component.modem
modem.open(0xffef)
modem.open(0xfffe)

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

-- ============================================
-- СИСТЕМА ЛОГИРОВАНИЯ ДЛЯ ОТЛАДКИ
-- ============================================
local function writeDebugLog(msg)
    local file = io.open("/home/debug.log", "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " | " .. msg .. "\n")
        file:close()
    end
end

writeDebugLog("=== СЕРВЕР ЗАПУЩЕН ===")

-- ============================================
-- TELEGRAM НАСТРОЙКИ
-- ============================================
local TELEGRAM_TOKEN = "8780133006:AAF2Zg7Dv_mr-E1-bgVuGDVsKYvyuwizuaE"
local TELEGRAM_CHAT_ID = "492178371"

writeDebugLog("Telegram токен загружен")

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

local ansi = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",
    bg_black   = "\27[40m",
    bg_blue    = "\27[44m",
    clear   = "\27[2J\27[H",
    hide_cursor = "\27[?25l",
    show_cursor = "\27[?25h"
}

local function setColor(fg, bg)
    io.write(fg or "")
    if bg then io.write(bg) end
end

local function resetColor()
    io.write(ansi.reset)
end

local function gotoxy(x, y)
    io.write("\27[", y, ";", x, "H")
end

local function fill(x, y, w, h, char)
    for i = 0, h-1 do
        gotoxy(x, y+i)
        io.write(string.rep(char, w))
    end
end

local function timeToMidnight()
    local now = getRealTimestamp()
    local dt = os.date("*t", now)
    local secondsLeft = (24 - dt.hour - 1) * 3600 + (60 - dt.min - 1) * 60 + (60 - dt.sec)
    if secondsLeft < 0 then secondsLeft = 0 end
    local h = math.floor(secondsLeft / 3600)
    local m = math.floor((secondsLeft % 3600) / 60)
    local s = secondsLeft % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local ACCESS_PASSWORD = "secret"

-- ===== СИСТЕМА АДМИНИСТРАТОРОВ =====
local ADMINS_PATH = "/home/admins.db"
local admins = {}

if filesystem.exists(ADMINS_PATH) then
    local file = io.open(ADMINS_PATH, "r")
    if file then
        local raw = file:read("*a")
        file:close()
        if raw and #raw > 0 then
            local success, data = pcall(serialization.unserialize, raw)
            if success and type(data) == "table" then
                admins = data
            end
        end
    end
end

if #admins == 0 then
    admins = {"ZoziDo"}
    local file = io.open(ADMINS_PATH, "w")
    if file then
        file:write(serialization.serialize(admins))
        file:close()
    end
end

local function isAdmin(playerName)
    if not playerName then return false end
    for _, name in ipairs(admins) do
        if name == playerName then
            return true
        end
    end
    return false
end

local function addAdmin(playerName)
    if not playerName or playerName == "" or isAdmin(playerName) then return false end
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
    if not playerName or #admins <= 1 then return false end
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

-- ===== ДАННЫЕ =====
local DB_PATH = "/home/players.db"
local players = {}
if filesystem.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then players = data end
    end
end

local function saveDB()
    local file = io.open(DB_PATH, "w")
    file:write(serialization.serialize(players))
    file:close()
end

local STATS_PATH = "/home/global_stats.db"
local globalStats = { totalReports = 0, totalBuys = 0, totalSells = 0 }
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

local function saveGlobalStats()
    local file = io.open(STATS_PATH, "w")
    file:write(serialization.serialize(globalStats))
    file:close()
end

-- ===== ПЕРЕМЕННЫЕ =====
local owner = nil
local sessions = {}
local markets = {}
local SESSION_TIMEOUT = 31536000
local marketConnected = false
local logBuffer = {}
local shopPaused = false
local adminMode = false
local adminPlayerList = {}
local adminScroll = 0
local selectedAdminIndex = 1
local adminViewHeight = 20
local editBalanceMode = false
local editingPlayer = nil
local editInput = ""
local addAdminMode = false
local addAdminInput = ""
local addItemMode = false
local addItemFields = { internal = "", display = "", price_coin = "", price_ema = "0", damage = "0" }
local addItemCurrentField = 1
local addItemFieldNames = { "internal", "display", "price_coin", "price_ema", "damage" }
local addItemResponse = nil
local addItemResponseTimer = nil
local sellHistory = {}
local MAX_SELL_HISTORY = 20
local ACTIVITY_SIZE = 60
local activityBuffer = {}
for i=1, ACTIVITY_SIZE do activityBuffer[i] = 0 end
local activityIndex = 0
local screenW, screenH = 80, 25
local colX = {5, 30, 55, 80}
local colWidth = 25
local logStartY = 20
local maxLogLines = 14
local drawing = false
local lastUpdateId = 0

local function updateScreenSize()
    local w, h = gpu.getResolution()
    if w > 200 then w = 200 end
    if w < 80 then w = 80 end
    if h < 15 then h = 15 end
    screenW, screenH = w, h
    local usable = screenW - 8
    colWidth = math.max(12, math.floor(usable / 4))
    colX = {4, 4 + colWidth, 4 + colWidth * 2, 4 + colWidth * 3}
    logStartY = math.min(18, screenH - 5)
    maxLogLines = screenH - logStartY - 3
    if maxLogLines < 3 then maxLogLines = 3 end
    adminViewHeight = screenH - 8
    if adminViewHeight < 3 then adminViewHeight = 3 end
end

local function addActivity()
    activityIndex = activityIndex % ACTIVITY_SIZE + 1
    activityBuffer[activityIndex] = 0
end
event.timer(60, addActivity, math.huge)

local function recordTransaction()
    if activityBuffer[activityIndex] then
        activityBuffer[activityIndex] = activityBuffer[activityIndex] + 1
    end
end

function addLog(text, fg)
    table.insert(logBuffer, {text = text, color = fg or ansi.white})
    while #logBuffer > 200 do table.remove(logBuffer, 1) end
end

local function log(level, msg, emoji)
    local color = ansi.white
    if level == "INFO" then color = ansi.green
    elseif level == "WARN" then color = ansi.yellow
    elseif level == "ERROR" then color = ansi.red
    elseif level == "SUCCESS" then color = ansi.green
    elseif level == "IMPORTANT" then color = ansi.magenta end
    
    local prefix = ""
    if emoji then prefix = emoji .. " " end
    
    addLog("[" .. getRealTimeString() .. "] " .. prefix .. msg, color)
    
    if level == "IMPORTANT" or level == "SUCCESS" or level == "WARN" then
        local logFile = io.open("/home/server_events.log", "a")
        if logFile then
            logFile:write("[" .. getRealDateTimeString() .. "] " .. prefix .. msg .. "\n")
            logFile:close()
        end
    end
end

local function logIncoming(from, msg)
    local importantOps = {
        ["enter"] = true,
        ["sell"] = true,
        ["buy"] = true,
        ["agree"] = true,
        ["report"] = true,
        ["add_feedback"] = true,
        ["get_feedbacks"] = true
    }
    
    if importantOps[msg.op] then
        if msg.op == "enter" then
            if msg.name and msg.name ~= "" then
                log("INFO", "👤 Вход игрока: " .. msg.name)
            end
        elseif msg.op == "sell" then
            log("SUCCESS", "💰 Продажа от " .. msg.name .. ": " .. (msg.item or "?") .. " x" .. (msg.qty or 0))
        elseif msg.op == "buy" then
            log("SUCCESS", "🛒 Покупка от " .. msg.name .. ": " .. (msg.item or "?") .. " x" .. (msg.qty or 0))
        elseif msg.op == "agree" then
            log("IMPORTANT", "📝 Соглашение принято: " .. msg.name)
        elseif msg.op == "report" then
            log("WARN", "📩 Репорт от " .. msg.name)
        elseif msg.op == "add_feedback" then
            log("INFO", "📝 Отзыв от " .. msg.name)
        elseif msg.op == "get_feedbacks" then
            log("INFO", "📋 Запрос отзывов от " .. msg.name)
        end
    end
end

local function updateAdminPlayerList()
    adminPlayerList = {}
    for name, data in pairs(players) do
        table.insert(adminPlayerList, {name=name, data=data})
    end
    table.sort(adminPlayerList, function(a,b) return a.name < b.name end)
end

local function broadcastUpdate()
    if next(markets) == nil then
        addLog("Нет подключённых маркетов для обновления", ansi.red)
        return 0
    end
    local sent = 0
    for addr, _ in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="update_market"}))
        sent = sent + 1
    end
    log("SUCCESS", "Обновление отправлено " .. sent .. " терминалам")
    return sent
end

local function broadcastKill()
    if next(markets) == nil then
        addLog("Нет подключённых маркетов для завершения", ansi.red)
        return 0
    end
    local sent = 0
    for addr, _ in pairs(markets) do
        modem.send(addr, 0xffef, serialization.serialize({op="kill_market"}))
        sent = sent + 1
    end
    log("WARN", "Команда завершения отправлена " .. sent .. " терминалам")
    return sent
end

local function drawAdminPanel()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    setColor(ansi.white)
    fill(1, 1, screenW, 1, "─")
    fill(1, screenH, screenW, 1, "─")
    for y=2, screenH-1 do
        gotoxy(1, y) io.write("│")
        gotoxy(screenW, y) io.write("│")
    end
    gotoxy(1,1) io.write("┌"..string.rep("─", screenW-2).."┐")
    gotoxy(1,screenH) io.write("└"..string.rep("─", screenW-2).."┘")
    resetColor()

    setColor(ansi.bg_blue, ansi.white)
    fill(1, 2, screenW, 1, " ")
    gotoxy(1, 2)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKET")
    if shopPaused then title = title .. " [ПАУЗА]" end
    io.write(title .. string.rep(" ", screenW - #title))
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(1, 3)
    io.write(string.rep("=", screenW))
    resetColor()

    local startIdx = adminScroll + 1
    local endIdx = math.min(#adminPlayerList, adminScroll + adminViewHeight)
    setColor(ansi.yellow)

    resetColor()

    for i=startIdx, endIdx do
        local ply = adminPlayerList[i]
        local isPlayerAdmin = isAdmin(ply.name)
        local bannedStr = ply.data.banned and " [ЗАБАНЕН]" or ""
        local adminStr = isPlayerAdmin and " [АДМИН]" or ""
        local line = string.format("%-20s | Coin: %8.2f ₵ | ЭМЫ: %8.2f ۞ | Транз: %d%s%s",
            ply.name, ply.data.balance or 0, ply.data.emaBalance or 0, ply.data.transactions or 0, bannedStr, adminStr)
        if #line > screenW - 4 then line = line:sub(1, screenW-4) end
        local y = 4 + (i - startIdx)
        local color = ansi.white
        if isPlayerAdmin then color = ansi.green end
        if ply.data.banned then color = ansi.red end
        setColor((i == selectedAdminIndex) and ansi.bg_blue or color, (i == selectedAdminIndex) and ansi.white or nil)
        gotoxy(2, y)
        io.write(line)
        resetColor()
    end

    setColor(ansi.cyan)
    gotoxy(2, screenH-2)
    io.write("BAN: D | RESET: R | PAUSE: P | EDIT BALANCE: E | ADD ITEM: B | ADD ADMIN: + | REMOVE ADMIN: - | SCROLL: ↑↓ | U - UPDATE | K - KILL MARKET")
    resetColor()
    io.flush()
    drawing = false
end

local function drawAddAdminWindow()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    local w = 60
    local h = 10
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    setColor(ansi.white)
    fill(x, y, w, h, " ")
    setColor(ansi.bg_black, ansi.white)
    for i = 0, h-1 do
        gotoxy(x, y+i) io.write("│")
        gotoxy(x+w-1, y+i) io.write("│")
    end
    fill(x+1, y, w-2, 1, "─")
    fill(x+1, y+h-1, w-2, 1, "─")
    setColor(ansi.bg_blue, ansi.white)
    fill(x+2, y, w-4, 1, " ")
    gotoxy(x+2, y) io.write(" ДОБАВЛЕНИЕ АДМИНИСТРАТОРА ")
    resetColor()

    setColor(ansi.yellow)
    gotoxy(x+2, y+2) io.write("Текущие админы: " .. table.concat(admins, ", "))
    gotoxy(x+2, y+3) io.write(string.rep("─", w-4))
    resetColor()

    setColor(ansi.cyan)
    gotoxy(x+2, y+4) io.write("Введите ник игрока для добавления в админы: ")
    setColor(ansi.white)
    gotoxy(x+2, y+5)
    io.write(string.rep(" ", w-4))
    gotoxy(x+2, y+5)
    io.write(addAdminInput .. "_")
    resetColor()

    setColor(ansi.white)
    gotoxy(x+2, y+7) io.write("Enter - добавить | Esc - отмена | ] - выход")
    resetColor()
    io.flush()
    drawing = false
end

local function drawEditBalanceWindow()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    local w = 60
    local h = 10
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    setColor(ansi.white)
    fill(x, y, w, h, " ")
    setColor(ansi.bg_black, ansi.white)
    for i = 0, h-1 do
        gotoxy(x, y+i) io.write("│")
        gotoxy(x+w-1, y+i) io.write("│")
    end
    fill(x+1, y, w-2, 1, "─")
    fill(x+1, y+h-1, w-2, 1, "─")
    setColor(ansi.bg_blue, ansi.white)
    fill(x+2, y, w-4, 1, " ")
    gotoxy(x+2, y) io.write(" РЕДАКТИРОВАНИЕ БАЛАНСА ")
    resetColor()

    setColor(ansi.yellow)
    gotoxy(x+2, y+2) io.write("Игрок: " .. editingPlayer.name)
    gotoxy(x+2, y+3) io.write("Текущий баланс Coin: " .. string.format("%.2f", editingPlayer.data.balance) .. " ₵")
    gotoxy(x+2, y+4) io.write("Текущий баланс ЭМЫ: " .. string.format("%.2f", editingPlayer.data.emaBalance or 0) .. " ۞")
    gotoxy(x+2, y+5) io.write(string.rep("─", w-4))
    resetColor()

    setColor(ansi.cyan)
    gotoxy(x+2, y+6) io.write("Введите новую сумму (Coin + ЭМЫ через пробел, например \"100 50\"): ")
    setColor(ansi.white)
    gotoxy(x+2, y+7)
    io.write(string.rep(" ", w-4))
    gotoxy(x+2, y+7)
    io.write(editInput .. "_")
    resetColor()

    setColor(ansi.white)
    gotoxy(x+2, y+8) io.write("Enter - подтвердить | Esc - отмена | ] - выход")
    resetColor()
    io.flush()
    drawing = false
end

local function drawAddItemForm()
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()

    local w = 70
    local h = 15
    local x = math.floor((screenW - w) / 2)
    local y = math.floor((screenH - h) / 2)

    setColor(ansi.white)
    fill(x, y, w, h, " ")
    setColor(ansi.bg_black, ansi.white)
    for i = 0, h-1 do
        gotoxy(x, y+i) io.write("│")
        gotoxy(x+w-1, y+i) io.write("│")
    end
    fill(x+1, y, w-2, 1, "─")
    fill(x+1, y+h-1, w-2, 1, "─")
    setColor(ansi.bg_blue, ansi.white)
    fill(x+2, y, w-4, 1, " ")
    gotoxy(x+2, y) io.write(" ДОБАВЛЕНИЕ ПРЕДМЕТА В МАГАЗИН (покупка) ")
    resetColor()

    local labels = { "Internal Name:", "Display Name:", "Price Coin (число):", "Price Ema (число):", "Damage (0 = без damage):" }
    for i = 1, 5 do
        setColor(ansi.yellow)
        gotoxy(x+3, y+2 + (i-1)*2)
        io.write(labels[i])
        setColor(ansi.cyan)
        gotoxy(x+35, y+2 + (i-1)*2)
        local val = addItemFields[addItemFieldNames[i]]
        local cursor = (addItemCurrentField == i) and "█" or " "
        io.write(val .. cursor)
        resetColor()
    end

    setColor(ansi.white)
    gotoxy(x+3, y+13)
    io.write("Enter - далее / отправить | ] - отмена")
    io.flush()
    drawing = false
end

function drawInterface()
    if adminMode or editBalanceMode or addItemMode or addAdminMode then return end
    if drawing then return end
    drawing = true
    io.write(ansi.hide_cursor .. ansi.clear)
    updateScreenSize()
    
    setColor(ansi.bg_blue, ansi.white)
    fill(1, 2, screenW, 1, " ")
    gotoxy(1, 2)
    local title = " PIM MARKET SERVER – СТАТУС: " .. (marketConnected and "АКТИВЕН" or "ОЖИДАНИЕ MARKET")
    if shopPaused then title = title .. " [ПАУЗА]" end
    io.write(title .. string.rep(" ", screenW - #title))
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(1, 3)
    io.write("Время: " .. getRealTimeString() .. "  До сброса репортов: " .. timeToMidnight())
    local activeCount = 0
    for _, v in pairs(sessions) do
        if type(v) == "table" and v.token then activeCount = activeCount + 1 end
    end
    gotoxy(screenW - 25, 3)
    io.write("Активных сессий: " .. activeCount)
    resetColor()
    
    setColor(ansi.white)
    fill(1, 4, screenW, 1, "─")
    resetColor()
    
    local titles = {"👥 ИГРОКИ", "📦 ПРОДАЖИ", "🔒 БЕЗОПАСНОСТЬ", "📊 СТАТИСТИКА"}
    setColor(ansi.bold, ansi.yellow)
    for i=1,4 do
        gotoxy(colX[i], 5)
        io.write(titles[i] .. string.rep(" ", colWidth - #titles[i]))
    end
    resetColor()
    
    setColor(ansi.green)
    local playerList = {}
    for name, s in pairs(sessions) do
        if type(s) == "table" and s.token then table.insert(playerList, name) end
    end
    local rowsAvailable = logStartY - 7
    for i=1, math.min(rowsAvailable, #playerList) do
        gotoxy(colX[1], 5+i)
        local name = playerList[i]
        if #name > colWidth then name = name:sub(1, colWidth) end
        local isPlayerAdmin = isAdmin(name)
        if isPlayerAdmin then
            io.write(ansi.green .. "★ " .. name .. ansi.reset)
        else
            io.write(name .. string.rep(" ", colWidth - #name))
        end
    end
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(colX[2], 6)
    io.write("Последние продажи:")
    for i = 1, math.min(rowsAvailable, #sellHistory) do
        local entry = sellHistory[#sellHistory - i + 1]
        if entry then
            gotoxy(colX[2], 6 + i)
            local line = entry.name .. ": " .. entry.item .. " x" .. entry.qty
            if unicode.len(line) > colWidth then
                line = unicode.sub(line, 1, colWidth)
            end
            io.write(line)
        end
    end
    resetColor()
    
    setColor(ansi.magenta)
    gotoxy(colX[3], 6)
    io.write("Лимит сессии: " .. SESSION_TIMEOUT .. " сек")
    local playersCount = 0
    for _ in pairs(players) do playersCount = playersCount + 1 end
    gotoxy(colX[3], 7)
    io.write("Игроков в БД: " .. playersCount)
    gotoxy(colX[3], 9)
    io.write("Активность (последние 60 мин):")
    local graphWidth = colWidth - 2
    local maxVal = 1
    for i=1, ACTIVITY_SIZE do
        if activityBuffer[i] > maxVal then maxVal = activityBuffer[i] end
    end
    for i=1, math.min(ACTIVITY_SIZE, graphWidth) do
        local val = activityBuffer[(activityIndex - i + ACTIVITY_SIZE) % ACTIVITY_SIZE + 1] or 0
        local height = math.ceil((val / (maxVal+0.01)) * 3)
        gotoxy(colX[3]+i-1, 13 - height)
        setColor(ansi.green)
        io.write("█")
        resetColor()
    end
    resetColor()
    
    setColor(ansi.yellow)
    gotoxy(colX[4], 6)
    io.write("Репортов: " .. globalStats.totalReports)
    gotoxy(colX[4], 7)
    io.write("Покупок: " .. globalStats.totalBuys)
    gotoxy(colX[4], 8)
    io.write("Продаж: " .. globalStats.totalSells)
    resetColor()
    
    setColor(ansi.white)
    gotoxy(1, screenH-1)
    io.write("R - обновить | P - Пауза | A - Админ-панель")
    resetColor()
    
    setColor(ansi.cyan)
    gotoxy(1, logStartY-1)
    io.write(string.rep("=", screenW))
    resetColor()
    for i=1, maxLogLines do
        local entry = logBuffer[#logBuffer - maxLogLines + i]
        if entry then
            setColor(entry.color)
            gotoxy(1, logStartY + i - 1)
            local line = entry.text
            if #line > screenW - 1 then line = line:sub(1, screenW-1) end
            io.write(line .. string.rep(" ", screenW - #line))
            resetColor()
        end
    end
    io.flush()
    drawing = false
end

local function getOrCreatePlayer(name)
    if not players[name] then
        players[name] = {
            balance = 0.0,
            emaBalance = 0.0,
            transactions = 0,
            regDate = getRealDateTimeString(),
            agreed = false,
            banned = false,
            hasFeedback = false
        }
        saveDB()
        log("SUCCESS", "🎮 Новый игрок: " .. name)
    end
    return players[name]
end

local function validateSession(name, token)
    local s = sessions[name]
    return s and s.token == token and os.time() - (s.lastAction or 0) < SESSION_TIMEOUT
end

-- ============================================
-- TELEGRAM ФУНКЦИИ
-- ============================================

local function sendTelegram(text, keyboard)
    if not text then return false end
    
    -- Ограничим длину текста
    if #text > 4000 then
        text = text:sub(1, 3997) .. "..."
    end
    
    local encodedText = text:gsub(" ", "%%20"):gsub("\n", "%%0A"):gsub("#", "%%23"):gsub("&", "%%26")
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/sendMessage"
    local postData = "chat_id=" .. TELEGRAM_CHAT_ID .. "&text=" .. encodedText
    
    if keyboard then 
        -- Отправляем клавиатуру как есть
        postData = postData .. "&reply_markup=" .. keyboard
    end
    
    writeDebugLog("sendTelegram: отправка запроса, длина postData: " .. #postData)
    
    local success, result = pcall(function()
        local request = internet.request(url, postData, {
            ["Content-Type"] = "application/x-www-form-urlencoded"
        })
        
        if request then
            local response = ""
            while true do
                local chunk = request()
                if not chunk then break end
                response = response .. chunk
            end
            writeDebugLog("sendTelegram: ответ: " .. (response:sub(1, 200) or "нет ответа"))
            if response and response:find('"ok":true') then
                writeDebugLog("sendTelegram: успешно отправлено")
                return true
            elseif response and response:find('"ok":false') then
                writeDebugLog("sendTelegram: ОШИБКА API: " .. response)
                return false
            end
            return true
        end
        return false
    end)
    
    if not success then
        writeDebugLog("sendTelegram: ошибка: " .. tostring(result))
        return false
    end
    
    return result
end

local function getMainKeyboard()
    return '{"keyboard":[["Игроки","Статистика"],["Баланс","Админы"],["Добавить предмет","Обновить"],["Пауза","Закрыть"]],"resize_keyboard":true}'
end

local function getPlayersKeyboard(playersList)
    local keyboard = '{"keyboard":['
    local row = {}
    for i, name in ipairs(playersList) do
        table.insert(row, '"' .. name .. '"')
        if #row == 2 then
            keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
            row = {}
        end
        if i >= 10 then break end
    end
    if #row > 0 then
        keyboard = keyboard .. '[' .. table.concat(row, ",") .. '],'
    end
    keyboard = keyboard .. '["Назад"]],"resize_keyboard":true}'
    return keyboard
end

local function getReportsKeyboard()
    return '{"keyboard":[["Отзывы"],["Назад"]],"resize_keyboard":true}'
end

local function getFeedbackDeleteKeyboard(feedbackId)
    return '{"keyboard":[["Удалить ' .. feedbackId .. '"],["Назад"]],"resize_keyboard":true}'
end

local function getAdminKeyboard()
    return '{"keyboard":[["Добавить админа","Удалить админа"],["Назад"]],"resize_keyboard":true}'
end

-- Хранилище для отзывов
local feedbacks = {}
if filesystem.exists("/home/feedbacks.db") then
    local file = io.open("/home/feedbacks.db", "r")
    if file then
        local data = file:read("*a")
        file:close()
        if data and #data > 0 then
            local ok, result = pcall(serialization.unserialize, data)
            if ok and type(result) == "table" then
                feedbacks = result
            end
        end
    end
end

local function saveFeedbacks()
    local file = io.open("/home/feedbacks.db", "w")
    if file then
        file:write(serialization.serialize(feedbacks))
        file:close()
        return true
    end
    return false
end

local function handleTelegramCommand(text)
    writeDebugLog("handleTelegramCommand: получен текст: " .. tostring(text))
    
    if not text or text == "" then return end
    
    if text == "/start" or text == "Назад" then
        writeDebugLog("handleTelegramCommand: команда /start или Назад")
        sendTelegram("🛒 PIM Market Admin\n\nВыберите действие:", getMainKeyboard())
        return
    end
    
    if text == "Игроки" then
        writeDebugLog("handleTelegramCommand: команда Игроки")
        local msg = "👥 Список игроков:\n═══════════════════\n"
        local playersKeys = {}
        for name, data in pairs(players) do
            msg = msg .. (#playersKeys + 1) .. ". " .. name
            if data.banned then msg = msg .. " 🚫" end
            msg = msg .. "\n"
            table.insert(playersKeys, name)
            if #playersKeys >= 10 then
                msg = msg .. "\n... и ещё " .. (#players - 10) .. " игроков"
                break
            end
        end
        if #playersKeys == 0 then msg = msg .. "Нет игроков" end
        sendTelegram(msg, getPlayersKeyboard(playersKeys))
        return
    end
    
    if text == "Статистика" then
        writeDebugLog("handleTelegramCommand: команда Статистика")
        local totalPlayers = 0
        local totalTransactions = 0
        local bannedCount = 0
        for _, p in pairs(players) do
            totalPlayers = totalPlayers + 1
            totalTransactions = totalTransactions + (p.transactions or 0)
            if p.banned then bannedCount = bannedCount + 1 end
        end
        local msg = "📊 Статистика магазина\n═══════════════════\n"
        msg = msg .. "👥 Игроков: " .. totalPlayers .. "\n"
        msg = msg .. "💰 Транзакций: " .. totalTransactions .. "\n"
        msg = msg .. "🚫 Забанов: " .. bannedCount .. "\n"
        msg = msg .. "👑 Админов: " .. #admins .. "\n"
        msg = msg .. "⏸️ Пауза: " .. (shopPaused and "🔴 Включена" or "🟢 Выключена") .. "\n"
        sendTelegram(msg, getReportsKeyboard())
        return
    end
    
    if text == "Отзывы" then
        writeDebugLog("handleTelegramCommand: команда Отзывы")
        if #feedbacks == 0 then
            sendTelegram("📝 Отзывов пока нет", getMainKeyboard())
            return
        end
        local msg = "📝 Отзывы:\n═══════════════════\n"
        for i, fb in ipairs(feedbacks) do
            msg = msg .. i .. ". " .. fb.name .. ":\n   " .. fb.text .. "\n   [" .. (fb.time or "без даты") .. "]\n"
            msg = msg .. "───────────────────\n"
        end
        sendTelegram(msg, '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    if text:match("^Удалить ") then
        writeDebugLog("handleTelegramCommand: команда Удалить")
        local id = tonumber(text:match("Удалить (%d+)"))
        if id and id >= 1 and id <= #feedbacks then
            table.remove(feedbacks, id)
            saveFeedbacks()
            sendTelegram("✅ Отзыв удален!", getMainKeyboard())
        else
            sendTelegram("❌ Отзыв не найден", getMainKeyboard())
        end
        return
    end
    
    if text == "Админы" then
        writeDebugLog("handleTelegramCommand: команда Админы")
        local msg = "👑 Управление администраторами\n═══════════════════\n"
        msg = msg .. "Текущие админы:\n"
        for i, name in ipairs(admins) do
            msg = msg .. i .. ". " .. name .. "\n"
        end
        sendTelegram(msg, getAdminKeyboard())
        return
    end
    
    if text == "Добавить админа" then
        writeDebugLog("handleTelegramCommand: команда Добавить админа")
        sendTelegram("👑 Введите ник игрока для добавления в администраторы:", '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    if text == "Удалить админа" then
        writeDebugLog("handleTelegramCommand: команда Удалить админа")
        sendTelegram("👑 Введите ник игрока для удаления из администраторов:", '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    if text ~= "Назад" and text ~= "Игроки" and text ~= "Статистика" and text ~= "Админы" and text ~= "Пауза" and text ~= "Обновить" and text ~= "Закрыть" and text ~= "Добавить предмет" and text ~= "Баланс" and text ~= "Добавить админа" and text ~= "Удалить админа" and text ~= "Отзывы" and not text:match("^Удалить ") and not text:match("^/additem") and not text:match("^/") then
        writeDebugLog("handleTelegramCommand: обработка ника: " .. text)
        local found = false
        for name, data in pairs(players) do
            if name:lower() == text:lower() then
                local msg = "👤 " .. name .. "\n═══════════════════\n"
                msg = msg .. "💰 Coina: " .. string.format("%.2f", data.balance or 0) .. " ₵\n"
                msg = msg .. "💚 ЭМЫ: " .. string.format("%.2f", data.emaBalance or 0) .. " ۞\n"
                msg = msg .. "📊 Транзакций: " .. (data.transactions or 0) .. "\n"
                if data.banned then 
                    msg = msg .. "🚫 Забанен\n"
                else
                    msg = msg .. "✅ Активен\n"
                end
                msg = msg .. "\nВыберите действие:"
                sendTelegram(msg, '{"keyboard":[["Изменить баланс","Бан/Разбан"],["Назад"]],"resize_keyboard":true}')
                found = true
                return
            end
        end
        
        if not found then
            if not players[text] and not isAdmin(text) then
                if addAdmin(text) then
                    sendTelegram("👑 " .. text .. " добавлен в администраторы!", getMainKeyboard())
                else
                    sendTelegram("❌ Ошибка: " .. text .. " уже является администратором", getMainKeyboard())
                end
                return
            end
            if isAdmin(text) then
                if removeAdmin(text) then
                    sendTelegram("👑 " .. text .. " удален из администраторов!", getMainKeyboard())
                else
                    sendTelegram("❌ Нельзя удалить последнего администратора!", getMainKeyboard())
                end
                return
            end
            sendTelegram("❌ Игрок " .. text .. " не найден!", getMainKeyboard())
        end
        return
    end
    
    if text == "Изменить баланс" then
        writeDebugLog("handleTelegramCommand: команда Изменить баланс")
        sendTelegram("💰 Введите сумму для изменения баланса (Coin + ЭМЫ через пробел, например: 100 50):", '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    if text == "Бан/Разбан" then
        writeDebugLog("handleTelegramCommand: команда Бан/Разбан")
        sendTelegram("🔒 Введите ник игрока для бана/разбана:", '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    if text == "Пауза" then
        writeDebugLog("handleTelegramCommand: команда Пауза")
        shopPaused = not shopPaused
        for addr in pairs(markets) do
            modem.send(addr, 0xffef, serialization.serialize({op="shop_paused", paused=shopPaused}))
        end
        sendTelegram("⏸️ Магазин " .. (shopPaused and "ПРИОСТАНОВЛЕН" or "ВОЗОБНОВЛЕН"), getMainKeyboard())
        return
    end
    
    if text == "Обновить" then
        writeDebugLog("handleTelegramCommand: команда Обновить")
        local sent = broadcastUpdate()
        sendTelegram("✅ Обновление отправлено " .. sent .. " терминалам!", getMainKeyboard())
        return
    end
    
    if text == "Закрыть" then
        writeDebugLog("handleTelegramCommand: команда Закрыть")
        local sent = broadcastKill()
        sendTelegram("🚫 Магазин закрыт! " .. sent .. " терминалов отключены.", getMainKeyboard())
        return
    end
    
    if text == "Добавить предмет" then
        writeDebugLog("handleTelegramCommand: команда Добавить предмет")
        local msg = "📦 Добавление предмета\n\n"
        msg = msg .. "Отправьте команду:\n"
        msg = msg .. "/additem internalName displayName цена_coin цена_ema damage\n\n"
        msg = msg .. "📌 Пример:\n"
        msg = msg .. "/additem minecraft:diamond Алмаз 10 5 0\n\n"
        msg = msg .. "Где damage = 0 если не нужен"
        sendTelegram(msg, getMainKeyboard())
        return
    end
    
    if text:match("^/additem") then
        writeDebugLog("handleTelegramCommand: команда /additem")
        local parts = {}
        for part in text:gmatch("%S+") do table.insert(parts, part) end
        if #parts >= 5 then
            local internal = parts[2]
            local display = parts[3]
            local coin = tonumber(parts[4]) or 0
            local ema = tonumber(parts[5]) or 0
            local damage = tonumber(parts[6]) or 0
            if coin < 0 then coin = 0 end
            if ema < 0 then ema = 0 end
            if damage < 0 then damage = 0 end
            if coin == 0 and ema == 0 then
                sendTelegram("❌ Ошибка! Цена не может быть нулевой", getMainKeyboard())
                return
            end
            local buyItems = {}
            if filesystem.exists("/home/buy_items.lua") then
                buyItems = dofile("/home/buy_items.lua") or {}
            end
            table.insert(buyItems, { internalName = internal, displayName = display, price_coin = coin, price_ema = ema, damage = damage })
            local file = io.open("/home/buy_items.lua", "w")
            file:write("return " .. serialization.serialize(buyItems))
            file:close()
            broadcastUpdate()
            local msg = "✅ Предмет добавлен!\n📦 " .. display .. "\n💰 " .. coin .. " ₵\n💚 " .. ema .. " ۞\n🔢 Damage: " .. damage
            sendTelegram(msg, getMainKeyboard())
        else
            sendTelegram("❌ Ошибка!\nФормат: /additem internalName displayName цена_coin цена_ema damage", getMainKeyboard())
        end
        return
    end
    
    if text == "Баланс" then
        writeDebugLog("handleTelegramCommand: команда Баланс")
        sendTelegram("💰 Введите имя игрока для просмотра баланса:", '{"keyboard":[["Назад"]],"resize_keyboard":true}')
        return
    end
    
    writeDebugLog("handleTelegramCommand: неизвестная команда: " .. text)
end

-- ============================================
-- ФУНКЦИЯ ПРОВЕРКИ ОБНОВЛЕНИЙ TELEGRAM
-- ============================================
local function checkTelegramUpdates()
    writeDebugLog("checkTelegramUpdates: начат")
    
    local f = io.open("/tmp/last_id.txt", "r")
    if f then
        local data = f:read("*a")
        f:close()
        if data and #data > 0 then
            lastUpdateId = tonumber(data) or 0
            writeDebugLog("checkTelegramUpdates: lastUpdateId = " .. lastUpdateId)
        end
    end
    
    local url = "https://api.telegram.org/bot" .. TELEGRAM_TOKEN .. "/getUpdates?limit=5"
    if lastUpdateId > 0 then
        url = url .. "&offset=" .. (lastUpdateId + 1)
    end
    
    writeDebugLog("checkTelegramUpdates: запрос к API")
    
    local success, response = pcall(function()
        return internet.request(url)
    end)
    
    if not success or type(response) ~= "table" then
        writeDebugLog("checkTelegramUpdates: ошибка запроса")
        return
    end
    
    local responseData = ""
    while true do
        local chunk = response()
        if not chunk then break end
        responseData = responseData .. chunk
    end
    
    writeDebugLog("checkTelegramUpdates: получен ответ, длина: " .. #responseData)
    
    -- Парсим update_id
    local maxId = lastUpdateId
    for updateId in responseData:gmatch('"update_id":(%d+)') do
        local id = tonumber(updateId)
        if id and id > maxId then
            maxId = id
        end
    end
    
    -- Парсим тексты
    local hasUpdates = false
    for text in responseData:gmatch('"text":"([^"]+)"') do
        hasUpdates = true
        local decoded = text:gsub("\\u([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])", function(hex)
            return unicode.char(tonumber(hex, 16))
        end)
        writeDebugLog("checkTelegramUpdates: команда: " .. decoded)
        local ok, err = pcall(handleTelegramCommand, decoded)
        if not ok then
            writeDebugLog("checkTelegramUpdates: ОШИБКА обработки: " .. tostring(err))
        end
    end
    
    if not hasUpdates then
        writeDebugLog("checkTelegramUpdates: новых команд нет")
    end
    
    if maxId > lastUpdateId then
        lastUpdateId = maxId
        local f2 = io.open("/tmp/last_id.txt", "w")
        if f2 then
            f2:write(lastUpdateId)
            f2:close()
            writeDebugLog("checkTelegramUpdates: lastUpdateId сохранен: " .. lastUpdateId)
        end
    end
end

-- ===== ВЕБ-АДМИН ОБРАБОТЧИК =====
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
            if msg.coin ~= nil then player.balance = msg.coin end
            if msg.ema ~= nil then player.emaBalance = msg.ema end
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
            local buyItems = {}
            if filesystem.exists("/home/buy_items.lua") then
                buyItems = dofile("/home/buy_items.lua") or {}
            end
            table.insert(buyItems, { internalName = msg.internal, displayName = msg.display, price_coin = msg.price_coin or 0, price_ema = msg.price_ema or 0, damage = msg.damage or 0 })
            local file = io.open("/home/buy_items.lua", "w")
            file:write("return " .. serialization.serialize(buyItems))
            file:close()
            broadcastUpdate()
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="add_item", success=true}))
        end
        
    elseif msg.command == "get_admins" then
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="admins", admins=admins}))
        
    elseif msg.command == "add_admin" then
        if msg.name and not isAdmin(msg.name) then
            addAdmin(msg.name)
            modem.send(from, 0xffef, serialization.serialize({op="web_response", command="add_admin", success=true}))
        end
        
    elseif msg.command == "remove_admin" then
        if msg.name and #admins > 1 then
            removeAdmin(msg.name)
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
            if p.banned then bannedCount = bannedCount + 1 end
        end
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="stats", totalPlayers=totalPlayers, totalTransactions=totalTransactions, bannedCount=bannedCount, adminsCount=#admins, shopPaused=shopPaused}))
        
    elseif msg.command == "update_market" then
        broadcastUpdate()
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="update", success=true}))
        
    elseif msg.command == "kill_market" then
        broadcastKill()
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="kill", success=true}))
        
    elseif msg.command == "get_logs" then
        local logs = {}
        for i = math.max(1, #logBuffer - 50), #logBuffer do
            table.insert(logs, logBuffer[i])
        end
        modem.send(from, 0xffef, serialization.serialize({op="web_response", command="logs", logs=logs}))
    end
end

-- ===== ОСНОВНЫЕ ОБРАБОТЧИКИ =====

local function handleKey(key, char, player)
    local isPlayerAdmin = isAdmin(player)

    if addAdminMode then
        if char == 27 or char == 93 then
            addAdminMode = false
            addAdminInput = ""
            drawAdminPanel()
            return
        elseif char == 13 then
            if addAdminInput ~= "" then
                if addAdmin(addAdminInput) then
                    log("SUCCESS", "👑 " .. addAdminInput .. " добавлен в администраторы")
                    updateAdminPlayerList()
                    drawAdminPanel()
                else
                    addLog("Ошибка: игрок уже является администратором", ansi.red)
                end
            end
            addAdminMode = false
            addAdminInput = ""
            return
        elseif char == 8 then
            addAdminInput = addAdminInput:sub(1, -2)
            drawAddAdminWindow()
            return
        elseif char >= 32 then
            local c = unicode.char(char)
            if c:match("[%w_]") then
                addAdminInput = addAdminInput .. c
                drawAddAdminWindow()
            end
            return
        end
        return
    end

    if addItemMode then
        if char == 27 or char == 93 then
            addItemMode = false
            addItemResponse = nil
            if adminMode then drawAdminPanel() else drawInterface() end
            return
        elseif char == 13 then
            if addItemCurrentField < 5 then
                addItemCurrentField = addItemCurrentField + 1
                drawAddItemForm()
                return
            else
                local priceCoin = tonumber(addItemFields.price_coin)
                local priceEma = tonumber(addItemFields.price_ema)
                if not priceCoin then priceCoin = 0 end
                if not priceEma then priceEma = 0 end
                if priceCoin < 0 then priceCoin = 0 end
                if priceEma < 0 then priceEma = 0 end
                local damage = tonumber(addItemFields.damage) or 0
                if damage < 0 then damage = 0 end
                if addItemFields.internal == "" or addItemFields.display == "" then
                    addLog("Ошибка: internalName и displayName не могут быть пустыми", ansi.red)
                    addItemMode = false
                    drawAdminPanel()
                    return
                end
                if priceCoin == 0 and priceEma == 0 then
                    addLog("Ошибка: цена не может быть нулевой (хотя бы одна валюта >0)", ansi.red)
                    addItemMode = false
                    drawAdminPanel()
                    return
                end

                local data = {
                    op = "add_buy_item",
                    internalName = addItemFields.internal,
                    displayName = addItemFields.display,
                    price_coin = priceCoin,
                    price_ema = priceEma,
                    damage = damage
                }
                
                if next(markets) == nil then
                    addLog("Нет подключённых терминалов market_01", ansi.red)
                else
                    local sent = 0
                    for addr, _ in pairs(markets) do
                        modem.send(addr, 0xffef, serialization.serialize(data))
                        sent = sent + 1
                    end
                    addLog("Отправка предмета на " .. sent .. " терминал(ов)...", ansi.yellow)
                    
                    addItemResponse = nil
                    addItemResponseTimer = os.time()
                    while os.time() - addItemResponseTimer < 5 do
                        event.pull(0.2)
                        if addItemResponse then break end
                    end
                    if addItemResponse and addItemResponse.success then
                        log("SUCCESS", "✅ Предмет добавлен: " .. addItemFields.display)
                        for addr, _ in pairs(markets) do
                            modem.send(addr, 0xffef, serialization.serialize({op = "reload_buy_items"}))
                        end
                        addLog("Отправлена команда перезагрузки на все терминалы", ansi.green)
                    else
                        addLog("Внимание: не получен ответ от терминалов, но предмет мог быть добавлен.", ansi.yellow)
                    end
                end
                addItemMode = false
                addItemResponse = nil
                if adminMode then drawAdminPanel() else drawInterface() end
                return
            end
        elseif char == 8 then
            local field = addItemFieldNames[addItemCurrentField]
            addItemFields[field] = addItemFields[field]:sub(1, -2)
            drawAddItemForm()
            return
        elseif char >= 32 then
            local c = unicode.char(char)
            local field = addItemFieldNames[addItemCurrentField]
            if field == "price_coin" or field == "price_ema" or field == "damage" then
                if c:match("%d") or (c == "." and not addItemFields[field]:find("%.")) then
                    addItemFields[field] = addItemFields[field] .. c
                end
            else
                addItemFields[field] = addItemFields[field] .. c
            end
            drawAddItemForm()
            return
        end
        return
    end

    if editBalanceMode then
        if char == 27 or char == 93 then
            editBalanceMode = false
            editingPlayer = nil
            editInput = ""
            drawAdminPanel()
            return
        elseif char == 13 then
            if editInput ~= "" then
                local parts = {}
                for part in editInput:gmatch("%S+") do
                    table.insert(parts, part)
                end
                local coinVal = tonumber(parts[1])
                local emaVal = tonumber(parts[2])
                if coinVal then
                    editingPlayer.data.balance = coinVal
                end
                if emaVal then
                    editingPlayer.data.emaBalance = emaVal
                end
                log("INFO", "📊 Баланс игрока " .. editingPlayer.name .. " изменён: Coin=" .. (coinVal or editingPlayer.data.balance) .. " ₵, ЭМЫ=" .. (emaVal or editingPlayer.data.emaBalance) .. " ۞")
                saveDB()
            end
            editBalanceMode = false
            editingPlayer = nil
            editInput = ""
            drawAdminPanel()
            return
        else
            if (char >= 48 and char <= 57) or char == 32 then
                editInput = editInput .. string.char(char)
            elseif char == 46 then
                if not editInput:find("%.") then
                    editInput = editInput .. "."
                end
            elseif char == 8 then
                editInput = editInput:sub(1, -2)
            end
            drawEditBalanceWindow()
            return
        end
        return  
    end

    if adminMode then
        if not isPlayerAdmin then
            adminMode = false
            drawInterface()
            log("WARN", "Сессия администратора истекла, выход из панели")
            return
        end

        if key == 200 then
            if selectedAdminIndex > 1 then
                selectedAdminIndex = selectedAdminIndex - 1
                if selectedAdminIndex < adminScroll + 1 then
                    adminScroll = math.max(0, selectedAdminIndex - 1)
                end
                drawAdminPanel()
            end
            return
        elseif key == 208 then
            if selectedAdminIndex < #adminPlayerList then
                selectedAdminIndex = selectedAdminIndex + 1
                if selectedAdminIndex > adminScroll + adminViewHeight then
                    adminScroll = selectedAdminIndex - adminViewHeight
                end
                drawAdminPanel()
            end
            return
        end
    end

    local pressed = nil
    if char and char >= 1 and char <= 255 then
        pressed = string.lower(string.char(char))
    end

    if not adminMode then
        if pressed == "a" then
            if isPlayerAdmin then
                adminMode = true
                adminScroll = 0
                selectedAdminIndex = 1
                updateAdminPlayerList()
                log("INFO", "🔐 Админ-панель открыта")
                drawAdminPanel()
            else
                log("WARN", "⚠️ Попытка входа в админ-панель не админом: " .. tostring(player))
            end
            return
        elseif pressed == "p" then
            if isPlayerAdmin then
                shopPaused = not shopPaused
                log("IMPORTANT", "⏸️ Магазин " .. (shopPaused and "приостановлен" or "возобновлён"))
                drawInterface()
            else
                log("WARN", "⚠️ Попытка паузы магазина не админом: " .. tostring(player))
            end
            return
        elseif pressed == "r" then
            drawInterface()
            return
        end
    else
        if pressed == "p" then
            shopPaused = not shopPaused
            log("IMPORTANT", "⏸️ Магазин " .. (shopPaused and "приостановлен" or "возобновлён"))
            drawAdminPanel()
            return
        elseif pressed == "a" then
            adminMode = false
            log("INFO", "🔐 Выход из админ-панели")
            drawInterface()
            return
        elseif pressed == "d" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.banned = not ply.data.banned
                saveDB()
                log("IMPORTANT", "🚫 Игрок " .. ply.name .. (ply.data.banned and " ЗАБАНЕН" or " РАЗБАНЕН"))
                drawAdminPanel()
            end
            return
        elseif pressed == "r" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                ply.data.transactions = 0
                ply.data.balance = 0
                ply.data.emaBalance = 0
                saveDB()
                log("INFO", "📊 Статистика игрока " .. ply.name .. " сброшена")
                drawAdminPanel()
            end
            return
        elseif pressed == "e" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                editingPlayer = ply
                editInput = ""
                editBalanceMode = true
                drawEditBalanceWindow()
            end
            return
        elseif pressed == "b" then
            addItemMode = true
            addItemFields = { internal = "", display = "", price_coin = "", price_ema = "0", damage = "0" }
            addItemCurrentField = 1
            drawAddItemForm()
            return
        elseif pressed == "+" then
            addAdminMode = true
            addAdminInput = ""
            drawAddAdminWindow()
            return
        elseif pressed == "-" then
            local ply = adminPlayerList[selectedAdminIndex]
            if ply then
                if removeAdmin(ply.name) then
                    log("SUCCESS", "👑 " .. ply.name .. " удалён из администраторов")
                    updateAdminPlayerList()
                    drawAdminPanel()
                else
                    addLog("Нельзя удалить последнего администратора!", ansi.red)
                end
            end
            return
        elseif pressed == "u" then
            broadcastUpdate()
            return
        elseif pressed == "k" then
            broadcastKill()
            return
        end
    end
end

local function handleTouch(x, y, player)
    if not adminMode or editBalanceMode or addItemMode or addAdminMode then return end
    if not isAdmin(player) then return end
    if y >= 4 and y <= 3 + adminViewHeight then
        local lineIndex = y - 4
        local realIndex = adminScroll + lineIndex + 1
        if realIndex >= 1 and realIndex <= #adminPlayerList then
            selectedAdminIndex = realIndex
            drawAdminPanel()
        end
    end
end

-- ============================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================
local function main()
    writeDebugLog("main: функция запущена")
    log("SUCCESS", "🚀 Сервер запущен. Администраторы: " .. table.concat(admins, ", "))
    sendTelegram("🤖 PIM Market Бот запущен!\nНажмите /start для начала работы.", getMainKeyboard())
    drawInterface()

    local lastTelegramCheck = 0
    local telegramCheckInterval = 2

    while true do
        local ev = {event.pull(0.5)}
        local etype = ev[1]

        if os.time() - lastTelegramCheck > telegramCheckInterval then
            lastTelegramCheck = os.time()
            local ok, err = pcall(checkTelegramUpdates)
            if not ok then
                writeDebugLog("main: ОШИБКА checkTelegramUpdates: " .. tostring(err))
                print("❌ Ошибка Telegram: " .. tostring(err))
            end
        end

        if etype == "key_down" then
            local key = ev[4]
            local char = ev[3]
            local player = ev[5]
            handleKey(key, char, player)
        elseif etype == "touch" then
            local x = ev[3]
            local y = ev[4]
            local player = ev[5]
            handleTouch(x, y, player)
        elseif etype == "modem_message" then
            local from = ev[3]
            local raw = ev[6]
            local success, msg = pcall(serialization.unserialize, raw)
            if not success or not msg or type(msg) ~= "table" then
                goto continue
            end

            local last = sessions["__modem_"..from] or 0
            if os.time() - last < 0.5 then
                log("WARN", "Спам от " .. from)
                goto continue
            end
            sessions["__modem_"..from] = os.time()

            logIncoming(from, msg)

            if msg.op == "register" then
                if msg.password ~= ACCESS_PASSWORD then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Неверный пароль"}))
                    log("WARN", "❌ Попытка подключения с неверным паролем от " .. from)
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                marketConnected = true
                if not owner then
                    owner = from
                    log("SUCCESS", "🔐 АДМИН ЗАРЕГИСТРИРОВАН: " .. from)
                end
                if not markets[from] then
                    markets[from] = true
                    log("SUCCESS", "✅ Терминал подключён: " .. from)
                end
                modem.send(from, 0xffef, serialization.serialize({op="welcome", owner=(from==owner), shopPaused=shopPaused}))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "enter" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local playerName = msg.name
                if not playerName or playerName == "" then
                    log("WARN", "❌ Вход без имени от " .. from)
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = getOrCreatePlayer(playerName)
                if player.banned then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Вы забанены"}))
                    log("WARN", "🚫 Забаненный игрок пытается войти: " .. playerName)
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end

                local existingSession = sessions[playerName]
                local token
                if existingSession and os.time() - (existingSession.lastAction or 0) < SESSION_TIMEOUT then
                    token = existingSession.token
                    existingSession.lastAction = os.time()
                else
                    token = tostring(math.floor(math.random() * 900000000 + 100000000))
                    sessions[playerName] = {token = token, lastAction = os.time()}
                    log("SUCCESS", "👤 " .. playerName .. " вошёл в систему")
                end

                modem.send(from, 0xffef, serialization.serialize({
                    op="welcome", status="ok", token=token,
                    balance=player.balance or 0.0,
                    emaBalance=player.emaBalance or 0.0,
                    transactions=player.transactions,
                    regDate=player.regDate,
                    agreed = player.agreed or false,
                    shopPaused = shopPaused
                }))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "getAccount" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "❌ Неверный токен для getAccount от " .. (msg.name or "?"))
                    modem.send(from, 0xffef, serialization.serialize({op="accountData", error = true, message = "Токен устарел"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player then goto continue end
                sessions[msg.name].lastAction = os.time()
                modem.send(from, 0xffef, serialization.serialize({
                    op="accountData",
                    data = {
                        balance = player.balance,
                        emaBalance = player.emaBalance,
                        transactions = player.transactions,
                        regDate = player.regDate,
                        agreed = player.agreed,
                        shopPaused = shopPaused
                    }
                }))
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "sell" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "❌ Неверный токен для sell от " .. (msg.name or "?"))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player or player.banned then goto continue end
                local qty = tonumber(msg.qty) or 0
                local value = tonumber(msg.value) or 0
                local internalName = msg.internalName

                if internalName == "customnpcs:npcMoney" then
                    player.emaBalance = (player.emaBalance or 0) + value
                    log("SUCCESS", "💚 " .. msg.name .. " пополнил ЭМЫ: " .. (msg.item or "?") .. " x" .. qty .. " на " .. string.format("%.2f", value) .. " ۞")
                    sendTelegram("💰 Пополнение!\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. qty .. "\n💚 +" .. string.format("%.2f", value) .. " ۞")
                else
                    player.balance = (player.balance or 0) + value
                    log("SUCCESS", "💰 " .. msg.name .. " пополнил Coina: " .. (msg.item or "?") .. " x" .. qty .. " на " .. string.format("%.2f", value) .. " ₵")
                    sendTelegram("💰 Пополнение!\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. qty .. "\n💰 +" .. string.format("%.2f", value) .. " ₵")
                end
                player.transactions = (player.transactions or 0) + 1
                sessions[msg.name].lastAction = os.time()
                globalStats.totalSells = (globalStats.totalSells or 0) + 1
                saveGlobalStats()
                saveDB()
                recordTransaction()
                table.insert(sellHistory, {item = msg.item, qty = qty, name = msg.name})
                while #sellHistory > MAX_SELL_HISTORY do table.remove(sellHistory, 1) end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "buy" then
                if shopPaused then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Магазин на паузе"}))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "❌ Неверный токен для buy от " .. (msg.name or "?"))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if not player or player.banned then goto continue end
                local value_coin = tonumber(msg.value_coin) or 0
                local value_ema = tonumber(msg.value_ema) or 0

                if player.balance < value_coin or player.emaBalance < value_ema then
                    modem.send(from, 0xffef, serialization.serialize({op="error", message="Недостаточно средств"}))
                    log("WARN", "❌ " .. msg.name .. " пытался купить " .. (msg.item or "?") .. " x" .. (msg.qty or 0) .. " но недостаточно средств")
                    goto continue
                end

                player.balance = player.balance - value_coin
                player.emaBalance = player.emaBalance - value_ema
                player.transactions = (player.transactions or 0) + 1
                sessions[msg.name].lastAction = os.time()
                globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
                saveGlobalStats()
                saveDB()
                recordTransaction()
                
                local priceStr = ""
                if value_coin > 0 then
                    priceStr = priceStr .. string.format("%.2f", value_coin) .. "₵"
                end
                
                if value_ema > 0 then
                    if priceStr ~= "" then
                        priceStr = priceStr .. " + "
                    end
                    priceStr = priceStr .. string.format("%.2f", value_ema) .. "۞"
                end
                log("SUCCESS", "🛒 " .. msg.name .. " купил " .. (msg.item or "?") .. " x" .. (msg.qty or 0) .. " за " .. priceStr)
                sendTelegram("🛒 Покупка!\n👤 " .. msg.name .. "\n📦 " .. (msg.item or "?") .. " x" .. (msg.qty or 0) .. "\n💳 " .. priceStr)
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "report" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "❌ Неверный токен для report")
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                globalStats.totalReports = (globalStats.totalReports or 0) + 1
                saveGlobalStats()
                log("IMPORTANT", "📩 Репорт от " .. msg.name .. " (" .. msg.time .. ")")
                log("INFO", "   Текст: " .. (msg.text or ""))
                sendTelegram("📩 Репорт!\n👤 " .. msg.name .. "\n📝 " .. (msg.text or ""))
                local file = io.open("/home/reports.log", "a")
                if file then
                    file:write("[" .. msg.time .. "] " .. msg.name .. ": " .. msg.text .. "\n")
                    file:close()
                else
                    log("ERROR", "❌ Не удалось открыть reports.log")
                end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "agree" then
                if not validateSession(msg.name, msg.token) then
                    log("WARN", "❌ Неверный токен для agree")
                    modem.send(from, 0xffef, serialization.serialize({ op="agree", error = true, message = "Токен устарел" }))
                    if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                    goto continue
                end
                local player = players[msg.name]
                if player then
                    player.agreed = true
                    saveDB()
                    sessions[msg.name].lastAction = os.time()
                    log("IMPORTANT", "📝 " .. msg.name .. " принял пользовательское соглашение")
                    sendTelegram("📝 Соглашение принято!\n👤 " .. msg.name)
                    modem.send(from, 0xffef, serialization.serialize({ op = "agree", success = true, agreed = true }))
                else
                    modem.send(from, 0xffef, serialization.serialize({ op = "agree", error = true, message = "Игрок не найден" }))
                end
                if not adminMode and not editBalanceMode and not addItemMode then drawInterface() end
                goto continue
            elseif msg.op == "add_buy_item_response" then
                addItemResponse = { success = msg.success, error = msg.error }
                goto continue
            elseif msg.op == "get_feedbacks" then
                if not validateSession(msg.name, msg.token) then
                    modem.send(from, 0xffef, serialization.serialize({op="feedbacks_list", error="Токен устарел"}))
                    goto continue
                end
                local player = players[msg.name]
                local feedbacks = {}
                if filesystem.exists("/home/feedbacks.db") then
                    local file = io.open("/home/feedbacks.db", "r")
                    local data = file:read("*a")
                    file:close()
                    if data and #data > 0 then
                        local ok, result = pcall(serialization.unserialize, data)
                        if ok and type(result) == "table" then
                            feedbacks = result
                        end
                    end
                end
                modem.send(from, 0xffef, serialization.serialize({
                    op = "feedbacks_list",
                    feedbacks = feedbacks,
                    hasFeedback = player and player.hasFeedback or false
                }))
                goto continue
            elseif msg.op == "add_feedback" then
                if not validateSession(msg.name, msg.token) then
                    modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Токен устарел"}))
                    goto continue
                end
                local player = players[msg.name]
                if not player then
                    modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Игрок не найден"}))
                    goto continue
                end
                if player.hasFeedback then
                    modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=false, error="Вы уже оставляли отзыв"}))
                    goto continue
                end
                local feedbacks = {}
                if filesystem.exists("/home/feedbacks.db") then
                    local file = io.open("/home/feedbacks.db", "r")
                    local data = file:read("*a")
                    file:close()
                    if data and #data > 0 then
                        local ok, result = pcall(serialization.unserialize, data)
                        if ok and type(result) == "table" then
                            feedbacks = result
                        end
                    end
                end
                table.insert(feedbacks, 1, {name = msg.name, text = msg.text, time = msg.time})
                local file = io.open("/home/feedbacks.db", "w")
                file:write(serialization.serialize(feedbacks))
                file:close()
                player.hasFeedback = true
                saveDB()
                modem.send(from, 0xffef, serialization.serialize({op="add_feedback_response", success=true}))
                log("INFO", "📝 Новый отзыв от " .. msg.name)
                goto continue
            elseif msg.op == "web_command" then
                handleWebCommand(msg, from)
            end
        end
        ::continue::
    end
end
    
-- ============================================
-- ЗАПУСК
-- ============================================
writeDebugLog("=== ЗАПУСК СЕРВЕРА ===")

while true do
    writeDebugLog("Запуск main()...")
    local ok, err = pcall(main)
    if not ok then
        writeDebugLog("КРИТИЧЕСКАЯ ОШИБКА: " .. tostring(err))
        print("❌ Ошибка сервера: " .. tostring(err))
        pcall(drawInterface)
        os.sleep(5)
    end
end
