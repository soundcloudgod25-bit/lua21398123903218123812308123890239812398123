--==============================================================
-- REVELATION STANDALONE MENU
-- GameSense synchronized menu animation
--==============================================================

local UI = {}

--==============================================================
-- CONSTANTS
--==============================================================

local VK_LBUTTON = 0x01
local VK_ESCAPE  = 0x1B

local CHECKBOX_SIZE = 8
local LABEL_OFFSET = 15

local SLIDER_X_OFFSET = 20
local SLIDER_HEIGHT = 8

local BOX_X_OFFSET = 20
local BOX_HEIGHT = 20
local BOX_ITEM_OFFSET = 10

local DROPDOWN_HEIGHT = 20
local DROPDOWN_ITEM_HEIGHT = 16

local KEYBIND_HEIGHT = 20

--==============================================================
-- COLORS
--==============================================================

local C = {
    black       = { 0,   0,   0,   255 },
    outer       = { 5,   5,   5,   255 },
    frame       = { 40,  40,  40,  255 },
    frame_light = { 60,  60,  60,  255 },

    background  = { 12,  12,  12,  255 },
    panel       = { 17,  17,  17,  255 },
    element     = { 41,  41,  41,  255 },

    text        = { 205, 205, 205, 255 },
    text_dim    = { 152, 152, 152, 255 },
    text_dark   = { 90,  90, 90, 255 },

    accent      = { 140, 180, 255, 255 }
}

--==============================================================
-- HELPERS
--==============================================================

local function color(r, g, b, a)
    return {
        r,
        g,
        b,
        a or 255
    }
end

local function rgba(c, alpha)
    return
        c[1],
        c[2],
        c[3],
        alpha or c[4] or 255
end

local function clamp(v, min, max)

    if v < min then
        return min
    end

    if v > max then
        return max
    end

    return v
end

local function round_step(v, step)

    if step == 0 then
        return v
    end

    return math.floor(
        v / step + 0.5
    ) * step
end

local function inside(mx, my, x, y, w, h)

    return
        mx >= x and
        mx <= x + w and
        my >= y and
        my <= y + h
end

local function fill(x, y, w, h, c, alpha)

    if w <= 0 or h <= 0 then
        return
    end

    renderer.rectangle(
        x,
        y,
        w,
        h,
        rgba(c, alpha)
    )
end

local function outline(x, y, w, h, c, alpha)

    renderer.rectangle(
        x,
        y,
        w,
        1,
        rgba(c, alpha)
    )

    renderer.rectangle(
        x,
        y + h - 1,
        w,
        1,
        rgba(c, alpha)
    )

    renderer.rectangle(
        x,
        y,
        1,
        h,
        rgba(c, alpha)
    )

    renderer.rectangle(
        x + w - 1,
        y,
        1,
        h,
        rgba(c, alpha)
    )
end

local function gradient(
    x,
    y,
    w,
    h,
    c1,
    c2,
    horizontal,
    alpha
)

    if w <= 0 or h <= 0 then
        return
    end

    renderer.gradient(
        x,
        y,
        w,
        h,

        c1[1],
        c1[2],
        c1[3],
        alpha or c1[4] or 255,

        c2[1],
        c2[2],
        c2[3],
        alpha or c2[4] or 255,

        horizontal
    )
end

local function draw_text(
    x,
    y,
    c,
    value,
    flags,
    alpha
)

    renderer.text(
        x,
        y,
        c[1],
        c[2],
        c[3],
        alpha or c[4] or 255,
        flags or "",
        0,
        tostring(value or "")
    )
end

local function text_size(value)

    local w, h =
        renderer.measure_text(
            nil,
            tostring(value or "")
        )

    return w, h
end

--==============================================================
-- INPUT
--==============================================================

local input = {
    down = {},
    pressed = {},
    mouse_x = 0,
    mouse_y = 0
}

function input:update()

    self.mouse_x,
    self.mouse_y =
        ui.mouse_position()

    self.pressed = {}

    for key = 1, 254 do

        local down =
            client.key_state(key)

        self.pressed[key] =
            down and not self.down[key]

        self.down[key] =
            down
    end
end

function input:is_down(key)

    return self.down[key] == true
end

function input:is_pressed(key)

    return self.pressed[key] == true
end

--==============================================================
-- KEY NAMES
--==============================================================

