require "rendertext"
require "keys"
require "graphics"
require "font"
require "inputbox"
require "dialog"
require "settings"

FileInfo = {
	title_H = 40,	-- title height
	spacing = 36,	-- spacing between lines
	foot_H = 28,	-- foot height
	margin_H = 10,	-- horisontal margin
	-- state buffer
	pagedirty = true,
	result = {},
	commands = nil,
	items = 0,
	pathfile = "",
}

function FileInfo:FileCreated(fname, attr)
	return os.date("%d %b %Y, %H:%M:%S", lfs.attributes(fname,attr))
end

function FileInfo:FormatSize(size)
	if size < 1024 then
		return size.." Bytes"
	elseif size < 2^20 then
		return string.format("%.2f", size/2^10).."KB ("..size.." Bytes)"
	elseif size < 2^30 then
		return string.format("%.2f", size/2^20).."MB ("..size.." Bytes)"
	else
		return string.format("%.2f", size/2^30).."GB ("..size.." Bytes)"
	end
end

function getUnpackedZipSize(zipfile)
	-- adding quotes allows us to avoid crash on zips which filename contains space(s)
	local cmd='unzip -l \"'..zipfile..'\" | tail -1 | sed -e "s/^ *\\([0-9][0-9]*\\) *.*/\\1/"'
	local p = assert(io.popen(cmd, "r"))
	local res = assert(p:read("*a"))
	p:close()
	res = string.gsub(res, "[\n\r]+", "")
	return tonumber(res)
end

function getDiskSizeInfo()
	local s = {}
	local tmp = assert(io.popen('df /mnt/us/ | tail -1', "r"))
	local output = assert(tmp:read("*line"))
	for w in string.gmatch(output, "%d+") do 
		s[#s+1] = tonumber(w)*1024 -- to return in bytes
	end
	tmp:close()
	if #s < 3 then return nil end
	return { total = s[1], used = s[2], free = s[3] }
end

function FileInfo:formatDiskSizeInfo()
	local s = getDiskSizeInfo()
	if s then 
		return self:FormatSize(s.free)..string.format(", %.2f", 100*s.free/s.total).."%" 
	end
	return "?"
end

function FileInfo:getFolderContent()
	InfoMessage:show("Scanning folder...", 1)
	local tmp = assert(io.popen('du -a \"'..self.pathfile..'\"', "r"))
	local dirs, files, books, size, name, output, ftype, j = -1, 0, 0, 0
	while true do
		output = tmp:read("*line")
		if not output then break end
		j = output:find("/")
		name = output:sub(j, -1)
		size = tonumber(output:sub(1, j-1)) -- in kB
		j = lfs.attributes(name, "mode")
		if j == "file" then 
			files = files + 1
			ftype = string.match(name, ".+%.([^.]+)")
			if ftype and ext:getReader(ftype) then
				books = books + 1
			end
		elseif j == "directory" then
			dirs = dirs + 1
		end
	end
	tmp:close()
	-- add 2 entries; might be joined / splitted
	table.insert(self.result, {dir = "Contents", name = dirs.." sub-folder(s) / "..files.." file(s) / "..books.." book(s)"})
	table.insert(self.result, {dir = "Size", name = self:FormatSize(size*1024)})
end

function FileInfo:init(path, fname)
	-- add commands only once
	if not self.commands then
		self:addAllCommands()
	end

	if fname then
		self.pathfile = path.."/"..fname
		table.insert(self.result, {dir = "Name", name = fname} )
		self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
			"open document",
			function(self)
				openFile(self.pathfile)
				self.pagedirty = true
			end)
	else
		self.pathfile = path.."/"
		-- extracting folder name
		local i, j = 0, 0
		while true do
			i = string.find(path, "/", i+1)
			if i == nil then break else j=i end
		end
		table.insert(self.result, {dir = "Name", name = path:sub(j+1,-1) } )
		table.insert(self.result, {dir = "Path", name = path:sub(1,j) } )
		self.commands:add({KEY_ENTER, KEY_FW_PRESS}, nil, "Enter",
			"goto folder",
			function(self)
				return "goto"
			end)
	end

	local tmp, output
	if fname then -- file info
		table.insert(self.result, {dir = "Path", name = path.."/"} )
		table.insert(self.result, {dir = "Size", name = self:FormatSize(lfs.attributes(self.pathfile, "size"))} )
		-- total size of all unzipped entries for zips 
		local match = string.match(fname, ".+%.([^.]+)")
		if match and string.lower(match) == "zip" then
			table.insert(self.result, {dir = "Unpacked", name = self:FormatSize(getUnpackedZipSize(self.pathfile))} )
		end
	else -- folder info
		self:getFolderContent()
	end

	table.insert(self.result, {dir = "Free space", name = self:formatDiskSizeInfo()})
	table.insert(self.result, {dir = "Status changed", name = self:FileCreated(self.pathfile, "change")})
	table.insert(self.result, {dir = "Modified", name = self:FileCreated(self.pathfile, "modification")})
	table.insert(self.result, {dir = "Accessed", name = self:FileCreated(self.pathfile, "access")})

	if fname then
		-- if the document was already opened
		local history = DocToHistory(self.pathfile)
		local file, msg = io.open(history, "r")
		if not file then 
			table.insert(self.result, {dir = "Last read", name = "Never"})
		else
			table.insert(self.result, {dir = "Last read", name = self:FileCreated(history, "change")})
			local file_type = string.lower(string.match(self.pathfile, ".+%.([^.]+)"))
			local to_search, add, factor = "[\"last_percent\"]", "%", 100
			if ext:getReader(file_type) ~= CREReader then
				to_search = "[\"last_page\"]"
				add = " pages"
				factor = 1
			end
			for line in io.lines(history) do
				if string.match(line, "%b[]") == to_search then
					local cdc = tonumber(string.match(line, "%d+")) / factor
					table.insert(self.result, {dir = "Completed", name = string.format("%d", cdc)..add })
				end
			end
		end
	end
	self.items = #self.result
