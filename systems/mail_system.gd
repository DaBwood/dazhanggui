# ============================================================
# 邮件系统（骨架版，2026-09-10 商会第二批）
# 纯本地存档：奖励不进背包，先进邮箱，玩家手动领取
# 骨架功能：列表 / 单封领取 / 一键领取（领取即删），无已读未读
# 发信方：商会商贸结算（guild_view 惰性结算时调用 add_mail）
# 幂等：mail_id 唯一去重，同 id 不重复发（商贸靠它防重复领奖）
# ============================================================
class_name MailSystem
extends RefCounted

var g

# 邮件列表：[{id, title, content, rewards:{item_id:count}, ts}]
var mails: Array = []

func _init(p_g):
	g = p_g

# ============ 存档 ============
func get_save_data() -> Dictionary:
	return {"mails": mails}

func load_save_data(s: Dictionary):
	if s.has("mails") and s.mails is Array:
		mails = []
		for m in s.mails:
			# 防御：只收字典且 id 非空的条目（防脏档）
			if m is Dictionary and str(m.get("id", "")) != "":
				mails.append(m)

# ============ 查询 ============
func get_unclaimed_count() -> int:
	return mails.size()

func has_mail(mail_id: String) -> bool:
	for m in mails:
		if str(m.get("id", "")) == mail_id:
			return true
	return false

# ============ 发邮件 ============
# 返回 true=新发，false=已存在（幂等，调用方靠它判断要不要做配套动作）
func add_mail(mail_id: String, title: String, content: String, rewards: Dictionary) -> bool:
	if has_mail(mail_id):
		return false
	mails.append({
		"id": mail_id,
		"title": title,
		"content": content,
		"rewards": rewards,
		"ts": Time.get_unix_time_from_system(),
	})
	g.save_game()
	return true

# ============ 领取 ============
# 单封领取：奖励进背包，邮件删除
func claim(mail_id: String) -> Dictionary:
	for i in range(mails.size()):
		if str(mails[i].get("id", "")) == mail_id:
			var gains: Dictionary = mails[i].get("rewards", {})
			for item_id in gains.keys():
				g.items[item_id] = g.items.get(item_id, 0) + int(gains[item_id])
			mails.remove_at(i)
			g.save_game()
			return {"ok": true, "gains": gains}
	return {"ok": false, "reason": "邮件不存在或已领取"}

# 一键领取：全部奖励汇总进背包，清空列表
func claim_all() -> Dictionary:
	if mails.is_empty():
		return {"ok": false, "reason": "没有待领取的邮件"}
	var total: Dictionary = {}
	for m in mails:
		for item_id in m.get("rewards", {}).keys():
			total[item_id] = total.get(item_id, 0) + int(m.rewards[item_id])
	for item_id in total.keys():
		g.items[item_id] = g.items.get(item_id, 0) + int(total[item_id])
	mails.clear()
	g.save_game()
	return {"ok": true, "gains": total}
