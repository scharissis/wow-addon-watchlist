-- Global saved variable: WL

local DENUG = true;
local AH_SHOWING = false;
local TIME_WINDOW = 86400/24; -- 1 day / 24 = 1hr


function makeSummaryItem(price)
	price = tonumber(price);
    return {minPrice=price, maxPrice=price, lastPrice=price, lastChecked=time()}
end

function addSummary(itemID, itemLevel, price)
	itemID = tonumber(itemID);
	price = tonumber(price);

	-- Add summary
	local db = getDB();
	local summary = db.summary;
	if summary == nil then
		summary = {};
	end
	if summary[itemID] == nil then
		summary[itemID] = {};
	end
	if summary[itemID][itemLevel] == nil then
        summary[itemID][itemLevel] = makeSummaryItem(price)
	else
		local min, max = summary[itemID][itemLevel].minPrice, summary[itemID][itemLevel].maxPrice
		local tmp = makeSummaryItem(price)
		tmp.minPrice = math.min(min, price)
		tmp.maxPrice = math.max(max, price)
		tmp.lastPrice = price
		tmp.lastChecked = time()
		--print(string.format("addSummary(%s,%s): {%s, %s, %s, %s}\n", itemID, price, tmp.minPrice, tmp.maxPrice, tmp.lastPrice, tmp.lastChecked));
		summary[itemID][itemLevel] = tmp
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
	local db = getDB();
	db.watchlist[itemID] = name;
	Message("Added "..itemStr(itemID, name).." to the watchlist.");
end

function AddItemHistory(itemID, itemLevel, price)
	local itemID = tonumber(itemID);
	local price = tonumber(price);

	addSummary(itemID, itemLevel, price);

	-- Add history
	local db = getDB();
	if db.history[itemID] == nil then
		db.history[itemID] = {}
	end
    if db.history[itemID][itemLevel] == nil then
        db.history[itemID][itemLevel] = {makeHistoryItem(price)}
    else
        timeSince = time() - db.history[itemID][itemLevel][#db.history[itemID][itemLevel]].ts
        if timeSince > TIME_WINDOW then
            table.insert(db.history[itemID][itemLevel], makeHistoryItem(price))
        end
	end
	--print("DB.history size: "..table.size(db.history))
	--Message(string.format("Scanned '%s'.", db.watchlist[itemID][itemLevel]));
end

function ScanAH()
	local db = getDB();
	local numScanned = 0;
	for itemID, _ in pairs(db.watchlist) do
		local itemKey = C_AuctionHouse.MakeItemKey(itemID);
		C_AuctionHouse.SendSearchQuery(itemKey, {}, false);
		numScanned = numScanned + 1;
	end
	Message("Scanned AH for "..table.size(db.watchlist).." watchlisted items.");
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
			init();
		else
			if not WL[getServer()] then
				--- First load of addon on this server
				initDB();
				Message('Login on a new server detected! Created a new database.');
			end
		end
	elseif event == "PLAYER_LOGOUT" then
	elseif event == "ITEM_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		local db = getDB();
		local itemKey = arg;
		for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
			local result = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i);
			local itemLevel = getItemLevel(result.itemLink);
			-- print("Completed scan for item "..db.watchlist[itemKey.itemID] ..", quantity: " .. result.quantity ..", ilvl: "..ilvl)
			AddItemHistory(itemKey.itemID, itemLevel, result.buyoutAmount);
		end
	elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" and WL ~= nil then
		local db = getDB();
		local itemID = arg;
		for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
			local result = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i);
			local itemLevel = getItemLevel(result.itemID);
			-- print("Completed scan for commodity "..db.watchlist[result.itemID]..", quantity: " .. result.quantity .. ", price: ".. result.unitPrice .. ", ilvl: "..  ilvl);
			AddItemHistory(itemID, itemLevel, result.unitPrice);
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
	-- if not LOCKED_N_LOADED then 
	-- 	--print("NOT LOCKED AND LOADED!!");
	-- 	return
	-- end
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
	elseif cmd == "clear" then
		initDB(getServer);
	elseif cmd == "reset" then
		initWL();
	else
		Message("Unknown command.");
	end
end


--
-- UTILS
--

function init()
	initWL();
	initDB();
	Message("Watchlist loaded successfully!");
end

function initWL()
	local server = getServer();
	WL = {};
	WL[server] = {};
	initDB();
end

function initDB(server)
	if not server then
		server = getServer()
	end
	if not WL[server] then
		WL[server] = {};
	end
	WL[server]['db'] = {
		watchlist = {}, -- map[id]name
		summary = {},
		history = {
			-- id -> [{price, ts}]
		}
	};
end

function getServer()
	local server = GetRealmName();
	return server;
end

function getDB()
	local server = getServer();
	local db = WL[server]['db'];
	return db;
end

function printWatchlist()
	local db = getDB();
	if table.size(db.watchlist) == 0 then
		Message("Watchlist is empty.");
		return
	end
	Message("WATCHLIST ("..table.size(db.watchlist).."):");
	for itemID, name in pairs(db.watchlist) do
		if not db.summary[itemID] then
			Message(name.." = ?g (unscanned)");
		else
			if table.size(db.summary[itemID]) == 1 then
				local itemLevel = table.getKeys(db.summary[itemID])[1];
				Message(string.format("%s (%s) = %s", name, itemLevel, priceStr(itemID, itemLevel)));
			else
				Message(itemStr(itemID, name, nil)..":");
				for itemLevel, summary in pairs(db.summary[itemID]) do
					Message("  - "..itemStr(nil, name, itemLevel).." = "..priceStr(itemID, itemLevel));
				end
			end
		end
	end
end

function itemStr(itemID, name, itemLevel)
	if not itemLevel then
		return name.." [id: "..itemID.."]"
	end
	if not itemID then
		return name.." ("..itemLevel..")"
	end
	return name
end

function priceStr(itemID, itemLevel)
	local db = getDB();
	local p = "?g"
	if db.summary[itemID][itemLevel] then
		local min = db.summary[itemID][itemLevel].minPrice;
		local max = db.summary[itemID][itemLevel].maxPrice;
		--local last = db.summary[itemID][itemLevel].lastPrice;
		--local diff = (last/max)*100.0 .. "% of max";
		p = string.format("{min: %s, max: %s}", asGoldStr(min), asGoldStr(max));
	end
	return p
end

function Message(message)
	if (message) then
		print(LIGHTBLUE_FONT_COLOR:WrapTextInColorCode("WL: ") .. message)
	end
end

function table.getKeys(t)
	local keyset={}
	local n=0
	for k,v in pairs(t) do
		n=n+1
		keyset[n]=k
	end
	return keyset
end

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