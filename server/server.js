/**
 * ANDA AKE — Safety-Critical SAR Alarm Server
 * 
 * Architecture follows Safety-Critical Computer Systems principles:
 * - Acceptance Tests (AT): Validate every alarm payload before broadcast
 * - Heartbeat Watchdog: Detect dead clients via ping/pong
 * - Forward Error Recovery: Pending alarm queue for reconnecting clients
 * - Robust Software: Handle all invalid inputs gracefully without crash
 * - Error Confinement: Single client errors don't affect others
 * 
 * Endpoints:
 *   WS  /ws                    → WebSocket connection for real-time alarms
 *   POST /api/trigger-alarm    → Trigger alarm to all connected clients
 *   GET  /api/pending-alarms   → Polling fallback (Recovery Block alternate)
 *   GET  /api/health           → Server health check
 *   GET  /api/clients          → Connected clients list
 */

const express = require('express');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const { v4: uuidv4 } = require('uuid');

// ============================================================
// Configuration
// ============================================================
const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY || 'anda-ake-secret-key-change-me';
const HEARTBEAT_INTERVAL_MS = 15000;   // 15 seconds between pings
const MAX_MISSED_HEARTBEATS = 3;       // 3 misses = dead client
const PENDING_ALARM_TTL_MS = 300000;   // Keep pending alarms for 5 minutes
const MAX_PENDING_ALARMS = 50;         // Max pending alarms in memory

// ============================================================
// State
// ============================================================
const clients = new Map();        // clientId -> { ws, alive, missedBeats, connectedAt, lastAckAt, deviceInfo }
const pendingAlarms = [];         // Array of { id, payload, timestamp, ackedBy[] }
const alarmHistory = [];          // Last 100 alarms for audit trail
let serverStartTime = Date.now();

// ============================================================
// Express App
// ============================================================
const app = express();
app.use(express.json());

// ============================================================
// Acceptance Test Module (Safety-Critical: Chapter 4)
// 
// "Is this value physically possible?" — Every alarm payload
// must pass these checks before being broadcast to clients.
// ============================================================
function acceptanceTest(payload) {
  const errors = [];

  // AT-1: Required fields exist
  if (!payload.title || typeof payload.title !== 'string' || payload.title.trim().length === 0) {
    errors.push('AT-1 FAIL: title is required and must be non-empty string');
  }
  if (!payload.body || typeof payload.body !== 'string' || payload.body.trim().length === 0) {
    errors.push('AT-2 FAIL: body is required and must be non-empty string');
  }

  // AT-3: Title and body length sanity check
  if (payload.title && payload.title.length > 200) {
    errors.push('AT-3 FAIL: title exceeds 200 characters');
  }
  if (payload.body && payload.body.length > 1000) {
    errors.push('AT-4 FAIL: body exceeds 1000 characters');
  }

  // AT-5: Priority validation
  const validPriorities = ['critical', 'high', 'normal'];
  if (payload.priority && !validPriorities.includes(payload.priority)) {
    errors.push(`AT-5 FAIL: priority must be one of: ${validPriorities.join(', ')}`);
  }

  return {
    passed: errors.length === 0,
    errors
  };
}

// ============================================================
// Authentication Middleware (Robust Software: validate all inputs)
// ============================================================
function authenticateApiKey(req, res, next) {
  const apiKey = req.headers['x-api-key'] || req.query.apiKey;
  if (!apiKey || apiKey !== API_KEY) {
    console.warn(`[AUTH] Rejected request from ${req.ip} — invalid API key`);
    return res.status(401).json({ 
      success: false, 
      error: 'Unauthorized: invalid or missing API key' 
    });
  }
  next();
}

// ============================================================
// REST API Routes
// ============================================================

/**
 * POST /api/trigger-alarm
 * Trigger a nuclear alarm to all connected clients.
 * 
 * Body: { title, body, priority?, mission_id? }
 * Headers: X-API-Key: <api_key>
 */
