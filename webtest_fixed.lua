-- ============================================================
-- ДИАГНОСТИЧЕСКИЙ СКРИПТ ДЛЯ OC11
-- Сохраняет данные в файл для скачивания
-- ============================================================

local component = require("component")
local computer = require("computer")
local gpu = component.gpu
local event = require("event")
local fs = require("filesystem")
local internet = require("internet")
local serialization = require("serialization")
local unicode = require("unicode")

-- ============================================================
-- НАСТРОЙКИ
-- ============================================================

local logFile = "/home/diagnostic_log.txt"
local jsonFile = "/home/diagnostic_results.json"
local htmlFile = "/home/diagnostic_report.html"
local results = {}

-- ============================================================
-- ФУНКЦИИ ДЛЯ ЗАПИСИ
-- ============================================================

function writeToFile(text)
    local file = io.open(logFile, "a")
    if file then
        file:write(text .. "\n")
        file:close()
    end
    print(text)
end

function addResult(category, key, value)
    if not results[category] then
        results[category] = {}
    end
    results[category][key] = value
end

function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ============================================================
-- 1. ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ
-- ============================================================

function getComputerInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 1. ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ")
    writeToFile(string.rep("=", 60))
    
    local info = {}
    info["Тип"] = "Computer"
    info["Адрес"] = computer.address() or "N/A"
    info["Время работы (сек)"] = computer.uptime()
    info["Время запуска"] = os.date("%d.%m.%Y %H:%M:%S", os.time() - computer.uptime())
    
    if computer.totalMemory then
        local ok, total = pcall(computer.totalMemory)
        if ok and total then
            info["Всего памяти"] = string.format("%.1f MB", total / 1024 / 1024)
        end
    end
    if computer.freeMemory then
        local ok, free = pcall(computer.freeMemory)
        if ok and free then
            info["Свободно памяти"] = string.format("%.1f MB", free / 1024 / 1024)
            if info["Всего памяти"] then
                local total = tonumber(info["Всего памяти"]:match("%d+%.?%d*"))
                local free_mb = free / 1024 / 1024
                info["Использовано памяти"] = string.format("%.1f MB", total - free_mb)
                info["Процент использования"] = string.format("%.1f%%", (total - free_mb) / total * 100)
            end
        end
    end
    
    if computer.getCPUUsage then
        local ok, cpu = pcall(computer.getCPUUsage)
        if ok and cpu then
            info["Загрузка CPU"] = string.format("%.1f%%", cpu * 100)
        end
    end
    
    if computer.getLocalIP then
        local ok, ip = pcall(computer.getLocalIP)
        if ok and ip then
            info["IP интернет карты"] = ip
        end
    end
    
    if computer.energy then
        local ok, energy = pcall(computer.energy)
        if ok and energy then
            info["Энергия"] = string.format("%.1f / %.1f", energy, computer.maxEnergy and computer.maxEnergy() or "?")
        end
    end
    
    for key, value in pairs(info) do
        writeToFile(string.format("  %-20s: %s", key, tostring(value)))
        addResult("computer", key, value)
    end
end

-- ============================================================
-- 2. КОМПОНЕНТЫ
-- ============================================================

