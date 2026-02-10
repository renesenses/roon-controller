"use strict";

const RoonApi          = require("node-roon-api");
const RoonApiTransport = require("node-roon-api-transport");
const RoonApiBrowse    = require("node-roon-api-browse");
const RoonApiImage     = require("node-roon-api-image");
const RoonApiStatus    = require("node-roon-api-status");
const express          = require("express");
const http             = require("http");
const { WebSocketServer } = require("ws");
const path             = require("path");
const fs               = require("fs");

// ─── Configuration ──────────────────────────────────────────────────────────
const PORT = process.env.PORT || 3333;
const CONFIG_DIR = path.join(__dirname, "config");

if (!fs.existsSync(CONFIG_DIR)) {
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
}

// ─── State ──────────────────────────────────────────────────────────────────
let core = null;
let transport = null;
let browse = null;
let image = null;
let zones = {};
let reconnectTimer = null;

// ─── Roon API Setup ────────────────────────────────────────────────────────
const roon = new RoonApi({
    extension_id:    "com.bertrand.rooncontroller",
    display_name:    "Roon Controller macOS",
    display_version: "1.0.0",
    publisher:       "Bertrand",
    email:           "",

    core_paired: function(paired_core) {
        core = paired_core;
        transport = core.services.RoonApiTransport;
        browse    = core.services.RoonApiBrowse;
        image     = core.services.RoonApiImage;

        console.log("[Roon] Core paired:", core.display_name, core.display_version);
        broadcastState("connected");

        if (reconnectTimer) {
            clearInterval(reconnectTimer);
            reconnectTimer = null;
        }

        transport.subscribe_zones(function(cmd, data) {
            if (cmd === "Subscribed") {
                zones = {};
                if (data.zones) {
                    data.zones.forEach(z => { zones[z.zone_id] = z; });
                }
                broadcastMessage({ type: "zones", zones: Object.values(zones) });
            } else if (cmd === "Changed") {
                if (data.zones_changed) {
                    data.zones_changed.forEach(z => { zones[z.zone_id] = z; });
                }
                if (data.zones_added) {
                    data.zones_added.forEach(z => { zones[z.zone_id] = z; });
                }
                if (data.zones_removed) {
                    data.zones_removed.forEach(id => { delete zones[id]; });
                }
                if (data.zones_seek_changed) {
                    data.zones_seek_changed.forEach(z => {
                        if (zones[z.zone_id]) {
                            zones[z.zone_id].seek_position = z.seek_position;
                            if (z.queue_time_remaining !== undefined) {
                                zones[z.zone_id].queue_time_remaining = z.queue_time_remaining;
                            }
                        }
                    });
                }
                broadcastMessage({ type: "zones_changed", zones: Object.values(zones) });
            } else if (cmd === "SubscriptionStopped") {
                zones = {};
            }
        });

        transport.subscribe_zones(function(cmd, data) {
            if (cmd === "Subscribed" || cmd === "Changed") {
                // Seek updates come through zone changes
            }
        }, 1); // second subscription for seek
    },

    core_unpaired: function(unpaired_core) {
        console.log("[Roon] Core unpaired");
        core = null;
        transport = null;
        browse = null;
        image = null;
        zones = {};
        broadcastState("disconnected");
        broadcastMessage({ type: "zones", zones: [] });
        startReconnect();
    },

    set_persisted_state: function(state) {
        try {
            fs.writeFileSync(
                path.join(CONFIG_DIR, "roon-state.json"),
                JSON.stringify(state, null, 2)
            );
        } catch (e) {
            console.error("[Config] Failed to save state:", e.message);
        }
    },

    get_persisted_state: function() {
        try {
            const data = fs.readFileSync(path.join(CONFIG_DIR, "roon-state.json"), "utf8");
            return JSON.parse(data);
        } catch (e) {
            return {};
        }
    }
});

const roonStatus = new RoonApiStatus(roon);

