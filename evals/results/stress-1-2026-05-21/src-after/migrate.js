const { createDatabase, defaultDbPath, migrate } = require('./db');

const db = createDatabase();

migrate(db);
db.close();

console.log(`Migration completed: ${defaultDbPath()}`);
