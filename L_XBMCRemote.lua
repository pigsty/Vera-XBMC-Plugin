module("L_XBMCRemote", package.seeall)
_VERSION = "0.0.2"
_COPYRIGHT = ""

local dkjson = require("L_XBMCRemote_dkjson")

local ipAddress
local json_http_port
local json_tcp_port
local ping_interval
local serviceid = "urn:upnp-org:serviceId:XBMC1"
local deviceid = lul_device
	
local DEBUG_MODE = true

local DEFAULT_XBMC_TCP_PORT = 9090
local DEFAULT_XBMC_HTTP_PORT = 80
local DEFAULT_PING_TIME = 18

local SOON = 5

local taskHandle = -1
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1


local function log(stuff, level)
	luup.log("XBMC: " .. stuff, (level or 50))
end

local function debug(stuff)
	if (DEBUG_MODE) then
		log("debug " .. stuff, 1)
	end
end

-- From the NEST plugin
local function task(text, mode)
  local mode = mode or TASK_ERROR
  if (mode ~= TASK_SUCCESS) then
	log("task: " .. text, 50)
  end
  taskHandle = luup.task(text, (mode == TASK_ERROR_PERM) and TASK_ERROR or mode, MSG_CLASS, taskHandle)
end

-- From the NEST plugin
local function readVariableOrInit(lul_device, serviceId, name, defaultValue) 
  local var = luup.variable_get(serviceId, name, lul_device)
  if (var == nil) then
	var = defaultValue
	luup.variable_set(serviceId, name, var, lul_device)
	log("Initialized variable: '" .. name .. "' = '" .. var .. "' SID is " .. serviceId )
  end
  return var
end

-- From the NEST plugin
local function writeVariable(lul_device, serviceId, name, value) 
  luup.variable_set(serviceId, name, value, lul_device)
end

-- Originally from the NEST plugin
local function writeVariableIfChanged(lul_device, serviceId, name, value)
  local curValue = luup.variable_get(serviceId, name, lul_device)
  
  -- convert to strings as numeric comparison of floats was hit
  -- and miss to say the least
  
  if (tostring(value) ~= tostring(curValue)) then
	writeVariable(lul_device, serviceId, name, value)
	log("Changed variable: '" .. name .. "' = '" .. value .. "' SID is " .. serviceId )
	return true
  else
	return false
  end
end

-- From http://lua-users.org/wiki/StringRecipes
function string.starts(String,Start)
	return string.sub(String,1,string.len(Start))==Start
end

function string.ends(String,End)
	return End=='' or string.sub(String,-string.len(End))==End
end

-- Logic starts

function xbmc_json_call( meth, para, msg_id )
	--local cmd = '{"jsonrpc": "2.0", "method": "" .. meth .. "", "params": {" .. para .. "}, "id": 1}'
	
	local request = {
						jsonrpc = "2.0";
						id = msg_id or "1";
					}
					
	if meth ~= nil then request.method = meth end
	if (para ~= nil) and (type(para) == "table")then request.params = para end
	
	local cmd = json.encode(request)
	
	debug( "xbmc_json_call with: " .. cmd )
	
	return sendCommand(cmd)		
end