local key_names = {
    [0x01] = "mouse1",
    [0x02] = "mouse2",
    [0x04] = "mouse3",
    [0x05] = "mouse4",
    [0x06] = "mouse5",

    [0x08] = "backspace",
    [0x09] = "tab",
    [0x0D] = "enter",

    [0x10] = "shift",
    [0x11] = "ctrl",
    [0x12] = "alt",

    [0x1B] = "esc",
    [0x20] = "space",

    [0x21] = "pgup",
    [0x22] = "pgdn",

    [0x24] = "home",
    [0x25] = "left",
    [0x26] = "up",
    [0x27] = "right",
    [0x28] = "down",

    [0x2D] = "insert",
    [0x2E] = "delete"
}

for i = 0x30, 0x39 do
    key_names[i] =
        string.char(i)
end

for i = 0x41, 0x5A do
    key_names[i] =
        string.char(i + 32)
end

for i = 1, 12 do
    key_names[0x6F + i] =
        "f" .. i
end

--==============================================================
-- BASE ELEMENT
--==============================================================

local Element = {}

Element.__index = Element

function Element:new(kind)

    local self =
        setmetatable({}, Element)

    self.kind = kind

    self.parent = nil

    self.x = 0
    self.y = 0

    self.w = 220
    self.h = 16

    self.visible = true

    self.callback = nil

    return self
end

function Element:absolute()

    local form =
        self.parent

    return
        form.content_x + self.x,
        form.content_y + self.y
end

function Element:set_callback(fn)

    self.callback = fn

    return self
end

function Element:fire()

    if self.callback ~= nil then
        self.callback(self)
    end
end

--==============================================================
-- CHECKBOX
--==============================================================

local Checkbox =
    setmetatable({}, Element)

Checkbox.__index = Checkbox

function Checkbox:new(label, value)

    local self =
        Element.new(
            self,
            "checkbox"
        )

    self.label =
        label or ""

    self.value =
        value == true

    self.w =
        CHECKBOX_SIZE

    self.h =
        CHECKBOX_SIZE

    return self
end

function Checkbox:get()

    return self.value
end

function Checkbox:set(value)

    local new_value =
        value == true

    local changed =
        self.value ~= new_value

    self.value =
        new_value

    if changed then
        self:fire()
    end
end

function Checkbox:click()

    self:set(
        not self.value
    )
end

function Checkbox:draw(alpha)

    local x, y =
        self:absolute()

    outline(
        x,
        y,
        CHECKBOX_SIZE,
        CHECKBOX_SIZE,
        C.black,
        alpha
    )

    if self.value then

        fill(
            x + 1,
            y + 1,
            CHECKBOX_SIZE - 2,
            CHECKBOX_SIZE - 2,
            C.accent,
            alpha
        )

    else

        gradient(
            x + 1,
            y + 1,
            CHECKBOX_SIZE - 2,
            CHECKBOX_SIZE - 2,
            color(75, 75, 75),
            color(45, 45, 45),
            false,
            alpha
        )
    end

    if self.label ~= "" then

        draw_text(
            x + LABEL_OFFSET,
            y - 3,
            C.text,
            self.label,
            nil,
            alpha
        )
    end
end

--==============================================================
-- SLIDER
--==============================================================

local Slider =
    setmetatable({}, Element)

Slider.__index = Slider

function Slider:new(
    label,
    min,
    max,
    value,
    step,
    suffix
)

    local self =
        Element.new(
            self,
            "slider"
        )

    self.label =
        label or ""

    self.min =
        min or 0

    self.max =
        max or 100

    self.value =
        value or self.min

    self.step =
        step or 1

    self.suffix =
        suffix or ""

    self.dragging = false

    self.offset =
        self.label ~= "" and 15 or 0

    self.h =
        self.offset +
        SLIDER_HEIGHT

    return self
end

function Slider:get()

    return self.value
end

function Slider:set(value)

    local next_value =
        clamp(
            round_step(
                value,
                self.step
            ),
            self.min,
            self.max
        )

    local changed =
        next_value ~= self.value

    self.value =
        next_value

    if changed then
        self:fire()
    end
end

function Slider:think()

    if not self.dragging then
        return
    end

    if not input:is_down(
        VK_LBUTTON
    ) then

        self.dragging = false

        return
    end

    local x, y =
        self:absolute()

    local bx =
        x + SLIDER_X_OFFSET

    local bw =
        self.w -
        SLIDER_X_OFFSET

    local ratio =
        clamp(
            (
                input.mouse_x -
                bx
            ) / bw,
            0,
            1
        )

    self:set(
        self.min +
        (
            self.max -
            self.min
        ) * ratio
    )
end

