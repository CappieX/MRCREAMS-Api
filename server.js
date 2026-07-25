require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const { query, getClient, pool } = require('./config/database');

const authRouter = require('./routes/auth');
const authRoutesRouter = require('./routes/authRoutes');
const adminRouter = require('./routes/adminRoutes');
const supportTicketsRouter = require('./routes/supportTickets');
const emotionAnalysisRouter = require('./routes/emotionAnalysis');
const therapistRouter = require('./routes/therapistRoutes');
const mobileRouter = require('./routes/mobileRoutes');
const analyticsRouter = require('./routes/analyticsRoutes');
const reportingRouter = require('./routes/reportingRoutes');
const publicAPIRouter = require('./routes/publicAPIRoutes');
const integrationRouter = require('./routes/integrationRoutes');
const hipaaComplianceRouter = require('./routes/hipaaComplianceRoutes');
const gdprComplianceRouter = require('./routes/gdprComplianceRoutes');
const securityRouter = require('./routes/securityRoutes');
const metricsRouter = require('./routes/metricsRoutes');
const platformRouter = require('./routes/platformRoutes');
const paymentRouter = require('./routes/paymentRoutes');

const { authenticateToken } = require('./middleware/auth');
const {
  configureSecurityHeaders,
  requestLogging,
  securityEventLogging,
  ipSecurity,
  userAgentValidation,
  requestSizeLimit,
  requestFrequencyLimit,
  httpsEnforcement,
  corsSecurity,
  apiVersioning,
  errorHandling,
  securityMonitoring
} = require('./middleware/security');
const { sanitizeInput, securityValidation, validatePayloadSize } = require('./middleware/validation');
const monitoringService = require('./services/monitoringService');

const app = express();
const PORT = parseInt(process.env.PORT, 10) || 5001;
const isDev = process.env.NODE_ENV !== 'production';

const allowedOrigins = (process.env.ALLOWED_ORIGINS ? process.env.ALLOWED_ORIGINS.split(',') : [
  process.env.FRONTEND_URL || 'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:3001',
  'http://127.0.0.1:3001',
  'http://localhost:5173',
  'http://127.0.0.1:5173'
]).filter(Boolean);

app.set('trust proxy', 1); // Trust first proxy

app.use(cors({
  origin: function (origin, callback) {
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    if (isDev) return callback(null, true);
    return callback(new Error('Origin blocked by CORS policy: ' + origin), false);
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'X-API-Key', 'API-Version']
}));

app.use(configureSecurityHeaders());
app.use(compression({ threshold: 1024 }));
app.use(httpsEnforcement);
app.use(corsSecurity);
app.use(apiVersioning);
app.use(ipSecurity);

if (!isDev) {
  app.use(userAgentValidation);
} else {
  app.use((req, res, next) => {
    if (!req.get('User-Agent')) {
      req.headers['user-agent'] = 'DevClient/1.0';
    }
    next();
  });
}

app.use(requestLogging);
app.use(securityEventLogging);
app.use(securityMonitoring);
app.use(requestSizeLimit(parseInt(process.env.MAX_REQUEST_SIZE, 10) || 10 * 1024 * 1024));
app.use(requestFrequencyLimit(
  parseInt(process.env.RATE_LIMIT_WINDOW, 10) || 60000,
  isDev ? 5000 : (parseInt(process.env.RATE_LIMIT_MAX, 10) || 100)
));

app.use(helmet({
  contentSecurityPolicy: false,
  crossOriginEmbedderPolicy: false
}));

const apiLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: isDev ? 5000 : 100,
  message: { error: 'Too many requests from this IP, please try again later.', code: 'RATE_LIMIT_EXCEEDED' },
  standardHeaders: true,
  legacyHeaders: false
});
app.use('/api', apiLimiter);

const authLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: isDev ? 200 : 20,
  message: { error: 'Too many login attempts. Please try again later.', code: 'AUTH_RATE_LIMIT_EXCEEDED' },
  standardHeaders: true,
  legacyHeaders: false
});

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