roon.init_services({
    required_services: [RoonApiTransport, RoonApiBrowse, RoonApiImage],
    provided_services: [roonStatus]
});

roonStatus.set_status("Ready", false);

// ─── Express HTTP Server ────────────────────────────────────────────────────
const app = express();
const server = http.createServer(app);

app.use((req, res, next) => {
    res.header("Access-Control-Allow-Origin", "*");
    res.header("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.header("Access-Control-Allow-Headers", "Content-Type");
    next();
});

// Image proxy endpoint
app.get("/api/image/:key", (req, res) => {
    if (!image) {
        return res.status(503).json({ error: "Roon core not connected" });
    }

    const key = req.params.key;
    const opts = {
        scale:  req.query.scale  || "fit",
        width:  parseInt(req.query.width)  || 300,
        height: parseInt(req.query.height) || 300,
        format: req.query.format || "image/jpeg"
    };

    image.get_image(key, opts, (error, content_type, body) => {
        if (error) {
            console.error("[Image] Error:", error);
            return res.status(500).json({ error: error });
        }
        res.set("Content-Type", content_type);
        res.set("Cache-Control", "public, max-age=86400");
        res.send(body);
    });
});

// Status endpoint
app.get("/api/status", (req, res) => {
    res.json({
        connected: !!core,
        core_name: core ? core.display_name : null,
        core_version: core ? core.display_version : null,
        zone_count: Object.keys(zones).length,
        zones: Object.values(zones).map(z => ({
            zone_id: z.zone_id,
            display_name: z.display_name,
            state: z.state
        })),
        version: "1.0.0"
    });
});

// ─── WebSocket Server ───────────────────────────────────────────────────────
const wss = new WebSocketServer({ server });
const wsClients = new Set();

wss.on("connection", (ws) => {
    console.log("[WS] Client connected");
    wsClients.add(ws);

    // Send current state
    ws.send(JSON.stringify({
        type: "state",
        state: core ? "connected" : "disconnected"
    }));

    // Send current zones
    if (Object.keys(zones).length > 0) {
        ws.send(JSON.stringify({
            type: "zones",
            zones: Object.values(zones)
        }));
    }

    ws.on("message", (raw) => {
        let msg;
        try {
            msg = JSON.parse(raw.toString());
        } catch (e) {
            console.error("[WS] Invalid JSON:", raw.toString());
            return;
        }
        handleWSMessage(ws, msg);
    });

    ws.on("close", () => {
        console.log("[WS] Client disconnected");
        if (ws.__queue_sub) {
            ws.__queue_sub.unsubscribe && ws.__queue_sub.unsubscribe();
            ws.__queue_sub = null;
        }
        wsClients.delete(ws);
    });

    ws.on("error", (err) => {
        console.error("[WS] Error:", err.message);
        wsClients.delete(ws);
    });
});

function broadcastMessage(msg) {
    const data = JSON.stringify(msg);
    for (const ws of wsClients) {
        if (ws.readyState === 1) { // OPEN
            ws.send(data);
        }
    }
}

function broadcastState(state) {
    broadcastMessage({ type: "state", state });
}

// ─── WebSocket Message Handler ──────────────────────────────────────────────
function handleWSMessage(ws, msg) {
    const type = msg.type;

    if (!type) {
        sendError(ws, "Missing message type");
        return;
    }

    switch (type) {
        case "transport/control":
            handleTransportControl(ws, msg);
            break;
        case "transport/seek":
            handleTransportSeek(ws, msg);
            break;
        case "transport/volume":
            handleTransportVolume(ws, msg);
            break;
        case "transport/mute":
            handleTransportMute(ws, msg);
            break;
        case "transport/settings":
            handleTransportSettings(ws, msg);
            break;
        case "transport/subscribe_queue":
            handleSubscribeQueue(ws, msg);
            break;
        case "transport/play_from_here":
            handlePlayFromHere(ws, msg);
            break;
        case "browse/browse":
            handleBrowse(ws, msg);
            break;
        case "browse/load":
            handleBrowseLoad(ws, msg);
            break;
        case "browse/play_search":
            handlePlaySearch(ws, msg);
            break;
        case "core/connect":
            handleCoreConnect(ws, msg);
            break;
        case "get_zones":
            ws.send(JSON.stringify({
                type: "zones",
                zones: Object.values(zones)
            }));
            break;
        default:
            sendError(ws, "Unknown message type: " + type);
    }
}

function handleTransportControl(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const zone_id = msg.zone_id;
    const control = msg.control; // play, pause, playpause, stop, previous, next
    if (!zone_id || !control) return sendError(ws, "Missing zone_id or control");

    transport.control(zone_id, control, (err) => {
        if (err) sendError(ws, "Transport control error: " + err);
    });
}

function handleTransportSeek(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const zone_id = msg.zone_id;
    if (!zone_id) return sendError(ws, "Missing zone_id");

    if (msg.how === "absolute") {
        transport.seek(zone_id, "absolute", msg.seconds, (err) => {
            if (err) sendError(ws, "Seek error: " + err);
        });
    } else {
        transport.seek(zone_id, "relative", msg.seconds, (err) => {
            if (err) sendError(ws, "Seek error: " + err);
        });
    }
}

function handleTransportVolume(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const output_id = msg.output_id;
    const value = msg.value;
    const how = msg.how || "absolute";
    if (!output_id || value === undefined) return sendError(ws, "Missing output_id or value");

    transport.change_volume(output_id, how, value, (err) => {
        if (err) sendError(ws, "Volume error: " + err);
    });
}

function handleTransportMute(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const output_id = msg.output_id;
    const how = msg.how || "toggle"; // mute, unmute, toggle
    if (!output_id) return sendError(ws, "Missing output_id");

    transport.mute(output_id, how, (err) => {
        if (err) sendError(ws, "Mute error: " + err);
    });
}

function handleTransportSettings(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const zone_id = msg.zone_id;
    if (!zone_id) return sendError(ws, "Missing zone_id");

    const settings = {};
    if (msg.shuffle !== undefined) settings.shuffle = msg.shuffle;
    if (msg.loop !== undefined) settings.loop = msg.loop;
    if (msg.auto_radio !== undefined) settings.auto_radio = msg.auto_radio;

    transport.change_settings(zone_id, settings, (err) => {
        if (err) sendError(ws, "Settings error: " + err);
    });
}

function handleSubscribeQueue(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const zone_id = msg.zone_id;
    if (!zone_id) return sendError(ws, "Missing zone_id");

    // Cancel previous queue subscription for this client
    if (ws.__queue_sub) {
        ws.__queue_sub.unsubscribe && ws.__queue_sub.unsubscribe();
        ws.__queue_sub = null;
    }

    const sub = transport.subscribe_queue(zone_id, 100, (response, data) => {
        if (response === "Subscribed" || response === "Changed") {
            if (data && data.items) {
                if (ws.readyState === 1) {
                    ws.send(JSON.stringify({
                        type: "queue",
                        zone_id: zone_id,
                        items: data.items
                    }));
                }
            }
        }
    });
    ws.__queue_sub = sub;
}

function handlePlayFromHere(ws, msg) {
    if (!transport) return sendError(ws, "Transport not available");
    const zone_id = msg.zone_id;
    const queue_item_id = msg.queue_item_id;
    if (!zone_id || queue_item_id === undefined) return sendError(ws, "Missing zone_id or queue_item_id");

    transport.play_from_here(zone_id, queue_item_id, (err) => {
        if (err) sendError(ws, "Play from here error: " + err);
    });
}

function handleBrowse(ws, msg) {
    if (!browse) return sendError(ws, "Browse not available");

    const opts = {
        hierarchy:  msg.hierarchy || "browse",
        multi_session_key: ws.__session_key || undefined
    };
    if (msg.zone_id) opts.zone_or_output_id = msg.zone_id;
    if (msg.item_key) opts.item_key = msg.item_key;
    if (msg.input) opts.input = msg.input;
    if (msg.pop_levels !== undefined) opts.pop_levels = msg.pop_levels;
    if (msg.pop_all) opts.pop_all = true;

    browse.browse(opts, (err, result) => {
        if (err) return sendError(ws, "Browse error: " + err);

        // Load first page only; client can request more via browse/load
        if (result.list && result.list.count > 0) {
            const hierarchy = msg.hierarchy || "browse";
            const sessionKey = ws.__session_key || undefined;
            const PAGE_SIZE = 100;

            browse.load({
                hierarchy: hierarchy,
                multi_session_key: sessionKey,
                offset: 0,
                count: PAGE_SIZE
            }, (lerr, litems) => {
                if (lerr) return sendError(ws, "Browse load error: " + lerr);
                const items = litems.items || [];
                if (ws.readyState === 1) {
                    ws.send(JSON.stringify({
                        type: "browse_result",
                        action: result.action,
                        list: result.list,
                        items: items,
                        offset: 0
                    }));
                }
            });
        } else {
            ws.send(JSON.stringify({
                type: "browse_result",
                action: result.action,
                list: result.list,
                items: [],
                offset: 0
            }));
        }
    });
}

function handleBrowseLoad(ws, msg) {
    if (!browse) return sendError(ws, "Browse not available");

    const opts = {
        hierarchy:  msg.hierarchy || "browse",
        multi_session_key: ws.__session_key || undefined,
        offset: msg.offset || 0,
        count:  msg.count  || 100
    };

    browse.load(opts, (err, result) => {
        if (err) return sendError(ws, "Browse load error: " + err);
        ws.send(JSON.stringify({
            type: "browse_result",
            action: "list",
            list: result.list,
            items: result.items || [],
            offset: result.offset || 0
        }));
    });
}

function handlePlaySearch(ws, msg) {
    if (!browse) return sendError(ws, "Browse not available");
    const zone_id = msg.zone_id;
    const title = msg.title;
    if (!zone_id || !title) return sendError(ws, "Missing zone_id or title");

    const sessionKey = "play_" + ws.__session_key;
    const hierarchy = "browse";
    const base = { hierarchy, multi_session_key: sessionKey, zone_or_output_id: zone_id };

    // Step 1: Reset browse and load root
    browse.browse({ ...base, pop_all: true }, (err) => {
        if (err) return sendError(ws, "Play search error: " + err);
        browse.load({ hierarchy, multi_session_key: sessionKey, offset: 0, count: 20 }, (err, loaded) => {
            if (err) return;
            const rootItems = loaded.items || [];

            // Search might be at root level or inside Library
            let searchItem = rootItems.find(i => i.input_prompt);
            if (searchItem) { doSearch(searchItem); return; }

            const libraryItem = rootItems.find(i => i.title === "Library" || i.title === "Bibliothèque");
            if (!libraryItem) return;

            browse.browse({ ...base, item_key: libraryItem.item_key }, (err) => {
                if (err) return;
                browse.load({ hierarchy, multi_session_key: sessionKey, offset: 0, count: 20 }, (err, libLoaded) => {
                    if (err) return;
                    searchItem = (libLoaded.items || []).find(i => i.input_prompt);
                    if (searchItem) doSearch(searchItem);
                });
            });
        });
    });

    function doSearch(searchItem) {
        browse.browse({ ...base, item_key: searchItem.item_key, input: title }, (err, searchResult) => {
            if (err) return;
            if (!searchResult.list || searchResult.list.count === 0) return;
            browse.load({ hierarchy, multi_session_key: sessionKey, offset: 0, count: 50 }, (err, searchLoaded) => {
                if (err) return;
                const items = searchLoaded.items || [];

                const actionItem = items.find(i => i.hint === "action_list");
                if (actionItem) { playBrowseItem(hierarchy, sessionKey, zone_id, actionItem); return; }

                const category = items.find(i => i.hint === "list" && i.title && /track/i.test(i.title))
                              || items.find(i => i.hint === "list");
                if (!category) return;

                browse.browse({ ...base, item_key: category.item_key }, (err) => {
                    if (err) return;
                    browse.load({ hierarchy, multi_session_key: sessionKey, offset: 0, count: 20 }, (err, catLoaded) => {
                        if (err) return;
                        const trackItem = (catLoaded.items || []).find(i => i.hint === "action_list");
                        if (trackItem) playBrowseItem(hierarchy, sessionKey, zone_id, trackItem);
                    });
                });
            });
        });
    }
}

function playBrowseItem(hierarchy, sessionKey, zone_id, item, depth) {
    depth = depth || 0;
    if (depth > 3) return;

    const base = { hierarchy, multi_session_key: sessionKey, zone_or_output_id: zone_id };

    browse.browse({ ...base, item_key: item.item_key }, (err, result) => {
        if (err) return;
        if (result.action === "message") return; // action executed
        if (!result.list || result.list.count === 0) return;

        browse.load({ hierarchy, multi_session_key: sessionKey, offset: 0, count: 10 }, (err, loaded) => {
            if (err) return;
            const actions = loaded.items || [];

            // Execute a direct action (Play Now, etc.)
            const directAction = actions.find(a => a.hint === "action");
            if (directAction) {
                browse.browse({ ...base, item_key: directAction.item_key }, () => {});
                return;
            }

            // Recurse into nested action_list
            const nextItem = actions.find(a => a.hint === "action_list") || actions[0];
            if (nextItem) playBrowseItem(hierarchy, sessionKey, zone_id, nextItem, depth + 1);
        });
    });
}

function handleCoreConnect(ws, msg) {
    const ip = msg.ip;
    if (!ip) return sendError(ws, "Missing ip");

    console.log("[Roon] Manual connect to:", ip);
    broadcastState("connecting");

    roon.ws_connect({
        host: ip,
        port: 9330,
        onclose: () => {
            console.log("[Roon] Manual connection closed");
            if (core) {
                core = null;
                transport = null;
                browse = null;
                image = null;
                zones = {};
                broadcastState("disconnected");
                broadcastMessage({ type: "zones", zones: [] });
                startReconnect();
            }
        }
    });
}

function sendError(ws, message) {
    console.error("[Error]", message);
    ws.send(JSON.stringify({ type: "error", message }));
}

// ─── Reconnection Logic ────────────────────────────────────────────────────
function startReconnect() {
    if (reconnectTimer) return;
    console.log("[Roon] Starting reconnection attempts...");
    reconnectTimer = setInterval(() => {
        if (!core) {
            console.log("[Roon] Attempting re-discovery...");
            roon.start_discovery();
        } else {
            clearInterval(reconnectTimer);
            reconnectTimer = null;
        }
    }, 5000);
}

// ─── Startup ────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
    console.log(`[Server] HTTP + WebSocket listening on port ${PORT}`);
    console.log(`[Server] Image proxy: http://localhost:${PORT}/api/image/:key`);
    console.log(`[Server] Status:      http://localhost:${PORT}/api/status`);
    console.log(`[Server] WebSocket:   ws://localhost:${PORT}`);
    console.log("");
    console.log("[Roon] Starting discovery...");
    roon.start_discovery();
});

// Assign session keys to WS clients for browse multi-session
let sessionCounter = 0;
wss.on("connection", (ws) => {
    ws.__session_key = "session_" + (++sessionCounter);
});

// Graceful shutdown
process.on("SIGINT", () => {
    console.log("\n[Server] Shutting down...");
    wss.close();
    server.close();
    process.exit(0);
});

process.on("SIGTERM", () => {
    console.log("\n[Server] Shutting down...");
    wss.close();
    server.close();
    process.exit(0);
});