function Slider:click()

    local x, y =
        self:absolute()

    local bx =
        x + SLIDER_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        SLIDER_X_OFFSET

    if inside(
        input.mouse_x,
        input.mouse_y,
        bx,
        by,
        bw,
        SLIDER_HEIGHT
    ) then

        self.dragging = true

        self:think()
    end
end

function Slider:draw(alpha)

    local x, y =
        self:absolute()

    if self.label ~= "" then

        draw_text(
            x + LABEL_OFFSET,
            y - 2,
            C.text,
            self.label,
            nil,
            alpha
        )
    end

    local bx =
        x + SLIDER_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        SLIDER_X_OFFSET

    local ratio =
        (
            self.value -
            self.min
        ) /
        (
            self.max -
            self.min
        )

    local fill_width =
        math.floor(
            clamp(
                ratio,
                0,
                1
            ) * bw
        )

    outline(
        bx,
        by,
        bw,
        SLIDER_HEIGHT,
        C.black,
        alpha
    )

    gradient(
        bx + 1,
        by + 1,
        bw - 2,
        SLIDER_HEIGHT - 2,
        color(75, 75, 75),
        color(45, 45, 45),
        false,
        alpha
    )

    if fill_width > 2 then

        fill(
            bx + 1,
            by + 1,
            fill_width - 2,
            SLIDER_HEIGHT - 2,
            C.accent,
            alpha
        )
    end

    local value =
        tostring(
            math.floor(
                self.value * 10 +
                0.5
            ) / 10
        )

    value =
        value ..
        self.suffix

    local tw =
        text_size(value)

    draw_text(
        bx +
        fill_width -
        math.floor(tw / 2),
        by + 1,
        C.text,
        value,
        nil,
        alpha
    )
end

--==============================================================
-- DROPDOWN
--==============================================================

local Dropdown =
    setmetatable({}, Element)

Dropdown.__index = Dropdown

function Dropdown:new(
    label,
    items,
    active
)

    local self =
        Element.new(
            self,
            "dropdown"
        )

    self.label =
        label or ""

    self.items =
        items or {}

    self.active =
        active or 1

    self.open = false

    self.anim = 0

    self.offset =
        self.label ~= "" and 15 or 0

    self.h =
        self.offset +
        DROPDOWN_HEIGHT

    return self
end

function Dropdown:get()

    return self.items[
        self.active
    ]
end

function Dropdown:set(index)

    index =
        clamp(
            index,
            1,
            #self.items
        )

    if self.active ~= index then

        self.active =
            index

        self:fire()
    end
end

function Dropdown:think()

    local target =
        self.open
        and
        (
            #self.items *
            DROPDOWN_ITEM_HEIGHT
        )
        or 0

    local speed =
        1000 *
        globals.frametime()

    if self.anim < target then

        self.anim =
            math.min(
                self.anim + speed,
                target
            )

    elseif self.anim > target then

        self.anim =
            math.max(
                self.anim - speed,
                target
            )
    end
end

function Dropdown:click()

    local x, y =
        self:absolute()

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        BOX_X_OFFSET

    if inside(
        input.mouse_x,
        input.mouse_y,
        bx,
        by,
        bw,
        DROPDOWN_HEIGHT
    ) then

        self.open =
            not self.open

        return
    end

    if not self.open then
        return
    end

    for i = 1, #self.items do

        local iy =
            by +
            DROPDOWN_HEIGHT +
            2 +
            (
                i - 1
            ) *
            DROPDOWN_ITEM_HEIGHT

        if inside(
            input.mouse_x,
            input.mouse_y,
            bx,
            iy,
            bw,
            DROPDOWN_ITEM_HEIGHT
        ) then

            self:set(i)

            self.open = false

            return
        end
    end
end

