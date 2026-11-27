import SwiftUI

// MARK: Cart (sale / purchase / order)
enum CartKind { case sale, purchase, order }
struct CartSheet: View {
    let kind: CartKind; var rid = 0; var seed: Row? = nil; var seedItems: [CartItem] = []; var done: (Int) -> Void
    @Environment(\.dismiss) var dismiss
    @State var party = ""; @State var date = Date(); @State var notes = ""; @State var orderNo = ""
    @State var disc = "0"; @State var tax = "0"; @State var paid = "0"
    @State var items = [CartItem](); @State var pid = 0; @State var qty = ""; @State var price = ""
    @State var products = [Row](); @State var parties = [String](); @State var msg = ""; @State var loaded = false
    var title: String { kind == .sale ? "New Sale" : kind == .purchase ? "Purchase" : "Customer Order" }
    var prev: Double { kind == .sale ? db.val("SELECT COALESCE(SUM(balance_due),0) FROM billing WHERE customer=? AND balance_due>0", [party.trimmed]) : 0 }
    var sub: Double { items.reduce(0) { $0 + $1.qty * $1.price } }
    var bill: Double { sub - (Double(disc) ?? 0) + (Double(tax) ?? 0) }
    var grand: Double { prev + bill }

    var body: some View {
        NavigationStack { Form {
            Section {
                if kind == .order { TextField("Order No (auto)", text: $orderNo) }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                HStack { TextField(kind == .purchase ? "Supplier" : "Customer", text: $party)
                    Menu { ForEach(parties, id: \.self) { n in Button(n) { party = n } } } label: { Image(systemName: "chevron.down.circle") } }
                if kind == .sale && prev > 0 { Label("Pending: " + rs(prev), systemImage: "exclamationmark.triangle").foregroundColor(K.warn).font(.system(size: 13, weight: .bold)) }
            }
            Section("Add item") {
                Picker("Product", selection: $pid) { Text("Select").tag(0); ForEach(products.indices, id: \.self) { Text(products[$0].s("name")).tag(products[$0].i("id")) } }
                    .onChange(of: pid) { _, id in if let p = products.first(where: { $0.i("id") == id }) { price = String(kind == .purchase ? p.d("cost") : p.d("price")) } }
                HStack { TextField("Qty", text: $qty).keyboardType(.decimalPad); TextField(kind == .purchase ? "Cost/unit" : "Price", text: $price).keyboardType(.decimalPad)
                    Button("+ Add", action: add).buttonStyle(BtnStyle()) }
                if !msg.isEmpty { Text(msg).foregroundColor(K.bad).font(.caption) }
            }
            Section("Items") {
                ForEach(items.indices, id: \.self) { i in HStack { VStack(alignment: .leading) { Text(items[i].name).bold(); Text("\(items[i].qty.clean) \(items[i].unit) × \(rs(items[i].price))").font(.caption).foregroundColor(K.sub) }
                    Spacer(); Text(rs(items[i].qty * items[i].price)).bold().foregroundColor(K.ok) } }.onDelete { items.remove(atOffsets: $0) }
            }
            Section {
                if kind != .purchase { HStack { Text("Discount"); TextField("0", text: $disc).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
                if kind == .sale { HStack { Text("Tax"); TextField("0", text: $tax).keyboardType(.decimalPad).multilineTextAlignment(.trailing) } }
                HStack { Text(prev > 0 ? "Bill \(rs(bill)) + Prev \(rs(prev)) = Grand" : "Total").bold(); Spacer(); Text(rs(grand)).bold().foregroundColor(K.pri) }
                if kind == .sale { HStack { Text("Paid"); TextField("0", text: $paid).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                    let b = grand - (Double(paid) ?? 0); HStack { Text("Balance").bold(); Spacer(); Text(rs(b)).bold().foregroundColor(b > 0 ? K.bad : K.ok) } }
                TextField("Notes (optional)", text: $notes)
            }
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button(kind == .sale ? "Save & Print" : "Save", action: save) } }
        }.onAppear(perform: setup)
    }
    func setup() {
        guard !loaded else { return }; loaded = true
        products = db.q("SELECT * FROM products ORDER BY name")
        parties = db.q("SELECT name FROM \(kind == .purchase ? "suppliers" : "customers") ORDER BY name").map { $0.s("name") }
        if let s = seed { party = s.s(kind == .purchase ? "supplier" : "customer"); date = parseDate(s.s("date")); notes = s.s("notes"); orderNo = s.s("order_no"); disc = s.s("discount").isEmpty ? "0" : s.s("discount"); items = seedItems }
    }
    func add() {
        guard let p = products.first(where: { $0.i("id") == pid }) else { msg = "Select a valid product."; return }
        guard let q = Double(qty), q > 0, let pr = Double(price) else { msg = "Enter valid Qty and Price."; return }
        if kind == .sale && q > p.d("stock") { msg = "Only \(p.s("stock")) \(p.s("unit")) in stock!"; return }
        items.append(CartItem(id: pid, name: p.s("name"), unit: p.s("unit").isEmpty ? "pcs" : p.s("unit"), qty: q, price: pr)); pid = 0; qty = ""; price = ""; msg = ""
    }
    func save() {
        if items.isEmpty { msg = "Add at least one item."; return }
        let d = ymd(date)
        switch kind {
        case .sale: done(db.saveSale(cust: party, date: d, items: items, disc: Double(disc) ?? 0, tax: Double(tax) ?? 0, paid: Double(paid) ?? 0, notes: notes))
        case .purchase: db.savePurchase(rid: rid, date: d, supplier: party, notes: notes, items: items); done(0)
        case .order: db.saveOrder(rid: rid, no: orderNo, date: d, customer: party, disc: Double(disc) ?? 0, notes: notes, items: items); done(0)
        }
        dismiss()
    }
}
extension Double { var clean: String { self == rounded() ? String(Int(self)) : String(self) } }

// MARK: Purchases
struct PurchaseView: View {
    @State var rows = [Row](); @State var s = ""; @State var sheet = false; @State var edit: (Int, Row, [CartItem])?
    var body: some View {
        Screen(title: "Purchases") {
            List(rows.indices, id: \.self) { i in let r = rows[i]
                Button { edit = (r.i("id"), r, db.q("SELECT pi.product_id id,p.name,p.unit,pi.qty,pi.cost price FROM purchase_items pi JOIN products p ON p.id=pi.product_id WHERE purchase_id=?", [r.i("id")]).map { CartItem(id: $0.i("id"), name: $0.s("name"), unit: $0.s("unit"), qty: $0.d("qty"), price: $0.d("price")) }); sheet = true } label: {
                    HStack { VStack(alignment: .leading) { Text(r.s("supplier").isEmpty ? "—" : r.s("supplier")).bold().foregroundColor(K.navy); Text(r.s("date") + (r.s("notes").isEmpty ? "" : " · " + r.s("notes"))).font(.caption).foregroundColor(K.sub) }
                        Spacer(); Text(rs(r.d("total"))).bold().foregroundColor(K.ok) } }
                .swipeActions { Button("Delete", role: .destructive) { db.deletePurchase(r.i("id")); load() } } }
            .searchable(text: $s, prompt: "Search by supplier...").onChange(of: s) { _, _ in load() }
            .toolbar { Button("+ New") { edit = nil; sheet = true }.buttonStyle(BtnStyle(color: K.ok)) }
            .sheet(isPresented: $sheet) { CartSheet(kind: .purchase, rid: edit?.0 ?? 0, seed: edit?.1, seedItems: edit?.2 ?? []) { _ in load() } }
        }.onAppear(perform: load)
    }
    func load() { rows = s.isEmpty ? db.q("SELECT * FROM purchases ORDER BY id DESC") : db.q("SELECT * FROM purchases WHERE supplier LIKE ? ORDER BY id DESC", ["%\(s)%"]) }
}

// MARK: Orders
struct OrdersView: View {
    @State var rows = [Row](); @State var st = "All Status"; @State var s = ""; @State var sheet = false
    @State var edit: (Int, Row, [CartItem])?; @State var flash = ""; @State var inv: Int?
    let col: [String: Color] = ["Pending": K.warn, "Confirmed": K.pri, "Delivered": K.ok, "Cancelled": K.sub]
    func cnt(_ x: String) -> Int { Int(db.val("SELECT COUNT(*) FROM orders WHERE status=?", [x])) }
    var body: some View {
        Screen(title: "Customer Orders") {
            List {
                Section { HStack { Text("Pending: \(cnt("Pending"))").foregroundColor(K.warn); Text("Confirmed: \(cnt("Confirmed"))").foregroundColor(K.pri); Text("Delivered: \(cnt("Delivered"))").foregroundColor(K.ok) }.font(.system(size: 12, weight: .bold))
                    Picker("Status", selection: $st) { ForEach(["All Status", "Pending", "Confirmed", "Delivered", "Cancelled"], id: \.self) { Text($0) } }.onChange(of: st) { _, _ in load() }
                    if !flash.isEmpty { Text(flash).font(.caption).foregroundColor(K.warn) } }
                ForEach(rows.indices, id: \.self) { i in let r = rows[i]; let status = r.s("status"); let c = col[status] ?? K.sub
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(r.s("order_no").isEmpty ? String(format: "ORD-%04d", r.i("id")) : r.s("order_no")).bold().foregroundColor(K.pri); Spacer(); Text(status).modifier(Pill(color: c)) }
                        HStack { Text(r.s("customer").isEmpty ? "—" : r.s("customer")); Spacer(); Text(rs(r.d("total"))).bold().foregroundColor(K.ok) }
                        Text(r.s("date") + (r.s("notes").isEmpty ? "" : " · " + r.s("notes"))).font(.caption).foregroundColor(K.sub)
                        HStack {
                            Button("Edit") { edit = (r.i("id"), r, db.q("SELECT product_id id,product_name name,unit,qty,price FROM order_items WHERE order_id=?", [r.i("id")]).map { CartItem(id: $0.i("id"), name: $0.s("name"), unit: $0.s("unit"), qty: $0.d("qty"), price: $0.d("price")) }); sheet = true }.buttonStyle(BtnStyle())
                            if status == "Pending" { Button("→ Conf") { setStatus(r, "Confirmed") }.buttonStyle(BtnStyle()) }
                            if status == "Confirmed" { Button("→ Deli") { setStatus(r, "Delivered") }.buttonStyle(BtnStyle(color: K.ok))
                                Button("Invoice") { let (id, e) = db.orderToInvoice(r.i("id")); if let id = id { inv = id } else { flash = e ?? ""; load() } }.buttonStyle(BtnStyle(color: K.ok)) }
                            if status == "Pending" || status == "Confirmed" { Button("✕") { setStatus(r, "Cancelled") }.buttonStyle(BtnStyle(color: K.bad)) }
                            if status == "Cancelled" { Button("Del") { db.run("DELETE FROM order_items WHERE order_id=?", [r.i("id")]); db.run("DELETE FROM orders WHERE id=?", [r.i("id")]); load() }.buttonStyle(BtnStyle(color: K.bad)) }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 4) }
            }
            .searchable(text: $s, prompt: "Customer or order no…").onChange(of: s) { _, _ in load() }
            .toolbar { Button("+ New") { edit = nil; sheet = true }.buttonStyle(BtnStyle(color: K.ok)) }
            .sheet(isPresented: $sheet) { CartSheet(kind: .order, rid: edit?.0 ?? 0, seed: edit?.1, seedItems: edit?.2 ?? []) { _ in load() } }
            .navigationDestination(item: $inv) { InvoiceView(id: $0) }
        }.onAppear(perform: load)
    }
    func setStatus(_ r: Row, _ x: String) { db.run("UPDATE orders SET status=? WHERE id=?", [x, r.i("id")]); load() }
    func load() {
        var w = [String](); var p = [Any]()
        if st != "All Status" { w.append("status=?"); p.append(st) }
        if !s.isEmpty { w.append("(customer LIKE ? OR order_no LIKE ?)"); p += ["%\(s)%", "%\(s)%"] }
        rows = db.q("SELECT * FROM orders" + (w.isEmpty ? "" : " WHERE " + w.joined(separator: " AND ")) + " ORDER BY id DESC", p)
    }
}

// MARK: Sales (bills == true -> Bills & Invoices list)
extension Int: @retroactive Identifiable { public var id: Int { self } }
struct SalesView: View {
    let bills: Bool
    @State var rows = [Row](); @State var s = ""; @State var sheet = false; @State var inv: Int?
    var body: some View {
        Screen(title: bills ? "Bills & Invoices" : "Sales Bills") {
            List(rows.indices, id: \.self) { i in let r = rows[i]
                NavigationLink { InvoiceView(id: r.i("id")) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(String(format: "INV-%04d", r.i("id"))).bold().foregroundColor(K.pri); Spacer(); Text(rs(r.d("total"))).bold() }
                        HStack { Text(r.s("customer").isEmpty ? "Walk-in" : r.s("customer")); Spacer()
                            if !bills { Text("Bal " + rs(r.d("balance"))).font(.caption).bold().foregroundColor(r.d("balance") > 0 ? K.bad : K.ok) } }
                        Text("\(r.s("date")) · Disc \(rs(r.d("discount")))").font(.caption).foregroundColor(K.sub)
                    } } }
            .searchable(text: $s, prompt: "Search by customer...").onChange(of: s) { _, _ in load() }
            .toolbar { if !bills { Button("+ New Sale") { sheet = true }.buttonStyle(BtnStyle(color: K.ok)) } }
            .sheet(isPresented: $sheet) { CartSheet(kind: .sale) { id in inv = id; load() } }
            .navigationDestination(item: $inv) { InvoiceView(id: $0) }
        }.onAppear(perform: load)
    }
    func load() {
        rows = db.q("SELECT s.id,s.date,s.customer,s.discount,s.total,COALESCE(l.balance,0) balance FROM sales s LEFT JOIN ledger l ON l.customer=s.customer AND l.description LIKE ('INV-'||printf('%04d',s.id)||'%')" + (s.isEmpty ? "" : " WHERE s.customer LIKE ?") + " GROUP BY s.id ORDER BY s.id DESC LIMIT 100", s.isEmpty ? [] : ["%\(s)%"])
    }
}
