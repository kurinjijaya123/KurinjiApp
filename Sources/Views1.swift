import SwiftUI
import Charts

let db = DB.shared

// MARK: shared UI bits
struct Card<C: View>: View {
    @ViewBuilder var c: C
    var body: some View { c.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(K.card).clipShape(RoundedRectangle(cornerRadius: 12)) }
}
struct Pill: ViewModifier {
    var color: Color
    func body(content: Content) -> some View { content.font(.system(size: 11, weight: .bold)).padding(.horizontal, 10).padding(.vertical, 4).background(color.opacity(0.2)).foregroundColor(color).clipShape(Capsule()) }
}
struct BtnStyle: ButtonStyle {
    var color: Color = K.pri
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .bold)).foregroundColor(.white).padding(.horizontal, 14).padding(.vertical, 9)
            .background(color).clipShape(RoundedRectangle(cornerRadius: 6)).opacity(configuration.isPressed ? 0.8 : 1)
    }
}
struct Screen<C: View>: View {
    let title: String; @ViewBuilder var c: C
    var body: some View { c.background(K.bg.ignoresSafeArea()).navigationTitle(title).navigationBarTitleDisplayMode(.inline) }
}

// MARK: Login
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State var u = ""; @State var p = ""; @State var err = ""
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0xE8EEFA), Color(hex: 0xDCE6F7)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 6) {
                Image("logo1").resizable().scaledToFit().frame(width: 90, height: 90)
                Text("KURINJI").font(.system(size: 23, weight: .bold)).foregroundColor(K.navy)
                Text("Cup Sambarani - Inventory Management").font(.system(size: 13)).foregroundColor(K.sub).padding(.bottom, 16)
                if !err.isEmpty { Text(err).font(.system(size: 13)).foregroundColor(K.bad).padding(10).frame(maxWidth: .infinity).background(Color(hex: 0xFFF0F0)).cornerRadius(7) }
                field("Username") { TextField("Enter username", text: $u).textInputAutocapitalization(.never).autocorrectionDisabled() }
                field("Password") { SecureField("Enter password", text: $p) }
                Button("LOGIN") { if !app.login(u, p) { err = "Invalid username or password!" } }
                    .buttonStyle(BtnStyle()).frame(maxWidth: .infinity).padding(.top, 14)
                Text("© \(fmt(Date(), "yyyy")) Kurinji Cup Sambarani\nInventory Management System").multilineTextAlignment(.center)
                    .font(.system(size: 11)).foregroundColor(Color(hex: 0x8792AD)).padding(.top, 18)
            }
            .padding(28).background(.white).cornerRadius(18).shadow(color: K.navy.opacity(0.15), radius: 18, y: 8).padding(20)
        }
    }
    func field<C: View>(_ l: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l).font(.system(size: 13, weight: .semibold)).foregroundColor(Color(hex: 0x35436A))
            c().padding(12).background(Color(hex: 0xF7FAFF)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xD8DEEE))).cornerRadius(8)
        }.padding(.top, 8)
    }
}

