#!./kpdfview
--[[
    KindlePDFViewer: a reader implementation
    Copyright (C) 2011 Hans-Werner Hilse <hilse@web.de>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--
require "alt_getopt"
require "pdfreader"
require "djvureader"
require "crereader"
require "filechooser"
require "settings"
require "screen"
require "keys"
require "commands"
require "dialog"
require "extentions"

-- option parsing:
longopts = {
	password = "p",
	goto = "g",
	gamma = "G",
	debug = "d",
	help = "h"
}

function openFile(filename)
	local file_type = string.lower(string.match(filename, ".+%.([^.]+)"))
	local reader = nil

	reader = ext:getReader(file_type)
	if reader then
		InfoMessage:show("Opening document, please wait... ", 0)
		reader:preLoadSettings(filename)
		local ok, err = reader:open(filename)
		if ok then
			reader:loadSettings(filename)
			page_num = reader:getLastPageOrPos()
			reader:goto(tonumber(page_num), true)
			G_reader_settings:saveSetting("lastfile", filename)
			return reader:inputLoop()
		else
			InfoMessage:show(err or "Error opening document.", 0)
			util.sleep(2)
		end
	end
	return true -- on failed attempts, we signal to keep running
end

function showusage()
	print("usage: ./reader.lua [OPTION] ... path")
	print("Read PDFs and DJVUs on your E-Ink reader")
	print("")
	print("-p, --password=PASSWORD   set password for reading PDF document")
	print("-g, --goto=page           start reading on page")
	print("-G, --gamma=GAMMA         set gamma correction")
	print("-d, --debug               start in debug mode")
	print("                          (floating point notation, e.g. \"1.5\")")
	print("-h, --help                show this usage help")
	print("")
	print("If you give the name of a directory instead of a file path, a file")
	print("chooser will show up and let you select a PDF|DJVU file")
	print("")
	print("If you don't pass any path, the last viewed document will be opened")
	print("")
	print("This software is licensed under the GPLv3.")
	print("See http://github.com/hwhw/kindlepdfviewer for more info.")
	return
end

optarg, optind = alt_getopt.get_opts(ARGV, "p:g:G:hg:dg:", longopts)
if optarg["h"] then
	return showusage()
end

if not optarg["d"] then
	debug = function() end
end

if optarg["G"] ~= nil then
	globalgamma = optarg["G"]
end

if util.isEmulated()==1 then
	input.open("")
	-- SDL key codes
	setEmuKeycodes()
else
	input.open("slider")
	input.open("/dev/input/event0")
	input.open("/dev/input/event1")

	-- check if we are running on Kindle 3 (additional volume input)
	local f=lfs.attributes("/dev/input/event2")
	if f then
		print("Auto-detected Kindle 3")
		input.open("/dev/input/event2")
		setK3Keycodes()
	end
end

G_screen_saver_mode = false
G_charging_mode = false
fb = einkfb.open("/dev/fb0")
G_width, G_height = fb:getSize()
-- read current rotation mode
Screen:updateRotationMode()
Screen.native_rotation_mode = Screen.cur_rotation_mode

-- set up reader's setting: font
G_reader_settings = DocSettings:open(".reader")
fontmap = G_reader_settings:readSetting("fontmap")
if fontmap ~= nil then
	Font.fontmap = fontmap
end

-- initialize global settings shared among all readers
UniReader:initGlobalSettings(G_reader_settings)
-- initialize specific readers
PDFReader:init()
DJVUReader:init()
CREReader:init()

-- display directory or open file
local patharg = G_reader_settings:readSetting("lastfile")
if ARGV[optind] and lfs.attributes(ARGV[optind], "mode") == "directory" then
	local running = true
	FileChooser:setPath(ARGV[optind])
	while running do
		local file, callback = FileChooser:choose(0, G_height)
		if callback then
			callback()
		else
			if file ~= nil then
				running = openFile(file)
				print(file)
			else
				running = false
			end
		end
	end
elseif ARGV[optind] and lfs.attributes(ARGV[optind], "mode") == "file" then
	openFile(ARGV[optind], optarg["p"])
elseif patharg and lfs.attributes(patharg, "mode") == "file" then
	openFile(patharg, optarg["p"])
else
	return showusage()
end


-- save reader settings
G_reader_settings:saveSetting("fontmap", Font.fontmap)
G_reader_settings:close()

-- @TODO dirty workaround, find a way to force native system poll
-- screen orientation and upside down mode 09.03 2012
fb:setOrientation(Screen.native_rotation_mode)

input.closeAll()
if util.isEmulated()==0 then
	os.execute("killall -cont cvm")
	os.execute('echo "send '..KEY_MENU..'" > /proc/keypad;echo "send '..KEY_MENU..'" > /proc/keypad')
end
