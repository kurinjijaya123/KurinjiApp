import SwiftUI
import UIKit

// MARK: Ledger
struct LedgerView: View {
    @State var rows = [Row](); @State var s = ""; @State var sheet = false
    var body: some View {
        Screen(title: "Customer Ledger") {
            List {
                Section { HStack { Text("Debit: " + rs(rows.reduce(0) { $0 + $1.d("debit") })).foregroundColor(K.bad); Text("Credit: " + rs(rows.reduce(0) { $0 + $1.d("credit") })).foregroundColor(K.ok) }.font(.system(size: 12, weight: .bold)) }
                ForEach(rows.indices, id: \.self) { i in let r = rows[i]
                    VStack(alignment: .leading, spacing: 3) {
                        HStack { Text(r.s("customer")).bold(); Spacer(); Text(r.s("type")).foregroundColor(K.pri).font(.caption) }
                        Text("\(r.s("date")) · \(r.s("description"))").font(.caption).foregroundColor(K.sub)
                        HStack { Text("Dr " + rs(r.d("debit"))).foregroundColor(K.bad); Text("Cr " + rs(r.d("credit"))).foregroundColor(K.ok); Spacer()
                            Text("Bal " + rs(r.d("balance"))).bold().foregroundColor(r.d("balance") > 0 ? K.bad : K.ok) }.font(.system(size: 12))
                    } }
            }
            .searchable(text: $s, prompt: "Filter by customer...").onChange(of: s) { _ in load() }
            .toolbar { Button("+ Entry") { sheet = true }.buttonStyle(BtnStyle()) }
            .sheet(isPresented: $sheet) { LedgerForm { load() } }
        }.onAppear(perform: load)
    }
    func load() { rows = s.isEmpty ? db.q("SELECT * FROM ledger ORDER BY id DESC") : db.q("SELECT * FROM ledger WHERE customer LIKE ? ORDER BY id DESC", ["%\(s)%"]) }
}
struct LedgerForm: View {
    var done: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var cust = ""; @State var date = Date(); @State var type = "Payment"; @State var desc = ""; @State var dr = "0"; @State var cr = "0"
    var body: some View {
        NavigationStack { Form {
            TextField("Customer *", text: $cust); DatePicker("Date", selection: $date, displayedComponents: .date)
            Picker("Type", selection: $type) { ForEach(["Bill", "Payment", "Credit", "Debit"], id: \.self) { Text($0) } }
            TextField("Description", text: $desc)
            HStack { Text("Debit"); TextField("0", text: $dr).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            HStack { Text("Credit"); TextField("0", text: $cr).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
        }.navigationTitle("Add Ledger Entry").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") {
                let d = Double(dr) ?? 0, c = Double(cr) ?? 0
                if !cust.trimmed.isEmpty { db.run("INSERT INTO ledger (date,customer,type,description,debit,credit,balance) VALUES (?,?,?,?,?,?,?)", [ymd(date), cust, type, desc, d, c, d - c]) }
                done(); dismiss() } } } }
    }
}

