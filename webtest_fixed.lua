local component = require("component")
local event = require("event")
local computer = require("computer")

print("")
print("═══════════════════════════════════════════════════════════════")
print("  ТЕСТ ВЫДАЧИ ПРЕДМЕТА В PIM (ИСПРАВЛЕННЫЙ v3)")
print("═══════════════════════════════════════════════════════════════")
print("")

-- 1. Проверяем компоненты
print("1. ПРОВЕРКА КОМПОНЕНТОВ")
print("")

-- ME интерфейс
if not component.isAvailable("me_interface") then
    print("❌ ME интерфейс НЕ ДОСТУПЕН!")
    return
end
local me = component.me_interface
print("✅ ME интерфейс доступен")

-- PIM
local pimAddr = nil
for addr in component.list("pim") do
    pimAddr = addr
    break
end
if not pimAddr then
    print("❌ PIM НЕ НАЙДЕН!")
    return
end
local pim = component.proxy(pimAddr)
print("✅ PIM найден: " .. pimAddr)

-- Проверяем, есть ли предметы в инвентаре PIM
print("")
print("   ⚠️ Проверка PIM...")
print("   Встаньте на PIM и нажмите любую клавишу")
event.pull("key_down")

local hasItems = false
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        hasItems = true
        print("   Слот " .. slot .. ": " .. stack.name .. " x" .. stack.size)
    end
end

if not hasItems then
    print("   ✅ Инвентарь пуст, можно тестировать")
else
    print("   ⚠️ В инвентаре есть предметы, они могут мешать")
end

print("")
print("2. ВВОД ДАННЫХ")
print("")

io.write("  Internal name (например GraviSuite:vajra): ")
local internalName = io.read()
internalName = internalName:match("^%s*(.-)%s*$")

if not internalName or internalName == "" then
    print("   Используем GraviSuite:vajra")
    internalName = "GraviSuite:vajra"
end

io.write("  Damage (Enter для 0): ")
local dmgInput = io.read()
local damage = 0
if dmgInput and dmgInput ~= "" then
    damage = tonumber(dmgInput) or 0
end

io.write("  Количество (Enter для 1): ")
local qtyInput = io.read()
local testQty = 1
if qtyInput and qtyInput ~= "" then
    testQty = tonumber(qtyInput) or 1
end

print("")
print("   Тестируем: " .. internalName .. " (damage: " .. damage .. ") x" .. testQty)
print("")

-- 3. Проверяем наличие предмета в ME
print("3. ПОИСК В ME")
print("")

local fingerprint = { id = internalName, dmg = damage }
local items = me.getItemsInNetwork()
local foundItem = nil

for _, item in ipairs(items) do
    if item.name == internalName and (item.damage or 0) == damage then
        foundItem = item
        break
    end
end

if not foundItem then
    print("❌ Предмет НЕ НАЙДЕН в ME системе!")
    print("")
    print("   Похожие предметы в ME:")
    local count = 0
    for _, item in ipairs(items) do
        if string.find(item.name, internalName:match("[^:]+$") or "") then
            count = count + 1
            if count <= 10 then
                print("     " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
            end
        end
    end
    if count == 0 then
        print("     Нет похожих предметов. Первые 10 в ME:")
        for i = 1, math.min(10, #items) do
            local item = items[i]
            print("     " .. item.name .. " (damage: " .. (item.damage or 0) .. ") - " .. (item.size or 0) .. " шт.")
        end
    end
    return
end

print("✅ Предмет найден!")
print("   Количество в ME: " .. (foundItem.size or 0) .. " шт.")

if (foundItem.size or 0) < testQty then
    print("⚠️ В ME меньше предметов чем нужно для теста!")
    testQty = foundItem.size or 0
    if testQty == 0 then
        print("❌ Нет предметов для теста")
        return
    end
    print("   Будем тестировать с " .. testQty .. " шт.")
end

print("")
print("4. ПРОВЕРКА ИНВЕНТАРЯ")
print("")

local freeSlots = 0
local slotContents = {}

for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        slotContents[slot] = { name = stack.name, size = stack.size, damage = stack.damage or 0 }
    else
        freeSlots = freeSlots + 1
    end
end

print("   Свободных слотов: " .. freeSlots)

if freeSlots == 0 then
    print("❌ ИНВЕНТАРЬ ПОЛОН! Освободите место.")
    print("   Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

if next(slotContents) then
    print("   Предметы в инвентаре:")
    for slot, data in pairs(slotContents) do
        print("     Слот " .. slot .. ": " .. data.name .. " x" .. data.size)
    end
else
    print("   Инвентарь пуст")
end

print("")
print("5. ТЕСТОВАЯ ВЫДАЧА")
print("")

local successResult = false

-- КЛЮЧЕВОЕ ОТКРЫТИЕ: используем ЧИСЛОВЫЕ коды направлений (1..7)
-- DOWN=0, UP=1, NORTH=2, SOUTH=3, WEST=4, EAST=5, UNKNOWN=6
local directionCodes = {
    DOWN = 0,
    UP = 1,
    NORTH = 2,
    SOUTH = 3,
    WEST = 4,
    EAST = 5,
    UNKNOWN = 6
}

print("   🔍 Пробуем exportItem с числовыми кодами направлений:")
print("")

for dirName, dirCode in pairs(directionCodes) do
    if successResult then break end
    print("   Пробуем направление: " .. dirName .. " (код: " .. dirCode .. ")")
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, dirCode, testQty)
    end)
    
    if success and result and type(result) == "number" and result > 0 then
        print("   ✅ УСПЕШНО! Выдано " .. result .. " шт. в направлении " .. dirName)
        print("")
        print("   ИСПОЛЬЗУЙТЕ В КОДЕ:")
        print("   me.exportItem(fingerprint, " .. dirCode .. ", qty)  -- " .. dirName)
        print("   ИЛИ")
        print("   me.exportItem(fingerprint, \"" .. dirName .. "\", qty)")
        successResult = true
    else
        if success then
            print("     ❌ Результат: " .. tostring(result))
        else
            print("     ❌ Ошибка: " .. tostring(result))
        end
    end
end

-- Если ничего не сработало
if not successResult then
    print("")
    print("❌ НИ ОДИН СПОСОБ НЕ СРАБОТАЛ!")
    print("")
    print("Возможные причины:")
    print("  1. ME интерфейс не подключён к сети хранения")
    print("  2. Предмет не может быть выдан через ME (NBT, особый предмет)")
    print("  3. Проблема с PIM (не настроен на приём)")
    print("  4. В инвентаре нет места для этого конкретного предмета")
    print("  5. PIM находится не в том направлении относительно ME")
    print("")
    print("Нажмите любую клавишу для выхода...")
    event.pull("key_down")
    return
end

-- Если успешно
print("")
print("═══════════════════════════════════════════════════════════════")
print("  ✅ ТЕСТ ЗАВЕРШЁН УСПЕШНО!")
print("═══════════════════════════════════════════════════════════════")
print("")

-- Проверяем, что предмет появился в инвентаре
print("ПРОВЕРКА ИНВЕНТАРЯ ПОСЛЕ ВЫДАЧИ:")
local hasItemsAfter = false
for slot = 1, 36 do
    local stack = pim.getStackInSlot(slot)
    if stack and stack.size and stack.size > 0 then
        hasItemsAfter = true
        print("  Слот " .. slot .. ": " .. stack.name .. " x" .. stack.size)
    end
end

if not hasItemsAfter then
    print("  Инвентарь пуст! Предмет не появился.")
end

print("")
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
