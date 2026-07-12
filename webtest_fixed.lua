-- ============================================================
-- ТЕСТОВЫЙ СКРИПТ: Проверка системных данных OpenComputers
-- ============================================================

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local event = require("event")
local gpu = component.gpu

-- Цвета для красивого вывода
local colors = {
    reset = 0xFFFFFF,
    green = 0x00FF00,
    red = 0xFF4444,
    yellow = 0xFFFF00,
    cyan = 0x00FFFF,
    white = 0xFFFFFF,
    gray = 0x888888
}

-- Очистка экрана
gpu.setBackground(0x000000)
gpu.fill(1, 1, 80, 25, " ")
gpu.setForeground(colors.white)

-- Функция для безопасного вызова
function safeCall(fn, default)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return default
end

-- Функция для форматирования времени
function formatUptime(seconds)
    if not seconds then return "N/A" end
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
-- ГЛАВНАЯ ФУНКЦИЯ ТЕСТА
-- ============================================================

function testSystemInfo()
    print("=" .. string.rep("=", 58) .. "=")
    print("  🔍 ТЕСТ СИСТЕМНЫХ ДАННЫХ OPENCOMPUTERS")
    print("=" .. string.rep("=", 58) .. "=")
    print("")
    
    -- 1. ВРЕМЯ РАБОТЫ
    print("📊 1. ВРЕМЯ РАБОТЫ:")
    local uptime = safeCall(computer.uptime, 0)
    if uptime and uptime > 0 then
        gpu.setForeground(colors.green)
        print("   ✅ Время работы: " .. formatUptime(uptime))
    else
        gpu.setForeground(colors.red)
        print("   ❌ Не удалось получить время работы")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 2. CPU
    print("📊 2. ЗАГРУЗКА CPU:")
    if computer.getCPUUsage then
        local cpu = safeCall(computer.getCPUUsage, 0)
        if cpu and cpu > 0 then
            gpu.setForeground(colors.green)
            print("   ✅ CPU загрузка: " .. string.format("%.1f%%", cpu * 100))
        else
            gpu.setForeground(colors.yellow)
            print("   ⚠️ CPU загрузка: 0% (возможно API недоступен)")
        end
    else
        gpu.setForeground(colors.red)
        print("   ❌ computer.getCPUUsage() НЕ ДОСТУПЕН!")
        gpu.setForeground(colors.gray)
        print("      (возможно, старая версия OC)")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 3. ПАМЯТЬ
    print("📊 3. ПАМЯТЬ:")
    local totalMem = safeCall(computer.totalMemory, 0)
    local freeMem = safeCall(computer.freeMemory, 0)
    
    if totalMem and totalMem > 0 then
        gpu.setForeground(colors.green)
        print("   ✅ Всего памяти: " .. string.format("%.1f MB", totalMem / 1024 / 1024))
        if freeMem and freeMem > 0 then
            local usedMem = totalMem - freeMem
            local percent = (usedMem / totalMem) * 100
            print("   ✅ Использовано: " .. string.format("%.1f MB (%.1f%%)", usedMem / 1024 / 1024, percent))
            print("   ✅ Свободно: " .. string.format("%.1f MB", freeMem / 1024 / 1024))
        else
            gpu.setForeground(colors.yellow)
            print("   ⚠️ Не удалось получить свободную память")
        end
    else
        gpu.setForeground(colors.red)
        print("   ❌ Не удалось получить информацию о памяти")
        gpu.setForeground(colors.gray)
        print("      (computer.totalMemory() недоступен)")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 4. ДИСК
    print("📊 4. ДИСКОВОЕ ПРОСТРАНСТВО:")
    local diskFree = safeCall(fs.space, "/", 0)
    local diskTotal = safeCall(fs.total, "/", 0)
    
    if diskTotal and diskTotal > 0 then
        gpu.setForeground(colors.green)
        print("   ✅ Всего места: " .. string.format("%.1f MB", diskTotal / 1024 / 1024))
        if diskFree and diskFree > 0 then
            local used = diskTotal - diskFree
            local percent = (used / diskTotal) * 100
            print("   ✅ Использовано: " .. string.format("%.1f MB (%.1f%%)", used / 1024 / 1024, percent))
            print("   ✅ Свободно: " .. string.format("%.1f MB", diskFree / 1024 / 1024))
        else
            gpu.setForeground(colors.yellow)
            print("   ⚠️ Не удалось получить свободное место")
        end
    else
        gpu.setForeground(colors.red)
        print("   ❌ Не удалось получить информацию о диске")
        gpu.setForeground(colors.gray)
        print("      (fs.space() или fs.total() недоступны)")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 5. IP АДРЕС
    print("📊 5. IP АДРЕС:")
    if computer.getLocalIP then
        local ip = safeCall(computer.getLocalIP, "127.0.0.1")
        if ip and ip ~= "127.0.0.1" then
            gpu.setForeground(colors.green)
            print("   ✅ IP адрес: " .. ip)
        else
            gpu.setForeground(colors.yellow)
            print("   ⚠️ IP адрес: " .. ip .. " (возможно, локальный)")
        end
    else
        gpu.setForeground(colors.red)
        print("   ❌ computer.getLocalIP() НЕ ДОСТУПЕН!")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 6. ВРЕМЯ ЗАПУСКА
    print("📊 6. ВРЕМЯ ЗАПУСКА:")
    if uptime and uptime > 0 then
        local bootTime = os.time() - uptime
        local bootStr = os.date("%d.%m.%Y %H:%M:%S", bootTime)
        gpu.setForeground(colors.green)
        print("   ✅ Время запуска: " .. bootStr)
    else
        gpu.setForeground(colors.red)
        print("   ❌ Не удалось определить время запуска")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- 7. PIM (для определения игрока)
    print("📊 7. PIM (ИГРОК):")
    local pimAddr = nil
    for addr in component.list("pim") do
        pimAddr = addr
        break
    end
    
    if pimAddr then
        local pim = component.proxy(pimAddr)
        local player = safeCall(pim.getPlayer, "Неизвестно")
        if player and player ~= "Неизвестно" then
            gpu.setForeground(colors.green)
            print("   ✅ PIM найден, игрок: " .. player)
        else
            gpu.setForeground(colors.yellow)
            print("   ⚠️ PIM найден, но игрок не определён")
        end
    else
        gpu.setForeground(colors.red)
        print("   ❌ PIM не найден!")
        gpu.setForeground(colors.gray)
        print("      (компонент PIM отсутствует)")
    end
    gpu.setForeground(colors.white)
    print("")
    
    -- ИТОГ
    print("=" .. string.rep("=", 58) .. "=")
    print("  📋 ИТОГОВЫЙ ВЕРДИКТ:")
    
    local successCount = 0
    if uptime and uptime > 0 then successCount = successCount + 1 end
    if totalMem and totalMem > 0 then successCount = successCount + 1 end
    if diskTotal and diskTotal > 0 then successCount = successCount + 1 end
    if pimAddr then successCount = successCount + 1 end
    
    if successCount >= 3 then
        gpu.setForeground(colors.green)
        print("  ✅ Система работает нормально (" .. successCount .. "/4)")
        print("  ✅ Данные будут передаваться на сайт")
    elseif successCount >= 2 then
        gpu.setForeground(colors.yellow)
        print("  ⚠️ Частичная работоспособность (" .. successCount .. "/4)")
        print("  ⚠️ Некоторые данные могут отсутствовать")
    else
        gpu.setForeground(colors.red)
        print("  ❌ КРИТИЧЕСКИЕ ПРОБЛЕМЫ (" .. successCount .. "/4)")
        print("  ❌ Данные НЕ будут передаваться на сайт")
        print("  ❌ Проверьте версию OpenComputers")
    end
    
    gpu.setForeground(colors.white)
    print("=" .. string.rep("=", 58) .. "=")
    print("")
    print("🔄 Нажмите любую клавишу для выхода...")
    event.pull("key_down")
end

-- ============================================================
-- ЗАПУСК ТЕСТА
-- ============================================================

-- Запускаем тест
testSystemInfo()

-- Очищаем экран перед выходом
gpu.setBackground(0x000000)
gpu.fill(1, 1, 80, 25, " ")
print("✅ Тест завершён")