function Dropdown:draw(alpha)

    local x, y =
        self:absolute()

    if self.label ~= "" then

        draw_text(
            x + LABEL_OFFSET,
            y - 2,
            C.text,
            self.label,
            nil,
            alpha
        )
    end

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        BOX_X_OFFSET

    outline(
        bx,
        by,
        bw,
        DROPDOWN_HEIGHT,
        C.black,
        alpha
    )

    fill(
        bx + 1,
        by + 1,
        bw - 2,
        DROPDOWN_HEIGHT - 2,
        C.element,
        alpha
    )

    draw_text(
        bx + BOX_ITEM_OFFSET,
        by + 4,
        C.text_dim,
        self:get() or "none",
        nil,
        alpha
    )

    if self.open then

        renderer.triangle(
            bx + bw - 12,
            by + 12,
            bx + bw - 5,
            by + 12,
            bx + bw - 9,
            by + 7,
            152,
            152,
            152,
            alpha
        )

    else

        renderer.triangle(
            bx + bw - 12,
            by + 8,
            bx + bw - 5,
            by + 8,
            bx + bw - 9,
            by + 13,
            152,
            152,
            152,
            alpha
        )
    end

    if self.anim > 0 then

        local iy =
            by +
            DROPDOWN_HEIGHT +
            2

        local height =
            math.floor(
                self.anim
            )

        outline(
            bx,
            iy,
            bw,
            height + 2,
            C.black,
            alpha
        )

        fill(
            bx + 1,
            iy + 1,
            bw - 2,
            height,
            C.element,
            alpha
        )

        for i, item in ipairs(
            self.items
        ) do

            local item_y =
                iy +
                (
                    i - 1
                ) *
                DROPDOWN_ITEM_HEIGHT

            if item_y <
                iy + height
            then

                local item_color =
                    i == self.active
                    and C.accent
                    or C.text_dim

                draw_text(
                    bx + BOX_ITEM_OFFSET,
                    item_y + 4,
                    item_color,
                    item,
                    nil,
                    alpha
                )
            end
        end
    end
end

--==============================================================
-- MULTI DROPDOWN
--==============================================================

local MultiDropdown =
    setmetatable(
        {},
        Dropdown
    )

MultiDropdown.__index =
    MultiDropdown

function MultiDropdown:new(
    label,
    items
)

    local self =
        Dropdown.new(
            self,
            label,
            items,
            1
        )

    self.kind =
        "multidropdown"

    self.selected = {}

    return self
end

function MultiDropdown:get(index)

    return self.selected[
        index
    ] == true
end

function MultiDropdown:summary()

    local result = {}

    for i = 1, #self.items do

        if self.selected[i] then

            table.insert(
                result,
                self.items[i]
            )
        end
    end

    if #result == 0 then
        return "none"
    end

    return table.concat(
        result,
        ", "
    )
end

function MultiDropdown:click()

    local x, y =
        self:absolute()

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        BOX_X_OFFSET

    if inside(
        input.mouse_x,
        input.mouse_y,
        bx,
        by,
        bw,
        DROPDOWN_HEIGHT
    ) then

        self.open =
            not self.open

        return
    end

    if not self.open then
        return
    end

    for i = 1, #self.items do

        local iy =
            by +
            DROPDOWN_HEIGHT +
            2 +
            (
                i - 1
            ) *
            DROPDOWN_ITEM_HEIGHT

        if inside(
            input.mouse_x,
            input.mouse_y,
            bx,
            iy,
            bw,
            DROPDOWN_ITEM_HEIGHT
        ) then

            self.selected[i] =
                not self.selected[i]

            self:fire()

            return
        end
    end
end

function MultiDropdown:draw(alpha)

    local x, y =
        self:absolute()

    if self.label ~= "" then

        draw_text(
            x + LABEL_OFFSET,
            y - 2,
            C.text,
            self.label,
            nil,
            alpha
        )
    end

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + self.offset

    local bw =
        self.w -
        BOX_X_OFFSET

    outline(
        bx,
        by,
        bw,
        DROPDOWN_HEIGHT,
        C.black,
        alpha
    )

    fill(
        bx + 1,
        by + 1,
        bw - 2,
        DROPDOWN_HEIGHT - 2,
        C.element,
        alpha
    )

    draw_text(
        bx + BOX_ITEM_OFFSET,
        by + 4,
        C.text_dim,
        self:summary(),
        nil,
        alpha
    )

    if self.open then

        local iy =
            by +
            DROPDOWN_HEIGHT +
            2

        local height =
            #self.items *
            DROPDOWN_ITEM_HEIGHT

        outline(
            bx,
            iy,
            bw,
            height + 2,
            C.black,
            alpha
        )

        fill(
            bx + 1,
            iy + 1,
            bw - 2,
            height,
            C.element,
            alpha
        )

        for i, item in ipairs(
            self.items
        ) do

            local item_y =
                iy +
                (
                    i - 1
                ) *
                DROPDOWN_ITEM_HEIGHT

            local item_color =
                self.selected[i]
                and C.accent
                or C.text_dim

            draw_text(
                bx + BOX_ITEM_OFFSET,
                item_y + 4,
                item_color,
                item,
                nil,
                alpha
            )
        end
    end
end

--==============================================================
-- KEYBIND
--==============================================================

local Keybind =
    setmetatable(
        {},
        Element
    )

Keybind.__index =
    Keybind

