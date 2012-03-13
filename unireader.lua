require "keys"
require "settings"
require "selectmenu"

UniReader = {
	-- "constants":
	ZOOM_BY_VALUE = 0,
	ZOOM_FIT_TO_PAGE = -1,
	ZOOM_FIT_TO_PAGE_WIDTH = -2,
	ZOOM_FIT_TO_PAGE_HEIGHT = -3,
	ZOOM_FIT_TO_CONTENT = -4,
	ZOOM_FIT_TO_CONTENT_WIDTH = -5,
	ZOOM_FIT_TO_CONTENT_HEIGHT = -6,
	ZOOM_FIT_TO_CONTENT_WIDTH_PAN = -7,
	--ZOOM_FIT_TO_CONTENT_HEIGHT_PAN = -8,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN = -9,
	ZOOM_FIT_TO_CONTENT_HALF_WIDTH = -10,

	GAMMA_NO_GAMMA = 1.0,

	-- framebuffer update policy state:
	rcount = 5,
	rcountmax = 5,

	-- zoom state:
	globalzoom = 1.0,
	globalzoom_orig = 1.0,
	globalzoommode = -1, -- ZOOM_FIT_TO_PAGE

	globalrotate = 0,

	-- gamma setting:
	globalgamma = 1.0,   -- GAMMA_NO_GAMMA

	-- size of current page for current zoom level in pixels
	fullwidth = 0,
	fullheight = 0,
	offset_x = 0,
	offset_y = 0,
	min_offset_x = 0,
	min_offset_y = 0,
	content_top = 0, -- for ZOOM_FIT_TO_CONTENT_WIDTH_PAN (prevView)

	-- set panning distance
	shift_x = 100,
	shift_y = 50,
	pan_by_page = false, -- using shift_[xy] or width/height
	pan_x = 0, -- top-left offset of page when pan activated
	pan_y = 0,
	pan_margin = 20, -- horizontal margin for two-column zoom
	pan_overlap_vertical = 30,

	-- the document:
	doc = nil,
	-- the document's setting store:
	settings = nil,

	-- you have to initialize newDC, nulldc in specific reader
	newDC = function() return nil end,
	-- we will use this one often, so keep it "static":
	nulldc = nil, 

	-- tile cache configuration:
	cache_max_memsize = 1024*1024*5, -- 5MB tile cache
	cache_item_max_pixels = 1024*1024*2, -- max. size of rendered tiles
	cache_max_ttl = 20, -- time to live
	-- tile cache state:
	cache_current_memsize = 0,
	cache = {},

	pagehash = nil,

	jump_stack = {},
	toc = nil,

	bbox = {}, -- override getUsedBBox
}

function UniReader:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

--[[ 
	For a new specific reader,
	you must always overwrite following two methods:

	* self:init()
	* self:open()

	overwrite other methods if needed.
--]]
function UniReader:init()
	print("empty initialization method!")
end

-- open a file and its settings store
-- tips: you can use self:loadSettings in open() method.
function UniReader:open(filename, password)
	return false
end



--[ following are default methods ]--

function UniReader:loadSettings(filename)
	if self.doc ~= nil then
		self.settings = DocSettings:open(filename)

		local gamma = self.settings:readsetting("gamma")
		if gamma then
			self.globalgamma = gamma
		end

		local jumpstack = self.settings:readsetting("jumpstack")
		self.jump_stack = jumpstack or {}

		local bbox = self.settings:readsetting("bbox")
		print("# bbox loaded "..dump(bbox))
		self.bbox = bbox

		self.globalzoom = self.settings:readsetting("globalzoom") or 1.0
		self.globalzoommode = self.settings:readsetting("globalzoommode") or -1

		return true
	end
	return false
end

function UniReader:initGlobalSettings(settings)
	local pan_overlap_vertical = settings:readsetting("pan_overlap_vertical")
	if pan_overlap_vertical then
		self.pan_overlap_vertical = pan_overlap_vertical
	end

	local cache_max_memsize = settings:readsetting("cache_max_memsize")
	if cache_max_memsize then
		self.cache_max_memsize = cache_max_memsize
	end

	local cache_max_ttl = settings:readsetting("cache_max_ttl")
	if cache_max_ttl then
		self.cache_max_ttl = cache_max_ttl
	end
