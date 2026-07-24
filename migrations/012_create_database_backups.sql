-- Database backup tracking table for Platform Admin
CREATE TABLE IF NOT EXISTS database_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES users(id),
    destination VARCHAR(50) NOT NULL DEFAULT 'cloud',
    size_mb INTEGER,
    encrypted BOOLEAN DEFAULT false,
    status VARCHAR(50) NOT NULL DEFAULT 'completed',
    metadata JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_database_backups_created_at
    ON database_backups (created_at DESC);

