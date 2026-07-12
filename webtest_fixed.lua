-- ============================================================
-- РАСШИРЕННЫЙ ТЕСТ СИСТЕМНЫХ ДАННЫХ OpenComputers
-- ============================================================

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local event = require("event")
local gpu = component.gpu
local unicode = require("unicode")

-- Цвета
local C = {
    reset = 0xFFFFFF,
    green = 0x00FF00,
    red = 0xFF4444,
    yellow = 0xFFFF00,
    cyan = 0x00FFFF,
    white = 0xFFFFFF,
    gray = 0x888888,
    pink = 0xFF66AA
}

-- Очистка экрана
gpu.setBackground(0x000000)
gpu.fill(1, 1, 80, 25, " ")
gpu.setForeground(C.white)

-- Безопасный вызов
function safe(fn, default)
    local ok, result = pcall(fn)
    if ok then return result end
    return default
end

-- Форматирование времени
function formatUptime(seconds)
    if not seconds or type(seconds) ~= "number" then return "N/A" end
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

-- Форматирование байт
function formatBytes(bytes)
    if not bytes or type(bytes) ~= "number" then return "N/A" end
    if bytes < 1024 then
        return string.format("%d B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", bytes / 1024 / 1024)
    else
        return string.format("%.1f GB", bytes / 1024 / 1024 / 1024)
    end
end

-- ============================================================
-- ОСНОВНОЙ ТЕСТ
-- ============================================================

function printHeader(text)
    print("")
    gpu.setForeground(C.cyan)
    print("┌" .. string.rep("─", 58) .. "┐")
    print("│ " .. string.rep(" ", 15) .. text .. string.rep(" ", 58 - 16 - unicode.len(text)) .. "│")
    print("└" .. string.rep("─", 58) .. "┘")
    gpu.setForeground(C.white)
end

function printSuccess(text)
    gpu.setForeground(C.green)
    print("   ✅ " .. text)
    gpu.setForeground(C.white)
end

function printWarning(text)
    gpu.setForeground(C.yellow)
    print("   ⚠️ " .. text)
    gpu.setForeground(C.white)
end

function printError(text)
    gpu.setForeground(C.red)
    print("   ❌ " .. text)
    gpu.setForeground(C.white)
end

function printInfo(text)
    gpu.setForeground(C.gray)
    print("      " .. text)
    gpu.setForeground(C.white)
end

function printValue(label, value, color)
    if color then gpu.setForeground(color) end
    print("   " .. label .. ": " .. tostring(value))
    gpu.setForeground(C.white)
end

-- ============================================================
-- ГЛАВНАЯ ФУНКЦИЯ
-- ============================================================

