-- ============================================================
-- ★★★ ДИАГНОСТИЧЕСКИЙ СКРИПТ (ИСПРАВЛЕННЫЙ) ★★★
-- Сохраните как /home/test_export.lua
-- Запустите: lua /home/test_export.lua
-- ============================================================

local component = require("component")
local event = require("event")
local computer = require("computer")
local serialization = require("serialization")

-- Цвета для вывода
local colors = {
    red = "\x1b[31m",
    green = "\x1b[32m",
    yellow = "\x1b[33m",
    blue = "\x1b[34m",
    magenta = "\x1b[35m",
    cyan = "\x1b[36m",
    white = "\x1b[37m",
    reset = "\x1b[0m"
}

function printColor(text, color)
    print((color or colors.white) .. text .. colors.reset)
end

function printHeader(text)
    print("")
    printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
    printColor("  " .. text, colors.cyan)
    printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
    print("")
end

function printSuccess(text)
    printColor("✅ " .. text, colors.green)
end

function printError(text)
    printColor("❌ " .. text, colors.red)
end

function printWarning(text)
    printColor("⚠️ " .. text, colors.yellow)
end

function printInfo(text)
    printColor("📌 " .. text, colors.blue)
end

-- ============================================================
-- 1. ПРОВЕРКА КОМПОНЕНТОВ
-- ============================================================

printHeader("1. ПРОВЕРКА КОМПОНЕНТОВ")

-- Проверка PIM
local pimAddr = nil
for addr in component.list("pim") do
    pimAddr = addr
    break
end

if pimAddr then
    printSuccess("PIM найден: " .. pimAddr)
    local success, owner = pcall(function()
        return component.invoke(pimAddr, "getOwner")
    end)
    if success and owner then
        printInfo("Владелец PIM: " .. tostring(owner))
    else
        printWarning("Не удалось получить владельца PIM (это нормально, если никто не стоит)")
    end
else
    printError("PIM НЕ НАЙДЕН!")
    printInfo("Убедитесь, что PIM установлен и подключен")
end

