ReaderFont = InputContainer:new{
	font_face = nil,
	font_size = nil,
	line_space_percent = 100,
	font_menu_title = "Font Menu",
	face_table = nil,
}

function ReaderFont:init()
	if not Device:hasNoKeyboard() then
		-- add shortcut for keyboard
		self.key_events = {
			ShowFontMenu = { {"F"}, doc = "show font menu" },
			IncreaseSize = { 
				{ "Shift", Input.group.PgFwd }, 
				doc = "increase font size", 
				event = "ChangeSize", args = "increase" },
			DecreaseSize = { 
				{ "Shift", Input.group.PgBack },
				doc = "decrease font size",
				event = "ChangeSize", args = "decrease" },
			IncreaseLineSpace = {
				{ "Alt", Input.group.PgFwd },
				doc = "increase line space",
				event = "ChangeLineSpace", args = "increase" },
			DecreaseLineSpace = {
				{ "Alt", Input.group.PgBack },
				doc = "decrease line space",
				event = "ChangeLineSpace", args = "decrease" },
		}
	end
	-- build face_table for menu
	self.face_table = {}
	local face_list = cre.getFontFaces()
	for k,v in ipairs(face_list) do
		table.insert(self.face_table, {
			text = v,
			callback = function()
				self:setFont(v)
			end
		})
		face_list[k] = {text = v}
	end
	self.ui.menu:registerToMainMenu(self)
end

function ReaderFont:onSetDimensions(dimen)
	self.dimen = dimen
end

function ReaderFont:onReadSettings(config)
	self.font_face = config:readSetting("font_face")
	if not self.font_face then 
		self.font_face = self.ui.document.default_font
	end
	self.ui.document:setFontFace(self.font_face)

	self.font_size = config:readSetting("font_size")
	if not self.font_size then 
		self.font_size = self.ui.document:getFontSize()
	end
	self.ui.document:setFontSize(self.font_size)
end

function ReaderFont:onShowFontMenu()
	-- build menu widget
	local main_menu = Menu:new{
		title = self.font_menu_title,
		item_table = self.face_table,
		width = Screen:getWidth() - 100,
	}
	function main_menu:onMenuChoice(item)
		if item.callback then
			item.callback()
		end
	end
	-- build container
	local menu_container = CenterContainer:new{
		main_menu,
		dimen = Screen:getSize(),
	}
	main_menu.close_callback = function () 
		UIManager:close(menu_container)
	end
	-- show menu
	UIManager:show(menu_container)
	return true
end

function ReaderFont:onChangeSize(direction)
	local delta = 1
	if direction == "decrease" then
	   delta = -1
	end
	self.font_size = self.font_size + delta
	msg = InfoMessage:new{text = direction.." font size to "..self.font_size}
	UIManager:show(msg)
	self.ui.document:zoomFont(delta)
	self.ui:handleEvent(Event:new("UpdatePos"))
	UIManager:close(msg)

	return true
end

function ReaderFont:onChangeLineSpace(direction)
	if direction == "decrease" then
		self.line_space_percent = self.line_space_percent - 10
		-- NuPogodi, 15.05.12: reduce lowest space_percent to 80
		self.line_space_percent = math.max(self.line_space_percent, 80)
	else
		self.line_space_percent = self.line_space_percent + 10
		self.line_space_percent = math.min(self.line_space_percent, 200)
	end
	msg = InfoMessage:new{"line spacing "..self.line_space_percent.."%"}
	self.ui.document:setInterlineSpacePercent(self.line_space_percent)
	self.ui:handleEvent(Event:new("UpdatePos"))

	return true
end

function ReaderFont:onCloseDocument()
	self.ui.doc_settings:saveSetting("font_face", self.font_face)
	self.ui.doc_settings:saveSetting("font_size", self.font_size)
end

function ReaderFont:setFont(face)
	if face and self.font_face ~= face then
		self.font_face = face
		msg = InfoMessage:new{ text = "Redrawing with "..face }
		UIManager:show(msg)

		self.ui.document:setFontFace(face)
		-- signal readerrolling to update pos in new height
		self.ui:handleEvent(Event:new("UpdatePos"))

		UIManager:close(msg)
	end
end

function ReaderFont:addToMainMenu(item_table)
	-- insert table to main reader menu
	table.insert(item_table, {
		text = self.font_menu_title,
		sub_item_table = self.face_table,
	})
end