function getComponents()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 2. КОМПОНЕНТЫ")
    writeToFile(string.rep("=", 60))
    
    local components = {}
    for address, type in component.list() do
        if not components[type] then
            components[type] = {}
        end
        table.insert(components[type], address)
    end
    
    local componentData = {}
    for type, addresses in pairs(components) do
        writeToFile(string.format("  %s: %d шт.", type, #addresses))
        componentData[type] = #addresses
        for i, addr in ipairs(addresses) do
            writeToFile(string.format("    [%d] %s", i, addr))
        end
    end
    addResult("components", "list", componentData)
    addResult("components", "total", #componentData)
end

-- ============================================================
-- 3. ИНФОРМАЦИЯ О ФАЙЛОВОЙ СИСТЕМЕ
-- ============================================================

function getFilesystemInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 3. ФАЙЛОВАЯ СИСТЕМА")
    writeToFile(string.rep("=", 60))
    
    local paths = {"/", "/home", "/tmp", "/lib", "/etc"}
    for _, path in ipairs(paths) do
        local ok1, free = pcall(fs.space, path)
        local ok2, total = pcall(fs.total, path)
        if ok1 and ok2 and total and total > 0 then
            local used = total - free
            writeToFile(string.format("  %s:", path))
            writeToFile(string.format("    Всего: %.1f KB", total / 1024))
            writeToFile(string.format("    Свободно: %.1f KB", free / 1024))
            writeToFile(string.format("    Использовано: %.1f KB", used / 1024))
            writeToFile(string.format("    Занято: %.1f%%", used / total * 100))
        end
    end
    
    writeToFile("\n  Файлы в /home:")
    local files = {}
    if fs.exists("/home") then
        for file in fs.list("/home") do
            local size = 0
            local ok, s = pcall(fs.size, "/home/" .. file)
            if ok and s then size = s end
            local isDir = fs.isDirectory("/home/" .. file)
            table.insert(files, {name = file, size = size, isDir = isDir})
            writeToFile(string.format("    %-30s %8d байт %s", file, size, isDir and "[DIR]" or ""))
        end
    end
    addResult("filesystem", "files", files)
end

-- ============================================================
-- 4. PIM (Player Interface Module)
-- ============================================================

function getPIMInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 4. PIM (Player Interface Module)")
    writeToFile(string.rep("=", 60))
    
    local pimAddr = nil
    for addr in component.list("pim") do
        pimAddr = addr
        break
    end
    
    if not pimAddr then
        writeToFile("  ❌ PIM не найден!")
        addResult("pim", "found", false)
        return
    end
    
    writeToFile("  ✅ PIM найден: " .. pimAddr)
    addResult("pim", "found", true)
    addResult("pim", "address", pimAddr)
    
    local pim = component.proxy(pimAddr)
    
    local methods = {}
    for name, func in pairs(pim) do
        if type(func) == "function" then
            table.insert(methods, name)
        end
    end
    table.sort(methods)
    
    writeToFile("\n  Доступные методы PIM:")
    for _, name in ipairs(methods) do
        writeToFile(string.format("    - %s()", name))
    end
    addResult("pim", "methods", methods)
    
    writeToFile("\n  Получение данных:")
    local data = {}
    local tests = {
        {"getPlayer", "Игрок"},
        {"getPlayerName", "Имя игрока"},
        {"getUsername", "Имя пользователя"},
        {"getUUID", "UUID"},
        {"getHealth", "Здоровье"},
        {"getFood", "Еда"},
        {"getLevel", "Уровень"},
        {"getExp", "Опыт"},
        {"getX", "X"},
        {"getY", "Y"},
        {"getZ", "Z"},
        {"getWorld", "Мир"},
        {"getDimension", "Измерение"},
        {"getGamemode", "Режим игры"},
        {"getSaturation", "Насыщение"},
        {"getArmor", "Броня"},
        {"getTotalArmor", "Всего брони"},
        {"getHeldItem", "Предмет в руке"},
    }
    
    for _, test in ipairs(tests) do
        local method = test[1]
        local label = test[2]
        if pim[method] then
            local ok, result = pcall(pim[method], pim)
            if ok and result ~= nil then
                local value = tostring(result)
                if #value > 50 then value = value:sub(1, 50) .. "..." end
                writeToFile(string.format("    %-20s: %s", label, value))
                data[label] = result
            else
                writeToFile(string.format("    %-20s: ❌ ошибка", label))
            end
        else
            writeToFile(string.format("    %-20s: ⚠️ метод не найден", label))
        end
    end
    addResult("pim", "data", data)
end

-- ============================================================
-- 5. МОДЕМ
-- ============================================================

function getModemInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 5. МОДЕМ")
    writeToFile(string.rep("=", 60))
    
    local modem = component.modem
    if not modem then
        writeToFile("  ❌ Модем не найден!")
        return
    end
    
    writeToFile("  ✅ Модем найден")
    local ports = {}
    for i = 1, 65535 do
        if modem.isOpen(i) then
            table.insert(ports, i)
        end
    end
    
    if #ports > 0 then
        writeToFile("  Открытые порты: " .. table.concat(ports, ", "))
    else
        writeToFile("  Открытые порты: нет")
    end
    addResult("modem", "ports", ports)
end

-- ============================================================
-- 6. ИНТЕРНЕТ
-- ============================================================

function getInternetInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 6. ИНТЕРНЕТ")
    writeToFile(string.rep("=", 60))
    
    writeToFile("  Проверка подключения к интернету...")
    local testUrls = {
        "https://zozido.pythonanywhere.com",
        "https://google.com",
        "https://yandex.ru",
    }
    
    local internetResults = {}
    for _, url in ipairs(testUrls) do
        local success, response = pcall(function()
            return internet.request(url, nil, {
                ["Connection"] = "close",
                ["Timeout"] = 3
            })
        end)
        
        if success and response then
            local status = "OK"
            if response.getStatus then
                local ok, s = pcall(response.getStatus, response)
                if ok then status = "HTTP " .. tostring(s) end
            end
            writeToFile(string.format("  ✅ %s - %s", url, status))
            internetResults[url] = status
        else
            writeToFile(string.format("  ❌ %s - Нет ответа", url))
            internetResults[url] = "Нет ответа"
        end
    end
    addResult("internet", "results", internetResults)
end

-- ============================================================
-- 7. ГРАФИКА
-- ============================================================

function getGPUInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 7. ГРАФИКА")
    writeToFile(string.rep("=", 60))
    
    if not gpu then
        writeToFile("  ❌ GPU не найден!")
        return
    end
    
    local w, h = gpu.getResolution()
    writeToFile(string.format("  Разрешение: %d x %d", w, h))
    
    if gpu.getViewport then
        local vw, vh = gpu.getViewport()
        writeToFile(string.format("  Viewport: %d x %d", vw, vh))
    end
    
    if gpu.maxResolution then
        local mw, mh = gpu.maxResolution()
        writeToFile(string.format("  Макс. разрешение: %d x %d", mw, mh))
    end
    addResult("gpu", "resolution", {w, h})
end

-- ============================================================
-- 8. ЭНЕРГИЯ
-- ============================================================

function getEnergyInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 8. ЭНЕРГИЯ")
    writeToFile(string.rep("=", 60))
    
    if computer.energy then
        local ok, energy = pcall(computer.energy)
        if ok and energy then
            writeToFile(string.format("  Текущая энергия: %.1f", energy))
            addResult("energy", "current", energy)
        end
    end
    
    if computer.maxEnergy then
        local ok, maxEnergy = pcall(computer.maxEnergy)
        if ok and maxEnergy then
            writeToFile(string.format("  Макс. энергия: %.1f", maxEnergy))
            addResult("energy", "max", maxEnergy)
        end
    end
end

-- ============================================================
-- 9. ВРЕМЯ
-- ============================================================

function getTimeInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 9. ВРЕМЯ")
    writeToFile(string.rep("=", 60))
    
    local now = os.time()
    local boot = now - computer.uptime()
    writeToFile(string.format("  Текущее время: %s", os.date("%d.%m.%Y %H:%M:%S", now)))
    writeToFile(string.format("  Время запуска: %s", os.date("%d.%m.%Y %H:%M:%S", boot)))
    writeToFile(string.format("  Время работы: %.1f секунд", computer.uptime()))
    writeToFile(string.format("  Время работы: %s", formatUptime(computer.uptime())))
    
    addResult("time", "current", os.date("%d.%m.%Y %H:%M:%S", now))
    addResult("time", "boot", os.date("%d.%m.%Y %H:%M:%S", boot))
    addResult("time", "uptime_seconds", computer.uptime())
    addResult("time", "uptime_human", formatUptime(computer.uptime()))
end

function formatUptime(seconds)
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
-- 10. СОЗДАНИЕ HTML ОТЧЁТА
-- ============================================================

function createHTMLReport()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 10. СОЗДАНИЕ HTML ОТЧЁТА")
    writeToFile(string.rep("=", 60))
    
    local html = [[
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Диагностический отчёт OC</title>
    <style>
        body { 
            background: #0a0a12; 
            color: #c0c8d8; 
            font-family: 'Segoe UI', monospace; 
            padding: 30px; 
            max-width: 900px; 
            margin: 0 auto; 
        }
        h1 { 
            color: #4fc3ff; 
            border-bottom: 2px solid #4fc3ff; 
            padding-bottom: 10px; 
            text-align: center;
        }
        .section {
            background: #14141f;
            border: 1px solid #2a2a3f;
            border-radius: 8px;
            padding: 15px 20px;
            margin: 20px 0;
        }
        .section h2 {
            color: #8B5CF6;
            margin-top: 0;
            font-size: 18px;
        }
        .info-row {
            display: flex;
            padding: 4px 0;
            border-bottom: 1px solid #1a1a2a;
        }
        .info-row .key {
            color: #8a9bb0;
            width: 200px;
            flex-shrink: 0;
        }
        .info-row .value {
            color: #e8eef6;
            word-break: break-all;
        }
        .info-row .value.success { color: #66bb6a; }
        .info-row .value.error { color: #ef5350; }
        .info-row .value.warning { color: #ffa726; }
        .badge {
            display: inline-block;
            padding: 2px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge.success { background: #1a3a1a; color: #66bb6a; }
        .badge.error { background: #3a1a1a; color: #ef5350; }
        .badge.warning { background: #3a2a1a; color: #ffa726; }
        .timestamp {
            color: #6b7d93;
            text-align: center;
            font-size: 12px;
            margin-top: 20px;
        }
        pre {
            background: #0a0a12;
            padding: 10px;
            border-radius: 4px;
            overflow-x: auto;
            font-size: 12px;
            margin: 5px 0;
        }
    </style>
</head>
<body>
    <h1>🔍 Диагностический отчёт OC</h1>
    <p style="text-align:center;color:#6b7d93;">Создан: ]] .. os.date("%d.%m.%Y %H:%M:%S") .. [[</p>
]]

    -- Компьютер
    html = html .. [[
    <div class="section">
        <h2>💻 Компьютер</h2>
]]
    for key, value in pairs(results.computer or {}) do
        local color = ""
        if key == "IP интернет карты" and value ~= "N/A" then color = "success" end
        if key == "Загрузка CPU" and value:match("(%d+%.?%d*)%%") then
            local cpu = tonumber(value:match("(%d+%.?%d*)%%"))
            if cpu and cpu > 80 then color = "error"
            elseif cpu and cpu > 50 then color = "warning" end
        end
        html = html .. string.format([[
        <div class="info-row">
            <span class="key">%s</span>
            <span class="value %s">%s</span>
        </div>
]], key, color, tostring(value))
    end
    html = html .. [[
    </div>
]]

    -- Компоненты
    html = html .. [[
    <div class="section">
        <h2>🔧 Компоненты</h2>
        <div class="info-row">
            <span class="key">Всего типов</span>
            <span class="value">]] .. (results.components and results.components.total or 0) .. [[</span>
        </div>
]]
    if results.components and results.components.list then
        for type, count in pairs(results.components.list) do
            html = html .. string.format([[
        <div class="info-row">
            <span class="key">  %s</span>
            <span class="value">%d шт.</span>
        </div>
]], type, count)
        end
    end
    html = html .. [[
    </div>
]]

    -- PIM
    html = html .. [[
    <div class="section">
        <h2>👤 PIM</h2>
]]
    if results.pim and results.pim.found then
        html = html .. [[
        <div class="info-row">
            <span class="key">Статус</span>
            <span class="value success">✅ Найден</span>
        </div>
        <div class="info-row">
            <span class="key">Адрес</span>
            <span class="value">]] .. (results.pim.address or "N/A") .. [[</span>
        </div>
]]
        if results.pim.data then
            for key, value in pairs(results.pim.data) do
                html = html .. string.format([[
        <div class="info-row">
            <span class="key">  %s</span>
            <span class="value">%s</span>
        </div>
]], key, tostring(value))
            end
        end
    else
        html = html .. [[
        <div class="info-row">
            <span class="key">Статус</span>
            <span class="value error">❌ Не найден</span>
        </div>
]]
    end
    html = html .. [[
    </div>
]]

    -- Время
    html = html .. [[
    <div class="section">
        <h2>⏰ Время</h2>
]]
    if results.time then
        html = html .. string.format([[
        <div class="info-row">
            <span class="key">Текущее время</span>
            <span class="value">%s</span>
        </div>
        <div class="info-row">
            <span class="key">Время запуска</span>
            <span class="value">%s</span>
        </div>
        <div class="info-row">
            <span class="key">Время работы</span>
            <span class="value">%s</span>
        </div>
]], results.time.current or "N/A", results.time.boot or "N/A", results.time.uptime_human or "N/A")
    end
    html = html .. [[
    </div>
]]

    -- Закрываем HTML
    html = html .. [[
    <div class="timestamp">
        Отчёт создан автоматически диагностическим скриптом OC
    </div>
</body>
</html>
]]

    -- Сохраняем HTML
    local file = io.open(htmlFile, "w")
    if file then
        file:write(html)
        file:close()
        writeToFile("  ✅ HTML отчёт создан: " .. htmlFile)
    else
        writeToFile("  ❌ Не удалось создать HTML отчёт")
    end
end

-- ============================================================
-- 11. СОХРАНЕНИЕ РЕЗУЛЬТАТОВ
-- ============================================================

function saveResults()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 11. СОХРАНЕНИЕ РЕЗУЛЬТАТОВ")
    writeToFile(string.rep("=", 60))
    
    -- Сохраняем JSON
    local file = io.open(jsonFile, "w")
    if file then
        file:write(serialization.serialize(results))
        file:close()
        writeToFile("  ✅ JSON сохранён: " .. jsonFile)
    else
        writeToFile("  ❌ Не удалось сохранить JSON")
    end
    
    -- Создаём HTML отчёт
    createHTMLReport()
    
    -- Показываем сводку
    writeToFile("\n  📊 СВОДКА:")
    for category, data in pairs(results) do
        writeToFile(string.format("    %s: %d записей", category, tableCount(data)))
    end
end

-- ============================================================
-- ГЛАВНАЯ ФУНКЦИЯ
-- ============================================================

function main()
    -- Очищаем файл лога
    local file = io.open(logFile, "w")
    if file then
        file:write(string.rep("=", 60) .. "\n")
        file:write(" ДИАГНОСТИЧЕСКИЙ ОТЧЕТ OC\n")
        file:write(string.rep("=", 60) .. "\n")
        file:write(" Время: " .. os.date("%d.%m.%Y %H:%M:%S") .. "\n")
        file:write(string.rep("=", 60) .. "\n")
        file:close()
    end
    
    print("\n" .. string.rep("=", 60))
    print(" ДИАГНОСТИЧЕСКИЙ СКРИПТ")
    print("=" .. string.rep("=", 60))
    print("")
    
    -- Запускаем все проверки
    getComputerInfo()
    getComponents()
    getFilesystemInfo()
    getPIMInfo()
    getModemInfo()
    getInternetInfo()
    getGPUInfo()
    getEnergyInfo()
    getTimeInfo()
    saveResults()
    
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" ДИАГНОСТИКА ЗАВЕРШЕНА")
    writeToFile(string.rep("=", 60))
    
    print("\n" .. string.rep("=", 60))
    print(" ✅ ДИАГНОСТИКА ЗАВЕРШЕНА")
    print("=" .. string.rep("=", 60))
    print(" 📁 Лог: " .. logFile)
    print(" 📁 JSON: " .. jsonFile)
    print(" 📁 HTML: " .. htmlFile)
    print("")
    print(" 💡 Для скачивания файлов:")
    print("    Скачайте через FTP или используйте:")
    print("    cat " .. htmlFile .. " > /tmp/report.html")
    print("=" .. string.rep("=", 60))
end

-- Запускаем
main()
