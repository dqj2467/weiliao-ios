import SwiftUI
import AVFoundation
import Photos
import PhotosUI

/// 原生聊天页（1:1 移植安卓 ChatActivity v5.47）：
/// 头部=返回+标题(人数)+「...」原位成员面板；气泡=时间胶囊+昵称+头像+群钱包金额；
/// 底栏=语音切换+下划线输入框+表情/图片开关+工具格(相册/红包/转账/充值/提现)+表情面板；
/// 红包/转账/充值/提现全部原生页；支付密码六格闸门；发送失败 toast（修「发不出去」无提示）。

struct ChatScreen: View {
    var isGroup: Bool
    var chatId: Int64
    var title: String
    var onClosed: () -> Void = {}

    @Environment(\.presentationMode) var mode

    @State var msgs: [Msg] = []
    @State var myUid: Int64 = 0
    @State var myManage = 0
    @State var bossUid: Int64 = 0
    @State var memberNum = 0
    @State var qunNotice = ""
    @State var myNick = ""
    @State var lockText = ""
    @State var input = ""
    @State var lastMid: Int64 = 0
    @State var viewer: String? = nil
    @State var showImagePicker = false
    @State var showEmojiPanel = false
    @State var showToolBox = false
    @State var voiceMode = false
    @State var loadedOnce = false

    // 成员面板（安卓：原位切换，替换消息区+底栏）
    @State var showPanel = false
    @State var panelMembers: [JSONObject] = []
    @State var onlineNum = 0
    @State var moneyTotal = ""
    @State var delMode = false
    @State var delSel: Set<Int64> = []

    // 原生页/弹层
    @State var showRedPacket = false
    @State var showTransfer = false
    @State var showRecharge = false
    @State var showWithdraw = false
    @State var showMoneyLog = false
    @State var showProfit = false
    @State var showNotice = false
    @State var showAddMember = false
    @State var showNick = false
    @State var adjustTarget: PanelMember? = nil
    @State var muteTarget: PanelMember? = nil
    @State var transferInfo: JSONObject? = nil

    // 语音
    @StateObject private var recorderBox = RecorderBox()
    @State var recCancel = false

    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    struct PanelMember: Identifiable {
        var id: Int64
        var nickname: String
        var money: String
        var idTag: Int64 { id }
    }

    // MARK: - 界面

