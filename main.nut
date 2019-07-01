/*   This file is part of IndustryConstructor, which is a GameScript for OpenTTD
 *   Copyright (C) 2013  R2dical
 *
 *   This program is free software: you can redistribute it and/or modify
 *   it under the terms of the GNU General Public License as published by
 *   the Free Software Foundation, either version 3 of the License, or
 *   (at your option) any later version.
 *
 *   This program is distributed in the hope that it will be useful,
 *   but WITHOUT ANY WARRANTY; without even the implied warranty of
 *   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *   GNU General Public License for more details.
 *
 *   You should have received a copy of the GNU General Public License
 *   along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

// Objectives

// 1. Maintain functionality but improve script performance
// 2. Extend script functionality into other 'post-map creation' initialization
//     ex. drawing roads between towns?
// 3. Extend script to handle more uses cases -- don't hardcode cargo types
// 4. Reference appropriate documentation for game API calls

// Notes:
// Log levels:
//    static LVL_INFO = 1;           // main info. eg what it is doing
//    static LVL_SUB_DECISIONS = 2;  // sub decisions - eg. reasons for not doing certain things etc.
//    static LVL_DEBUG = 3;          // debug prints - debug prints during carrying out actions



// Imports - wtf does this do
import("util.superlib", "SuperLib", 36);
Result <- SuperLib.Result;
Log <- SuperLib.Log;
Helper <- SuperLib.Helper;
ScoreList <- SuperLib.ScoreList;
Tile <- SuperLib.Tile;
Direction <- SuperLib.Direction;
Town <- SuperLib.Town;
Industry <- SuperLib.Industry;

require("progress.nut");

import("util.MinchinWeb", "MinchinWeb", 6);
SpiralWalker <- MinchinWeb.SpiralWalker;
// https://www.tt-forums.net/viewtopic.php?f=65&t=57903
// SpiralWalker - allows you to define a starting point and walks outward

class IndustryConstructor extends GSController {
    test_counter = 0;
    build_limit = 0;
    town_industry_limit = 4; // set in config
    town_radius = 15; // set in config

    chunk_size = 256; // Change this if Valuate runs out of CPU time


    land_tiles = GSTileList();
    shore_tiles = GSTileList();
    water_tiles = GSTileList();
    eligible_towns = GSTownList();
    eligible_town_tiles = GSTileList();

    eligible_town_id_array = [];

    cluster_node_ids = [];

    ind_type_count = 0; // count of industries in this.ind_type_list, set in industryconstructor.init.
    cargo_paxid = 0; // passenger cargo id, set in industryconstructor.init.

    rawindustry_list = []; // array of raw industry type id's, set in industryconstructor.init.
    rawindustry_list_count = 0; // count of primary industries, set in industryconstructor.init.
    procindustry_list = []; // array of processor industry type id's, set in industryconstructor.init.
    procindustry_list_count = 0; // count of secondary industries, set in industryconstructor.init.
    tertiaryindustry_list = []; // array of tertiary industry type id's, set in industryconstructor.init.
    tertiaryindustry_list_count = 0; // count of tertiary industries, set in industryconstructor.init.

    // user variables
    density_ind_total = 0; // set from settings, in industryconstructor.init. total industries, integer always >= 1
    density_ind_min = 0; // set from settings, in industryconstructor. init.min industry density %, float always < 1.
    density_ind_max = 0; // set from settings, in industryconstructor.init. max industry density %, float always > 1.
    density_raw_prop = 0; // set from settings, in industryconstructor.init. primary industry proportion, float always < 1.
    density_proc_prop = 0; // set from settings, in industryconstructor.init. secondary industry proportion, float always < 1.
    density_tert_prop = 0; // set from settings, in industryconstructor.init. tertiary industry proportion, float always < 1.
    density_raw_method = 0; // set from settings, in industryconstructor.init.
    density_proc_method = 0; // set from settings, in industryconstructor.init.
    density_tert_method = 0; // set from settings, in industryconstructor.init.

    constructor() {
    }
}

// Save function
function IndustryConstructor::Save() {
    return null;
}

// Load function
function IndustryConstructor::Load() {
}

// Program start function
function IndustryConstructor::Start() {
    this.Init();
    //this.BuildIndustry();
}

// Initialization function
function IndustryConstructor::Init() {
    /**
    // Assign PAX cargo id ---- why is this step necessary?
    // - Create cargo list
    local CARGO_LIST = GSCargoList();
    // - Loop for each cargo
    foreach(CARGO_ID in CARGO_LIST) {
        // - Assign passenger cargo ID
        if(GSCargo.GetTownEffect(CARGO_ID) == GSCargo.TE_PASSENGERS) CARGO_PAXID = CARGO_ID;
    }

    // Identify industries by type - primary, secondary, tertiary
    // This is where we will put manual overrides when we get to them
    // Including but not limited to - water based industry, shore based industry
    **/
    foreach(ind_id, value in GSIndustryTypeList()) {
        local ind_name = GSIndustryType.GetName(ind_id);

        if (GSIndustryType.IsRawIndustry(ind_id)) {
            Log.Info(" ~Raw Industry: " + ind_name, Log.LVL_INFO);
            rawindustry_list.push(ind_id);
        } else {
        /*
         * From the API docs:
         *   Industries might be neither raw nor processing. This is usually the
         *   case for industries which produce nothing (e.g. power plants), but
         *   also for weird industries like temperate banks and tropic lumber
         *   mills.
         */
            if (GSIndustryType.IsProcessingIndustry(ind_id)) {
                Log.Info(" ~Processor Industry: " + ind_name, Log.LVL_INFO);
                procindustry_list.push(ind_id);
            }
            else {
                Log.Info(" ~Tertiary Industry: " + ind_name, Log.LVL_INFO);
                tertiaryindustry_list.push(ind_id);
            }
        }
    }

    // Import settings
    /**
    // - Assign settings
    local raw_count = GSController.GetSetting("raw_count");
        if(rawindustry_list_count < 1) raw_prop = 0;
    local proc_count = GSController.GetSetting("proc_count").tofloat();
        if(procindustry_list_count < 1) proc_prop = 0;
    local tert_count = GSController.GetSetting("tert_count").tofloat();
        if(tertiaryindustry_list_count < 1) tert_prop = 0;
    **/
    // Preprocess map
    MapPreprocess();
    eligible_towns = GSTownList();
    eligible_town_tiles = BuildEligibleTownTiles();
    BuildEligibleTowns();
    /**
    while(true) {
        test_counter++;
        TownBuildMethod(2);
        //DiagnosticTileMap(eligible_town_tiles);
        //Print("---");
        Print(test_counter);
    }
    **/

}

