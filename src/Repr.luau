--!optimize 2
--!strict

local FastMergeDeep = require(script.Parent.FastMergeDeep)
local IsArray = require(script.Parent.IsArray)

--[=[
	Indicates that [DateTime]s should be formatted using the
	[DateTime.fromLocalTime] format.

	@interface LocalTimeFormat
	@field Type "LocalTime"
	@field Format string
	@field Locale? string
	@within TableUtilities
]=]
--[=[
	Indicates that [DateTime]s should be formatted using the
	[DateTime.fromUniversalTime] format.

	@interface UniversalTimeFormat
	@field Type "UniversalTime"
	@field Format string
	@field Locale? string
	@within TableUtilities
]=]
--[=[
	Indicates how we should format [DateTime]s.

	@type DateTimeFormatType "UnixTimestamp" | "UnixTimestampMillis" | "IsoDate" | "LocalTimeTable" | "UniversalTimeTable" | LocalTimeFormat | UniversalTimeFormat
	@within TableUtilities
]=]
export type DateTimeFormatType =
	"UnixTimestamp"
	| "UnixTimestampMillis"
	| "IsoDate"
	| "LocalTimeTable"
	| "UniversalTimeTable"
	| {
		Type: "LocalTime",
		Format: string,
		Locale: string?,
	}
	| {
		Type: "UniversalTime",
		Format: string,
		Locale: string?,
	}

--[=[
	Configures how the Repr function formats.

	@interface ReprSettings
	@field DateTimeFormatType? DateTimeFormatType -- How to format [DateTime]s.
	@field Pretty? boolean -- Whether to use pretty formatting.
	@field RobloxClassName? boolean -- Whether to include Roblox class names.
	@field RobloxDirectoryToString? boolean -- Whether or not to use the DirectoryToString function, which is a fixed version of [Instance.GetFullName].
	@field RobloxFullName? boolean -- Whether to include Roblox full names.
	@field RobloxProperFullName? boolean -- Whether to include Roblox proper full names.
	@field Semicolons? boolean -- Whether to use semicolons.
	@field SortKeys? boolean -- Whether to sort keys.
	@field Spaces? number -- How many spaces to use.
	@field Tabs? boolean -- Whether to use tabs over spaces.
	@within TableUtilities
]=]
type RequiredReprSettings = {
	DateTimeFormatType: DateTimeFormatType,
	Pretty: boolean,
	RobloxClassName: boolean,
	RobloxDirectoryToString: boolean,
	RobloxFullName: boolean,
	RobloxProperFullName: boolean,
	Semicolons: boolean,
	SortKeys: boolean,
	Spaces: number,
	Tabs: boolean,
	[any]: never,
}
export type ReprSettings = {
	DateTimeFormatType: DateTimeFormatType?,
	Pretty: boolean?,
	RobloxClassName: boolean?,
	RobloxDirectoryToString: boolean?,
	RobloxFullName: boolean?,
	RobloxProperFullName: boolean?,
	Semicolons: boolean?,
	SortKeys: boolean?,
	Spaces: number?,
	Tabs: boolean?,
	[any]: never,
}

local DEFAULT_SETTINGS: RequiredReprSettings = {
	DateTimeFormatType = "UnixTimestamp";
	Pretty = true;
	RobloxClassName = false;
	RobloxDirectoryToString = true;
	RobloxFullName = true;
	RobloxProperFullName = false;
	Semicolons = true;
	SortKeys = true;
	Spaces = 4;
	Tabs = true;
}

local LUAU_KEYWORDS = {
	["and"] = true;
	["break"] = true;
	["do"] = true;
	["else"] = true;
	["elseif"] = true;
	["end"] = true;
	["false"] = true;
	["for"] = true;
	["function"] = true;
	["if"] = true;
	["in"] = true;
	["local"] = true;
	["nil"] = true;
	["not"] = true;
	["or"] = true;
	["repeat"] = true;
	["return"] = true;
	["then"] = true;
	["true"] = true;
	["until"] = true;
	["while"] = true;
}

local function IsNumber(value: string)
	local byte = string.byte(value, 1, 1)
	return byte > 47 and byte < 58
