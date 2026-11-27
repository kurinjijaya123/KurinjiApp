import Foundation
import SQLite3

typealias Row = [String: Any]
extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String {
        if let v = self[k] as? String { return v }
        if let d = self[k] as? Double { return d == d.rounded() ? String(Int(d)) : String(d) }
        if let i = self[k] as? Int { return String(i) }
        return ""
    }
    func d(_ k: String) -> Double { (self[k] as? Double) ?? Double((self[k] as? Int) ?? 0) }
    func i(_ k: String) -> Int { (self[k] as? Int) ?? Int((self[k] as? Double) ?? 0) }
}
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

struct CartItem: Identifiable { let id: Int; var name: String; var unit: String; var qty: Double; var price: Double }

func ymd(_ d: Date = Date()) -> String { fmt(d, "yyyy-MM-dd") }
func fmt(_ d: Date, _ f: String) -> String {
    let x = DateFormatter(); x.dateFormat = f; x.locale = Locale(identifier: "en_US_POSIX")
    x.timeZone = TimeZone(identifier: "Asia/Kolkata"); return x.string(from: d)
}
func parseDate(_ s: String) -> Date { let x = DateFormatter(); x.dateFormat = "yyyy-MM-dd"; return x.date(from: s) ?? Date() }
func rs(_ v: Double) -> String {
    let n = NumberFormatter(); n.numberStyle = .decimal; n.minimumFractionDigits = 2; n.maximumFractionDigits = 2
    return "₹" + (n.string(from: NSNumber(value: v)) ?? "0.00")
}
func words(_ n: Double) -> String {
    let o = ["","One","Two","Three","Four","Five","Six","Seven","Eight","Nine","Ten","Eleven","Twelve","Thirteen","Fourteen","Fifteen","Sixteen","Seventeen","Eighteen","Nineteen"]
    let t = ["","","Twenty","Thirty","Forty","Fifty","Sixty","Seventy","Eighty","Ninety"]
    func w(_ n: Int) -> String {
        if n == 0 { return "" }; if n < 20 { return o[n] }
        if n < 100 { return t[n / 10] + (n % 10 > 0 ? " " + o[n % 10] : "") }
        if n < 1000 { return o[n / 100] + " Hundred" + (n % 100 > 0 ? " " + w(n % 100) : "") }
        if n < 100000 { return w(n / 1000) + " Thousand" + (n % 1000 > 0 ? " " + w(n % 1000) : "") }
        if n < 10000000 { return w(n / 100000) + " Lakh" + (n % 100000 > 0 ? " " + w(n % 100000) : "") }
        return w(n / 10000000) + " Crore" + (n % 10000000 > 0 ? " " + w(n % 10000000) : "")
    }
    let r = Int(n), p = Int(((n - Double(r)) * 100).rounded())
    return (r > 0 ? w(r) : "Zero") + " Rupees" + (p > 0 ? " and " + w(p) + " Paise" : "") + " Only"
}

