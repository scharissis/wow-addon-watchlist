-- Global saved variable: WL


local LOCKED_N_LOADED = false;
local AH_SHOWING = false;
local timeGranularity = 86400/24; -- 1 day / 24 = 1hr


function Message(message)
	if (message) then
		print(
		LIGHTBLUE_FONT_COLOR:WrapTextInColorCode("WL: ")
		.. message
		)
	end
end

function makeSummaryItem(price)
	price = tonumber(price);
    return {minPrice=price, maxPrice=price, lastPrice=price, lastChecked=time()}
end

function addSummary(itemID, price)
	itemID = tonumber(itemID);
	price = tonumber(price);
	-- Add summary
	if WL.db.summary == nil then
		WL.db.summary = {}
	end
	if WL.db.summary[itemID] == nil then
        WL.db.summary[itemID] = makeSummaryItem(price)
	else
		local min, max = WL.db.summary[itemID].minPrice, WL.db.summary[itemID].maxPrice
		local tmp = makeSummaryItem(price)
		tmp.minPrice = math.min(min, price)
		tmp.maxPrice = math.max(max, price)
		tmp.lastPrice = price
		tmp.lastChecked = time()
		--print(string.format("addSummary(%s,%s): {%s, %s, %s, %s}\n", itemID, price, tmp.minPrice, tmp.maxPrice, tmp.lastPrice, tmp.lastChecked));
		WL.db.summary[itemID] = tmp
	end
end

function makeHistoryItem(price)
	price = tonumber(price);
    return {price=price, ts=time()}
end

function AddToWatchlist(itemID)
	itemID = tonumber(itemID);
	name = C_Item.GetItemNameByID(tostring(itemID));
	if not name or name == "" then
		Message("Error: could not find item with ID '"..itemID.."'.")
		return
	end
	WL.db.watchlist[itemID] = name;
	Message("Added "..itemStr(itemID, name).." to the watchlist.");
end

function AddItemHistory(itemID, price)
	itemID = tonumber(itemID);
	price = tonumber(price);

	addSummary(itemID, price);

	-- Add history
    if WL.db.history[itemID] == nil then
        WL.db.history[itemID] = {makeHistoryItem(price)}
    else
        timeSince = time() - WL.db.history[itemID][#WL.db.history[itemID]].ts
        if timeSince > timeGranularity then
            table.insert(WL.db.history[itemID], makeHistoryItem(price))
        end
	end
	--print("DB.history size: "..table.size(WL.db.history))
	--Message(string.format("Scanned '%s'.", WL.db.watchlist[itemID]));
end

function ScanAH()
	local numScanned = 0;
	for itemID, _ in pairs(WL.db.watchlist) do
		local itemKey = C_AuctionHouse.MakeItemKey(itemID);
		--itemKey.itemLevel = 190;
		--print(string.format("item key: (id: %s, ilvl: %s, suff: %s)", itemKey.itemID, itemKey.itemLevel, itemKey.itemSuffix));
		C_AuctionHouse.SendSearchQuery(itemKey, {}, false);
		numScanned = numScanned + 1;
	end
	Message("Scanned AH for "..table.size(WL.db.watchlist).." watchlisted items.");
end

local f = CreateFrame("Frame", "WatchlistFrame", AuctionHouseFrame);
f:RegisterEvent("ADDON_LOADED");
f:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED");
f:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED");
f:Hide();

function f:OnEvent(event, arg)
	--print("event: "..event..", arg: "..arg or "");
	if event == "ADDON_LOADED" and arg == "Watchlist" then
		if not WL then
			-- First ever addon load; init data structures.
			initWL();
		end
		if WL then
			LOCKED_N_LOADED = true
			Message("Watchlist loaded successfully!");
		end
	elseif event == "PLAYER_LOGOUT" then
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		local itemKey = arg
		for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
			local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i);
			local ilvl = getItemLevel(result.itemLink);
			--print("Completed scan for item "..WL.db.watchlist[itemKey.itemID].." ilvl: "..ilvl)
			AddItemHistory(itemKey.itemID, result.buyoutAmount);
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		local itemID = arg
		for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
			local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i);
			local ilvl = getItemLevel(result.itemID);
			--print("Completed scan for commodity "..WL.db.watchlist[result.itemID]..", quantity: " .. result.quantity .. ", price: ".. result.unitPrice .. ", ilvl: "..  ilvl);
			AddItemHistory(itemID, result.unitPrice);
		end
	elseif event == "AUCTION_HOUSE_SHOW" then
		--print("AUCTION_HOUSE_SHOW...");
	end
end
f:SetScript("OnEvent", f.OnEvent);

-- NB: https://wow.gamepedia.com/API_GetDetailedItemLevelInfo
function getItemLevel(arg)
	if not arg then
		return nil
	end
	local effectiveILvl, isPreview, baseILvl = GetDetailedItemLevelInfo(arg)
	return effectiveILvl
end

-- SLASH CMDs