end

function FileInfo:show(path, name)
	-- at first, one has to test whether the file still exists or not: necessary for last documents
	if name and not io.open(path.."/"..name,"r") then return nil end
	-- then goto main functions
	self:init(path,name)
	-- local variables
	local cface, lface, tface, fface, width, xrcol, c, dy, ev, keydef, ret_code
	while true do
		if self.pagedirty then
			-- refresh the fonts, if not yet defined or updated via 'F'
			cface = Font:getFace("cfont", 22)
			lface = Font:getFace("tfont", 22)
			tface = Font:getFace("tfont", 25)
			fface = Font:getFace("ffont", 16)
			-- drawing
			fb.bb:paintRect(0, 0, G_width, G_height, 0)
			DrawTitle(name and "Document Information" or "Folder Information", self.margin_H, 0, self.title_H, 3, tface)
			-- now calculating xrcol-position for the right column
			width = 0
			for c = 1, self.items do
				width = math.max(sizeUtf8Text(0, G_width, lface, self.result[c].dir, true).x, width)
			end
			xrcol = self.margin_H + width + 25
			dy = 5 -- to store the y-position correction 'cause of the multiline drawing
			for c = 1, self.items do
				y = self.title_H + self.spacing * c + dy
				renderUtf8Text(fb.bb, self.margin_H, y, lface, self.result[c].dir, true)
				dy = dy + renderUtf8Multiline(fb.bb, xrcol, y, cface, self.result[c].name, true,
						G_width - self.margin_H - xrcol, 1.65).y - y
			end
			fb:refresh(0)
			self.pagedirty = false
		end
		-- waiting for user's commands
		ev = input.saveWaitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value ~= EVENT_VALUE_KEY_RELEASE then
			keydef = Keydef:new(ev.code, getKeyModifier())
			command = self.commands:getByKeydef(keydef)
			if command ~= nil then ret_code = command.func(self, keydef) end
			if ret_code == "break" or ret_code == "goto" then break end
		end -- if ev.type
	end -- while true
	self.pagedirty = true
	self.result = {}
	return ret_code
end

function FileInfo:addAllCommands()
	self.commands = Commands:new{}
	self.commands:add({KEY_SPACE}, nil, "Space",
		"refresh page manually",
		function(self)
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_H,nil,"H",
		"show help page",
		function(self)
			HelpPage:show(0, G_height, self.commands)
			self.pagedirty = true
		end
	)
	self.commands:add({KEY_F, KEY_AA}, nil, "F",
		"change font faces",
		function(self)
			Font:chooseFonts()
			self.pagedirty = true
		end
	)
	self.commands:add(KEY_L, nil, "L",
		"last documents",
		function(self)
			FileHistory:init()
			FileHistory:choose("")
			self.pagedirty = true
		end
	) 
	self.commands:add({KEY_BACK, KEY_FW_LEFT}, nil, "Back",
		"back",
		function(self)
			return "break"
		end
	)
end
