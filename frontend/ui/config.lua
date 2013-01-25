require "ui/widget"
require "ui/focusmanager"
require "ui/infomessage"
require "ui/font"

FixedTextWidget = TextWidget:new{}
function FixedTextWidget:getSize()
	local tsize = sizeUtf8Text(0, Screen:getWidth(), self.face, self.text, true)
	if not tsize then
		return Geom:new{}
	end
	self._length = tsize.x
	self._height = self.face.size
	return Geom:new{
		w = self._length,
		h = self._height,
	}
end

function FixedTextWidget:paintTo(bb, x, y)
	renderUtf8Text(bb, x, y+self._height, self.face, self.text, true)
end

MenuBarItem = InputContainer:new{}
function MenuBarItem:init()
	self.dimen = self[1]:getSize()
	-- we need this table per-instance, so we declare it here
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Select Menu Item",
			},
		}
	else
		self.active_key_events = {
			Select = { {"Press"}, doc = "chose selected item" },
		}
	end
end

function MenuBarItem:onTapSelect()
	self[1].invert = true
	self.config:onShowConfigPanel(self.index)
	UIManager:scheduleIn(0.5, function() self:invert(false) end)
	return true
end

function MenuBarItem:invert(invert)
	self[1].invert = invert
	UIManager:setDirty(self.config, "partial")
end

OptionTextItem = InputContainer:new{}
function OptionTextItem:init()
	local text_widget = self[1]
	self.dimen = text_widget:getSize()
	self[1] = UnderlineContainer:new{
		text_widget,
		padding = self.padding,
		color = self.color,
		}
	-- we need this table per-instance, so we declare it here
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Select Option Item",
			},
		}
	else
		self.active_key_events = {
			Select = { {"Press"}, doc = "chose selected item" },
		}
	end
end

function OptionTextItem:onTapSelect()
	for _, item in pairs(self.items) do
		item[1].color = 0
	end
	self[1].color = 15
	local option_value = nil
	local option_arg = nil
	if type(self.values) == "table" then
		option_value = self.values[self.current_item]
		self.config:onConfigChoice(self.name, option_value, self.event)
	elseif type(self.args) == "table" then
		option_arg = self.args[self.current_item]
		self.config:onConfigChoice(self.name, option_arg, self.event)
	end
	UIManager.repaint_all = true
	return true
end

--[[
Dummy Widget that reserves vertical and horizontal space
]]
RectSpan = Widget:new{
	width = 0,
	hright = 0,
}

function RectSpan:getSize()
	return {w = self.width, h = self.height}
end

ToggleLabel = TextWidget:new{}
function ToggleLabel:paintTo(bb, x, y)
	if self.color == 0 then
		return
	end
	renderUtf8Text(bb, x, y+self._height*0.75, self.face, self.text, true)
end

ToggleSwitch = InputContainer:new{}
function ToggleSwitch:init()
	self.n_pos = #self.toggle
	if self.n_pos ~= 2 and self.n_pos ~= 3 then
		-- currently only support options with two or three items.
		error("items number not supported")
	end
	self.position = nil
	
	local label_font_face = "cfont"
	local label_font_size = math.floor(20*Screen:getWidth()/600)
	
	self.toggle_frame = FrameContainer:new{background = 0, color = 7, radius = 7, bordersize = 1, padding = 2,}
	self.toggle_content = HorizontalGroup:new{}
	
	self.left_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.toggle[self.n_pos],
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.left_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.left_label,
	}
	self.middle_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.n_pos > 2 and self.toggle[2] or "",
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.middle_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.middle_label,
	}
	self.right_label = ToggleLabel:new{
		align = "center",
		color = 0,
		text = self.toggle[1],
		face = Font:getFace(label_font_face, label_font_size),
	}
	self.right_button = FrameContainer:new{
		background = 0,
		color = 7,
		margin = 0,
		radius = 5,
		bordersize = 1,
		padding = 2,
		self.right_label,
	}
	
	table.insert(self.toggle_content, self.left_button)
  	table.insert(self.toggle_content, self.middle_button)
  	table.insert(self.toggle_content, self.right_button)
  	
	self.toggle_frame[1] = self.toggle_content
	self[1] = self.toggle_frame
	self.dimen = Geom:new(self.toggle_frame:getSize())
	if Device:isTouchDevice() then
		self.ges_events = {
			TapSelect = {
				GestureRange:new{
					ges = "tap",
					range = self.dimen,
				},
				doc = "Toggle switch",
			},
		}
	end