function XBMCall (action)
	local method = ""
	local params = nil
	
	debug( "XBMCall: " .. action )

	--PING
	if (action == "ping" ) then
		method = "JSONRPC.Ping"
	
	--LEFT
	elseif(action == "left") then
		method = "Input.Left"	
	
	--RIGHT
	elseif (action == "right") then
		method = "Input.Right"

	--UP
	elseif (action == "up") then
		method = "Input.Up"

	--DOWN
	elseif (action == "down") then
		method = "Input.Down"
	
	--BACK
	elseif (action == "back") then
		method = "Input.Back"		

	--HOME
	elseif (action == "home") then
		method = "Input.Home"
	
	--ENTER
	elseif (action == "enter") then
		method = "Input.Select"

	--PLAY / PAUSE
	elseif (action == "playpause") then
		method = "Player.PlayPause"
		params = {
			playerid = "1";
		}

	--STOP
	elseif (action == "stop") then
		method = "Player.Stop"
		params = {
			playerid = "1";
		}

	--MUTE
	elseif (action == "mute") then
		method = "Application.SetMute"
		params = {
			mute = "toggle";
		}
	
	--REBOOT
	elseif (action == "reboot") then
		method = "System.Reboot"
	
	--SUSPEND
	elseif (action == "suspend") then
		method = "System.Suspend"
	
	--SHUTDOWN
	elseif (action == "shutdown") then
		method = "System.Shutdown"
	
	--AUDIO LIBRARY UPDATE
	elseif (action == "audioupdate") then
		method = "AudioLibrary.Scan"
	
	--AUDIO LIBRARY CLEAN
	elseif (action == "audioclean") then
		method = "AudioLibrary.Clean"
	
	--VIDEO LIBRARY SCAN
	elseif (action == "videoupdate") then
		method = "VideoLibrary.Scan"
	
	--VIDEO LIBRARY CLEAN
	elseif (action == "videoclean") then
		method = "VideoLibrary.Clean"
	
	--NEXT
	elseif (action == "next") then
		method = "Player.GoNext"
		params = {
			playerid = "1";
		}
	
	--PREVIOUS
	elseif (action == "prev") then
		method = "Player.GoPrevious"
		params = {
			playerid = "1";
		}
	
	--FASTER
	elseif (action == "faster") then
		method = "Player.SetSpeed"
		params = {
			playerid = "1";
			speed = "increment";
		}
	
	--SLOWER
	elseif (action == "slower") then
		method = "Player.SetSpeed"
		params = {
			playerid = "1";
			speed = "decrement";
		}		
	
	--VOLUME UP
	elseif (action == "vup") then
		method = "Application.SetVolume"
		params = {
			volume = "100";
		}
	
	--VOLUME DOWN
	elseif (action == "vdown") then
		method = "Application.SetVolume"
		params = {
			volume = "0";
		}

	--ERROR
	else
		debug("XBMCall Command not found! action: " .. action)		
	end

	local dbg_str = ""
	if (action ~= nil) then dbg_str = dbg_str .. "action: " .. action end
	if (method ~= nil) then dbg_str = dbg_str .. " method: " .. method end
	if (params ~= nil) then dbg_str = dbg_str .. " params: " .. table.concat(params) end		
	debug( dbg_str )
	
	--curlcall (method, params)
	return xbmc_json_call( method, params )
end


function sendCommand(command)
	debug( "in sendCommand" )
	local result = luup.io.write(command)
	if (result == nil) or (result == false) then
		log("Cannot send command " .. command .. " communications error")
--			luup.set_failure(true)
		return false
	end
	debug( "sendCommand = success" )
	return true
end

local function nextchar(result)
	return coroutine.yield(result)
end

local function JSONRPC_Process_Coroutine(ch)
	while true do
		local result
		if ( '{' == ch ) then
				local open_braces_found = 1
				result = ch
				while true do
					next_ch = nextchar()

					result = result .. next_ch

					if (next_ch == "{") then open_braces_found = open_braces_found + 1 end
					if (next_ch == "}") then open_braces_found = open_braces_found - 1 end

					if ( open_braces_found <= 0 ) then break end

				end
		end

		--if ( result ~= nil) then debug( "result: " .. result ) end
		ch = nextchar(result)
	end
end

local JSONRPC_Process = coroutine.wrap(JSONRPC_Process_Coroutine)

function xbmc_ping()
	
	--local ping_cmd ="{\"jsonrpc\": \"2.0\", \"method\": \"JSONRPC.Ping\", \"id\": 1}"		
	--local result = sendCommand(ping_cmd)
	
	local result = XBMCall( "ping" )
	
	return result
end

function getPlayerStatus()
	return luup.variable_get(serviceid, "PlayerStatus", lul_device)
end

function setPlayerStatus(status)
	return writeVariableIfChanged(lul_device, serviceid, "PlayerStatus", status)
end

-- regular ping
function scheduled_ping_ok()
	writeVariableIfChanged(lul_device, serviceid, "PingStatus", "up")
end

function scheduled_ping_fail()
	writeVariableIfChanged(lul_device, serviceid, "PingStatus", "down")
	setPlayerStatus("--")
	writeVariableIfChanged(lul_device, serviceid, "IdleTime", "--")
end

function scheduled_ping()
	log("sending routine ping")
	
	-- check whether we're still connected
	if (luup.io.is_connected(lul_device) == false) then
		scheduled_ping_fail()
	
		log( "io.is_connected is false - No longer connected in scheduled ping, attempt to reconnect")
		
		xbmc_connect()

		luup.call_timer("scheduled_ping", 1, ping_interval, "", "")
		return false			
	end
			

	local result = xbmc_ping()
	if (result == true) then
		scheduled_ping_ok()
		debug("XBMCRemote is UP!")
	else
		scheduled_ping_fail()
		debug("XBMCRemote is DOWN!")
	end
	
	luup.call_timer("scheduled_ping", 1, ping_interval, "", "")