-- Проверка ME интерфейса
if component.isAvailable("me_interface") then
    printSuccess("ME интерфейс доступен")
    local me = component.me_interface
    
    -- ★★★ УБРАЛИ getType() ★★★
    printInfo("ME интерфейс готов к работе")
    
    -- Проверяем, есть ли предметы в ME
    local itemsSuccess, itemsResult = pcall(function()
        return me.getItemsInNetwork()
    end)
    
    if itemsSuccess and itemsResult then
        printInfo("В ME системе: " .. #itemsResult .. " типов предметов")
    else
        printWarning("Не удалось получить список предметов из ME")
    end
else
    printError("ME интерфейс НЕ ДОСТУПЕН!")
    printInfo("Убедитесь, что ME интерфейс установлен и подключен к сети")
end

-- Проверка селектора
local selector = nil
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

if selector then
    printSuccess("Селектор найден")
else
    printWarning("Селектор не найден (не критично для теста)")
end

-- ============================================================
-- 2. ВВОД ДАННЫХ ДЛЯ ТЕСТА
-- ============================================================

printHeader("2. ВВОД ДАННЫХ ДЛЯ ТЕСТА")

print("")
print("Введите параметры предмета для проверки:")
print("")
print("Примеры внутренних имён:")
print("  - GraviSuite:vajra")
print("  - minecraft:diamond")
print("  - IC2:itemCofeeBeans")
print("")

io.write("  Internal name: ")
local internalName = io.read()
internalName = internalName:match("^%s*(.-)%s*$") -- trim

if not internalName or internalName == "" then
    printError("Имя не введено, используем GraviSuite:vajra")
    internalName = "GraviSuite:vajra"
end

io.write("  Damage (0-15, Enter для 0): ")
local damageInput = io.read()
local damage = 0
if damageInput and damageInput ~= "" then
    damage = tonumber(damageInput) or 0
end

io.write("  Количество для теста (Enter для 1): ")
local qtyInput = io.read()
local testQty = 1
if qtyInput and qtyInput ~= "" then
    testQty = tonumber(qtyInput) or 1
end

print("")
printInfo("Тестируем предмет:")
printInfo("  internalName: " .. internalName)
printInfo("  damage: " .. damage)
printInfo("  количество: " .. testQty)

-- ============================================================
-- 3. ПОИСК ПРЕДМЕТА В ME
-- ============================================================

printHeader("3. ПОИСК ПРЕДМЕТА В ME СИСТЕМЕ")

if not component.isAvailable("me_interface") then
    printError("ME интерфейс недоступен, тест прерван")
    return
end

local me = component.me_interface
local fingerprint = { id = internalName, dmg = damage }

-- ★★★ ПРОВЕРЯЕМ, ЕСТЬ ЛИ ПРЕДМЕТ В ME ★★★
local findSuccess, findResult = pcall(function()
    return me.findItem(fingerprint)
end)

if not findSuccess then
    printError("Ошибка поиска: " .. tostring(findResult))
    printInfo("Возможно, предмет не существует или неправильное имя")
    return
end

if not findResult then
    printError("Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    printWarning("Возможные причины:")
    printWarning("  1. Неправильный internalName")
    printWarning("  2. Неправильный damage")
    printWarning("  3. Предмета нет в ME")
    printWarning("  4. Предмет в ME под другим именем")
    print("")
    printInfo("Список доступных предметов в ME (первые 20):")
    
    local itemsSuccess, itemsResult = pcall(function()
        return me.getItemsInNetwork()
    end)
    
    if itemsSuccess and itemsResult then
        for i = 1, math.min(20, #itemsResult) do
            local item = itemsResult[i]
            local name = item.name or "?"
            local qty = item.size or 0
            local dmg = item.damage or 0
            print(string.format("  %d. %s (damage: %d) - %d шт.", i, name, dmg, qty))
        end
        if #itemsResult > 20 then
            print(string.format("  ... и ещё %d предметов", #itemsResult - 20))
        end
    end
    return
end

local availableQty = findResult.size or 0
printInfo("Найдено в ME: " .. availableQty .. " шт.")

if availableQty <= 0 then
    printError("Предмет есть в системе, но количество = 0!")
    return
end

printSuccess("✅ Предмет найден в ME системе!")

-- Получаем детали предмета (если возможно)
local detailSuccess, detailResult = pcall(function()
    return me.getItemDetail(internalName, damage)
end)

if detailSuccess and detailResult then
    printInfo("Детали предмета:")
    printInfo("  displayName: " .. (detailResult.displayName or "?"))
    printInfo("  maxSize: " .. (detailResult.maxSize or "?"))
    printInfo("  hasNBT: " .. tostring(detailResult.hasNBT or false))
else
    printInfo("Детали предмета не получены (не критично)")
end

-- ============================================================
-- 4. ТЕСТОВАЯ ВЫДАЧА
-- ============================================================

printHeader("4. ТЕСТОВАЯ ВЫДАЧА ПРЕДМЕТА")

-- ★★★ ПРОВЕРЯЕМ НАПРАВЛЕНИЯ ★★★
printInfo("Проверка доступных направлений...")
local directions = {"up", "down", "north", "south", "west", "east"}
local workingDirections = {}

for _, dir in ipairs(directions) do
    local testSuccess, testResult = pcall(function()
        return me.exportItem(fingerprint, dir, 1)
    end)
    if testSuccess and testResult and type(testResult) == "number" and testResult > 0 then
        table.insert(workingDirections, dir)
        printSuccess("Направление " .. dir .. " работает! Выдано " .. testResult .. " шт.")
    else
        printWarning("Направление " .. dir .. " не работает")
    end
end

if #workingDirections == 0 then
    printError("❌ НЕТ РАБОЧИХ НАПРАВЛЕНИЙ!")
    printInfo("Проверьте подключение ME интерфейса к хранилищу")
    return
end

local PULL_DIRECTION = workingDirections[1]
printInfo("Используем направление: " .. PULL_DIRECTION)

-- Функция для попытки выдачи с разными методами
function testExport(methodName, methodFunc)
    print("")
    printInfo("Пробуем метод: " .. methodName)
    
    local success, result = pcall(methodFunc)
    
    if success then
        local got = 0
        if type(result) == "number" then
            got = result
        elseif type(result) == "boolean" and result == true then
            got = testQty
        elseif type(result) == "table" then
            got = result.count or result.amount or result.size or 0
        end
        
        if got > 0 then
            printSuccess("✅ Успешно выдано " .. got .. " шт. через " .. methodName)
            return got
        else
            printWarning("⚠️ Метод " .. methodName .. " вернул " .. tostring(result) .. " (0 предметов)")
        end
    else
        printError("❌ Ошибка в " .. methodName .. ": " .. tostring(result))
    end
    
    return 0
end

local totalExtracted = 0

-- Метод 1: Стандартный exportItem
totalExtracted = totalExtracted + testExport("exportItem (стандартный)", function()
    return me.exportItem(fingerprint, PULL_DIRECTION, testQty)
end)

-- Если выдано меньше чем нужно - пробуем другие методы
if totalExtracted < testQty then
    local remaining = testQty - totalExtracted
    
    -- Метод 2: exportItem с force
    totalExtracted = totalExtracted + testExport("exportItem (force)", function()
        return me.exportItem(fingerprint, PULL_DIRECTION, remaining, true)
    end)
end

if totalExtracted < testQty then
    local remaining = testQty - totalExtracted
    
    -- Метод 3: simulateExport + export
    totalExtracted = totalExtracted + testExport("simulateExport", function()
        local sim = me.simulateExport(fingerprint, PULL_DIRECTION, remaining)
        if sim and sim.size and sim.size > 0 then
            return me.exportItem(fingerprint, PULL_DIRECTION, math.min(remaining, sim.size))
        end
        return 0
    end)
end

if totalExtracted < testQty then
    local remaining = testQty - totalExtracted
    
    -- Метод 4: findItem + export по одному
    totalExtracted = totalExtracted + testExport("findItem (по одному)", function()
        local found = me.findItem(fingerprint)
        if found and found.size and found.size > 0 then
            local toTake = math.min(remaining, found.size)
            return me.exportItem(fingerprint, PULL_DIRECTION, toTake)
        end
        return 0
    end)
end

-- ============================================================
-- 5. РЕЗУЛЬТАТЫ
-- ============================================================

printHeader("5. РЕЗУЛЬТАТЫ ТЕСТА")

print("")
if totalExtracted >= testQty then
    printSuccess("✅ ТЕСТ УСПЕШНЫЙ!")
    printInfo("Выдано " .. totalExtracted .. " из " .. testQty .. " шт.")
    printInfo("Предмет выдается нормально!")
else
    printError("❌ ТЕСТ НЕ УДАЛСЯ!")
    printError("Выдано только " .. totalExtracted .. " из " .. testQty .. " шт.")
    print("")
    printWarning("Возможные причины:")
    printWarning("  1. Нет места в инвентаре")
    printWarning("  2. Предмет не может быть выдан через ME (NBT, особый предмет)")
    printWarning("  3. Неправильное направление выдачи (" .. PULL_DIRECTION .. ")")
    printWarning("  4. Проблемы с PIM")
    printWarning("  5. Предмет повреждён (damage не совпадает)")
    printWarning("  6. В инвентаре нет свободных слотов")
    
    print("")
    printInfo("Проверьте инвентарь:")
    printInfo("  - Есть ли свободные слоты?")
    printInfo("  - Не занят ли инвентарь другими предметами?")
end

-- ============================================================
-- 6. ВСЕ ПРЕДМЕТЫ В ME (первые 20)
-- ============================================================

printHeader("6. ВСЕ ПРЕДМЕТЫ В ME (первые 20)")

local itemsSuccess, itemsResult = pcall(function()
    return me.getItemsInNetwork()
end)

if itemsSuccess and itemsResult and #itemsResult > 0 then
    printInfo("Всего предметов в ME: " .. #itemsResult)
    print("")
    for i = 1, math.min(20, #itemsResult) do
        local item = itemsResult[i]
        local name = item.name or "?"
        local qty = item.size or 0
        local dmg = item.damage or 0
        print(string.format("  %d. %s (damage: %d) - %d шт.", i, name, dmg, qty))
    end
    if #itemsResult > 20 then
        print(string.format("  ... и ещё %d предметов", #itemsResult - 20))
    end
else
    printWarning("В ME системе нет предметов или ошибка получения списка")
end

print("")
printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
printColor("  ТЕСТ ЗАВЕРШЁН", colors.cyan)
printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
print("")

-- Ждём нажатие клавиши
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
