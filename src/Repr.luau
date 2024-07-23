--!optimize 2
--!strict

local CopyDeep = require(script.Parent.CopyDeep)
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
	RobloxClassName = true;
	RobloxFullName = false;
	RobloxProperFullName = true;
	Semicolons = true;
	SortKeys = true;
	Spaces = 4;
	Tabs = true;
}

local LUA_KEYWORDS = {
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

local function IsLuaIdentifier(value: string)
	return not (
		type(value) ~= "string"
		or #value == 0
		or string.find(value, "[^%d%a_]")
		or tonumber(string.sub(value, 1, 1))
		or LUA_KEYWORDS[value]
	)
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

local depth = 0
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
	return if trueNumber % 1 == 0 then string.format("%d", trueNumber) else GetFloat(trueNumber)
end

local function MergeDeep<T>(...: {[any]: any}?): T
	local new = {}
	for index = 1, select("#", ...) do
		local dictionary = select(index, ...)
		if type(dictionary) ~= "table" then
			continue
		end

		for key, value in dictionary do
			if type(value) == "table" then
				if new[key] == nil or type(new[key]) ~= "table" then
					new[key] = CopyDeep(value)
				else
					new[key] = MergeDeep(new[key], value)
				end
			else
				new[key] = value
			end
		end
	end

	return new :: never
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

local Repr: (value: any, reprSettings: ReprSettings?) -> string

local FORMATTERS: {[string]: string | (value: any, reprOptions: RequiredReprSettings, tabs: string) -> string} = {
	string = function(newValue: string)
		return string.format("%q", newValue)
	end;
	number = function(newValue: number)
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
		local reprString = "{" .. (reprOptions.Pretty and "\n" .. CurrentIndent .. tabs or "")

		if isArray then
			local length = #newValue
			if length == 0 then
				Shown[newValue] = false
				return "{}"
			end

			reprString = "{"
			for index, arrayValue in newValue do
				if index ~= 1 then
					reprString ..= ", "
				end

				depth += 1
				reprString ..= Repr(arrayValue, reprOptions)
				depth -= 1
			end

			Shown[newValue] = false
			return reprString .. "}"
		end

		local keyOrder = {}
		local length = 0
		local keyValueStrings = {}
		for key, dictionaryValue in next, newValue do
			depth += 1
			local keyString = if IsLuaIdentifier(key) then key else "[" .. Repr(key, reprOptions) .. "]"
			local valueString = Repr(dictionaryValue, reprOptions)

			length += 1
			keyOrder[length] = keyString

			keyValueStrings[keyString] = valueString
			depth -= 1
		end

		if reprOptions.SortKeys then
			table.sort(keyOrder)
		end

		local first = true
		for _, keyString in keyOrder do
			if not first then
				reprString ..= (if reprOptions.Semicolons then ";" else ",") .. (if reprOptions.Pretty
					then "\n" .. CurrentIndent .. tabs
					else " ")
			end

			reprString ..= string.format("%* = %*", keyString, keyValueStrings[keyString])
			first = false
		end

		Shown[newValue] = false
		if reprOptions.Pretty then
			reprString ..= "\n" .. tabs
		end

		return reprString .. "}"
	end;
	userdata = function(newValue: any)
		local metatable = getmetatable(newValue)
		return if type(metatable) == "table" and type(rawget(metatable, "__tostring")) == "function"
			then tostring(newValue)
			else "<userdata>"
	end;
	buffer = function(newValue: buffer)
		return `<buffer:{buffer.tostring(newValue)}>`
	end;

	Instance = function(newValue: Instance, reprOptions)
		return (
			if reprOptions.RobloxFullName
				then (if reprOptions.RobloxProperFullName then ProperFullName(newValue) else newValue:GetFullName())
				else newValue.Name
		) .. (if reprOptions.RobloxClassName then (string.format(" (%*)", newValue.ClassName)) else "")
	end;
	Axes = function(newValue: Axes, reprOptions)
		local array = table.create(3)
		local length = 0
		if newValue.X then
			length += 1
			array[length] = Repr(Enum.Axis.X, reprOptions)
		end

		if newValue.Y then
			length += 1
			array[length] = Repr(Enum.Axis.Y, reprOptions)
		end

		if newValue.Z then
			length += 1
			array[length] = Repr(Enum.Axis.Z, reprOptions)
		end

		return string.format("Axes.new(%*)", table.concat(array, ", "))
	end;
	BrickColor = function(newValue: BrickColor)
		return string.format("BrickColor.new(%q)", newValue.Name)
	end;
	CFrame = function(newValue: CFrame)
		local components = table.create(12)
		for index, component in {newValue:GetComponents()} do
			components[index] = IntegerOrFloat(component)
		end
		return string.format("CFrame.new(%*)", table.concat(components, ", "))
	end;
	Color3 = function(newValue: Color3)
		return string.format("Color3.fromRGB(%d, %d, %d)", newValue.R * 255, newValue.G * 255, newValue.B * 255)
	end;
	ColorSequence = function(newValue: ColorSequence, reprOptions)
		if #newValue.Keypoints > 2 then
			return string.format("ColorSequence.new(%*)", Repr(newValue.Keypoints, reprOptions))
		end

		if newValue.Keypoints[1].Value == newValue.Keypoints[2].Value then
			return string.format("ColorSequence.new(%*)", Repr(newValue.Keypoints[1].Value, reprOptions))
		end

		return string.format(
			"ColorSequence.new(%*, %*)",
			Repr(newValue.Keypoints[1].Value, reprOptions),
			Repr(newValue.Keypoints[2].Value, reprOptions)
		)
	end;
	ColorSequenceKeypoint = function(newValue: ColorSequenceKeypoint, reprOptions)
		return string.format(
			"ColorSequenceKeypoint.new(%*, %*)",
			IntegerOrFloat(newValue.Time),
			Repr(newValue.Value, reprOptions)
		)
	end;
	DockWidgetPluginGuiInfo = function(newValue: DockWidgetPluginGuiInfo, reprOptions)
		return string.format(
			"DockWidgetPluginGuiInfo.new(%*, %*, %*, %*, %*, %*, %*)",
			Repr(Enum.InitialDockState.Bottom, reprOptions),
			Repr(newValue.InitialEnabled, reprOptions),
			Repr(newValue.InitialEnabledShouldOverrideRestore, reprOptions),
			Repr(newValue.FloatingXSize, reprOptions),
			Repr(newValue.FloatingYSize, reprOptions),
			Repr(newValue.MinWidth, reprOptions),
			Repr(newValue.MinHeight, reprOptions)
		)
	end;
	Enums = "Enum";
	Enum = function(newValue: Enum)
		return `Enum.{newValue}`
	end;
	EnumItem = function(newValue: EnumItem)
		return `Enum.{newValue.EnumType}.{newValue.Name}`
	end;
	Faces = function(newValue: Faces, reprOptions)
		local array = table.create(6)
		local length = 0
		for _, enumItem in NORMAL_IDS do
			if (newValue :: never)[enumItem.Name] then
				length += 1
				array[length] = Repr(enumItem, reprOptions)
			end
		end

		return string.format("Faces.new(%*)", table.concat(array, ", "))
	end;
	Font = function(newValue: Font, reprOptions)
		return string.format(
			"Font.new(%q, %*, %*)",
			newValue.Family,
			Repr(newValue.Weight, reprOptions),
			Repr(newValue.Style, reprOptions)
		)
	end;
	NumberRange = function(newValue: NumberRange)
		return if newValue.Min == newValue.Max
			then string.format("NumberRange.new(%*)", IntegerOrFloat(newValue.Min))
			else string.format(
				"NumberRange.new(%*, %*)",
				IntegerOrFloat(newValue.Min),
				IntegerOrFloat(newValue.Max)
			)
	end;
	NumberSequence = function(newValue: NumberSequence, reprOptions)
		if #newValue.Keypoints > 2 then
			return string.format("NumberSequence.new(%*)", Repr(newValue.Keypoints, reprOptions))
		end

		if newValue.Keypoints[1].Value == newValue.Keypoints[2].Value then
			return string.format("NumberSequence.new(%*)", IntegerOrFloat(newValue.Keypoints[1].Value))
		end

		return string.format(
			"NumberSequence.new(%*, %*)",
			IntegerOrFloat(newValue.Keypoints[1].Value),
			IntegerOrFloat(newValue.Keypoints[2].Value)
		)
	end;
	NumberSequenceKeypoint = function(newValue: NumberSequenceKeypoint)
		return if newValue.Envelope ~= 0
			then string.format(
				"NumberSequenceKeypoint.new(%*, %*, %*)",
				IntegerOrFloat(newValue.Time),
				IntegerOrFloat(newValue.Value),
				IntegerOrFloat(newValue.Envelope)
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
				"PathWaypoint.new(%*, %*, %*)",
				Repr(newValue.Position, reprOptions),
				Repr(newValue.Action, reprOptions),
				Repr(newValue.Label, reprOptions)
			)
			else string.format(
				"PathWaypoint.new(%*, %*)",
				Repr(newValue.Position, reprOptions),
				Repr(newValue.Action, reprOptions)
			)
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
		return string.format(
			"RaycastParams.new({\n\tBruteForceAllSlow = %*;\n\tCollisionGroup = %*;\n\tFilterDescendantsInstances = %*;\n\tFilterType = %*;\n\tIgnoreWater = %*;\n\tRespectCanCollide = %*;\n})",
			Repr(newValue.BruteForceAllSlow, reprOptions),
			Repr(newValue.CollisionGroup, reprOptions),
			Repr(newValue.FilterDescendantsInstances, reprOptions),
			Repr(newValue.FilterType, reprOptions),
			Repr(newValue.IgnoreWater, reprOptions),
			Repr(newValue.RespectCanCollide, reprOptions)
		)
	end;
	RaycastResult = function(newValue: RaycastResult, reprOptions)
		return string.format(
			"RaycastResult({\n\tInstance = %*;\n\tPosition = %*;\n\tNormal = %*;\n\tMaterial = %*;\n})",
			Repr(newValue.Instance, reprOptions),
			Repr(newValue.Position, reprOptions),
			Repr(newValue.Normal, reprOptions),
			Repr(newValue.Material, reprOptions)
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
		local min = newValue.CFrame.Position + newValue.Size / -2
		local max = newValue.CFrame.Position + newValue.Size / 2
		return string.format("Region3.new(%*, %*)", Repr(min, reprOptions), Repr(max, reprOptions))
	end;
	Region3int16 = function(newValue: Region3int16, reprOptions)
		return string.format(
			"Region3int16.new(%*, %*)",
			Repr(newValue.Min, reprOptions),
			Repr(newValue.Max, reprOptions)
		)
	end;
	TweenInfo = function(newValue: TweenInfo, reprOptions)
		return string.format(
			"TweenInfo.new(%*, %*, %*, %*, %*, %*)",
			IntegerOrFloat(newValue.Time),
			Repr(newValue.EasingStyle, reprOptions),
			Repr(newValue.EasingDirection, reprOptions),
			IntegerOrFloat(newValue.RepeatCount),
			Repr(newValue.Reverses, reprOptions),
			IntegerOrFloat(newValue.DelayTime)
		)
	end;
	UDim = function(newValue: UDim)
		return string.format("UDim.new(%*, %*)", IntegerOrFloat(newValue.Scale), IntegerOrFloat(newValue.Offset))
	end;
	UDim2 = function(newValue: UDim2)
		return string.format(
			"UDim2.new(%*, %*, %*, %*)",
			IntegerOrFloat(newValue.X.Scale),
			IntegerOrFloat(newValue.X.Offset),
			IntegerOrFloat(newValue.Y.Scale),
			IntegerOrFloat(newValue.Y.Offset)
		)
	end;
	Vector2 = function(newValue: Vector2)
		return string.format("Vector2.new(%*, %*)", IntegerOrFloat(newValue.X), IntegerOrFloat(newValue.Y))
	end;
	Vector2int16 = function(newValue: Vector2int16)
		return string.format("Vector2int16.new(%*, %*)", IntegerOrFloat(newValue.X), IntegerOrFloat(newValue.Y))
	end;
	Vector3 = function(newValue: Vector3)
		return string.format(
			"Vector3.new(%*, %*, %*)",
			IntegerOrFloat(newValue.X),
			IntegerOrFloat(newValue.Y),
			IntegerOrFloat(newValue.Z)
		)
	end;
	Vector3int16 = function(newValue: Vector3int16)
		return string.format(
			"Vector3int16.new(%*, %*, %*)",
			IntegerOrFloat(newValue.X),
			IntegerOrFloat(newValue.Y),
			IntegerOrFloat(newValue.Z)
		)
	end;

	SharedTable = function(newValue: SharedTable, reprOptions)
		return Repr(SharedTableToNormalTable(newValue), reprOptions)
	end;
	DateTime = function(newValue: DateTime, reprOptions)
		local dateTimeFormatType = reprOptions.DateTimeFormatType

		if type(dateTimeFormatType) == "table" then
			if dateTimeFormatType.Type == "LocalTime" then
				return `<DateTime:LocalTime:{newValue:FormatLocalTime(
					dateTimeFormatType.Format,
					dateTimeFormatType.Locale or "en-us"
				)}>`
			end
			return `<DateTime:UniversalTime:{newValue:FormatUniversalTime(
				dateTimeFormatType.Format,
				dateTimeFormatType.Locale or "en-us"
			)}>`
		end

		if dateTimeFormatType == "IsoDate" then
			return `DateTime.fromIsoDate({newValue:ToIsoDate()})`
		end

		if dateTimeFormatType == "UnixTimestamp" then
			return `DateTime.fromUnixTimestamp({newValue.UnixTimestamp})`
		end
		if dateTimeFormatType == "UnixTimestampMillis" then
			return `DateTime.fromUnixTimestampMillis({newValue.UnixTimestampMillis})`
		end

		if dateTimeFormatType == "LocalTimeTable" then
			local timeTable: TimeTable = newValue:ToLocalTime() :: never
			return `DateTime.fromLocalTime({timeTable.Year}, {timeTable.Month}, {timeTable.Day}, {timeTable.Hour}, {timeTable.Minute}, {timeTable.Second}, {timeTable.Millisecond})`
		end

		local timeTable: TimeTable = newValue:ToUniversalTime() :: never
		return `DateTime.fromUniversalTime({timeTable.Year}, {timeTable.Month}, {timeTable.Day}, {timeTable.Hour}, {timeTable.Minute}, {timeTable.Second}, {timeTable.Millisecond})`
	end;
	CatalogSearchParams = function(newValue: CatalogSearchParams, reprOptions)
		return `CatalogSearchParams.new({Repr({
			AssetTypes = Repr(newValue.AssetTypes, reprOptions);
			BundleType = Repr(newValue.BundleType, reprOptions);
			CategoryFilter = Repr(newValue.CategoryFilter, reprOptions);
			MaxPrice = Repr(newValue.MaxPrice, reprOptions);
			MinPrice = Repr(newValue.MinPrice, reprOptions);
			SearchKeyword = Repr(newValue.SearchKeyword, reprOptions);
			SortType = Repr(newValue.SortType, reprOptions);
		}, reprOptions)})`
	end;
	FloatCurveKey = function(newValue: FloatCurveKey, reprOptions)
		return `FloatCurve.new({IntegerOrFloat(newValue.Time)}, {IntegerOrFloat(newValue.Value)}, {Repr(
			newValue.Interpolation,
			reprOptions
		)})`
	end;
	OverlapParams = function(newValue: OverlapParams, reprOptions)
		return string.format(
			"OverlapParams.new({\n\tBruteForceAllSlow = %*;\n\tCollisionGroup = %*;\n\tFilterDescendantsInstances = %*;\n\tFilterType = %*;\n\tMaxParts = %*;\n\tRespectCanCollide = %*;\n})",
			Repr(newValue.BruteForceAllSlow, reprOptions),
			Repr(newValue.CollisionGroup, reprOptions),
			Repr(newValue.FilterDescendantsInstances, reprOptions),
			Repr(newValue.FilterType, reprOptions),
			Repr(newValue.MaxParts, reprOptions),
			Repr(newValue.RespectCanCollide, reprOptions)
		)
	end;
	Path2DControlPoint = function(newValue: Path2DControlPoint, reprOptions)
		return `Path2DControlPoint.new({Repr(newValue.Position, reprOptions)}, {Repr(newValue.LeftTangent, reprOptions)}, {Repr(
			newValue.RightTangent,
			reprOptions
		)})`
	end;
	RotationCurveKey = function(newValue: RotationCurveKey, reprOptions)
		return `RotationCurveKey.new({IntegerOrFloat(newValue.Time)}, {Repr(newValue.Value, reprOptions)}, {Repr(
			newValue.Interpolation,
			reprOptions
		)})`
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
	local reprOptions: RequiredReprSettings = MergeDeep(DEFAULT_SETTINGS, reprSettings)

	if reprOptions.Tabs then
		CurrentIndent = "\t"
	else
		CurrentIndent = string.rep(" ", reprOptions.Spaces)
	end

	local newValue = value
	local tabs = string.rep(CurrentIndent, depth)

	if depth == 0 then
		Shown = {}
	end

	local typeOf = typeof(value)
	local stringifyOrString = FORMATTERS[typeOf]
	if stringifyOrString then
		return if type(stringifyOrString) == "function"
			then stringifyOrString(value, reprOptions, tabs)
			else stringifyOrString
	end

	return if type(newValue) == typeOf then `<{type(newValue)}>` else `<Roblox:{typeOf}>`
end

return Repr
