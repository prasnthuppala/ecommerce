const http = require('http');

let requestCount = 0, errorCount = 0;
const startTime = Date.now();

const products = [
  { id: 'p1', name: 'Air Runner Pro X', sku: 'SKU-NKE-001', price: 12999, stock: 45, category: 'Footwear', brand: 'Nike', rating: 4.5, reviews: 1243, emoji: '👟', description: 'Premium running shoes with air cushioning technology', images: ['shoe1.jpg'] },
  { id: 'p2', name: 'UltraPhone 15 Pro', sku: 'SKU-SAM-042', price: 89999, stock: 3, category: 'Electronics', brand: 'Samsung', rating: 4.8, reviews: 5621, emoji: '📱', description: '6.7" AMOLED, 200MP camera, 5000mAh battery', images: ['phone1.jpg'] },
  { id: 'p3', name: 'SoundPods Elite', sku: 'SKU-APL-019', price: 24990, stock: 28, category: 'Audio', brand: 'Apple', rating: 4.7, reviews: 8934, emoji: '🎧', description: 'Active noise cancellation, 30hr battery life', images: ['pods1.jpg'] },
  { id: 'p4', name: 'SmartWatch Series 9', sku: 'SKU-APL-007', price: 41900, stock: 0, category: 'Wearables', brand: 'Apple', rating: 4.6, reviews: 3201, emoji: '⌚', description: 'Health monitoring, GPS, Always-on display', images: ['watch1.jpg'] },
  { id: 'p5', name: 'Gaming Laptop X1', sku: 'SKU-DEL-088', price: 124999, stock: 12, category: 'Computers', brand: 'Dell', rating: 4.4, reviews: 892, emoji: '💻', description: 'RTX 4070, Intel i9, 32GB RAM, 144Hz display', images: ['laptop1.jpg'] },
];

const respond = (res, status, data) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'X-Service': 'product-service', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'Content-Type' });
  res.end(JSON.stringify(data));
};

const routes = {
  'GET /health': (req, res) => respond(res, 200, { status: 'healthy', service: 'product', version: '1.0.0', uptime: ((Date.now() - startTime) / 1000).toFixed(1), timestamp: new Date().toISOString() }),
  'GET /metrics': (req, res) => { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end(`product_requests_total ${requestCount}\nproduct_catalog_size ${products.length}\nproduct_in_stock ${products.filter(p => p.stock > 0).length}`); },
  'GET /products': (req, res) => {
    const url = new URL(req.url, 'http://x');
    const category = url.searchParams.get('category');
    const search = url.searchParams.get('q');
    let result = [...products];
    if (category) result = result.filter(p => p.category.toLowerCase() === category.toLowerCase());
    if (search) result = result.filter(p => p.name.toLowerCase().includes(search.toLowerCase()));
    respond(res, 200, { products: result, total: result.length, categories: [...new Set(products.map(p => p.category))] });
  },
  'GET /product': (req, res) => {
    const id = new URL(req.url, 'http://x').searchParams.get('id');
    const product = products.find(p => p.id === id);
    if (!product) return respond(res, 404, { error: 'Product not found' });
    respond(res, 200, product);
  },
  'GET /stats': (req, res) => respond(res, 200, {
    totalProducts: products.length,
    inStock: products.filter(p => p.stock > 0).length,
    outOfStock: products.filter(p => p.stock === 0).length,
    categories: [...new Set(products.map(p => p.category))].length,
    avgPrice: Math.round(products.reduce((s, p) => s + p.price, 0) / products.length),
  }),
};

const server = http.createServer((req, res) => {
  requestCount++;
  if (req.method === 'OPTIONS') return respond(res, 204, {});
  const key = `${req.method} ${req.url.split('?')[0]}`;
  const handler = routes[key];
  if (handler) { try { handler(req, res); } catch (e) { errorCount++; respond(res, 500, { error: e.message }); } }
  else respond(res, 404, { error: 'Not found' });
});

process.on('SIGTERM', () => { server.close(() => process.exit(0)); });
process.on('SIGINT',  () => { server.close(() => process.exit(0)); });
const PORT = process.env.PORT || 3001;
server.listen(PORT, () => console.log(`[product] Running on :${PORT}`));