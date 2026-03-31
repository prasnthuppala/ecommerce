const http = require('http');

let requestCount = 0, errorCount = 0;
const startTime = Date.now();
const transactions = [];

const respond = (res, status, data) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'X-Service': 'payment-service', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type, X-User-Id' });
  res.end(JSON.stringify(data));
};

const parseBody = (req) => new Promise((resolve) => {
  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', () => { try { resolve(JSON.parse(body || '{}')); } catch { resolve({}); } });
});

const routes = {
  'GET /health': (req, res) => respond(res, 200, { status: 'healthy', service: 'payment', version: '1.0.0', uptime: ((Date.now() - startTime) / 1000).toFixed(1), timestamp: new Date().toISOString() }),
  'GET /metrics': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end(`payment_requests_total ${requestCount}\npayment_transactions_total ${transactions.length}\npayment_success_total ${transactions.filter(t => t.status === 'success').length}\npayment_failed_total ${transactions.filter(t => t.status === 'failed').length}`); },
  'POST /process': async (req, res) => {
    const body = await parseBody(req);
    const userId = req.headers['x-user-id'] || 'guest';
    const { amount, method = 'card', orderId } = body;
    if (!amount) return respond(res, 400, { error: 'Amount is required' });

    // Simulate payment processing (95% success rate)
    const success = Math.random() > 0.05;
    const txn = {
      id: `TXN-${Date.now()}`,
      userId, orderId, amount, method,
      status: success ? 'success' : 'failed',
      timestamp: new Date().toISOString(),
      gateway: 'razorpay',
      currency: 'INR',
    };
    transactions.push(txn);
    if (success) {
      respond(res, 200, { message: 'Payment successful', transaction: txn });
    } else {
      respond(res, 402, { message: 'Payment failed', transaction: txn, reason: 'Insufficient funds' });
    }
  },
  'GET /transactions': (req, res) => {
    const userId = req.headers['x-user-id'];
    const result = userId ? transactions.filter(t => t.userId === userId) : transactions;
    respond(res, 200, { transactions: result.slice(-20), total: result.length });
  },
  'GET /stats': (req, res) => {
    const success = transactions.filter(t => t.status === 'success');
    respond(res, 200, {
      totalTransactions: transactions.length,
      successRate: transactions.length > 0 ? ((success.length / transactions.length) * 100).toFixed(1) + '%' : '100%',
      totalRevenue: success.reduce((s, t) => s + t.amount, 0),
      methods: { card: transactions.filter(t => t.method === 'card').length, upi: transactions.filter(t => t.method === 'upi').length },
    });
  },
};

const server = http.createServer(async (req, res) => {
  requestCount++;
  if (req.method === 'OPTIONS') return respond(res, 204, {});
  const key = `${req.method} ${req.url.split('?')[0]}`;
  const handler = routes[key];
  if (handler) { try { await handler(req, res); } catch (e) { errorCount++; respond(res, 500, { error: e.message }); } }
  else respond(res, 404, { error: 'Not found' });
});

process.on('SIGTERM', () => { server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { server.close(() => process.exit(0)); });
const PORT = process.env.PORT || 3002;
server.listen(PORT, () => console.log(`[payment] Running on :${PORT}`));