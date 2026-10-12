-- Fungsi trigger untuk memperbarui stock_qty dan mencegah negative inventory
CREATE OR REPLACE FUNCTION trg_update_stock_and_journal()
RETURNS TRIGGER AS $$
DECLARE
    current_stock INT;
    new_stock INT;
BEGIN
    -- Ambil stok saat ini dengan penguncian baris untuk mencegah race condition
    SELECT stock_qty INTO current_stock
    FROM inventory_items
    WHERE item_id = NEW.item_id
    FOR UPDATE;
    
    -- Hitung stok baru berdasarkan jenis transaksi
    IF NEW.trx_type = 'PURCHASE' THEN
        new_stock := current_stock + NEW.qty;
    ELSIF NEW.trx_type = 'SALE' THEN
        new_stock := current_stock - NEW.qty;
    ELSIF NEW.trx_type = 'ADJUSTMENT' THEN
        new_stock := NEW.qty; -- ADJUSTMENT menetapkan stok baru secara langsung
    ELSE
        RAISE EXCEPTION 'Jenis transaksi tidak valid: %', NEW.trx_type;
    END IF;
    
    -- Anti-negative inventory prevention
    IF new_stock < 0 THEN
        RAISE EXCEPTION 'Stok tidak mencukupi untuk item %. Stok saat ini: %, diminta: %', 
            NEW.item_id, current_stock, NEW.qty;
    END IF;
    
    -- Perbarui stock_qty
    UPDATE inventory_items
    SET stock_qty = new_stock
    WHERE item_id = NEW.item_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger yang memanggil fungsi di atas
CREATE TRIGGER trg_update_stock_and_journal
    AFTER INSERT ON inventory_transactions
    FOR EACH ROW
    EXECUTE FUNCTION trg_update_stock_and_journal();