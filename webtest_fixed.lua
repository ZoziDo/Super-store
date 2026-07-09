local component = require("component")
local event = require("event")
local computer = require("computer")

print("")
print("═══════════════════════════════════════════════════════════════")
print("  ТЕСТ ВЫДАЧИ ПРЕДМЕТА В PIM (ИСПРАВЛЕННЫЙ v4)")
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
local successDirection = nil

-- ПРАВИЛЬНЫЕ КОДЫ: 1..7 (не 0..6!)
-- 1=DOWN, 2=UP, 3=NORTH, 4=SOUTH, 5=WEST, 6=EAST, 7=UNKNOWN
local directionCodes = {
    DOWN = 1,
    UP = 2,
    NORTH = 3,
    SOUTH = 4,
    WEST = 5,
    EAST = 6,
    UNKNOWN = 7
}

print("   🔍 Пробуем exportItem с правильными кодами направлений (1..7):")
print("")

for dirName, dirCode in pairs(directionCodes) do
    if successResult then break end
    print("   Пробуем направление: " .. dirName .. " (код: " .. dirCode .. ")")
    
    local success, result = pcall(function()
        return me.exportItem(fingerprint, dirCode, testQty)
    end)
    
    if success then
        if result and type(result) == "number" and result > 0 then
            print("   ✅ УСПЕШНО! Выдано " .. result .. " шт. в направлении " .. dirName)
            successResult = true
            successDirection = dirName
        else
            print("     ❌ Результат: " .. tostring(result))
        end
    else
        local errMsg = tostring(result)
        print("     ⚠️ " .. errMsg)
    end
end

-- Если ничего не сработало
if not successResult then
    print("")
    print("❌ НИ ОДИН СПОСОБ НЕ СРАБОТАЛ!")
    print("")
    print("📋 АНАЛИЗ РЕЗУЛЬТАТОВ:")
    print("  • WEST и EAST: 'No neighbour attached' → PIM подключён туда, но не установлен")
    print("  • DOWN/UP/NORTH/SOUTH: 'nil' → предмет не выходит в этих направлениях")
    print("")
    print("⚙️ ЧТО ПРОВЕРИТЬ:")
    print("  1. Убедитесь, что PIM установлен НА сторону ME интерфейса (WEST или EAST)")
    print("  2. PIM должен быть АКТИВЕН (на красный сигнал, не наоборот)")
    print("  3. В ME интерфейсе должны быть кабели/линии к PIM")
    print("  4. PIM должен иметь прямой контакт с ME сетью (не через другие блоки)")
    print("  5. Проверьте, что PIM корректно принимает предметы (попробуйте вручную)")
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

print("✅ РАБОТАЮЩЕЕ НАПРАВЛЕНИЕ: " .. successDirection)
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
    print("  ⚠️ Инвентарь пуст! Предмет не появился в PIM.")
    print("     Возможно, он вышел в другое место или был удален.")
else
    print("  ✅ Предмет успешно появился в инвентаре PIM!")
end

print("")
print("═══════════════════════════════════════════════════════════════")
print("  КОД ДЛЯ ИСПОЛЬЗОВАНИЯ В СКРИПТАХ:")
print("═══════════════════════════════════════════════════════════════")
print("")
print("  me.exportItem(fingerprint, " .. directionCodes[successDirection] .. ", qty)")
print("  -- Где " .. directionCodes[successDirection] .. " = " .. successDirection)
print("")
print("Нажмите любую клавишу для выхода...")
event.pull("key_down")
