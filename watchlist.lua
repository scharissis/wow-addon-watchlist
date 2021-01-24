WL = {
	db = {
		watchlist = {172438},
		summary = {},
		history = {
			-- id -> [{price, ts}]
		}
	}
};

local timeGranularity = 0 --86400 -- 1 day


function WL:Message(message)
	if (message) then
		print(
		LIGHTBLUE_FONT_COLOR:WrapTextInColorCode("WL: ")
		.. message
		)
	end
end

function makeSummaryItem(price)
	-- C_Item.GetItemNameByID()
    return {minPrice=price, maxPrice=price, lastPrice=price, lastChecked=time()}
end

function makeHistoryItem(price)
    return {price=price, ts=time()}
end

function AddItem(itemID, price)
	-- Add summary
	if WL.db.summary[itemID] == nil then
        WL.db.summary[itemID] = makeSummaryItem(price)
	else
		min, max, _, _ = WL.db.summary[itemID]
		tmp = makeSummaryItem(price)
		tmp.minPrice = math.min(min, price)
		tmp.maxPrice = math.max(max, price)
		tmp.lastPrice = price
		tmp.lastChecked = time()
		WL.db.summary[itemID] = tmp
	end

	-- Add history
    if WL.db.history[itemID] == nil then
        WL.db.history[itemID] = {makeHistoryItem(price)}
    else
        timeSince = time() - WL.db.history[itemID][#WL.db.history[itemID]].ts
        if timeSince > timeGranularity then
            table.insert(WL.db.history[itemID], makeHistoryItem(price))
        end
	end
	print("DB.history size: "..#WL.db.history)
end

function ScanAH()
	for _, itemID in ipairs(WL.db.watchlist) do
		--local itemID = 172438 --WL.db.watchlist[0]
		local itemKey = C_AuctionHouse.MakeItemKey(itemID)
		C_AuctionHouse.SendSearchQuery(itemKey, {}, false)
	end
end


local test_item = 5956 -- Blacksmith Hammer
local test_commodity = 172438

local f = CreateFrame("Frame");
f:RegisterEvent("ADDON_LOADED");
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED");
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED");

function f:OnEvent(event, arg)
	if WL == nil or event == "ADDON_LOADED" and arg ~= "history" then
		return
	end
	print("event: "..event..", arg: "..arg);
	if event == "ADDON_LOADED" and arg == "history" then
		if not WL == nil then
			WL:Message("Addon loaded.");
		end
	elseif event == "PLAYER_LOGOUT" then
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		itemKey = arg
		for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
			local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
			print(itemKey.itemID, i, result.buyoutAmount)
			AddItem(itemKey.itemID,result.buyoutAmount)
			return
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		itemID = arg
		for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
			local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
			print(itemID, i, result.quantity, result.unitPrice)
			AddItem(itemID, result.unitPrice)
			return
		end
	end
end
f:SetScript("OnEvent", f.OnEvent);

local btnScan = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate");
btnScan:SetPoint("CENTER");
btnScan:SetSize(120, 40);
btnScan:SetText("Scan AH");
btnScan:SetScript("OnClick", function(self, button)
	ScanAH();
end)
local btnShow = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate");
btnShow:SetPoint("TOP")
btnShow:SetSize(120, 40)
btnShow:SetText("Show DB")
btnShow:SetScript("OnClick", function(self, button)
	printTable(WL.db);
end)


  
-- util
function table.val_to_str ( price )
    if "string" == type( price ) then
      price = string.gsub( price, "\n", "\\n" )
      if string.match( string.gsub(price,"[^'\"]",""), '^"+$' ) then
        return "'" .. price .. "'"
      end
      return '"' .. string.gsub(price,'"', '\\"' ) .. '"'
    else
      return "table" == type( price ) and table.tostring( price ) or
        tostring( price )
    end
  end
  
  function table.key_to_str ( k )
    if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
      return k
    else
      return "[" .. table.val_to_str( k ) .. "]"
    end
  end
function table.tostring( tbl )
    local result, done = {}, {}
    for k, price in ipairs( tbl ) do
      table.insert( result, table.val_to_str( price ) )
      done[ k ] = true
    end
    for k, price in pairs( tbl ) do
      if not done[ k ] then
        table.insert( result,
          table.key_to_str( k ) .. "=" .. table.val_to_str( price ) )
      end
    end
    return "{" .. table.concat( result, "," ) .. "}"
end

function printTable(t)
	message(table.tostring(t))
end