SLASH_WATCHLIST1 = '/wl';
function SlashCmdList.WATCHLIST(msg, editbox)
	if not LOCKED_N_LOADED then 
		--print("NOT LOCKED AND LOADED!!");
		return
	end
	local _, _, cmd, args = string.find(msg, "%s?(%w+)%s?(.*)"); -- %d ?
	--print("cmd: "..cmd..", args: "..(args or ""));

	if cmd == "show" then
		printWatchlist();
	elseif cmd == "scan" then
		ScanAH();
	elseif cmd == "add" then
		if args == "" then
			Message("Error: provide an item ID. (eg.: /wl add 172438");
		else
			AddToWatchlist(args)
		end
	elseif cmd == "ilvl" then
		getItemLevel(args)
	elseif cmd == "reset" or cmd == "clear" then
		initWL();
	else
		Message("Unknown command.");
	end
end


--
-- UTILS
--

function initWL()
	WL = {
		db = {
			watchlist = {}, -- map[id]name
			summary = {},
			history = {
				-- id -> [{price, ts}]
			}
		}
	};
end
function printWatchlist()
	if table.size(WL.db.watchlist) == 0 then
		Message("Watchlist is empty.");
		return
	end
	Message("WATCHLIST ("..table.size(WL.db.watchlist).."):");
	for itemID, name in pairs(WL.db.watchlist) do
		Message(" - "..itemStr(itemID, name).." = "..priceStr(itemID));
	end
end

function itemStr(itemID, name)
	-- if WL.db.watchlist[itemID]
	-- 	return "?UnknownItem?"
	-- end
	-- name = WL.db.watchlist[itemID]
	return name.." [id: "..itemID.."]"
end

function priceStr(itemID)
	local p = "?g"
	if WL.db.summary[itemID] then
		local min = WL.db.summary[itemID].minPrice;
		local max = WL.db.summary[itemID].maxPrice;
		local last = WL.db.summary[itemID].lastPrice;
		local diff = last/max.."% of max";
		p = string.format("{min: %s, max: %s, last: %s (%s)}", asGoldStr(min), asGoldStr(max), asGoldStr(last), diff);
	end
	return p
end

--
-- UI
--

-- function setupWindow()
-- 	local btnScan = CreateFrame("Button", nil, f, "UIPanelButtonTemplate");
-- 	btnScan:SetPoint("CENTER");
-- 	btnScan:SetSize(120, 40);
-- 	btnScan:SetText("Scan AH");
-- 	btnScan:SetScript("OnClick", function(self, button)
-- 		ScanAH();
-- 	end)
-- 	local btnShow = CreateFrame("Button", nil, f, "UIPanelButtonTemplate");
-- 	btnShow:SetPoint("TOP")
-- 	btnShow:SetSize(120, 40)
-- 	btnShow:SetText("Show DB")
-- 	btnShow:SetScript("OnClick", function(self, button)
-- 		printTable(WL.db);
-- 	end)
-- end
-- setupWindow();

local TAB_NAME_HISTORY = "AuctionFrameTabWatchlistHistory"

function getNumTabs()
	local tabs = 1;
	while ( _G["AuctionFrameTab"..tabs] ) do

		if ( _G["AuctionFrameTab"..tabs]:GetName() == TAB_NAME_HISTORY ) then
			return
		end
		tabs = tabs + 1;
	end
	return tabs
end

function setupTabs()
	local numTabs = getNumTabs()
	local button = CreateFrame("Button", TAB_NAME_HISTORY, AuctionFrame);
	button:SetText(MARKETWATCHER_HISTORY);
	--PanelTemplates_TabResize(button, 0);
	PanelTemplates_DeselectTab(button);

	_G["AuctionFrameTab"..numTabs] = TAB_NAME_HISTORY;

	button = _G["AuctionFrameTab"..numTabs];
	button:SetParent("AuctionFrame");
	button:SetPoint("TOPLEFT", _G["AuctionFrameTab"..(numTabs - 1)]:GetName(), "TOPRIGHT", -8, 0);
	button:SetID(numTabs);
	button:Show();

	PanelTemplates_SetNumTabs(AuctionFrame, numTabs);

	Watchlist_Frame:SetParent(AuctionFrame);
	Watchlist_Frame:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 0, 0);

	hooksecurefunc("AuctionFrameTab_OnClick", history.Tab_OnClick);
	button:SetScript("OnClick", AuctionFrameTab_OnClick);
end

function tabOnClick(self)
	if ( self ) then
		index = self:GetID();
	else
		Watchlist_Frame:Hide();
		return
	end

	local tab = _G["AuctionFrameTab"..index];
	if ( tab and tab:GetName() == TAB_NAME_HISTORY ) then
		PanelTemplates_SetTab(AuctionFrame, index);
		MarketWatcherScanFrame:Hide();

		-- AuctionFrameTopLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopLeft");
		-- AuctionFrameTop:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-Top");
		-- AuctionFrameTopRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-TopRight");
		-- AuctionFrameBotLeft:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Browse-BotLeft");
		-- AuctionFrameBot:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Auction-Bot");
		-- AuctionFrameBotRight:SetTexture("Interface\\AuctionFrame\\UI-AuctionFrame-Bid-BotRight");

		Watchlist_Frame:Show();
	else
		Watchlist_Frame:Hide();
	end
end


  
-- util
function table.size(t)
	local count = 0;
	for _,_ in pairs(t) do
		count = count + 1;
	end
	return count;
end

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

function asGoldStr(n)
	local g = n/10000;
	return g.."g"
end