    var body: some View {
        VStack(spacing: 0) {
            header
            if isGroup && showPanel {
                memberPanel
            } else {
                msgArea
                if !lockText.isEmpty {
                    Text(lockText).font(.system(size: 13)).foregroundColor(Color(hex: 0xFA5151))
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                foot
            }
        }
        .background(Color(hex: 0xF5F6F7).ignoresSafeArea())
        .fullScreenCover(isPresented: $showRedPacket) {
            RedPacketPage(isGroup: isGroup, chatId: chatId, onSent: { packetTouched() })
        }
        .fullScreenCover(isPresented: $showTransfer) {
            TransferPage(isGroup: isGroup, chatId: chatId, onSent: { poll() })
        }
        .fullScreenCover(isPresented: $showRecharge) { RechargePage(qunId: chatId) }
        .fullScreenCover(isPresented: $showWithdraw) { WithdrawPage(qunId: chatId) }
        .fullScreenCover(isPresented: $showMoneyLog) { MoneyLogSheet(qunId: chatId) }
        .fullScreenCover(isPresented: $showProfit) { ProfitStatSheet(qunId: chatId) }
        .fullScreenCover(isPresented: $showNotice) { NoticeSheet(notice: qunNotice) }
        .fullScreenCover(isPresented: $showAddMember) { MemberAddSheet(qunId: chatId, onDone: { loadPanel() }) }
        .fullScreenCover(isPresented: $showNick) { NickSheet(qunId: chatId, current: myNick, onDone: { loadPanel() }) }
        .fullScreenCover(item: $adjustTarget) { t in
            MoneyAdjustSheet(qunId: chatId, uid: t.id, nick: t.nickname, curMoney: t.money, onDone: { loadPanel() })
        }
        .fullScreenCover(item: $muteTarget) { t in
            SheetMenuView(title: "禁言「" + t.nickname + "」",
                          items: ["禁言 10 分钟", "禁言 1 小时", "禁言 24 小时", "解除禁言"]) { i in
                let durs: [Int64] = [600, 3600, 86400, 0]
                Api.shared.post("/Home/Group/mute.html",
                                form: ["qunid": String(chatId), "uid": String(t.id), "dur": String(durs[i])]) { r in
                    DispatchQueue.main.async {
                        PayDialogs.toast(r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常")
                        if r?.status == 1 { loadPanel() }
                    }
                }
            }
        }
        .fullScreenCover(item: Binding(get: { transferInfo.map { InfoItem(d: $0) } },
                                       set: { transferInfo = $0?.d })) { item in
            TransferInfoSheet(d: item.d)
        }
        .fullScreenCover(isPresented: $showImagePicker) {
            ImagePicker { ui in
                if let d = ui?.jpegData(compressionQuality: 0.85) { uploadAndSendImage(d) }
            }
        }
        .fullScreenCover(item: Binding(get: { viewer.map { SheetItem(u: $0) } },
                                       set: { viewer = $0?.u })) { _ in
            ImageViewer(url: viewer ?? "")
        }
        .onAppear { bootstrap() }
        .onReceive(timer) { _ in poll() }
    }

    struct InfoItem: Identifiable {
        var d: JSONObject
        var id: String { String(d.long("id")) }
    }

    // 头部（#EDEDED 48：返回 + 居中标题(群带人数) + 右「...」H5 原图）
    private var header: some View {
        ZStack {
            Color(hex: 0xEDEDED)
            Text(headTitle).font(.system(size: 17, weight: .bold)).foregroundColor(Color(hex: 0x262626))
            HStack(spacing: 0) {
                Button(action: { mode.wrappedValue.dismiss(); onClosed() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(hex: 0x333333))
                        .frame(width: 44, height: 48)
                }
                Spacer()
                if isGroup {
                    Button(action: { togglePanel() }) {
                        Image("h5ico_members").resizable().scaledToFit()
                            .frame(width: 26, height: 26).padding(.trailing, 14)
                    }
                }
            }
        }.frame(height: 48)
    }

    private var headTitle: String {
        isGroup ? title + (memberNum > 0 ? "(\(memberNum))" : "") : title
    }

    // MARK: - 消息区

    private var msgArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                if !loadedOnce {
                    Text("消息加载中…（点此重试）")
                        .font(.system(size: 14)).foregroundColor(Color(hex: 0x999999))
                        .frame(maxWidth: .infinity).padding(.top, 80)
                        .onTapGesture { firstLoad() }
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(msgs.indices, id: \.self) { i in
                            let m = msgs[i]
                            let showTime = i == 0 || (m.time - msgs[i - 1].time) > 300
                            ChatBubble(m: m, mine: m.senderId == myUid, showTime: showTime,
                                       showNick: isGroup && m.senderId != myUid,
                                       onTapImage: { viewer = m.text },
                                       onTapHb: { openPacket(m.packId) },
                                       onTapZz: { openTransferInfo(m.packId) },
                                       onRecall: { recall(m) })
                                .id(m.mid)
                        }
                    }.padding(.vertical, 8)
                }
            }
            .onChange(of: msgs.count) { _ in
                if let last = msgs.last {
                    withAnimation { proxy.scrollTo(last.mid, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 底栏（安卓 foot 三层：输入行 / 工具格 / 表情面板）

    private var foot: some View {
        VStack(spacing: 0) {
            inputRow
            if showToolBox { toolBox }
            if showEmojiPanel { emojiPanel }
        }.background(Color(hex: 0xF7F7F7))
    }

    private var inputRow: some View {
        HStack(spacing: 0) {
            // 语音/键盘切换
            Button(action: {
                voiceMode.toggle()
                showEmojiPanel = false; showToolBox = false
            }) {
                Image(systemName: voiceMode ? "keyboard" : "mic.fill")
                    .font(.system(size: 20)).foregroundColor(Color(hex: 0x333333))
                    .frame(width: 32, height: 32).padding(.horizontal, 6)
            }
            if voiceMode {
                // 按住说话（微信式：上滑 90 取消）
                Text(recorderBox.recording ? (recCancel ? "松开 取消" : "松开 发送") : "按住 说话")
                    .font(.system(size: 15)).foregroundColor(Color(hex: 0x191919))
                    .frame(maxWidth: .infinity).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(recorderBox.recording ? Color(hex: 0xDEDEDE) : Color(hex: 0xF7F7F7))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: recorderBox.recording ? 0xCCCCCC : 0xDBDBDB))))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                recCancel = v.translation.height < -90
                                if !recorderBox.recording { recorderBox.start() }
                            }
                            .onEnded { _ in
                                recorderBox.finish(cancel: recCancel) { path, dur in
                                    var f = baseParams()
                                    f["text"] = path + "|dur=" + String(dur)
                                    f["type"] = "3"
                                    send(path: sendPath, form: f)
                                }
                            }
                    )
            } else {
                // 输入框（下划线，同 H5 #textarea）
                VStack(spacing: 0) {
                    TextField("说点什么…", text: $input, onCommit: { sendText() })
                        .font(.system(size: 15)).foregroundColor(Color(hex: 0x333333))
                        .padding(.top, 6)
                    Rectangle().fill(Color(hex: 0xDBDBDB)).frame(height: 1)
                }.padding(.horizontal, 4)

                Button(action: { showToolBox = false; showEmojiPanel.toggle() }) {
                    Image("h5ico_emoji").resizable().scaledToFit()
                        .frame(width: 30, height: 30).padding(.horizontal, 8)
                }
                Button(action: { showEmojiPanel = false; showToolBox.toggle() }) {
                    Image("h5ico_sendimg").resizable().scaledToFit()
                        .frame(width: 30, height: 30).padding(.trailing, 8)
                }
                Button(action: { sendText() }) {
                    Text("发送").font(.system(size: 15, weight: .bold)).foregroundColor(.white)
                        .frame(width: 53, height: 34)
                        .background(Color(hex: 0x1AAD19)).cornerRadius(2)
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color(hex: 0x179E16)))
                }
            }
        }
        .padding(6)
    }

    // 工具格（安卓 buildToolBox 1:1：相册/红包/转账/充值/提现）
    private var toolBox: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: 0xDBDBDB)).frame(height: 1)
            HStack(spacing: 0) {
                toolItem("h5ico_photo", "相册") { showToolBox = false; showImagePicker = true }
                toolItem("h5ico_redpack", "红包") { showToolBox = false; showRedPacket = true }
                toolItem("h5ico_transfer", "转账") { showToolBox = false; startTransfer() }
                if isGroup {
                    toolItem("h5ico_recharge", "充值") { showToolBox = false; showRecharge = true }
                    toolItem("h5ico_withdraw", "提现") { showToolBox = false; showWithdraw = true }
                }
            }.padding(.vertical, 14)
        }
    }

    private func toolItem(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(icon).resizable().scaledToFit().frame(width: 40, height: 40)
                Text(label).font(.system(size: 13)).foregroundColor(Color(hex: 0x777777))
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }

    // 表情面板（8 列彩色 emoji，同安卓 buildEmojPanel）
    private var emojiPanel: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(hex: 0xDBDBDB)).frame(height: 1)
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                    ForEach(Emo.panelEmojis, id: \.self) { hex in
                        Button(action: { if let ch = Emo.char(hex) { input += ch } }) {
                            if let img = Emo.image(hex) {
                                Image(uiImage: img).resizable().scaledToFit().frame(width: 30, height: 30)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
            .frame(height: 220)
        }.background(Color(hex: 0xF6F6F6))
    }

    // MARK: - 成员面板（安卓 renderMemberPanel 1:1：头部白卡 + 5列网格 + 功能行）

    private var memberPanel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                // 头部白卡
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 0) {
                        panelHeadline
                        Spacer()
                        if myManage == 1 {
                            Button(action: { showMoneyLog = true }) {
                                Text("群金额明细").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 5)
                                    .background(Capsule().fill(Color(hex: 0x1AAD19)))
                            }
                        }
                    }
                    if myManage == 1 {
                        Button(action: { showProfit = true }) {
                            Text("分润统计").font(.system(size: 13)).foregroundColor(Color(hex: 0x576B95))
                                .padding(.horizontal, 12).padding(.vertical, 5)
                                .background(Capsule().fill(Color(hex: 0xEFF2F6)))
                        }
                    }
                    if myManage == 1 && !moneyTotal.isEmpty {
                        Rectangle().fill(Color(hex: 0xECECEC)).frame(height: 1)
                            .background(DashLine())
                        Text("群成员余额合计 ")
                            .font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
                        + Text(moneyTotal).font(.system(size: 14, weight: .bold)).foregroundColor(Color(hex: 0xFA9D3B))
                        + Text(" 元").font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.cornerRadius(14))
                .padding(.horizontal, 12).padding(.top, 12)

                // 成员白卡网格（5 列）
                VStack(spacing: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 14) {
                        ForEach(panelMembers.indices, id: \.self) { i in
                            memberCell(panelMembers[i])
                        }
                        if myManage == 1 && !delMode {
                            Button(action: { showAddMember = true }) {
                                VStack(spacing: 5) {
                                    Text("+").font(.system(size: 26)).foregroundColor(Color(hex: 0x7F7F7F))
                                        .frame(width: 50, height: 50)
                                        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xD9D9D9)))
                                    Text("添加").font(.system(size: 12)).foregroundColor(Color(hex: 0x262626))
                                }
                            }.buttonStyle(.plain)
                            Button(action: { delMode = true; delSel = [] }) {
                                VStack(spacing: 5) {
                                    Text("−").font(.system(size: 26)).foregroundColor(Color(hex: 0x7F7F7F))
                                        .frame(width: 50, height: 50)
                                        .background(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xD9D9D9)))
                                    Text("移除").font(.system(size: 12)).foregroundColor(Color(hex: 0x262626))
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 4).padding(.top, 14)

                    if delMode {
                        HStack(spacing: 12) {
                            Button(action: { delMode = false; delSel = [] }) {
                                Text("取消").font(.system(size: 14)).foregroundColor(Color(hex: 0x666666))
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: 0xDBDBDB)))
                            }
                            Button(action: doRemoveSel) {
                                Text("移除所选（\(delSel.count)）").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                                    .frame(maxWidth: .infinity).frame(height: 36)
                                    .background(Color(hex: delSel.isEmpty ? 0xCCCCCC : 0xFA5151)).cornerRadius(6)
                            }
                        }.padding(.top, 12)
                    }
                }
                .padding(.bottom, 12)
                .background(Color.white.cornerRadius(14))
                .padding(.horizontal, 12)

                // 底部功能行（安卓 opsList 1:1）
                VStack(spacing: 0) {
                    panelOp("查找聊天记录", "") {
                        WebFallback.open(Api.host + "/Home/Group/msgsearch.html?qunid=" + String(chatId), title: "查找聊天记录")
                    }
                    panelOp("群公告", qunNotice.isEmpty ? "未设置" : "查看") { showNotice = true }
                    panelOp("我在本群的昵称", myNick) { showNick = true }
                    panelOp("群设置", "") {
                        WebFallback.open(Api.host + "/Home/Group/setting.html?qunid=" + String(chatId), title: "群设置")
                    }
                    if myManage == 1 {
                        panelOp("成员分配（分润归属）", "") {
                            WebFallback.open(Api.host + "/Home/Group/memberbind.html?qunid=" + String(chatId), title: "成员分配")
                        }
                        panelOp("我的充值收款码", "") {
                            WebFallback.open(Api.host + "/Home/Group/rechargecode.html?qunid=" + String(chatId), title: "我的充值收款码")
                        }
                        panelOp("会员提现处理", "") {
                            WebFallback.open(Api.host + "/Home/Group/payouts.html?qunid=" + String(chatId), title: "会员提现处理")
                        }
                    }
                    if bossUid > 0 && bossUid == myUid {
                        panelOp("清空聊天记录", "") { clearChatConfirm() }
                    }
                }
                .background(Color.white.cornerRadius(14))
                .padding(.horizontal, 12).padding(.bottom, 20)
            }
        }
        .background(Color(hex: 0xF5F6F7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelHeadline: Text {
        Text("群成员 ").font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
        + Text(String(panelMembers.count)).font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0x555555))
        + Text(" 人 · 在线 ").font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
        + Text(String(onlineNum)).font(.system(size: 13, weight: .bold)).foregroundColor(Color(hex: 0x555555))
        + Text(" 人").font(.system(size: 13)).foregroundColor(Color(hex: 0x8A8A8A))
    }

    private func memberCell(_ o: JSONObject) -> some View {
        let cUid = o.long("id")
        let manage = o.int("manage") == 1
        var nick = o.str("nickname")
        if manage { nick = "★" + nick }
        if cUid == bossUid && bossUid > 0 { nick = "👑" + nick }
        return Button(action: { tapMember(o) }) {
            VStack(spacing: 5) {
                Avatar(url: o.str("headimgurl"), fallback: o.str("nickname"), size: 48)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .fill(delMode && delSel.contains(cUid) ? Color(hex: 0xE6F7E6).opacity(0.5) : Color.clear))
                Text(nick).font(.system(size: 12)).foregroundColor(Color(hex: 0x262626)).lineLimit(1)
                if manage {
                    Text("管理").font(.system(size: 10)).foregroundColor(Color(hex: 0xB25E00))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color(hex: 0xFFF3E0)).cornerRadius(3)
                }
                if myManage == 1 && cUid != myUid && !manage {
                    Text("禁言").font(.system(size: 11)).foregroundColor(Color(hex: 0xC0392B))
                        .padding(.horizontal, 10).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xFDECEA)))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: 0xF5C6C0)))
                        .onTapGesture { muteTarget = PanelMember(id: cUid, nickname: nick, money: o.str("money")) }
                }
            }
        }.buttonStyle(.plain)
    }

    private func panelOp(_ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(label).font(.system(size: 15)).foregroundColor(Color(hex: 0x262626))
                Spacer()
                if !value.isEmpty {
                    Text(value).font(.system(size: 14)).foregroundColor(Color(hex: 0xAAAAAA))
                }
                Text("›").font(.system(size: 17)).foregroundColor(Color(hex: 0xD9D9D9)).padding(.leading, 6)
            }
            .padding(.horizontal, 14).frame(height: 48)
        }.buttonStyle(.plain)
        .overlay(Rectangle().fill(Color(hex: 0xF2F2F2)).frame(height: 0.5), alignment: .bottom)
    }

    // MARK: - 消息气泡（1:1 安卓 getView：时间胶囊+昵称+头像40+气泡+头像下群钱包金额）

    struct ChatBubble: View {
        var m: Msg
        var mine: Bool
        var showTime: Bool
        var showNick: Bool
        var onTapImage: () -> Void
        var onTapHb: () -> Void
        var onTapZz: () -> Void
        var onRecall: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                if showTime {
                    Text(listTime(m.time))
                        .font(.system(size: 12)).foregroundColor(Color(hex: 0x8C8C8C))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color(hex: 0xE3E3E3)))
                        .padding(.vertical, 10)
                }
                if m.msgtype == "rc" {
                    // 撤回/系统通知
                    Text(m.text).font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color(hex: 0xE6E6E6).opacity(0.6)).cornerRadius(6)
                        .padding(.vertical, 6)
                } else if mine {
                    HStack(alignment: .top, spacing: 8) {
                        Spacer()
                        bubble
                        VStack(spacing: 3) {
                            Avatar(url: m.avatar, fallback: m.nickname, size: 40)
                            if !m.money.isEmpty {
                                Text("¥" + m.money).font(.system(size: 11)).foregroundColor(Color(hex: 0xFA9D3B))
                            }
                        }
                    }.padding(.horizontal, 10).padding(.vertical, 5)
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(spacing: 3) {
                            Avatar(url: m.avatar, fallback: m.nickname, size: 40)
                            if !m.money.isEmpty {
                                Text("¥" + m.money).font(.system(size: 11)).foregroundColor(Color(hex: 0xFA9D3B))
                            }
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            if showNick {
                                Text(m.nickname).font(.system(size: 12)).foregroundColor(Color(hex: 0x999999))
                            }
                            bubble
                        }
                        Spacer()
                    }.padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
        }

        @ViewBuilder private var bubble: some View {
            if m.type == 2 {
                Button(action: onTapImage) {
                    RemoteImg(url: m.text, size: 140)
                }.buttonStyle(.plain)
            } else if m.type == 3 {
                VoiceBubble(text: m.text, mine: m.mine)
                    .contextMenu { Button(action: onRecall) { Text("撤回") } }
            } else if m.msgtype == "hb" {
                MoneyCard(text: m.text, sub: m.nickname, done: m.hbDone == 1,
                          title: "微聊红包", action: onTapHb)
            } else if m.msgtype == "zz" {
                MoneyCard(text: "¥" + m.zzAmount, sub: m.text.isEmpty ? "转账" : m.text,
                          done: false, title: "微聊转账", action: onTapZz)
            } else {
                Text(m.text)
                    .font(.system(size: 16)).foregroundColor(Color(hex: 0x262626))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(Color(hex: mine ? 0xA5E75A : 0xFFFFFF)))
                    .contextMenu { Button(action: onRecall) { Text("撤回") } }
            }
        }
    }

    // 语音气泡（安卓同款：▶ 语音 N\"，点击播放）
    struct VoiceBubble: View {
        var text: String
        var mine: Bool
        @State var player: AVAudioPlayer?

        var body: some View {
            Button(action: play) {
                Text("▶ 语音 \(dur)\"")
                    .font(.system(size: 15)).foregroundColor(Color(hex: 0x262626))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: mine ? 0xA5E75A : 0xFFFFFF)))
            }.buttonStyle(.plain)
        }

        private var dur: Int {
            if let r = text.range(of: "|dur=") { return Int(text[r.upperBound...]) ?? 1 }
            return 1
        }

        private func play() {
            let path = text.components(separatedBy: "|dur=").first ?? text
            guard let url = URL(string: path.hasPrefix("http") ? path : Api.host + path) else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            if let d = try? Data(contentsOf: url) {
                player = try? AVAudioPlayer(data: d)
                player?.play()
            }
        }
    }

    // 红包/转账橙卡（H5 1:1：#FB9F3C → 领完 #F8C460 + 白底条）
    struct MoneyCard: View {
        var text: String
        var sub: String
        var done: Bool
        var title: String
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image("b").resizable().scaledToFit()
                            .frame(width: 30, height: 38)
                            .colorMultiply(done ? Color(hex: 0xF8C460) : .white)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(text).font(.system(size: 15, weight: .bold))
                                .foregroundColor(done ? Color(hex: 0xFFF3E2) : .white).lineLimit(1)
                            Text(sub).font(.system(size: 12))
                                .foregroundColor(done ? Color(hex: 0xFFF3E2).opacity(0.8) : Color.white.opacity(0.85)).lineLimit(1)
                        }
                        Spacer()
                    }.padding(10)
                    Text(title).font(.system(size: 12))
                        .foregroundColor(done ? Color(hex: 0xC1854A) : Color(hex: 0x333333))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.white)
                }
                .frame(width: 220)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: done ? 0xF8C460 : 0xFB9F3C)))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain)
        }
    }

    // MARK: - 数据

    private func bootstrap() {
        Api.shared.post("/Api/Native/me.html", form: [:]) { r in
            DispatchQueue.main.async {
                if let d = r?.data { myUid = d.long("id") }
            }
        }
        if isGroup {
            Api.shared.post("/Api/Native/groupinfo.html", form: ["qunid": String(chatId)]) { r in
                DispatchQueue.main.async {
                    guard let d = r?.data else { return }
                    bossUid = d.long("boss_uid")
                    myManage = d.int("my_manage")
                    qunNotice = d.str("gginfo")
                    let n = d.int("member_num")
                    if n > 0 { memberNum = n }
                }
            }
        }
        firstLoad()
    }

    private func firstLoad() {
        Api.shared.post(endPath, form: baseParams()) { r in
            DispatchQueue.main.async { loadedOnce = true }
            if let r = r, r.status == 200 { apply(r); packetTouched() }
        }
    }

    private var endPath: String { isGroup ? "/Api/Message/getMag.html" : "/Api/Friendmessage/getMag.html" }
    private var sendPath: String { isGroup ? "/Api/Message/send.html" : "/Api/Friendmessage/send.html" }

    private func baseParams() -> [String: String] {
        isGroup ? ["qunid": String(chatId)] : ["friendid": String(chatId)]
    }

    private func poll() {
        var f = baseParams()
        f["mid"] = String(lastMid)
        Api.shared.post(endPath, form: f) { r in
            if let r = r, r.status == 200 { apply(r) }
        }
    }

    private func apply(_ r: JSONObject) {
        var batch: [Msg] = []
        for o in r.arr {
            let m = parseMsg(o)
            if m.mid > lastMid {
                lastMid = m.mid
                batch.append(m)
            }
        }
        DispatchQueue.main.async {
            for m in batch {
                if msgs.contains(where: { $0.mid == m.mid }) { continue }   // 去重
                if m.msgtype == "rc" {
                    msgs.removeAll { $0.mid == m.packId }
                    msgs.append(m)
                    continue
                }
                msgs.append(m)
            }
            if isGroup {
                let alllock = r.raw["alllock"] as? Int ?? 0
                let lock = r.raw["lock"] as? Int ?? 1
                lockText = alllock == 1 ? "群主已开启全体禁言" : (lock == 0 ? "您已被禁言" : "")
            }
        }
    }

    private func parseMsg(_ o: JSONObject) -> Msg {
        Msg(mid: o.long("mid"), senderId: o.long("id"), nickname: o.str("nickname"),
            avatar: o.str("headimgurl"), text: o.str("text"), time: o.long("time"),
            type: o.int("type"), packId: o.long("pack_id"), msgtype: o.str("msgtype"),
            zzAmount: o.str("zz_amount"), hbDone: o.int("hb_done"), hbMine: o.int("hb_mine"),
            money: o.str("money"), mine: false)
    }

    /// 红包状态回填（安卓 v5.35 refreshPacketStates 同款）
    private func packetTouched() {
        var f = baseParams()
        f["mid"] = "0"
        Api.shared.post(endPath, form: f) { r in
            guard let r = r, r.status == 200 else { return }
            let latest = (r.arr.suffix(10)).map { parseMsg($0) }
            DispatchQueue.main.async {
                for nm in latest {
                    if let idx = msgs.firstIndex(where: { $0.mid == nm.mid }) {
                        msgs[idx].hbDone = nm.hbDone
                        msgs[idx].hbMine = nm.hbMine
                    }
                }
            }
        }
    }

    // MARK: - 发送（★修复：失败必提示，成功后立即补拉）

    private func sendText() {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        input = ""
        showEmojiPanel = false; showToolBox = false
        var f = baseParams()
        f["text"] = Emo.encode(t)
        f["type"] = "1"
        send(path: sendPath, form: f)
    }

    /// 统一发送出口：失败 toast（安卓 v5.47 口径：成功静默），成功后立刻补拉一次消息
    private func send(path: String, form: [String: String]) {
        Api.shared.post(path, form: form) { r in
            DispatchQueue.main.async {
                if r == nil {
                    PayDialogs.toast("网络异常")
                } else if let r = r, r.status != 200 && r.status != 1 {
                    let info = r.str("msg").isEmpty ? "发送失败" : r.str("msg")
                    PayDialogs.toast(info)
                } else {
                    poll()
                }
            }
        }
    }

    private func uploadAndSendImage(_ data: Data) {
        Api.shared.upload("/Home/Index/fileUpload.html", fileData: data, fileName: "img.jpg") { up in
            let path = up?.str("img_path") ?? ""
            guard !path.isEmpty else {
                DispatchQueue.main.async { PayDialogs.toast("图片上传失败") }
                return
            }
            var f = baseParams()
            f["text"] = path
            f["type"] = "2"
            send(path: sendPath, form: f)
        }
    }

    private func recall(_ m: Msg) {
        guard isGroup else { return }
        PayDialogs.confirm("撤回这条消息？") {
            var f = baseParams()
            f["mid"] = String(m.mid)
            Api.shared.post(isGroup ? "/Api/Message/recall.html" : "/Api/Friendmessage/recall.html", form: f) { _ in
                poll()
            }
        }
    }

    // MARK: - 红包/转账打开（安卓 v5.32 同流程）

    private func openPacket(_ packId: Int64) {
        Api.shared.post("/Home/Index/getPacket.html", form: ["id": String(packId)]) { pre in
            DispatchQueue.main.async {
                guard let pre = pre, pre.status == 1 else {
                    // 已领完/已领过 → 看领取记录页（安卓同款 getPacketLog，H5 全屏）
                    WebFallback.open(Api.host + "/Home/Index/getPacketLog.html?id=" + String(packId), title: "微聊红包")
                    return
                }
                WebFallback.open(Api.host + "/Home/Index/getPacketPage.html?id=" + String(packId), title: "微聊红包")
                packetTouched()
            }
        }
    }

    private func openTransferInfo(_ packId: Int64) {
        Api.shared.post("/Api/Native/transferinfo.html", form: ["id": String(packId)]) { r in
            DispatchQueue.main.async {
                guard let r = r, r.status == 200 else { return }
                transferInfo = r.data
            }
        }
    }

    private func startTransfer() {
        if !isGroup { showTransfer = true; return }
        // 群转账直接进转账页点选群友（安卓同页内选人，不再单独选人弹窗）
        showTransfer = true
    }

    // MARK: - 成员面板

    private func togglePanel() {
        if showPanel { showPanel = false; return }
        showPanel = true
        delMode = false; delSel = []
        loadPanel()
    }

    private func loadPanel() {
        Api.shared.post("/Api/Message/getQunUser.html", form: ["qunid": String(chatId)]) { r in
            DispatchQueue.main.async {
                guard let r = r, r.status == 200 else { PayDialogs.toast("成员加载失败"); return }
                panelMembers = r.arr
                onlineNum = r.int("online_num")
                moneyTotal = r.str("money_total")
                for o in panelMembers where o.long("id") == myUid { myNick = o.str("nickname") }
            }
        }
    }

    /// 安卓同口径：主管理员点普通成员 → 金额调整；其余（点自己/管理员）→ 回聊天并 @他
    private func tapMember(_ o: JSONObject) {
        let cUid = o.long("id")
        if delMode {
            if o.int("manage") == 1 { return }
            if delSel.contains(cUid) { delSel.remove(cUid) } else { delSel.insert(cUid) }
            return
        }
        if bossUid > 0 && bossUid == myUid && o.int("manage") != 1 && cUid != myUid {
            adjustTarget = PanelMember(id: cUid, nickname: o.str("nickname"), money: o.str("money"))
        } else {
            showPanel = false
            input += "@" + o.str("nickname") + " "
        }
    }

    private func doRemoveSel() {
        guard !delSel.isEmpty else { PayDialogs.toast("请先勾选要移除的成员"); return }
        let uids = Array(delSel)
        var ok = 0
        let group = DispatchGroup()
        for u in uids {
            group.enter()
            Api.shared.post("/Home/Group/removeMember.html",
                            form: ["qunid": String(chatId), "uid": String(u)]) { r in
                if r?.status == 1 { DispatchQueue.main.async { ok += 1 } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            delMode = false; delSel = []
            PayDialogs.toast("已移除 \(ok)/\(uids.count) 人" + (ok < uids.count ? "（部分失败）" : ""))
            loadPanel()
        }
    }

    private func clearChatConfirm() {
        PayDialogs.confirm("确定清空本群聊天记录？仅影响自己视角。") {
            Api.shared.post("/Api/Message/clearChat.html", form: ["qunid": String(chatId)]) { r in
                DispatchQueue.main.async {
                    PayDialogs.toast(r.flatMap { $0.str("info").isEmpty ? $0.msg : $0.str("info") } ?? "网络异常")
                    if r?.status == 200 || r?.status == 1 { msgs = []; lastMid = 0; firstLoad() }
                }
            }
        }
    }
}

/// 录音包装（@StateObject 兼容）
final class RecorderBox: ObservableObject {
    @Published var recording = false
    private let rec = Recorder()

    func start() {
        recording = true
        rec.start()
    }

    func finish(cancel: Bool, done: @escaping (String, Int) -> Void) {
        recording = false
        if cancel { rec.finish { _, _ in } } else { rec.finish(done) }
    }
}

/// 虚线分隔
struct DashLine: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0.5))
                p.addLine(to: CGPoint(x: g.size.width, y: 0.5))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundColor(Color(hex: 0xECECEC))
        }.frame(height: 1)
    }
}

