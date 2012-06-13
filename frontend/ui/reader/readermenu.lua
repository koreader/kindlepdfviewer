ReaderMenu = InputContainer:new{
	key_events = {
		ShowMenu = { { "Menu" }, doc = "show menu" },
	},
}

function ReaderMenu:onShowMenu()
	local item_table = {}

	table.insert(item_table, {
		text = "Screen rotate",
		sub_item_table = {
			{
				text = "rotate 90 degree clockwise",
				callback = function()
					Screen:screenRotate("clockwise")
					self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
				end
			},
			{
				text = "rotate 90 degree anticlockwise",
				callback = function()
					Screen:screenRotate("anticlockwise")
					self.ui:handleEvent(Event:new("SetDimensions", Screen:getSize()))
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
				},
				{
					text = "Zoom to fit content height",
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
		text = "Return to file browser"
	})

	local main_menu = Menu:new{
		title = "Document menu",
		item_table = item_table,
		width = 300,
		height = #item_table + 3 * 28
	}

	function main_menu:onMenuChoice(item)
		if item.callback then
			item.callback()
		end
	end

	UIManager:show(main_menu)

	return true
end
