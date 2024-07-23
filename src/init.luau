--!optimize 2
--!strict

local CopyDeep = require(script.CopyDeep)
local EqualObjects = require(script.EqualObjects)
local Equals = require(script.Equals)
local EqualsDeep = require(script.EqualsDeep)
local IsArray = require(script.IsArray)
local LockDeep = require(script.LockDeep)
local Repr = require(script.Repr)

local FindInsertIndex = require(script.SortedArrays.FindInsertIndex)
local FindInsertIndexSimple = require(script.SortedArrays.FindInsertIndexSimple)
local SortedInsert = require(script.SortedArrays.SortedInsert)
local SortedInsertSimple = require(script.SortedArrays.SortedInsertSimple)

-- TODO: When we get @native in selene (and roblox? don't know if it's on without fflag mods) we should transform some of these to @native

--[=[
	A library that contains various utilities for tables.

	@class TableUtilities
]=]
local TableUtilities = table.freeze({
	CopyDeep = CopyDeep;
	EqualObjects = EqualObjects;
	Equals = Equals;
	EqualsDeep = EqualsDeep;
	IsArray = IsArray;
	LockDeep = LockDeep;
	Repr = Repr;

	FindInsertIndex = FindInsertIndex;
	FindInsertIndexSimple = FindInsertIndexSimple;
	SortedInsert = SortedInsert;
	SortedInsertSimple = SortedInsertSimple;
})

export type DateTimeFormatType = Repr.DateTimeFormatType
export type ReprSettings = Repr.ReprSettings

return TableUtilities