// MARK: - 远程图片

struct RemoteImg: View {
    var url: String
    var size: CGFloat
    @State var img: UIImage?
    var body: some View {
        Group {
            if let img = img {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Rectangle().fill(Color(hex: 0xE0E0E0))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onAppear {
            Api.shared.fetchImage(url) { d in
                if let d = d { DispatchQueue.main.async { img = UIImage(data: d) } }
            }
        }
    }
}

// MARK: - 转账详情弹层（安卓 transferInfoSheet 1:1）

struct TransferInfoSheet: View {
    var d: JSONObject
    var body: some View {
        BottomSheetScaffold(title: "转账详情") {
            VStack(spacing: 10) {
                let canSee = d.int("can_see") == 1
                Text(canSee ? "¥ " + d.str("amount") : "转账")
                    .font(.system(size: 30, weight: .bold)).foregroundColor(Color(hex: 0x1AAD19))
                Text(d.str("scene") + " · " + d.str("status_text"))
                    .font(.system(size: 12)).foregroundColor(Color(hex: 0xFFA500))
                if canSee {
                    let who = "该转账由 " + d.str("from_name") + " 发起，收款人为 " + d.str("to_name")
                    Text(who)
                        .font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
                }
                VStack(spacing: 0) {
                    infoRow("付款方", d.str("from_name"))
                    infoRow("收款方", d.str("to_name"))
                    infoRow("留言", d.str("about"))
                    infoRow("转账时间", d.str("time_text"))
                    if d.int("profit_show") == 1 {
                        infoRow("服务费", "¥" + d.str("profit_text") + "，收款方实收 ¥" + d.str("to_amount"))
                    }
                }
                .padding(.vertical, 6)
                .background(Color.white.cornerRadius(10))
                .padding(.horizontal, 14)
                Spacer()
            }
        }
    }

    private func infoRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(k).font(.system(size: 13)).foregroundColor(Color(hex: 0x999999))
            Spacer()
            Text(v.isEmpty ? "-" : v).font(.system(size: 13)).foregroundColor(Color(hex: 0x333333))
                .multilineTextAlignment(.trailing)
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}