// Map preprocessor
// Creates data for all tiles on the map
function IndustryConstructor::MapPreprocess() {
    Print("Building map tile list.");
    local all_tiles = GSTileList();
    all_tiles.AddRectangle(GSMap.GetTileIndex(1, 1),
                           GSMap.GetTileIndex(GSMap.GetMapSizeX() - 2,
                                              GSMap.GetMapSizeY() - 2));
    Print("Map list size: " + all_tiles.Count());
    local chunks = (GSMap.GetMapSizeX() - 2) * (GSMap.GetMapSizeY() - 2) / (chunk_size * chunk_size);
    Print("Loading " + chunks + " chunks:");
    // Hybrid approach:
    // Break the map into chunk_size x chunk_size chunks and valuate on each of them
    local progress = ProgressReport(chunks);
    for(local y = 1; y < GSMap.GetMapSizeY() - 1; y += chunk_size) {
        for(local x = 1; x < GSMap.GetMapSizeX() - 1; x += chunk_size) {
            local chunk_land = GetChunk(x, y);
            local chunk_shore = GetChunk(x, y);
            local chunk_water = GetChunk(x, y);
            chunk_land.Valuate(GSTile.IsCoastTile);
            chunk_land.KeepValue(0);
            chunk_land.Valuate(GSTile.IsWaterTile);
            chunk_land.KeepValue(0);
            chunk_shore.Valuate(GSTile.IsCoastTile);
            chunk_shore.KeepValue(1);
            chunk_water.Valuate(GSTile.IsWaterTile);
            chunk_water.KeepValue(1);
            land_tiles.AddList(chunk_land);
            shore_tiles.AddList(chunk_shore);
            water_tiles.AddList(chunk_water);
            if(progress.Increment()) {
                Print(progress);
            }
        }
    }

    Print("Land tile list size: " + land_tiles.Count());
    Print("Shore tile list size: " + shore_tiles.Count());
    Print("Water tile list size: " + water_tiles.Count());
}