app.post('/api/trigger-alarm', authenticateApiKey, (req, res) => {
  const payload = req.body;
  
  // Acceptance Test — reject invalid payloads before broadcast
  const atResult = acceptanceTest(payload);
  if (!atResult.passed) {
    console.warn(`[AT] Alarm REJECTED:`, atResult.errors);
    return res.status(400).json({
      success: false,
      error: 'Acceptance Test failed',
      details: atResult.errors
    });
  }

  // Construct alarm message
  const alarm = {
    id: uuidv4(),
    type: 'ALARM',
    payload: {
      title: payload.title.trim(),
      body: payload.body.trim(),
      priority: payload.priority || 'critical',
      mission_id: payload.mission_id || `SAR-${Date.now()}`
    },
    timestamp: Date.now(),
    ackedBy: []
  };

  // Store in pending alarms (for polling fallback — Recovery Block Alternate)
  pendingAlarms.push(alarm);
  if (pendingAlarms.length > MAX_PENDING_ALARMS) {
    pendingAlarms.shift(); // Remove oldest
  }

  // Store in history (audit trail)
  alarmHistory.push({
    ...alarm,
    connectedClientsAtTime: clients.size,
    triggeredBy: req.ip
  });
  if (alarmHistory.length > 100) {
    alarmHistory.shift();
  }

  // Broadcast to all connected WebSocket clients
  let sentCount = 0;
  let failCount = 0;
  const message = JSON.stringify(alarm);

  clients.forEach((client, clientId) => {
    try {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(message);
        sentCount++;
        console.log(`[ALARM] Sent to client ${clientId}`);
      } else {
        failCount++;
        console.warn(`[ALARM] Client ${clientId} not in OPEN state (${client.ws.readyState})`);
      }
    } catch (err) {
      // Error Confinement: one client's error doesn't affect others
      failCount++;
      console.error(`[ALARM] Error sending to ${clientId}:`, err.message);
    }
  });

  console.log(`[ALARM] 🚨 Broadcast complete: ${sentCount} sent, ${failCount} failed, alarm_id=${alarm.id}`);

  res.json({
    success: true,
    alarm_id: alarm.id,
    sent_to: sentCount,
    failed: failCount,
    total_clients: clients.size,
    timestamp: alarm.timestamp
  });
});

/**
 * GET /api/pending-alarms
 * Polling fallback endpoint (Recovery Block: Alternate 1)
 * 
 * Query: ?since=<timestamp> — only return alarms newer than this
 * Headers: X-API-Key: <api_key>
 */
app.get('/api/pending-alarms', authenticateApiKey, (req, res) => {
  const since = parseInt(req.query.since) || 0;
  const now = Date.now();

  // Filter: only alarms newer than 'since' and not expired
  const relevant = pendingAlarms.filter(a => 
    a.timestamp > since && 
    (now - a.timestamp) < PENDING_ALARM_TTL_MS
  );

  res.json({
    success: true,
    alarms: relevant,
    count: relevant.length,
    server_time: now
  });
});

/**
 * POST /api/ack
 * Acknowledge an alarm (client confirms receipt)
 * 
 * Body: { alarm_id, client_id }
 */
app.post('/api/ack', (req, res) => {
  const { alarm_id, client_id } = req.body;

  if (!alarm_id || !client_id) {
    return res.status(400).json({ success: false, error: 'alarm_id and client_id required' });
  }

  const alarm = pendingAlarms.find(a => a.id === alarm_id);
  if (alarm && !alarm.ackedBy.includes(client_id)) {
    alarm.ackedBy.push(client_id);
    console.log(`[ACK] Client ${client_id} acknowledged alarm ${alarm_id}`);
  }

  // Update client's last ack time
  const client = clients.get(client_id);
  if (client) {
    client.lastAckAt = Date.now();
  }

  res.json({ success: true });
});

/**
 * GET /api/health
 * Server health check endpoint
 */
