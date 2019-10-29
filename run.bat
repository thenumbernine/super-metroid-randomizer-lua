@echo off
set LUA_PATH=;;?.lua;?/?.lua
luajit.exe run.lua in=sm.sfc