// Returns the map chunk with x, y in the upper left corner
// i.e. GetChunk(1, 1) will give you (1, 1) to (257, 257)
function IndustryConstructor::GetChunk(x, y) {
    local chunk = GSTileList();
    chunk.AddRectangle(GSMap.GetTileIndex(x, y),
                       GSMap.GetTileIndex(min(x + 256, GSMap.GetMapSizeX() - 2),
                                          min(y + 256, GSMap.GetMapSizeY() - 2)));
    return chunk;
}

// Go through each town and identify every valid tile_id (do we have a way to ID the town of a tile?)
function IndustryConstructor::BuildEligibleTownTiles() {

    /*
    1. get every town
    2. get every tile in every town
    3. cull based on config parameters
     */
    Print("Building town tile list.");
    local town_list = GSTownList();
    town_list.Valuate(GSTown.GetLocation);
    local all_town_tiles = GSTileList();
    local progress = ProgressReport(town_list.Count());
    foreach(town_id, tile_id in town_list) {
        local local_town_tiles = RectangleAroundTile(tile_id, town_radius);
        foreach(tile, value in local_town_tiles) {
            if(!all_town_tiles.HasItem(tile)) {
                all_town_tiles.AddTile(tile);
            }
        }
        if(progress.Increment()) {
            Print(progress);
        }
    }
    Print("Town tile list size: " + all_town_tiles.Count());
    return all_town_tiles;
}


function IndustryConstructor::BuildEligibleTowns() {
    foreach(town_id, value in eligible_towns) {
        eligible_town_id_array.push(town_id);
    }
}

// Fetch eligible tiles belonging to the town with the given ID
function IndustryConstructor::GetEligibleTownTiles(town_id) {
    if(!eligible_towns.HasItem(town_id)) {
        return null;
    }
    local town_tiles = RectangleAroundTile(GSTown.GetLocation(town_id), town_radius);
    // now do a comparison between tiles in town_tiles and eligible_town_tiles
    local local_eligible_tiles = GSTileList();
    foreach(tile_id, value in town_tiles) {
        if(eligible_town_tiles.HasItem(tile_id)) {
            local_eligible_tiles.AddItem(tile_id, value);
        }
    }
    return local_eligible_tiles;
}

// Builds industries in the order of their IDs
function IndustryConstructor::BuildIndustry() {
    // Display status msg
    Log.Info("+==============================+", Log.LVL_INFO);
    Log.Info("Building industries...", Log.LVL_INFO);

    // Iterate through the list of all industries
    Log.Info(" ~Building " + BUILD_TARGET + " " + GSIndustryType.GetName(CURRENT_IND_ID), Log.LVL_SUB_DECISIONS);

    foreach(industry_id in GSIndustryTypeList) {
        build_method = LookupIndustryBuildMethod(industry_id);
        for(local i = 0; i < BUILD_TARGET; i++) {
            // Build
            switch(build_method) {
                case 1:
                    // Increment count using town build
                    CURRENT_BUILD_COUNT += TownBuildMethod(CURRENT_IND_ID);
                    break;
                case 2:
                    // Increment count using cluster build
                    CURRENT_BUILD_COUNT += ClusterBuildMethod(CURRENT_IND_ID);
                    break;
                case 3:
                    // Increment count using scatter build
                    CURRENT_BUILD_COUNT += ScatteredBuildMethod(CURRENT_IND_ID);
                    break;
            this.ErrorHandler();
            }
            // Display status
            Log.Info(" ~Built " + CURRENT_BUILD_COUNT + " / " + BUILD_TARGET, Log.LVL_SUB_DECISIONS);
        }
    }
}