end
local function IsLuaIdentifier(value: unknown)
	return not (
		type(value) ~= "string"
		or #value == 0
		or string.find(value, "[^%d%a_]")
		or IsNumber(value)
		or LUAU_KEYWORDS[value]
	)
end

local GetService = game.GetService
local ServicesMetatable = {}
function ServicesMetatable:__index(index)
	local success, object = pcall(GetService, game, index)
	local service = success and object
	self[index] = service
	return service
end
local CachedServices = setmetatable({}, ServicesMetatable)

local function DirectoryToString(object: Instance?)
	if object == nil or object == game then
		return ""
	end

	local fullName: {string} = {}
	local count = 0

	while object.Parent ~= game and object.Parent ~= nil do
		local objectName = string.gsub(object.Name, "([\\\"])", "\\%1")
		if string.find(objectName, "^[_%a][_%w]*$") and IsLuaIdentifier(objectName) then
			fullName[count] = "." .. objectName
		else
			fullName[count] = "[\"" .. objectName .. "\"]"
		end

		count -= 1
		object = object.Parent
	end

	if CachedServices[object.ClassName] == object then
		fullName[count] = "game:GetService(\"" .. object.ClassName .. "\")"
	else
		fullName[count] = "." .. "[\"" .. object.Name .. "\"]"
	end

	return table.concat(fullName, nil, count, 0)
end
local function ProperFullName(object: Instance?)
	if object == nil or object == game then
		return ""
	end

	local name = object.Name
	local usePeriod = true
	if not IsLuaIdentifier(name) then
		name = string.format("[%q]", name)
		usePeriod = false
	end

	if not object.Parent or object.Parent == game then
		return name
	end

	return ProperFullName(object.Parent) .. (if usePeriod then "." else "") .. name
end

local GetFullName = game.GetFullName
local ToLocalTime = DateTime.now().ToLocalTime
local ToUniversalTime = DateTime.now().ToUniversalTime
local ToIsoDate = DateTime.now().ToIsoDate

local Depth = 0
local Shown: {[any]: any}
local CurrentIndent: string

local NORMAL_IDS = Enum.NormalId:GetEnumItems()
type TimeTable = {
	Year: number,
	Month: number,
	Day: number,
	Hour: number,
	Minute: number,
	Second: number,
	Millisecond: number,
}

local function GetFloat(number: number): string
	local asString = tostring(number)
	if tonumber(asString) == number then
		return asString
	end

	for index = 15, 99 do
		asString = string.format("%." .. index .. "f", number)
		if tonumber(asString) == number then
			return asString
		end
	end

	error(`Couldn't convert {number} to a float?`, 2)
end

local function IntegerOrFloat(number: number | string)
	local trueNumber = tonumber(number) or 0
	return if trueNumber ~= trueNumber
		then "0 / 0"
		elseif trueNumber % 1 == 0 then string.format("%d", trueNumber)
		else GetFloat(trueNumber)
end

local function SharedTableToNormalTable(sharedTable: SharedTable): {[any]: any}
	local newTable = {}
	for key, value in sharedTable :: never do
		if typeof(value) == "SharedTable" then
			newTable[key] = SharedTableToNormalTable(value)
		else
			newTable[key] = value
		end
	end

	return newTable
end

type CatalogSearchParamsProperties = "CategoryFilter" | "MaxPrice" | "MinPrice" | "SearchKeyword" | "SortType"
local CATALOG_SEARCH_PARAMETERS_PROPERTIES: {CatalogSearchParamsProperties} = {
	"CategoryFilter" :: "CategoryFilter";
	"MaxPrice" :: "MaxPrice";
	"MinPrice" :: "MinPrice";
	"SearchKeyword" :: "SearchKeyword";
	"SortType" :: "SortType";
}
local DEFAULT_CATALOG_SEARCH_PARAMETERS = CatalogSearchParams.new()

type OverlapParamsProperties = "BruteForceAllSlow" | "CollisionGroup" | "FilterType" | "MaxParts" | "RespectCanCollide"
local OVERLAP_PARAMETERS_PROPERTIES: {OverlapParamsProperties} = {
	"BruteForceAllSlow" :: "BruteForceAllSlow";
	"CollisionGroup" :: "CollisionGroup";
	"FilterType" :: "FilterType";
	"MaxParts" :: "MaxParts";
	"RespectCanCollide" :: "RespectCanCollide";
}
local DEFAULT_OVERLAP_PARAMETERS = OverlapParams.new()