// MARK: Root (sidebar -> tabs + More)
struct RootView: View {
    @EnvironmentObject var app: AppState
    @State var confirm = false
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Dashboard", systemImage: "square.grid.2x2") }
            NavigationStack { OrdersView() }.tabItem { Label("Orders", systemImage: "cart") }
            NavigationStack { SalesView(bills: false) }.tabItem { Label("Sales", systemImage: "indianrupeesign.circle") }
            NavigationStack { CrudView(cfg: CRUDS["products"]!) }.tabItem { Label("Products", systemImage: "shippingbox") }
            NavigationStack {
                List {
                    NavigationLink("Customers") { CrudView(cfg: CRUDS["customers"]!) }
                    NavigationLink("Suppliers") { CrudView(cfg: CRUDS["suppliers"]!) }
                    NavigationLink("Purchase") { PurchaseView() }
                    NavigationLink("Ledger") { LedgerView() }
                    NavigationLink("Bills") { SalesView(bills: true) }
                    NavigationLink("Reports") { ReportsView() }
                    Button { confirm = true } label: { HStack { Image("logout").resizable().frame(width: 26, height: 26).clipShape(Circle()); Text("Logout \(app.user ?? "")").foregroundColor(K.bad) } }
                }.navigationTitle("More")
            }.tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tint(K.pri)
        .alert("Are you sure you want to logout?", isPresented: $confirm) {
            Button("Logout", role: .destructive) { app.user = nil }; Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: Dashboard
struct Pt: Identifiable { let id = UUID(); let l: String; let v: Double }
func periodBars(_ p: String) -> [(String, String, String)] {
    var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2; let t = Date(); var o = [(String, String, String)]()
    if p == "Weekly" {
        let st = cal.dateInterval(of: .weekOfYear, for: t)!.start
        for i in stride(from: 7, through: 0, by: -1) { let s = cal.date(byAdding: .day, value: -7 * i, to: st)!; o.append(("W\(8 - i)", ymd(s), ymd(cal.date(byAdding: .day, value: 6, to: s)!))) }
    } else if p == "Monthly" {
        for i in stride(from: 5, through: 0, by: -1) { let m = cal.date(byAdding: .month, value: -i, to: t)!; let iv = cal.dateInterval(of: .month, for: m)!
            o.append((fmt(iv.start, "MMM"), ymd(iv.start), ymd(cal.date(byAdding: .day, value: -1, to: iv.end)!))) }
    } else {
        for i in stride(from: 6, through: 0, by: -1) { let d = cal.date(byAdding: .day, value: -i, to: t)!; o.append((fmt(d, "dd/MM"), ymd(d), ymd(d))) }
    }
    return o
}
struct DashboardView: View {
    @State var period = "Daily"; @State var sd = [Pt](); @State var pd = [Pt](); @State var stats = [(String, String, Color)](); @State var tx = [Row]()
    var body: some View {
        Screen(title: "Dashboard") {
            ScrollView { VStack(spacing: 10) {
                Text(fmt(Date(), "EEEE, dd MMMM yyyy")).font(.system(size: 12)).foregroundColor(K.sub).frame(maxWidth: .infinity, alignment: .trailing)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(stats.indices, id: \.self) { i in let s = stats[i]
                        VStack(alignment: .leading, spacing: 6) { Text(s.0).font(.system(size: 11)).foregroundColor(K.sub)
                            Text(s.1).font(.system(size: 18, weight: .bold)).foregroundColor(s.2) }
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(K.card).overlay(RoundedRectangle(cornerRadius: 12).stroke(s.2.opacity(0.2))).cornerRadius(12) }
                }
                Picker("", selection: $period) { ForEach(["Daily", "Weekly", "Monthly"], id: \.self) { Text($0) } }.pickerStyle(.segmented).onChange(of: period) { _ in load() }
                chart("Sales Chart", sd, K.ok); chart("Purchase Chart", pd, K.pri)
                Card { VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Transactions").bold()
                    ForEach(tx.indices, id: \.self) { i in let r = tx[i]
                        NavigationLink { InvoiceView(id: r.i("id")) } label: {
                            HStack { VStack(alignment: .leading) { Text(String(format: "INV-%04d", r.i("id"))).bold().foregroundColor(K.pri); Text("\(r.s("date")) · \(r.s("customer"))").font(.caption).foregroundColor(K.sub) }
                                Spacer(); VStack(alignment: .trailing) { Text(rs(r.d("total"))).bold().foregroundColor(K.ok)
                                    Text("Bal " + rs(r.d("balance"))).font(.caption).foregroundColor(r.d("balance") > 0 ? K.bad : K.ok) } }
                        }.buttonStyle(.plain); Divider() } } }
            }.padding(12) }
        }.onAppear(perform: load)
    }
    func chart(_ t: String, _ d: [Pt], _ c: Color) -> some View {
        Card { VStack(alignment: .leading) {
            HStack { Text(t).bold().foregroundColor(c); Spacer(); Text(rs(d.reduce(0) { $0 + $1.v })).bold().foregroundColor(c) }
            Chart(d) { LineMark(x: .value("p", $0.l), y: .value("v", $0.v)).foregroundStyle(c); AreaMark(x: .value("p", $0.l), y: .value("v", $0.v)).foregroundStyle(c.opacity(0.13)) }.frame(height: 160)
        } }
    }
    func load() {
        let b = periodBars(period)
        sd = b.map { Pt(l: $0.0, v: db.val("SELECT COALESCE(SUM(total),0) FROM sales WHERE date BETWEEN ? AND ?", [$0.1, $0.2])) }
        pd = b.map { Pt(l: $0.0, v: db.val("SELECT COALESCE(SUM(total),0) FROM purchases WHERE date BETWEEN ? AND ?", [$0.1, $0.2])) }
        stats = [("Customers", "\(Int(db.val("SELECT COUNT(*) FROM customers")))", K.pri), ("Suppliers", "\(Int(db.val("SELECT COUNT(*) FROM suppliers")))", K.warn),
                 ("Products", "\(Int(db.val("SELECT COUNT(*) FROM products")))", K.purple), ("Low Stock", "\(Int(db.val("SELECT COUNT(*) FROM products WHERE stock<10")))", K.bad),
                 ("Stock Value", rs(db.val("SELECT COALESCE(SUM(stock*cost),0) FROM products")), K.ok), ("Receivable", rs(db.val("SELECT COALESCE(SUM(balance_due),0) FROM billing WHERE balance_due>0")), Color(hex: 0xE03850))]
        tx = db.q("SELECT s.id,s.date,s.customer,s.total,COALESCE(l.balance,0) balance FROM sales s LEFT JOIN ledger l ON l.customer=s.customer AND l.description LIKE ('INV-'||printf('%04d',s.id)||'%') ORDER BY s.id DESC LIMIT 30")
    }
}

