require "rendertext"
require "keys"
require "graphics"
require "font"

FileSearcher = {
	-- title height
	title_H = 45,
	-- spacing between lines
	spacing = 40,
	-- foot height
	foot_H = 27,

	-- state buffer
	dirs = {},
	files = {},
	result = {},
	items = 0,
	page = 0,
	current = 1,
	oldcurrent = 1,
}

function FileSearcher:readDir()
	self.dirs = {self.path}
	self.files = {}
	while #self.dirs ~= 0 do
		new_dirs = {}
		-- handle each dir
		for __, d in pairs(self.dirs) do
			-- handle files in d
			for f in lfs.dir(d) do
				local file_type = string.lower(string.match(f, ".+%.([^.]+)") or "")
				if lfs.attributes(d.."/"..f, "mode") == "directory"
				and f ~= "." and f~= ".." and not string.match(f, "^%.[^.]") then
					table.insert(new_dirs, d.."/"..f)
				elseif file_type == "djvu" or file_type == "pdf" 
				or file_type == "xps" or file_type == "cbz" 
				or file_type == "epub" or file_type == "txt"
				or file_type == "rtf" or file_type == "htm"
				or file_type == "html"
				or file_type == "fb2" or file_type == "chm" then
					file_entry = {dir=d, name=f,}
					table.insert(self.files, file_entry)
					--print("file:"..d.."/"..f)
				end
			end
		end
		self.dirs = new_dirs
	end
end

function FileSearcher:setPath(newPath)
	self.path = newPath
	self:readDir()
	self.items = #self.files
	--@TODO check none found  19.02 2012
	if self.items == 0 then
		return nil
	end
	self.page = 1
	self.current = 1
	return true
end

function FileSearcher:setSearchResult(keywords)
	self.result = {}
	if keywords == " " then -- one space to show all files
		self.result = self.files
	else
		for __,f in pairs(self.files) do
			if string.find(string.lower(f.name), keywords) then
				table.insert(self.result, f)
			end
		end
	end
	self.items = #self.result
	self.page = 1
	self.current = 1
end

function FileSearcher:init(search_path)
	if search_path then
		self:setPath(search_path)
	else
		self:setPath("/mnt/us/documents")
	end
	self:addAllCommands()
end

function FileSearcher:prevItem()
	if self.current == 1 then
		if self.page > 1 then
			self.current = self.perpage
			self.page = self.page - 1
			self.pagedirty = true
		end
	else
		self.current = self.current - 1
		self.markerdirty = true
	end
end

function FileSearcher:nextItem()
	if self.current == self.perpage then
		if self.page < (self.items / self.perpage) then
			self.current = 1
			self.page = self.page + 1
			self.pagedirty = true
		end
	else
		if self.page ~= math.floor(self.items / self.perpage) + 1
			or self.current + (self.page-1)*self.perpage < self.items then
			self.current = self.current + 1
			self.markerdirty = true
		end
	end
end

function FileSearcher:addAllCommands()
	self.commands = Commands:new{}

	self.commands:add(KEY_FW_UP, nil, "joypad up",
		"goto previous item",
		function(self)
			self:prevItem()
		end
	)
	self.commands:add(KEY_FW_DOWN, nil, "joypad down",
		"goto next item",
		function(self)
			self:nextItem()
		end
	)
	self.commands:add(KEY_PGFWD, nil, ">",
		"next page",
		function(self)
			if self.page < (self.items / self.perpage) then
				if self.current + self.page*self.perpage > self.items then
					self.current = self.items - self.page*self.perpage
				end
				self.page = self.page + 1
				self.pagedirty = true
			else
				self.current = self.items - (self.page-1)*self.perpage
				self.markerdirty = true
			end
		end
	)
	self.commands:add(KEY_PGBCK, nil, "<",
		"previous page",
		function(self)
			if self.page > 1 then
				self.page = self.page - 1
				self.pagedirty = true
			else
				self.current = 1
				self.markerdirty = true
			end
		end
	)
	self.commands:add(KEY_S, nil, "S",
		"invoke search inputbox",
		function(self)
			old_keywords = keywords
			keywords = InputBox:input(height-100, 100, "Search:", old_keywords)
			if keywords then
				self:setSearchResult(keywords)
			else
				keywords = old_keywords
			end
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_F, nil, "F",
		"font menu",
		function(self)
			fonts_menu = SelectMenu:new{
				menu_title = "Fonts Menu",
				item_array = Font.fonts,
			}
			local re = fonts_menu:choose(0, height)
			if re then
				Font.cfont = Font.fonts[re]
				Font:update()
			end
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "",
		"select item",
		function(self)
			file_entry = self.result[self.perpage*(self.page-1)+self.current]
			file_full_path = file_entry.dir .. "/" .. file_entry.name

			-- rotation mode might be changed while reading, so
			-- record height_percent here
			local height_percent = height/fb.bb:getHeight()
			openFile(file_full_path)

			--reset height and item index if screen has been rotated
			local item_no = self.perpage * (self.page - 1) + self.current
			self.perpage = math.floor(height / self.spacing) - 2
			self.current = item_no % self.perpage
			self.page = math.floor(item_no / self.perpage) + 1

			self.pagedirty = true
		end
	)
	self.commands:add({KEY_BACK, KEY_HOME}, nil, "",
		"back to file browser",
		function(self)
			return "break"
		end
	)
