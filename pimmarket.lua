local component = require("component")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")
local serialization = require("serialization")
local computer = require("computer")
local fs = require("filesystem")
local internet = require("internet")
local math = require("math")
local os = require("os")
local TIMEZONE_OFFSET = 3 * 3600

-- ============================================================
-- АВТОМАТИЧЕСКАЯ246 НАСТРОЙКА АВТОЗАПУСКА11111
-- ============================================================

local function setupAutoStart()
    local fs = require("filesystem")
    local io = require("io")
    local os = require("os")
    
    local startupFile = "/home/startup.lua"
    if not fs.exists(startupFile) then
        print("📝 Создаём автозапуск: " .. startupFile)
        local file = io.open(startupFile, "w")
        if file then
            file:write([[
-- Автозапуск PIM MARKET
local shell = require("shell")
local computer = require("computer")

os.sleep(3)
shell.execute("lua /home/pimmarket.lua &")
print("✅ PIM MARKET запущен")
]])
            file:close()
            print("✅ Автозапуск создан")
            return true
        end
    end
    
    local shrcFile = "/home/.shrc"
    if not fs.exists(shrcFile) then
        local file = io.open(shrcFile, "w")
        if file then
            file:write("-- Автозапуск PIM MARKET\n")
            file:write("lua /home/pimmarket.lua &\n")
            file:close()
            print("✅ .shrc создан")
        end
    end
    
    return true
end

if not fs.exists("/home/.autostart_done") then
    local success = setupAutoStart()
    if success then
        local file = io.open("/home/.autostart_done", "w")
        if file then
            file:write("autostart_configured_" .. os.date("%Y-%m-%d %H:%M:%S"))
            file:close()
        end
        print("🎯 Автозагрузка настроена!")
    end
end

pcall(function()
    event.ignore("interrupted", function() end)
    event.ignore("terminate", function() end)
end)

if not event.shouldInterrupt then
    function event.shouldInterrupt()
        return false
    end
end

-- ============================================================
-- ★★★ БЫСТРАЯ ОТРИСОВКА БЕЗ МОРГАНИЯ ★★★
-- ============================================================

-- Двойной буфер
local backBuffer = {}
local frontBuffer = {}
local bufferDirty = false
local renderInProgress = false

-- Инициализация буферов
for i = 1, 25 do
    backBuffer[i] = {}
    frontBuffer[i] = {}
    for j = 1, 80 do
        backBuffer[i][j] = { char = " ", fg = 0xFFFFFF, bg = 0x0A0A0F }
        frontBuffer[i][j] = { char = " ", fg = 0xFFFFFF, bg = 0x0A0A0F }
    end
end

-- Буферизированный вывод
function bufferSet(x, y, text, fg, bg)
    if not text or text == "" then return end
    if type(text) ~= "string" then text = tostring(text) end
    
    fg = fg or colors.text_main
    bg = bg or colors.bg_main
    
    local len = unicode.len(text)
    for i = 1, len do
        local px = x + i - 1
        local py = y
        if px >= 1 and px <= 80 and py >= 1 and py <= 25 then
            local ch = unicode.sub(text, i, i)
            if backBuffer[py] and backBuffer[py][px] then
                backBuffer[py][px] = { char = ch, fg = fg, bg = bg }
            end
        end
    end
    bufferDirty = true
end

-- Мгновенный рендер буфера (без очистки экрана!)
function renderBuffer()
    if not bufferDirty or renderInProgress then return end
    renderInProgress = true
    
    local changes = 0
    for y = 1, 25 do
        for x = 1, 80 do
            local new = backBuffer[y][x]
            local old = frontBuffer[y][x]
            if new and old then
                if new.char ~= old.char or new.fg ~= old.fg or new.bg ~= old.bg then
                    gpu.setForeground(new.fg)
                    gpu.setBackground(new.bg)
                    gpu.set(x, y, new.char)
                    frontBuffer[y][x] = { char = new.char, fg = new.fg, bg = new.bg }
                    changes = changes + 1
                end
            end
        end
    end
    
    bufferDirty = false
    renderInProgress = false
end

-- Очистка буфера (быстрая, без моргания)
function bufferClear()
    for y = 1, 25 do
        for x = 1, 80 do
            backBuffer[y][x] = { char = " ", fg = colors.text_main, bg = colors.bg_main }
        end
    end
    bufferDirty = true
end

-- Заполнение буфера
function bufferFill(x, y, w, h, char, fg, bg)
    fg = fg or colors.text_main
    bg = bg or colors.bg_main
    if type(char) ~= "string" then char = " " end
    
    for row = y, y + h - 1 do
        for col = x, x + w - 1 do
            if row >= 1 and row <= 25 and col >= 1 and col <= 80 then
                if backBuffer[row] and backBuffer[row][col] then
                    backBuffer[row][col] = { char = char, fg = fg, bg = bg }
                end
            end
        end
    end
    bufferDirty = true
end

-- Переопределяем стандартные функции на буферизированные
local originalClear = clear
clear = function()
    bufferClear()
end

local originalDrawScreenBorder = drawScreenBorder
drawScreenBorder = function()
    bufferSet(1, 1, "┌", colors.accent_secondary)
    bufferFill(2, 1, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 1, "┐", colors.accent_secondary)
    for y = 2, 24 do
        bufferSet(1, y, "│", colors.accent_secondary)
        bufferSet(80, y, "│", colors.accent_secondary)
    end
    bufferSet(1, 24, "└", colors.accent_secondary)
    bufferFill(2, 24, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 24, "┘", colors.accent_secondary)
end

local originalDrawCenteredText = drawCenteredText
drawCenteredText = function(y, text, color)
    if not text then return end
    color = color or colors.text_main
    local x = math.floor((80 - unicode.len(text)) / 2) + 1
    bufferSet(x, y, text, color)
end

local originalDrawButton = drawButton
drawButton = function(btn)
    if not btn then return end
    bufferFill(btn.x, btn.y, btn.xs, btn.ys, " ", btn.fg or colors.text_main, btn.bg or colors.bg_button)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    bufferSet(textX, textY, text, btn.fg or colors.text_main, btn.bg or colors.bg_button)
end

-- Новая функция "быстрой" очистки (без мерцания)
function quickClear()
    gpu.setBackground(colors.bg_main)
    gpu.fill(1, 1, 80, 25, " ")
end

-- Таймер рендера - НЕ чаще чем раз в 16ms (60 FPS)
renderTimer = nil
lastRenderTime = 0
MIN_RENDER_INTERVAL = 0.05

function safeRender()
    local now = os.clock()
    if now - lastRenderTime < MIN_RENDER_INTERVAL then
        if not renderTimer then
            renderTimer = event.timer(MIN_RENDER_INTERVAL - (now - lastRenderTime), function()
                renderTimer = nil
                renderBuffer()
                lastRenderTime = os.clock()
                return false
            end)
        end
        return
    end
    
    renderBuffer()
    lastRenderTime = now
end

-- ★★★ ПЕРЕОПРЕДЕЛЯЕМ markDirty ДЛЯ БЫСТРОЙ ОТРИСОВКИ ★★★
local originalMarkDirty = markDirty
markDirty = function()
    guiDirty = true
    if not renderTimer then
        renderTimer = event.timer(0.016, function()  -- ~60 FPS
            renderTimer = nil
            safeRender()
            return false
        end)
    end
end

-- ★★★ ПЕРЕОПРЕДЕЛЯЕМ forceRender ★★★
local originalForceRender = forceRender
forceRender = function()
    guiDirty = true
    if renderTimer then
        event.cancel(renderTimer)
        renderTimer = nil
    end
    safeRender()
    guiDirty = false
end

-- ★★★ НЕЙМАРКЕР ДЛЯ ПАРТИАЛЬНОГО ОБНОВЛЕНИЯ ★★★
function partialRedraw()
    -- Обновляем только изменившуюся область, а не весь экран
    renderBuffer()
end

-- ★★★ ПЕРЕОПРЕДЕЛЯЕМ drawTempMessage ★★★
local originalDrawTempMessage = drawTempMessage
drawTempMessage = function()
    if tempMessage and tempMessage ~= "" then
        bufferFill(1, 25, 80, 1, " ", colors.success, colors.bg_main)
        local x = math.floor((80 - unicode.len(tempMessage)) / 2) + 1
        bufferSet(x, 25, tempMessage, colors.success, colors.bg_main)
    else
        bufferFill(1, 25, 80, 1, " ", colors.text_main, colors.bg_main)
    end
end

-- ★★★ ПЕРЕОПРЕДЕЛЯЕМ drawBalanceLine ★★★
local originalDrawBalanceLine = drawBalanceLine
drawBalanceLine = function(x, y)
    local coin = coinBalance or 0.0
    local ema = emaBalance or 0.0
    
    bufferSet(x, y, "Баланс: ", colors.white)
    local coinStr = string.format("%.2f", coin) .. " Coina ₵"
    bufferSet(x + unicode.len("Баланс: "), y, coinStr, colors.accent_main)
    bufferSet(x + unicode.len("Баланс: ") + unicode.len(coinStr), y, " | ", colors.white)
    local emaStr = "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞"
    bufferSet(x + unicode.len("Баланс: ") + unicode.len(coinStr) + unicode.len(" | "), y, emaStr, colors.tomato)
end

-- ★★★ АСИНХРОННАЯ ЗАГРУЗКА ДАННЫХ ★★★
function asyncLoadItems(callback)
    event.timer(0.01, function()
        local success, err = pcall(function()
            if currentShopMode == "buy" then
                loadBuyItems()
            else
                loadSellItems()
            end
        end)
        if callback then
            callback(success, err)
        end
        markDirty()
        return false
    end)
end

-- ★★★ БЫСТРЫЙ ПЕРЕХОД МЕЖДУ ЭКРАНАМИ ★★★
function quickScreenSwitch(newScreen)
    currentScreen = newScreen
    bufferClear()
    if newScreen == "menu" then
        drawMainMenu()
    elseif newScreen == "shop" then
        drawShopMenu()
    elseif newScreen == "shop_buy" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif newScreen == "shop_sell" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif newScreen == "welcome" then
        drawWelcomeScreen()
    end
    forceRender()
end

-- Асинхронный показ сообщения без блокировки
function showMessageAsync(msg, duration, callback)
    drawCenteredText(17, msg, colors.success)
    forceRender()
    event.timer(duration or 2, function()
        if callback then
            callback()
        end
        return false
    end)
end

-- ============================================================
-- ★★★ ОТЛАДОЧНОЕ ЛОГИРОВАНИЕ В ФАЙЛ ★★★
-- ============================================================

DEBUG_LOG_FILE = "/home/debug.log"

function writeDebugFile(msg)
    local file = io.open(DEBUG_LOG_FILE, "a")
    if file then
        local timestamp = os.date("%Y-%m-%d %H:%M:%S")
        file:write("[" .. timestamp .. "] " .. msg .. "\n")
        file:close()
    end
end

function clearDebugFile()
    if fs.exists(DEBUG_LOG_FILE) then
        fs.remove(DEBUG_LOG_FILE)
    end
    writeDebugFile("=== DEBUG LOG STARTED ===")
end

clearDebugFile()

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
-- ★★★ ОЧИСТКА СТРОК ОТ НЕВИДИМЫХ СИМВОЛОВ ★★★
-- ============================================================
function cleanString(str)
    if not str then return "" end
    str = str:gsub("[%c]", "")
    str = str:gsub("%s+", " ")
    str = str:match("^%s*(.-)%s*$") or ""
    return str
end

-- ============================================================
-- ★★★ НОВАЯ СИСТЕМА ЛОГИРОВАНИЯ ★★★
-- ============================================================

LOG_LEVELS = {
    DEBUG = 0,
    INFO = 1,
    WARNING = 2,
    ERROR = 3,
    CRITICAL = 4
}

CURRENT_LOG_LEVEL = LOG_LEVELS.INFO

function writeLog(level, msg)
    if level < CURRENT_LOG_LEVEL then
        return
    end
    
    local levelName = "INFO"
    if level == LOG_LEVELS.DEBUG then levelName = "DEBUG" end
    if level == LOG_LEVELS.WARNING then levelName = "WARNING" end
    if level == LOG_LEVELS.ERROR then levelName = "ERROR" end
    if level == LOG_LEVELS.CRITICAL then levelName = "CRITICAL" end
    
    addLogEntry(msg, levelName)
    
    if level == LOG_LEVELS.CRITICAL then
        sendErrorToWeb(msg, "CRITICAL")
    end
end

function writeDebugLog(msg)
    writeLog(LOG_LEVELS.DEBUG, msg)
end

function writeErrorLog(msg)
    writeLog(LOG_LEVELS.ERROR, msg)
end

-- ============================================================
-- ★★★ МЕНЕДЖЕР ТАЙМЕРОВ ★★★
-- ============================================================

timers = {}

function createTimer(interval, callback, shouldRepeat)
    local times = shouldRepeat and math.huge or 1
    local timerId = event.timer(interval, callback, times)
    table.insert(timers, timerId)
    return timerId
end

function clearAllTimers()
    for _, id in ipairs(timers) do
        pcall(event.cancel, id)
    end
    timers = {}
end

-- ============================================================
-- ★★★ GRACEFUL SHUTDOWN - ПЛАВНОЕ ЗАВЕРШЕНИЕ ★★★
-- ============================================================

isShuttingDown = false