end

function ToggleSwitch:onGesture(ev)
	for name, gsseq in pairs(self.ges_events) do
		for _, gs_range in ipairs(gsseq) do
			--DEBUG("gs_range", gs_range)
			if gs_range:match(ev) then
				local eventname = gsseq.event or name
				local position = math.ceil((ev.pos.x-gs_range.range.x)/gs_range.range.w*self.n_pos)
				return self:handleEvent(Event:new(eventname, position))
			end
		end
	end
end

function ToggleSwitch:update()
	local left_pos = self.position == 1
	local right_pos = self.position == self.n_pos
	local middle_pos = not left_pos and not right_pos
	self.left_label.color = right_pos and 15 or 0
	self.left_button.color = left_pos and 7 or 0
	self.left_button.background = left_pos and 7 or 0
	self.middle_label.color = middle_pos and 15 or 0
	self.middle_button.color = middle_pos and 0 or 0
	self.middle_button.background = middle_pos and 0 or 0
	self.right_label.color = left_pos and 15 or 0
	self.right_button.color = right_pos and 7 or 0
	self.right_button.background = right_pos and 7 or 0
end

function ToggleSwitch:setPosition(position)
	self.position = position
	self:update()
end

function ToggleSwitch:togglePosition(position)
	if self.n_pos == 2 then
		self.position = (self.position+1)%self.n_pos
		self.position = self.position == 0 and self.n_pos or self.position
	else
		self.position = position
	end
	self:update()
end

function ToggleSwitch:onTapSelect(position)
	DEBUG("toggle position:", position)
	self:togglePosition(position)
	local option_value = nil
	local option_arg = nil
	if type(self.values) == "table" then
		option_value = self.values[self.position]
		self.config:onConfigChoice(self.name, option_value, self.event)
	elseif type(self.args) == "table" then
		option_arg = self.args[self.position]
		self.config:onConfigChoice(self.name, option_arg, self.event)
	end
	UIManager.repaint_all = true
end