function Keybind:new(label)

    local self =
        Element.new(
            self,
            "keybind"
        )

    self.label =
        label or ""

    self.key = -1

    self.waiting = false

    self.offset = 15

    self.h =
        15 +
        KEYBIND_HEIGHT

    return self
end

function Keybind:think()

    if not self.waiting then
        return
    end

    for key = 1, 254 do

        if input:is_pressed(key) then

            if key == VK_ESCAPE then

                self.key = -1

            else

                self.key = key
            end

            self.waiting = false

            self:fire()

            return
        end
    end
end

function Keybind:click()

    local x, y =
        self:absolute()

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + 15

    local bw =
        self.w -
        BOX_X_OFFSET

    if inside(
        input.mouse_x,
        input.mouse_y,
        bx,
        by,
        bw,
        KEYBIND_HEIGHT
    ) then

        self.waiting = true
    end
end

function Keybind:draw(alpha)

    local x, y =
        self:absolute()

    draw_text(
        x + BOX_X_OFFSET,
        y - 2,
        C.text,
        self.label,
        nil,
        alpha
    )

    local bx =
        x + BOX_X_OFFSET

    local by =
        y + 15

    local bw =
        self.w -
        BOX_X_OFFSET

    outline(
        bx,
        by,
        bw,
        KEYBIND_HEIGHT,
        C.black,
        alpha
    )

    fill(
        bx + 1,
        by + 1,
        bw - 2,
        KEYBIND_HEIGHT - 2,
        C.element,
        alpha
    )

    local value

    if self.waiting then

        value = "press key"

    elseif self.key >= 0 then

        value =
            key_names[self.key]
            or
            (
                "[" ..
                self.key ..
                "]"
            )

    else

        value = ""
    end

    draw_text(
        bx + BOX_ITEM_OFFSET,
        by + 4,
        self.waiting
        and C.accent
        or C.text_dim,
        value,
        nil,
        alpha
    )
end

--==============================================================
-- BUTTON
--==============================================================

local Button =
    setmetatable(
        {},
        Element
    )

Button.__index =
    Button

function Button:new(label)

    local self =
        Element.new(
            self,
            "button"
        )

    self.label =
        label or ""

    self.h =
        BOX_HEIGHT

    return self
end

function Button:click()

    local x, y =
        self:absolute()

    local bx =
        x + BOX_X_OFFSET

    local by = y

    local bw =
        self.w -
        BOX_X_OFFSET

    if inside(
        input.mouse_x,
        input.mouse_y,
        bx,
        by,
        bw,
        BOX_HEIGHT
    ) then

        self:fire()
    end
end

function Button:draw(alpha)

    local x, y =
        self:absolute()

    local bx =
        x + BOX_X_OFFSET

    local bw =
        self.w -
        BOX_X_OFFSET

    outline(
        bx,
        y,
        bw,
        BOX_HEIGHT,
        C.black,
        alpha
    )

    fill(
        bx + 1,
        y + 1,
        bw - 2,
        BOX_HEIGHT - 2,
        C.element,
        alpha
    )

    draw_text(
        bx + bw / 2,
        y + 4,
        C.text,
        self.label,
        "c",
        alpha
    )
end

--==============================================================
-- TAB
--==============================================================

local Tab = {}

Tab.__index = Tab

function Tab:new(name)

    return setmetatable(
        {
            name = name,
            elements = {},
            form = nil,
            columns = {
                0,
                0
            }
        },
        Tab
    )
end

function Tab:add(
    element,
    column
)

    element.parent =
        self.form

    element.column =
        column or 0

    table.insert(
        self.elements,
        element
    )

    return element
end

function Tab:checkbox(
    label,
    value,
    column
)

    return self:add(
        Checkbox:new(
            label,
            value
        ),
        column
    )
end

function Tab:slider(
    label,
    min,
    max,
    value,
    step,
    suffix,
    column
)

    return self:add(
        Slider:new(
            label,
            min,
            max,
            value,
            step,
            suffix
        ),
        column
    )
end

function Tab:dropdown(
    label,
    items,
    default,
    column
)

    return self:add(
        Dropdown:new(
            label,
            items,
            default
        ),
        column
    )
end

function Tab:multidropdown(
    label,
    items,
    column
)

    return self:add(
        MultiDropdown:new(
            label,
            items
        ),
        column
    )
end

function Tab:keybind(
    label,
    column
)

    return self:add(
        Keybind:new(label),
        column
    )
end

function Tab:button(
    label,
    column
)

    return self:add(
        Button:new(label),
        column
    )
end

--==============================================================
-- FORM
--==============================================================

local Form = {}

Form.__index = Form

