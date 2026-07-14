-- test_system.lua
-- Полная диагностика системы

local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local os = require("os")
local gpu = component.gpu

print("=" .. string.rep("=", 70))
print("                    ПОЛНАЯ ДИАГНОСТИКА СИСТЕМЫ")
print("=" .. string.rep("=", 70))

-- ============================================================
-- 1. ИНФОРМАЦИЯ О КОМПЬЮТЕРЕ
-- ============================================================
print("\n[1] КОМПЬЮТЕР")
print("  Время работы: " .. math.floor(computer.uptime() / 60) .. " мин " .. math.floor(computer.uptime() % 60) .. " сек")
print("  Энергия: " .. string.format("%.1f", computer.energy() or 0) .. " / " .. string.format("%.1f", computer.maxEnergy() or 0))
print("  Адрес: " .. (computer.address and computer.address() or "N/A"))
print("  Архитектура: " .. (computer.arch and computer.arch() or "N/A"))
print("  Версия: " .. (computer.version and computer.version() or "N/A"))

-- ============================================================
-- 2. ОПЕРАТИВНАЯ ПАМЯТЬ
-- ============================================================
print("\n[2] ОПЕРАТИВНАЯ ПАМЯТЬ")
if computer.totalMemory and computer.freeMemory then
    local total = computer.totalMemory()
    local free = computer.freeMemory()
    local used = total - free
    print("  Всего: " .. string.format("%.1f", total / 1024 / 1024) .. " MB")
    print("  Использовано: " .. string.format("%.1f", used / 1024 / 1024) .. " MB")
    print("  Свободно: " .. string.format("%.1f", free / 1024 / 1024) .. " MB")
    print("  Занято: " .. string.format("%.1f%%", (used / total) * 100))
end

-- ============================================================
-- 3. ПРОЦЕССОР
-- ============================================================
print("\n[3] ПРОЦЕССОР")
if computer.getCPUUsage then
    local ok, cpu = pcall(computer.getCPUUsage)
    if ok and cpu then
        print("  Загрузка CPU: " .. string.format("%.1f%%", cpu * 100))
    else
        print("  Загрузка CPU: N/A")
    end
end

-- ============================================================
-- 4. ДИСКОВОЕ ПРОСТРАНСТВО
-- ============================================================
print("\n[4] ДИСКОВОЕ ПРОСТРАНСТВО")
local drives = {"/", "/home", "/tmp", "/lib", "/boot"}
for _, path in ipairs(drives) do
    if fs.exists(path) then
        local ok1, free = pcall(fs.space, path)
        local ok2, total = pcall(fs.total, path)
        if ok1 and ok2 and total and total > 0 then
            local used = total - free
            local percent = (used / total) * 100
            print("  " .. path .. ":")
            print("    Всего: " .. string.format("%.1f", total / 1024 / 1024) .. " MB")
            print("    Свободно: " .. string.format("%.1f", free / 1024 / 1024) .. " MB")
            print("    Занято: " .. string.format("%.1f", used / 1024 / 1024) .. " MB")
            print("    Заполнено: " .. string.format("%.1f%%", percent))
        else
            print("  " .. path .. ": доступен")
        end
    end
end

-- ============================================================
-- 5. ВИДЕОКАРТА (GPU)
-- ============================================================
print("\n[5] ВИДЕОКАРТА (GPU)")
if gpu then
    print("  Тип: " .. (gpu.getType and gpu.getType() or "N/A"))
    local w, h = gpu.getResolution()
    print("  Разрешение: " .. w .. "x" .. h)
    local maxW, maxH = gpu.maxResolution()
    print("  Макс. разрешение: " .. maxW .. "x" .. maxH)
    if gpu.getScreen then
        print("  Экран: " .. gpu.getScreen())
    end
    if gpu.getViewport then
        local vw, vh = gpu.getViewport()
        print("  Viewport: " .. vw .. "x" .. vh)
    end
    if gpu.getBackground then
        print("  Цвет фона: " .. gpu.getBackground())
    end
    if gpu.getForeground then
        print("  Цвет текста: " .. gpu.getForeground())
    end
else
    print("  ❌ GPU не найден")
end

-- ============================================================
-- 6. СЕТЕВЫЕ УСТРОЙСТВА
-- ============================================================
print("\n[6] СЕТЕВЫЕ УСТРОЙСТВА")

-- Интернет
local internet = component.internet
if internet then
    print("  📡 Интернет:")
    print("    Компонент: internet")
    if internet.address then
        print("    Адрес: " .. internet.address)
    end
    if internet.getAddress then
        local ok, addr = pcall(internet.getAddress, internet)
        if ok then print("    getAddress(): " .. tostring(addr)) end
    end
    if internet.isAvailable then
        local ok, avail = pcall(internet.isAvailable, internet)
        if ok then print("    Доступен: " .. tostring(avail)) end
    end
else
    print("  ❌ Интернет компонент не найден")
end

-- Модем
local modem = component.modem
if modem then
    print("  📶 Модем:")
    print("    Компонент: modem")
    if modem.address then
        print("    Адрес: " .. modem.address)
    end
    if modem.isOpen then
        local ports = {}
        for port = 1, 65535 do
            if modem.isOpen(port) then
                table.insert(ports, port)
            end
        end
        if #ports > 0 then
            print("    Открытые порты: " .. table.concat(ports, ", "))
        else
            print("    Открытых портов: нет")
        end
    end
else
    print("  ❌ Модем не найден")
end

-- ============================================================
-- 7. ВСЕ КОМПОНЕНТЫ
-- ============================================================
print("\n[7] ВСЕ УСТРОЙСТВА (компоненты)")
local components = {}
for addr, name in component.list() do
    if not components[name] then components[name] = {} end
    table.insert(components[name], addr)
end

local sortedNames = {}
for name in pairs(components) do
    table.insert(sortedNames, name)
end
table.sort(sortedNames)

for _, name in ipairs(sortedNames) do
    local addrs = components[name]
    print("  " .. name .. " (" .. #addrs .. " шт.)")
    for i, addr in ipairs(addrs) do
        if i <= 2 then  -- Показываем только первые 2 адреса
            print("    - " .. addr)
        elseif i == 3 then
            print("    - ... и ещё " .. (#addrs - 2) .. " адресов")
            break
        end
    end
end

-- ============================================================
-- 8. ВРЕМЯ
-- ============================================================
print("\n[8] ВРЕМЯ")
print("  Текущее время: " .. os.date("%Y-%m-%d %H:%M:%S"))
print("  Timestamp: " .. os.time())
print("  Часовой пояс: " .. (os.getenv("TZ") or "не задан"))

-- ============================================================
-- 9. СТАТИСТИКА
-- ============================================================
print("\n[9] СТАТИСТИКА")
local count = 0
for _ in component.list() do count = count + 1 end
print("  Всего устройств: " .. count)

print("\n" .. "=" .. string.rep("=", 70))
print("                    ДИАГНОСТИКА ЗАВЕРШЕНА")
print("=" .. string.rep("=", 70))
