-- Skenario: Dua kasir menjual item yang sama secara bersamaan
-- Kasir 1 dan Kasir 2 memulai transaksi secara bersamaan

-- Transaksi Kasir 1
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Kunci baris item yang akan dijual
SELECT stock_qty 
FROM inventory_items 
WHERE item_id = 'ITEM001' 
FOR UPDATE;

-- stock_qty = 1

INSERT INTO inventory_transactions (item_id, trx_type, qty)
VALUES ('ITEM001', 'SALE', 1);

-- Trigger akan memperbarui stock_qty menjadi 0
COMMIT;

-- Transaksi Kasir 2 (dimulai setelah Kasir 1 commit)
BEGIN;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

-- Kunci baris item yang akan dijual
SELECT stock_qty 
FROM inventory_items 
WHERE item_id = 'ITEM001' 
FOR UPDATE;

-- stock_qty = 0 (karena Kasir 1 sudah commit)

INSERT INTO inventory_transactions (item_id, trx_type, qty)
VALUES ('ITEM001', 'SALE', 1);

-- Trigger akan mencoba mengurangi stock_qty menjadi -1
-- RAISE EXCEPTION: Stok tidak mencukupi!
ROLLBACK;