app.get('/api/health', (req, res) => {
  const now = Date.now();
  const uptimeMs = now - serverStartTime;
  
  res.json({
    status: 'ok',
    uptime_seconds: Math.floor(uptimeMs / 1000),
    uptime_human: formatUptime(uptimeMs),
    connected_clients: clients.size,
    pending_alarms: pendingAlarms.filter(a => (now - a.timestamp) < PENDING_ALARM_TTL_MS).length,
    total_alarms_sent: alarmHistory.length,
    heartbeat_interval_ms: HEARTBEAT_INTERVAL_MS,
    server_time: now,
    version: '1.0.0'
  });
});

/**
 * GET /api/clients
 * List connected clients (admin)
 */
app.get('/api/clients', authenticateApiKey, (req, res) => {
  const clientList = [];
  clients.forEach((client, id) => {
    clientList.push({
      id,
      connected_at: client.connectedAt,
      last_ack_at: client.lastAckAt,
      missed_beats: client.missedBeats,
      alive: client.alive,
      device_info: client.deviceInfo
    });
  });

  res.json({
    success: true,
    clients: clientList,
    count: clientList.length
  });
});

// ============================================================
// HTTP Server + WebSocket Server
// ============================================================
const server = http.createServer(app);

const wss = new WebSocketServer({ 
  server,
  path: '/ws'
});

// ============================================================
// WebSocket Connection Handler
// ============================================================
wss.on('connection', (ws, req) => {
  const clientId = uuidv4();
  const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

  // Register client
  clients.set(clientId, {
    ws,
    alive: true,
    missedBeats: 0,
    connectedAt: Date.now(),
    lastAckAt: null,
    deviceInfo: null
  });

  console.log(`[WS] ✅ Client connected: ${clientId} from ${clientIp} (total: ${clients.size})`);

  // Send welcome message with client ID
  ws.send(JSON.stringify({
    type: 'WELCOME',
    client_id: clientId,
    server_time: Date.now(),
    heartbeat_interval_ms: HEARTBEAT_INTERVAL_MS
  }));

  // Handle incoming messages from client
  ws.on('message', (data) => {
    try {
      const message = JSON.parse(data.toString());

      switch (message.type) {
        case 'ACK':
          // Client acknowledges an alarm
          handleAck(clientId, message.alarm_id);
          break;

        case 'REGISTER':
          // Client sends device info
          const client = clients.get(clientId);
          if (client) {
            client.deviceInfo = message.device_info || {};
            console.log(`[WS] Client ${clientId} registered device:`, client.deviceInfo);
          }
          break;

        case 'PONG':
          // Client responds to heartbeat (manual pong for app-level heartbeat)
          const c = clients.get(clientId);
          if (c) {
            c.alive = true;
            c.missedBeats = 0;
          }
          break;

        default:
          console.warn(`[WS] Unknown message type from ${clientId}:`, message.type);
      }
    } catch (err) {
      // Robust Software: don't crash on malformed messages
      console.warn(`[WS] Malformed message from ${clientId}:`, err.message);
    }
  });

  // Handle WebSocket-level pong (protocol-level heartbeat)
  ws.on('pong', () => {
    const client = clients.get(clientId);
    if (client) {
      client.alive = true;
      client.missedBeats = 0;
    }
  });

  // Handle disconnection
  ws.on('close', (code, reason) => {
    clients.delete(clientId);
    console.log(`[WS] ❌ Client disconnected: ${clientId} (code: ${code}, total: ${clients.size})`);
  });

  // Handle errors (Error Confinement: isolate per-client errors)
  ws.on('error', (err) => {
    console.error(`[WS] Error from client ${clientId}:`, err.message);
    clients.delete(clientId);
  });
});

