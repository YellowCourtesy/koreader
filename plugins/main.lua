local Device = require("device")

if not (Device:isKindle() and Device:hasLightSensor()) then
    return { disabled = true, }
end

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local PluginShare = require("pluginshare")
if PluginShare.backgroundJobs == nil then PluginShare.backgroundJobs = {} end
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local AutoFrontlight = {
  settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/autofrontlight.lua"),
  settings_id = 0,
  enabled = false,
  last_brightness = -1,
}

function AutoFrontlight:_schedule(settings_id)
    local enabled = function()
        if not self.enabled then
            logger.dbg("AutoFrontlight:_schedule() is disabled")
            return false
        end
        if settings_id ~= self.settings_id then
            logger.dbg("AutoFrontlight:_schedule(): registered settings_id ",
                       settings_id,
                       " does not equal to current one ",
                       self.settings_id)
            return false
        end

        return true
    end

    table.insert(PluginShare.backgroundJobs, {
        when = 10,
        repeated = enabled,
        executable = function()
            if enabled() then
                self:_action()
            end
        end
    })
    local Event = require("ui/event")
    UIManager:broadcastEvent(Event:new("BackgroundJobsUpdated"))
end

function AutoFrontlight:_action()
    local current_level = Device:ambientBrightnessLevel()
    if self.last_brightness == current_level then return end
    logger.dbg("AutoFrontlight: ambient bucket ", current_level)

    local powerd = Device:getPowerDevice()
    local max = powerd.fl_max or 24
    local min = powerd.fl_min or 0

    -- Map ambient bucket 0..4 to a frontlight intensity.
    -- 0 = darkest environment → highest frontlight
    -- 4 = brightest environment → frontlight off
    local map = {
       [0] = 10,  -- darkest: full brightness within your useful range
       [1] = 6,
       [2] = 2,
       [3] = 0,
       [4] = min, -- brightest: off
    }
    local target = map[current_level]
    if target == nil then return end

    if target <= min then
        powerd:turnOffFrontlight()
    else
        if not powerd:isFrontlightOn() then
            powerd:turnOnFrontlight()
        end
        powerd:setIntensity(target)
    end
    self.last_brightness = current_level
end

function AutoFrontlight:init()
    self.enabled = self.settings:nilOrTrue("enable")
    self.settings_id = self.settings_id + 1
    logger.dbg("AutoFrontlight:init() self.enabled: ", self.enabled, " with id ", self.settings_id)
    self:_schedule(self.settings_id)
end

function AutoFrontlight:flipSetting()
    self.settings:flipNilOrTrue("enable")
    self:init()
end

function AutoFrontlight:onFlushSettings()
    self.settings:flush()
end

AutoFrontlight:init()

local AutoFrontlightWidget = WidgetContainer:extend{
    name = "autofrontlight",
}

function AutoFrontlightWidget:init()
    -- self.ui and self.ui.menu are nil in unittests.
    if self.ui ~= nil and self.ui.menu ~= nil then
        self.ui.menu:registerToMainMenu(self)
    end
end

function AutoFrontlightWidget:flipSetting()
    AutoFrontlight:flipSetting()
end

-- For test only.
function AutoFrontlightWidget:deprecateLastTask()
    logger.dbg("AutoFrontlightWidget:deprecateLastTask() @ ", AutoFrontlight.settings_id)
    AutoFrontlight.settings_id = AutoFrontlight.settings_id + 1
end

function AutoFrontlightWidget:addToMainMenu(menu_items)
    menu_items.auto_frontlight = {
        text = _("Auto frontlight"),
        callback = function(touchmenu_instance)
            UIManager:show(ConfirmBox:new{
                text = T(_("Auto frontlight detects the brightness of the environment and automatically turn on and off the frontlight.\nFrontlight will be turned off to save battery in bright environment, and turned on in dark environment.\nDo you want to %1 it?"),
                         AutoFrontlight.enabled and _("disable") or _("enable")),
                ok_text = AutoFrontlight.enabled and _("Disable") or _("Enable"),
                ok_callback = function()
                    self:flipSetting()
                    touchmenu_instance:updateItems()
                end
            })
        end,
        checked_func = function() return AutoFrontlight.enabled end,
    }
end

function AutoFrontlightWidget:onFlushSettings()
    AutoFrontlight:onFlushSettings()
end

return AutoFrontlightWidget