function saveAllData()
    writeDebugLog("💾 Сохранение всех данных...")
    
    if dbDirty then
        saveDB()
        writeDebugLog("   ✅ Игроки сохранены")
    end
    
    saveGlobalStats()
    writeDebugLog("   ✅ Статистика сохранена")
    
    flushLogQueue()
    writeDebugLog("   ✅ Логи отправлены")
    
    if #pending_buffer > 0 then
        save_pending_buffer()
        writeDebugLog("   ✅ Буфер изменений сохранён")
    end
    
    writeDebugLog("💾 Все данные сохранены!")
end

function asyncSaveData()
    if isShuttingDown then
        return
    end
    
    isShuttingDown = true
    
    event.timer(0.1, function()
        pcall(saveAllData)
        isShuttingDown = false
        return false
    end)
end

function forceSaveData()
    isShuttingDown = true
    saveAllData()
    isShuttingDown = false
end

-- ============================================================
-- ★★★ ОБРАБОТЧИК ВЫКЛЮЧЕНИЯ КОМПЬЮТЕРА ★★★
-- ============================================================

event.listen("computer_shutdown", function()
    writeErrorLog("⏻ Компьютер выключается! Сохраняем данные...")
    forceSaveData()
    writeErrorLog("✅ Данные сохранены перед выключением")
end)

event.listen("terminate", function()
    writeErrorLog("⏻ Процесс завершается! Сохраняем данные...")
    forceSaveData()
    writeErrorLog("✅ Данные сохранены перед завершением")
end)

-- ============================================================
-- ★★★ ЗАЩИТА ОТ ЗАВИСАНИЙ ★★★
-- ============================================================

TRANSACTION_LOCK = false
COMMAND_CHECK_INTERVAL = 10

function lockTransactions()
    TRANSACTION_LOCK = true
    writeDebugLog("🔒 Транзакции заблокированы")
end

function unlockTransactions()
    TRANSACTION_LOCK = false
    writeDebugLog("🔓 Транзакции разблокированы")
    event.timer(0.5, function()
        if not TRANSACTION_LOCK then
            writeDebugLog("📡 Быстрая проверка команд после транзакции")
            checkWebCommands()
        end
        return false
    end)
end

function safeExit()
    writeDebugLog("🚪 Безопасный выход")
    
    isShuttingDown = true
    
    if currentPlayer ~= nil then
        addLog("👤 Выход: " .. currentPlayer)
        writeDebugLog("👤 Выход игрока: " .. tostring(currentPlayer))
    else
        writeDebugLog("🚪 Выход без игрока")
    end
    
    currentPlayer = nil
    currentToken = nil
    alreadyAuthorized = false
    pimOwner = nil
    currentScreen = "welcome"
    authCodeInput = ""
    boundPlayer = nil
    
    if TRANSACTION_LOCK then
        TRANSACTION_LOCK = false
        writeDebugLog("🔓 Блокировка сброшена при выходе")
    end
    
    selectedItem = nil
    hoveredIndex = 0
    selectedIndex = 0
    filteredItems = {}
    shopSearch = ""
    searchActive = false
    searchInput = ""
    purchaseItem = nil
    purchaseQuantity = 1
    sellConfirmItem = nil
    foundAmount = 0
    showSellPopup = false
    showPartialPopup = false
    showInsufficientPopup = false
    showInventoryFullPopup = false
    listScroll = 1
    horizontalScroll = 1
    tempMessage = ""
    
    if tempMessageTimer then
        event.cancel(tempMessageTimer)
        tempMessageTimer = nil
    end
    
    pcall(updateSelectorDisplay, nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
    
    clearAllTimers()
    writeDebugLog("⏹️ Все таймеры остановлены")
    
    drawWelcomeScreen()
    forceRender()
    writeDebugLog("🖥️ Экран приветствия отображён")
    
    asyncSaveData()
    writeDebugLog("💾 Запущено фоновое сохранение данных")
    
    isShuttingDown = false
    
    writeDebugLog("✅ Безопасный выход завершён")
    writeErrorLog("🔴 Терминал #1 (PIM MARKET) остановлен")
end

-- ============================================================
-- ВЕБ-ИНТЕГРАЦИЯ
-- ============================================================

WEB_URL = "https://zozido.pythonanywhere.com"

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
            ["Connection"] = "close",
            ["Timeout"] = 3
        })
    end)
end

