const { createApp } = require('./app');
const { createDatabase, migrate } = require('./db');

const port = Number(process.env.PORT || 3000);
const db = createDatabase();

migrate(db);

const server = createApp({ db }).listen(port, () => {
  console.log(`Tasks API listening on http://localhost:${port}`);
});

function shutdown() {
  server.close(() => {
    db.close();
    process.exit(0);
  });
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
