const http = require('http');

let requestCount = 0;
const startTime = Date.now();
const notifications = [];

const respond = (res, status, data) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'X-Service': 'notification-service', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, X-User-Id' });
  res.end(JSON.stringify(data));
};

const parseBody = (req) => new Promise((resolve) => {
  let body = '';
  req.on('data', c => body += c);
  req.on('end', () => { try { resolve(JSON.parse(body || '{}')); } catch { resolve({}); } });
});

const templates = {
  order_placed:    (d) => ({ subject: `Order #${d.orderId} Confirmed!`, body: `Hi ${d.name}, your order of ₹${d.amount} has been placed.` }),
  payment_success: (d) => ({ subject: `Payment of ₹${d.amount} received`, body: `Transaction ${d.txnId} was successful.` }),
  order_shipped:   (d) => ({ subject: `Your order is on the way!`, body: `Order #${d.orderId} has been shipped. ETA: 2-3 days.` }),
  welcome:         (d) => ({ subject: `Welcome to ShopFlow, ${d.name}!`, body: `Start shopping and enjoy exclusive deals.` }),
};

const routes = {
  'GET /health': (req, res) => respond(res, 200, { status: 'healthy', service: 'notification', version: '1.0.0', uptime: ((Date.now() - startTime) / 1000).toFixed(1), totalSent: notifications.length, timestamp: new Date().toISOString() }),
  'GET /metrics': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end(`notification_requests_total ${requestCount}\nnotification_sent_total ${notifications.length}\nnotification_email_total ${notifications.filter(n => n.channel === 'email').length}`); },
  'POST /send': async (req, res) => {
    const body = await parseBody(req);
    const { type, channel = 'email', userId, data = {} } = body;
    if (!type || !userId) return respond(res, 400, { error: 'type and userId are required' });
    const template = templates[type];
    const content = template ? template(data) : { subject: 'Notification', body: data.message || 'You have a new notification' };
    const notification = { id: `notif_${Date.now()}`, type, channel, userId, ...content, sentAt: new Date().toISOString(), status: 'delivered' };
    notifications.push(notification);
    respond(res, 201, { message: 'Notification sent', notification });
  },
  'GET /notifications': (req, res) => {
    const userId = req.headers['x-user-id'];
    const result = userId ? notifications.filter(n => n.userId === userId) : notifications;
    respond(res, 200, { notifications: result.slice(-20), total: result.length });
  },
  'GET /stats': (req, res) => respond(res, 200, {
    totalSent: notifications.length,
    byChannel: { email: notifications.filter(n => n.channel === 'email').length, sms: notifications.filter(n => n.channel === 'sms').length, push: notifications.filter(n => n.channel === 'push').length },
    byType: { order_placed: notifications.filter(n => n.type === 'order_placed').length, payment_success: notifications.filter(n => n.type === 'payment_success').length },
  }),
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
const PORT = process.env.PORT || 3004;
server.listen(PORT, () => console.log(`[notification] Running on :${PORT}`));