-- ============================================================
-- ЛОГИ
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
    if #logQueue == 0 then 
        return 
    end
    
    local batch = {}
    for _, e in ipairs(logQueue) do
        table.insert(batch, { time = e.time, text = e.text, level = e.level })
    end
    
    local success, err = pcall(function()
        sendToWeb("/api/logs_batch", toJson({ logs = batch }))
    end)
    
    if not success then
        writeDebugLog("⚠️ Не удалось отправить логи: " .. tostring(err))
        return
    end
    
    logQueue = {}
    writeDebugLog("📤 Отправлено " .. #batch .. " логов")
end
createTimer(LOG_FLUSH_INTERVAL, flushLogQueue, true)

function addLog(text)
    addLogEntry(text, "INFO")
end

function sendErrorToWeb(error_msg, level)
    level = level or "ERROR"
    local timestamp = getRealTimeHM()
    sendToWeb("/api/error_log", toJson({
        error = error_msg,
        level = level,
        time = timestamp
    }))
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

event.ignore("interrupted", function() end)
event.ignore("terminate", function() end)

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
-- ★★★ DIRTY FLAG - УПРАВЛЕНИЕ ПЕРЕРИСОВКОЙ ★★★
-- ============================================================

guiDirty = true
renderTimer = nil
lastRenderedScreen = ""

function renderCurrentScreen()
    if renderInProgress then return end
    renderInProgress = true

    bufferClear()

    if currentScreen == "welcome" then
        drawWelcomeScreen()
    elseif currentScreen == "menu" then
        drawMainMenu()
    elseif currentScreen == "shop" then
        drawShopMenu()
    elseif currentScreen == "shop_buy" or currentScreen == "shop_sell" then
        drawBuyStatic()
        drawBuyItemsList()
        drawBuyButtons()
    elseif currentScreen == "sell_scan" then
        drawSellScanScreen()
    elseif currentScreen == "purchase" then
        drawPurchaseScreen()
    elseif currentScreen == "account" then
        drawAccount({balance=coinBalance, emaBalance=emaBalance, transactions=playerTransactions, regDate=playerRegDate, agreed=playerAgreed})
    elseif currentScreen == "report" then
        drawReportScreen()
    elseif currentScreen == "feedbacks" then
        drawFeedbacksList()
    elseif currentScreen == "feedback_input" then
        drawFeedbackInputScreen()
    elseif currentScreen == "agreement" then
        if type(drawAgreementScreen) == "function" then
            drawAgreementScreen()
        end
    elseif currentScreen == "auth_popup" then
        showAuthPopup()
    elseif currentScreen == "qr_popup" then
        showQRCodePopup()
    end

    drawTempMessage()
    renderBuffer()
    renderInProgress = false
end

function forceRender()
    if renderInProgress then return end
    guiDirty = true
    if renderTimer then
        event.cancel(renderTimer)
        renderTimer = nil
    end
    renderCurrentScreen()
    guiDirty = false
end

function markDirty()
    guiDirty = true
    if not renderTimer then
        renderTimer = event.timer(0.016, function()
            renderTimer = nil
            if guiDirty then
                renderCurrentScreen()
                guiDirty = false
            end
            return false
        end)
    end
end

-- ============================================================
-- ★★★ DEBOUNCE ДЛЯ СОБЫТИЙ МЫШИ ★★★
-- ============================================================

mouseDebounceTimer = nil
pendingMouseX = 0
pendingMouseY = 0

function processMouseMove(x, y)
    if currentScreen ~= "shop_buy" and currentScreen ~= "shop_sell" then
        return
    end
    
    if y >= 7 and y <= 21 and x >= 2 and x <= 77 then
        local rel = y - 6
        local newHover = (listScroll or 1) + rel - 1
        if newHover <= #filteredItems and newHover ~= hoveredIndex then
            hoveredIndex = newHover
            drawBuyItemsList()
            partialRedraw()
        end
    else
        if hoveredIndex ~= 0 then
            hoveredIndex = 0
            drawBuyItemsList()
            partialRedraw()
        end
    end
end

-- ============================================================
-- СИСТЕМНЫЕ ДАННЫЕ ДЛЯ ТЕРМИНАЛОВ
-- ============================================================

function getSystemInfo()
    local info = {}
    
    local uptime = computer.uptime()
    info.uptime_seconds = uptime
    info.uptime_human = formatUptime(uptime)
    
    local realTime = getRealTimestamp()
    local bootTime = realTime - uptime
    info.boot_time = os.date("%d.%m.%Y %H:%M:%S", bootTime)
    
    info.cpu_load = 0
    info.cpu_percent = "N/A"
    if computer.getCPUUsage then
        local ok, cpu = pcall(computer.getCPUUsage)
        if ok and cpu and type(cpu) == "number" then
            info.cpu_load = cpu
            info.cpu_percent = string.format("%.1f%%", cpu * 100)
        end
    end
    
    info.memory_total = 0
    info.memory_used = 0
    info.memory_free = 0
    info.memory_used_mb = "N/A"
    info.memory_total_mb = "N/A"
    info.memory_human = "N/A"
    
    if computer.totalMemory then
        local ok, total = pcall(computer.totalMemory)
        if ok and total and type(total) == "number" then
            info.memory_total = total
            info.memory_total_mb = string.format("%.1f MB", total / 1024 / 1024)
        end
    end
    
    if computer.freeMemory then
        local ok, free = pcall(computer.freeMemory)
        if ok and free and type(free) == "number" then
            info.memory_free = free
            if info.memory_total > 0 then
                info.memory_used = info.memory_total - free
                info.memory_used_mb = string.format("%.1f MB", info.memory_used / 1024 / 1024)
                info.memory_human = info.memory_used_mb .. " / " .. info.memory_total_mb
            end
        end
    end
    
    info.disk_used_percent = "N/A"
    local fs = require("filesystem")
    local paths = {"/", "/home", "/tmp", "/lib"}
    for _, path in ipairs(paths) do
        local ok1, free = pcall(fs.space, path)
        local ok2, total = pcall(fs.total, path)
        if ok1 and ok2 and total and type(total) == "number" and total > 0 then
            if free and type(free) == "number" then
                info.disk_used_percent = string.format("%.1f%%", (total - free) / total * 100)
                break
            end
        end
    end
    
    info.ip = "N/A"
    if computer.getLocalIP then
        local ok, ip = pcall(computer.getLocalIP)
        if ok and ip then
            info.ip = ip
        end
    end
    
    info.current_player = "—"
    local pimAddr = getPimAddr()
    if pimAddr then
        local pim = component.proxy(pimAddr)
        local player = nil
        
        if pim.getPlayer then
            local ok, result = pcall(pim.getPlayer, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player and pim.getPlayerName then
            local ok, result = pcall(pim.getPlayerName, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player and pim.getUsername then
            local ok, result = pcall(pim.getUsername, pim)
            if ok and result then
                player = result
            end
        end
        
        if not player then
            local ok, result = pcall(function()
                return pim.player
            end)
            if ok and result then
                player = result
            end
        end
        
        if player and player ~= "" then
            info.current_player = player
        end
    end
    
    info.real_time = getRealTimeString()
    
    return info
end

function formatUptime(seconds)
    if not seconds or seconds < 0 then 
        return "—" 
    end 
    
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    
    if days > 0 then
        return string.format("%dд %dч %dм", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%dч %dм", hours, minutes)
    else
        return string.format("%dм", math.max(1, minutes))
    end
end

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
    
    bufferFill(btn.x, btn.y, btn.xs, btn.ys, " ", btn.fg or colors.text_main, btn.bg or colors.bg_button)
    local text = btn.text or ""
    local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
    local textY = btn.y + math.floor((btn.ys - 1) / 2)
    bufferSet(textX, textY, text, btn.fg or colors.text_main, btn.bg or colors.bg_button)
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
REPORTS_FILE = "/home/reports.json"
PENDING_FILE = "/home/pending_changes.lua"

admins = {}
players = {}
globalStats = { totalReports = 0, totalBuys = 0, totalSells = 0, totalRevenue = 0, totalBalance = 0 }
transactions = {}
pending_buffer = {}
retry_delay = 10

playersIndex = {}

function syncPlayerIndex()
    playersIndex = {}
    for name, data in pairs(players) do
        if name and data then
            playersIndex[name] = data
        end
    end
    writeDebugLog("🔄 Индекс игроков обновлён: " .. #playersIndex .. " записей")
end

function findPlayer(name)
    if not name then return nil end
    return playersIndex[name]
end

function updatePlayerData(name, data)
    if not name then return false end
    players[name] = data
    playersIndex[name] = data
    writeDebugLog("💾 Игрок обновлён: " .. name)
    return true
end

function deletePlayer(name)
    if not name then return false end
    players[name] = nil
    playersIndex[name] = nil
    writeDebugLog("🗑️ Игрок удалён: " .. name)
    return true
end

function loadReportsFromFile()
    if fs.exists(REPORTS_FILE) then
        local file = io.open(REPORTS_FILE, "r")
        if file then
            local data = file:read("*a")
            file:close()
            if data and #data > 0 then
                local ok, result = pcall(serialization.unserialize, data)
                if ok and type(result) == "table" then
                    return result
                end
            end
        end
    end
    return {}
end

function saveReportsToFile(reports)
    local file = io.open(REPORTS_FILE, "w")
    if file then
        file:write(serialization.serialize(reports))
        file:close()
        return true
    else
        writeErrorLog("❌ Не удалось сохранить репорты в файл")
        return false
    end
end

function addReportToLocal(name, text)
    local reports = loadReportsFromFile()
    local report_entry = {
        time = getRealTimeString(),
        name = name or "Аноним",
        text = text or "",
        viewed = false
    }
    table.insert(reports, 1, report_entry)
    saveReportsToFile(reports)
    writeDebugLog("📝 Репорт сохранён локально: " .. (name or "Аноним"))
    return reports
end

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
    if not ids then
        pending_buffer = {}
        save_pending_buffer()
        writeDebugLog("🗑️ Буфер полностью очищен")
        return
    end
    
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

function send_pending_changes()
    writeDebugFile(">>> send_pending_changes()")
    writeDebugFile("   pending_buffer: " .. #pending_buffer .. " записей")
    
    if #pending_buffer == 0 then
        writeDebugFile("   буфер пуст, выходим")
        return true
    end

    for i, ch in ipairs(pending_buffer) do
        writeDebugFile("   [" .. i .. "] " .. ch.type .. " " .. ch.data.player .. " " .. ch.data.item)
    end

    local changes_to_send = {}
    for _, ch in ipairs(pending_buffer) do
        table.insert(changes_to_send, ch)
    end

    local payload = { changes = changes_to_send }
    local json_payload = toJson(payload)

    writeDebugFile("📤 Отправка дельты: " .. #changes_to_send .. " изменений")
    writeDebugFile("   URL: " .. WEB_URL .. "/api/delta")
    writeDebugFile("   Payload: " .. json_payload)

    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/delta", json_payload, {
            ["Content-Type"] = "application/json",
            ["Connection"] = "close",
            ["Timeout"] = "5"
        })
    end)

    if success and response then
        writeDebugFile("✅ Ответ получен")
        local body = ""
        local timeout = os.clock() + 5
        for chunk in response do
            if os.clock() > timeout then
                writeDebugFile("⚠️ Таймаут чтения ответа")
                break
            end
            body = body .. chunk
        end
        
        writeDebugFile("   body: " .. body)
        
        local data = parseJSON(body)
        if data and data.status == "ok" then
            pending_buffer = {}
            save_pending_buffer()
            writeDebugFile("✅ Дельта подтверждена, буфер очищен")
            retry_delay = 10
            return true
        else
            writeDebugFile("⚠️ Ошибка сервера, буфер сохранён")
            if data then
                writeDebugFile("   data.status = " .. tostring(data.status))
            end
            retry_delay = math.min(retry_delay * 2, 120)
            return false
        end
    else
        writeDebugFile("⚠️ Ошибка соединения, буфер сохранён")
        writeDebugFile("   success=" .. tostring(success))
        if not success then
            writeDebugFile("   err=" .. tostring(err))
        end
        retry_delay = math.min(retry_delay * 2, 120)
        return false
    end
end

event.timer(10, function()
    writeDebugFile("⏰ Таймер сработал (event.timer)")
    if #pending_buffer > 0 then
        send_pending_changes()
    end
    return true
end, math.huge)

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
ensureFileExists(REPORTS_FILE, {})

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

if fs.exists(DB_PATH) then
    local file = io.open(DB_PATH, "r")
    local raw = file:read("*a")
    file:close()
    if raw and #raw > 0 then
        local success, data = pcall(serialization.unserialize, raw)
        if success and data then players = data end
    end
end

syncPlayerIndex()

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

load_pending_buffer()

dbDirty = false
SAVE_DB_INTERVAL = 10

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
    if not dbDirty then 
        return 
    end
    
    if TRANSACTION_LOCK then
        writeDebugLog("⏳ Отложено сохранение (транзакция активна)")
        return
    end
    
    saveDB()
    dbDirty = false
end
createTimer(SAVE_DB_INTERVAL, flushDB, true)

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

function addTransaction(type, playerName, item, qty, value_coin, value_ema)
    writeDebugFile(">>> addTransaction()")
    writeDebugFile("   type=" .. tostring(type))
    writeDebugFile("   playerName=" .. tostring(playerName))
    writeDebugFile("   item=" .. tostring(item))
    writeDebugFile("   qty=" .. tostring(qty))
    writeDebugFile("   value_coin=" .. tostring(value_coin))
    writeDebugFile("   value_ema=" .. tostring(value_ema))
    
    if type == "sell" then
        globalStats.totalSells = (globalStats.totalSells or 0) + 1
        globalStats.totalRevenue = (globalStats.totalRevenue or 0) + (value_coin or 0) + (value_ema or 0)
    elseif type == "buy" then
        globalStats.totalBuys = (globalStats.totalBuys or 0) + 1
    end
    saveGlobalStats()
    
    local transactionRecord = {
        time = getRealTimeHM(),
        type = type,
        item = item or "?",
        qty = qty or 0,
        coin = value_coin or 0,
        ema = value_ema or 0
    }
    
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
    
    if playerName and playerName ~= "?" then
        local player = playersIndex[playerName]
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
            players[playerName] = player
            playersIndex[playerName] = player
            writeDebugLog("➕ Создан новый игрок в addTransaction: " .. playerName)
            addLog("✅ Новый игрок: " .. playerName)
        end
        
        player.transactions = (player.transactions or 0) + 1
        if not player.transactionsList then
            player.transactionsList = {}
        end
        table.insert(player.transactionsList, transactionRecord)
        saveDBDeferred()
        writeDebugLog("📊 Транзакции игрока " .. playerName .. ": " .. player.transactions)
        writeDebugLog("📋 Список теперь содержит " .. #player.transactionsList .. " записей")
        
        local currency = ""
        if value_coin > 0 and value_ema > 0 then
            currency = string.format("%.2f₵ + %.2f۞", value_coin, value_ema)
        elseif value_coin > 0 then
            currency = string.format("%.2f₵", value_coin)
        elseif value_ema > 0 then
            currency = string.format("%.2f۞", value_ema)
        end
        local action = type == "buy" and "🛒 Купил" or "💰 Продал"
        addLog(string.format("%s %s: %s x%d за %s", action, playerName, item, qty, currency))
        
    else
        writeErrorLog("⚠️ Некорректное имя игрока при добавлении транзакции: " .. tostring(playerName))
    end
    
    local change = {
        id = "txn_" .. os.time() .. "_" .. math.random(100000),
        type = type,
        data = {
            player = playerName,
            item = item,
            qty = qty,
            coin = value_coin or 0,
            ema = value_ema or 0
        }
    }
    writeDebugFile("📤 Добавлено изменение в буфер: " .. change.id)
    add_pending_change(change)
end

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

function sendStats()
    writeDebugLog("📊 sendStats() начат (резервный дамп)")
    
    local sysInfo = {}
    local ok, result = pcall(getSystemInfo)
    if ok and result then
        sysInfo = result
    else
        writeErrorLog("⚠️ Ошибка получения системной информации")
    end
    
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
    
    if #playerList > 0 and playerList[1] then
        playerList[1].system_info = sysInfo
        writeDebugLog("📊 Системные данные добавлены к игроку: " .. playerList[1].name)
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
        sell_items = sellItems,
        system_info = sysInfo
    }
    
    local jsonData = toJson(payload)
    writeDebugLog("📤 Размер JSON: " .. #jsonData .. " байт")
    writeDebugLog("📤 Отправлены данные: " .. #playerList .. " игроков, " .. #buyItems .. " товаров покупки, " .. #sellItems .. " товаров продажи")
    
    sendToWeb("/api/update", jsonData)
end

createTimer(60, function()
    if not TRANSACTION_LOCK then
        pcall(sendStats)
    end
    return true
end, true)

createTimer(30, function()
    if not TRANSACTION_LOCK then
        local sysInfo = getSystemInfo()
        sendToWeb("/api/system_info", toJson(sysInfo))
        writeDebugLog("📊 Отправлены системные данные отдельным пакетом")
    end
    return true
end, true)

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
    local success, result = pcall(function()
        for addr in component.list("pim") do
            return addr
        end
    end)
    if success and result then
        return result
    end
    return nil
end

PUSH_DIRECTION = "down"
PULL_DIRECTION = "up"

function normalizeName(name)
    if not name then 
        return "" 
    end
    local lastColon = name:match(".*:([^:]+)$")
    return lastColon or name
end

function namesMatch(name1, name2)
    if not name1 or not name2 then 
        return false 
    end
    
    if name1 == name2 then 
        return true 
    end
    
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

authCodeInput = ""
boundPlayer = nil

bindingCache = {
    isBound = false,
    lastCheck = 0,
    checkInterval = 10
}

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
-- JSON ПАРСЕР
-- ============================================================

function parseJSON(json_str)
    if not json_str or json_str == "" then 
        writeDebugLog("parseJSON: пустая строка")
        return nil 
    end

    local str = json_str
    local pos = 1
    local len = #str

    local function skipSpace()
        while pos <= len do
            local c = str:sub(pos, pos)
            if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then break end
            pos = pos + 1
        end
    end

    local function parseString()
        if str:sub(pos, pos) ~= '"' then 
            return nil 
        end
        
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
                local map = {
                    ['"'] = '"',
                    ['\\'] = '\\',
                    ['/'] = '/',
                    b = '\b',
                    f = '\f',
                    n = '\n',
                    r = '\r',
                    t = '\t'
                }
                
                if map[esc] then
                    result = result .. map[esc]
                elseif esc == 'u' then
                    local hex = str:sub(pos+1, pos+4)
                    if #hex == 4 then
                        local code = tonumber(hex, 16)
                        if code then
                            result = result .. unicode.char(code)
                            pos = pos + 4
                        end
                    end
                else
                    result = result .. '\\' .. esc
                end
                pos = pos + 1
                start = pos
            else
                pos = pos + 1
            end
        end
        return nil
    end

    function parseNumber()
        local start = pos
        while pos <= len do
            local ch = str:sub(pos, pos)
            if not ch:match("[%d%.%-%+eE]") then break end
            pos = pos + 1
        end
        return tonumber(str:sub(start, pos-1))
    end

    local function parseArray()
        if str:sub(pos, pos) ~= '[' then 
            return nil
        end
        
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
            if ch == ',' then 
                pos = pos + 1
            elseif ch == ']' then 
                pos = pos + 1
                break
            else 
                break 
            end
        end
        return arr
    end

    local function parseObject()
        if str:sub(pos, pos) ~= '{' then 
            return nil
        end
        
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
            if ch == ',' then 
                pos = pos + 1
            elseif ch == '}' then 
                pos = pos + 1
                break
            else 
                break 
            end
        end
        return obj
    end

    function parseValue()
        skipSpace()
        if pos > len then 
            return nil
        end
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
    if not playerName or not pimOwner then 
        return false
    end
    return playerName == pimOwner
end

function syncCurrentPlayer()
    if not currentPlayer then 
        return
    end
    
    writeDebugLog("🔄 Синхронизация игрока: " .. currentPlayer)
    
    local player = playersIndex[currentPlayer]
    if player then
        coinBalance = player.balance or 0
        emaBalance = player.emaBalance or 0
        playerTransactions = player.transactions or 0
        playerRegDate = player.regDate or ""
        playerAgreed = player.agreed or false
        
        writeDebugLog("✅ Синхронизирован: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        return true
    end
    
    writeDebugLog("⚠️ Игрок не найден при синхронизации: " .. currentPlayer)
    return false
end

function checkBindingStatus()
    if not currentPlayer then 
        return
    end
    
    local checkSuccess, checkResponse = pcall(function()
        return internet.request(WEB_URL .. "/api/player_binding?game_player=" .. currentPlayer, nil, {
            ["Connection"] = "close",
            ["Timeout"] = "3"
        })
    end)
    
    if checkSuccess and checkResponse then
        local body = ""
        for chunk in checkResponse do
            body = body .. chunk
        end
        local data = parseJSON(body)
        if data and data.success then
            local wasBound = boundPlayer ~= nil
            local isBound = data.success and data.site_user ~= nil
            
            if wasBound and not isBound then
                boundPlayer = nil
                clearBoundPlayer()
                addLog("🔓 Привязка отозвана на сервере")
                if currentScreen == "menu" or currentScreen == "account" then
                    markDirty()
                end
            elseif not wasBound and isBound then
                boundPlayer = currentPlayer
                saveBoundPlayer(currentPlayer)
                addLog("🔗 Привязка восстановлена на сервере")
                if currentScreen == "menu" or currentScreen == "account" then
                    markDirty()
                end
            end
        end
    end
end

function getBindingStatus()
    if not currentPlayer then
        boundPlayer = nil
        bindingCache.isBound = false
        return false
    end
   
    local now = os.time()
    if now - (bindingCache.lastCheck or 0) < bindingCache.checkInterval then
        return bindingCache.isBound
    end
   
    bindingCache.lastCheck = now
   
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/player_binding?site_user=" .. currentPlayer)
    end)
   
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
       
        if data and data.success and data.player then
            boundPlayer = data.player
            bindingCache.isBound = true
            writeDebugLog("✅ Привязка подтверждена: " .. boundPlayer)
            return true
        else
            boundPlayer = nil
            bindingCache.isBound = false
            writeDebugLog("❌ Привязка не найдена")
            return false
        end
    else
        writeDebugLog("⚠️ Не удалось проверить привязку")
        return bindingCache.isBound
    end
end

createTimer(30, function()
    if not TRANSACTION_LOCK then
        checkBindingStatus()
    end
    return true
end, true)

function updateSelectorDisplay(item)
    if not selector then 
        return
    end
    
    if not item then
        pcall(selector.setSlot, 0, nil)
        pcall(selector.setSlot, 1, nil)
        return
    end
    
    local raw = item.internalName or item.name or item.displayName
    if not raw then 
        return
    end
    
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
    if not lastReportTime then 
        return true
    end
    
    local now = getRealTimestamp()
    local reportDate = os.date("*t", lastReportTime)
    local nowDate = os.date("*t", now)
    if reportDate.day ~= nowDate.day or reportDate.month ~= nowDate.month or reportDate.year ~= nowDate.year then
        return true
    end
    return false
end

function getActualItemQuantity(internalName, damage)
    if not component.isAvailable("me_interface") then 
        return 0
    end
    
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
        markDirty()
    end)
    drawTempMessage()
end

-- ============================================================
-- ЗАГРУЗКА ТОВАРОВ
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
        writeErrorLog("❌ ❌ ME интерфейс недоступен для загрузки товаров")
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

BOUND_PLAYER_FILE = "/home/bound_player.dat"

function saveBoundPlayer(playerName)
    if playerName and playerName ~= "" then
        local file = io.open(BOUND_PLAYER_FILE, "w")
        if file then
            file:write(playerName)
            file:close()
            writeDebugLog("💾 Привязка сохранена: " .. playerName)
            return true
        end
    end
    return false
end

function loadBoundPlayer()
    if fs.exists(BOUND_PLAYER_FILE) then
        local file = io.open(BOUND_PLAYER_FILE, "r")
        if file then
            local data = file:read("*a")
            file:close()
            if data and data ~= "" then
                writeDebugLog("📂 Загружена привязка: " .. data)
                return data
            end
        end
    end
    return nil
end

function clearBoundPlayer()
    if fs.exists(BOUND_PLAYER_FILE) then
        fs.remove(BOUND_PLAYER_FILE)
        writeDebugLog("🗑️ Привязка удалена")
    end
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
    if not pimAddr or amount <= 0 then 
        return 0
    end
    
    targetDamage = targetDamage or 0
    local extracted = 0
    for slot = 1, 36 do
        if extracted >= amount then
            break
        end
        
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
-- UI МАГАЗИНА
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
    
    bufferSet(1, 1, "┌", colors.accent_secondary)
    bufferFill(2, 1, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 1, "┐", colors.accent_secondary)
    for y = 2, 24 do
        bufferSet(1, y, "│", colors.accent_secondary)
        bufferSet(80, y, "│", colors.accent_secondary)
    end
    bufferSet(1, 24, "└", colors.accent_secondary)
    bufferFill(2, 24, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 24, "┘", colors.accent_secondary)

    drawBalanceLine(3, 1)

    local title = currentShopMode == "buy" and "Магазин продаёт" or "Магазин покупает"
    bufferSet(3, 3, title, colors.accent_secondary)

    local searchX = 42
    local searchText = ""
    if searchActive then
        searchText = (searchInput or "") .. "_"
    else
        searchText = (shopSearch == "" and "Поиск..." or (shopSearch or ""))
    end
    bufferFill(searchX, 3, 23, 1, " ", colors.accent_main, colors.bg_button)
    bufferSet(searchX + 1, 3, unicode.sub(searchText, 1, 21), colors.accent_main, colors.bg_button)

    local clearText = "[ СТЕРЕТЬ ]"
    local clearWidth = unicode.len(clearText) + 2
    local clearX = searchX + 23 + 1
    bufferFill(clearX, 3, clearWidth, 1, " ", colors.accent_secondary, colors.error)
    local textX = clearX + math.floor((clearWidth - unicode.len(clearText)) / 2)
    bufferSet(textX, 3, clearText, colors.accent_secondary, colors.error)

    bufferFill(2, 5, 76, 1, " ", colors.text_bright, colors.bg_button)
    bufferSet(3, 5, "Название", colors.text_bright, colors.bg_button)
    bufferSet(42, 5, "Кол-во", colors.text_bright, colors.bg_button)
    if currentShopMode == "buy" then
        bufferSet(55, 5, "Coina", colors.text_bright, colors.bg_button)
        bufferSet(67, 5, "ЭМЫ", colors.text_bright, colors.bg_button)
    else
        bufferSet(65, 5, "Цена", colors.text_bright, colors.bg_button)
    end

    bufferFill(2, 6, 76, 15, " ", colors.text_main, colors.bg_main)
    
    drawTempMessage()
end

function drawSingleRow(y, item, isHovered, isSelected, itemIndex)
    if not item then return end
    
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
        fg = (item.qty > 0) and colors.accent_main or colors.inactive
    else
        fg = colors.accent_main
    end
    
    bufferFill(2, y, 76, 1, " ", fg, bg)
    
    local name = item.displayName or "Неизвестно"
    if unicode.len(name) > 37 then
        name = unicode.sub(name, (horizontalScroll or 1), (horizontalScroll or 1) + 36)
    end
    bufferSet(3, y, name, fg, bg)
    
    bufferSet(42, y, tostring(item.qty or 0), (item.qty > 0) and colors.text_bright or colors.inactive, bg)
    
    if currentShopMode == "sell" then
        local priceColor = (item.internalName == "customnpcs:npcMoney") and colors.tomato or colors.text_bright
        bufferSet(65, y, string.format("%.2f", item.price or 0) .. (item.internalName == "customnpcs:npcMoney" and " ۞" or " ₵"), priceColor, bg)
    else
        if item.priceCoin and item.priceCoin > 0 then
            bufferSet(55, y, string.format("%.2f", item.priceCoin), colors.accent_main, bg)
        else
            bufferSet(55, y, "0", colors.inactive, bg)
        end
        if item.priceEma and item.priceEma > 0 then
            bufferSet(67, y, string.format("%.2f", item.priceEma), colors.tomato, bg)
        else
            bufferSet(67, y, "0", colors.inactive, bg)
        end
    end
end

function drawScrollBar()
    local total = #filteredItems
    local barX = 78
    local barY = 7
    local barHeight = 15
    
    bufferFill(barX, barY, 2, barHeight, " ", colors.text_main, colors.bg_main)
    
    if total <= visibleRows then 
        return
    end
    
    bufferFill(barX, barY, 2, barHeight, " ", colors.text_main, colors.bg_secondary)
    
    local thumbHeight = math.max(2, math.floor(barHeight * visibleRows / total))
    local maxPos = barHeight - thumbHeight
    local thumbPos = math.floor((listScroll - 1) * maxPos / (total - visibleRows)) + 1
    thumbPos = math.min(thumbPos, maxPos + 1)
    
    bufferFill(barX, barY + thumbPos - 1, 2, thumbHeight, " ", colors.text_main, colors.accent_main)
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
        if not item then
            goto continue
        end

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
        if len > maxItemWidth then
            maxItemWidth = len
        end
    end

    writeDebugLog("getFilteredItems: найдено " .. #filtered .. " товаров")
    return filtered
end

function drawBuyItemsList()
    writeDebugLog("drawBuyItemsList()")
    filteredItems = getFilteredItems()
    local total = #filteredItems
    local maxScroll = math.max(1, total - visibleRows + 1)
    listScroll = math.max(1, math.min(listScroll or 1, maxScroll))

    bufferFill(2, 6, 76, 15, " ", colors.text_main, colors.bg_main)

    if total == 0 then
        local msg = "ПО ТВОЕМУ ЗАПРОСУ, НИЧЕГО НЕ НАЙДЕНО!"
        local msgX = math.floor((80 - unicode.len(msg)) / 2) + 1
        bufferSet(msgX, 14, msg, colors.error)
    else
        for i = 1, visibleRows do
            local itemIndex = listScroll + i - 1
            local item = filteredItems[itemIndex]
            local y = 6 + i
            local isSelected = (itemIndex == selectedIndex)
            local isHovered = (itemIndex == hoveredIndex)
            
            if item then
                drawSingleRow(y, item, isHovered, isSelected, itemIndex)
            else
                bufferFill(2, y, 76, 1, " ", colors.text_main, colors.bg_main)
            end
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
    
    if newScroll == listScroll then
        return
    end
    
    listScroll = newScroll
    markDirty()
end

function drawBuyButtons()
    writeDebugFile("========== drawBuyButtons() ==========")
    
    bufferFill(2, 24, 76, 1, " ", colors.text_main, colors.bg_main)
    
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
    
    if selectedItem and (currentShopMode ~= "buy" or selectedItem.qty > 0) then
        nextButton.fg = colors.accent_secondary
    else
        nextButton.fg = colors.inactive
    end

    drawFlexButton(backButton)
    drawFlexButton(nextButton)
    drawTempMessage()
    writeDebugFile("========================================")
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
    
    bufferClear()
    
    local border_color = 0x00E5C9
    local text_color = 0x00FFCC
    local sub_color = 0xFFFF00
    local hint_color = 0xAAAAAA
    
    bufferSet(1, 1, "┌", border_color)
    bufferFill(2, 1, 78, 1, "─", border_color)
    bufferSet(80, 1, "┐", border_color)
    for y = 2, 24 do
        bufferSet(1, y, "│", border_color)
        bufferSet(80, y, "│", border_color)
    end
    bufferSet(1, 24, "└", border_color)
    bufferFill(2, 24, 78, 1, "─", border_color)
    bufferSet(80, 24, "┘", border_color)
    
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
        0x003D33,
        0x005A4C,
        0x007A66,
        0x009980,
        0x00B899,
        0x00D4B3,
        0x00E5C9,
        0x33FFD6,
    }
    
    local diamX = 17
    local diamY = 3
    
    for i, line in ipairs(diamond) do
        local color = gradient[math.min(math.floor((i-1) / 2) + 1, #gradient)]
        bufferSet(diamX, diamY + i - 1, line, color)
    end
    
    local cx = 41
    
    if shopPaused then
        bufferSet(cx - 2, 21, " РЕЖИМ ОБСЛУЖИВАНИЯ", colors.error)
        bufferSet(cx - 2, 22, " Магазин временно закрыт", colors.error)
        bufferSet(cx - 2, 23, " Пожалуйста, зайдите позже", colors.text_main)
    else
        bufferSet(cx - 2, 21, "VIP SHOP", text_color)
        bufferSet(cx - 6, 22, "◆ McSkill HiTech ◆", sub_color)
        bufferSet(cx - 10, 23, "Встаньте на ПИМ для входа", hint_color)
    end
end

function drawMainMenu()
    writeDebugLog("drawMainMenu()")
    
    bufferSet(1, 1, "┌", colors.accent_secondary)
    bufferFill(2, 1, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 1, "┐", colors.accent_secondary)
    for y = 2, 24 do
        bufferSet(1, y, "│", colors.accent_secondary)
        bufferSet(80, y, "│", colors.accent_secondary)
    end
    bufferSet(1, 24, "└", colors.accent_secondary)
    bufferFill(2, 24, 78, 1, "─", colors.accent_secondary)
    bufferSet(80, 24, "┘", colors.accent_secondary)
    
    if currentPlayer then
        local hello1 = "Добро пожаловать, "
        local hello2 = currentPlayer .. "!"
        local full1 = hello1 .. hello2
        local x1 = math.floor((80 - unicode.len(full1))/2) + 2
        bufferSet(x1, 4, hello1, colors.success)
        bufferSet(x1 + unicode.len(hello1), 4, hello2, colors.text_bright)

        local coin = coinBalance or 0.0
        local ema = emaBalance or 0.0
        
        local balanceText = "Баланс: " .. string.format("%.2f", coin) .. " Coina ₵"
        local balanceX = math.floor((80 - unicode.len(balanceText .. " | ЭМЫ: " .. string.format("%.2f", ema) .. " ۞")) / 2) + 1
        bufferSet(balanceX, 5, "Баланс: ", colors.white)
        bufferSet(balanceX + unicode.len("Баланс: "), 5, string.format("%.2f", coin) .. " Coina ₵", colors.accent_main)
        bufferSet(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵"), 5, " | ", colors.white)
        bufferSet(balanceX + unicode.len("Баланс: ") + unicode.len(string.format("%.2f", coin) .. " Coina ₵") + unicode.len(" | "), 5, "ЭМЫ: " .. string.format("%.2f", ema) .. " ۞", colors.tomato)
        
        local boundInfo = ""
        local boundColor = colors.error
        
        local isBound = getBindingStatus()
        
        if isBound then
            boundInfo = "  АККАУНТ ПРИВЯЗАН " 
            boundColor = colors.success
        else
            boundInfo = "  АККАУНТ НЕ ПРИВЯЗАН"
            boundColor = colors.error
        end
        
        local boundX = math.floor((80 - unicode.len(boundInfo)) / 2) + 1
        bufferSet(boundX, 2, boundInfo, boundColor)

        if not playerAgreed then
            if showShopDenied then
                bufferSet(math.floor((80 - unicode.len("Доступ запрещён. Примите соглашение [Соглашение]")) / 2) + 1, 8, "Доступ запрещён. Примите соглашение [Соглашение]", colors.error)
            else
                bufferSet(math.floor((80 - unicode.len("Вы не приняли пользовательское соглашение! Нажмите [Соглашение]")) / 2) + 1, 8, "Вы не приняли пользовательское соглашение! Нажмите [Соглашение]", colors.accent_secondary)
            end
        else
            bufferFill(2, 8, 76, 1, " ", colors.text_main, colors.bg_main)
        end

        for _, btn in pairs(menuButtons) do
            bufferFill(btn.x, btn.y, btn.xs, btn.ys, " ", btn.fg or colors.text_main, btn.bg or colors.bg_button)
            local text = btn.text or ""
            local textX = btn.x + math.floor((btn.xs - unicode.len(text)) / 2)
            local textY = btn.y + math.floor((btn.ys - 1) / 2)
            bufferSet(textX, textY, text, btn.fg or colors.text_main, btn.bg or colors.bg_button)
        end
        
        bufferSet(4, 24, "[ ПОДДЕРЖКА ]", colors.error)
        bufferSet(35, 24, "[ СОГЛАШЕНИЕ ]", colors.error)
        bufferSet(68, 24, "[ ОТЗЫВЫ ]", colors.error)
        
        bufferFill(2, 6, 76, 1, " ", colors.text_main, colors.bg_main)
        bufferFill(2, 7, 76, 1, " ", colors.text_main, colors.bg_main)
        bufferFill(2, 9, 76, 8, " ", colors.text_main, colors.bg_main)
        bufferFill(2, 18, 76, 6, " ", colors.text_main, colors.bg_main)
        
    else
        drawWelcomeScreen()
    end
    
    if tempMessage and tempMessage ~= "" then
        bufferFill(1, 25, 80, 1, " ", colors.success, colors.bg_main)
        local x = math.floor((80 - unicode.len(tempMessage)) / 2) + 1
        bufferSet(x, 25, tempMessage, colors.success, colors.bg_main)
    else
        bufferFill(1, 25, 80, 1, " ", colors.text_main, colors.bg_main)
    end
end

function drawShopMenu()
    writeDebugLog("drawShopMenu()")
    clear()
    drawScreenBorder()
    drawCenteredText(6, " МАГАЗИН", colors.accent_secondary)
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

    local authBtn = {
        text = "[ АУТЕНТИФИКАЦИЯ ]",
        x = 20,
        y = 24,
        xs = unicode.len("[ АУТЕНТИФИКАЦИЯ ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }

    local backButton = {
        text = "[ НАЗАД ]",
        x = 50,
        y = 24,
        xs = unicode.len("[ НАЗАД ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }

    drawFlexButton(authBtn)
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
    writeDebugFile(">>> drawPurchaseScreen()")
    currentScreen = "purchase"
    clear()
    drawScreenBorder()
    drawBalanceLine(3, 1)

    if not purchaseItem then
        writeDebugFile("❌ drawPurchaseScreen: purchaseItem = nil!")
        writeErrorLog("❌ drawPurchaseScreen: purchaseItem = nil!")
        drawCenteredText(10, "Ошибка: предмет не выбран", colors.error)
        local backBtn = {x = 37, y = 24, xs = unicode.len("[ НАЗАД ]") + 2, ys = 1, text = "[ НАЗАД ]", bg = colors.bg_button, fg = colors.accent_secondary}
        drawFlexButton(backBtn)
        drawTempMessage()
        return
    end

    writeDebugFile("✅ purchaseItem: " .. tostring(purchaseItem.displayName))

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
    updateSelectorDisplay(nil)
    pcall(selector.setSlot, 0, nil)
    pcall(selector.setSlot, 1, nil)
    drawMainMenu()
    forceRender()
end

function goToShop()
    writeDebugLog("goToShop()")
    currentScreen = "shop"
    drawShopMenu()
    forceRender()
end

function goToBuy()
    writeDebugLog("goToBuy()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        forceRender()
        event.timer(3, function() 
            markDirty() 
            return false 
        end)
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
    forceRender()
end

function goToSell()
    writeDebugLog("goToSell()")
    if not playerAgreed then
        drawCenteredText(12, "Вы не приняли пользовательское соглашение!", colors.error)
        drawCenteredText(13, "Нажмите [Помощь] и ознакомьтесь с условиями.", colors.text_main)
        forceRender()
        event.timer(3, function() 
            markDirty() 
            return false 
        end)
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
    forceRender()
end

function goToSellConfirm(item)
    writeDebugFile(">>> goToSellConfirm()")
    if not item then
        writeDebugFile("❌ goToSellConfirm: item = nil!")
        writeErrorLog("❌ goToSellConfirm: item = nil!")
        return
    end
    sellConfirmItem = item
    foundAmount = 0
    showSellPopup = false
    currentScreen = "sell_scan"
    writeDebugFile("✅ sellConfirmItem установлен: " .. tostring(sellConfirmItem.displayName))
    writeDebugFile("✅ currentScreen = " .. currentScreen)
    markDirty()
end

function goToPurchase(item)
    writeDebugFile(">>> goToPurchase()")
    if not item then
        writeDebugFile("❌ goToPurchase: item = nil!")
        writeErrorLog("❌ goToPurchase: item = nil!")
        return
    end
    purchaseItem = item
    purchaseQuantity = 1
    currentScreen = "purchase"
    writeDebugFile("✅ purchaseItem установлен: " .. tostring(purchaseItem.displayName))
    writeDebugFile("✅ currentScreen = " .. currentScreen)
    markDirty()
end

function goToReport()
    writeDebugLog("goToReport()")
    currentScreen = "report"
    reportInput = ""
    markDirty()
end

function goToHelp()
    writeDebugLog("goToHelp()")
    currentScreen = "agreement"
    if type(drawAgreementScreen) == "function" then
        markDirty()
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
        forceRender()
    end
end

function goToAccount()
    writeDebugLog("goToAccount()")
    if not currentToken then
        drawCenteredText(12, "Ошибка: нет авторизации", colors.error)
        return
    end
    currentScreen = "account_loading"
    markDirty()
    local player = playersIndex[currentPlayer]
    if player then
        currentScreen = "account"
        markDirty()
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
    markDirty()
end

-- ============================================================
-- ★★★ АУТЕНТИФИКАЦИЯ (ПРИВЯЗКА АККАУНТА) ★★★
-- ============================================================

function showAuthPopup()
    writeDebugLog("showAuthPopup()")
    currentScreen = "auth_popup"
    authCodeInput = authCodeInput or ""
    
    local popupWidth = 50
    local popupHeight = 16
    local popupX = math.floor((80 - popupWidth) / 2) + 1
    local popupY = math.floor((25 - popupHeight) / 2)
    
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, 80, 25, " ")
    gpu.setBackground(0x0A0A1A)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    
    gpu.setForeground(0x00FFCC)
    gpu.fill(popupX, popupY, popupWidth, 1, "=")
    gpu.fill(popupX, popupY + popupHeight - 1, popupWidth, 1, "=")
    for i = 1, popupHeight - 2 do
        gpu.set(popupX, popupY + i, "|")
        gpu.set(popupX + popupWidth - 1, popupY + i, "|")
    end
    gpu.set(popupX, popupY, "+")
    gpu.set(popupX + popupWidth - 1, popupY, "+")
    gpu.set(popupX, popupY + popupHeight - 1, "+")
    gpu.set(popupX + popupWidth - 1, popupY + popupHeight - 1, "+")
    
    gpu.setForeground(0x00FFCC)
    gpu.set(popupX + math.floor((popupWidth - 22) / 2) + 1, popupY + 1, "🔐 АУТЕНТИФИКАЦИЯ")
    
    gpu.setForeground(colors.white)
    gpu.set(popupX + 3, popupY + 3, "👤 Игрок: ")
    gpu.setForeground(colors.accent_main)
    gpu.set(popupX + 15, popupY + 3, currentPlayer or "Неизвестно")
    
    local savedBound = loadBoundPlayer()
    local isBound = (boundPlayer and boundPlayer ~= "") or (savedBound and savedBound ~= "")
    
    if isBound then
        local displayName = boundPlayer or savedBound
        
        gpu.setForeground(colors.success)
        gpu.set(popupX + 3, popupY + 5, "✅ Аккаунт ПРИВЯЗАН к: " .. displayName)
        
        gpu.setForeground(colors.text_main)
        gpu.set(popupX + 3, popupY + 7, "   Для отвязки нажмите кнопку ниже")
        
        local unbindBtn = {
            text = "[ ОТВЯЗАТЬ ]",
            x = popupX + 5,
            y = popupY + popupHeight - 3,
            xs = unicode.len("[ ОТВЯЗАТЬ ]") + 2,
            ys = 1,
            bg = 0x441111,
            fg = colors.error
        }
        drawFlexButton(unbindBtn)
        
        local closeBtn = {
            text = "[ ЗАКРЫТЬ ]",
            x = popupX + popupWidth - 12,
            y = popupY + popupHeight - 3,
            xs = 10,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.accent_secondary
        }
        drawFlexButton(closeBtn)
        
        while currentScreen == "auth_popup" do
            local ev = {event.pull(0.5)}
            
            if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
                writeDebugLog("👤 Игрок ушёл с PIM во время аутентификации")
                currentScreen = "welcome"
                markDirty()
                break
            end
            
            if ev[1] == "touch" then
                local x, y = ev[3], ev[4]
                
                if isButtonClicked(closeBtn, x, y) then
                    goBackToMenu()
                    break
                end
                
                if isButtonClicked(unbindBtn, x, y) then
                    showUnbindConfirmPopup()
                    break
                end
            end
        end
        
    else
        gpu.setForeground(colors.text_main)
        gpu.set(popupX + 3, popupY + 5, "📋 Введите код из браузера:")
        gpu.setForeground(colors.inactive)
        gpu.set(popupX + 3, popupY + 6, "   (код отображается на сайте)")
        
        gpu.setBackground(0x000000)
        gpu.fill(popupX + 5, popupY + 8, popupWidth - 10, 3, " ")
        gpu.setBackground(0x1A1A2E)
        gpu.fill(popupX + 6, popupY + 9, popupWidth - 12, 1, " ")
        
        gpu.setForeground(0x00FFAA)
        local displayCode = authCodeInput or ""
        if #displayCode < 6 then
            displayCode = displayCode .. "_"
        end
        local codeX = popupX + 6 + math.floor((popupWidth - 12 - unicode.len(displayCode)) / 2)
        gpu.set(codeX, popupY + 9, displayCode)
        gpu.setBackground(0x0A0A1A)
        
        local closeBtn = {
            text = "[ ЗАКРЫТЬ ]",
            x = popupX + popupWidth - 12,
            y = popupY + popupHeight - 3,
            xs = 10,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.error
        }
        local confirmBtn = {
            text = "[ ПОДТВЕРДИТЬ ]",
            x = popupX + 3,
            y = popupY + popupHeight - 3,
            xs = 13,
            ys = 1,
            bg = colors.bg_button,
            fg = colors.success
        }
        
        drawFlexButton(closeBtn)
        drawFlexButton(confirmBtn)
        
        local isEditing = true
        while currentScreen == "auth_popup" and isEditing do
            local ev = {event.pull(0.5)}
            
            if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
                writeDebugLog("👤 Игрок ушёл с PIM во время аутентификации")
                currentScreen = "welcome"
                markDirty()
                break
            end
            
            if ev[1] == "touch" then
                local x, y = ev[3], ev[4]
                
                if isButtonClicked(closeBtn, x, y) then
                    isEditing = false
                    goBackToMenu()
                    break
                end
                
                if authCodeInput and #authCodeInput == 6 then
                    isEditing = false
                    verifyAuthCode(authCodeInput)
                else
                    gpu.setForeground(colors.error)
                    gpu.set(popupX + 3, popupY + 13, " Введите 6-значный код!")
                    forceRender()
                    event.timer(1.5, function()
                        markDirty()
                        return false
                    end)
                end
                
            elseif ev[1] == "key_down" then
                local ch = ev[3]
                
                if ch == 13 then
                if authCodeInput and #authCodeInput == 6 then
                    isEditing = false
                    verifyAuthCode(authCodeInput)
                else
                    gpu.setForeground(colors.error)
                    gpu.set(popupX + 3, popupY + 13, " Введите 6-значный код!")
                    forceRender()
                    event.timer(1.5, function()
                        markDirty()
                        return false
                    end)
                end
                    
                elseif ch == 8 then
                    authCodeInput = unicode.sub(authCodeInput or "", 1, -2)
                    markDirty()
                    
                elseif ch >= 48 and ch <= 57 then
                    if unicode.len(authCodeInput or "") < 6 then
                        authCodeInput = (authCodeInput or "") .. unicode.char(ch)
                        markDirty()
                    end
                end
            end
        end
    end
end

function showUnbindConfirmPopup()
    writeDebugLog("showUnbindConfirmPopup()")
    
    local popupWidth = 46
    local popupHeight = 10
    local popupX = math.floor((80 - popupWidth) / 2) + 1
    local popupY = math.floor((25 - popupHeight) / 2)
    
    gpu.setBackground(0x000000)
    gpu.fill(popupX - 2, popupY - 2, popupWidth + 4, popupHeight + 4, " ")
    gpu.setBackground(0x0A0A1A)
    gpu.fill(popupX, popupY, popupWidth, popupHeight, " ")
    
    gpu.setForeground(colors.error)
    gpu.fill(popupX, popupY, popupWidth, 1, "═")
    gpu.fill(popupX, popupY + popupHeight - 1, popupWidth, 1, "═")
    for i = 1, popupHeight - 2 do
        gpu.set(popupX, popupY + i, "║")
        gpu.set(popupX + popupWidth - 1, popupY + i, "║")
    end
    gpu.set(popupX, popupY, "╔")
    gpu.set(popupX + popupWidth - 1, popupY, "╗")
    gpu.set(popupX, popupY + popupHeight - 1, "╚")
    gpu.set(popupX + popupWidth - 1, popupY + popupHeight - 1, "╝")
    
    local titleText = "ПОДТВЕРЖДЕНИЕ"
    local titleLen = unicode.len(titleText)
    gpu.setForeground(colors.error)
    gpu.set(popupX + math.floor((popupWidth - titleLen) / 2), popupY + 1, titleText)
    
    gpu.setForeground(colors.text_main)
    gpu.set(popupX + 3, popupY + 3, "Вы действительно хотите")
    gpu.set(popupX + 3, popupY + 4, "ОТВЯЗАТЬ аккаунт?")
    
    gpu.setForeground(colors.inactive)
    gpu.set(popupX + 3, popupY + 6, "После отвязки доступ к магазину")
    gpu.set(popupX + 3, popupY + 7, "будет ограничен до новой привязки.")
    
    local yesBtn = {
        text = "[ ДА, ОТВЯЗАТЬ ]",
        x = popupX + 5,
        y = popupY + popupHeight - 2,
        xs = unicode.len("[ ДА, ОТВЯЗАТЬ ]") + 2,
        ys = 1,
        bg = 0x441111,
        fg = colors.error
    }
    local noBtn = {
        text = "[ ОТМЕНА ]",
        x = popupX + popupWidth - unicode.len("[ ОТМЕНА ]") - 4,
        y = popupY + popupHeight - 2,
        xs = unicode.len("[ ОТМЕНА ]") + 2,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(yesBtn)
    drawFlexButton(noBtn)
    
    while true do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "player_off" or ev[1] == "pim_player_leave" then
            writeDebugLog("👤 Игрок ушёл с PIM во время подтверждения отвязки")
            currentScreen = "welcome"
            markDirty()
            break
        end
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            if isButtonClicked(noBtn, x, y) then
                showAuthPopup()
                break
            end
            
            if isButtonClicked(yesBtn, x, y) then
                unbindAccount()
                break
            end
        end
    end
end

function verifyAuthCode(code)
    drawCenteredText(15, "Проверка кода...", colors.accent_secondary)
    forceRender()
    
    event.timer(0.1, function()
        local success, response = pcall(function()
            return internet.request(WEB_URL .. "/api/verify_auth_code", toJson({
                code = code,
                game_player = currentPlayer
            }), {
                ["Content-Type"] = "application/json",
                ["Connection"] = "close",
                ["Timeout"] = "5"
            })
        end)
        
        if success and response then
            local body = ""
            for chunk in response do
                body = body .. chunk
            end
            local data = parseJSON(body)
            
            if data and data.success then
                drawCenteredText(15, "✅ Аккаунт успешно привязан!", colors.success)
                drawCenteredText(16, "Теперь вы можете пользоваться магазином", colors.text_main)
                
                if data.player then
                    boundPlayer = data.player
                    saveBoundPlayer(data.player)
                    bindingCache.isBound = true
                    bindingCache.lastCheck = os.clock()
                    addLog("🔗 Аккаунт привязан: " .. boundPlayer)
                end
                
                syncCurrentPlayer()
                event.timer(2, function() 
                    goBackToMenu() 
                    return false 
                end)
                
            else
                local errorMsg = (data and data.error) or "Ошибка привязки"
                drawCenteredText(15, "❌ " .. errorMsg, colors.error)
                
                if data and data.bound then
                    drawCenteredText(16, "Этот игрок уже привязан к другому аккаунту", colors.text_main)
                end
                
                event.timer(2, function() 
                    markDirty() 
                    return false 
                end)
            end
        else
            drawCenteredText(15, "❌ Ошибка соединения с сервером", colors.error)
            event.timer(2, function() 
                markDirty() 
                return false 
            end)
        end
        return false
    end)
end

function unbindAccount()
    if not currentPlayer then
        showTempMessage("Ошибка: игрок не авторизован", 2)
        return
    end
    
    local json_data = toJson({
        site_user = currentPlayer
    })
    
    local success, response = pcall(function()
        return internet.request(WEB_URL .. "/api/unbind_player", json_data, {
            ["Content-Type"] = "application/json; charset=utf-8",
            ["Connection"] = "close",
            ["Timeout"] = "5"
        })
    end)
    
    if success and response then
        local body = ""
        for chunk in response do
            body = body .. chunk
        end
        local data = parseJSON(body)
        
        if data and data.success then
            boundPlayer = nil
            clearBoundPlayer()
            
            gpu.setForeground(colors.success)
            gpu.set(28, 17, "✅ Аккаунт ОТВЯЗАН!")
            gpu.setForeground(colors.text_main)
            gpu.set(23, 18, "   Доступ к магазину ограничен")
            addLog("🔓 Аккаунт отвязан: " .. currentPlayer)
            event.timer(2, function()
                goBackToMenu()
                return false
            end)
        else
            local errorMsg = (data and data.error) or "Ошибка отвязки"
            gpu.setForeground(colors.error)
            gpu.set(20, 17, "❌ " .. errorMsg)
            forceRender()
            event.timer(2, function()
                markDirty()
                return false
            end)
        end
    else
        gpu.setForeground(colors.error)
        gpu.set(20, 17, "❌ Ошибка соединения")
        forceRender()
        event.timer(2, function()
            markDirty()
            return false
        end)
    end
end

function showQRCodePopup()
    writeDebugLog("showQRCodePopup()")
    currentScreen = "qr_popup"
    
    local oldWidth, oldHeight = gpu.getResolution()
    gpu.setResolution(160, 50)
    
    gpu.setBackground(0x000000)
    gpu.fill(1, 1, 160, 50, " ")
    
    gpu.setForeground(0x00FFCC)
    gpu.fill(1, 1, 160, 1, "=")
    gpu.fill(1, 50, 160, 1, "=")
    for i = 2, 49 do
        gpu.set(1, i, "|")
        gpu.set(160, i, "|")
    end
    gpu.set(1, 1, "+")
    gpu.set(160, 1, "+")
    gpu.set(1, 50, "+")
    gpu.set(160, 50, "+")
    
    local titleText = "QR-КОД ДЛЯ ВХОДА"
    local titleX = 80 - math.floor(#titleText / 2) + 2
    gpu.setForeground(0x00FFCC)
    gpu.set(titleX, 2, titleText)
    
    local playerText = "Игрок: " .. (currentPlayer or "?")
    local playerX = 80 - math.floor(#playerText / 2)   
    gpu.setForeground(colors.white)
    gpu.set(playerX, 4, playerText)
    
    local hintText = "Отсканируйте QR-код для входа на сайт"
    local hintX = 80 - math.floor(#hintText / 2) + 11
    gpu.setForeground(colors.inactive)
    gpu.set(hintX, 5, hintText)
    
    local qrY = 7
    local qrX = 44
    
    local asciiQR = [[
█████████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████████
██████░░░░░░░░░░███████░██░░██████░██████░░░░██░░░███░░░░░░░░░░██████
████░░█████████░░████████░████░░██░░░██░░░░██░░░████░░█████████░░████
████░░██░░░░░██░░██████░░░████████░████░░░░████░████░░██░░░░░██░░████
████░░██░░░░░██░░████░░███░░██░░░░███████░░██░░░████░░██░░░░░██░░████
████░░██░░░░░██░░████░░░████████████░░░██░░██░░░████░░██░░░░░██░░████
████░░█████████░░███████░░░░░░░░░░░██░░░░██░░███░░██░░█████████░░████
█████░░░░░░░░░░░███░░██░██░░██░░██░██░░██░░██░██░░███░░░░░░░░░░░█████
███████████████████████░██░░░░░░░░░░░██░░░░███░░█████████████████████
████████░░░░███░░████░░░░░░░██░░███░░████░░░░███░░░░░░██░████████████
████████░░░░░░░██████░░░░░██░░░░░░█░░░░██████░░░██░░░░███████░░░░████
██████░░░░██░██░░░░█████░░░░████░░░██░░░░░░░░░░░░░██░░███████░░░░████
████████████░████████░░░█████████████████████░██████░░░░░░░██████████
████░░██████░░░░░░░██░░██████████████████████░░░░░░░██░░█████████████
████████░░██░██████░░██████░░░██████████████████░░████░░░██░░████████
██████░░░░░░░██░░██░░██░█████░░░░░░░░░░░██████████░░░░█████░░████████
████░░████░░█████████░░░██████░░░░░░░░░██████░████░░████░░░████░░████
██████████░░█░░░░░░████████████░░░░░░░████████░░░░██░░░░░░░██████████
█████████████░░██░░░░░░███████░░█████████████░░░████░░░░░██░░░░██████
████░░██░░██░░░░░░░██░░░████████████████████████████████░██░░████████
████░░░░█████████░░██░░░██████░░█████░░██████░████░░░░░░░████░░██████
████░░░░████░░░░░██░░░░██████████████████████░████░░█████░░░░████████
████░░██░░███░░██████░░░██████████████████████████░░███████░░██░░████
████████████░░░░░██████░████░░░░░░░░░░░████░░░██████░░░░█░░░░░░░░████
██████░░███████████░░░░░██░░░░████░████░░████░░░░░░░██░░█████░░░░████
████░░██████░░░░░░░░░███░░██░░█████░░██░░░░░░░░░░░░░░░░░░████░░░░████
███████████████████░░█████░░██░░░░░░░░░░░░░██░██░░██████░██░░░░██████
█████░░░░░░░░░░░███░░░░░██░░░░██░░░░░░░██████░░░░░██░░██░░░░░████████
████░░█████████░░████░░░░░░░░░████░████████░░░██░░██████░██░░░░░░████
████░░██░░░░░██░░█████████░░██████░██░░░░░░████░░░░░░░░░░░░░░░░██████
████░░██░░░░░██░░██░░███░░██░░░░░░█░░████░░░░███░░████░░█████████████
████░░██░░░░░██░░██░░███████████░░░██░░██░░██░░░░░░░░░░░░░░░░░░░░████
████░░█████████░░██████░░░██░░███████░░████░░█░░░░░░░░░░░░░░░░░░░████
██████░░░░░░░░░░████████░░████████░██░░███████░░░░░░░░░░░░░░░░░░░████
█████████████████████████████████████████████████████████████████████
█████████████████████████████████████████████████████████████████████
]]
    
    local lines = {}
    for line in asciiQR:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    
    for i, line in ipairs(lines) do
        gpu.set(qrX, qrY + i - 1, line)
    end
    
    local linkText = "Ссылка: https://zozido.pythonanywhere.com/"
    local linkX = 80 - math.floor(#linkText / 2) + 1
    gpu.setForeground(colors.inactive)
    gpu.set(linkX, qrY + 39, linkText)
    
    local bottomHint = "[ Нажмите ЗАКРЫТЬ или ESC для возврата ]"
    local bottomHintX = 80 - math.floor(#bottomHint / 2) + 12
    gpu.setForeground(colors.text_main)
    gpu.set(bottomHintX, 48, bottomHint)
    
    local closeBtn = {
        text = "[ ЗАКРЫТЬ ]",
        x = 80 - 6,
        y = 49,
        xs = 12,
        ys = 1,
        bg = colors.bg_button,
        fg = colors.accent_secondary
    }
    drawFlexButton(closeBtn)
    
    while currentScreen == "qr_popup" do
        local ev = {event.pull(0.5)}
        
        if ev[1] == "touch" then
            local x, y = ev[3], ev[4]
            
            if isButtonClicked(closeBtn, x, y) then
                break
            end
            
        elseif ev[1] == "key_down" then
            local code = ev[3]
            if code == 27 then
                break
            end
        end
    end
    
    gpu.setResolution(oldWidth, oldHeight)
    markDirty()
end

function decodeBase64(data)
    if not data or data == "" then
        return ""
    end
    
    local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    local result = {}
    local padding = 0
    
    data = data:gsub('[^A-Za-z0-9+/=]', '')
    
    if data:sub(-1) == '=' then
        padding = padding + 1
    end
    if data:sub(-2, -1) == '==' then
        padding = padding + 1
    end
    
    for i = 1, #data, 4 do
        local chunk = data:sub(i, i + 3)
        local n = 0
        
        for j = 1, #chunk do
            local c = chunk:sub(j, j)
            if c ~= '=' then
                local index = b64chars:find(c)
                if index then
                    n = n * 64 + (index - 1)
                end
            end
        end
        
        local bytes = {}
        for j = 3, 1, -1 do
            if i + j - 1 <= #data - padding then
                table.insert(bytes, 1, string.char(n % 256))
                n = math.floor(n / 256)
            end
        end
        table.insert(result, table.concat(bytes))
    end
    
    return table.concat(result)
end

-- ============================================================
-- ВЫПОЛНЕНИЕ ПОКУПКИ И ПРОДАЖИ
-- ============================================================

function performSell()
    if not playerAgreed then
        drawCenteredText(17, "Сначала примите пользовательское соглашение", colors.error)
        forceRender()
        event.timer(2, function() 
            markDirty() 
            return false 
        end)
        return
    end

    if TRANSACTION_LOCK then
        writeDebugLog("⚠️ Продажа уже выполняется")
        showTempMessage("Подождите, транзакция выполняется...", 2)
        return
    end
    lockTransactions()

    if sellConfirmItem and sellConfirmItem._processing then
        writeDebugLog("⚠️ Продажа уже выполняется, пропускаем")
        unlockTransactions()
        return
    end
    
    if sellConfirmItem and sellConfirmItem._processed then
        writeDebugLog("⚠️ Продажа уже обработана, пропускаем")
        unlockTransactions()
        return
    end

    showSellPopup = false
    drawCenteredText(17, "Выполняется пополнение...", colors.accent_main)
    forceRender()
    
    event.timer(0.01, function()
        sellConfirmItem._processing = true

        local realExtracted = extractToME(sellConfirmItem.internalName, foundAmount, sellConfirmItem.damage or 0)
        if realExtracted == 0 then
            sellConfirmItem._processing = false
            drawCenteredText(17, "Не удалось изъять предметы! Проверьте инвентарь.", colors.error)
            forceRender()
            event.timer(2, function()
                unlockTransactions()
                currentScreen = "shop_sell"
                markDirty()
                return false
            end)
            return false
        end

        local value = realExtracted * sellConfirmItem.price
        if sellConfirmItem.internalName == "customnpcs:npcMoney" then
            emaBalance = emaBalance + value
        else
            coinBalance = coinBalance + value
        end
        playerTransactions = playerTransactions + 1

        if currentPlayer and playersIndex[currentPlayer] then
            local player = playersIndex[currentPlayer]
            player.balance = coinBalance
            player.emaBalance = emaBalance
            player.transactions = playerTransactions
            saveDB()
            writeDebugLog("💾 Баланс сохранён после продажи для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        else
            writeErrorLog("⚠️ Игрок не найден при продаже: " .. tostring(currentPlayer))
        end

        addTransaction("sell", currentPlayer, sellConfirmItem.displayName, realExtracted, value, 0)

        sellConfirmItem._processed = true
        sellConfirmItem._processing = false

        local currencySymbol = (sellConfirmItem.internalName == "customnpcs:npcMoney") and "۞" or "₵"
        drawCenteredText(17, "Успешно! +" .. string.format("%.2f", value) .. " " .. currencySymbol, colors.success)
        forceRender()

        event.timer(0.8, function()
            unlockTransactions()
            currentScreen = "shop_sell"
            showSellPopup = false
            markDirty()
            
            writeDebugFile("========================================")
            writeDebugFile("✅ performSell() ЗАВЕРШЕНА")
            writeDebugFile("   realExtracted=" .. tostring(realExtracted))
            writeDebugFile("   value=" .. tostring(value))
            writeDebugFile("   currentPlayer=" .. tostring(currentPlayer))
            writeDebugFile("========================================")
            return false
        end)
        return false
    end)
end

function performBuy()
    if not playerAgreed then
        drawCenteredText(20, "Сначала примите пользовательское соглашение", colors.error)
        forceRender()
        event.timer(2, function() 
            markDirty() 
            return false 
        end)
        return
    end

    if TRANSACTION_LOCK then
        writeDebugLog("⚠️ Покупка уже выполняется")
        showTempMessage("Подождите, транзакция выполняется...", 2)
        return
    end
    lockTransactions()

    if not purchaseItem then
        writeErrorLog("❌ performBuy: purchaseItem = nil!")
        unlockTransactions()
        return
    end

    local me = component.me_interface
    local item = purchaseItem

    local actualQty = getActualItemQuantity(item.internalName, item.damage)
    if actualQty <= 0 then
        drawCenteredText(20, "Товар закончился! Обновление списка...", colors.error)
        forceRender()
        event.timer(0.8, function()
            loadBuyItems(true)
            unlockTransactions()
            currentScreen = "shop_buy"
            markDirty()
            return false
        end)
        return
    end

    local qty = purchaseQuantity
    if qty > actualQty then
        qty = actualQty
        purchaseQuantity = qty
        markDirty()
    end

    if qty <= 0 then
        drawCenteredText(20, "Выберите количество!", colors.error)
        forceRender()
        event.timer(0.8, function()
            unlockTransactions()
            currentScreen = "shop_buy"
            markDirty()
            return false
        end)
        return
    end

    local totalCoin = (item.priceCoin or 0) * qty
    local totalEma = (item.priceEma or 0) * qty
    if coinBalance < totalCoin or emaBalance < totalEma then
        showInsufficientPopup = true
        insufficientBalanceCoin = coinBalance
        insufficientBalanceEma = emaBalance
        unlockTransactions()
        markDirty()
        drawInsufficientPopup()
        return
    end

    drawCenteredText(20, "Выполняется покупка...", colors.accent_main)
    forceRender()
    
    event.timer(0.1, function()
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
            unlockTransactions()
            markDirty()
            drawInventoryFullPopup()
            return false
        end

        if extracted < qty then
            local actuallySpentCoin = extracted * (item.priceCoin or 0)
            local actuallySpentEma = extracted * (item.priceEma or 0)
            coinBalance = coinBalance - actuallySpentCoin
            emaBalance = emaBalance - actuallySpentEma
            playerTransactions = playerTransactions + 1

            if currentPlayer and playersIndex[currentPlayer] then
                local player = playersIndex[currentPlayer]
                player.balance = coinBalance
                player.emaBalance = emaBalance
                player.transactions = playerTransactions
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
            unlockTransactions()
            markDirty()
            drawPartialPopup()
            return false
        end

        coinBalance = coinBalance - totalCoin
        emaBalance = emaBalance - totalEma
        playerTransactions = playerTransactions + 1

        if currentPlayer and playersIndex[currentPlayer] then
            local player = playersIndex[currentPlayer]
            player.balance = coinBalance
            player.emaBalance = emaBalance
            player.transactions = playerTransactions
            saveDB()
            writeDebugLog("💾 Баланс сохранён (полн.) для " .. currentPlayer .. ": Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
        else
            writeErrorLog("⚠️ Игрок не найден при покупке: " .. tostring(currentPlayer))
        end

        addTransaction("buy", currentPlayer, item.displayName, extracted, totalCoin, totalEma)

        local priceStr = ""
        if totalCoin > 0 then
            priceStr = priceStr .. string.format("%.2f", totalCoin) .. "₵"
        end
        if totalEma > 0 then
            if priceStr ~= "" then
                priceStr = priceStr .. " + "
            end
            priceStr = priceStr .. string.format("%.2f", totalEma) .. "۞"
        end
        drawCenteredText(20, "Куплено " .. extracted .. " шт. за " .. priceStr, colors.success)
        forceRender()

        loadBuyItems(true)
        for _, newItem in ipairs(shopItems) do
            if newItem.internalName == item.internalName and newItem.damage == item.damage then
                purchaseItem = newItem
                break
            end
        end
        
        event.timer(0.8, function()
            unlockTransactions()
            currentScreen = "shop_buy"
            markDirty()
            
            writeDebugFile("========================================")
            writeDebugFile("✅ performBuy() ЗАВЕРШЕНА")
            writeDebugFile("   extracted=" .. tostring(extracted))
            writeDebugFile("   totalCoin=" .. tostring(totalCoin))
            writeDebugFile("   totalEma=" .. tostring(totalEma))
            writeDebugFile("   currentPlayer=" .. tostring(currentPlayer))
            writeDebugFile("========================================")
            return false
        end)
        return false
    end)
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

    function fixDisplayNames(items)
        local fixed_items = {}
        for _, item in ipairs(items) do
            local new_item = {}
            for k, v in pairs(item) do
                if k == "displayName" and type(v) == "string" then
                    local fixed = v:gsub("\\u(%x%x%x%x)", function(hex)
                        return unicode.char(tonumber(hex, 16))
                    end)
                    new_item[k] = fixed
                else
                    new_item[k] = v
                end
            end
            table.insert(fixed_items, new_item)
        end
        return fixed_items
    end
    
    if not isShopFile then
        sellItemsList = fixDisplayNames(sellItemsList)
    else
        if fileData.sellItems then
            fileData.sellItems = fixDisplayNames(fileData.sellItems)
        end
    end
    
    writeDebugLog("💾 Сохраняем файл: " .. itemsFile)
    local file = io.open(itemsFile, "w")
    if not file then
        writeErrorLog("❌ Не удалось открыть файл для записи: " .. itemsFile)
        return false
    end
    
    local serialized
    if isShopFile then
        fileData.sellItems = sellItemsList
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
        cachedBuyItems = nil
        cacheTimestamp = 0
        loadBuyItems(true)
        if currentScreen == "shop_buy" then
            markDirty()
        end
    end

    broadcastUpdate()
    return true
end

-- ============================================================
-- ★★★ ИСПРАВЛЕННЫЙ checkWebCommands ★★★
-- ============================================================

function checkWebCommands()
    writeDebugFile(">>> checkWebCommands() ВЫЗВАНА в " .. getRealTimeHM())
    
    if currentPlayer then
        syncCurrentPlayer()
    end
    
    writeDebugLog("🔍 checkWebCommands() запущена в " .. getRealTimeHM())

    local success, err = pcall(function()
        local url = WEB_URL .. "/api/commands"
        writeDebugFile("📡 Запрос к: " .. url)

        local response = internet.request(url, nil, {
            ["Connection"] = "close",
            ["Timeout"] = 2
        })
        
        if not response then
            writeDebugFile("⚠️ Нет ответа от сервера")
            return
        end

        local status = response.getStatus and response:getStatus() or response.code or response.status
        if status then
            if status == 200 or status == 204 then
                writeDebugFile("✅ Статус ответа: " .. tostring(status))
            else
                writeDebugFile("⚠️ Сервер вернул HTTP " .. tostring(status))
                return
            end
        else
            writeDebugFile("⚠️ Не удалось получить статус ответа")
        end

        if status == 204 then
            writeDebugFile("⚠️ Сервер вернул 204 No Content, пропускаем")
            return
        end

        local body = ""
        for chunk in response do
            body = body .. chunk
        end

        writeDebugFile("📥 Получено " .. #body .. " байт")

        if #body < 10 then
            writeDebugFile("⚠️ Ответ слишком короткий")
            return
        end

        local data = parseJSON(body)
        if data then
            writeDebugFile("✅ Распарсено")
        else
            writeDebugFile("❌ Ошибка парсинга JSON")
            writeErrorLog("❌ Ошибка парсинга JSON: " .. string.sub(body, 1, 300))
            return
        end

        if not data.commands or #data.commands == 0 then
            writeDebugFile("⚠️ Нет команд в ответе")
            return
        end

        writeDebugFile("📨 Найдено команд: " .. #data.commands)

        for _, cmd in ipairs(data.commands) do
            local d = cmd.data or cmd
            local requestId = cmd.requestId or os.time()
        
            local function sendResult(success, msg)
                writeDebugFile("📤 [" .. (cmd.command or "unknown") .. "] " .. (success and "✅" or "❌") .. " " .. (msg or ""))
                sendToWeb("/api/command_result", toJson({
                    requestId = requestId,
                    success = success,
                    message = msg or "",
                    command = cmd.command
                }))
            end
        
            writeDebugFile("🔧 Выполняем команду: " .. (cmd.command or "unknown"))
            writeDebugFile("📨 Данные команды: " .. serialization.serialize(d))
        
            if cmd.command == "update_player" or cmd.command == "set_balance" then
                writeDebugFile("📥 Получена команда update_player")
                local playerName = d.name or d.player
                writeDebugFile("   playerName=" .. tostring(playerName))
                writeDebugFile("   balance=" .. tostring(d.balance))
                writeDebugFile("   emaBalance=" .. tostring(d.emaBalance))
                
                if not playerName then
                    sendResult(false, "Нет имени игрока")
                    goto continue
                end
                
                local player = playersIndex[playerName]
                if player then
                    if d.balance then
                        player.balance = tonumber(d.balance) or 0
                        writeDebugFile("   ✅ Баланс установлен: " .. player.balance)
                    end
                    if d.emaBalance then
                        player.emaBalance = tonumber(d.emaBalance) or 0
                        writeDebugFile("   ✅ EMA баланс установлен: " .. player.emaBalance)
                    end
                    saveDBDeferred()
                    addLog("💰 Баланс обновлён: " .. playerName)
                    markDirty()
                    
                    if currentPlayer == playerName then
                        coinBalance = player.balance
                        emaBalance = player.emaBalance
                        writeDebugFile("   ✅ ТЕКУЩИЙ ИГРОК ОБНОВЛЁН: Coin=" .. coinBalance .. ", EMA=" .. emaBalance)
                    end
                    
                    local balance_change = {
                        id = "bal_" .. os.time() .. "_" .. math.random(100000),
                        type = "update_balance",
                        data = {
                            player = playerName,
                            balance = player.balance,
                            emaBalance = player.emaBalance
                        }
                    }
                    add_pending_change(balance_change)
                    
                    sendResult(true, "Баланс обновлён")
                else
                    writeDebugFile("   ❌ Игрок не найден")
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end
            
            if cmd.command == "save_buy_items_incremental" then
                writeDebugFile("📥 save_buy_items_incremental получен")
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
                writeDebugFile("📥 save_shop_items_incremental получен")
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
            
            if cmd.command == "toggle_pause" then
                if d.paused ~= nil then
                    shopPaused = d.paused
                    writeDebugFile("📥 Установлен режим обслуживания: " .. tostring(shopPaused))
                else
                    shopPaused = not shopPaused
                    writeDebugFile("📥 Переключён режим обслуживания: " .. tostring(shopPaused))
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
                markDirty()
                
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
            
            if cmd.command == "terminal_control" then
                local action = d.action
                writeDebugFile("🚨 ПОЛУЧЕНА КОМАНДА: " .. action)
                
                if action == "shutdown" then
                    writeDebugFile("⏻ ВЫКЛЮЧЕНИЕ ТЕРМИНАЛА")
                    sendResult(true, "Терминал выключается...")
                    os.sleep(0.5)
                    
                    local shutdown_attempts = {
                        function() computer.shutdown() end,
                        function() os.execute("shutdown -h now") end,
                        function() os.execute("shutdown") end,
                        function() os.exit(0) end
                    }
                    
                    for i, func in ipairs(shutdown_attempts) do
                        local ok, err = pcall(func)
                        if ok then
                            writeDebugFile("✅ Выключение успешно (способ " .. i .. ")")
                            break
                        else
                            writeDebugFile("⚠️ Способ " .. i .. " не сработал: " .. tostring(err))
                        end
                    end
                    
                elseif action == "reboot" then
                    writeDebugFile("🔄 ПЕРЕЗАГРУЗКА ТЕРМИНАЛА")
                    sendResult(true, "Терминал перезагружается...")
                    os.sleep(0.5)
                    
                    local reboot_attempts = {
                        function() computer.reboot() end,
                        function() os.execute("reboot") end,
                        function() os.execute("shutdown -r now") end,
                        function() os.exit(1) end
                    }
                    
                    for i, func in ipairs(reboot_attempts) do
                        local ok, err = pcall(func)
                        if ok then
                            writeDebugFile("✅ Перезагрузка успешна (способ " .. i .. ")")
                            break
                        else
                            writeDebugFile("⚠️ Способ " .. i .. " не сработал: " .. tostring(err))
                        end
                    end
                end
                goto continue
            end
            
            if cmd.command == "unbind_player" then
                local playerName = d.player
                writeDebugFile("📥 Получена команда отвязки для: " .. playerName)
                
                if currentPlayer == playerName then
                    boundPlayer = nil
                    clearBoundPlayer()
                    bindingCache.isBound = false
                    bindingCache.lastCheck = 0
                    addLog("🔓 Аккаунт отвязан по команде сервера: " .. playerName)
                    markDirty()
                    
                    sendResult(true, "Аккаунт отвязан")
                else
                    sendResult(false, "Игрок не найден")
                end
                goto continue
            end
            
            if cmd.command == "delete_feedback" then
                local index = d.index
                writeDebugFile("🗑️ Удаление отзыва: индекс " .. tostring(index))
                
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
                        writeDebugFile("✅ Отзыв удалён из OC")
                        sendResult(true, "Отзыв удалён")
                    else
                        writeDebugFile("❌ Не удалось открыть файл для записи")
                        sendResult(false, "Ошибка записи")
                    end
                else
                    writeDebugFile("⚠️ Индекс не найден: " .. tostring(index) .. " (OC индекс: " .. tostring(ocIndex) .. "), всего отзывов: " .. #feedbacks)
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end
            
            if cmd.command == "feedback_viewed" then
                local index = d.index
                writeDebugFile("📌 Отметка отзыва как просмотренного: индекс " .. tostring(index))
                
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
                        writeDebugFile("✅ Отзыв отмечен как просмотренный в OC")
                        sendResult(true, "Отзыв отмечен")
                    else
                        writeDebugFile("❌ Не удалось открыть файл для записи")
                        sendResult(false, "Ошибка записи")
                    end
                else
                    writeDebugFile("⚠️ Индекс не найден: " .. tostring(index) .. " (OC индекс: " .. tostring(ocIndex) .. "), всего отзывов: " .. #feedbacks)
                    sendResult(false, "Индекс не найден")
                end
                goto continue
            end
            
            sendResult(false, "Неизвестная команда: " .. tostring(cmd.command))
            
            ::continue::
        end  
     end)

    if not success then
        writeDebugFile("❌ Критическая ошибка в checkWebCommands: " .. tostring(err))
        writeErrorLog("❌ Критическая ошибка в checkWebCommands: " .. tostring(err))
    end
end

event.timer(10, function()
    writeDebugFile("📡 ТАЙМЕР checkWebCommands СРАБОТАЛ!")
    if not TRANSACTION_LOCK then
        writeDebugFile("📡 Вызываем checkWebCommands()")
        checkWebCommands()
    else
        writeDebugFile("⏳ Транзакция активна, пропускаем")
    end
    return true
end, math.huge)

writeDebugFile("✅ Таймер checkWebCommands создан (event.timer)")

-- ============================================================
-- СОГЛАШЕНИЕ
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
        forceRender()
    end
end

-- ============================================================
-- ОСНОВНОЙ ЦИКЛ
-- ============================================================

gpu.setResolution(80, 25)
gpu.setBackground(colors.bg_main)

lastMouseMoveTime = 0
MOUSE_DEBOUNCE = 0.05

function main()
    writeDebugLog("🚀 main() запущен")
    
    gpu.setResolution(80, 25)
    gpu.setBackground(colors.bg_main)
    gpu.fill(1,1,80,25," ")

    currentScreen = "welcome"
    drawWelcomeScreen()
    renderBuffer()   -- первый вывод

    writeErrorLog("🟢 Терминал #1 (PIM MARKET) запущен")

    while true do
        local ev = {event.pull(0.5)}
        local e = ev[1]

        -- ★★★ ПЕРВЫМ ДЕЛОМ ОБРАБАТЫВАЕМ ВХОД/ВЫХОД ИГРОКА ★★★
        if e == "player_on" or e == "pim" or e == "pim_player_enter" then
            local playerName = (ev[2] or ev[6] or ""):match("^%s*(.-)%s*$")
            writeDebugLog("player_on: " .. tostring(playerName))
            
            if not playerName or playerName == "" then
                writeDebugLog("⚠️ Пропущен вход: пустое имя игрока")
                goto continue
            end
            
            if currentPlayer and currentPlayer ~= "" then
                writeDebugLog("⚠️ Игрок уже авторизован: " .. currentPlayer .. ", игнорируем вход: " .. playerName)
                goto continue
            end
            
            if shopPaused then
                writeDebugLog("Режим обслуживания активен, вход запрещён для: " .. playerName)
                drawWelcomeScreen()
                forceRender()
                while shopPaused do
                    local ev2 = {event.pull(1)}
                    if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                        writeDebugLog("👤 Игрок ушёл с PIM: " .. playerName)
                        drawWelcomeScreen()
                        forceRender()
                        break
                    end
                end
                goto continue
            end
                        
            if not pimOwner then
                pimOwner = playerName
            end
            currentPlayer = playerName
            
            -- ★★★ ПРОВЕРКА БАНА ★★★
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
                local reason = "Не указана"
                if banInfo.reason_b64 then
                    reason = decodeBase64(banInfo.reason_b64)
                elseif banInfo.reason then
                    reason = banInfo.reason
                end
                reason = cleanString(reason)
                
                local admin = cleanString(banInfo.admin or "Система")
                
                local function formatDate(isoDate)
                    if not isoDate or isoDate == "" then return "" end
                    local year, month, day = isoDate:match("(%d+)-(%d+)-(%d+)")
                    if year and month and day then
                        return day .. "." .. month .. "." .. year
                    end
                    return isoDate
                end
                
                local formattedDate = banInfo.date and formatDate(banInfo.date) or ""
                local formattedExpire = banInfo.expires and formatDate(banInfo.expires) or ""
                local isPermanent = not banInfo.expires or banInfo.expires == ""
                
                gpu.setBackground(colors.bg_main)
                gpu.fill(1, 1, 80, 25, " ")
                
                gpu.setForeground(colors.error)
                drawCenteredText(6, "╔══════════════════════════════════════════════════════════════╗", colors.error)
                drawCenteredText(7, "║                       ВЫ ЗАБЛОКИРОВАНЫ                       ║", colors.error)
                drawCenteredText(8, "╚══════════════════════════════════════════════════════════════╝", colors.error)
                
                drawCenteredText(10, "Причина: " .. reason, colors.text_main)
                drawCenteredText(11, "Администратор: " .. admin, colors.text_main)
                
                if formattedDate ~= "" then
                    drawCenteredText(12, "Дата: " .. formattedDate, colors.text_main)
                end
                
                if isPermanent then
                    drawCenteredText(13, "Бессрочный бан", colors.text_main)
                else
                    drawCenteredText(13, "Срок истекает: " .. formattedExpire, colors.text_main)
                end
                
                drawCenteredText(15, " Доступ запрещён", colors.error)
                
                gpu.setForeground(colors.accent_secondary)
                drawCenteredText(22, "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━", colors.accent_secondary)
                
                drawTempMessage()
                forceRender()
                
                event.timer(1, function()
                    while true do
                        local ev2 = {event.pull(1)}
                        if ev2[1] == "player_off" or ev2[1] == "pim_player_leave" then
                            writeDebugLog("👤 Игрок ушёл с PIM: " .. playerName)
                            currentPlayer = nil
                            pimOwner = nil
                            alreadyAuthorized = false
                            currentScreen = "welcome"
                            drawWelcomeScreen()
                            forceRender()
                            break
                        end
                    end
                    return false
                end, math.huge)
                
                goto continue
            end
            
            if alreadyAuthorized then
                if currentScreen == "auth" or currentScreen == "account_loading" then
                    currentScreen = "menu"
                    drawMainMenu()
                    forceRender()
                end
                getBindingStatus()
                drawMainMenu()
                forceRender()
            else
                writeDebugLog("Новый вход: " .. playerName)
                coinBalance = 0.0
                emaBalance = 0.0
                playerAgreed = false
                currentScreen = "auth"
                authStartTime = os.clock()
                
                local player = playersIndex[currentPlayer]
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
                    playersIndex[currentPlayer] = player
                    saveDBDeferred()
                    addLog("✅ Новый игрок: " .. currentPlayer)
                    writeDebugLog("Создан новый игрок: " .. currentPlayer)
                    sendToWeb("/api/new_log", toJson({
                        time = getRealTimeHM(),
                        level = "SUCCESS",
                        text = "Новый игрок: " .. currentPlayer
                    }))
                    
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
                    forceRender()
                    event.timer(2, function()
                        currentPlayer = nil
                        currentScreen = "welcome"
                        drawWelcomeScreen()
                        forceRender()
                        return false
                    end)
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
                    forceRender()  -- ★★★ САМОЕ ВАЖНОЕ - ОБНОВЛЯЕМ ЭКРАН ★★★
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
                
                if TRANSACTION_LOCK then
                    writeDebugLog("⚠️ Игрок ушёл ВО ВРЕМЯ транзакции! Ожидаем завершения...")
                    local waitCount = 0
                    while TRANSACTION_LOCK and waitCount < 30 do
                        os.sleep(0.1)
                        waitCount = waitCount + 1
                    end
                    if TRANSACTION_LOCK then
                        writeDebugLog("⚠️ Транзакция зависла, принудительный сброс")
                        TRANSACTION_LOCK = false
                    end
                end
            end
            
            if currentPlayer and playerName == currentPlayer then
                safeExit()
            else
                if playerName == pimOwner then
                    safeExit()
                end
            end
            
            drawWelcomeScreen()
            forceRender()  -- ★★★ ОБНОВЛЯЕМ ЭКРАН ★★★
            
            goto continue
        end

        -- ★★★ ОСТАЛЬНЫЕ СОБЫТИЯ ★★★
        if e == "key_down" then
            local _, _, _, code, char = table.unpack(ev)
            if char == 3 then
                goto continue
            end
        end

        if currentScreen == "auth" then
            if os.clock() - authStartTime >= AUTH_TIMEOUT then
                currentScreen = "menu"
                markDirty()
            end
        end

        if e == "touch" then
            -- ... ВЕСЬ ТВОЙ КОД ОБРАБОТКИ TOUCH (который был раньше) ...
            -- (Вставь сюда свой полный код обработки touch)
        end

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
            
            local x, y = ev[3], ev[4]
            
            pendingMouseX = x
            pendingMouseY = y
            
            if mouseDebounceTimer then
                event.cancel(mouseDebounceTimer)
                mouseDebounceTimer = nil
            end
            
            mouseDebounceTimer = event.timer(0.05, function()
                mouseDebounceTimer = nil
                processMouseMove(pendingMouseX, pendingMouseY)
                return false
            end)
            
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
                    markDirty()
                elseif ch == 8 then
                    reportInput = unicode.sub(reportInput or "", 1, -2)
                    markDirty()
                elseif ch >= 32 then
                    reportInput = (reportInput or "") .. unicode.char(ch)
                    markDirty()
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
                    forceRender()
                elseif ch == 8 then
                    searchInput = unicode.sub(searchInput or "", 1, -2)
                    shopSearch = searchInput or ""
                    drawBuyItemsList()
                    forceRender()
                elseif ch >= 32 then
                    searchInput = (searchInput or "") .. unicode.char(ch)
                    shopSearch = searchInput or ""
                    drawBuyItemsList()
                    forceRender()
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
                    markDirty()
                elseif ch == 8 then
                    feedbackInput = unicode.sub(feedbackInput or "", 1, -2)
                    markDirty()
                elseif ch >= 32 then
                    if unicode.len(feedbackInput or "") < 200 then
                        feedbackInput = (feedbackInput or "") .. unicode.char(ch)
                        markDirty()
                    end
                end
                goto continue
            end
            goto continue
        end

       ::continue::
    end
end

-- ★★★ ЗАПУСК С ЗАЩИТОЙ ★★★
local running = true
while running do
    local ok, err = pcall(main)
    if not ok then
        local msg = "💥 ГЛОБАЛЬНАЯ ОШИБКА: " .. tostring(err)
        print(msg)
        writeErrorLog(msg)
        local stack = debug.traceback()
        writeErrorLog("Стек вызовов:\n" .. stack)
        print(stack)
        
        if err and type(err) == "string" and err:find("shutdown") then
            running = false
            break
        end
        
        os.sleep(5)
    end
end

forceSaveData()
writeErrorLog("🔴 Терминал #1 завершил работу")
