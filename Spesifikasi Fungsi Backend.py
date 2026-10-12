from fastapi import FastAPI, HTTPException, Depends
from pydantic import BaseModel
from typing import Optional
from datetime import datetime
import hashlib
import asyncpg

app = FastAPI()

# Model untuk jurnal
class JournalEntry(BaseModel):
    header_id: int
    transaction_date: str
    reference_number: str
    description: str
    lines: list

# Koneksi database
async def get_db():
    conn = await asyncpg.connect(
        user="user",
        password="password",
        database="accounting_db",
        host="localhost"
    )
    try:
        yield conn
    finally:
        await conn.close()

# Fungsi untuk mengunci transaksi POSTED
async def lock_posted_transaction(header_id: int, db: asyncpg.Connection):
    """
    Mengunci transaksi yang berstatus POSTED agar tidak dapat diubah atau dihapus.
    """
    # Periksa status posting
    status = await db.fetchval(
        "SELECT status_posting FROM journal_headers WHERE header_id = $1",
        header_id
    )
    
    if status == 'POSTED':
        raise HTTPException(
            status_code=403,
            detail="Transaksi POSTED tidak dapat diubah. Gunakan jurnal pembalik (reversing entry)."
        )
    
    return True

# Endpoint untuk membuat jurnal baru
@app.post("/journal/create")
async def create_journal(entry: JournalEntry, db: asyncpg.Connection = Depends(get_db)):
    """
    Membuat jurnal baru dengan status DRAFT.
    """
    async with db.transaction():
        # Insert header
        header_id = await db.fetchval(
            """
            INSERT INTO journal_headers (transaction_date, reference_number, description, status_posting)
            VALUES ($1, $2, $3, 'DRAFT')
            RETURNING header_id
            """,
            entry.transaction_date,
            entry.reference_number,
            entry.description
        )
        
        # Insert lines
        for line in entry.lines:
            await db.execute(
                """
                INSERT INTO journal_lines (header_id, account_id, debit, credit)
                VALUES ($1, $2, $3, $4)
                """,
                header_id,
                line['account_id'],
                line.get('debit', 0),
                line.get('credit', 0)
            )
        
        return {"header_id": header_id, "status": "DRAFT"}

# Endpoint untuk posting jurnal
@app.post("/journal/{header_id}/post")
async def post_journal(header_id: int, user_id: str, db: asyncpg.Connection = Depends(get_db)):
    """
    Memposting jurnal: mengubah status dari DRAFT menjadi POSTED.
    Menambahkan audit trail: created_by, created_at, hash_checksum.
    """
    async with db.transaction():
        # Periksa keseimbangan
        totals = await db.fetchrow(
            """
            SELECT COALESCE(SUM(debit), 0) as total_debit,
                   COALESCE(SUM(credit), 0) as total_credit
            FROM journal_lines
            WHERE header_id = $1
            """,
            header_id
        )
        
        if totals['total_debit'] != totals['total_credit']:
            raise HTTPException(
                status_code=400,
                detail=f"Jurnal tidak seimbang: Debit={totals['total_debit']}, Kredit={totals['total_credit']}"
            )
        
        # Hitung hash_checksum untuk integritas data
        journal_data = await db.fetch(
            "SELECT line_id, account_id, debit, credit FROM journal_lines WHERE header_id = $1 ORDER BY line_id",
            header_id
        )
        
        data_string = f"{header_id}|{entry.transaction_date}|{entry.reference_number}|"
        for row in journal_data:
            data_string += f"{row['line_id']}:{row['account_id']}:{row['debit']}:{row['credit']}|"
        
        hash_checksum = hashlib.sha256(data_string.encode()).hexdigest()
        
        # Update status dan audit trail
        await db.execute(
            """
            UPDATE journal_headers
            SET status_posting = 'POSTED',
                created_by = $1,
                created_at = $2,
                hash_checksum = $3
            WHERE header_id = $4
            """,
            user_id,
            datetime.now(),
            hash_checksum,
            header_id
        )
        
        return {"header_id": header_id, "status": "POSTED", "hash_checksum": hash_checksum}

# Endpoint untuk reversing entry
@app.post("/journal/{header_id}/reverse")
async def reverse_journal(header_id: int, user_id: str, db: asyncpg.Connection = Depends(get_db)):
    """
    Membuat jurnal pembalik (reversing entry) untuk transaksi POSTED.
    """
    async with db.transaction():
        # Periksa status
        status = await db.fetchval(
            "SELECT status_posting FROM journal_headers WHERE header_id = $1",
            header_id
        )
        
        if status != 'POSTED':
            raise HTTPException(
                status_code=400,
                detail="Hanya transaksi POSTED yang dapat dibalik."
            )
        
        # Buat header baru untuk reversing entry
        new_header_id = await db.fetchval(
            """
            INSERT INTO journal_headers (transaction_date, reference_number, description, status_posting, created_by, created_at)
            VALUES (CURRENT_DATE, $1, $2, 'POSTED', $3, $4)
            RETURNING header_id
            """,
            f"REV-{header_id}",
            f"Reversing entry untuk header {header_id}",
            user_id,
            datetime.now()
        )
        
        # Salin baris jurnal dengan debit/kredit ditukar
        original_lines = await db.fetch(
            "SELECT account_id, debit, credit FROM journal_lines WHERE header_id = $1",
            header_id
        )
        
        for line in original_lines:
            await db.execute(
                """
                INSERT INTO journal_lines (header_id, account_id, debit, credit)
                VALUES ($1, $2, $3, $4)
                """,
                new_header_id,
                line['account_id'],
                line['credit'],  # Debit dan kredit ditukar
                line['debit']
            )
        
        return {"reversing_header_id": new_header_id, "original_header_id": header_id}