ConfigOption = CenterContainer:new{}
function ConfigOption:init()
	local default_name_font_size = math.floor(20*Screen:getWidth()/600)
	local default_item_font_size = math.floor(20*Screen:getWidth()/600)
	local default_items_spacing = math.floor(30*Screen:getWidth()/600)
	local default_option_height = math.floor(50*Screen:getWidth()/600)
	local default_option_padding = math.floor(30*Screen:getWidth()/600)
	local vertical_group = VerticalGroup:new{}
	table.insert(vertical_group, VerticalSpan:new{ width = default_option_padding })
	for c = 1, #self.options do
		if self.options[c].show ~= false then
			local name_align = self.options[c].name_align_right and self.options[c].name_align_right or 0.33
			local item_align = self.options[c].item_align_center and self.options[c].item_align_center or 0.66
			local name_font_face = self.options[c].name_font_face and self.options[c].name_font_face or "tfont"
			local name_font_size = self.options[c].name_font_size and self.options[c].name_font_size or default_name_font_size
			local item_font_face = self.options[c].item_font_face and self.options[c].item_font_face or "cfont"
			local item_font_size = self.options[c].item_font_size and self.options[c].item_font_size or default_item_font_size
			local option_height = self.options[c].height and self.options[c].height or default_option_height
			local items_spacing = HorizontalSpan:new{ width = self.options[c].spacing and self.options[c].spacing or default_items_spacing}
			
			local horizontal_group = HorizontalGroup:new{}
			if self.options[c].name_text then
				local option_name_container = RightContainer:new{
					dimen = Geom:new{ w = Screen:getWidth()*name_align, h = option_height},
				}
				local option_name =	TextWidget:new{
						text = self.options[c].name_text,
						face = Font:getFace(name_font_face, name_font_size),
				}
				table.insert(option_name_container, option_name)
				table.insert(horizontal_group, option_name_container)
			end
			
			if self.options[c].widget == "ProgressWidget" then
				local widget_container = CenterContainer:new{
					dimen = Geom:new{w = Screen:getWidth()*self.options[c].widget_align_center, h = option_height}
				}
				local widget = ProgressWidget:new{
					width = self.options[c].width,
					height = self.options[c].height,
					percentage = self.options[c].percentage,
				}
				table.insert(widget_container, widget)
				table.insert(horizontal_group, widget_container)
			end
			
			local option_items_container = CenterContainer:new{
				dimen = Geom:new{w = Screen:getWidth()*item_align, h = option_height}
			}
			local option_items_group = HorizontalGroup:new{}
			local option_items_fixed = false
			local option_items = {}
			if type(self.options[c].item_font_size) == "table" then
				option_items_group.align = "bottom"
				option_items_fixed = true
			end
			-- make current index according to configurable table
			local current_item = nil
			if self.options[c].name then
				if self.options[c].values then
					local val = self.config.configurable[self.options[c].name]
					local min_diff = math.abs(val - self.options[c].values[1])
					local diff = nil
					for index, val_ in pairs(self.options[c].values) do
						if val == val_ then
							current_item = index
							break
						end
						diff = math.abs(val - val_)
						if diff <= min_diff then
							min_diff = diff
							current_item = index
						end
					end
				elseif self.options[c].args then
					local arg = self.config.configurable[self.options[c].name]
					for idx, arg_ in pairs(self.options[c].args) do
						if arg_ == arg then
							current_item = idx
							break
						end
					end
				end
			end
			
			if self.options[c].item_text then
				for d = 1, #self.options[c].item_text do
					local option_item = nil
					if option_items_fixed then
						option_item = OptionTextItem:new{
							FixedTextWidget:new{
								text = self.options[c].item_text[d],
								face = Font:getFace(item_font_face, item_font_size[d]),
							},
							padding = 3,
							color = d == current_item and 15 or 0,
						}
					else
						option_item = OptionTextItem:new{
							TextWidget:new{
								text = self.options[c].item_text[d],
								face = Font:getFace(item_font_face, item_font_size),
							},
							padding = -3,
							color = d == current_item and 15 or 0,
						}
					end
					option_items[d] = option_item
					option_item.items = option_items
					option_item.name = self.options[c].name
					option_item.values = self.options[c].values
					option_item.args = self.options[c].args
					option_item.event = self.options[c].event
					option_item.current_item = d
					option_item.config = self.config
					table.insert(option_items_group, option_item)
					if d ~= #self.options[c].item_text then
						table.insert(option_items_group, items_spacing)
					end
				end
			end
			
			if self.options[c].toggle then
				local switch = ToggleSwitch:new{
					name = self.options[c].name,
					toggle = self.options[c].toggle,
					values = self.options[c].values,
					args = self.options[c].args,
					event = self.options[c].event,
					config = self.config,
				}
				local position = current_item
				switch:setPosition(position)
				table.insert(option_items_group, switch)
			end
			
			table.insert(option_items_container, option_items_group)
			table.insert(horizontal_group, option_items_container)
			table.insert(vertical_group, horizontal_group)
		end -- if
	end -- for
	table.insert(vertical_group, VerticalSpan:new{ width = default_option_padding })
	self[1] = vertical_group
	self.dimen = vertical_group:getSize()
end

ConfigPanel = FrameContainer:new{ background = 0, bordersize = 0, }
function ConfigPanel:init()
	local config_options = self.config_dialog.config_options
	local default_option = config_options.default_options and config_options.default_options 
							or config_options[1].options
	local panel = ConfigOption:new{
		options = self.index and config_options[self.index].options or default_option,
		config = self.config_dialog,
	}
	self.dimen = panel:getSize()
	table.insert(self, panel)
