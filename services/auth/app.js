const http = require('http');
const crypto = require('crypto');

let requestCount = 0;
const startTime = Date.now();
const users = new Map([
  ['usr_001', { id: 'usr_001', name: 'Prasanth Uppala', email: 'prasanth@shopflow.io', role: 'admin' }],
  ['usr_002', { id: 'usr_002', name: 'Priya Sharma', email: 'priya@shopflow.io', role: 'user' }],
  ['usr_003', { id: 'usr_003', name: 'Rahul Kumar', email: 'rahul@shopflow.io', role: 'user' }],
]);
const sessions = new Map();

const respond = (res, status, data) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'X-Service': 'auth-service', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, Authorization' });
  res.end(JSON.stringify(data));
};

const parseBody = (req) => new Promise((resolve) => {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => { try { resolve(JSON.parse(body || '{}')); } catch { resolve({}); } });
});

const generateToken = () => crypto.randomBytes(32).toString('hex');

const routes = {
  'GET /health': (req, res) => respond(res, 200, { status: 'healthy', service: 'auth', version: '1.0.0', uptime: ((Date.now() - startTime) / 1000).toFixed(1), activeSessions: sessions.size, timestamp: new Date().toISOString() }),
  'GET /metrics': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end(`auth_requests_total ${requestCount}\nauth_active_sessions ${sessions.size}\nauth_users_total ${users.size}`); },
  'POST /login': async (req, res) => {
    const { email, password } = await parseBody(req);
    if (!email) return respond(res, 400, { error: 'Email required' });
    const user = [...users.values()].find(u => u.email === email);
    if (!user) return respond(res, 401, { error: 'Invalid credentials' });
    const token = generateToken();
    sessions.set(token, { userId: user.id, createdAt: Date.now(), expiresAt: Date.now() + 3600000 });
    respond(res, 200, { token, user: { id: user.id, name: user.name, email: user.email, role: user.role }, expiresIn: 3600 });
  },
  'POST /verify': async (req, res) => {
    const body = await parseBody(req);
    const token = body.token || (req.headers.authorization || '').replace('Bearer ', '');
    if (!token) return respond(res, 401, { valid: false, error: 'Token required' });
    const session = sessions.get(token);
    if (!session || session.expiresAt < Date.now()) {
      sessions.delete(token);
      return respond(res, 401, { valid: false, error: 'Token expired or invalid' });
    }
    const user = users.get(session.userId);
    respond(res, 200, { valid: true, user: { id: user.id, name: user.name, role: user.role } });
  },
  'POST /logout': async (req, res) => {
    const body = await parseBody(req);
    const token = body.token || (req.headers.authorization || '').replace('Bearer ', '');
    sessions.delete(token);
    respond(res, 200, { message: 'Logged out' });
  },
  'GET /users': (req, res) => respond(res, 200, { users: [...users.values()].map(u => ({ id: u.id, name: u.name, email: u.email, role: u.role })), total: users.size }),
  'GET /stats': (req, res) => respond(res, 200, { totalUsers: users.size, activeSessions: sessions.size, admins: [...users.values()].filter(u => u.role === 'admin').length }),
};

const server = http.createServer(async (req, res) => {
  requestCount++;
  if (req.method === 'OPTIONS') return respond(res, 204, {});
  const key = `${req.method} ${req.url.split('?')[0]}`;
  const handler = routes[key];
  if (handler) { try { await handler(req, res); } catch (e) { respond(res, 500, { error: e.message }); } }
  else respond(res, 404, { error: 'Not found' });
});

process.on('SIGTERM', () => { server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { server.close(() => process.exit(0)); });
const PORT = process.env.PORT || 3003;
server.listen(PORT, () => console.log(`[auth] Running on :${PORT}`));