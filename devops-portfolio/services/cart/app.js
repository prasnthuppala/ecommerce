const http = require('http');

// In-memory store (in production this would be Redis)
const carts = new Map();
const products = [
  { id: 'p1', name: 'Air Runner Pro X', sku: 'SKU-NKE-001', price: 12999, stock: 45, emoji: '👟' },
  { id: 'p2', name: 'UltraPhone 15 Pro', sku: 'SKU-SAM-042', price: 89999, stock: 3, emoji: '📱' },
  { id: 'p3', name: 'SoundPods Elite', sku: 'SKU-APL-019', price: 24990, stock: 28, emoji: '🎧' },
  { id: 'p4', name: 'SmartWatch Series 9', sku: 'SKU-APL-007', price: 41900, stock: 0, emoji: '⌚' },
  { id: 'p5', name: 'Gaming Laptop X1', sku: 'SKU-DEL-088', price: 124999, stock: 12, emoji: '💻' },
];

// Metrics
let requestCount = 0;
let errorCount = 0;
const startTime = Date.now();

const respond = (res, status, data) => {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'X-Service': 'cart-service',
    'X-Version': '1.0.0',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-User-Id',
  });
  res.end(JSON.stringify(data));
};

const parseBody = (req) => new Promise((resolve) => {
  let body = '';
  req.on('data', chunk => body += chunk);
  req.on('end', () => {
    try { resolve(JSON.parse(body || '{}')); }
    catch { resolve({}); }
  });
});

const routes = {
  'GET /health': (req, res) => respond(res, 200, {
    status: 'healthy',
    service: 'cart',
    version: '1.0.0',
    uptime: ((Date.now() - startTime) / 1000).toFixed(1),
    requests_total: requestCount,
    error_rate: requestCount > 0 ? ((errorCount / requestCount) * 100).toFixed(2) + '%' : '0%',
    memory: process.memoryUsage(),
    timestamp: new Date().toISOString(),
  }),

  'GET /metrics': (req, res) => {
    // Prometheus-format metrics
    const metrics = [
      `# HELP cart_requests_total Total requests`,
      `# TYPE cart_requests_total counter`,
      `cart_requests_total ${requestCount}`,
      `# HELP cart_errors_total Total errors`,
      `# TYPE cart_errors_total counter`,
      `cart_errors_total ${errorCount}`,
      `# HELP cart_active_carts Active cart count`,
      `# TYPE cart_active_carts gauge`,
      `cart_active_carts ${carts.size}`,
      `# HELP cart_uptime_seconds Service uptime`,
      `# TYPE cart_uptime_seconds gauge`,
      `cart_uptime_seconds ${((Date.now() - startTime) / 1000).toFixed(0)}`,
    ].join('\n');
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(metrics);
  },

  'GET /items': (req, res) => {
    const userId = req.headers['x-user-id'] || 'guest';
    const cart = carts.get(userId) || { items: [], userId, createdAt: new Date().toISOString() };
    const total = cart.items.reduce((sum, item) => sum + (item.price * item.quantity), 0);
    respond(res, 200, {
      userId,
      items: cart.items,
      itemCount: cart.items.length,
      total,
      totalFormatted: `₹${total.toLocaleString('en-IN')}`,
    });
  },

  'POST /add': async (req, res) => {
    const userId = req.headers['x-user-id'] || 'guest';
    const body = await parseBody(req);
    const productId = body.productId || 'p1';
    const quantity = body.quantity || 1;

    const product = products.find(p => p.id === productId);
    if (!product) return respond(res, 404, { error: 'Product not found' });
    if (product.stock === 0) return respond(res, 400, { error: 'Out of stock' });

    const cart = carts.get(userId) || { items: [], userId, createdAt: new Date().toISOString() };
    const existing = cart.items.find(i => i.productId === productId);
    if (existing) {
      existing.quantity += quantity;
    } else {
      cart.items.push({ productId, name: product.name, emoji: product.emoji, price: product.price, quantity, sku: product.sku });
    }
    carts.set(userId, cart);
    const total = cart.items.reduce((sum, i) => sum + (i.price * i.quantity), 0);
    respond(res, 201, { message: 'Added to cart', cart: cart.items, total });
  },

  'DELETE /remove': async (req, res) => {
    const userId = req.headers['x-user-id'] || 'guest';
    const body = await parseBody(req);
    const cart = carts.get(userId);
    if (!cart) return respond(res, 404, { error: 'Cart not found' });
    cart.items = cart.items.filter(i => i.productId !== body.productId);
    carts.set(userId, cart);
    respond(res, 200, { message: 'Item removed', cart: cart.items });
  },

  'DELETE /clear': (req, res) => {
    const userId = req.headers['x-user-id'] || 'guest';
    carts.delete(userId);
    respond(res, 200, { message: 'Cart cleared' });
  },

  'GET /stats': (req, res) => respond(res, 200, {
    activeCarts: carts.size,
    totalItems: [...carts.values()].reduce((s, c) => s + c.items.length, 0),
    totalValue: [...carts.values()].reduce((s, c) => s + c.items.reduce((si, i) => si + i.price * i.quantity, 0), 0),
  }),
};

const server = http.createServer(async (req, res) => {
  requestCount++;
  if (req.method === 'OPTIONS') return respond(res, 204, {});
  const key = `${req.method} ${req.url.split('?')[0]}`;
  const handler = routes[key];
  if (handler) {
    try { await handler(req, res); }
    catch (e) { errorCount++; respond(res, 500, { error: e.message }); }
  } else {
    respond(res, 404, { error: 'Route not found', available: Object.keys(routes) });
  }
});

const shutdown = (sig) => {
  console.log(`[cart] ${sig} received — graceful shutdown`);
  server.close(() => { console.log('[cart] Server closed'); process.exit(0); });
  setTimeout(() => process.exit(1), 29000);
};
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => console.log(`[cart] Running on :${PORT}`));