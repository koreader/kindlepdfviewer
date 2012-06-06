require "cache"
require "ui/geometry"

CreDocument = Document:new{
	_document = false,
	line_space_percent = 100,
	--dc_null = DrawContext.new()
}

-- NuPogodi, 20.05.12: inspect the zipfile content
function CreDocument:zipContentExt(fname)
	local outfile = "./data/zip_content"
	local s = ""
	os.execute("unzip ".."-l \""..fname.."\" > "..outfile)
	local i = 1
	if io.open(outfile,"r") then
		for lines in io.lines(outfile) do
			if i == 4 then s = lines break else i = i + 1 end
		end
	end
	-- return the extention
	return string.lower(string.match(s, ".+%.([^.]+)"))
end

function CreDocument:init()
	-- we need to initialize the CRE font list
	local fonts = Font:getFontList()
	for _k, _v in ipairs(fonts) do
		local ok, err = pcall(cre.registerFont, Font.fontdir..'/'.._v)
		if not ok then
			DEBUG(err)
		end
	end

	--local default_font = G_reader_settings:readSetting("cre_font")
	--if default_font then
		--self.default_font = default_font
	--end

	local ok
	local file_type = string.lower(string.match(self.file, ".+%.([^.]+)"))
	if file_type == "zip" then
		-- NuPogodi, 20.05.12: read the content of zip-file
		-- and return extention of the 1st file
		file_type = self:zipContentExt(filename)
	end
	-- these two format use the same css file
	if file_type == "html" then
		file_type = "htm"
	end
	-- if native css-file doesn't exist, one needs to use default cr3.css
	if not io.open("./data/"..file_type..".css") then
		file_type = "cr3"
	end
	local style_sheet = "./data/"..file_type..".css"

	ok, self._document = pcall(cre.openDocument, self.file, style_sheet,
								G_width, G_height)
	if not ok then
		self.error_message = self.doc -- will contain error message
		return
	end
	self.is_open = true
	self.info.has_pages = false
	self:_readMetadata()

	self._document:setDefaultInterlineSpace(self.line_space_percent)
end

function CreDocument:hintPage(pageno, zoom, rotation)
end

function CreDocument:drawPage(target, x, y, rect, pageno, zoom, rotation)
end

function CreDocument:renderPage(pageno, rect, zoom, rotation)
end

DocumentRegistry:addProvider("txt", "application/txt", CreDocument)