type RaycastParamsProperties = "BruteForceAllSlow" | "CollisionGroup" | "FilterType" | "IgnoreWater" | "RespectCanCollide"
local RAYCAST_PARAMETERS_PROPERTIES: {RaycastParamsProperties} = {
	"BruteForceAllSlow" :: "BruteForceAllSlow";
	"CollisionGroup" :: "CollisionGroup";
	"FilterType" :: "FilterType";
	"IgnoreWater" :: "IgnoreWater";
	"RespectCanCollide" :: "RespectCanCollide";
}
local BLACK_COLOR3 = Color3.fromRGB()
local CFRAME_IDENTITY = CFrame.identity
local DEFAULT_RAYCAST_PARAMETERS = RaycastParams.new()
local PATH_2D_CONTROL_POINT_NONE = Path2DControlPoint.new()
local UDIM2_ZERO = UDim2.new()
local VECTOR2_ONE = Vector2.one
local VECTOR2_XAXIS = Vector2.xAxis
local VECTOR2_YAXIS = Vector2.yAxis
local VECTOR2_ZERO = Vector2.zero
local VECTOR3_KEYS = {
	[Vector3.zero] = "Vector3.zero";
	[Vector3.one] = "Vector3.one";
	[Vector3.xAxis] = "Vector3.xAxis";
	[Vector3.yAxis] = "Vector3.yAxis";
	[Vector3.zAxis] = "Vector3.zAxis";
}