function Form:new(
    x,
    y,
    w,
    h
)

    local self =
        setmetatable(
            {},
            Form
        )

    self.x =
        x or 250

    self.y =
        y or 150

    self.w =
        w or 620

    self.h =
        h or 430

    self.open = false

    self.opacity = 0

    self.tabs = {}

    self.active_tab = 1

    self.dragging = false

    self.drag_x = 0
    self.drag_y = 0

    self.active_element = nil

    self.accent =
        color(
            140,
            180,
            255
        )

    self.tab_x =
        self.x + 20

    self.tab_y =
        self.y + 20

    self.tab_w =
        100

    self.content_x =
        self.x + 140

    self.content_y =
        self.y + 20

    self.content_w =
        self.w - 160

    self.content_h =
        self.h - 40

    return self
end

function Form:tab(name)

    local tab =
        Tab:new(name)

    tab.form =
        self

    table.insert(
        self.tabs,
        tab
    )

    return tab
end

function Form:update_geometry()

    self.tab_x =
        self.x + 20

    self.tab_y =
        self.y + 20

    self.content_x =
        self.x + 140

    self.content_y =
        self.y + 20

    self.content_w =
        self.w - 160

    self.content_h =
        self.h - 40

    for _, tab in ipairs(
        self.tabs
    ) do

        tab.form =
            self

        local column_y = {
            0,
            0
        }

        for _, element in ipairs(
            tab.elements
        ) do

            element.parent =
                self

            local column =
                element.column
                or 0

            if column == 0 then

                element.x = 10

            else

                element.x =
                    math.floor(
                        self.content_w / 2
                    ) + 10
            end

            element.y =
                column_y[
                    column + 1
                ]

            element.w =
                math.floor(
                    self.content_w / 2
                ) - 20

            column_y[
                column + 1
            ] =
                column_y[
                    column + 1
                ] +
                element.h +
                10
        end
    end
end

--==============================================================
-- FORM INPUT
--==============================================================

function Form:process()

    if not self.open then
        return
    end

    local mx =
        input.mouse_x

    local my =
        input.mouse_y

    if input:is_pressed(
        VK_LBUTTON
    ) then

        for i, tab in ipairs(
            self.tabs
        ) do

            local ty =
                self.tab_y +
                (
                    i - 1
                ) * 16

            if inside(
                mx,
                my,
                self.tab_x,
                ty,
                self.tab_w,
                16
            ) then

                self.active_tab =
                    i

                self.active_element =
                    nil

                return
            end
        end
    end

    local tab =
        self.tabs[
            self.active_tab
        ]

    if tab == nil then
        return
    end

    if input:is_pressed(
        VK_LBUTTON
    ) then

        for i = #tab.elements, 1, -1 do

            local e =
                tab.elements[i]

            if e.visible ~= false then

                local ex =
                    self.content_x +
                    e.x

                local ey =
                    self.content_y +
                    e.y

                if inside(
                    mx,
                    my,
                    ex,
                    ey,
                    e.w,
                    e.h
                ) then

                    self.active_element =
                        e

                    if e.click then
                        e:click()
                    end

                    return
                end
            end
        end
    end

    if input:is_pressed(
        VK_LBUTTON
    ) then

        if inside(
            mx,
            my,
            self.x,
            self.y,
            self.w,
            18
        ) then

            self.dragging = true

            self.drag_x =
                mx - self.x

            self.drag_y =
                my - self.y

            return
        end
    end

    if not input:is_down(
        VK_LBUTTON
    ) then

        self.dragging = false
    end

    if self.dragging then

        self.x =
            mx - self.drag_x

        self.y =
            my - self.drag_y

        self:update_geometry()
    end
end

--==============================================================
-- FORM THINK
--==============================================================

function Form:think()

    if not self.open then
        return
    end

    local tab =
        self.tabs[
            self.active_tab
        ]

    if tab == nil then
        return
    end

    for _, element in ipairs(
        tab.elements
    ) do

        if element.think then
            element:think()
        end
    end
end

--==============================================================
-- FORM DRAW
--==============================================================