final class DB {
    static let shared = DB()
    var db: OpaquePointer?
    private let T = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("inventory.db")
        if !FileManager.default.fileExists(atPath: url.path), let b = Bundle.main.url(forResource: "inventory", withExtension: "db") {
            try? FileManager.default.copyItem(at: b, to: url)
        }
        sqlite3_open(url.path, &db)
        sqlite3_exec(db, """
        CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category TEXT, unit TEXT DEFAULT 'pcs', cost REAL DEFAULT 0, price REAL DEFAULT 0, stock REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS purchases (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, supplier TEXT, total REAL DEFAULT 0, notes TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS purchase_items (id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER, product_id INTEGER, qty REAL, cost REAL);
        CREATE TABLE IF NOT EXISTS sales (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, customer TEXT, total REAL DEFAULT 0, discount REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS sale_items (id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, product_id INTEGER, qty REAL, price REAL);
        CREATE TABLE IF NOT EXISTS customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT DEFAULT '', email TEXT DEFAULT '', address TEXT DEFAULT '', notes TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS suppliers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, phone TEXT DEFAULT '', email TEXT DEFAULT '', address TEXT DEFAULT '', company TEXT DEFAULT '', notes TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS billing (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, customer TEXT, prev_balance REAL DEFAULT 0, subtotal REAL DEFAULT 0, discount REAL DEFAULT 0, total REAL DEFAULT 0, paid REAL DEFAULT 0, balance_due REAL DEFAULT 0, notes TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT, customer TEXT, type TEXT, description TEXT, debit REAL DEFAULT 0, credit REAL DEFAULT 0, balance REAL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS orders (id INTEGER PRIMARY KEY AUTOINCREMENT, order_no TEXT DEFAULT '', date TEXT, customer TEXT, status TEXT DEFAULT 'Pending', subtotal REAL DEFAULT 0, discount REAL DEFAULT 0, total REAL DEFAULT 0, notes TEXT DEFAULT '');
        CREATE TABLE IF NOT EXISTS order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, order_id INTEGER, product_id INTEGER, product_name TEXT, unit TEXT DEFAULT 'pcs', qty REAL DEFAULT 1, price REAL DEFAULT 0, amount REAL DEFAULT 0);
        """, nil, nil, nil)
    }

    private func prep(_ sql: String, _ p: [Any]) -> OpaquePointer? {
        var st: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &st, nil)
        for (n, v) in p.enumerated() {
            let i = Int32(n + 1)
            switch v {
            case let x as Int: sqlite3_bind_int64(st, i, Int64(x))
            case let x as Int64: sqlite3_bind_int64(st, i, x)
            case let x as Double: sqlite3_bind_double(st, i, x)
            case let x as String: sqlite3_bind_text(st, i, x, -1, T)
            default: sqlite3_bind_null(st, i)
            }
        }
        return st
    }
    @discardableResult func run(_ sql: String, _ p: [Any] = []) -> Int {
        let st = prep(sql, p); sqlite3_step(st); sqlite3_finalize(st)
        return Int(sqlite3_last_insert_rowid(db))
    }
    func q(_ sql: String, _ p: [Any] = []) -> [Row] {
        let st = prep(sql, p); var out = [Row]()
        while sqlite3_step(st) == SQLITE_ROW {
            var r = Row()
            for c in 0..<sqlite3_column_count(st) {
                let k = String(cString: sqlite3_column_name(st, c))
                switch sqlite3_column_type(st, c) {
                case SQLITE_INTEGER: r[k] = Int(sqlite3_column_int64(st, c))
                case SQLITE_FLOAT: r[k] = sqlite3_column_double(st, c)
                case SQLITE_TEXT: r[k] = String(cString: sqlite3_column_text(st, c))
                default: break
                }
            }
            out.append(r)
        }
        sqlite3_finalize(st); return out
    }
    func one(_ sql: String, _ p: [Any] = []) -> Row? { q(sql, p).first }
    func val(_ sql: String, _ p: [Any] = []) -> Double { one(sql, p)?.values.first.map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) } ?? 0 }

    // MARK: business rules (ported 1:1 from app.php)
    func saveSale(cust: String, date: String, items: [CartItem], disc: Double, tax: Double, paid: Double, notes: String) -> Int {
        let c = cust.trimmed.isEmpty ? "Walk-in" : cust.trimmed
        let sub = items.reduce(0) { $0 + $1.qty * $1.price }
        let prev = val("SELECT COALESCE(SUM(balance_due),0) FROM billing WHERE customer=? AND balance_due>0", [c])
        let bill = sub - disc + tax, grand = prev + bill, bal = grand - paid
        let sid = run("INSERT INTO sales (date,customer,total,discount) VALUES (?,?,?,?)", [date, c, bill, disc])
        for i in items {
            run("INSERT INTO sale_items (sale_id,product_id,qty,price) VALUES (?,?,?,?)", [sid, i.id, i.qty, i.price])
            run("UPDATE products SET stock=stock-? WHERE id=?", [i.qty, i.id])
        }
        if let eb = one("SELECT id FROM billing WHERE customer=? ORDER BY id DESC LIMIT 1", [c]) {
            run("UPDATE billing SET date=?,prev_balance=?,subtotal=subtotal+?,discount=discount+?,total=total+?,paid=paid+?,balance_due=?,notes=? WHERE id=?", [date, prev, sub, disc, bill, paid, bal, notes, eb.i("id")])
        } else {
            run("INSERT INTO billing (date,customer,prev_balance,subtotal,discount,total,paid,balance_due,notes) VALUES (?,?,?,?,?,?,?,?,?)", [date, c, prev, sub, disc, bill, paid, bal, notes])
        }
        let desc = String(format: "INV-%04d", sid) + (prev > 0 ? "  (prev bal Rs." + String(format: "%.2f", prev) + ")" : "")
        run("INSERT INTO ledger (date,customer,type,description,debit,credit,balance) VALUES (?,?,?,?,?,?,?)", [date, c, "Sale", desc, grand, paid, bal])
        return sid
    }
    func savePurchase(rid: Int, date: String, supplier: String, notes: String, items: [CartItem]) {
        var id = rid
        if id > 0 {
            for it in q("SELECT * FROM purchase_items WHERE purchase_id=?", [id]) { run("UPDATE products SET stock=stock-? WHERE id=?", [it.d("qty"), it.i("product_id")]) }
            run("DELETE FROM purchase_items WHERE purchase_id=?", [id])
        }
        let grand = items.reduce(0) { $0 + $1.qty * $1.price }
        if id > 0 { run("UPDATE purchases SET date=?,supplier=?,total=?,notes=? WHERE id=?", [date, supplier, grand, notes, id]) }
        else { id = run("INSERT INTO purchases (date,supplier,total,notes) VALUES (?,?,?,?)", [date, supplier, grand, notes]) }
        for i in items {
            run("INSERT INTO purchase_items (purchase_id,product_id,qty,cost) VALUES (?,?,?,?)", [id, i.id, i.qty, i.price])
            run("UPDATE products SET stock=stock+?, cost=? WHERE id=?", [i.qty, i.price, i.id])
        }
    }
    func deletePurchase(_ id: Int) {
        for it in q("SELECT * FROM purchase_items WHERE purchase_id=?", [id]) { run("UPDATE products SET stock=stock-? WHERE id=?", [it.d("qty"), it.i("product_id")]) }
        run("DELETE FROM purchase_items WHERE purchase_id=?", [id]); run("DELETE FROM purchases WHERE id=?", [id])
    }
    func saveOrder(rid: Int, no: String, date: String, customer: String, disc: Double, notes: String, items: [CartItem]) {
        let sub = items.reduce(0) { $0 + $1.qty * $1.price }, total = max(0, sub - disc); var id = rid
        if id > 0 {
            run("DELETE FROM order_items WHERE order_id=?", [id])
            run("UPDATE orders SET order_no=?,date=?,customer=?,subtotal=?,discount=?,total=?,notes=? WHERE id=?", [no, date, customer, sub, disc, total, notes, id])
        } else {
            id = run("INSERT INTO orders (order_no,date,customer,status,subtotal,discount,total,notes) VALUES (?,?,?,?,?,?,?,?)", [no, date, customer, "Pending", sub, disc, total, notes])
            run("UPDATE orders SET order_no=? WHERE id=? AND order_no=''", [String(format: "ORD-%04d", id), id])
        }
        for i in items { run("INSERT INTO order_items (order_id,product_id,product_name,unit,qty,price,amount) VALUES (?,?,?,?,?,?,?)", [id, i.id, i.name, i.unit, i.qty, i.price, i.qty * i.price]) }
    }
    /// Returns invoice id, or an error message
    func orderToInvoice(_ oid: Int) -> (Int?, String?) {
        guard let o = one("SELECT * FROM orders WHERE id=?", [oid]) else { return (nil, "Order not found.") }
        let items = q("SELECT * FROM order_items WHERE order_id=?", [oid])
        if items.isEmpty { return (nil, "Order has no items.") }
        for it in items { let st = val("SELECT stock FROM products WHERE id=?", [it.i("product_id")])
            if it.d("qty") > st { return (nil, "Insufficient stock for \(it.s("product_name")) (available \(Int(st)))") } }
        let cust = o.s("customer").isEmpty ? "Walk-in" : o.s("customer"), disc = o.d("discount"), bt = o.d("total")
        let prev = val("SELECT balance_due FROM billing WHERE customer=? ORDER BY id DESC LIMIT 1", [cust]), grand = prev + bt
        let sid = run("INSERT INTO sales (date,customer,total,discount) VALUES (?,?,?,?)", [o.s("date"), cust, bt, disc])
        var sub = 0.0
        for it in items {
            sub += it.d("qty") * it.d("price")
            run("INSERT INTO sale_items (sale_id,product_id,qty,price) VALUES (?,?,?,?)", [sid, it.i("product_id"), it.d("qty"), it.d("price")])
            run("UPDATE products SET stock=stock-? WHERE id=?", [it.d("qty"), it.i("product_id")])
        }
        if let eb = one("SELECT id FROM billing WHERE customer=? ORDER BY id DESC LIMIT 1", [cust]) {
            run("UPDATE billing SET date=?,prev_balance=?,subtotal=subtotal+?,discount=discount+?,total=total+?,balance_due=? WHERE id=?", [o.s("date"), prev, sub, disc, bt, grand, eb.i("id")])
        } else {
            run("INSERT INTO billing (date,customer,prev_balance,subtotal,discount,total,paid,balance_due,notes) VALUES (?,?,?,?,?,?,?,?,?)", [o.s("date"), cust, prev, sub, disc, bt, 0.0, grand, o.s("notes")])
        }
        let no = o.s("order_no").isEmpty ? String(oid) : o.s("order_no")
        run("INSERT INTO ledger (date,customer,type,description,debit,credit,balance) VALUES (?,?,?,?,?,?,?)", [o.s("date"), cust, "Sale", String(format: "INV-%04d (from ORD %@)", sid, no), grand, 0.0, grand])
        run("UPDATE orders SET status='Delivered' WHERE id=?", [oid])
        return (sid, nil)
    }
}
