const http = require('http');

const port = process.env.PORT || 3001;

const server = http.createServer((_, res) => {
  res.writeHead(200, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ status: 'api stub ok' }));
});

server.listen(port, () => {
  console.log(`api app stub listening on ${port}`);
});