function Form:draw()

    if self.opacity <= 0 then
        return
    end

    local alpha =
        math.floor(
            255 *
            self.opacity
        )

    local accent =
        color(
            self.accent[1],
            self.accent[2],
            self.accent[3],
            alpha
        )

    --==========================================================
    -- OUTER FRAME
    --==========================================================

    fill(
        self.x,
        self.y,
        self.w,
        self.h,
        C.background,
        alpha
    )

    outline(
        self.x,
        self.y,
        self.w,
        self.h,
        C.outer,
        alpha
    )

    outline(
        self.x + 1,
        self.y + 1,
        self.w - 2,
        self.h - 2,
        C.frame_light,
        alpha
    )

    outline(
        self.x + 3,
        self.y + 3,
        self.w - 6,
        self.h - 6,
        C.frame,
        alpha
    )

    outline(
        self.x + 5,
        self.y + 5,
        self.w - 10,
        self.h - 10,
        C.frame_light,
        alpha
    )

    --==========================================================
    -- HEADER
    --==========================================================

    draw_text(
        self.x + 12,
        self.y + 5,
        C.text,
        "REVELATION",
        nil,
        alpha
    )

    draw_text(
        self.x + self.w - 35,
        self.y + 5,
        C.text_dim,
        "1.0",
        nil,
        alpha
    )

    --==========================================================
    -- TAB PANEL
    --==========================================================

    fill(
        self.tab_x,
        self.tab_y,
        self.tab_w,
        self.h - 40,
        C.panel,
        alpha
    )

    outline(
        self.tab_x,
        self.tab_y,
        self.tab_w,
        self.h - 40,
        C.black,
        alpha
    )

    outline(
        self.tab_x + 1,
        self.tab_y + 1,
        self.tab_w - 2,
        self.h - 42,
        C.frame_light,
        alpha
    )

    --==========================================================
    -- TABS
    --==========================================================

    for i, tab in ipairs(
        self.tabs
    ) do

        local ty =
            self.tab_y +
            (
                i - 1
            ) * 16

        local selected =
            i == self.active_tab

        if selected then

            fill(
                self.tab_x + 2,
                ty,
                self.tab_w - 4,
                16,
                color(
                    30,
                    30,
                    30
                ),
                alpha
            )

            draw_text(
                self.tab_x + 10,
                ty + 4,
                accent,
                tab.name,
                nil,
                alpha
            )

        else

            draw_text(
                self.tab_x + 10,
                ty + 4,
                C.text_dim,
                tab.name,
                nil,
                alpha
            )
        end
    end

    --==========================================================
    -- CONTENT
    --==========================================================

    fill(
        self.content_x,
        self.content_y,
        self.content_w,
        self.content_h,
        C.panel,
        alpha
    )

    outline(
        self.content_x,
        self.content_y,
        self.content_w,
        self.content_h,
        C.black,
        alpha
    )

    outline(
        self.content_x + 1,
        self.content_y + 1,
        self.content_w - 2,
        self.content_h - 2,
        C.frame_light,
        alpha
    )

    local tab =
        self.tabs[
            self.active_tab
        ]

    if tab == nil then
        return
    end

    for _, element in ipairs(
        tab.elements
    ) do

        if element.visible ~= false then

            if element.draw then

                element:draw(alpha)
            end
        end
    end
end

--==============================================================
-- CREATE FORM
--==============================================================

local form =
    Form:new(
        250,
        150,
        620,
        430
    )

--==============================================================
-- RAGE
--==============================================================

local rage =
    form:tab("rage")

rage:checkbox(
    "enable",
    false,
    0
)

rage:checkbox(
    "automatic fire",
    false,
    0
)

rage:checkbox(
    "automatic penetration",
    false,
    0
)

rage:dropdown(
    "target",
    {
        "nearest",
        "crosshair",
        "damage",
        "distance"
    },
    1,
    0
)

rage:slider(
    "minimum damage",
    0,
    130,
    20,
    1,
    "",
    1
)

rage:slider(
    "hitchance",
    0,
    100,
    50,
    1,
    "%",
    1
)

rage:keybind(
    "damage override",
    1
)

--==============================================================
-- ANTI-AIM
--==============================================================

local aa =
    form:tab("anti-aim")

aa:checkbox(
    "enable",
    false,
    0
)

aa:checkbox(
    "freestanding",
    false,
    0
)

aa:checkbox(
    "static freestand",
    false,
    0
)

aa:dropdown(
    "pitch",
    {
        "default",
        "up",
        "down",
        "zero"
    },
    1,
    0
)

aa:dropdown(
    "yaw",
    {
        "off",
        "180",
        "spin",
        "random"
    },
    1,
    1
)

aa:dropdown(
    "body yaw",
    {
        "off",
        "opposite",
        "static",
        "jitter"
    },
    1,
    1
)

aa:slider(
    "body yaw offset",
    -180,
    180,
    0,
    1,
    "°",
    1
)

aa:keybind(
    "freestanding key",
    0
)

--==============================================================
-- PLAYERS
--==============================================================

local players =
    form:tab("players")

players:checkbox(
    "player esp",
    false,
    0
)

