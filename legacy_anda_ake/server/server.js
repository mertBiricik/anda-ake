/**
 * ANDA AKE — Safety-Critical SAR Alarm Server (with Authentication & Roles)
 * 
 * Architecture follows Safety-Critical Computer Systems principles:
 * - Acceptance Tests (AT): Validate every alarm payload before broadcast
 * - Heartbeat Watchdog: Detect dead clients via ping/pong
 * - Forward Error Recovery: Pending alarm queue for reconnecting clients
 * - Robust Software: Handle all invalid inputs gracefully without crash
 * - Error Confinement: Single client errors don't affect others
 * - Authorization/Security: JWT & Role-based Access Control (MERKEZ, IL_BASKANI, RESCUER)
 */

const express = require('express');
const http = require('http');
const { WebSocketServer, WebSocket } = require('ws');
const { v4: uuidv4 } = require('uuid');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const cors = require('cors');
const { PrismaClient } = require('@prisma/client');

const prisma = new PrismaClient();

// ============================================================
// Configuration
// ============================================================
const PORT = process.env.PORT || 3000;
const JWT_SECRET = process.env.JWT_SECRET || 'anda-ake-super-secret-jwt-key';
const HEARTBEAT_INTERVAL_MS = 15000;   // 15 seconds between pings
const MAX_MISSED_HEARTBEATS = 3;       // 3 misses = dead client
const PENDING_ALARM_TTL_MS = 300000;   // Keep pending alarms for 5 minutes
const MAX_PENDING_ALARMS = 50;         // Max pending alarms in memory

// ============================================================
// State
// ============================================================
// clientId -> { ws, alive, missedBeats, connectedAt, lastAckAt, deviceInfo, user: { id, email, role, province } }
const clients = new Map();        
const pendingAlarms = [];         
let serverStartTime = Date.now();

// ============================================================
// Express App
// ============================================================
const app = express();
app.use(express.json());
app.use(cors());
app.use(express.static('public')); // For Web Admin Panel

// ============================================================
// Acceptance Test Module (Safety-Critical: Chapter 4)
// ============================================================
function acceptanceTest(payload) {
  const errors = [];
  if (!payload.title || typeof payload.title !== 'string' || payload.title.trim().length === 0) {
    errors.push('AT-1 FAIL: title is required and must be non-empty string');
  }
  if (!payload.body || typeof payload.body !== 'string' || payload.body.trim().length === 0) {
    errors.push('AT-2 FAIL: body is required and must be non-empty string');
  }
  if (payload.title && payload.title.length > 200) {
    errors.push('AT-3 FAIL: title exceeds 200 characters');
  }
  if (payload.body && payload.body.length > 1000) {
    errors.push('AT-4 FAIL: body exceeds 1000 characters');
  }
  const validPriorities = ['critical', 'high', 'normal'];
  if (payload.priority && !validPriorities.includes(payload.priority)) {
    errors.push(`AT-5 FAIL: priority must be one of: ${validPriorities.join(', ')}`);
  }
  return { passed: errors.length === 0, errors };
}

// ============================================================
// Authentication Middleware
// ============================================================
function authenticateJWT(req, res, next) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ success: false, error: 'Unauthorized: Missing or invalid token' });
  }

  const token = authHeader.split(' ')[1];
  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      return res.status(403).json({ success: false, error: 'Forbidden: Invalid token' });
    }
    req.user = user;
    next();
  });
}

// ============================================================
// REST API Routes - AUTHENTICATION
// ============================================================

/**
 * POST /api/setup
 * Creates the initial MERKEZ admin if the database is empty.
 */
