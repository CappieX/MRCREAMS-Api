console.warn('[DEPRECATED] models/userModel.js uses legacy schema (username/password/gender/is_admin). Prefer routes/auth.js + config/database.js for new code.');
let db;
try {
  db = require('../config/database');
} catch (err) {
  try {
    db = require('../db');
  } catch (_) {
    console.error('[userModel.js] Could not load database module:', err.message);
    db = { query: async () => ({ rows: [] }), getClient: async () => null };
  }
}
const { query, getClient } = db;

const createUser = async (username, password, gender, isAdmin = false) => {
  try {
    const result = await query(
      'INSERT INTO users (email, password_hash, name, user_type) VALUES ($1, $2, $3, $4) RETURNING id, email, user_type',
      [username, password, username, isAdmin ? 'admin' : 'user']
    );
    return {
      id: result.rows[0].id,
      username: result.rows[0].email,
      gender: gender || 'unknown',
      is_admin: result.rows[0].user_type === 'admin'
    };
  } catch (error) {
    throw error;
  }
};

const getUserByUsername = async (username) => {
  try {
    console.log(`[userModel] Legacy lookup for username: ${username} (using email column)`);
    const result = await query('SELECT * FROM users WHERE LOWER(email) = LOWER($1)', [username]);
    console.log(`[userModel] User found: ${result.rows.length > 0 ? 'Yes' : 'No'}`);
    if (result.rows.length > 0) {
      console.log(`[userModel] id=${result.rows[0].id}, user_type=${result.rows[0].user_type}, email=${result.rows[0].email}`);
      return {
        ...result.rows[0],
        username: result.rows[0].email,
        password: result.rows[0].password_hash,
        gender: result.rows[0].gender || 'unknown',
        is_admin: ['admin', 'platform_admin', 'super_admin'].includes(result.rows[0].user_type)
      };
    }
    return undefined;
  } catch (error) {
    console.error('[userModel] Error getting user by username:', error);
    throw error;
  }
};

const getUserById = async (id) => {
  try {
    const result = await query('SELECT id, email, name, user_type FROM users WHERE id = $1', [id]);
    if (!result.rows[0]) return undefined;
    return {
      id: result.rows[0].id,
      username: result.rows[0].email,
      gender: 'unknown',
      is_admin: ['admin', 'platform_admin', 'super_admin'].includes(result.rows[0].user_type)
    };
  } catch (error) {
    throw error;
  }
};

module.exports = {
  createUser,
  getUserByUsername,
  getUserById,
  query,
  getClient
};
