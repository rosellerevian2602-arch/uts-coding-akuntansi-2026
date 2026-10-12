-- 1. Tabel chart_of_accounts
CREATE TABLE chart_of_accounts (
    account_id SERIAL PRIMARY KEY,
    account_code VARCHAR(20) NOT NULL UNIQUE,
    account_name VARCHAR(100) NOT NULL,
    normal_balance VARCHAR(6) NOT NULL CHECK (normal_balance IN ('DEBIT', 'CREDIT')),
    report_class VARCHAR(20) NOT NULL CHECK (report_class IN ('ASET', 'LIABILITAS', 'EKUITAS', 'PENDAPATAN', 'BEBAN'))
);

-- 2. Tabel journal_headers
CREATE TABLE journal_headers (
    header_id SERIAL PRIMARY KEY,
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    reference_number VARCHAR(50) NOT NULL,
    description TEXT,
    status_posting VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status_posting IN ('DRAFT', 'POSTED', 'VOID'))
);

-- 3. Tabel journal_lines
CREATE TABLE journal_lines (
    line_id SERIAL PRIMARY KEY,
    header_id INT NOT NULL,
    account_id INT NOT NULL,
    debit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
    credit NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
    
    -- Foreign Key dengan ON DELETE RESTRICT
    CONSTRAINT fk_journal_lines_header
        FOREIGN KEY (header_id)
        REFERENCES journal_headers(header_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    
    CONSTRAINT fk_journal_lines_account
        FOREIGN KEY (account_id)
        REFERENCES chart_of_accounts(account_id)
        ON DELETE RESTRICT
        ON UPDATE CASCADE,
    
    -- CHECK constraint: debit dan credit tidak boleh nol bersamaan
    CONSTRAINT chk_debit_credit_not_both_zero
        CHECK (NOT (debit = 0 AND credit = 0))
);

-- 4. Trigger untuk memastikan total debit = total kredit per header (double-entry constraint)
CREATE OR REPLACE FUNCTION check_journal_balance()
RETURNS TRIGGER AS $$
DECLARE
    total_debit NUMERIC(15,2);
    total_credit NUMERIC(15,2);
BEGIN
    SELECT COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
    INTO total_debit, total_credit
    FROM journal_lines
    WHERE header_id = COALESCE(NEW.header_id, OLD.header_id);
    
    -- Hanya periksa keseimbangan jika status posting bukan DRAFT
    IF EXISTS (
        SELECT 1 FROM journal_headers 
        WHERE header_id = COALESCE(NEW.header_id, OLD.header_id) 
        AND status_posting = 'POSTED'
    ) THEN
        IF total_debit != total_credit THEN
            RAISE EXCEPTION 'Journal entry tidak seimbang: Total Debit (%) != Total Kredit (%)', total_debit, total_credit;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_journal_balance
    AFTER INSERT OR UPDATE OR DELETE ON journal_lines
    FOR EACH ROW
    EXECUTE FUNCTION check_journal_balance();