// ============================================================
// Heartbeat Watchdog (Safety-Critical: Chapter 3)
// 
// Every HEARTBEAT_INTERVAL_MS, ping all clients.
// If a client misses MAX_MISSED_HEARTBEATS pongs, terminate it.
// This prevents ghost connections from accumulating.
// ============================================================
const heartbeatInterval = setInterval(() => {
  clients.forEach((client, clientId) => {
    if (!client.alive) {
      client.missedBeats++;

      if (client.missedBeats >= MAX_MISSED_HEARTBEATS) {
        console.warn(`[HEARTBEAT] 💀 Client ${clientId} dead (${client.missedBeats} missed beats) — terminating`);
        client.ws.terminate();
        clients.delete(clientId);
        return;
      }

      console.warn(`[HEARTBEAT] ⚠️ Client ${clientId} missed beat ${client.missedBeats}/${MAX_MISSED_HEARTBEATS}`);
    }

    // Mark as not-alive, wait for pong to set it back
    client.alive = false;

    // Send both protocol-level ping and app-level ping
    try {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.ping();
        client.ws.send(JSON.stringify({ 
          type: 'PING', 
          timestamp: Date.now() 
        }));
      }
    } catch (err) {
      console.error(`[HEARTBEAT] Error pinging ${clientId}:`, err.message);
    }
  });
}, HEARTBEAT_INTERVAL_MS);

// Cleanup expired pending alarms periodically
const cleanupInterval = setInterval(() => {
  const now = Date.now();
  while (pendingAlarms.length > 0 && (now - pendingAlarms[0].timestamp) > PENDING_ALARM_TTL_MS) {
    const removed = pendingAlarms.shift();
    console.log(`[CLEANUP] Expired alarm removed: ${removed.id}`);
  }
}, 60000); // Every minute

// ============================================================
// ACK Handler
// ============================================================
function handleAck(clientId, alarmId) {
  if (!alarmId) return;

  const alarm = pendingAlarms.find(a => a.id === alarmId);
  if (alarm && !alarm.ackedBy.includes(clientId)) {
    alarm.ackedBy.push(clientId);
  }

  const client = clients.get(clientId);
  if (client) {
    client.lastAckAt = Date.now();
  }

  console.log(`[ACK] ✅ Client ${clientId} acknowledged alarm ${alarmId}`);

  // Send ACK confirmation back
  try {
    const c = clients.get(clientId);
    if (c && c.ws.readyState === WebSocket.OPEN) {
      c.ws.send(JSON.stringify({
        type: 'ACK_CONFIRMED',
        alarm_id: alarmId,
        timestamp: Date.now()
      }));
    }
  } catch (err) {
    console.error(`[ACK] Error sending confirmation to ${clientId}:`, err.message);
  }
}

// ============================================================
// Utility Functions
// ============================================================
function formatUptime(ms) {
  const seconds = Math.floor(ms / 1000);
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;
  return `${days}d ${hours}h ${minutes}m ${secs}s`;
}

// ============================================================
// Graceful Shutdown (Safety-Critical: proper resource cleanup)
// ============================================================
function shutdown(signal) {
  console.log(`\n[SERVER] ${signal} received — graceful shutdown...`);

  clearInterval(heartbeatInterval);
  clearInterval(cleanupInterval);

  // Notify all clients
  clients.forEach((client, clientId) => {
    try {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(JSON.stringify({
          type: 'SERVER_SHUTDOWN',
          message: 'Server is shutting down. Reconnect shortly.',
          timestamp: Date.now()
        }));
        client.ws.close(1001, 'Server shutdown');
      }
    } catch (err) {
      // Ignore errors during shutdown
    }
  });

  wss.close(() => {
    server.close(() => {
      console.log('[SERVER] Shutdown complete.');
      process.exit(0);
    });
  });

  // Force exit after 5 seconds
  setTimeout(() => {
    console.error('[SERVER] Forced exit after timeout');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ============================================================
// Start Server
// ============================================================
server.listen(PORT, () => {
  console.log('');
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║     🚨 ANDA AKE — SAR Alarm Server 🚨      ║');
  console.log('║   Safety-Critical WebSocket Architecture     ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  HTTP API:     http://0.0.0.0:${PORT}            ║`);
  console.log(`║  WebSocket:    ws://0.0.0.0:${PORT}/ws           ║`);
  console.log(`║  Heartbeat:    every ${HEARTBEAT_INTERVAL_MS / 1000}s (max ${MAX_MISSED_HEARTBEATS} misses)      ║`);
  console.log(`║  Pending TTL:  ${PENDING_ALARM_TTL_MS / 1000}s                          ║`);
  console.log('╚══════════════════════════════════════════════╝');
  console.log('');
});