end

-- guarantee that we have enough memory in cache
function UniReader:cacheclaim(size)
	if(size > self.cache_max_memsize) then
		-- we're not allowed to claim this much at all
		error("too much memory claimed")
		return false
	end
	while self.cache_current_memsize + size > self.cache_max_memsize do
		-- repeat this until we have enough free memory
		for k, _ in pairs(self.cache) do
			if self.cache[k].ttl > 0 then
				-- reduce ttl
				self.cache[k].ttl = self.cache[k].ttl - 1
			else
				-- cache slot is at end of life, so kick it out
				self.cache_current_memsize = self.cache_current_memsize - self.cache[k].size
				self.cache[k] = nil
			end
		end
	end
	self.cache_current_memsize = self.cache_current_memsize + size
	return true
end

function UniReader:draworcache(no, preCache)
	-- our general caching strategy is as follows:
	-- #1 goal: we must render the needed area.
	-- #2 goal: we render as much of the requested page as we can
	-- #3 goal: we render the full page
	-- #4 goal: we render next page, too. (TODO)

	-- ideally, this should be factored out and only be called when needed (TODO)
	local page = self.doc:openPage(no)
	local dc = self:setzoom(page)

	-- offset_x_in_page & offset_y_in_page is the offset within zoomed page
	-- they are always positive. 
	-- you can see self.offset_x_& self.offset_y as the offset within 
	-- draw space, which includes the page. So it can be negative and positive.
	local offset_x_in_page = -self.offset_x
	local offset_y_in_page = -self.offset_y
	if offset_x_in_page < 0 then offset_x_in_page = 0 end
	if offset_y_in_page < 0 then offset_y_in_page = 0 end

	-- check if we have relevant cache contents
	local pagehash = no..'_'..self.globalzoom..'_'..self.globalrotate..'_'..self.globalgamma
	if self.cache[pagehash] ~= nil then
		-- we have something in cache, check if it contains the requested part
		if self.cache[pagehash].x <= offset_x_in_page
			and self.cache[pagehash].y <= offset_y_in_page
			and ( self.cache[pagehash].x + self.cache[pagehash].w >= offset_x_in_page + width
				or self.cache[pagehash].w >= self.fullwidth - 1)
			and ( self.cache[pagehash].y + self.cache[pagehash].h >= offset_y_in_page + height
				or self.cache[pagehash].h >= self.fullheight - 1)
		then
			-- requested part is within cached tile
			-- ...so properly clean page
			page:close()
			-- ...and give it more time to live (ttl), except if we're precaching
			if not preCache then
				self.cache[pagehash].ttl = self.cache_max_ttl
			end
			-- ...and return blitbuffer plus offset into it
			return pagehash,
				offset_x_in_page - self.cache[pagehash].x,
				offset_y_in_page - self.cache[pagehash].y
		end
	end
	-- okay, we do not have it in cache yet.
	-- so render now.
	-- start off with the requested area
	local tile = { x = offset_x_in_page, y = offset_y_in_page, 
					w = width, h = height }
	-- can we cache the full page?
	local max_cache = self.cache_max_memsize
	if preCache then
		max_cache = max_cache - self.cache[self.pagehash].size
	end
	if (self.fullwidth * self.fullheight / 2) <= max_cache then
		-- yes we can, so do this with offset 0, 0
		tile.x = 0
		tile.y = 0
		tile.w = self.fullwidth
		tile.h = self.fullheight
	elseif (tile.w*tile.h / 2) > max_cache then
		-- no, we can't. so generate a tile as big as we can go
		-- grow area in steps of 10px
		while ((tile.w+10) * (tile.h+10) / 2) < max_cache do
			if tile.x > 0 then
				tile.x = tile.x - 5
				tile.w = tile.w + 5
			end
			if tile.x + tile.w < self.fullwidth then
				tile.w = tile.w + 5
			end
			if tile.y > 0 then
				tile.y = tile.y - 5
				tile.h = tile.h + 5
			end
			if tile.y + tile.h < self.fullheigth then
				tile.h = tile.h + 5
			end
		end
	else
		if not preCache then
			print("E: not enough memory in cache left, probably a bug.")
		end
		return nil
	end
	self:cacheclaim(tile.w * tile.h / 2);
	self.cache[pagehash] = {
		x = tile.x,
		y = tile.y,
		w = tile.w,
		h = tile.h,
		ttl = self.cache_max_ttl,
		size = tile.w * tile.h / 2,
		bb = Blitbuffer.new(tile.w, tile.h)
	}
	--print ("# new biltbuffer:"..dump(self.cache[pagehash]))
	dc:setOffset(-tile.x, -tile.y)
	print("# rendering: page="..no)
	page:draw(dc, self.cache[pagehash].bb, 0, 0)
	page:close()

	-- return hash and offset within blitbuffer
	return pagehash,
		offset_x_in_page - tile.x,
		offset_y_in_page - tile.y