app.use(monitoringService.requestDurationMiddleware.bind(monitoringService));

app.use(sanitizeInput);
app.use(securityValidation);
app.use(validatePayloadSize(parseInt(process.env.MAX_REQUEST_SIZE, 10) || 10 * 1024 * 1024));

app.use((req, res, next) => {
  console.log(`${new Date().toISOString()} - ${req.method} ${req.path} - ${req.ip}`);
  next();
});

app.get('/health', async (req, res) => {
  try {
    await query('SELECT 1');
    res.json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      database: 'connected',
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      version: process.env.npm_package_version || '1.0.0'
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      timestamp: new Date().toISOString(),
      database: 'disconnected',
      error: error.message
    });
  }
});

app.get('/status', async (req, res) => {
  try {
    const dbResult = await query('SELECT 1');
    res.json({
      status: 'ok',
      environment: process.env.NODE_ENV || 'development',
      backendPort: PORT,
      dbConnected: !!dbResult,
      allowedOrigins,
      uptime: process.uptime(),
      version: process.env.npm_package_version || '1.0.0'
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy',
      environment: process.env.NODE_ENV || 'development',
      dbConnected: false,
      error: error.message
    });
  }
});

app.use('/api/auth', authLimiter, authRouter);
app.use('/api/v1/auth', authLimiter, authRoutesRouter.router);
app.use('/api/admin', adminRouter);
app.use('/api/v1/admin', adminRouter);

app.get('/api', (req, res) => {
  res.json({
    name: 'MR.CREAMS Backend API',
    version: process.env.npm_package_version || '1.0.0',
    status: 'ok',
    endpoints: {
      auth: '/api/auth',
      admin: '/api/admin',
      support: '/api/v1/support',
      emotions: '/api/emotions',
      therapists: '/api/therapists',
      mobile: '/api/mobile',
      analytics: '/api/analytics',
      reports: '/api/reports',
      public: '/api/public',
      integrations: '/api/integrations',
      hipaa: '/api/hipaa',
      gdpr: '/api/gdpr',
      security: '/api/security',
      platform: '/api/platform',
      payments: '/api/payments'
    }
  });
});

app.use('/api/v1/support', supportTicketsRouter);
app.use('/api/emotions', emotionAnalysisRouter);
app.use('/api/therapists', therapistRouter);
app.use('/api/mobile', mobileRouter);
app.use('/api/analytics', analyticsRouter);
app.use('/api/reports', reportingRouter);
app.use('/api/public', publicAPIRouter);
app.use('/api/integrations', integrationRouter);
app.use('/api/hipaa', hipaaComplianceRouter);
app.use('/api/gdpr', gdprComplianceRouter);
app.use('/api/security', securityRouter);
app.use('/api/platform', platformRouter);
app.use('/api/payments', paymentRouter);
app.use('/api', paymentRouter);
app.use('/metrics', metricsRouter);

const protectRoute = authenticateToken;