end

function FileSearcher:choose(keywords)
	self.perpage = math.floor(height / self.spacing) - 2
	self.pagedirty = true
	self.markerdirty = false


	-- if given keywords, set new result according to keywords.
	-- Otherwise, display the previous search result.
	if keywords then
		self:setSearchResult(keywords)
	end

	while true do
		local cface, cfhash = Font:getFaceAndHash(22)
		local tface, tfhash = Font:getFaceAndHash(25, Font.tfont)
		local fface, ffhash = Font:getFaceAndHash(16, Font.ffont)

		if self.pagedirty then
			self.markerdirty = true
			fb.bb:paintRect(0, 0, width, height, 0)

			-- draw menu title
			renderUtf8Text(fb.bb, 30, 0 + self.title_H, tface, tfhash,
				"Search Result for: "..keywords, true)

			-- draw results
			local c
			if self.items == 0 then -- nothing found
				y = self.title_H + self.spacing * 2
				renderUtf8Text(fb.bb, 20, y, cface, cfhash,
					"Sorry, no match found.", true)
				renderUtf8Text(fb.bb, 20, y + self.spacing, cface, cfhash,
					"Please try a different keyword.", true)
				self.markerdirty = false
			else -- found something, draw it
				for c = 1, self.perpage do
					local i = (self.page - 1) * self.perpage + c
					if i <= self.items then
						y = self.title_H + (self.spacing * c)
						renderUtf8Text(fb.bb, 50, y, cface, cfhash,
							self.result[i].name, true)
					end
				end
			end

			-- draw footer
			y = self.title_H + (self.spacing * self.perpage) + self.foot_H
			x = (width / 2) - 50
			all_page = (math.floor(self.items / self.perpage)+1)
			renderUtf8Text(fb.bb, x, y, fface, ffhash,
				"Page "..self.page.." of "..all_page, true)
		end

		if self.markerdirty then
			if not self.pagedirty then
				if self.oldcurrent > 0 then
					y = self.title_H + (self.spacing * self.oldcurrent) + 10
					fb.bb:paintRect(30, y, width - 60, 3, 0)
					fb:refresh(1, 30, y, width - 60, 3)
				end
			end
			-- draw new marker line
			y = self.title_H + (self.spacing * self.current) + 10
			fb.bb:paintRect(30, y, width - 60, 3, 15)
			if not self.pagedirty then
				fb:refresh(1, 30, y, width - 60, 3)
			end
			self.oldcurrent = self.current
			self.markerdirty = false
		end

		if self.pagedirty then
			fb:refresh(0, 0, 0, width, height)
			self.pagedirty = false
		end

		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			keydef = Keydef:new(ev.code, getKeyModifier())
			print("key pressed: "..tostring(keydef))

			command = self.commands:getByKeydef(keydef)
			if command ~= nil then
				print("command to execute: "..tostring(command))
				ret_code = command.func(self, keydef)
			else
				print("command not found: "..tostring(command))
			end

			if ret_code == "break" then
				break
			end

			if self.selected_item ~= nil then
				print("# selected "..self.selected_item)
				return self.selected_item
			end
		end -- EOF if
	end -- EOF while
	return nil
end