// MARK: Products / Customers / Suppliers
struct Fld { let key: String; let label: String; var num = false }
struct Crud { let table: String; let title: String; let fields: [Fld] }
let CRUDS: [String: Crud] = [
    "products": Crud(table: "products", title: "Products", fields: [Fld(key: "name", label: "Product Name"), Fld(key: "category", label: "Category"), Fld(key: "unit", label: "Unit"), Fld(key: "cost", label: "Cost Price", num: true), Fld(key: "price", label: "Selling Price", num: true), Fld(key: "stock", label: "Stock Qty", num: true)]),
    "customers": Crud(table: "customers", title: "Customers", fields: [Fld(key: "name", label: "Full Name *"), Fld(key: "phone", label: "Phone"), Fld(key: "email", label: "Email"), Fld(key: "address", label: "Address"), Fld(key: "notes", label: "Notes")]),
    "suppliers": Crud(table: "suppliers", title: "Suppliers", fields: [Fld(key: "name", label: "Contact Name *"), Fld(key: "company", label: "Company"), Fld(key: "phone", label: "Phone"), Fld(key: "email", label: "Email"), Fld(key: "address", label: "Address"), Fld(key: "notes", label: "Notes")]),
]
struct CrudView: View {
    let cfg: Crud
    @State var rows = [Row](); @State var s = ""; @State var edit: Row?; @State var form = false
    var body: some View {
        Screen(title: cfg.title) {
            List { ForEach(rows.indices, id: \.self) { i in let r = rows[i]
                Button { edit = r; form = true } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(r.s("name")).bold().foregroundColor(K.navy); Spacer()
                            if cfg.table == "products" { Text("Stock \(r.i("stock"))").modifier(Pill(color: r.d("stock") < 10 ? K.bad : K.ok)) } }
                        ForEach(cfg.fields.dropFirst().filter { $0.key != "stock" && !r.s($0.key).isEmpty }, id: \.key) { f in
                            Text("\(f.label): " + (["cost", "price"].contains(f.key) ? rs(r.d(f.key)) : r.s(f.key))).font(.system(size: 12)).foregroundColor(K.sub) }
                    } }
                .swipeActions { Button("Delete", role: .destructive) { db.run("DELETE FROM \(cfg.table) WHERE id=?", [r.i("id")]); load() } } } }
            .searchable(text: $s).onChange(of: s) { _ in load() }
            .toolbar { Button("+ Add") { edit = nil; form = true }.buttonStyle(BtnStyle(color: K.ok)) }
            .sheet(isPresented: $form) { CrudForm(cfg: cfg, rec: edit) { load() } }
        }.onAppear(perform: load)
    }
    func load() {
        let sc = cfg.fields.prefix(3).map { "\($0.key) LIKE ?" }.joined(separator: " OR ")
        rows = s.isEmpty ? db.q("SELECT * FROM \(cfg.table) ORDER BY name") : db.q("SELECT * FROM \(cfg.table) WHERE \(sc) ORDER BY name", Array(repeating: "%\(s)%", count: 3))
    }
}
struct CrudForm: View {
    let cfg: Crud; let rec: Row?; var done: () -> Void
    @Environment(\.dismiss) var dismiss; @State var v = [String: String]()
    var body: some View {
        NavigationStack { Form { ForEach(cfg.fields, id: \.key) { f in
            VStack(alignment: .leading) { Text(f.label).font(.caption).foregroundColor(K.sub)
                TextField(f.label, text: Binding(get: { v[f.key] ?? "" }, set: { v[f.key] = $0 })).keyboardType(f.num ? .decimalPad : .default) } } }
            .navigationTitle(cfg.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } } }
        }.onAppear { if let r = rec { for f in cfg.fields { v[f.key] = r.s(f.key) } } }
    }
    func save() {
        guard !(v["name"] ?? "").trimmed.isEmpty else { return }
        let vals: [Any] = cfg.fields.map { f in let x = (v[f.key] ?? "").trimmed; return f.num ? (Double(x) ?? 0) : (f.key == "unit" && x.isEmpty ? "pcs" : x) }
        let cols = cfg.fields.map { $0.key }
        if let r = rec { db.run("UPDATE \(cfg.table) SET " + cols.map { "\($0)=?" }.joined(separator: ",") + " WHERE id=?", vals + [r.i("id")]) }
        else { db.run("INSERT INTO \(cfg.table) (" + cols.joined(separator: ",") + ") VALUES (" + cols.map { _ in "?" }.joined(separator: ",") + ")", vals) }
        done(); dismiss()
    }
}
