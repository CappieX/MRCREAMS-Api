-- Security Events Table
-- Tracks security-related events for audit and monitoring purposes

CREATE TABLE IF NOT EXISTS security_events (
    id SERIAL PRIMARY KEY,
    event_type VARCHAR(255),
    description TEXT,
    ip_address VARCHAR(100),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index on event_type for faster queries
CREATE INDEX IF NOT EXISTS idx_security_events_event_type ON security_events(event_type);

-- Create index on created_at for time-based queries
CREATE INDEX IF NOT EXISTS idx_security_events_created_at ON security_events(created_at);

-- Create index on ip_address for security analysis
CREATE INDEX IF NOT EXISTS idx_security_events_ip_address ON security_events(ip_address);
