-- ============================================================
-- ДИАГНОСТИЧЕСКИЙ СКРИПТ ДЛЯ OC
-- Проверка всех доступных данных
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

-- ============================================================
-- 1. ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ
-- ============================================================

function getComputerInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 1. ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ")
    writeToFile(string.rep("=", 60))
    
    -- Основная информация
    local info = {}
    info["Тип"] = "Computer"
    info["Адрес"] = computer.address() or "N/A"
    info["Время работы (сек)"] = computer.uptime()
    info["Время работы"] = os.date("%d.%m.%Y %H:%M:%S", os.time() - computer.uptime())
    
    -- Память
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
    
    -- CPU
    if computer.getCPUUsage then
        local ok, cpu = pcall(computer.getCPUUsage)
        if ok and cpu then
            info["Загрузка CPU"] = string.format("%.1f%%", cpu * 100)
        end
    end
    
    -- IP
    if computer.getLocalIP then
        local ok, ip = pcall(computer.getLocalIP)
        if ok and ip then
            info["IP адрес"] = ip
        end
    end
    
    -- Энергия (если есть)
    if computer.energy then
        local ok, energy = pcall(computer.energy)
        if ok and energy then
            info["Энергия"] = string.format("%.1f / %.1f", energy, computer.maxEnergy and computer.maxEnergy() or "?")
        end
    end
    
    -- Запись результатов
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
    
    -- Список файлов в /home
    writeToFile("\n  Файлы в /home:")
    if fs.exists("/home") then
        for file in fs.list("/home") do
            local size = 0
            local ok, s = pcall(fs.size, "/home/" .. file)
            if ok and s then size = s end
            writeToFile(string.format("    %-30s %8d байт", file, size))
        end
    end
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
    
    -- Проверяем доступные методы
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
    
    -- Пробуем получить данные
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
    
    -- Открытые порты
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
end

-- ============================================================
-- 6. ИНТЕРНЕТ
-- ============================================================

function getInternetInfo()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 6. ИНТЕРНЕТ")
    writeToFile(string.rep("=", 60))
    
    -- Проверяем интернет
    writeToFile("  Проверка подключения к интернету...")
    local testUrls = {
        "https://zozido.pythonanywhere.com",
        "https://google.com",
        "https://yandex.ru",
    }
    
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
        else
            writeToFile(string.format("  ❌ %s - Нет ответа", url))
        end
    end
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
        end
    end
    
    if computer.maxEnergy then
        local ok, maxEnergy = pcall(computer.maxEnergy)
        if ok and maxEnergy then
            writeToFile(string.format("  Макс. энергия: %.1f", maxEnergy))
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
    
    writeToFile(string.format("  Текущее время: %s", os.date("%d.%m.%Y %H:%M:%S")))
    writeToFile(string.format("  Время запуска: %s", os.date("%d.%m.%Y %H:%M:%S", os.time() - computer.uptime())))
    writeToFile(string.format("  Время работы: %.1f секунд", computer.uptime()))
    writeToFile(string.format("  Время работы: %s", formatUptime(computer.uptime())))
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
-- 10. СОХРАНЕНИЕ РЕЗУЛЬТАТОВ
-- ============================================================

function saveResults()
    writeToFile("\n" .. string.rep("=", 60))
    writeToFile(" 10. СОХРАНЕНИЕ РЕЗУЛЬТАТОВ")
    writeToFile(string.rep("=", 60))
    
    -- Сохраняем JSON
    local jsonFile = "/home/diagnostic_results.json"
    local file = io.open(jsonFile, "w")
    if file then
        file:write(serialization.serialize(results))
        file:close()
        writeToFile("  ✅ Результаты сохранены в: " .. jsonFile)
    else
        writeToFile("  ❌ Не удалось сохранить результаты")
    end
    
    -- Показываем сводку
    writeToFile("\n  📊 СВОДКА:")
    for category, data in pairs(results) do
        writeToFile(string.format("    %s: %d записей", category, tableCount(data)))
    end
end

function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- ============================================================
-- ГЛАВНАЯ ФУНКЦИЯ
-- ============================================================

function main()
    -- Очищаем файл лога
    local file = io.open(logFile, "w")
    if file then
        file:write("=" .. string.rep("=", 59) .. "\n")
        file:write(" ДИАГНОСТИЧЕСКИЙ ОТЧЕТ OC\n")
        file:write("=" .. string.rep("=", 59) .. "\n")
        file:write(" Время: " .. os.date("%d.%m.%Y %H:%M:%S") .. "\n")
        file:close()
    end
    
    print("\n" .. string.rep("=", 60))
    print(" ДИАГНОСТИЧЕСКИЙ СКРИПТ")
    print("=" .. string.rep("=", 60))
    print(" Лог сохраняется в: " .. logFile)
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
    print(" 📁 JSON: /home/diagnostic_results.json")
    print("=" .. string.rep("=", 60))
end

-- Запускаем
main()
