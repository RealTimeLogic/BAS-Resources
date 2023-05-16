--[[
This is a simple command line entry point for OPC UA Server
]]

local ua = require("opcua.api")

local function PrintUsage()
  print("Usage:")
  print("  opcua_server.lua [options]   ")
  print("    --config <config_path>")
  print("        config_path - path to lua file which contains configuration table")
  print()
  print("    --help")
  print("        Print help")
  print()
end

local config
if #arg == 2 and arg[1] == '--config' then
  config = dofile(arg[2])
elseif #arg == 1  and arg[1] == '--help' then
  PrintUsage()
  os.exit(0)
elseif #arg ~= 0 then
  print("Invalid command line parameters. Print --help to see detailed information.")
  os.exit(-1)
end

local server = ua.newServer(config)
server:initialize()
server:run()

local ba = ba
while ba ~= nil do
  ba.sleep(1000)
end

os.exit(0)