end

local function XBMC_processNotification( method, params)
	debug( "XBMC_processNotification: " .. method )

	if (string.starts(method, "Player.")) then
		-- Player states
		local state = string.sub(method,-(string.len(method)-7))
		debug( "Player state is: " .. state )
		
		setPlayerStatus( state )
		
		if (state == "OnPlay" ) then 
			-- in here send a request for more information on what's playing
			-- then process it in the event handler
			
			if (params.data ~= nil) and (params.data.item ~= nil) and (params.data.player ~= nil) then
				local item = params.data.item
				local player = params.data.player
				
				local new_method = "Player.GetItem"
				local new_params = {
					properties = { "title" };
					playerid = player.playerid;
				}
				
				-- buffer any new data
				xbmc_json_call( new_method, new_params, "GetWhatsPlaying" )				
			
			end
			
		elseif ( state == "OnStop") then
			writeVariableIfChanged(lul_device, serviceid, "CurrentPlaying", "--")
		end
	end
	
end

local function XBMC_processIncomingMessage(msg)
	debug( "XBMC_processIncomingMessage: " .. msg )
	
	-- if we got a notification we must be up, so log the device as up
	scheduled_ping_ok()
	
	local oMsg = json.decode(msg)
	
	if ((oMsg == nil) or (type(oMsg) ~= "table")) then 
		debug( "Couldn't decode returned message" )
		return false 
	end
	
	if( oMsg.id == nil) and (oMsg.method ~= nil) then
		debug( "found a notification" )
		XBMC_processNotification( oMsg.method, oMsg.params )
	elseif ( oMsg.id == "GetWhatsPlaying" ) and (oMsg.result ~= nil) and (oMsg.result.item ~= nil) then
		-- abuse the ID flag to maintain state as GetItem is a generic response
		local item = oMsg.result.item
		
		if ( item.type ~= nil) and (item.title ~= nil) then
			local playing = item.type .. ": " .. item.title
			writeVariableIfChanged(lul_device, serviceid, "CurrentPlaying", playing )
		end
	else
		debug( "unhandled message type" )
	end
end


	-- processed byte by byte
function processIncoming(s)
	if (luup.is_ready(PARENT_DEVICE) == false) then
		return
	end

	local msg = JSONRPC_Process( s )

	if ( msg ~= nil ) then			
		XBMC_processIncomingMessage(msg)
	end
end

function xbmc_connect()
	log("Connecting to XBMC host on: " .. ipAddress .. ":" .. json_tcp_port )
	luup.io.open(lul_device, ipAddress, json_tcp_port)
	
	if (luup.io.is_connected(lul_device) == false) then
		log("Cannot connect. Confirm the IP address is correct, will attempt to reconnect in scheduled ping.")
		-- task( "couldn't connect", TASK_ERROR )
	else
		log("connected to XBMC succesfully")
	end
end


function init(lul_device)
		ipAddress = luup.devices[lul_device].ip
		
		json_tcp_port = readVariableOrInit(lul_device, serviceid, "XBMC_TCP_port", DEFAULT_XBMC_TCP_PORT)
		json_http_port = readVariableOrInit(lul_device, serviceid, "XBMC_HTTP_port", DEFAULT_XBMC_HTTP_PORT)		
		ping_interval = readVariableOrInit(lul_device, serviceid, "PingInterval", DEFAULT_PING_TIME)

		log("starting device: " .. tostring(lul_device))

		
		if (ipAddress == nil or ipAddress == "") then
			return false, "IP Address is required in Device's Advanced Settings!", "XBMCRemote"
		else
			local PingStatus1 = readVariableOrInit( lul_device, serviceid, "PingStatus", "--")
			local IdleTime1 = readVariableOrInit( lul_device, serviceid, "IdleTime", "--")
			local PlayerStatus1 = readVariableOrInit( lul_device, serviceid, "PlayerStatus", "--")
			local CurrentPlaying = readVariableOrInit( lul_device, serviceid, "CurrentPlaying", "--")
		end
		
		if (ipAddress ~= "") and (json_tcp_port ~= "") then
			xbmc_connect()
		else
			return false,'No IP supplied, please enter the IP.','XBMC'
		end
		
		-- at startup do the first ping nearly immediately without waiting for the usual interval
		log( "ping scheduled in " .. SOON .. " seconds" )
		luup.call_timer("scheduled_ping", 1, SOON, "", "")
		
		log("startup complete: " .. tostring(lul_device))
		
		return true,'ok','XBMC'
end