players:checkbox(
    "health bar",
    false,
    0
)

players:checkbox(
    "name",
    true,
    0
)

players:multidropdown(
    "flags",
    {
        "money",
        "armor",
        "scoped",
        "flashed",
        "defusing"
    },
    1
)

players:dropdown(
    "box",
    {
        "off",
        "normal",
        "corner"
    },
    1,
    1
)

players:slider(
    "alpha",
    0,
    100,
    100,
    1,
    "%",
    1
)

--==============================================================
-- VISUALS
--==============================================================

local visuals =
    form:tab("visuals")

visuals:checkbox(
    "world esp",
    false,
    0
)

visuals:checkbox(
    "grenade prediction",
    false,
    0
)

visuals:checkbox(
    "bullet impacts",
    false,
    0
)

visuals:dropdown(
    "crosshair",
    {
        "default",
        "recoil",
        "spread"
    },
    1,
    1
)

visuals:slider(
    "viewmodel fov",
    60,
    120,
    90,
    1,
    "°",
    1
)

visuals:keybind(
    "thirdperson",
    1
)

--==============================================================
-- MISC
--==============================================================

local misc =
    form:tab("misc")

misc:checkbox(
    "bunny hop",
    false,
    0
)

misc:checkbox(
    "auto strafe",
    false,
    0
)

misc:checkbox(
    "fast stop",
    false,
    0
)

misc:dropdown(
    "strafe",
    {
        "off",
        "legit",
        "rage"
    },
    1,
    1
)

misc:keybind(
    "slow walk",
    1
)

misc:keybind(
    "fake duck",
    1
)

--==============================================================
-- CONFIG
--==============================================================

local config =
    form:tab("config")

config:dropdown(
    "configuration",
    {
        "default",
        "legit",
        "rage",
        "custom"
    },
    1,
    0
)

config:button(
    "load",
    0
)

config:button(
    "save",
    0
)

config:button(
    "reset",
    1
)

config:slider(
    "menu scale",
    80,
    120,
    100,
    1,
    "%",
    1
)

--==============================================================
-- FINALIZE
--==============================================================

form:update_geometry()

--==============================================================
-- GAME SENSE MENU SYNCHRONIZATION
--==============================================================

local last_dlc_state = false

local menu_alpha = 0

-- Скорость появления/исчезновения.
-- 20 = быстро и плавно.
-- 12 = медленнее.
-- 25 = очень быстро.
local MENU_ANIMATION_SPEED = 20

client.set_event_callback(
    "paint_ui",
    function()

        --------------------------------------------------------
        -- Получаем текущее состояние меню GameSense/DLC
        --------------------------------------------------------

        local gs_open =
            ui.is_menu_open()

        --------------------------------------------------------
        -- Определяем target alpha
        --------------------------------------------------------

        local target_alpha =
            gs_open
            and 1
            or 0

        --------------------------------------------------------
        -- Плавная анимация
        --------------------------------------------------------

        local speed =
            MENU_ANIMATION_SPEED *
            globals.frametime()

        if menu_alpha < target_alpha then

            menu_alpha =
                math.min(
                    menu_alpha + speed,
                    target_alpha
                )

        elseif menu_alpha > target_alpha then

            menu_alpha =
                math.max(
                    menu_alpha - speed,
                    target_alpha
                )
        end

        --------------------------------------------------------
        -- Передаём alpha в форму
        --------------------------------------------------------

        form.opacity =
            menu_alpha

        --------------------------------------------------------
        -- Открытие
        --------------------------------------------------------

        if gs_open then

            if not last_dlc_state then

                form.open = true

                form:update_geometry()
            end

            ----------------------------------------------------
            -- Input разрешён только когда GameSense открыт
            ----------------------------------------------------

            input:update()

            form:process()

            form:think()
        end

        --------------------------------------------------------
        -- Отрисовка
        --------------------------------------------------------

        if menu_alpha > 0 then

            form.open =
                gs_open

            form:draw()
        else

            form.open = false

            form.dragging = false

            form.active_element = nil
        end

        --------------------------------------------------------
        -- Сохраняем предыдущее состояние
        --------------------------------------------------------

        last_dlc_state =
            gs_open
    end
)

--==============================================================
-- EXPORT
--==============================================================

UI.form =
    form

UI.tabs =
    form.tabs

UI.Checkbox =
    Checkbox

UI.Slider =
    Slider

UI.Dropdown =
    Dropdown

UI.MultiDropdown =
    MultiDropdown

UI.Keybind =
    Keybind

UI.Button =
    Button