function testSystem()
    print("")
    gpu.setForeground(C.pink)
    print("  ╔══════════════════════════════════════════════════════════╗")
    print("  ║     🔍 РАСШИРЕННЫЙ ТЕСТ СИСТЕМНЫХ ДАННЫХ OC            ║")
    print("  ╚══════════════════════════════════════════════════════════╝")
    gpu.setForeground(C.white)
    
    -- ============================================================
    -- 1. БАЗОВАЯ ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ
    -- ============================================================
    printHeader("1. БАЗОВАЯ ИНФОРМАЦИЯ")
    
    -- Версия OC
    local ocVersion = safe(function() return _G._VERSION or "N/A" end, "N/A")
    printValue("Версия Lua", ocVersion)
    
    -- Адрес компьютера
    local address = safe(computer.address, "N/A")
    printValue("Адрес", address)
    
    -- Время работы
    local uptime = safe(computer.uptime, 0)
    if uptime and uptime > 0 then
        printSuccess("Время работы: " .. formatUptime(uptime))
        local bootTime = os.time() - uptime
        printValue("Запущен", os.date("%d.%m.%Y %H:%M:%S", bootTime))
    else
        printError("Не удалось получить время работы")
    end
    
    -- ============================================================
    -- 2. CPU (ПРОЦЕССОР)
    -- ============================================================
    printHeader("2. ПРОЦЕССОР (CPU)")
    
    -- Вариант 1: getCPUUsage
    if computer.getCPUUsage then
        local cpu = safe(computer.getCPUUsage, 0)
        if cpu and type(cpu) == "number" then
            printSuccess("CPU загрузка: " .. string.format("%.1f%%", cpu * 100))
        else
            printWarning("CPU загрузка: 0% (возможно недоступно)")
        end
    else
        printError("computer.getCPUUsage() НЕ ДОСТУПЕН")
        printInfo("Попробуйте обновить OpenComputers")
    end
    
    -- Альтернатива: энергия
    if computer.energy then
        local energy = safe(computer.energy, 0)
        local maxEnergy = safe(computer.maxEnergy, 1)
        if energy and maxEnergy and maxEnergy > 0 then
            local percent = (energy / maxEnergy) * 100
            printValue("Энергия", string.format("%.1f / %.1f (%.1f%%)", energy, maxEnergy, percent))
        end
    end
    
    -- ============================================================
    -- 3. ПАМЯТЬ (RAM)
    -- ============================================================
    printHeader("3. ОПЕРАТИВНАЯ ПАМЯТЬ (RAM)")
    
    local totalMem = safe(computer.totalMemory, 0)
    local freeMem = safe(computer.freeMemory, 0)
    
    if totalMem and totalMem > 0 then
        printSuccess("Всего: " .. formatBytes(totalMem))
        if freeMem and freeMem > 0 then
            local usedMem = totalMem - freeMem
            local percent = (usedMem / totalMem) * 100
            printSuccess("Использовано: " .. formatBytes(usedMem) .. " (" .. string.format("%.1f%%)", percent))
            printSuccess("Свободно: " .. formatBytes(freeMem))
        else
            printWarning("Свободная память недоступна")
        end
    else
        printError("Информация о памяти недоступна")
        printInfo("Проверьте наличие компонента памяти")
    end
    
    -- ============================================================
    -- 4. ДИСК (HDD/SSD)
    -- ============================================================
    printHeader("4. ДИСКОВОЕ ПРОСТРАНСТВО")
    
    -- Пробуем разные пути
    local diskPaths = {"/", "/home", "/tmp", "/lib"}
    local foundDisk = false
    
    for _, path in ipairs(diskPaths) do
        local ok1, free = pcall(fs.space, path)
        local ok2, total = pcall(fs.total, path)
        
        if ok1 and ok2 and total and type(total) == "number" and total > 0 then
            foundDisk = true
            printSuccess("Путь: " .. path)
            printValue("Всего", formatBytes(total))
            
            if free and type(free) == "number" then
                local used = total - free
                local percent = (used / total) * 100
                printValue("Использовано", formatBytes(used) .. " (" .. string.format("%.1f%%)", percent))
                printValue("Свободно", formatBytes(free))
            else
                printWarning("Свободное место недоступно для " .. path)
            end
            break
        end
    end
    
    if not foundDisk then
        printError("Не удалось получить информацию о диске")
        printInfo("Проверьте, смонтирована ли файловая система")
        printInfo("Попробуйте: mount /")
    end
    
    -- ============================================================
    -- 5. СЕТЬ (NETWORK)
    -- ============================================================
    printHeader("5. СЕТЬ (NETWORK)")
    
    -- IP адрес
    if computer.getLocalIP then
        local ip = safe(computer.getLocalIP, "127.0.0.1")
        if ip and ip ~= "127.0.0.1" then
            printSuccess("IP адрес: " .. ip)
        else
            printWarning("IP адрес: " .. ip .. " (локальный)")
        end
    else
        printError("computer.getLocalIP() НЕ ДОСТУПЕН")
    end
    
    -- Проверка интернета
    printInfo("Проверка подключения к интернету...")
    local hasInternet = false
    local ok, response = pcall(function()
        return require("internet").request("https://zozido.pythonanywhere.com/api/stats")
    end)
    if ok and response then
        hasInternet = true
        printSuccess("Интернет: ДОСТУПЕН")
    else
        printWarning("Интернет: НЕ ДОСТУПЕН")
        printInfo("Проверьте подключение к сети")
    end
    
    -- ============================================================
    -- 6. КОМПОНЕНТЫ (HARDWARE)
    -- ============================================================
    printHeader("6. ДОСТУПНЫЕ КОМПОНЕНТЫ")
    
    local components = {}
    for addr in component.list() do
        local type = component.type(addr)
        if type then
            components[type] = (components[type] or 0) + 1
        end
    end
    
    local componentList = {
        "pim", "me_interface", "gpu", "modem", 
        "screen", "keyboard", "filesystem", "memory"
    }
    
    for _, comp in ipairs(componentList) do
        if components[comp] then
            printSuccess(comp:upper() .. ": " .. components[comp] .. " шт.")
        else
            printWarning(comp:upper() .. ": ОТСУТСТВУЕТ")
        end
    end
    
    -- ============================================================
    -- 7. ДОПОЛНИТЕЛЬНАЯ ИНФОРМАЦИЯ
    -- ============================================================
    printHeader("7. ДОПОЛНИТЕЛЬНО")
    
    -- Версия OC (если есть)
    if _G.OC_VERSION then
        printValue("Версия OC", _G.OC_VERSION)
    end
    
    -- Информация о системе
    if computer.getSystemInfo then
        local info = safe(computer.getSystemInfo, {})
        if info and type(info) == "table" then
            for k, v in pairs(info) do
                if type(v) ~= "table" then
                    printValue(tostring(k), tostring(v))
                end
            end
        end
    end
    
    -- Количество игроков в базе
    printInfo("Проверка базы игроков...")
    local dbOk, players = pcall(function()
        local f = io.open("/home/players.db", "r")
        if f then
            local data = f:read("*a")
            f:close()
            return data
        end
        return nil
    end)
    if players then
        printValue("players.db", "существует (" .. string.len(players) .. " байт)")
    else
        printWarning("players.db: не найден")
    end
    
    -- ============================================================
    -- 8. ИТОГ
    -- ============================================================
    printHeader("8. ИТОГОВЫЙ ВЕРДИКТ")
    
    local score = 0
    local maxScore = 6
    
    if uptime and uptime > 0 then score = score + 1 end
    if totalMem and totalMem > 0 then score = score + 1 end
    if foundDisk then score = score + 1 end
    if hasInternet then score = score + 1 end
    if component.list("pim")() then score = score + 1 end
    if component.list("me_interface")() then score = score + 1 end
    
    local percent = (score / maxScore) * 100
    
    if score >= 5 then
        gpu.setForeground(C.green)
        print("  ✅ ОТЛИЧНО! (" .. score .. "/" .. maxScore .. " - " .. string.format("%.0f%%", percent) .. ")")
        print("  ✅ Все системы работают корректно")
        print("  ✅ Данные будут передаваться на сайт")
    elseif score >= 3 then
        gpu.setForeground(C.yellow)
        print("  ⚠️ ХОРОШО (" .. score .. "/" .. maxScore .. " - " .. string.format("%.0f%%", percent) .. ")")
        print("  ⚠️ Некоторые данные могут отсутствовать")
        print("  ⚠️ Рекомендуется обновить OpenComputers")
    else
        gpu.setForeground(C.red)
        print("  ❌ ПЛОХО (" .. score .. "/" .. maxScore .. " - " .. string.format("%.0f%%", percent) .. ")")
        print("  ❌ Критические проблемы с системой")
        print("  ❌ Данные НЕ будут передаваться")
        print("  ❌ Проверьте установку OpenComputers")
    end
    
    gpu.setForeground(C.white)
    print("")
    print("  ╔" .. string.rep("═", 58) .. "╗")
    print("  ║  Рекомендации:                                    ║")
    if computer.getCPUUsage == nil then
        print("  ║  • Обновите OpenComputers до последней версии   ║")
    end
    if not foundDisk then
        print("  ║  • Проверьте монтирование диска: mount /        ║")
    end
    if not hasInternet then
        print("  ║  • Проверьте интернет-соединение               ║")
    end
    if not component.list("pim")() then
        print("  ║  • Установите PIM на компьютер                  ║")
    end
    print("  ╚" .. string.rep("═", 58) .. "╝")
    
    print("")
    print("🔄 Нажмите любую клавишу для выхода...")
    event.pull("key_down")
end

-- ============================================================
-- ЗАПУСК
-- ============================================================

-- Устанавливаем разрешение для красивого вывода
local w, h = gpu.getResolution()
if w < 80 then
    gpu.setResolution(80, 25)
end

testSystem()

-- Очистка перед выходом
gpu.setBackground(0x000000)
gpu.fill(1, 1, 80, 25, " ")
gpu.setForeground(C.green)
print("✅ Тест завершён")
gpu.setForeground(C.white)
