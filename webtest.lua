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
end

-- Проверка ME интерфейса
if component.isAvailable("me_interface") then
    printSuccess("ME интерфейс доступен")
    local me = component.me_interface
    printInfo("ME интерфейс готов к работе")
    
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
    return
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
    printWarning("Селектор не найден")
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
internalName = internalName:match("^%s*(.-)%s*$")

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
-- 3. ПОИСК ПРЕДМЕТА В ME (ВРУЧНУЮ)
-- ============================================================

printHeader("3. ПОИСК ПРЕДМЕТА В ME СИСТЕМЕ")

local me = component.me_interface
local foundItem = nil
local allItems = {}

-- ★★★ ПОЛУЧАЕМ ВСЕ ПРЕДМЕТЫ ИЗ ME ★★★
local itemsSuccess, itemsResult = pcall(function()
    return me.getItemsInNetwork()
end)

if not itemsSuccess or not itemsResult then
    printError("Не удалось получить список предметов из ME!")
    return
end

allItems = itemsResult
printInfo("Всего предметов в ME: " .. #allItems)

-- ★★★ ИЩЕМ НУЖНЫЙ ПРЕДМЕТ ★★★
local foundItems = {}
for _, item in ipairs(allItems) do
    local name = item.name or ""
    local dmg = item.damage or 0
    local qty = item.size or 0
    
    -- Проверяем по имени (точное совпадение)
    if name == internalName and dmg == damage then
        table.insert(foundItems, item)
    end
    
    -- Также проверяем частичное совпадение (на всякий случай)
    if not foundItems[1] and string.find(name, internalName) then
        table.insert(foundItems, item)
    end
end

if #foundItems == 0 then
    printError("❌ Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    printWarning("Возможные причины:")
    printWarning("  1. Неправильный internalName")
    printWarning("  2. Неправильный damage")
    printWarning("  3. Предмета нет в ME")
    print("")
    printInfo("Похожие предметы в ME (первые 20):")
    
    local count = 0
    for _, item in ipairs(allItems) do
        local name = item.name or ""
        if string.find(name, internalName:match("([^:]+)$") or "") then
            count = count + 1
            if count <= 20 then
                local dmg = item.damage or 0
                local qty = item.size or 0
                print(string.format("  %s (damage: %d) - %d шт.", name, dmg, qty))
            end
        end
    end
    
    if count == 0 then
        printInfo("Нет похожих предметов. Вот первые 20 предметов в ME:")
        for i = 1, math.min(20, #allItems) do
            local item = allItems[i]
            local name = item.name or "?"
            local dmg = item.damage or 0
            local qty = item.size or 0
            print(string.format("  %d. %s (damage: %d) - %d шт.", i, name, dmg, qty))
        end
    end
    
    print("")
    printInfo("Попробуйте ввести одно из названий выше")
    return
end

-- Берём первый найденный предмет
foundItem = foundItems[1]
local availableQty = foundItem.size or 0

printSuccess("✅ Предмет найден в ME системе!")
printInfo("  Имя: " .. (foundItem.name or "?"))
printInfo("  damage: " .. (foundItem.damage or 0))
printInfo("  количество: " .. availableQty)
printInfo("  всего найдено совпадений: " .. #foundItems)

if availableQty <= 0 then
    printError("Предмет есть в системе, но количество = 0!")
    return
end

-- ============================================================
-- 4. ТЕСТОВАЯ ВЫДАЧА
-- ============================================================

printHeader("4. ТЕСТОВАЯ ВЫДАЧА ПРЕДМЕТА")

-- ★★★ СОЗДАЁМ FINGERPRINT ДЛЯ ЭКСПОРТА ★★★
local fingerprint = { id = internalName, dmg = damage }

-- Проверяем направления
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

-- Функция для попытки выдачи
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
    
    -- Метод 3: exportItem с другими параметрами
    totalExtracted = totalExtracted + testExport("exportItem (альтернативный)", function()
        return me.exportItem(fingerprint, PULL_DIRECTION, remaining, false)
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
    printWarning("  1. Нет места в инвентаре (проверьте свободные слоты)")
    printWarning("  2. Предмет не может быть выдан через ME (особый предмет)")
    printWarning("  3. Неправильное направление выдачи")
    printWarning("  4. Проблемы с PIM (встаньте на PIM)")
    printWarning("  5. Предмет повреждён (damage не совпадает)")
end

print("")
printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
printColor("  ТЕСТ ЗАВЕРШЁН", colors.cyan)
printColor("═══════════════════════════════════════════════════════════════", colors.cyan)
print("")

print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
