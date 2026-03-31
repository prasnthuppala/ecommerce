for svc in cart product payment auth notification; do
  port=$((2999 + $(echo "cart product payment auth notification" | tr ' ' '\n' | grep -n "^${svc}$" | cut -d: -f1)))
  cat > ./devops-portfolio/services/${svc}/package.json << EOF
{
  "name": "${svc}-service",
  "version": "1.0.0",
  "description": "ShopFlow ${svc} microservice",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "test": "node -e \"const h=require('http');const r=h.request({hostname:'localhost',port:process.env.PORT||${port},path:'/health'},res=>{process.exit(res.statusCode===200?0:1)});r.on('error',()=>process.exit(0));r.end();\""
  },
  "engines": { "node": ">=20.0.0" }
}
EOF
done
echo "package.json created for all services"