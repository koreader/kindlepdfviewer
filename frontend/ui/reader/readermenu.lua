ReaderMenu = InputContainer:new{}

function ReaderMenu:init()
	if Device:isTouchDevice() then
		self.ges_events = {
			TapShowMenu = {
				GestureRange:new{
					ges = "tap",
					range = Geom:new{
						x = 0, y = 0,
						w = Screen:getWidth(),
						h = Screen:getHeight()/2
					}
				}
			},
		}
	else
		self.key_events = {
			ShowMenu = { { "Menu" }, doc = "show menu" },
		}
	end
end

function ReaderMenu:genSetZoomModeCallBack(mode)
	return function()
		self.ui:handleEvent(Event:new("SetZoomMode", mode))
	end
end

function ReaderMenu:onShowMenu()
	local item_table = {}

	table.insert(item_table, {
		text = "Screen rotate",
		sub_item_table = {
			{
				text = "rotate 90 degree clockwise",
				callback = function()
					Screen:screenRotate("clockwise")
					self.ui:handleEvent(
						Event:new("SetDimensions", Screen:getSize()))
				end
			},
			{
				text = "rotate 90 degree anticlockwise",
				callback = function()
					Screen:screenRotate("anticlockwise")
					self.ui:handleEvent(
						Event:new("SetDimensions", Screen:getSize()))
				end
			},
		}
	})

	if self.ui.document.info.has_pages then
		table.insert(item_table, {
			text = "Switch zoom mode",
			sub_item_table = {
				{
					text = "Zoom to fit content width",
					callback = self:genSetZoomModeCallBack("contentwidth")
				},
				{
					text = "Zoom to fit content height",
					callback = self:genSetZoomModeCallBack("contentheight")
				},
				{
					text = "Zoom to fit page width",
					callback = self:genSetZoomModeCallBack("pagewidth")
				},
				{
					text = "Zoom to fit page height",
					callback = self:genSetZoomModeCallBack("pageheight")
				},
				{
					text = "Zoom to fit content",
					callback = self:genSetZoomModeCallBack("content")
				},
				{
					text = "Zoom to fit page",
					callback = self:genSetZoomModeCallBack("page")
				},
			}
		})
	else
		table.insert(item_table, {
			text = "Font menu",
			callback = function()
				self.ui:handleEvent(Event:new("ShowFontMenu"))
			end
		})
	end

	table.insert(item_table, {
		text = "Return to file browser",
		callback = function()
			UIManager:close(self.menu_container)
			self.ui:onClose()
		end
	})

	local main_menu = Menu:new{
		title = "Document menu",
		item_table = item_table,
		width = Screen:getWidth() - 100,
	}
	function main_menu:onMenuChoice(item)
		if item.callback then
			item.callback()
		end
	end

	local menu_container = CenterContainer:new{
		main_menu,
		dimen = Screen:getSize(),
	}
	main_menu.close_callback = function () 
		UIManager:close(menu_container)
	end
	-- maintain a reference to menu_container
	self.menu_container = menu_container

	UIManager:show(menu_container)

	return true
end

function ReaderMenu:onTapShowMenu()
	self:onShowMenu()
	return true
end

function ReaderMenu:onSetDimensions(dimen)
	-- update gesture listenning range according to new screen orientation
	self:init()
end

