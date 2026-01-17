import ./database
import ./query

type Cursor* = ref object of CursorBase
  db: Database

proc cursor*(db: Database): Cursor =
  Cursor(db: db)

proc database*(cur: Cursor): Database =
  cur.db
