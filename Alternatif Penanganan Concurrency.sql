CREATE OR REPLACE PROCEDURE process_sale(
    p_item_id VARCHAR(10),
    p_qty INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stock INT;
BEGIN
    -- Kunci baris item
    SELECT stock_qty INTO v_stock
    FROM inventory_items
    WHERE item_id = p_item_id
    FOR UPDATE;
    
    -- Periksa ketersediaan stok
    IF v_stock < p_qty THEN
        RAISE EXCEPTION 'Stok tidak mencukupi. Tersedia: %, diminta: %', v_stock, p_qty;
    END IF;
    
    -- Catat transaksi
    INSERT INTO inventory_transactions (item_id, trx_type, qty)
    VALUES (p_item_id, 'SALE', p_qty);
    
    -- Trigger akan memperbarui stock_qty secara otomatis
END;
$$;