local Repr: (value: any, reprSettings: ReprSettings?) -> string
local FORMATTERS: {[string]: string | (value: any, reprOptions: RequiredReprSettings, tabs: string) -> string} = {
	string = function(newValue: string)
		return string.format("%q", newValue)
	end;
	number = function(newValue: number)
		if newValue ~= newValue then
			return "0/0"
		end

		if newValue == math.huge then
			return "math.huge"
		end

		if newValue == -math.huge then
			return "-math.huge"
		end

		return IntegerOrFloat(newValue)
	end;
	boolean = tostring;
	["nil"] = "nil";
	table = function(newValue: {[any]: any}, reprOptions, tabs)
		if Shown[newValue] then
			return "{CYCLIC}"
		end

		if type(rawget(newValue, "__tostring")) == "function" then
			return tostring(newValue)
		end

		local metatable = getmetatable(newValue :: never)
		if type(metatable) == "table" and type(rawget(metatable, "__tostring")) then
			return tostring(newValue)
		end

		Shown[newValue] = true
		local isArray = IsArray(newValue)

		local pretty = reprOptions.Pretty
		local semicolons = reprOptions.Semicolons

		if isArray then
			local length = #newValue
			if length == 0 then
				Shown[newValue] = false
				return "{}"
			end

			local reprString = {"{"}
			local count = 1

			local reprValues = table.create(length)
			local totalStringLength = 0
			local isMultiline = false

			for index, arrayValue in ipairs(newValue) do
				Depth += 1
				local reprValue = Repr(arrayValue, reprOptions)
				Depth -= 1

				reprValues[index] = reprValue
				if not isMultiline then
					totalStringLength += #reprValue
					if totalStringLength >= 120 then
						isMultiline = true
					end
				end
			end

			local separator = if isMultiline and semicolons then ";" else ","
			local first = true
			if isMultiline and pretty then
				count += 1
				reprString[count] = "\n" .. CurrentIndent .. tabs
			end

			for index, reprValue in reprValues do
				if not first then
					count += 1
					reprString[count] = if isMultiline and pretty then "\n" .. CurrentIndent .. tabs else " "
				end

				count += 1
				reprString[count] = reprValue

				if (isMultiline and pretty) or index < length then
					count += 1
					reprString[count] = separator
				end
				first = false
			end

			Shown[newValue] = false
			if isMultiline and pretty then
				reprString[count + 1] = "\n"
				reprString[count + 2] = tabs
			end
			return table.concat(reprString) .. "}"
		end

		local reprString = {"{", if pretty then "\n" .. CurrentIndent .. tabs else ""}
		local count = 2

		local keyOrder = {}
		local length = 0
		local keyValueStrings = {}
		for key, dictionaryValue in next, newValue do
			Depth += 1
			local keyString = if IsLuaIdentifier(key) then key else "[" .. Repr(key, reprOptions) .. "]"
			local valueString = Repr(dictionaryValue, reprOptions)

			length += 1
			keyOrder[length] = keyString

			keyValueStrings[keyString] = valueString
			Depth -= 1
		end

		if reprOptions.SortKeys then
			table.sort(keyOrder)
		end

		local first = true
		local separator = if semicolons then ";" else ","
		for index, keyString in keyOrder do
			if not first then
				count += 1
				reprString[count] = if pretty then "\n" .. CurrentIndent .. tabs else " "
			end

			count += 1
			reprString[count] = string.format("%* = %*", keyString, keyValueStrings[keyString])

			if pretty or index < length then
				count += 1
				reprString[count] = separator
			end

			first = false
		end

		Shown[newValue] = false
		if pretty then
			reprString[count + 1] = "\n"
			reprString[count + 2] = tabs
		end

		return table.concat(reprString) .. "}"
	end;
	userdata = function(newValue: any)
		local metatable = getmetatable(newValue)
		return if type(metatable) == "table" and type(rawget(metatable, "__tostring")) == "function"
			then tostring(newValue)
			else "<userdata>"
	end;
	buffer = function(newValue: buffer)
		return "<buffer:" .. buffer.tostring(newValue) .. ">"
	end;

	Instance = function(newValue: Instance, reprOptions)
		return (
			if reprOptions.RobloxFullName
				then (if reprOptions.RobloxDirectoryToString
					then DirectoryToString(newValue)
					elseif reprOptions.RobloxProperFullName then ProperFullName(newValue)
					else GetFullName(newValue))
				else newValue.Name
		) .. (if reprOptions.RobloxClassName then string.format(" (%*)", newValue.ClassName) else "")
	end;
	Axes = function(newValue: Axes)
		local array = table.create(3)
		local length = 0
		if newValue.X then
			length = 1
			array[1] = "Enum.Axis.X"
		end

		if newValue.Y then
			length += 1
			array[length] = "Enum.Axis.Y"
		end

		if newValue.Z then
			length += 1
			array[length] = "Enum.Axis.Z"
		end

		return string.format("Axes.new(%*)", table.concat(array, ", "))
	end;
	BrickColor = function(newValue: BrickColor)
		return string.format("BrickColor.new(%q)", newValue.Name)
	end;
	CFrame = function(newValue: CFrame)
		if newValue == CFRAME_IDENTITY then
			return "CFrame.identity"
		end

		local components = table.create(12)
		for index, component in {newValue:GetComponents()} do
			components[index] = IntegerOrFloat(component)
		end
		return string.format("CFrame.new(%*)", table.concat(components, ", "))
	end;
	Color3 = function(newValue: Color3)
		return if newValue == BLACK_COLOR3
			then "Color3.fromRGB()"
			else string.format("Color3.fromRGB(%d, %d, %d)", newValue.R * 255, newValue.G * 255, newValue.B * 255)
	end;
	ColorSequence = function(newValue: ColorSequence, reprOptions)
		local keypoints = newValue.Keypoints
		if #keypoints > 2 then
			return string.format("ColorSequence.new(%*)", Repr(keypoints, reprOptions))
		end

		if keypoints[1].Value == keypoints[2].Value then
			return string.format("ColorSequence.new(%*)", Repr(keypoints[1].Value, reprOptions))
		end

		return string.format(
			"ColorSequence.new(%*, %*)",
			Repr(keypoints[1].Value, reprOptions),
			Repr(keypoints[2].Value, reprOptions)
		)
	end;
	ColorSequenceKeypoint = function(newValue: ColorSequenceKeypoint, reprOptions)
		return string.format(
			"ColorSequenceKeypoint.new(%*, %*)",
			IntegerOrFloat(newValue.Time),
			Repr(newValue.Value, reprOptions)
		)
	end;
	DockWidgetPluginGuiInfo = function(newValue: DockWidgetPluginGuiInfo)
		return string.format(
			"DockWidgetPluginGuiInfo.new(%*, %*, %*, %*, %*, %*, %*)",
			"Enum.InitialDockState.Bottom",
			newValue.InitialEnabled,
			newValue.InitialEnabledShouldOverrideRestore,
			IntegerOrFloat(newValue.FloatingXSize),
			IntegerOrFloat(newValue.FloatingYSize),
			IntegerOrFloat(newValue.MinWidth),
			IntegerOrFloat(newValue.MinHeight)
		)
	end;
	Enums = "Enum";
	Enum = function(newValue: Enum)
		return "Enum." .. tostring(newValue)
	end;
	-- EnumItem = function(newValue: EnumItem)
	-- 	return "Enum." .. tostring(newValue.EnumType) .. "." .. newValue.Name
	-- end;
	EnumItem = tostring;
	Faces = function(newValue: Faces)
		local array = table.create(6)
		local length = 0
		for _, enumItem in NORMAL_IDS do
			if (newValue :: never)[enumItem.Name] then
				length += 1
				array[length] = tostring(enumItem)
			end
		end

		return string.format("Faces.new(%*)", table.concat(array, ", "))
	end;
	Font = function(newValue: Font)
		local weight = newValue.Weight
		local style = newValue.Style

		local includeStyle = style ~= Enum.FontStyle.Normal
		local includeWeight = if includeStyle then true else weight ~= Enum.FontWeight.Regular

		return if includeWeight
			then if includeStyle
				then string.format("Font.new(%q, %*, %*)", newValue.Family, newValue.Weight, newValue.Style)
				else string.format("Font.new(%q, %*)", newValue.Family, newValue.Weight)
			else string.format("Font.new(%q)", newValue.Family)
	end;
	NumberRange = function(newValue: NumberRange)
		local min = newValue.Min
		local max = newValue.Max
		return if min == max
			then string.format("NumberRange.new(%*)", IntegerOrFloat(min))
			else string.format("NumberRange.new(%*, %*)", IntegerOrFloat(min), IntegerOrFloat(max))
	end;
	NumberSequence = function(newValue: NumberSequence, reprOptions)
		local keypoints = newValue.Keypoints
		if #keypoints > 2 then
			return string.format("NumberSequence.new(%*)", Repr(keypoints, reprOptions))
		end

		if keypoints[1].Value == keypoints[2].Value then
			return string.format("NumberSequence.new(%*)", IntegerOrFloat(keypoints[1].Value))
		end

		return string.format(
			"NumberSequence.new(%*, %*)",
			IntegerOrFloat(keypoints[1].Value),
			IntegerOrFloat(keypoints[2].Value)
		)
	end;
	NumberSequenceKeypoint = function(newValue: NumberSequenceKeypoint)
		local envelope = newValue.Envelope
		return if envelope ~= 0
			then string.format(
				"NumberSequenceKeypoint.new(%*, %*, %*)",
				IntegerOrFloat(newValue.Time),
				IntegerOrFloat(newValue.Value),
				IntegerOrFloat(envelope)
			)
			else string.format(
				"NumberSequenceKeypoint.new(%*, %*)",
				IntegerOrFloat(newValue.Time),
				IntegerOrFloat(newValue.Value)
			)
	end;
	PathWaypoint = function(newValue: PathWaypoint, reprOptions)
		local label = newValue.Label
		return if label and label ~= ""
			then string.format(
				"PathWaypoint.new(%*, %*, %q)",
				Repr(newValue.Position, reprOptions),
				newValue.Action,
				label
			)
			else string.format("PathWaypoint.new(%*, %*)", Repr(newValue.Position, reprOptions), newValue.Action)
	end;
	PhysicalProperties = function(newValue: PhysicalProperties)
		return string.format(
			"PhysicalProperties.new(%*, %*, %*, %*, %*)",
			IntegerOrFloat(newValue.Density),
			IntegerOrFloat(newValue.Friction),
			IntegerOrFloat(newValue.Elasticity),
			IntegerOrFloat(newValue.FrictionWeight),
			IntegerOrFloat(newValue.ElasticityWeight)
		)
	end;
	Random = "<Random>";
	Ray = function(newValue: Ray, reprOptions)
		return string.format(
			"Ray.new(%*, %*)",
			Repr(newValue.Origin, reprOptions),
			Repr(newValue.Direction, reprOptions)
		)
	end;
	RaycastParams = function(newValue: RaycastParams, reprOptions)
		local optionsTable: {
			BruteForceAllSlow: boolean?,
			CollisionGroup: string?,
			FilterDescendantsInstances: {Instance}?,
			FilterType: Enum.RaycastFilterType?,
			IgnoreWater: boolean?,
			RespectCanCollide: boolean?,
		} =
			{
				BruteForceAllSlow = nil;
				CollisionGroup = nil;
				FilterDescendantsInstances = nil;
				FilterType = nil;
				IgnoreWater = nil;
				RespectCanCollide = nil;
			}

		local filterDescendantsInstances = newValue.FilterDescendantsInstances
		if filterDescendantsInstances and #filterDescendantsInstances > 0 then
			optionsTable.FilterDescendantsInstances = filterDescendantsInstances
		end

		for _, property: RaycastParamsProperties in RAYCAST_PARAMETERS_PROPERTIES do
			local currentValue = (newValue :: never)[property]
			if currentValue ~= (DEFAULT_RAYCAST_PARAMETERS :: never)[property] then
				optionsTable[property] = currentValue
			end
		end

		return string.format("RaycastParams.new(%*)", Repr(optionsTable, reprOptions))
	end;
	RaycastResult = function(newValue: RaycastResult, reprOptions)
		return string.format(
			"RaycastResult<%*>",
			Repr({
				Distance = IntegerOrFloat(newValue.Distance);
				Instance = Repr(newValue.Instance, reprOptions);
				Material = newValue.Material;
				Normal = Repr(newValue.Normal, reprOptions);
				Position = Repr(newValue.Position, reprOptions);
			}, reprOptions)
		)
	end;
	RBXScriptConnection = "<RBXScriptConnection>";
	RBXScriptSignal = "<RBXScriptSignal>";
	Rect = function(newValue: Rect)
		return string.format(
			"Rect.new(%*, %*, %*, %*)",
			IntegerOrFloat(newValue.Min.X),
			IntegerOrFloat(newValue.Min.Y),
			IntegerOrFloat(newValue.Max.X),
			IntegerOrFloat(newValue.Max.Y)
		)
	end;
	Region3 = function(newValue: Region3, reprOptions)
		local halfSize = newValue.Size / 2
		local position = newValue.CFrame.Position
		return string.format(
			"Region3.new(%*, %*)",
			Repr(position - halfSize, reprOptions),
			Repr(position + halfSize, reprOptions)
		)
	end;
	Region3int16 = function(newValue: Region3int16, reprOptions)
		return string.format(
			"Region3int16.new(%*, %*)",
			Repr(newValue.Min, reprOptions),
			Repr(newValue.Max, reprOptions)
		)
	end;
	TweenInfo = function(newValue: TweenInfo)
		return string.format(
			"TweenInfo.new(%*, %*, %*, %*, %*, %*)",
			IntegerOrFloat(newValue.Time),
			newValue.EasingStyle,
			newValue.EasingDirection,
			IntegerOrFloat(newValue.RepeatCount),
			newValue.Reverses,
			IntegerOrFloat(newValue.DelayTime)
		)
	end;
	UDim = function(newValue: UDim)
		local scale = newValue.Scale
		local offset = newValue.Offset

		if scale == 0 and offset == 0 then
			return "UDim.new()"
		end

		return string.format("UDim.new(%*, %*)", IntegerOrFloat(scale), IntegerOrFloat(offset))
	end;
	UDim2 = function(newValue: UDim2)
		if newValue == UDIM2_ZERO then
			return "UDim2.new()"
		end

		local x = newValue.X
		local y = newValue.Y

		local scaleX = x.Scale
		local offsetX = x.Offset

		local scaleY = y.Scale
		local offsetY = y.Offset

		if offsetX == 0 and offsetY == 0 then
			return string.format("UDim2.fromScale(%*, %*)", IntegerOrFloat(scaleX), IntegerOrFloat(scaleY))
		end
		if scaleX == 0 and scaleY == 0 then
			return string.format("UDim2.fromOffset(%*, %*)", offsetX, offsetY)
		end

		return string.format(
			"UDim2.new(%*, %*, %*, %*)",
			IntegerOrFloat(scaleX),
			offsetX,
			IntegerOrFloat(scaleY),
			offsetY
		)
	end;
	Vector2 = function(newValue: Vector2)
		if newValue == VECTOR2_ONE then
			return "Vector2.one"
		end
		if newValue == VECTOR2_ZERO then
			return "Vector2.zero"
		end
		if newValue == VECTOR2_XAXIS then
			return "Vector2.xAxis"
		end
		if newValue == VECTOR2_YAXIS then
			return "Vector2.yAxis"
		end
		return string.format("Vector2.new(%*, %*)", IntegerOrFloat(newValue.X), IntegerOrFloat(newValue.Y))
	end;
	Vector2int16 = function(newValue: Vector2int16)
		local x = newValue.X
		local y = newValue.Y
		return if x == 0 and y == 0
			then "Vector2int16.new()"
			else string.format("Vector2int16.new(%*, %*)", newValue.X, newValue.Y)
	end;
	Vector3 = function(newValue: Vector3)
		return VECTOR3_KEYS[newValue]
			or string.format(
				"Vector3.new(%*, %*, %*)",
				IntegerOrFloat(newValue.X),
				IntegerOrFloat(newValue.Y),
				IntegerOrFloat(newValue.Z)
			)
	end;
	Vector3int16 = function(newValue: Vector3int16)
		local x = newValue.X
		local y = newValue.Y
		local z = newValue.Z

		return if x == 0
				and y == 0
				and z == 0
			then "Vector3int16.new()"
			else string.format("Vector3int16.new(%*, %*, %*)", newValue.X, newValue.Y, newValue.Z)
	end;

	SharedTable = function(newValue: SharedTable, reprOptions)
		return string.format("SharedTable.new(%*)", Repr(SharedTableToNormalTable(newValue), reprOptions))
	end;
	DateTime = function(newValue: DateTime, reprOptions)
		local dateTimeFormatType = reprOptions.DateTimeFormatType

		if type(dateTimeFormatType) == "table" then
			local formatType = dateTimeFormatType.Type
			local format = dateTimeFormatType.Format
			local locale = dateTimeFormatType.Locale or "en-us"

			return string.format(
				"<DateTime:%*:%*>",
				formatType,
				if formatType == "LocalTime"
					then newValue:FormatLocalTime(format, locale)
					else newValue:FormatUniversalTime(format, locale)
			)
		end

		if dateTimeFormatType == "IsoDate" then
			return string.format("DateTime.fromIsoDate(%q)", ToIsoDate(newValue))
		end

		if dateTimeFormatType == "UnixTimestamp" then
			return string.format("DateTime.fromUnixTimestamp(%*)", newValue.UnixTimestamp)
		end
		if dateTimeFormatType == "UnixTimestampMillis" then
			return string.format("DateTime.fromUnixTimestampMillis(%*)", newValue.UnixTimestampMillis)
		end

		if dateTimeFormatType == "LocalTimeTable" then
			local timeTable: TimeTable = ToLocalTime(newValue) :: never
			return string.format(
				"DateTime.fromLocalTime(%*, %*, %*, %*, %*, %*, %*)",
				timeTable.Year,
				timeTable.Month,
				timeTable.Day,
				timeTable.Hour,
				timeTable.Minute,
				timeTable.Second,
				timeTable.Millisecond
			)
		end

		local timeTable: TimeTable = ToUniversalTime(newValue) :: never
		return string.format(
			"DateTime.fromUniversalTime(%*, %*, %*, %*, %*, %*, %*)",
			timeTable.Year,
			timeTable.Month,
			timeTable.Day,
			timeTable.Hour,
			timeTable.Minute,
			timeTable.Second,
			timeTable.Millisecond
		)
	end;
	CatalogSearchParams = function(newValue: CatalogSearchParams, reprOptions)
		if newValue == DEFAULT_CATALOG_SEARCH_PARAMETERS then
			return "CatalogSearchParams.new()"
		end

		local optionsTable: {
			AssetTypes: {Enum.AssetType}?,
			BundleTypes: {Enum.BundleType}?,
			CategoryFilter: Enum.CatalogCategoryFilter?,
			MaxPrice: number?,
			MinPrice: number?,
			SearchKeyword: string?,
			SortType: Enum.CatalogSortType?,
		} =
			{
				AssetTypes = nil;
				BundleTypes = nil;
				CategoryFilter = nil;
				MaxPrice = nil;
				MinPrice = nil;
				SearchKeyword = nil;
				SortType = nil;
			}

		local assetTypes = newValue.AssetTypes
		if assetTypes and #assetTypes > 0 then
			optionsTable.AssetTypes = assetTypes
		end
		local bundleTypes = newValue.BundleTypes
		if bundleTypes and #bundleTypes > 0 then
			optionsTable.BundleTypes = bundleTypes
		end

		for _, property: CatalogSearchParamsProperties in CATALOG_SEARCH_PARAMETERS_PROPERTIES do
			local currentValue = (newValue :: never)[property]
			if currentValue ~= (DEFAULT_CATALOG_SEARCH_PARAMETERS :: never)[property] then
				optionsTable[property] = currentValue
			end
		end

		return string.format("CatalogSearchParams.new(%*)", Repr(optionsTable, reprOptions))
	end;
	FloatCurveKey = function(newValue: FloatCurveKey)
		return string.format(
			"FloatCurveKey.new(%*, %*, %*)",
			IntegerOrFloat(newValue.Time),
			IntegerOrFloat(newValue.Value),
			newValue.Interpolation
		)
	end;
	OverlapParams = function(newValue: OverlapParams, reprOptions)
		local optionsTable: {
			BruteForceAllSlow: boolean?,
			CollisionGroup: string?,
			FilterDescendantsInstances: {Instance}?,
			FilterType: Enum.RaycastFilterType?,
			MaxParts: number?,
			RespectCanCollide: boolean?,
		} =
			{
				BruteForceAllSlow = nil;
				CollisionGroup = nil;
				FilterDescendantsInstances = nil;
				FilterType = nil;
				MaxParts = nil;
				RespectCanCollide = nil;
			}

		local filterDescendantsInstances = newValue.FilterDescendantsInstances
		if filterDescendantsInstances and #filterDescendantsInstances > 0 then
			optionsTable.FilterDescendantsInstances = filterDescendantsInstances
		end

		for _, property: OverlapParamsProperties in OVERLAP_PARAMETERS_PROPERTIES do
			local currentValue = (newValue :: never)[property]
			if currentValue ~= (DEFAULT_OVERLAP_PARAMETERS :: never)[property] then
				optionsTable[property] = currentValue
			end
		end

		return string.format("OverlapParams.new(%*)", Repr(optionsTable, reprOptions))
	end;
	Path2DControlPoint = function(newValue: Path2DControlPoint, reprOptions)
		return if newValue == PATH_2D_CONTROL_POINT_NONE
			then "Path2DControlPoint.new()"
			else string.format(
				"Path2DControlPoint.new(%*, %*, %*)",
				Repr(newValue.Position, reprOptions),
				Repr(newValue.LeftTangent, reprOptions),
				Repr(newValue.RightTangent, reprOptions)
			)
	end;
	RotationCurveKey = function(newValue: RotationCurveKey, reprOptions)
		return string.format(
			"RotationCurveKey.new(%*, %*, %*)",
			IntegerOrFloat(newValue.Time),
			Repr(newValue.Value, reprOptions),
			newValue.Interpolation
		)
	end;

	["function"] = "<function>";
	thread = "<thread>";
}

--[=[
	Basically the same as the `repr` function from Python. Formats things in a
	a pretty way.

	@function Repr
	@within TableUtilities

	@param value unknown -- The value to format.
	@param reprSettings? ReprSettings -- The settings to use.
	@return string -- The formatted value.
]=]
function Repr(value: any, reprSettings: ReprSettings?)
	local reprOptions: RequiredReprSettings = FastMergeDeep(DEFAULT_SETTINGS, reprSettings)

	if reprOptions.Tabs then
		CurrentIndent = "\t"
	else
		CurrentIndent = string.rep(" ", reprOptions.Spaces)
	end

	local tabs = string.rep(CurrentIndent, Depth)
	if Depth == 0 then
		Shown = {}
	end

	local typeOf = typeof(value)
	local stringifyOrString = FORMATTERS[typeOf]
	if stringifyOrString then
		return if type(stringifyOrString) == "function"
			then stringifyOrString(value, reprOptions, tabs)
			else stringifyOrString
	end

	return if type(value) == typeOf then "<" .. type(value) .. ">" else "<Roblox:" .. typeOf .. ">"
end

return Repr
