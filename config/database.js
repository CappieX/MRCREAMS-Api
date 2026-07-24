const { Pool } = require('pg');
require('dotenv').config();

const isProduction = process.env.NODE_ENV === 'production';

const poolConfig = process.env.DATABASE_URL
  ? {
      connectionString: process.env.DATABASE_URL,
      ssl: isProduction
        ? {
            rejectUnauthorized: false,
          }
        : false,
    }
  : {
      user: process.env.DB_USER || process.env.PGUSER || 'postgres',
      host: process.env.DB_HOST || process.env.PGHOST || 'localhost',
      database: process.env.DB_NAME || process.env.PGDATABASE || 'mr_creams_db',
      password: process.env.DB_PASSWORD || process.env.PGPASSWORD || 'Admin@123',
      port: parseInt(process.env.DB_PORT || process.env.PGPORT || '5432', 10),
      max: 20,
      idleTimeoutMillis: 30000,
      connectionTimeoutMillis: 2000,
      ssl: false,
    };

const pool = new Pool(poolConfig);

pool.on('connect', () => {
  console.log('Connected to PostgreSQL database');
});

pool.on('error', (err) => {
  console.error('Unexpected error on idle client', err);
  process.exit(-1);
});

// Query helper
const query = async (text, params) => {
  const start = Date.now();
  try {
    const res = await pool.query(text, params);
    const duration = Date.now() - start;
    console.log('Executed query', { duration, rows: res.rowCount });
    return res;
  } catch (error) {
    console.error('Database query error:', error);
    throw error;
  }
};

const getClient = async () => pool.connect();

const closePool = async () => {
  await pool.end();
  console.log('Database pool closed');
};

module.exports = {
  pool,
  query,
  getClient,
  closePool,
};