app.get('/api/conflicts', protectRoute, async (req, res) => {
  try {
    let queryText = `
      SELECT c.*, u.name as user_name, u.email as user_email
      FROM conflicts c
      JOIN users u ON c.user_id = u.id
    `;
    let params = [];

    if (req.user && !req.user.isAdmin) {
      queryText += ' WHERE c.user_id = $1';
      params.push(req.user.id);
    }

    queryText += ' ORDER BY c.date DESC, c.time DESC';

    const result = await query(queryText, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching conflicts:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/conflicts/:id', protectRoute, async (req, res) => {
  try {
    const { id } = req.params;
    let queryText = `
      SELECT c.*, u.name as user_name, u.email as user_email
      FROM conflicts c
      JOIN users u ON c.user_id = u.id
      WHERE c.id = $1
    `;
    let params = [id];

    if (req.user && !req.user.isAdmin) {
      queryText += ' AND c.user_id = $2';
      params.push(req.user.id);
    }

    const result = await query(queryText, params);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Conflict not found' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error fetching conflict:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.post('/api/conflicts', protectRoute, async (req, res) => {
  try {
    const { date, time, conflict_reason, description, time_consumption, fight_degree, final_result, remark, partner_id } = req.body;

    if (!date || !time || !conflict_reason || !time_consumption || !fight_degree) {
      return res.status(400).json({ error: 'Missing required fields', code: 'MISSING_FIELDS' });
    }

    if (!req.user || !req.user.id) {
      return res.status(401).json({ error: 'Authentication required' });
    }

    const queryText = `
      INSERT INTO conflicts (date, time, conflict_reason, description, time_consumption, fight_degree, final_result, remark, user_id, partner_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      RETURNING *
    `;
    const params = [date, time, conflict_reason, description, time_consumption, fight_degree, final_result, remark, req.user.id, partner_id];

    const result = await query(queryText, params);
    res.status(201).json(result.rows[0]);
  } catch (err) {
    console.error('Error creating conflict:', err);
    res.status(500).json({ error: 'Failed to save conflict. Please try again.' });
  }
});

app.put('/api/conflicts/:id', protectRoute, async (req, res) => {
  try {
    const { id } = req.params;
    const { date, time, conflict_reason, description, time_consumption, fight_degree, final_result, remark, partner_id } = req.body;

    let queryText = `
      UPDATE conflicts 
      SET date = $1, time = $2, conflict_reason = $3, description = $4, time_consumption = $5, 
          fight_degree = $6, final_result = $7, remark = $8, partner_id = $9, updated_at = CURRENT_TIMESTAMP
      WHERE id = $10
    `;
    let params = [date, time, conflict_reason, description, time_consumption, fight_degree, final_result, remark, partner_id, id];

    if (req.user && !req.user.isAdmin) {
      queryText += ' AND user_id = $11';
      params.push(req.user.id);
    }

    queryText += ' RETURNING *';

    const result = await query(queryText, params);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Conflict not found or you do not have permission to update it' });
    }

    res.json(result.rows[0]);
  } catch (err) {
    console.error('Error updating conflict:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.delete('/api/conflicts/:id', protectRoute, async (req, res) => {
  try {
    const { id } = req.params;

    let queryText = 'DELETE FROM conflicts WHERE id = $1';
    let params = [id];

    if (req.user && !req.user.isAdmin) {
      queryText += ' AND user_id = $2';
      params.push(req.user.id);
    }

    queryText += ' RETURNING id';

    const result = await query(queryText, params);

    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'Conflict not found or you do not have permission to delete it' });
    }

    res.json({ message: 'Conflict deleted successfully' });
  } catch (err) {
    console.error('Error deleting conflict:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/analytics', protectRoute, async (req, res) => {
  try {
    let whereClause = '';
    let params = [];

    if (req.user && !req.user.isAdmin) {
      whereClause = 'WHERE user_id = $1';
      params.push(req.user.id);
    }

    const totalResult = await query(`SELECT COUNT(*) FROM conflicts ${whereClause}`, params);
    const totalConflicts = parseInt(totalResult.rows[0].count);

    const reasonQuery = `
      SELECT conflict_reason as name, COUNT(*) as value 
      FROM conflicts 
      ${whereClause}
      GROUP BY conflict_reason 
      ORDER BY value DESC
    `;
    const reasonResult = await query(reasonQuery, params);

    const avgDegreeQuery = `SELECT AVG(fight_degree) as avg_degree FROM conflicts ${whereClause}`;
    const avgDegreeResult = await query(avgDegreeQuery, params);
    const avgFightDegree = avgDegreeResult.rows[0].avg_degree ? parseFloat(avgDegreeResult.rows[0].avg_degree).toFixed(1) : '0.0';

    const avgTimeQuery = `SELECT AVG(time_consumption) as avg_time FROM conflicts ${whereClause}`;
    const avgTimeResult = await query(avgTimeQuery, params);
    const avgTimeConsumption = avgTimeResult.rows[0].avg_time ? parseFloat(avgTimeResult.rows[0].avg_time).toFixed(1) : '0.0';

    const monthlyQuery = `
      SELECT
        TO_CHAR(date, 'YYYY-MM') as month,
        COUNT(*) as count,
        AVG(fight_degree) as avg_degree
      FROM conflicts
      ${whereClause}
      GROUP BY TO_CHAR(date, 'YYYY-MM')
      ORDER BY month
    `;
    const monthlyResult = await query(monthlyQuery, params);

    res.json({
      totalConflicts,
      conflictsByReason: reasonResult.rows,
      avgFightDegree,
      avgTimeConsumption,
      monthlyTrends: monthlyResult.rows
    });
  } catch (err) {
    console.error('Error generating analytics:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.get('/api/recommendations', async (req, res) => {
  try {
    const commonReasonsQuery = `
      SELECT conflict_reason, COUNT(*) as count
      FROM conflicts
      GROUP BY conflict_reason
      ORDER BY count DESC
      LIMIT 3
    `;
    const commonReasonsResult = await query(commonReasonsQuery);

    const highIntensityQuery = `
      SELECT * FROM conflicts
      WHERE fight_degree >= 8
      ORDER BY fight_degree DESC, date DESC
      LIMIT 3
    `;
    const highIntensityResult = await query(highIntensityQuery);

    const longConflictsQuery = `
      SELECT * FROM conflicts
      WHERE time_consumption >= 60
      ORDER BY time_consumption DESC, date DESC
      LIMIT 3
    `;
    const longConflictsResult = await query(longConflictsQuery);

    res.json({
      commonReasons: commonReasonsResult.rows,
      highIntensityConflicts: highIntensityResult.rows,
      longConflicts: longConflictsResult.rows
    });
  } catch (err) {
    console.error('Error generating recommendations:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

app.use(errorHandling);

app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  const statusCode = err.statusCode || err.status || 500;
  res.status(statusCode).json({
    error: err.clientMessage || (statusCode >= 500 ? 'Internal server error' : err.message) || 'Internal server error',
    code: err.code || 'INTERNAL_ERROR',
    ...(isDev && { stack: err.stack })
  });
});

app.use('*', (req, res) => {
  res.status(404).json({ error: 'Route not found', code: 'NOT_FOUND', path: req.originalUrl });
});

const closePoolSafe = async () => {
  try {
    const { closePool } = require('./config/database');
    await closePool();
  } catch (_) {}
};

process.on('SIGTERM', async () => {
  console.log('SIGTERM received, shutting down gracefully');
  await closePoolSafe();
  process.exit(0);
});

process.on('SIGINT', async () => {
  console.log('SIGINT received, shutting down gracefully');
  await closePoolSafe();
  process.exit(0);
});

module.exports = app;

async function bootstrap() {
  try {
    console.log('🔌 Checking database connection...');
    const start = Date.now();
    await query('SELECT 1 as connection_check');
    console.log(`✅ PostgreSQL connected (${Date.now() - start}ms)`);
  } catch (dbErr) {
    console.warn('⚠️  Database connection check failed:', dbErr.message);
    console.warn('   Server will still start, but DB-dependent routes will fail until PostgreSQL is ready.');
  }

  if (require.main === module) {
    app.listen(PORT, () => {
      console.log(`🚀 MR.CREAMS API server running on port ${PORT}`);
      console.log(`   Environment : ${process.env.NODE_ENV || 'development'}`);
      console.log(`   Frontend URL: ${process.env.FRONTEND_URL || 'http://localhost:3000'}`);
      console.log(`   Allowed CORS: ${allowedOrigins.join(', ')}`);
      console.log(`   Health check : http://localhost:${PORT}/health`);
      console.log(`   Status       : http://localhost:${PORT}/status`);
      console.log(`   API Root     : http://localhost:${PORT}/api`);
    });
  }
}

bootstrap().catch((err) => {
  console.error('💥 Bootstrap failed:', err);
  if (require.main === module) process.exit(1);
});