// Town build method function
// return 1 if built and 0 if not
function IndustryConstructor::TownBuildMethod(INDUSTRY_ID) {

    local ind_name = GSIndustryType.GetName(INDUSTRY_ID);


    // Check if the list is not empty
    if(eligible_towns.IsEmpty() == true) {
        Log.Error(" ~IndustryConstructor.TownBuildMethod: No more eligible towns.", Log.LVL_INFO);
        return 0;
    }

    local town_id = eligible_towns[GSBase.RandRange(eligible_towns.Count())];
    // Debug msg
    Log.Info("   ~Trying to build in " + GSTown.GetName(town_id), Log.LVL_DEBUG);
    local eligible_tiles = this.GetEligibleTownTiles(town_id);

    // For each tile in the town tile list, try to build in one of them randomly
    // - Maintain spacing as given by config file
    // - Once built, remove the tile ID from the global eligible tile list
    // - Two checks at the end:
    //    - Check for town industry limit here and cull from eligible_towns if this puts it over the limit
    //    - Check if the town we just built in now no longer has any eligible tiles
    foreach(tile_id in eligible_tiles) {
        // Remove from global eligible tile list
        local build_success = GSIndustryType.BuildIndustry(industry_id, tile_id);
        if(build_success) {
            // 1. Check town industry limit and remove town from global eligible town list if so
            // 2. Check if town has any eligible tiles left in it from the global eligible tile list
            return 1;
        }
    }
    // Remove town from global eligible town list -- all tiles exhausted
    Log.Error("IndustryConstructor.TownBuildMethod: Town exhausted.", Log.LVL_INFO)
    return 0;
}