// MARK: Reports
struct ReportsView: View {
    @State var kind = "Sales Report"; @State var from = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!; @State var to = Date()
    @State var hd = [String](); @State var rows = [[String]](); @State var sum = ""
    var body: some View {
        Screen(title: "Reports") {
            List {
                Section { Picker("Report", selection: $kind) { ForEach(["Sales Report", "Purchase Report", "Stock Report", "Profit Report"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
                    DatePicker("From", selection: $from, displayedComponents: .date); DatePicker("To", selection: $to, displayedComponents: .date)
                    Button("Generate") { run() }.buttonStyle(BtnStyle(color: K.ok)) }
                if !sum.isEmpty { Section { Text(sum).bold().foregroundColor(K.ok) } }
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) { ForEach(hd.indices, id: \.self) { j in HStack { Text(hd[j]).font(.caption).foregroundColor(K.sub); Spacer(); Text(rows[i][j]).font(.system(size: 13)) } } }.padding(.vertical, 2) }
            }
        }.onAppear(perform: run).onChange(of: kind) { _ in run() }
    }
    func run() {
        let f = ymd(from), t = ymd(to)
        switch kind {
        case "Sales Report":
            let r = db.q("SELECT id,date,customer,discount,total FROM sales WHERE date BETWEEN ? AND ? ORDER BY date DESC", [f, t]); hd = ["#", "Date", "Customer", "Discount", "Total"]
            rows = r.map { ["#\($0.i("id"))", $0.s("date"), $0.s("customer").isEmpty ? "Walk-in" : $0.s("customer"), rs($0.d("discount")), rs($0.d("total"))] }
            sum = "Total Sales: " + rs(r.reduce(0) { $0 + $1.d("total") }) + "  (\(r.count) transactions)"
        case "Purchase Report":
            let r = db.q("SELECT id,date,supplier,total FROM purchases WHERE date BETWEEN ? AND ? ORDER BY date DESC", [f, t]); hd = ["#", "Date", "Supplier", "Total"]
            rows = r.map { ["#\($0.i("id"))", $0.s("date"), $0.s("supplier").isEmpty ? "N/A" : $0.s("supplier"), rs($0.d("total"))] }
            sum = "Total Purchases: " + rs(r.reduce(0) { $0 + $1.d("total") }) + "  (\(r.count) orders)"
        case "Stock Report":
            let r = db.q("SELECT * FROM products ORDER BY stock ASC"); hd = ["Product", "Category", "Unit", "Price", "Stock"]
            rows = r.map { [$0.s("name"), $0.s("category"), $0.s("unit"), rs($0.d("price")), "\($0.i("stock"))"] }
            sum = "Total Products: \(r.count)  |  Low Stock: \(r.filter { $0.d("stock") < 10 }.count)"
        default:
            let r = db.q("SELECT s.date,s.customer,s.total,COALESCE(SUM(si.qty*p.cost),0) cost FROM sales s JOIN sale_items si ON si.sale_id=s.id JOIN products p ON p.id=si.product_id WHERE s.date BETWEEN ? AND ? GROUP BY s.id ORDER BY s.date DESC", [f, t]); hd = ["Date", "Customer", "Revenue", "Cost", "Profit"]
            rows = r.map { [$0.s("date"), $0.s("customer").isEmpty ? "Walk-in" : $0.s("customer"), rs($0.d("total")), rs($0.d("cost")), rs($0.d("total") - $0.d("cost"))] }
            let rv = r.reduce(0) { $0 + $1.d("total") }, cs = r.reduce(0) { $0 + $1.d("cost") }
            sum = "Revenue: \(rs(rv))  |  Cost: \(rs(cs))  |  Profit: \(rs(rv - cs))"
        }
    }
}

// MARK: Invoice (view, PDF, WhatsApp)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}
struct InvoiceView: View {
    let id: Int
    @Environment(\.openURL) var openURL
    @State var sale = Row(); @State var items = [Row](); @State var prev = 0.0; @State var paid = 0.0; @State var pdf: URL?
    var cust: String { sale.s("customer") }
    var bt: Double { sale.d("total") }
    var grand: Double { prev + bt }
    var due: Double { max(0, grand - paid) }
    var body: some View {
        Screen(title: String(format: "INV-%04d", id)) {
            ScrollView { VStack(spacing: 12) {
                HStack { Button("📄 Print / Save PDF") { makePDF() }.buttonStyle(BtnStyle(color: K.warn))
                    Button("WhatsApp") { whatsapp() }.buttonStyle(BtnStyle(color: K.ok)) }
                sheet.padding(.vertical, 4)
            }.padding(12) }
        }.onAppear(perform: load).sheet(item: $pdf) { ShareSheet(url: $0) }
    }
    var sheet: some View {
        let ink = Color(hex: 0x1A2A4A)
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Image("logo1").resizable().scaledToFit().frame(width: 52)
                VStack(spacing: 2) { Text("KURINJI CUP SAMBARANI").font(.system(size: 15, weight: .bold)); Text("Premium Incense & Cup Products").font(.system(size: 9))
                    Text("Chellakutti Kadu, Kalarampatti, Erumapalayam, Salem - 636 015").font(.system(size: 8)); Text("+91 9994662878 | kurinjijaya123@email.com").font(.system(size: 8)) }.frame(maxWidth: .infinity)
                Image("logo").resizable().scaledToFit().frame(width: 52) }
            Rectangle().fill(ink).frame(height: 2)
            HStack(alignment: .top) { box("INVOICE DETAILS", [("Invoice No", String(format: "INV-%04d", id)), ("Date", sale.s("date"))]); box("BILL TO", [("Customer", cust.isEmpty ? "Walk-in" : cust)]) }
            VStack(spacing: 0) {
                row(["#", "Product", "Qty", "Price", "Amount"], head: true)
                ForEach(items.indices, id: \.self) { i in let it = items[i]; row(["\(i + 1)", it.s("name"), it.d("qty").clean + " " + (it.s("unit").isEmpty ? "pcs" : it.s("unit")), rs(it.d("price")), rs(it.d("total"))], alt: i % 2 == 0) } }
            VStack(spacing: 0) {
                kv("Subtotal", rs(items.reduce(0) { $0 + $1.d("total") }))
                if sale.d("discount") > 0 { kv("Discount (-)", "- " + rs(sale.d("discount")), K.warn) }
                kv("Bill Total", rs(bt), nil, true)
                if prev > 0 { kv("Previous Balance (+)", rs(prev), K.warn, true) }
                kv(prev > 0 ? "Grand Total" : "Total", rs(grand), K.ok, true); kv("Amount Paid (-)", rs(paid), K.ok, true)
                kv("Balance Due", rs(due), due > 0 ? K.bad : K.ok, true) }.frame(width: 220).frame(maxWidth: .infinity, alignment: .trailing)
            Text("Amount in Words: " + words(grand)).font(.system(size: 9, weight: .bold)).padding(6).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: 0xEEF4FF))
            Text("Thank you for your business! | Kurinji Cup Sambarani\nThis is a computer-generated invoice and does not require a signature.").font(.system(size: 8)).foregroundColor(.gray).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }.padding(16).foregroundColor(ink).background(.white).cornerRadius(8)
    }
    func box(_ t: String, _ r: [(String, String)]) -> some View {
        VStack(spacing: 0) { Text(t).font(.system(size: 9, weight: .bold)).foregroundColor(.white).frame(maxWidth: .infinity).padding(4).background(Color(hex: 0x1A2A4A))
            ForEach(r.indices, id: \.self) { HStack { Text(r[$0].0); Spacer(); Text(r[$0].1).bold() }.font(.system(size: 9)).padding(4) } }.overlay(Rectangle().stroke(Color(hex: 0xC8D0E8)))
    }
    func row(_ c: [String], head: Bool = false, alt: Bool = false) -> some View {
        HStack { ForEach(c.indices, id: \.self) { Text(c[$0]).frame(maxWidth: $0 == 1 ? .infinity : 62, alignment: $0 < 2 ? .leading : .trailing) } }
            .font(.system(size: 9, weight: head ? .bold : .regular)).foregroundColor(head ? .white : Color(hex: 0x1A2A4A)).padding(5)
            .background(head ? Color(hex: 0x1A2A4A) : (alt ? Color(hex: 0xEEF4FF) : .white))
    }
    func kv(_ a: String, _ b: String, _ c: Color? = nil, _ bold: Bool = false) -> some View {
        HStack { Text(a); Spacer(); Text(b) }.font(.system(size: 9, weight: bold ? .bold : .regular)).foregroundColor(c ?? Color(hex: 0x1A2A4A)).padding(5).overlay(Rectangle().stroke(Color(hex: 0xC8D0E8)))
    }
    func load() {
        sale = db.one("SELECT * FROM sales WHERE id=?", [id]) ?? [:]
        items = db.q("SELECT p.name,p.unit,si.qty,si.price,si.qty*si.price total FROM sale_items si JOIN products p ON p.id=si.product_id WHERE si.sale_id=?", [id])
        let lr = db.one("SELECT debit,credit,balance FROM ledger WHERE description LIKE ? AND customer=? ORDER BY id DESC LIMIT 1", [String(format: "INV-%04d%%", id), cust])
        let br = db.one("SELECT prev_balance,paid,balance_due FROM billing WHERE customer=? ORDER BY id DESC LIMIT 1", [cust])
        if let l = lr { paid = l.d("credit"); prev = max(0, l.d("debit") - bt) }
        else if let b = br { paid = b.d("paid"); prev = b.d("prev_balance") } else { paid = bt; prev = 0 }
    }
    @MainActor func makePDF() {
        let r = ImageRenderer(content: sheet.frame(width: 595).background(Color.white)); let url = FileManager.default.temporaryDirectory.appendingPathComponent(String(format: "INV-%04d.pdf", id))
        r.render { size, draw in var box = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            ctx.beginPDFPage(nil); draw(ctx); ctx.endPDFPage(); ctx.closePDF() }
        pdf = url
    }
    func whatsapp() {
        let t = "Dear \(cust.isEmpty ? "Customer" : cust),\nInvoice : \(String(format: "INV-%04d", id))\nDate    : \(sale.s("date"))\nTotal   : \(rs(bt))\nBalance : \(rs(due))\nThank you for your business!"
        if let e = t.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: "https://wa.me/?text=" + e) { openURL(u) }
    }
}
extension URL: @retroactive Identifiable { public var id: String { absoluteString } }