end

-- blank the cache
function UniReader:clearcache()
	self.cache = {}
	self.cache_current_memsize = 0
end

-- set viewer state according to zoom state
function UniReader:setzoom(page)
	local dc = self.newDC()
	local pwidth, pheight = page:getSize(self.nulldc)
	print("# page::getSize "..pwidth.."*"..pheight);
	local x0, y0, x1, y1 = page:getUsedBBox()
	if x0 == 0.01 and y0 == 0.01 and x1 == -0.01 and y1 == -0.01 then
		x0 = 0
		y0 = 0
		x1 = pwidth
		y1 = pheight
	end
	-- clamp to page BBox
	if x0 < 0 then x0 = 0 end
	if x1 > pwidth then x1 = pwidth end
	if y0 < 0 then y0 = 0 end
	if y1 > pheight then y1 = pheight end

	if self.bbox.enabled then
		print("# ORIGINAL page::getUsedBBox "..x0.."*"..y0.." "..x1.."*"..y1);
		local bbox = self.bbox[self.pageno] -- exact

		local odd_even = self:odd_even(self.pageno)
		if bbox ~= nil then
			print("## bbox from "..self.pageno)
		else
			bbox = self.bbox[odd_even] -- odd/even
		end
		if bbox ~= nil then -- last used up to this page
			print("## bbox from "..odd_even)
		else
			for i = 0,self.pageno do
				bbox = self.bbox[ self.pageno - i ]
				if bbox ~= nil then
					print("## bbox from "..self.pageno - i)
					break
				end
			end
		end
		if bbox ~= nil then
			x0 = bbox["x0"]
			y0 = bbox["y0"]
			x1 = bbox["x1"]
			y1 = bbox["y1"]
		end
	end

	print("# page::getUsedBBox "..x0.."*"..y0.." "..x1.."*"..y1);

	if self.globalzoommode == self.ZOOM_FIT_TO_PAGE
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		if height / pheight < self.globalzoom then
			self.globalzoom = height / pheight
			self.offset_x = (width - (self.globalzoom * pwidth)) / 2
			self.offset_y = 0
		end
		self.pan_by_page = false
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_WIDTH
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		self.globalzoom = width / pwidth
		self.offset_x = 0
		self.offset_y = (height - (self.globalzoom * pheight)) / 2
		self.pan_by_page = false
	elseif self.globalzoommode == self.ZOOM_FIT_TO_PAGE_HEIGHT
	or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		self.globalzoom = height / pheight
		self.offset_x = (width - (self.globalzoom * pwidth)) / 2
		self.offset_y = 0
		self.pan_by_page = false
	end

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
			if height / (y1 - y0) < self.globalzoom then
				self.globalzoom = height / (y1 - y0)
			end
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH then
		if (x1 - x0) < pwidth then
			self.globalzoom = width / (x1 - x0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
		self.content_top = self.offset_y
		-- enable pan mode in ZOOM_FIT_TO_CONTENT_WIDTH
		self.globalzoommode = self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.content_top == -2012 then
			-- We must handle previous page turn as a special cases,
			-- because we want to arrive at the bottom of previous page.
			-- Since this a real page turn, we need to recalcunate stuff.
			if (x1 - x0) < pwidth then
				self.globalzoom = width / (x1 - x0)
			end
			self.offset_x = -1 * x0 * self.globalzoom
			self.content_top = -1 * y0 * self.globalzoom
			self.offset_y = fb.bb:getHeight() - self.fullheight
		end
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HEIGHT then
		if (y1 - y0) < pheight then
			self.globalzoom = height / (y1 - y0)
		end
		self.offset_x = -1 * x0 * self.globalzoom
		self.offset_y = -1 * y0 * self.globalzoom
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH
		or self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN then
		local margin = self.pan_margin
		if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH then margin = 0 end
		self.globalzoom = width / (x1 - x0 + margin)
		self.offset_x = -1 * x0 * self.globalzoom * 2 + margin
		self.globalzoom = height / (y1 - y0)
		self.offset_y = -1 * y0 * self.globalzoom * 2 + margin
		self.globalzoom = width / (x1 - x0 + margin) * 2
		print("column mode offset:"..self.offset_x.."*"..self.offset_y.." zoom:"..self.globalzoom);
		self.globalzoommode = self.ZOOM_BY_VALUE -- enable pan mode
		self.pan_x = self.offset_x
		self.pan_y = self.offset_y
		self.pan_by_page = true
	end

	dc:setZoom(self.globalzoom)
	self.globalzoom_orig = self.globalzoom

	dc:setRotate(self.globalrotate);
	self.fullwidth, self.fullheight = page:getSize(dc)
	self.min_offset_x = fb.bb:getWidth() - self.fullwidth
	self.min_offset_y = fb.bb:getHeight() - self.fullheight
	if(self.min_offset_x > 0) then
		self.min_offset_x = 0
	end
	if(self.min_offset_y > 0) then
		self.min_offset_y = 0
	end

	print("# Reader:setzoom globalzoom:"..self.globalzoom.." globalrotate:"..self.globalrotate.." offset:"..self.offset_x.."*"..self.offset_y.." pagesize:"..self.fullwidth.."*"..self.fullheight.." min_offset:"..self.min_offset_x.."*"..self.min_offset_y)

	-- set gamma here, we don't have any other good place for this right now:
	if self.globalgamma ~= self.GAMMA_NO_GAMMA then
		print("gamma correction: "..self.globalgamma)
		dc:setGamma(self.globalgamma)
	end
	return dc
end

-- render and blit a page
function UniReader:show(no)
	local pagehash, offset_x, offset_y = self:draworcache(no)
	self.pagehash = pagehash
	local bb = self.cache[pagehash].bb
	local dest_x = 0
	local dest_y = 0
	if bb:getWidth() - offset_x < width then
		-- we can't fill the whole output width, center the content
		dest_x = (width - (bb:getWidth() - offset_x)) / 2
	end
	if bb:getHeight() - offset_y < height and 
	self.globalzoommode ~= self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		-- we can't fill the whole output height and not in 
		-- ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode, center the content
		dest_y = (height - (bb:getHeight() - offset_y)) / 2
	elseif self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN and
	self.offset_y > 0 then
		-- if we are in ZOOM_FIT_TO_CONTENT_WIDTH_PAN mode and turning to
		-- the top of the page, we might leave an empty space between the 
		-- page top and screen top.
		dest_y = self.offset_y
	end
	if dest_x or dest_y then
		fb.bb:paintRect(0, 0, width, height, 8)
	end
	print("# blitFrom dest_off:("..dest_x..", "..dest_y..
		"), src_off:("..offset_x..", "..offset_y.."), "..
		"width:"..width..", height:"..height)
	fb.bb:blitFrom(bb, dest_x, dest_y, offset_x, offset_y, width, height)
	if self.rcount == self.rcountmax then
		print("full refresh")
		self.rcount = 1
		fb:refresh(0)
	else
		print("partial refresh")
		self.rcount = self.rcount + 1
		fb:refresh(1)
	end
	self.slot_visible = slot;
end

--[[
	@ pageno is the page you want to add to jump_stack
--]]
function UniReader:add_jump(pageno, notes)
	local jump_item = nil
	local notes_to_add = notes 
	if not notes_to_add then
		-- no notes given, auto generate from TOC entry
		notes_to_add = self:getTOCTitleByPage(self.pageno)
		if notes_to_add ~= "" then
			notes_to_add = "in "..notes_to_add
		end
	end
	-- move pageno page to jump_stack top if already in
	for _t,_v in ipairs(self.jump_stack) do
		if _v.page == pageno then
			jump_item = _v
			table.remove(self.jump_stack, _t)
			-- if original notes is not empty, probably defined by users,
			-- we use the original notes to overwrite auto generated notes
			-- from TOC entry
			if jump_item.notes ~= "" then
				notes_to_add = jump_item.notes
			end
			jump_item.notes = notes or notes_to_add
			break
		end
	end
	-- create a new one if page not found in stack
	if not jump_item then
		jump_item = {
			page = pageno,
			datetime = os.date("%Y-%m-%d %H:%M:%S"),
			notes = notes_to_add,
		}
	end

	-- insert item at the start
	table.insert(self.jump_stack, 1, jump_item)

	if #self.jump_stack > 10 then
		-- remove the last element to keep the size less than 10
		table.remove(self.jump_stack)
	end
end

function UniReader:del_jump(pageno)
	for _t,_v in ipairs(self.jump_stack) do
		if _v.page == pageno then
			table.remove(self.jump_stack, _t)
		end
	end
end

-- change current page and cache next page after rendering
function UniReader:goto(no)
	if no < 1 or no > self.doc:getPages() then
		return
	end

	-- for jump_stack, distinguish jump from normal page turn
	if self.pageno and math.abs(self.pageno - no) > 1 then
		self:add_jump(self.pageno)
	end

	self.pageno = no
	self:show(no)

	-- TODO: move the following to a more appropriate place
	-- into the caching section
	if no < self.doc:getPages() then
		if #self.bbox == 0 or not self.bbox.enabled then
			-- pre-cache next page, but if we will modify bbox don't!
			self:draworcache(no+1, true)
		end
	end
end

function UniReader:nextView()
	local pageno = self.pageno

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y <= self.min_offset_y then
			-- hit content bottom, turn to next page
			self.globalzoommode = self.ZOOM_FIT_TO_CONTENT_WIDTH
			pageno = pageno + 1
		else
			-- goto next view of current page
			self.offset_y = self.offset_y - height + self.pan_overlap_vertical
		end
	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno + 1
		if self.pan_by_page then
			-- we are in two column mode
			self.offset_x = self.pan_x
			self.offset_y = self.pan_y
		end
	end

	return pageno
end

function UniReader:prevView()
	local pageno = self.pageno

	if self.globalzoommode == self.ZOOM_FIT_TO_CONTENT_WIDTH_PAN then
		if self.offset_y >= self.content_top then
			-- hit content top, turn to previous page
			-- set self.content_top with magic num to signal self:setzoom 
			self.content_top = -2012
			pageno = pageno - 1
		else
			-- goto previous view of current page
			self.offset_y = self.offset_y + height - self.pan_overlap_vertical
		end
	else
		-- not in fit to content width pan mode, just do a page turn
		pageno = pageno - 1
		if self.pan_by_page then
			-- we are in two column mode
			self.offset_x = self.pan_x
			self.offset_y = self.pan_y
		end
	end

	return pageno
end

-- adjust global gamma setting
function UniReader:modify_gamma(factor)
	print("modify_gamma, gamma="..self.globalgamma.." factor="..factor)
	self.globalgamma = self.globalgamma * factor;
	self:goto(self.pageno)
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoommode(newzoommode)
	if self.globalzoommode ~= newzoommode then
		self.globalzoommode = newzoommode
		self:goto(self.pageno)
	end
end

-- adjust zoom state and trigger re-rendering
function UniReader:setglobalzoom(zoom)
	if self.globalzoom ~= zoom then
		self.globalzoommode = self.ZOOM_BY_VALUE
		self.globalzoom = zoom
		self:goto(self.pageno)
	end
end

function UniReader:setrotate(rotate)
	self.globalrotate = rotate
	self:goto(self.pageno)
end

-- @ orien: 1 for clockwise rotate, -1 for anti-clockwise
function UniReader:screenRotate(orien)
	Screen:screenRotate(orien)
	width, height = fb:getSize()
	self:clearcache()
	self:goto(self.pageno)
end

function UniReader:cleanUpTOCTitle(title)
	return title:gsub("\13", "")
end

function UniReader:fillTOC()
	self.toc = self.doc:getTOC()
end

function UniReader:getTOCTitleByPage(pageno)
	if not self.toc then
		-- build toc when needed.
		self:fillTOC()
	end

	-- no table of content
	if #self.toc == 0 then
		return ""
	end
	
	local pre_entry = self.toc[1]
	for _k,_v in ipairs(self.toc) do
		if _v.page > pageno then
			break
		end
		pre_entry = _v
	end
	return self:cleanUpTOCTitle(pre_entry.title)
end

function UniReader:showTOC()
	if not self.toc then
		-- build toc when needed.
		self:fillTOC()
	end
	local menu_items = {}
	local filtered_toc = {}
	local curr_page = -1
	-- build menu items
	for _k,_v in ipairs(self.toc) do
		if(_v.page >= curr_page) then
			table.insert(menu_items,
			("        "):rep(_v.depth-1)..self:cleanUpTOCTitle(_v.title))
			table.insert(filtered_toc,_v.page)
			curr_page = _v.page
		end
	end
	toc_menu = SelectMenu:new{
		menu_title = "Table of Contents",
		item_array = menu_items,
		no_item_msg = "This document does not have a Table of Contents.",
	}
	item_no = toc_menu:choose(0, fb.bb:getHeight())
	if item_no then
		self:goto(filtered_toc[item_no])
	else
		self:goto(self.pageno)
	end
end

function UniReader:showJumpStack()
	local menu_items = {}
	for _k,_v in ipairs(self.jump_stack) do
		table.insert(menu_items, 
			_v.datetime.." -> Page ".._v.page.." ".._v.notes)
	end
	jump_menu = SelectMenu:new{
		menu_title = "Jump Keeper      (current page: "..self.pageno..")", 
		item_array = menu_items,
		no_item_msg = "No jump history.",
	}
	item_no = jump_menu:choose(0, fb.bb:getHeight())
	if item_no then
		local jump_item = self.jump_stack[item_no]
		self:goto(jump_item.page)
	else
		self:goto(self.pageno)
	end
end

function UniReader:showMenu()
	local ypos = height - 50
	local load_percent = (self.pageno / self.doc:getPages())

	fb.bb:paintRect(0, ypos, width, 50, 0)

	ypos = ypos + 15
	local face, fhash = Font:getFaceAndHash(22)
	local cur_section = self:getTOCTitleByPage(self.pageno)
	if cur_section ~= "" then
		cur_section = "Section: "..cur_section
	end
	renderUtf8Text(fb.bb, 10, ypos+6, face, fhash,
		"Page: "..self.pageno.."/"..self.doc:getPages()..
		"    "..cur_section, true)

	ypos = ypos + 15
	blitbuffer.progressBar(fb.bb, 10, ypos, width-20, 15, 
							5, 4, load_percent, 8)
	fb:refresh(1)
	while 1 do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			if ev.code == KEY_BACK or ev.code == KEY_MENU then
				return
			end
		end
	end
end

function UniReader:odd_even(number)
	print("## odd_even "..number)
	if number % 2 == 1 then
		return "odd"
	else
		return "even"
	end
end

-- wait for input and handle it
function UniReader:inputloop()
	local keep_running = true
	while 1 do
		local ev = input.waitForEvent()
		ev.code = adjustKeyEvents(ev)
		if ev.type == EV_KEY and ev.value == EVENT_VALUE_KEY_PRESS then
			local secs, usecs = util.gettime()
			if ev.code == KEY_PGFWD or ev.code == KEY_LPGFWD then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom+self.globalzoom_orig*0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom+self.globalzoom_orig*0.1)
				else
					-- turn page forward
					local pageno = self:nextView()
					self:goto(pageno)
				end
			elseif ev.code == KEY_PGBCK or ev.code == KEY_LPGBCK then
				if Keys.shiftmode then
					self:setglobalzoom(self.globalzoom-self.globalzoom_orig*0.2)
				elseif Keys.altmode then
					self:setglobalzoom(self.globalzoom-self.globalzoom_orig*0.1)
				else
					-- turn page back
					local pageno = self:prevView()
					self:goto(pageno)
				end
			elseif ev.code == KEY_BACK then
				if Keys.altmode then
					-- altmode, exit reader
					break
				else
					-- not altmode, back to last jump
					if #self.jump_stack ~= 0 then
						self:goto(self.jump_stack[1].page)
					end
				end
			elseif ev.code == KEY_VPLUS then
				self:modify_gamma( 1.25 )
			elseif ev.code == KEY_VMINUS then
				self:modify_gamma( 0.8 )
			elseif ev.code == KEY_1 then
				self:goto(1)
			elseif ev.code >= KEY_2 and ev.code <= KEY_9 then
				self:goto(math.floor(self.doc:getPages()/90*(ev.code-KEY_1)*10))
			elseif ev.code == KEY_0 then
				self:goto(self.doc:getPages())						
			elseif ev.code == KEY_A then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE)
				end
			elseif ev.code == KEY_S then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_WIDTH)
				end
			elseif ev.code == KEY_D then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HEIGHT)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_PAGE_HEIGHT)
				end
			elseif ev.code == KEY_F then
				if Keys.shiftmode then
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH)
				else
					self:setglobalzoommode(self.ZOOM_FIT_TO_CONTENT_HALF_WIDTH_MARGIN)
				end
			elseif ev.code == KEY_G then
				local page = InputBox:input(height-100, 100, "Page:")
				-- convert string to number
				if not pcall(function () page = page + 0 end) then
					page = self.pageno
				else
					if page < 1 or page > self.doc:getPages() then
						page = self.pageno
					end
				end
				self:goto(page)
			elseif ev.code == KEY_T then
				self:showTOC()
			elseif ev.code == KEY_B then
				if Keys.shiftmode then
					self:add_jump(self.pageno)
				else
					self:showJumpStack()
				end
			elseif ev.code == KEY_J then
				if Keys.shiftmode then
					self:screenRotate("clockwise")
				else
					self:setrotate( self.globalrotate + 10 )
				end
			elseif ev.code == KEY_K then
				if Keys.shiftmode then
					self:screenRotate("anticlockwise")
				else
					self:setrotate( self.globalrotate - 10 )
				end
			elseif ev.code == KEY_HOME then
				if Keys.shiftmode or Keys.altmode then
					-- signal quit
					keep_running = false
				end
				break
			elseif ev.code == KEY_Z and not (Keys.shiftmode or Keys.altmode) then
				local bbox = {}
				bbox["x0"] = - self.offset_x / self.globalzoom
				bbox["y0"] = - self.offset_y / self.globalzoom
				bbox["x1"] = bbox["x0"] + width / self.globalzoom
				bbox["y1"] = bbox["y0"] + height / self.globalzoom
				bbox.pan_x = self.pan_x
				bbox.pan_y = self.pan_y
				self.bbox[self.pageno] = bbox
				self.bbox[self:odd_even(self.pageno)] = bbox
				self.bbox.enabled = true
				print("# bbox " .. self.pageno .. dump(self.bbox)) 
				self.globalzoommode = self.ZOOM_FIT_TO_CONTENT -- use bbox
			elseif ev.code == KEY_Z and Keys.shiftmode then
				self.bbox[self.pageno] = nil;
				print("# bbox remove "..self.pageno .. dump(self.bbox));
			elseif ev.code == KEY_Z and Keys.altmode then
				self.bbox.enabled = not self.bbox.enabled;
				print("# bbox override: ", self.bbox.enabled);
			elseif ev.code == KEY_MENU then
				self:showMenu()
				self:goto(self.pageno)
			end

			-- switch to ZOOM_BY_VALUE to enable panning on fiveway move
			if ev.code == KEY_FW_LEFT
			or ev.code == KEY_FW_RIGHT
			or ev.code == KEY_FW_UP
			or ev.code == KEY_FW_DOWN
			then
				self.globalzoommode = self.ZOOM_BY_VALUE
			end

			if self.globalzoommode == self.ZOOM_BY_VALUE then
				local x
				local y

				if Keys.shiftmode then -- shift always moves in small steps
					x = self.shift_x / 2
					y = self.shift_y / 2
				elseif Keys.altmode then
					x = self.shift_x / 5
					y = self.shift_y / 5
				elseif self.pan_by_page then
					x = width;
					y = height - self.pan_overlap_vertical; -- overlap for lines which didn't fit
				else
					x = self.shift_x
					y = self.shift_y
				end

				print("offset "..self.offset_x.."*"..self.offset_x.." shift "..x.."*"..y.." globalzoom="..self.globalzoom)
				local old_offset_x = self.offset_x
				local old_offset_y = self.offset_y

				if ev.code == KEY_FW_LEFT then
					print("# KEY_FW_LEFT "..self.offset_x.." + "..x.." > 0");
					self.offset_x = self.offset_x + x
					if self.pan_by_page then
						if self.offset_x > 0 and self.pageno > 1 then
							self.offset_x = self.pan_x
							self.offset_y = self.min_offset_y -- bottom
							self:goto(self.pageno - 1)
						else
							self.offset_y = self.min_offset_y
						end
					elseif self.offset_x > 0 then
						self.offset_x = 0
					end
				elseif ev.code == KEY_FW_RIGHT then
					print("# KEY_FW_RIGHT "..self.offset_x.." - "..x.." < "..self.min_offset_x.." - "..self.pan_margin);
					self.offset_x = self.offset_x - x
					if self.pan_by_page then
						if self.offset_x < self.min_offset_x - self.pan_margin and self.pageno < self.doc:getPages() then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
							self:goto(self.pageno + 1)
						else
							self.offset_y = self.pan_y
						end
					elseif self.offset_x < self.min_offset_x then
						self.offset_x = self.min_offset_x
					end
				elseif ev.code == KEY_FW_UP then
					self.offset_y = self.offset_y + y
					if self.offset_y > 0 then
						self.offset_y = 0
					end
				elseif ev.code == KEY_FW_DOWN then
					self.offset_y = self.offset_y - y
					if self.offset_y < self.min_offset_y then
						self.offset_y = self.min_offset_y
					end
				elseif ev.code == KEY_FW_PRESS then
					if Keys.shiftmode then
						if self.pan_by_page then
							self.offset_x = self.pan_x
							self.offset_y = self.pan_y
						else
							self.offset_x = 0
							self.offset_y = 0
						end
					else
						self.pan_by_page = not self.pan_by_page
						if self.pan_by_page then
							self.pan_x = self.offset_x
							self.pan_y = self.offset_y
						end
					end
				end
				if old_offset_x ~= self.offset_x
				or old_offset_y ~= self.offset_y then
						self:goto(self.pageno)
				end
			end

			local nsecs, nusecs = util.gettime()
			local dur = (nsecs - secs) * 1000000 + nusecs - usecs
			print("E: T="..ev.type.." V="..ev.value.." C="..ev.code.." DUR="..dur)
		end
	end

	-- do clean up stuff
	self:clearcache()
	self.toc = nil
	if self.doc ~= nil then
		self.doc:close()
	end
	if self.settings ~= nil then
		self.settings:savesetting("last_page", self.pageno)
		self.settings:savesetting("gamma", self.globalgamma)
		self.settings:savesetting("jumpstack", self.jump_stack)
		self.settings:savesetting("bbox", self.bbox)
		self.settings:savesetting("globalzoom", self.globalzoom)
		self.settings:savesetting("globalzoommode", self.globalzoommode)
		self.settings:close()
	end

	return keep_running
end
