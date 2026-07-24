-- Comprehensive PostgreSQL Migration for WCREAMS Backend
-- This migration creates all missing tables referenced throughout the backend codebase
-- Run this after the existing migration files (001-011)

-- ============================================================================
-- SECTION 1: CORE USER & ORGANIZATION TABLES
-- ============================================================================

-- Organizations table
CREATE TABLE IF NOT EXISTS organizations (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    code VARCHAR(50) UNIQUE,
    domain VARCHAR(255),
    industry VARCHAR(100),
    size VARCHAR(50),
    subscription_tier VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    user_type VARCHAR(50) DEFAULT 'individual',
    organization_id INTEGER REFERENCES organizations(id) ON DELETE SET NULL,
    onboarding_completed BOOLEAN DEFAULT FALSE,
    email_verified BOOLEAN DEFAULT FALSE,
    email_verification_token VARCHAR(255),
    password_reset_token VARCHAR(255),
    password_reset_expires TIMESTAMP,
    last_login TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    profile_image_url VARCHAR(500),
    phone VARCHAR(20),
    timezone VARCHAR(50) DEFAULT 'UTC',
    language VARCHAR(10) DEFAULT 'en',
    preferences JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User metadata table (stores additional user information as JSON)
CREATE TABLE IF NOT EXISTS user_metadata (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_metadata_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- ============================================================================
-- SECTION 2: AUTHENTICATION & SESSION MANAGEMENT
-- ============================================================================

-- User sessions table
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    session_token TEXT NOT NULL UNIQUE,
    refresh_token TEXT NOT NULL UNIQUE,
    expires_at TIMESTAMP NOT NULL,
    ip_address VARCHAR(100),
    user_agent TEXT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_sessions_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Device tokens table (for push notifications)
CREATE TABLE IF NOT EXISTS device_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    token TEXT NOT NULL,
    platform VARCHAR(50) NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_device_tokens_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(user_id, token)
);

-- ============================================================================
-- SECTION 3: EMOTION & CONFLICT TRACKING
-- ============================================================================

-- Emotion check-ins table
CREATE TABLE IF NOT EXISTS emotion_checkins (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    primary_emotion VARCHAR(50),
    secondary_emotions TEXT[], -- Array of emotions
    intensity INTEGER CHECK (intensity >= 0 AND intensity <= 10),
    context TEXT,
    triggers TEXT[],
    coping_strategies TEXT[],
    ai_analysis TEXT,
    ai_confidence NUMERIC(5,2),
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_emotion_checkins_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Conflicts table
CREATE TABLE IF NOT EXISTS conflicts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    partner_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    date DATE NOT NULL,
    time TIME NOT NULL,
    conflict_reason VARCHAR(100) NOT NULL,
    description TEXT,
    time_consumption INTEGER NOT NULL CHECK (time_consumption > 0),
    fight_degree INTEGER NOT NULL CHECK (fight_degree >= 1 AND fight_degree <= 10),
    final_result TEXT,
    remark TEXT,
    status VARCHAR(50) DEFAULT 'active',
    resolution_date TIMESTAMP,
    tags TEXT[],
    category VARCHAR(100),
    severity VARCHAR(50),
    participants TEXT[],
    location VARCHAR(255),
    resolved_at TIMESTAMP,
    resolution_notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Conflict resolutions table (enhanced conflicts)
-- This extends the existing conflicts table with additional fields
-- Ensure conflicts table has these columns
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS category VARCHAR(100);
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS severity VARCHAR(50);
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS participants TEXT[];
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS location VARCHAR(255);
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS partner_id INTEGER;
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS resolved_at TIMESTAMP;
-- ALTER TABLE conflicts ADD COLUMN IF NOT EXISTS resolution_notes TEXT;

CREATE INDEX IF NOT EXISTS idx_emotion_checkins_user_id ON emotion_checkins(user_id);
CREATE INDEX IF NOT EXISTS idx_emotion_checkins_created_at ON emotion_checkins(created_at);
CREATE INDEX IF NOT EXISTS idx_emotion_checkins_primary_emotion ON emotion_checkins(primary_emotion);

-- ============================================================================
-- SECTION 4: THERAPY SESSIONS
-- ============================================================================

-- Therapy sessions table
CREATE TABLE IF NOT EXISTS therapy_sessions (
    id SERIAL PRIMARY KEY,
    therapist_id INTEGER NOT NULL,
    client_id INTEGER NOT NULL,
    scheduled_at TIMESTAMP NOT NULL,
    duration_minutes INTEGER,
    status VARCHAR(50) DEFAULT 'scheduled',
    notes TEXT,
    session_type VARCHAR(50),
    video_meeting_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_therapy_sessions_therapist FOREIGN KEY (therapist_id) REFERENCES users(id),
    CONSTRAINT fk_therapy_sessions_client FOREIGN KEY (client_id) REFERENCES users(id)
);

-- Therapist-Client relationships
CREATE TABLE IF NOT EXISTS therapist_clients (
    id SERIAL PRIMARY KEY,
    therapist_id INTEGER NOT NULL,
    client_id INTEGER NOT NULL,
    status VARCHAR(50) DEFAULT 'active',
    start_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    end_date TIMESTAMP,
    notes TEXT,
    treatment_plan TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_therapist_clients_therapist FOREIGN KEY (therapist_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_therapist_clients_client FOREIGN KEY (client_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(therapist_id, client_id)
);

-- Therapist verifications table
CREATE TABLE IF NOT EXISTS therapist_verifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE,
    status VARCHAR(50) DEFAULT 'pending',
    license_number VARCHAR(255),
    license_state VARCHAR(50),
    years_experience INTEGER,
    specializations TEXT[],
    credentials JSONB DEFAULT '{}',
    reviewed_at TIMESTAMP,
    notes TEXT,
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_therapist_verifications_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_therapy_sessions_therapist_id ON therapy_sessions(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_client_id ON therapy_sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_therapy_sessions_scheduled_at ON therapy_sessions(scheduled_at);
CREATE INDEX IF NOT EXISTS idx_therapist_clients_therapist_id ON therapist_clients(therapist_id);
CREATE INDEX IF NOT EXISTS idx_therapist_clients_client_id ON therapist_clients(client_id);

-- ============================================================================
-- SECTION 5: AI & ANALYTICS
-- ============================================================================

-- AI Models registry
CREATE TABLE IF NOT EXISTS ai_models (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    version VARCHAR(50),
    description TEXT,
    model_type VARCHAR(100),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Emotion analyses (results from AI emotion detection)
CREATE TABLE IF NOT EXISTS emotion_analyses (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    input_text TEXT,
    detected_emotions TEXT[],
    confidence_scores JSONB DEFAULT '{}',
    sentiment_score NUMERIC(5,2),
    analysis_metadata JSONB DEFAULT '{}',
    model_id INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_emotion_analyses_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_emotion_analyses_ai_models FOREIGN KEY (model_id) REFERENCES ai_models(id)
);

CREATE INDEX IF NOT EXISTS idx_emotion_analyses_user_id ON emotion_analyses(user_id);
CREATE INDEX IF NOT EXISTS idx_emotion_analyses_created_at ON emotion_analyses(created_at);

-- ============================================================================
-- SECTION 6: VIDEO CONFERENCING
-- ============================================================================

-- Video meetings table
CREATE TABLE IF NOT EXISTS video_meetings (
    id SERIAL PRIMARY KEY,
    session_id INTEGER NOT NULL,
    provider VARCHAR(100),
    meeting_id VARCHAR(255),
    join_url TEXT,
    password VARCHAR(255),
    start_url TEXT,
    meeting_metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_video_meetings_therapy_sessions FOREIGN KEY (session_id) REFERENCES therapy_sessions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_video_meetings_session_id ON video_meetings(session_id);

-- ============================================================================
-- SECTION 7: SUPPORT & TICKETING SYSTEM
-- ============================================================================

-- Support tickets
CREATE TABLE IF NOT EXISTS support_tickets (
    id SERIAL PRIMARY KEY,
    ticket_number VARCHAR(50) UNIQUE,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    priority VARCHAR(50) DEFAULT 'medium',
    status VARCHAR(50) DEFAULT 'open',
    category_id INTEGER,
    requester_id INTEGER NOT NULL,
    assigned_agent_id INTEGER,
    organization_id INTEGER,
    source VARCHAR(50) DEFAULT 'web',
    tags TEXT[],
    attachments JSONB DEFAULT '{}',
    sla_breach_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_support_tickets_requester FOREIGN KEY (requester_id) REFERENCES users(id),
    CONSTRAINT fk_support_tickets_agent FOREIGN KEY (assigned_agent_id) REFERENCES users(id),
    CONSTRAINT fk_support_tickets_organization FOREIGN KEY (organization_id) REFERENCES organizations(id)
);

-- Ticket categories
CREATE TABLE IF NOT EXISTS ticket_categories (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    color VARCHAR(7),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ticket activities (comments, status changes, etc.)
CREATE TABLE IF NOT EXISTS ticket_activities (
    id SERIAL PRIMARY KEY,
    ticket_id INTEGER NOT NULL,
    user_id INTEGER NOT NULL,
    activity_type VARCHAR(100),
    content TEXT,
    is_internal BOOLEAN DEFAULT FALSE,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ticket_activities_tickets FOREIGN KEY (ticket_id) REFERENCES support_tickets(id) ON DELETE CASCADE,
    CONSTRAINT fk_ticket_activities_users FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Support agents
CREATE TABLE IF NOT EXISTS support_agents (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE,
    is_available BOOLEAN DEFAULT TRUE,
    current_ticket_count INTEGER DEFAULT 0,
    max_tickets INTEGER DEFAULT 10,
    performance_score NUMERIC(5,2) DEFAULT 0.0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_support_agents_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Ticket statistics (materialized view or table for performance)
CREATE TABLE IF NOT EXISTS ticket_statistics (
    id SERIAL PRIMARY KEY,
    total_tickets INTEGER DEFAULT 0,
    open_tickets INTEGER DEFAULT 0,
    average_resolution_time INTEGER,
    average_response_time INTEGER,
    calculated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_status ON support_tickets(status);
CREATE INDEX IF NOT EXISTS idx_support_tickets_priority ON support_tickets(priority);
CREATE INDEX IF NOT EXISTS idx_support_tickets_created_at ON support_tickets(created_at);
CREATE INDEX IF NOT EXISTS idx_support_tickets_requester_id ON support_tickets(requester_id);
CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned_agent_id ON support_tickets(assigned_agent_id);
CREATE INDEX IF NOT EXISTS idx_ticket_activities_ticket_id ON ticket_activities(ticket_id);

-- ============================================================================
-- SECTION 8: NOTIFICATION SYSTEM
-- ============================================================================

-- Notification logs
CREATE TABLE IF NOT EXISTS notification_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    title VARCHAR(255),
    body TEXT,
    data JSONB DEFAULT '{}',
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    notification_type VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_notification_logs_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_notification_logs_user_id ON notification_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_notification_logs_created_at ON notification_logs(created_at);

-- ============================================================================
-- SECTION 9: PAYMENT & BILLING
-- ============================================================================

-- Payment customers
CREATE TABLE IF NOT EXISTS payment_customers (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE,
    provider VARCHAR(50),
    customer_id VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payment_customers_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Payment intents
CREATE TABLE IF NOT EXISTS payment_intents (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    provider VARCHAR(50),
    intent_id VARCHAR(255) NOT NULL,
    amount INTEGER,
    currency VARCHAR(3),
    status VARCHAR(50),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_payment_intents_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_payment_intents_user_id ON payment_intents(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_intents_status ON payment_intents(status);

-- ============================================================================
-- SECTION 10: INTEGRATIONS
-- ============================================================================

-- Integration settings
CREATE TABLE IF NOT EXISTS integration_settings (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    integration_type VARCHAR(100),
    provider VARCHAR(100),
    settings JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_integration_settings_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE(user_id, integration_type, provider)
);

-- Calendar integrations
CREATE TABLE IF NOT EXISTS calendar_integrations (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    provider VARCHAR(100),
    access_token TEXT,
    refresh_token TEXT,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_calendar_integrations_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Calendar events
CREATE TABLE IF NOT EXISTS calendar_events (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    provider VARCHAR(100),
    external_event_id VARCHAR(255),
    title VARCHAR(255),
    description TEXT,
    start_time TIMESTAMP,
    end_time TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_calendar_events_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_calendar_integrations_user_id ON calendar_integrations(user_id);
CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id ON calendar_events(user_id);

-- ============================================================================
-- SECTION 11: AUDIT & COMPLIANCE
-- ============================================================================

-- Audit logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    action VARCHAR(255),
    resource_type VARCHAR(100),
    resource_id INTEGER,
    old_data JSONB,
    new_data JSONB,
    details JSONB DEFAULT '{}',
    ip_address VARCHAR(100),
    user_agent TEXT,
    success BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_logs_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL
);

-- Audit logs archive (for historical data)
CREATE TABLE IF NOT EXISTS audit_logs_archive (
    id SERIAL PRIMARY KEY,
    user_id INTEGER,
    action VARCHAR(255),
    resource_type VARCHAR(100),
    resource_id INTEGER,
    old_data JSONB,
    new_data JSONB,
    details JSONB DEFAULT '{}',
    ip_address VARCHAR(100),
    user_agent TEXT,
    success BOOLEAN,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Consent records (GDPR compliance)
CREATE TABLE IF NOT EXISTS consent_records (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    consent_type VARCHAR(100),
    consent_version VARCHAR(50),
    granted BOOLEAN DEFAULT FALSE,
    granted_at TIMESTAMP,
    revoked_at TIMESTAMP,
    ip_address VARCHAR(100),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_consent_records_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Data deletion requests
CREATE TABLE IF NOT EXISTS data_deletion_requests (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL UNIQUE,
    reason TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_data_deletion_requests_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Data processing activities (GDPR/HIPAA)
CREATE TABLE IF NOT EXISTS data_processing_activities (
    id SERIAL PRIMARY KEY,
    activity_name VARCHAR(255) NOT NULL,
    description TEXT,
    legal_basis VARCHAR(255),
    purpose TEXT,
    categories_processed TEXT[],
    retention_period INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON audit_logs(created_at);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_consent_records_user_id ON consent_records(user_id);
CREATE INDEX IF NOT EXISTS idx_data_deletion_requests_user_id ON data_deletion_requests(user_id);

-- ============================================================================
-- SECTION 12: REPORTING & DASHBOARDS
-- ============================================================================

-- Report schedules
CREATE TABLE IF NOT EXISTS report_schedules (
    id VARCHAR(255) PRIMARY KEY,
    report_type VARCHAR(100) NOT NULL,
    organization_id INTEGER,
    frequency VARCHAR(50),
    recipients TEXT[],
    format VARCHAR(50),
    created_by INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_report_schedules_organizations FOREIGN KEY (organization_id) REFERENCES organizations(id),
    CONSTRAINT fk_report_schedules_users FOREIGN KEY (created_by) REFERENCES users(id)
);

-- ============================================================================
-- SECTION 13: PUBLIC API
-- ============================================================================

-- Webhooks
CREATE TABLE IF NOT EXISTS webhooks (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL,
    url TEXT NOT NULL,
    events TEXT[] NOT NULL,
    secret VARCHAR(255),
    is_active BOOLEAN DEFAULT TRUE,
    failed_attempts INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_webhooks_users FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_webhooks_user_id ON webhooks(user_id);

-- ============================================================================
-- SECTION 14: TRIGGER FUNCTIONS FOR TIMESTAMPS
-- ============================================================================

-- Update timestamp trigger function (if not already exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply update_updated_at trigger to all tables with updated_at
DO $$
DECLARE
    v_tablename text;
BEGIN
    FOR v_tablename IN
        SELECT table_name FROM information_schema.tables 
        WHERE table_schema = 'public' 
        AND EXISTS (
            SELECT 1 FROM information_schema.columns c 
            WHERE c.table_schema = 'public' 
            AND c.table_name = information_schema.tables.table_name
            AND c.column_name = 'updated_at'
        )
    LOOP
        EXECUTE format('
            CREATE TRIGGER update_%s_updated_at
                BEFORE UPDATE ON %I
                FOR EACH ROW
                EXECUTE FUNCTION update_updated_at_column()',
            v_tablename, v_tablename
        );
    END LOOP;
END
$$;

-- ============================================================================
-- SECTION 15: INSERT INITIAL DATA
-- ============================================================================

-- Insert default AI models
ALTER TABLE ai_models ADD CONSTRAINT IF NOT EXISTS ai_models_name_unique UNIQUE (name);
INSERT INTO ai_models (name, version, description, model_type, is_active)
VALUES 
    ('Emotion Detection v1.0', '1.0.0', 'Primary emotion detection model', 'emotion_analysis', TRUE),
    ('Sentiment Analysis v1.0', '1.0.0', 'Sentiment analysis model', 'sentiment_analysis', TRUE),
    ('Conflict Prediction v1.0', '1.0.0', 'Conflict pattern prediction model', 'prediction', TRUE)
ON CONFLICT (name) DO NOTHING;

-- Insert default ticket categories
ALTER TABLE ticket_categories ADD CONSTRAINT IF NOT EXISTS ticket_categories_name_unique UNIQUE (name);
INSERT INTO ticket_categories (name, description, color, is_active)
VALUES
    ('Technical Issue', 'Technical or software-related problems', '#FF6B6B', TRUE),
    ('Billing', 'Billing and payment-related inquiries', '#4ECDC4', TRUE),
    ('Feature Request', 'Feature requests and enhancements', '#45B7D1', TRUE),
    ('Account', 'Account-related issues', '#FFA07A', TRUE),
    ('Other', 'Other inquiries', '#95E1D3', TRUE)
ON CONFLICT (name) DO NOTHING;

-- Insert default data processing activities (GDPR)
ALTER TABLE data_processing_activities ADD CONSTRAINT IF NOT EXISTS data_processing_activities_activity_name_unique UNIQUE (activity_name);
INSERT INTO data_processing_activities (activity_name, description, legal_basis, purpose, categories_processed, retention_period, is_active)
VALUES
    ('User Registration', 'Collection of user account information during registration', 'Consent', 'Account creation and management', ARRAY['email', 'name', 'password_hash'], 2555, TRUE),
    ('Emotion Check-ins', 'Storage of user emotion tracking data', 'Consent', 'Emotion monitoring and analysis', ARRAY['emotions', 'intensity', 'context'], 1825, TRUE),
    ('Therapy Sessions', 'Storage of therapy session records', 'Contract', 'Therapy service delivery', ARRAY['session_notes', 'duration', 'outcomes'], 2555, TRUE),
    ('Audit Logging', 'Recording of user actions for security and compliance', 'Legal Obligation', 'Security monitoring and audit trail', ARRAY['actions', 'timestamps', 'ip_address'], 1095, TRUE)
ON CONFLICT (activity_name) DO NOTHING;

-- ============================================================================
-- MIGRATION COMPLETION MARKER
-- ============================================================================

-- Record this migration in the migrations table

CREATE TABLE IF NOT EXISTS migrations (
    id SERIAL PRIMARY KEY,
    filename VARCHAR(255) UNIQUE NOT NULL,
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO migrations (filename) 
VALUES ('013_create_complete_schema.sql')
ON CONFLICT (filename) DO NOTHING;