app.post('/api/setup', async (req, res) => {
  try {
    const userCount = await prisma.user.count();
    if (userCount > 0) {
      return res.status(400).json({ success: false, error: 'Setup already completed. Users exist.' });
    }

    const { email, password, name } = req.body;
    if (!email || !password || !name) {
      return res.status(400).json({ success: false, error: 'email, password, and name are required' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const admin = await prisma.user.create({
      data: { email, password: hashedPassword, name, role: 'MERKEZ' }
    });

    res.json({ success: true, message: 'Initial MERKEZ admin created successfully', user: { id: admin.id, email: admin.email } });
  } catch (error) {
    console.error(error);
    res.status(500).json({ success: false, error: 'Internal Server Error' });
  }
});

/**
 * POST /api/login
 * Authenticates a user and returns a JWT.
 */
app.post('/api/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ success: false, error: 'Email and password required' });

  try {
    const user = await prisma.user.findUnique({ where: { email } });
    if (!user || !user.isActive) {
      return res.status(401).json({ success: false, error: 'Invalid credentials or inactive account' });
    }

    const match = await bcrypt.compare(password, user.password);
    if (!match) {
      return res.status(401).json({ success: false, error: 'Invalid credentials' });
    }

    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role, province: user.province }, 
      JWT_SECRET, 
      { expiresIn: '7d' } // 1 week validity
    );

    res.json({ success: true, token, user: { id: user.id, name: user.name, email: user.email, role: user.role, province: user.province } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

/**
 * GET /api/me
 * Gets the current authenticated user's info
 */
app.get('/api/me', authenticateJWT, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.user.id }, select: { id: true, name: true, email: true, role: true, province: true, isActive: true }});
    res.json({ success: true, user });
  } catch (err) {
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ============================================================
// REST API Routes - USERS (User Management)
// ============================================================

// GET /api/users - List users
app.get('/api/users', authenticateJWT, async (req, res) => {
  try {
    const { role, province } = req.user;
    let users = [];
    if (role === 'MERKEZ') {
      users = await prisma.user.findMany({ select: { id: true, name: true, email: true, role: true, province: true, isActive: true } });
    } else if (role === 'IL_BASKANI' && province) {
      users = await prisma.user.findMany({ where: { province }, select: { id: true, name: true, email: true, role: true, province: true, isActive: true } });
    } else {
      return res.status(403).json({ success: false, error: 'Unauthorized to list users' });
    }
    res.json({ success: true, users });
  } catch (err) {
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// POST /api/users - Create a new user
app.post('/api/users', authenticateJWT, async (req, res) => {
  try {
    const { role, province } = req.user;
    const { name, email, password, role: newRole, province: newProv, phone } = req.body;

    if (role === 'RESCUER') return res.status(403).json({ success: false, error: 'Unauthorized' });
    if (role === 'IL_BASKANI' && (newRole === 'MERKEZ' || newRole === 'IL_BASKANI' || newProv !== province)) {
      return res.status(403).json({ success: false, error: 'Can only create RESCUER for your own province' });
    }

    const existing = await prisma.user.findUnique({ where: { email } });
    if (existing) return res.status(400).json({ success: false, error: 'Email already in use' });

    const hashedPassword = await bcrypt.hash(password, 10);
    const user = await prisma.user.create({
      data: { name, email, password: hashedPassword, role: newRole || 'RESCUER', province: newProv, phone },
      select: { id: true, name: true, email: true, role: true, province: true, phone: true }
    });
    res.json({ success: true, user });
  } catch (err) {
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// DELETE /api/users/:id - Delete a user
app.delete('/api/users/:id', authenticateJWT, async (req, res) => {
  try {
    const { role, province } = req.user;
    const targetId = req.params.id;

    if (role === 'RESCUER') return res.status(403).json({ success: false, error: 'Unauthorized' });

    const targetUser = await prisma.user.findUnique({ where: { id: targetId } });
    if (!targetUser) return res.status(404).json({ success: false, error: 'User not found' });

    if (role === 'IL_BASKANI' && targetUser.province !== province) {
      return res.status(403).json({ success: false, error: 'Unauthorized to delete this user' });
    }

    await prisma.user.delete({ where: { id: targetId } });
    res.json({ success: true, message: 'User deleted' });
  } catch (err) {
    res.status(500).json({ success: false, error: 'Server error' });
  }
});

// ============================================================
// REST API Routes - ALARMS
// ============================================================

app.post('/api/trigger-alarm', authenticateJWT, async (req, res) => {
  const payload = req.body;
  const user = req.user; // User from JWT

  // 1. Authorization checks based on role
  if (user.role === 'RESCUER') {
    return res.status(403).json({ success: false, error: 'RESCUER role cannot trigger alarms.' });
  }

  // If IL_BASKANI, they can only trigger for their own province
  let targetProv = payload.targetProv || null;
  if (user.role === 'IL_BASKANI') {
    if (!user.province) {
      return res.status(403).json({ success: false, error: 'Your account is not assigned to a province.' });
    }
    // Force the target province to the user's province
    targetProv = user.province;
  }

  // 2. Acceptance Test — reject invalid payloads before broadcast
  const atResult = acceptanceTest(payload);
  if (!atResult.passed) {
    console.warn(`[AT] Alarm REJECTED:`, atResult.errors);
    return res.status(400).json({ success: false, error: 'Acceptance Test failed', details: atResult.errors });
  }

  try {
    // 3. Save to Database (Audit log)
    const dbAlarm = await prisma.alarmLog.create({
      data: {
        title: payload.title.trim(),
        body: payload.body.trim(),
        priority: payload.priority || 'critical',
        targetProv: targetProv,
        senderId: user.id
      }
    });

    // 4. Construct alarm message for clients
    const alarm = {
      id: dbAlarm.id,
      type: 'ALARM',
      payload: {
        title: dbAlarm.title,
        body: dbAlarm.body,
        priority: dbAlarm.priority,
        targetProv: dbAlarm.targetProv,
        mission_id: payload.mission_id || `SAR-${Date.now()}`
      },
      timestamp: Date.now(),
      ackedBy: []
    };

    // Store in pending alarms (for polling fallback)
    pendingAlarms.push(alarm);
    if (pendingAlarms.length > MAX_PENDING_ALARMS) pendingAlarms.shift();

    // ==========================================
    // Netgsm SMS Integration (Safety-Critical)
    // ==========================================
    try {
      const usersToSms = await prisma.user.findMany({
        where: {
          isActive: true,
          phone: { not: null },
          ...(targetProv ? { province: targetProv } : {})
        },
        select: { phone: true }
      });
      const phones = usersToSms.map(u => u.phone).filter(p => p.length > 9).join(',');
      if (phones) {
        const netgsmUser = process.env.NETGSM_USER || 'test_user';
        const netgsmPass = process.env.NETGSM_PASS || 'test_pass';
        const netgsmHeader = process.env.NETGSM_HEADER || 'ANDAKURTAR';
        const smsMessage = `[ANDA ALARM] ${dbAlarm.title} - ${dbAlarm.body} - ACIL DURUM`;
        
        const netgsmUrl = new URL('https://api.netgsm.com.tr/sms/send/get');
        netgsmUrl.searchParams.append('usercode', netgsmUser);
        netgsmUrl.searchParams.append('password', netgsmPass);
        netgsmUrl.searchParams.append('gsmno', phones);
        netgsmUrl.searchParams.append('message', smsMessage);
        netgsmUrl.searchParams.append('msgheader', netgsmHeader);

        fetch(netgsmUrl.toString())
          .then(res => res.text())
          .then(text => console.log(`[NETGSM] SMS triggered to ${usersToSms.length} users. Response: ${text}`))
          .catch(err => console.error('[NETGSM] Failed to send SMS:', err));
      }
    } catch (err) {
      console.error('[NETGSM] Error fetching users for SMS:', err);
    }

    // 5. Broadcast to connected WebSocket clients based on Target Province
    let sentCount = 0;
    let failCount = 0;
    const message = JSON.stringify(alarm);

    clients.forEach((client, clientId) => {
      // Check location logic:
      // If alarm is nationwide (targetProv is null), send to everyone.
      // If alarm has a specific province, send ONLY to clients in that province OR MERKEZ clients (so they see what's happening).
      const shouldSend = 
        !targetProv || // Nationwide
        (client.user.province === targetProv) || // Belongs to target province
        (client.user.role === 'MERKEZ'); // HQ sees everything

      if (shouldSend) {
        try {
          if (client.ws.readyState === WebSocket.OPEN) {
            client.ws.send(message);
            sentCount++;
          } else {
            failCount++;
          }
        } catch (err) {
          failCount++;
        }
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

  } catch (error) {
    console.error('[ALARM] DB Error:', error);
    res.status(500).json({ success: false, error: 'Database error while saving alarm' });
  }
});

/**
 * GET /api/pending-alarms
 * Polling fallback endpoint for authenticated users
 */
app.get('/api/pending-alarms', authenticateJWT, (req, res) => {
  const since = parseInt(req.query.since) || 0;
  const now = Date.now();
  const user = req.user;

  // Filter: newer than 'since', not expired, and intended for the user's province
  const relevant = pendingAlarms.filter(a => {
    const isNewAndValid = a.timestamp > since && (now - a.timestamp) < PENDING_ALARM_TTL_MS;
    const isForUser = !a.payload.targetProv || a.payload.targetProv === user.province || user.role === 'MERKEZ';
    return isNewAndValid && isForUser;
  });

  res.json({ success: true, alarms: relevant, count: relevant.length, server_time: now });
});

/**
 * POST /api/ack
 */
app.post('/api/ack', authenticateJWT, async (req, res) => {
  const { alarm_id, client_id } = req.body;
  if (!alarm_id || !client_id) return res.status(400).json({ success: false, error: 'alarm_id and client_id required' });

  const alarm = pendingAlarms.find(a => a.id === alarm_id);
  if (alarm && !alarm.ackedBy.includes(client_id)) {
    alarm.ackedBy.push(client_id);
    console.log(`[ACK] Client ${client_id} acknowledged alarm ${alarm_id}`);
    
    // Update DB async
    prisma.alarmLog.update({
      where: { id: alarm_id },
      data: { clientsAck: { increment: 1 } }
    }).catch(err => console.error('DB Ack update failed', err));
  }

  const client = clients.get(client_id);
  if (client) client.lastAckAt = Date.now();

  res.json({ success: true });
});

/**
 * GET /api/health
 */
app.get('/api/health', (req, res) => {
  const now = Date.now();
  res.json({
    status: 'ok',
    uptime_seconds: Math.floor((now - serverStartTime) / 1000),
    connected_clients: clients.size,
    server_time: now,
    version: '2.0.0-auth'
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
  const url = new URL(req.url, `http://${req.headers.host}`);
  const token = url.searchParams.get('token');

  // Require token for WS connection
  if (!token) {
    ws.close(1008, 'Unauthorized: Missing token');
    return;
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      ws.close(1008, 'Unauthorized: Invalid token');
      return;
    }

    const clientId = uuidv4();
    const clientIp = req.headers['x-forwarded-for'] || req.socket.remoteAddress;

    clients.set(clientId, {
      ws,
      alive: true,
      missedBeats: 0,
      connectedAt: Date.now(),
      lastAckAt: null,
      deviceInfo: null,
      user // Attach authenticated user data to the WebSocket client
    });

    console.log(`[WS] ✅ ${user.role} connected: ${user.email} (Total: ${clients.size})`);

    ws.send(JSON.stringify({
      type: 'WELCOME',
      client_id: clientId,
      server_time: Date.now(),
      heartbeat_interval_ms: HEARTBEAT_INTERVAL_MS
    }));

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        if (message.type === 'ACK') handleAck(clientId, message.alarm_id);
        else if (message.type === 'PONG') {
          const c = clients.get(clientId);
          if (c) { c.alive = true; c.missedBeats = 0; }
        }
      } catch (err) {
        console.warn(`[WS] Malformed message from ${clientId}`);
      }
    });

    ws.on('pong', () => {
      const client = clients.get(clientId);
      if (client) { client.alive = true; client.missedBeats = 0; }
    });

    ws.on('close', () => {
      clients.delete(clientId);
      console.log(`[WS] ❌ Client disconnected: ${user.email} (total: ${clients.size})`);
    });

    ws.on('error', (err) => {
      console.error(`[WS] Error from client ${user.email}:`, err.message);
      clients.delete(clientId);
    });
  });
});

// ============================================================
// Heartbeat Watchdog
// ============================================================
const heartbeatInterval = setInterval(() => {
  clients.forEach((client, clientId) => {
    if (!client.alive) {
      client.missedBeats++;
      if (client.missedBeats >= MAX_MISSED_HEARTBEATS) {
        console.warn(`[HEARTBEAT] 💀 Client ${client.user.email} dead — terminating`);
        client.ws.terminate();
        clients.delete(clientId);
        return;
      }
    }
    client.alive = false;
    try {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.ping();
        client.ws.send(JSON.stringify({ type: 'PING', timestamp: Date.now() }));
      }
    } catch (err) {}
  });
}, HEARTBEAT_INTERVAL_MS);

// ============================================================
// ACK Handler
// ============================================================
function handleAck(clientId, alarmId) {
  if (!alarmId) return;
  const alarm = pendingAlarms.find(a => a.id === alarmId);
  if (alarm && !alarm.ackedBy.includes(clientId)) {
    alarm.ackedBy.push(clientId);
    prisma.alarmLog.update({
      where: { id: alarmId },
      data: { clientsAck: { increment: 1 } }
    }).catch(() => {});
  }
  const client = clients.get(clientId);
  if (client) client.lastAckAt = Date.now();
  
  try {
    if (client && client.ws.readyState === WebSocket.OPEN) {
      client.ws.send(JSON.stringify({ type: 'ACK_CONFIRMED', alarm_id: alarmId, timestamp: Date.now() }));
    }
  } catch (err) {}
}

// ============================================================
// Graceful Shutdown
// ============================================================
function shutdown(signal) {
  console.log(`\n[SERVER] ${signal} received — graceful shutdown...`);
  clearInterval(heartbeatInterval);
  
  clients.forEach(client => {
    try {
      if (client.ws.readyState === WebSocket.OPEN) {
        client.ws.send(JSON.stringify({ type: 'SERVER_SHUTDOWN', message: 'Server shutting down' }));
        client.ws.close(1001, 'Shutdown');
      }
    } catch (err) {}
  });
  
  wss.close(() => {
    server.close(async () => {
      await prisma.$disconnect();
      console.log('[SERVER] Shutdown complete.');
      process.exit(0);
    });
  });
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// ============================================================
// Start Server
// ============================================================
server.listen(PORT, () => {
  console.log('╔══════════════════════════════════════════════╗');
  console.log('║     🚨 ANDA AKE — SAR Alarm Server 🚨      ║');
  console.log('║   Auth & DB Enabled | JWT Token Security     ║');
  console.log('╠══════════════════════════════════════════════╣');
  console.log(`║  HTTP API:     http://0.0.0.0:${PORT}            ║`);
  console.log(`║  WebSocket:    ws://0.0.0.0:${PORT}/ws           ║`);
  console.log('╚══════════════════════════════════════════════╝');
});
