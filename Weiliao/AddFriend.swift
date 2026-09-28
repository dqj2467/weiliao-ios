import SwiftUI

// ============================================================
// 添加好友 / 新的朋友（v1.22 2026-09-28，与安卓 AddFriendActivity/FriendReqActivity 同构）
//   AddFriendSheet：通讯录「+」→ 搜微聊号/账号/昵称 → 发申请（需对方同意）
//   FriendReqSheet：「新的朋友」→ 同意/拒绝（同意=服务端建双向好友）
// 复用 H5 搜索：POST /Home/Search/doSearch.html kw=
// ============================================================

/// 通讯录页 sheet 路由（单一 .sheet(item:)，避免多弹层互相顶掉）
enum ContactSheetKind: Int, Identifiable {
    case addFriend = 1
    case friendReqs = 2
    var id: Int { rawValue }
}

struct SearchUser: Identifiable {
    let id: Int64
    var name: String
    var face: String
    var weihao: String
    var isFriend: Bool
    var sent: Bool
    var sending: Bool
}

struct AddFriendSheet: View {
    @Environment(\.presentationMode) var mode
    @State var kw = ""
    @State var users: [SearchUser] = []
    @State var searched = false
    @State var msg = ""

    var body: some View {
        VStack(spacing: 0) {
            sheetHead("添加好友")
            HStack(spacing: 8) {
                TextField("微聊号 / 账号 / 昵称", text: $kw)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10).frame(height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xF7F7F7))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB))))
                Button(action: search) {
                    Text("搜索").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                        .frame(width: 64, height: 36).background(Color(hex: 0x07C160)).cornerRadius(6)
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)

            Text("输入微聊号精确匹配，也可以搜昵称；加好友需对方同意")
                .font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 15)

            if !msg.isEmpty {
                Text(msg).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151)).padding(.top, 8)
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(users) { u in
                        HStack(spacing: 12) {
                            Avatar(url: u.face, fallback: u.name, size: 42)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(u.name).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                                Text("微聊号 " + (u.weihao.isEmpty ? String(u.id) : u.weihao))
                                    .font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                            }
                            Spacer()
                            Button(action: { add(u) }) {
                                Text(u.isFriend ? "已添加" : (u.sent ? "已发送" : "添加"))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Color(hex: (u.isFriend || u.sent) ? 0x999999 : 0x07C160))
                                    .padding(.horizontal, 14).padding(.vertical, 5)
                                    .overlay(RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color(hex: (u.isFriend || u.sent) ? 0xCCCCCC : 0x07C160)))
                            }.buttonStyle(.plain).disabled(u.isFriend || u.sent || u.sending)
                        }
                        .padding(.horizontal, 15).padding(.vertical, 8)
                        .background(Color.white)
                    }
                }
            }
        }
        .background(Color(hex: 0xF5F6F7))
    }

    private func search() {
        let k = kw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { PayDialogs.toast("请输入搜索内容"); return }
        msg = ""
        Api.shared.post("/Home/Search/doSearch.html", form: ["kw": k]) { r in
            DispatchQueue.main.async {
                var out: [SearchUser] = []
                if let r = r, (r.status == 200 || r.status == 1), let d = r.data {
                    for row in d.arrIn("users") {
                        out.append(SearchUser(id: row.long("id"),
                                              name: row.str("nickname"),
                                              face: row.str("headimgurl"),
                                              weihao: row.str("weihao"),
                                              isFriend: row.int("is_friend") == 1,
                                              sent: false, sending: false))
                    }
                    users = out
                    searched = true
                    if out.isEmpty { msg = "没有找到相关用户" }
                } else {
                    msg = r?.str("msg") ?? "网络异常"
                }
            }
        }
    }

    private func add(_ u: SearchUser) {
        guard !u.isFriend, !u.sent, !u.sending else { return }
        if let i = users.firstIndex(where: { $0.id == u.id }) { users[i].sending = true }
        CallManager.shared.sendFriendReq(toUid: u.id, note: "") { ok, m in
            DispatchQueue.main.async {
                if let i = users.firstIndex(where: { $0.id == u.id }) {
                    users[i].sending = false
                    if ok { users[i].sent = true }
                }
                PayDialogs.toast(ok ? "请求已发送，等待对方同意" : (m.isEmpty ? "发送失败" : m))
            }
        }
    }

    private func sheetHead(_ title: String) -> some View {
        ZStack {
            Color(hex: 0xEDEDED)
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
        }
        .frame(height: 48)
        .overlay(alignment: .leading) {
            Button(action: { mode.wrappedValue.dismiss() }) {
                Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color(hex: 0x333333)).padding(.leading, 14)
            }
        }
    }
}

struct FriendReqSheet: View {
    @Environment(\.presentationMode) var mode
    @State var reqs: [CallManager.FriendReq] = []
    @State var loaded = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: { mode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: 0x333333))
                }
                Spacer()
                Text("新的朋友").font(.system(size: 17, weight: .semibold)).foregroundColor(Color(hex: 0x262626))
                Spacer()
                Color.clear.frame(width: 18, height: 18)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Color(hex: 0xEDEDED))

            if loaded && reqs.isEmpty {
                Spacer()
                Text("暂无好友申请").font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(reqs) { q in
                            HStack(spacing: 12) {
                                Avatar(url: q.face, fallback: q.name, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(q.name).font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                                    Text(subTitle(q)).font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                                }
                                Spacer()
                                if q.status == 0 {
                                    Button(action: { handle(q, 1) }) {
                                        Text("同意").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(Color(hex: 0x07C160)).cornerRadius(4)
                                    }.buttonStyle(.plain)
                                    Button(action: { handle(q, 2) }) {
                                        Text("拒绝").font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0x666666))
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xCCCCCC)))
                                    }.buttonStyle(.plain).padding(.leading, 8)
                                } else {
                                    Text(q.byMe ? (q.status == 1 ? "已同意" : "已拒绝")
                                               : (q.status == 1 ? "对方已同意" : "对方已拒绝"))
                                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                                }
                            }
                            .padding(.horizontal, 15).padding(.vertical, 8)
                            .background(Color.white)
                        }
                    }
                }
            }
        }
        .background(Color(hex: 0xF5F6F7))
        .onAppear { load() }
    }

    private func subTitle(_ q: CallManager.FriendReq) -> String {
        var s = q.note.isEmpty ? (q.status == 0 ? "请求加为好友" : "") : q.note
        if !q.timeText.isEmpty { s = (s.isEmpty ? "" : s + " · ") + q.timeText }
        return s
    }

    private func load() {
        CallManager.shared.loadFriendReqs { list in
            reqs = list
            loaded = true
        }
    }

    private func handle(_ q: CallManager.FriendReq, _ op: Int) {
        CallManager.shared.handleFriendReq(id: q.id, op: op) { ok, m in
            DispatchQueue.main.async {
                PayDialogs.toast(ok ? (op == 1 ? "已添加" : "已拒绝") : (m.isEmpty ? "操作失败" : m))
                load()
            }
        }
    }
}
