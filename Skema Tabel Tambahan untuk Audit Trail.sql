-- Menambahkan kolom audit trail pada journal_headers
ALTER TABLE journal_headers
ADD COLUMN created_by VARCHAR(50),
ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN hash_checksum VARCHAR(64);

-- Tabel audit log untuk mencatat semua aktivitas
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    table_name VARCHAR(50) NOT NULL,
    record_id INT NOT NULL,
    action VARCHAR(10) NOT NULL CHECK (action IN ('INSERT', 'UPDATE', 'DELETE', 'POST', 'REVERSE')),
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(50),
    changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Trigger untuk mencatat audit log pada journal_headers
CREATE OR REPLACE FUNCTION log_journal_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, record_id, action, new_values, changed_by)
        VALUES ('journal_headers', NEW.header_id, 'INSERT', to_jsonb(NEW), NEW.created_by);
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values, changed_by)
        VALUES ('journal_headers', NEW.header_id, 'UPDATE', to_jsonb(OLD), to_jsonb(NEW), NEW.created_by);
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, changed_by)
        VALUES ('journal_headers', OLD.header_id, 'DELETE', to_jsonb(OLD), current_user);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_journal_headers
    AFTER INSERT OR UPDATE OR DELETE ON journal_headers
    FOR EACH ROW
    EXECUTE FUNCTION log_journal_changes();