// Cluster build method function (2), return 1 if built and 0 if not
function IndustryConstructor::ClusterBuildMethod(INDUSTRY_ID) {

    // Variables
    local IND_NAME = GSIndustryType.GetName(INDUSTRY_ID);            // Industry name string
    local LIST_VALUE = 0; // The point on the list surrently, to synchronise between lists
    local NODE_TILE = null;
    local MULTI = 0;
    local IND = null;
    local IND_DIST = 0;


    // Loop until suitable node
    while(SEARCH_TRIES > 0 && NODEGOT == false) {
        // Increment and check counter
        SEARCH_TRIES--
        if(SEARCH_TRIES == 0) {
            Log.Error("IndustryConstructor.ClusterBuildMethod: Couldn't find a valid tile to set node on!", Log.LVL_INFO)
            return 0
        }
        // Get a random tile
        NODE_TILE = Tile.GetRandomTile();

        // Is buildable
        if(GSTile.IsBuildable(NODE_TILE) == false) continue;


        // Check dist from edge

        // Check dist from town

        //Check dist from ind
        // - Get industry
        IND = this.GetClosestIndustry(NODE_TILE);
        // - If not null (null - no indusrties)
        if(IND != null) {
            // - Get distance
            IND_DIST = GSIndustry.GetDistanceManhattanToTile(IND,NODE_TILE);
            // - If less than minimum, re loop
            if(IND_DIST < (GSController.GetSetting("CLUSTER_MIN_IND") * MULTI)) continue;
        }

        // Check dist from other clusters
        NODEMATCH = false;
        // - Check if node list has entries
        if (CLUSTERNODE_LIST_IND.len() > 0) {
        //    // - Loop through node list
            for(local i = 0; i < CLUSTERTILE_LIST.len(); i++) {
        //        // - If below min dist, then set match and end
                if(GSTile.GetDistanceManhattanToTile(NODE_TILE,CLUSTERTILE_LIST[i]) < GSController.GetSetting("CLUSTER_MIN_NODE")) {
                    NODEMATCH = true;
                    break;
                }
            }
        }
        // - Check if match, and continue if true
        if(NODEMATCH == true) continue;
    //    Log.Info("node fine", Log.LVL_INFO)

        // Add to node list
        CLUSTERNODE_LIST_IND.push(INDUSTRY_ID);
        CLUSTERNODE_LIST_COUNT.push(0);
        CLUSTERTILE_LIST.push(NODE_TILE);
        LIST_VALUE = CLUSTERTILE_LIST.len() - 1;
        NODEGOT = true;
    }
    // Get tile to build industry on
    local TILE_ID = null;
    // Build tries defines the area to build on, and the first try is the first node. Therefore the tries should be the square of
    // the max distance parameter times the number of industries.
    local BUILD_TRIES = (GSController.GetSetting("CLUSTER_RADIUS_MAX") * GSController.GetSetting("CLUSTER_RADIUS_MAX") * GSController.GetSetting("CLUSTER_NODES")).tointeger();
    //Log.Info("Build tries: " + BUILD_TRIES, Log.LVL_INFO)
    // - Create spiral walker
    local SPIRAL_WALKER = SpiralWalker();
    // - Set spiral walker on node tile
    SPIRAL_WALKER.Start(NODE_TILE);
    // Debug sign
    if(GSGameSettings.GetValue("log_level") >= 4) GSSign.BuildSign(NODE_TILE,"Node tile: " + GSIndustryType.GetName (INDUSTRY_ID));

    // Loop till built
    while(BUILD_TRIES > 0) {

        // Walk one tile
        SPIRAL_WALKER.Walk();
        // Get tile
        TILE_ID = SPIRAL_WALKER.GetTile();

        // Check dist from ind
        // - Get industry
        IND = this.GetClosestIndustry(TILE_ID);
        // - If not null (null - no indusrties)
        if(IND != null) {
            // - Get distance
            IND_DIST = GSIndustry.GetDistanceManhattanToTile(IND,TILE_ID);
            // - If less than minimum, re loop
            if(IND_DIST < (GSController.GetSetting("CLUSTER_RADIUS_MIN") * MULTI)) continue;
            // - If more than maximum, re loop
            //if(IND_DIST > (GSController.GetSetting("CLUSTER_RADIUS_MAX") * MULTI)) continue;
        }

        // Try build
        if (GSIndustryType.BuildIndustry(INDUSTRY_ID, TILE_ID) == true) {
            CLUSTERNODE_LIST_COUNT[LIST_VALUE]++
            return 1;
        }

        // Increment and check counter
        BUILD_TRIES--
        if(BUILD_TRIES == ((256 * 256 * 2.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == ((256 * 256 * 1.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == ((256 * 256 * 0.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == 0) {
            Log.Error("IndustryConstructor.ClusterBuildMethod: Couldn't find a valid tile to build on!", Log.LVL_INFO)
        }
    }
    Log.Error("IndustryConstructor.ClusterBuildMethod: Build failed!", Log.LVL_INFO)
    return 0;
}

// Scattered build method function (3), return 1 if built and 0 if not
function IndustryConstructor::ScatteredBuildMethod(INDUSTRY_ID) {
    local IND_NAME = GSIndustryType.GetName(INDUSTRY_ID); // Industry name string
    local TILE_ID = null;
    local BUILD_TRIES = ((256 * 256 * 3) * MAP_SCALE).tointeger();
    local TOWN_DIST = 0;
    local IND = null;
    local IND_DIST = 0;
    local MULTI = 0;

    // Loop until correct tile
    while(BUILD_TRIES > 0) {
        // Get a random tile
        TILE_ID = Tile.GetRandomTile();

        // Check dist from town
        // - Get distance to town
        TOWN_DIST = GSTown.GetDistanceManhattanToTile(GSTile.GetClosestTown(TILE_ID),TILE_ID);
        // - If less than minimum, re loop
        if(TOWN_DIST < (GSController.GetSetting("SCATTERED_MIN_TOWN") * MULTI)) continue;

        // Check dist from ind
        // - Get industry
        IND = this.GetClosestIndustry(TILE_ID);
        // - If not null (null - no indusrties)
        if(IND != null) {
            // - Get distance
            IND_DIST = GSIndustry.GetDistanceManhattanToTile(IND,TILE_ID);
            // - If less than minimum, re loop
            if(IND_DIST < (GSController.GetSetting("SCATTERED_MIN_IND") * MULTI)) continue;
        }

        // Try build
        if (GSIndustryType.BuildIndustry(INDUSTRY_ID, TILE_ID) == true) return 1;

        // Increment and check counter
        BUILD_TRIES--
        if(BUILD_TRIES == ((256 * 256 * 2.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == ((256 * 256 * 1.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == ((256 * 256 * 0.5) * MAP_SCALE).tointeger()) Log.Warning(" ~Tries left: " + BUILD_TRIES, Log.LVL_INFO);
        if(BUILD_TRIES == 0) {
            Log.Error("IndustryConstructor.ScatteredBuildMethod: Couldn't find a valid tile!", Log.LVL_INFO)
        }
    }
    Log.Error("IndustryConstructor.ScatteredBuildMethod: Build failed!", Log.LVL_INFO)
    return 0;
}

/*
Helper functions
 */

// Custom get closest industry function
function IndustryConstructor::GetClosestIndustry(TILE) {
    // Create a list of all industries
    local IND_LIST = GSIndustryList();

    // If count is 0, return null
    if(IND_LIST.Count() == 0) return null;

    // Valuate by distance from tile
    IND_LIST.Valuate(GSIndustry.GetDistanceManhattanToTile, TILE);

    // Sort smallest to largest
    IND_LIST.Sort(GSList.SORT_BY_VALUE, GSList.SORT_ASCENDING);

    // Return the top one
    return IND_LIST.Begin();
}

// Min/Max X/Y list function, returns a 4 tile list with X Max, X Min, Y Max, Y Min, or blank list on fail.
// If second param is == true, returns a 2 tile list with XY Min and XY Max, or blank list on fail.
function IndustryConstructor::ListMinMaxXY(tile_list, two_tile) {
    // Squirrel is pass-by-reference
    local local_list = GSList();
    local_list.AddList(tile_list);
    local_list.Valuate(GSMap.IsValidTile);
    local_list.KeepValue(1);

    if local_list.IsEmpty() {
        return null;
    }

    local_list.Valuate(GSMap.GetTileX);
    local_list.Sort(GSList.SORT_BY_VALUE, false);
    x_max_tile = local_list.Begin();
    local_list.Sort(GSList.SORT_BY_VALUE, true);
    x_min_tile = local_list.Begin();

    local_list.Valuate(GSMap.GetTileY);
    local_list.Sort(GSList.SORT_BY_VALUE, false);
    y_max_tile = local_list.Begin();
    local_list.Sort(GSList.SORT_BY_VALUE, true);
    y_min_tile = local_list.Begin();

    local output_tile_list = GSTileList();

    if(two_tile) {
        local x_min = GSMap.GetTileX(x_min_tile);
        local x_max = GSMap.GetTileX(x_max_tile);
        local y_min = GSMap.GetTileY(y_min_tile);
        local y_max = GSMap.GetTileY(y_max_tile);
        output_tile_list.AddTile(GSMap.GetTileIndex(x_min, y_min));
        output_tile_list.AddTile(GSMap.GetTileIndex(x_max, y_max));
    } else {
        output_tile_list.AddTile(x_max_tile);
        output_tile_list.AddTile(x_min_tile);
        output_tile_list.AddTile(y_max_tile);
        output_tile_list.AddTile(y_min_tile);
    }
    return output_tile_list;
}

// Function to check if tile is industry, returns true or false
function IsIndustry(tile_id) {return (GSIndustry.GetIndustryID(tile_id) != 65535);}

// Function to valuate town by dist from edge
function GetTownDistFromEdge(town_id) {
    return GSMap.DistanceFromEdge(GSTown.GetLocation(town_id));
}

// Helper function
// Given a tile, returns true if the nearest industry is further away than
// TOWN_MIN_IND as defined in config (minimum spacing between town and industry)
function IndustryConstructor::FarFromIndustry(tile_id) {
    if(this.GetClosestIndustry(tile_id) == null) {
        return 1; // null case - no industries on map
    }
    local ind_distance = GSIndustry.GetDistanceManhattanToTile(this.GetClosestIndustry(tile_id), tile_id);
    return ind_distance > (GSController.GetSetting("TOWN_MIN_IND") * MULTI);
}