end

MenuBar = FrameContainer:new{ background = 0, }
function MenuBar:init()
	local config_options = self.config_dialog.config_options
	local menu_items = {}
	local icons_width = 0
	local icons_height = 0
	for c = 1, #config_options do
		local menu_icon = ImageWidget:new{
			file = config_options[c].icon
		}
		local icon_dimen = menu_icon:getSize()
		icons_width = icons_width + icon_dimen.w
		icons_height = icon_dimen.h > icons_height and icon_dimen.h or icons_height
		
		menu_items[c] = MenuBarItem:new{
			menu_icon,
			index = c,
			config = self.config_dialog,
		}
	end
	
	local spacing = HorizontalSpan:new{
		width = (Screen:getWidth() - icons_width) / (#menu_items+1)
	}
	
	local menu_bar = HorizontalGroup:new{}
	
	for c = 1, #menu_items do
		table.insert(menu_bar, spacing)
		table.insert(menu_bar, menu_items[c])
	end
	table.insert(menu_bar, spacing)
	
	self.dimen = Geom:new{ w = Screen:getWidth(), h = icons_height}
	table.insert(self, menu_bar)
end

--[[
Widget that displays config menubar and config panel

 +----------------+
 |                |
 |                |
 |                |
 |                |
 |                |
 +----------------+
 |                |
 |  Config Panel  |
 |                |
 +----------------+
 |    Menu Bar    |
 +----------------+
 
--]]

ConfigDialog = InputContainer:new{
	--is_borderless = false,
}

function ConfigDialog:init()
	------------------------------------------
	-- start to set up widget layout ---------
	------------------------------------------
	self.config_panel = ConfigPanel:new{
		config_dialog = self,
	}
	self.config_menubar = MenuBar:new{ 
		config_dialog = self,
	}
	self:makeDialog()
	------------------------------------------
	-- start to set up input event callback --
	------------------------------------------
	if Device:isTouchDevice() then
		self.ges_events.TapCloseMenu = {
			GestureRange:new{
				ges = "tap",
				range = Geom:new{
					x = 0, y = 0,
					w = Screen:getWidth(),
					h = Screen:getHeight(),
				}
			}
		}
	else
		-- set up keyboard events
		self.key_events.Close = { {"Back"}, doc = "close config menu" }
		-- we won't catch presses to "Right"
		self.key_events.FocusRight = nil
	end
	self.key_events.Select = { {"Press"}, doc = "select current menu item"}
	
	UIManager:setDirty(self, "partial")
end

function ConfigDialog:updateConfigPanel(index)
	self.config_panel = ConfigPanel:new{
		index = index,
		config_dialog = self,
	}
end

function ConfigDialog:makeDialog()
	local dialog = VerticalGroup:new{
		self.config_panel,
		self.config_menubar,
	}
	
	local dialog_size = dialog:getSize()
	
	self[1] = BottomContainer:new{
		dimen = Screen:getSize(),
		FrameContainer:new{
			dimen = dialog_size,
			background = 0,
			dialog,
		}
	}
	
	self.dialog_dimen = Geom:new{
		x = (Screen:getWidth() - dialog_size.w)/2,
		y = Screen:getHeight() - dialog_size.h,
		w = dialog_size.w,
		h = dialog_size.h,
	}	
end

function ConfigDialog:onShowConfigPanel(index)
	self:updateConfigPanel(index)
	self:makeDialog()
	UIManager.repaint_all = true
	return true
end

function ConfigDialog:onCloseMenu()
	UIManager:close(self)
	if self.close_callback then
		self.close_callback()
	end
	return true
end

function ConfigDialog:onTapCloseMenu(arg, ges_ev)
	if ges_ev.pos:notIntersectWith(self.dialog_dimen) then
		self:onCloseMenu()
		return true
	end
end
