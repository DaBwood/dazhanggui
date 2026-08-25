class_name GameData
extends RefCounted

func _init():
	_load_all_configs()

#保存路径
const SAVE_PATH = "user://save.json"
const OFFLINE_RATE = 0.8

const BEAST_CONFIG_PATH = "res://data/beasts.json"

# ========== VIP 等级经验表（累计经验，单位：10经验=1元）==========
const VIP_EXP_TABLE = [
	0,          # VIP0  → 0元
	300,        # VIP1  → 30元
	1000,       # VIP2  → 100元
	3000,       # VIP3  → 300元
	10000,      # VIP4  → 1000元
	30000,      # VIP5  → 3000元
	100000,     # VIP6  → 1万元
	300000,     # VIP7  → 3万元
	1000000,    # VIP8  → 10万元
	2000000,    # VIP9  → 20万元
	4000000,    # VIP10 → 40万元
	6000000,    # VIP11 → 60万元
	8000000,    # VIP12 → 80万元
	10000000,   # VIP13 → 100万元
	20000000,   # VIP14 → 200万元
	50000000,   # VIP15 → 500万元
	100000000,  # VIP16 → 1000万元
]

const SHOP_ORDER = ["ke_zhan", "yi_guan", "shuoshu_tan", "xiangliao_pu", "dang_pu", "yao_pu", "jiu_si", "yi_zhan", "miaoyin_fang", "jiu_fang", "changle_fang", "chengyi_pu", "suanming_tan", "chuan_wu", "chema_hang", "cha_si", "xi_lou", "zao_tang", "biao_ju", "yao_chang"]

const SHOP_UNLOCK_TABLE = {
	"ke_zhan": 1,
	"yi_guan": 5,
	"shuoshu_tan": 15,
	"xiangliao_pu": 40,
	"dang_pu": 80,
	"yao_pu": 130,
	"jiu_si": 200,
	"yi_zhan": 300,
	"miaoyin_fang": 450,
	"jiu_fang": 650,
	"changle_fang": 950,
	"chengyi_pu": 1400,
	"suanming_tan": 2100,
	"chuan_wu": 3200,
	"chema_hang": 4800,
	"cha_si": 7000,
	"xi_lou": 10000,
	"zao_tang": 13000,
	"biao_ju": 16500,
	"yao_chang": 20000,
}

# ========== 抽奖系统 ==========
const LOTTERY_POOL = [
	{"item": "hero_token", "count": 1, "weight": 0.0012},
	{"item": "friend_token", "count": 1, "weight": 0.0012},
	{"item": "zou_yu", "count": 1, "weight": 0.0012, "is_beast": true},
	{"item": "ginseng_1000", "count": 1, "weight": 0.05},
	{"item": "hq_blueprint", "count": 1, "weight": 0.05},
	{"item": "fengyasong", "count": 5, "weight": 0.05},
	{"item": "energy_pill", "count": 10, "weight": 0.05},
	{"item": "shop_blueprint", "count": 2, "weight": 0.1},
	{"item": "hour_card", "count": 10, "weight": 0.1},
	{"item": "ginseng", "count": 1, "weight": 0.1},
	{"item": "abacus", "count": 3, "weight": 0.1},
	{"item": "aroma_fruit", "count": 10, "weight": 0.1},
	{"item": "vitality_pill", "count": 10, "weight": 0.1},
	{"item": "aptitude_pill", "count": 2, "weight": 0.05},
	{"item": "wood_comb", "count": 100, "weight": 0.05},
	{"item": "rouge", "count": 100, "weight": 0.05},
	{"item": "exp_box", "count": 10, "weight": 0.0458},
	{"item": "feng_shen_zhi", "count": 1, "weight": 0.00015},
	{"item": "shan_hai_shi", "count": 1, "weight": 0.0001},
	{"item": "hong_huang_huo", "count": 1, "weight": 0.0001},
	{"item": "jiu_yuan_shui", "count": 1, "weight": 0.0001},
	{"item": "long_zhuo_xi", "count": 1, "weight": 0.00005},
	{"item": "xing_wu_po", "count": 1, "weight": 0.00005},
	{"item": "xing_shu_lin", "count": 1, "weight": 0.00005},
]
const LOTTERY_GUARANTEE = 500
const LOTTERY_TICKET_YUANBAO_RATE = 50

var lottery_draw_count: int = 0

# ========== 身份等级奖励表 ==========
const IDENTITY_REWARD_TABLE = {
	2: {"type": "hero", "id": "zheng_guonong", "name": "郑果农"},
	3: {"type": "hero", "id": "zhu_huolang", "name": "祝货郎"},
	4: {"type": "hero", "id": "kang_chashi", "name": "康茶师"},
	5: {"type": "hero", "id": "liang_waiqi", "name": "梁歪七"},
	6: {"type": "hero", "id": "ge_langzhong", "name": "葛郎中"},
	7: {"type": "hero", "id": "liu_bukuai", "name": "柳捕快"},
	8: {"type": "hero", "id": "hu_qigai", "name": "胡乞丐"},
	9: {"type": "hero", "id": "wu_shiren", "name": "武石仁"},
	10: {"type": "hero", "id": "zhu_daliang", "name": "朱大亮"},
	11: {"type": "hero", "id": "yan_xiaoer", "name": "严小二"},
	12: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	13: {"type": "hero", "id": "zheng_chuzi", "name": "郑厨子"},
	14: {"type": "hero", "id": "he_yashi", "name": "何雅士"},
	15: {"type": "hero", "id": "zhang_laobo", "name": "张老伯"},
	16: {"type": "hero", "id": "li_gushi", "name": "黎蛊师"},
	17: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	18: {"type": "hero", "id": "liu_silang", "name": "刘四郎"},
	19: {"type": "hero", "id": "jia_houzi", "name": "贾猴子"},
	20: {"type": "hero", "id": "wan_jinya", "name": "万金牙"},
	21: {"type": "hero", "id": "qin_jianxian", "name": "秦剑仙"},
	22: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	23: {"type": "hero", "id": "luo_sunshan", "name": "洛孙山"},
	24: {"type": "hero", "id": "zhuang_gengfu", "name": "庄更夫"},
	25: {"type": "hero", "id": "liu_xizi", "name": "刘戏子"},
	26: {"type": "hero", "id": "xing_huwei", "name": "邢护卫"},
	27: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	28: {"type": "hero", "id": "cai_yufu", "name": "蔡渔夫"},
	29: {"type": "hero", "id": "yao_wuzuo", "name": "姚仵作"},
	30: {"type": "hero", "id": "tang_hulu", "name": "唐葫芦"},
	31: {"type": "hero", "id": "yun_youren", "name": "云游人"},
	32: {"type": "beast", "id": "zou_yu", "name": "驺虞"},
	33: {"type": "hero", "id": "tian_shiren", "name": "田诗人"},
	34: {"type": "hero", "id": "niu_fushi", "name": "牛符师"},
	35: {"type": "hero", "id": "jia_jiguan", "name": "贾机关"},
	36: {"type": "hero", "id": "li_jianchi", "name": "李剑痴"},
}

var identity_rewards_claimed: Dictionary = {}

# ========== 特惠礼包配置表 ==========
# 字段：name 礼包名 / desc 内容描述 / cost 价格(元) / items 道具及数量
const SPECIAL_PACKS = [
	{"name": "封神志×100",   "desc": "兑换封神灵兽",                 "cost": 10000, "items": {"feng_shen_zhi": 100}},
	{"name": "山海石×100",   "desc": "兑换山海异兽",                 "cost": 10000, "items": {"shan_hai_shi": 100}},
	{"name": "鸿荒火×100",   "desc": "兑换上古凶兽",                 "cost": 10000, "items": {"hong_huang_huo": 100}},
	{"name": "九渊之水×100", "desc": "兑换蛮荒主兽",                 "cost": 10000, "items": {"jiu_yuan_shui": 100}},
	{"name": "星枢麟角×100", "desc": "兑换星神圣兽",                 "cost": 50000, "items": {"xing_shu_lin": 100}},
	{"name": "许愿石礼包",   "desc": "木梳×2000 + 胭脂×2000 + 许愿石×200", "cost": 1998, "items": {"wood_comb": 2000, "rouge": 2000, "wish_stone": 200}},
	{"name": "门客盒子礼包", "desc": "门客盒子×1",                   "cost": 10000, "items": {"hero_box": 1}},
	{"name": "门客帖礼包",   "desc": "门客帖×10",                    "cost": 1000,  "items": {"hero_token": 10}},
]

# ========== 元宝商城礼包表 ==========
# 字段：name 礼包名 / desc 内容描述 / cost 价格(元宝)
# 可选：items 道具及数量 / beast 珍兽ID / beast_fruit 珍兽果 / aroma_fruit 奇香果
const MALL_PACKS = [
	{"name": "驺虞礼包",   "desc": "驺虞×1 + 珍兽果×988 + 奇香果×988", "cost": 19888, "beast": "zou_yu", "beast_fruit": 988, "aroma_fruit": 988},
	{"name": "小时卡礼包", "desc": "小时卡×999",                        "cost": 998,   "items": {"hour_card": 999}},
	{"name": "活力礼包",   "desc": "木梳×1000 + 胭脂×1000 + 活力丹×2000 + 玫瑰香水×1", "cost": 1988,  "items": {"wood_comb": 1000, "rouge": 1000, "vitality_pill": 2000, "rose_perfume": 1}},
	{"name": "声望礼包",   "desc": "声望卡×100 + 高级声望卡×10", "cost": 988,  "items": {"reputation_card": 100, "reputation_card_adv": 10}},
	
]

# ========== 行善系统 ==========
const CHARITY_LOCATIONS = [
	{"id": "da_fo",     "name": "大佛", "career": "侠", "way_item": "xia_way"},
	{"id": "zhou_peng", "name": "粥棚", "career": "农", "way_item": "nong_way"},
	{"id": "xue_tang",  "name": "学堂", "career": "士", "way_item": "shi_way"},
	{"id": "shu_ta",    "name": "书塔", "career": "工", "way_item": "gong_way"},
	{"id": "liang_cang","name": "粮仓", "career": "商", "way_item": "shang_way"},
]
const CHARITY_BASE_COST = 10000        # 首次行善消耗铜钱
const CHARITY_COST_MULT = 1.5          # 每次消耗递增倍率
const CHARITY_EFFECT_PER_TIER = 50     # 每档：对应职业的徒弟赚速加成池 +50

# 各地点进度：{"da_fo": {"progress": 当前档进度, "tier": 已完成档数}, ...}
var charity_progress: Dictionary = {}
var charity_click_count: int = 0       # 今日行善次数（决定消耗）
var charity_last_day: String = ""      # 上次行善日期，跨天重置次数

#==============道具物品=========================
# 【重构】道具表外置到 res://data/items.json，启动时由 _load_items_config() 加载
# controller 仍通过 data.ITEM_CONFIG 访问，用法完全不变
var ITEM_CONFIG: Dictionary = {}

#=========道具初始数量===========
# 【重构】由 _load_items_config() 按 items.json 的 initial 段填充；未列出的道具自动补0
var items: Dictionary = {}

# ========== 门客帖兑换表 ==========
const TOKEN_EXCHANGE_HEROES = [
	{"id": "hong_laoxie", "cost": 20},      # 洪老邪
	{"id": "shen_wansan", "cost": 20},      # 沈万三
	{"id": "li_shenshou", "cost": 20},      # 李神手
	{"id": "zhen_tufu", "cost": 20},        # 镇屠夫
	{"id": "yan_xiansheng", "cost": 20},    # 严先生
	{"id": "feng_mier", "cost": 20},        # 冯蜜儿
	{"id": "cao_tiejiang", "cost": 10},     # 曹铁匠
	{"id": "zhao_liehu", "cost": 10},       # 赵猎户
	{"id": "qian_caizhu", "cost": 10},      # 钱财主
	{"id": "pi_yingjiang", "cost": 10},     # 皮影匠人
]

const TOKEN_EXCHANGE_FRIENDS = [
	{"id": "miao_jiang_shengnv", "cost": 20},   # 苗疆圣女
	{"id": "yi_shi", "cost": 20},               # 驿使
	{"id": "xun_ying_shaonv", "cost": 20},      # 驯鹰少女
	{"id": "hua_yi_shi", "cost": 20},           # 花艺师
	{"id": "bu_kuai", "cost": 20},              # 捕快
	{"id": "xun_ma_shi", "cost": 20},           # 驯马师
	{"id": "qi_shi", "cost": 10},               # 棋士
]

# ========== 徒弟系统 ==========
const APPRENTICE_MAX_PROGRESS = 10000        # 培养进度上限（满则成年）
const APPRENTICE_PROGRESS_PER_TRAIN = 4      # 每次培养提升的进度
const APPRENTICE_TRAIN_COST = 10000          # 每次培养消耗铜钱
const APPRENTICE_TRAIN_EXP = 3100            # 每次培养获得阅历
const APPRENTICE_VIGOR_MAX = 500             # 每个槽位活力上限
const APPRENTICE_UNLOCK_LEVELS = [3, 6, 9, 12, 15]  # 5个槽位解锁所需身份等级
const APPRENTICE_CAREERS = ["士", "农", "工", "商", "侠"]
const APPRENTICE_MALE_NAMES = ["阿宝", "小虎", "石头", "铁蛋", "柱子"]
const APPRENTICE_FEMALE_NAMES = ["小蝶", "阿翠", "丫丫", "秀儿", "花儿"]

# ========== 挚友美名 / 徒弟品质表 ==========
# 友好和才华都达到 req 才拥有该美名（自动生效，取最高档）
# 徒弟品质在领养时按挚友当前美名定格，徒弟赚速基数用 income 列
const FRIEND_TITLES = [
	{"title": "淑女", "req": 100,    "quality": "平庸", "income": 1000},
	{"title": "才女", "req": 250,    "quality": "活泼", "income": 1250},
	{"title": "玉女", "req": 500,    "quality": "伶俐", "income": 1500},
	{"title": "伊人", "req": 800,    "quality": "机敏", "income": 2000},
	{"title": "佳人", "req": 1000,   "quality": "聪明", "income": 3000},
	{"title": "丽人", "req": 2000,   "quality": "颖慧", "income": 5000},
	{"title": "红粉", "req": 4000,   "quality": "睿智", "income": 9000},
	{"title": "婵娟", "req": 8000,   "quality": "天才", "income": 17000},
	{"title": "花魁", "req": 20000,  "quality": "神童", "income": 33000},
	{"title": "国色", "req": 50000,  "quality": "灵心", "income": 65000},
	{"title": "仙子", "req": 100000, "quality": "天人", "income": 129000},
	{"title": "天仙", "req": 200000, "quality": "仙童", "income": 257000},
]


# 5个徒弟槽位：null=空位，字典=已有徒弟
var apprentices: Array = [null, null, null, null, null]
const APPRENTICE_TWIN_CHANCE = 0.01   # 领养时双胞胎概率
# 已结业的徒弟（魔法师/现充/已婚），结业后离开培养位进入这里
var graduated_apprentices: Array = []
# 每个槽位独立的活力与上次恢复时间（懒结算用）
var apprentice_vigor: Array = [500, 500, 500, 500, 500]
var apprentice_vigor_time: Array = [0, 0, 0, 0, 0]

# ========== 系列兑换表 ==========
# grant_friend = true 时，兑换门客同时获得 entry.friend 指定的同名挚友（秦淮五艳）
const SERIES_EXCHANGE = [
	{
		"series": "一代宗匠",
		"heroes": [
			{"hero": "gao_jianli", "item": "zongjiang_ling", "cost": 20},
			{"hero": "su_wu", "item": "zongjiang_ling", "cost": 20},
			{"hero": "bi_sheng", "item": "zongjiang_ling", "cost": 20},
			{"hero": "zong_ze", "item": "zongjiang_ling", "cost": 20},
			{"hero": "zhang_sanfeng", "item": "zongjiang_ling", "cost": 20},
		],
	},
	{
		"series": "开山鼻祖",
		"heroes": [
			{"hero": "wu_daozi", "item": "kaishan_ling", "cost": 20},
			{"hero": "sun_bin", "item": "kaishan_ling", "cost": 20},
			{"hero": "du_kang", "item": "kaishan_ling", "cost": 20},
			{"hero": "ou_yezi", "item": "kaishan_ling", "cost": 20},
		],
	},
	{
		"series": "秦淮五艳",
		"grant_friend": true,
		"heroes": [
			{"hero": "ma_xianglan", "friend": "ma_xianglan_friend", "item": "panzhu_zhuiyu", "cost": 100},
			{"hero": "dong_xiaowan", "friend": "dong_xiaowan_friend", "item": "zhimeng_zhuiyu", "cost": 100},
			{"hero": "bian_yujing", "friend": "bian_yujing_friend", "item": "yingge_zhuiyu", "cost": 100},
			{"hero": "li_xiangjun", "friend": "li_xiangjun_friend", "item": "luohua_zhuiyu", "cost": 100},
			{"hero": "kou_baimen", "friend": "kou_baimen_friend", "item": "liuyun_zhuiyu", "cost": 100},
		],
	},
	{
		"series": "一世枭雄",
		"heroes": [
			{"hero": "song_huizong", "item": "xuanhe_qixi", "cost": 100},
			{"hero": "song_jiang", "item": "tiankui_lingqi", "cost": 100},
			{"hero": "huo_yanwang", "item": "yuanhun_dou", "cost": 100},
			{"hero": "cai_jing", "item": "quanxiang_guan", "cost": 100},
			{"hero": "lv_bu", "item": "fangtian_huaji", "cost": 100},
			{"hero": "qin_shihuang", "item": "taia_jian", "cost": 100},
			{"hero": "sun_wu", "item": "hufu_junling", "cost": 100},
			{"hero": "qin_qiong_yuchi_gong", "item": "suitang_huaben", "cost": 100},
			{"hero": "xiang_yu", "item": "bawang_qiang", "cost": 100},
			{"hero": "song_taizu", "item": "huanglong_jinduan", "cost": 100},
		],
	},
	{
		"series": "奇人异士",
		"heroes": [
			{"hero": "shi_gandang", "item": "tiangong_zanchui", "cost": 100},
			{"hero": "baixi_shengdao", "item": "qisheng_mianju", "cost": 100},
			{"hero": "dunhuang_jiangshen", "item": "danqing_pan", "cost": 100},
			{"hero": "gun_haijiao", "item": "cangbao_tu", "cost": 100},
			{"hero": "ne_zha", "item": "huojian_qiang", "cost": 100},
			{"hero": "ao_wu", "item": "shoulie_guren", "cost": 100},
			{"hero": "zheng_he", "item": "chengzu_chiling", "cost": 100},
			{"hero": "long_xiang", "item": "wulong_xiuqiu", "cost": 100},
			{"hero": "luo_haiwang", "item": "yugu_dao", "cost": 100},
		],
	},
	{
		"series": "徒弟",
		"heroes": [
			{"hero": "xiao_qi", "item": "yuye_jinhua", "cost": 100},
			{"hero": "xiao_ba", "item": "linglong_hebao", "cost": 100},
		],
	},
]



# 系列兑换（可附带同名挚友）
func exchange_series_hero(hero_id: String, item_id: String, cost: int, friend_id: String = "") -> Dictionary:
	if heroes.has(hero_id):
		return {"ok": false, "reason": "已拥有该门客"}
	if items.get(item_id, 0) < cost:
		return {"ok": false, "reason": "兑换道具不足"}
	if not unlock_hero(hero_id):
		return {"ok": false, "reason": "兑换失败"}
	items[item_id] -= cost
	if friend_id != "":
		unlock_friend(friend_id)
	return {"ok": true}

# 已领取的VIP奖励等级（true=已领取）
var vip_claimed_rewards: Dictionary = {}

# ========== 关卡系统 ==========
var stage_main: int = 1
var stage_sub: int = 1
var stage_trade_count: int = 0
var reputation: int = 0
var lottery_ticket: int = 0

# 门客字典（仅包含已拥有的）
var heroes: Dictionary = {}
var friends: Dictionary = {}
var shops: Dictionary = {}


# ========== 配置表（运行时只读） ==========
var _hero_configs: Dictionary = {}
var _friend_configs: Dictionary = {}
var _vip_rewards: Dictionary = {}
var _shop_configs: Dictionary = {}
func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("配置缺失: " + path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("JSON解析失败: " + path)
		return {}
	return json.get_data()





const SURNAMES = ["赵","钱","孙","李","周","吴","郑","王","冯","陈","褚","卫","蒋","沈","韩","杨","朱","秦","尤","许"]
const NAME_PARTS = ["富贵","旺财","来福","德财","金宝","元宝","招财","进宝","大发","鸿运","兴隆","昌盛","鼎盛","荣华","锦绣","吉祥","如意","平安","康泰","兴旺"]

var last_login_time: int = 0      # 本次登录时间
var last_logout_time: int = 0     # 上次正常退出时间

# ========== 初始货币 ==========
var money: int = 0
var yuanbao: int = 0
var energy: int = 100
var vip_level: int = 0
var vip_exp: int = 0

# ========== 个人信息 ==========
var player_name: String = ""
var identity_level: int = 1
var last_daily_reward_time: int = 0

var _beast_configs: Dictionary = {}

var beasts: Dictionary = {}
var beast_fruit: int = 0
var aroma_fruit: int = 0

# ========== 钱庄（特殊建筑）==========
var hq = {
	"name": "钱庄",
	"click_income": 100,
	"auto_base": 100,
	"level": 1,
	"upgrade_cost": 1,
	"income_mult": 1.5,
	"global_bonus": 0.05,
}

# ========== 【新增】游历体力系统 ==========
var STAMINA_MAX: int = 30                # 体力自动恢复上限（杜康事件可超上限）
var STAMINA_RECOVER_SECONDS: int = 1200  # 每20分钟恢复1点体力

var stamina: int = STAMINA_MAX         # 当前体力（游历消耗，1点/次）
var stamina_time: int = 0              # 上次体力恢复结算时间戳（懒结算用）

# 懒结算体力：每20分钟恢复1点，30只是自动恢复的上限（杜康事件可超上限）
func _settle_stamina():

	var now = int(Time.get_unix_time_from_system())
	if stamina_time <= 0:
		stamina_time = now
		return
	# 体力已满（或超出上限）：不再恢复，但绝不能截断超出部分
	if stamina >= STAMINA_MAX:
		stamina_time = now
		return
	@warning_ignore("integer_division")
	var regen = (now - stamina_time) / STAMINA_RECOVER_SECONDS
	if regen > 0:
		stamina = min(STAMINA_MAX, stamina + regen)
		@warning_ignore("narrowing_conversion")
		stamina_time = stamina_time + regen * STAMINA_RECOVER_SECONDS

# 获取当前体力（先懒结算恢复）
func get_stamina() -> int:
	_settle_stamina()
	return stamina

# ========== 【新增】游历系统（XLS表1：地点/物品/事件） ==========
var TRAVEL_REPUTATION: int = 20          # 每次游历固定获得的声望
var TRAVEL_LOCATION_CHANCE: float = 0.5  # 抽到"地点"的概率
var TRAVEL_ITEM_CHANCE: float = 0.4      # 抽到"物品"的概率（其余10%为事件）
# 【重构新增】游历事件数值：原为硬编码，外置便于调节
var EV_CAI_SHEN_YUANBAO: int = 1000      # 财神到：元宝+N
var EV_DU_KANG_MIN: int = 1              # 杜康赠酒：体力+MIN~MAX
var EV_DU_KANG_MAX: int = 3
var EV_NEW_DISH_INCOME: int = 2000       # 今日新菜：基础赚速+N

# 游历地点表：id -> {name=显示名, friends=该地点可相遇挚友ID列表（含表2挚友）}
# 【重构】三张表外置到 res://data/travel.json，启动时由 _load_travel_config() 加载
var TRAVEL_LOCATIONS: Dictionary = {}

# 表2：好感解锁挚友（未拥有时游历相遇好感+1，达到要求即 unlock_friend 获得）
var TRAVEL_AFFECTION: Dictionary = {}

# 游历物品池：20项等概率，{item=道具ID, count=抽中后给N个}
# 注意：表格里的"许愿果"映射到现有许愿石 wish_stone；珍兽果/奇香果是独立货币，结算时加变量不加items
var TRAVEL_ITEM_POOL: Array = []

# 未拥有表2挚友的好感进度（fid -> 好感值），达标获得后清除
var friend_affection: Dictionary = {}
# 月老/观音祝福层数：可一直累计，只有谈心真正领养到徒弟时才消耗
var yuelao_count: int = 0    # 月老：下次谈心（能领养时）对象改为当前友好最高的挚友
var guanyin_count: int = 0   # 观音：下次谈心（能领养时）必定双胞胎

# 游历：消耗1点体力，固定声望+20，再按50%/40%/10%触发地点/物品/事件
func do_travel() -> Dictionary:
	_settle_stamina()
	if stamina < 1:
		return {"ok": false, "msg": "体力不足"}
	stamina -= 1
	reputation += TRAVEL_REPUTATION
	var roll = randf()
	if roll < TRAVEL_LOCATION_CHANCE:
		return _do_travel_location()
	elif roll < TRAVEL_LOCATION_CHANCE + TRAVEL_ITEM_CHANCE:
		return _do_travel_item()
	return _do_travel_event()

# 游历到地点：随机一个地点，从该地点「已拥有挚友 + 未拥有的表2挚友」中随机相遇
# 已拥有挚友友好+1；未拥有表2挚友好感+1，达标即获得
func _do_travel_location() -> Dictionary:
	var loc_ids = TRAVEL_LOCATIONS.keys()
	var loc_id = loc_ids[randi() % loc_ids.size()]
	var loc = TRAVEL_LOCATIONS[loc_id]
	# 筛选候选：该地点中已拥有的挚友 + 未拥有但属于表2的挚友
	var candidates = []
	for fid in loc.friends:
		if friends.has(fid):
			candidates.append(fid)
		elif TRAVEL_AFFECTION.has(fid):
			candidates.append(fid)
	if candidates.is_empty():
		return {"ok": true, "type": "location", "msg": "游历到【%s】，没有遇到熟人，声望+%d" % [loc.name, TRAVEL_REPUTATION]}
	var fid = candidates[randi() % candidates.size()]
	var cfg = get_friend_config(fid)
	if friends.has(fid):
		# 已拥有：友好+1
		friends[fid].friendly += 1
		return {"ok": true, "type": "location", "msg": "游历到【%s】，偶遇挚友【%s】，友好+1，声望+%d" % [loc.name, cfg.get("name", fid), TRAVEL_REPUTATION]}
	# 未拥有的表2挚友：好感+1，达标则获得
	friend_affection[fid] = friend_affection.get(fid, 0) + 1
	var need = TRAVEL_AFFECTION[fid]
	if friend_affection[fid] >= need:
		unlock_friend(fid)
		friend_affection.erase(fid)
		return {"ok": true, "type": "location", "msg": "游历到【%s】，与【%s】好感已满，喜获挚友！声望+%d" % [loc.name, cfg.get("name", fid), TRAVEL_REPUTATION], "unlock_friend": fid}
	return {"ok": true, "type": "location", "msg": "游历到【%s】，与【%s】相遇，好感+1（%d/%d），声望+%d" % [loc.name, cfg.get("name", fid), friend_affection[fid], need, TRAVEL_REPUTATION]}

# 游历获得物品：物品池20项等概率，抽中给 entry.count 个
func _do_travel_item() -> Dictionary:
	var entry = TRAVEL_ITEM_POOL[randi() % TRAVEL_ITEM_POOL.size()]
	var item_id = entry.item
	var count = entry.count
	# 珍兽果/奇香果是独立货币（珍兽页面消费用变量），其余进背包
	match item_id:
		"beast_fruit":
			beast_fruit += count
		"aroma_fruit":
			aroma_fruit += count
		_:
			items[item_id] = items.get(item_id, 0) + count
	var item_name = ITEM_CONFIG.get(item_id, {}).get("name", item_id)
	return {"ok": true, "type": "item", "msg": "游历途中获得【%s】×%d，声望+%d" % [item_name, count, TRAVEL_REPUTATION]}

# 游历遭遇事件：5个事件等概率
# 财神到=元宝+1000；月老/观音=祝福层数+1（可累计）；杜康=体力+1~3（可超上限）；今日新菜=赚速最高门客基础赚速+2000
func _do_travel_event() -> Dictionary:
	var events = ["cai_shen", "yue_lao", "guan_yin", "du_kang", "new_dish"]
	var event_id = events[randi() % events.size()]
	match event_id:
		"cai_shen":
			yuanbao += EV_CAI_SHEN_YUANBAO   # 【重构】数值走变量（travel.json可调）
			return {"ok": true, "type": "event", "msg": "遭遇【财神到】！元宝+%d，声望+%d" % [EV_CAI_SHEN_YUANBAO, TRAVEL_REPUTATION]}
		"yue_lao":
			yuelao_count += 1
			return {"ok": true, "type": "event", "msg": "遭遇【月老】！获得1层祝福：下次谈心（能领养徒弟时）将与友好最高的挚友谈心（当前累计%d层），声望+%d" % [yuelao_count, TRAVEL_REPUTATION]}
		"guan_yin":
			guanyin_count += 1
			return {"ok": true, "type": "event", "msg": "遭遇【观音】！获得1层祝福：下次谈心（能领养徒弟时）必为双胞胎（当前累计%d层），声望+%d" % [guanyin_count, TRAVEL_REPUTATION]}
		"du_kang":
			# 杜康赠酒：体力+MIN~MAX，不受自动恢复上限限制
			_settle_stamina()
			var gain = randi_range(EV_DU_KANG_MIN, EV_DU_KANG_MAX)   # 【重构】数值走变量
			stamina += gain
			return {"ok": true, "type": "event", "msg": "遭遇【杜康】！共饮美酒，体力+%d（当前%d点），声望+%d" % [gain, stamina, TRAVEL_REPUTATION]}
		"new_dish":
			# 今日新菜：当前总赚速最高的已拥有门客基础赚速+N
			var best_id = ""
			var best_income = -1
			for hid in heroes.keys():
				var income = get_hero_income(hid)
				if income > best_income:
					best_income = income
					best_id = hid
			if best_id == "":
				return {"ok": true, "type": "event", "msg": "遭遇【今日新菜】，但还没有门客可以享用，声望+%d" % TRAVEL_REPUTATION}
			heroes[best_id].base_income += EV_NEW_DISH_INCOME   # 【重构】数值走变量
			return {"ok": true, "type": "event", "msg": "遭遇【今日新菜】！【%s】大快朵颐，基础赚速+%d，声望+%d" % [heroes[best_id].name, EV_NEW_DISH_INCOME, TRAVEL_REPUTATION]}
	# 安全兜底：match 五个分支均已return，此行理论上不可达
	return {"ok": false, "msg": "未知事件"}

# 是否存在已解锁的空徒弟槽位（月老/观音祝福生效的前提）
func _has_empty_apprentice_slot() -> bool:
	for i in range(5):
		if not is_apprentice_slot_unlocked(i): break
		var entry = apprentices[i]
		if entry == null or (entry is Array and entry.is_empty()):
			return true
	return false

# 当前友好最高的已拥有挚友ID（月老牵线的谈心对象）；没有挚友时返回空串
func _get_highest_friendly_friend() -> String:
	var best_id = ""
	var best_friendly = -1
	for fid in friends.keys():
		var fv = friends[fid].get("friendly", 0)
		if fv > best_friendly:
			best_friendly = fv
			best_id = fid
	return best_id

# 谈心前的祝福结算：返回 {"target"=谈心挚友ID, "force_twin"=是否必双胞胎, "yuelao"=月老是否生效, "guanyin"=观音是否生效}
# 只有存在徒弟空位（本次谈心能领养）时才消耗层数；没有空位则层数保留、继续累计
func _prepare_chat_adoption(default_friend_id: String) -> Dictionary:
	var bless = {"target": default_friend_id, "force_twin": false, "yuelao": false, "guanyin": false}
	if not _has_empty_apprentice_slot():
		return bless
	if yuelao_count > 0:
		yuelao_count -= 1
		var top_id = _get_highest_friendly_friend()
		if top_id != "":
			bless.target = top_id
		bless.yuelao = true
	if guanyin_count > 0:
		guanyin_count -= 1
		bless.force_twin = true
		bless.guanyin = true
	return bless

func _load_all_configs():
	_hero_configs = _load_json("res://data/heroes.json")
	_friend_configs = _load_json("res://data/friends.json")
	_vip_rewards = _load_json("res://data/vip_rewards.json")
	_shop_configs = _load_json("res://data/shops.json")
	_beast_configs = _load_json(BEAST_CONFIG_PATH)
	_load_items_config()   # 【重构新增】道具表
	_load_travel_config()  # 【重构新增】游历配置

# 【重构新增】加载 res://data/items.json：道具定义 + 新档初始数量（未列出的道具自动补0）
func _load_items_config():
	var d = _load_json("res://data/items.json")
	ITEM_CONFIG = d.get("config", {})
	items.clear()
	var init: Dictionary = d.get("initial", {})
	for item_id in ITEM_CONFIG.keys():
		# JSON读出的数字全是float，统一转int，避免计数和"%d"显示出错
		items[item_id] = int(init.get(item_id, 0))

# 【重构新增】加载 res://data/travel.json：settings数值 + 地点表 + 表2好感表 + 物品池
func _load_travel_config():
	var d = _load_json("res://data/travel.json")
	var s: Dictionary = d.get("settings", {})
	# settings缺项时保留代码里的默认值兜底
	STAMINA_MAX = int(s.get("stamina_max", STAMINA_MAX))
	STAMINA_RECOVER_SECONDS = int(s.get("stamina_recover_seconds", STAMINA_RECOVER_SECONDS))
	TRAVEL_REPUTATION = int(s.get("reputation_per_travel", TRAVEL_REPUTATION))
	TRAVEL_LOCATION_CHANCE = float(s.get("location_chance", TRAVEL_LOCATION_CHANCE))
	TRAVEL_ITEM_CHANCE = float(s.get("item_chance", TRAVEL_ITEM_CHANCE))
	EV_CAI_SHEN_YUANBAO = int(s.get("cai_shen_yuanbao", EV_CAI_SHEN_YUANBAO))
	EV_DU_KANG_MIN = int(s.get("du_kang_stamina_min", EV_DU_KANG_MIN))
	EV_DU_KANG_MAX = int(s.get("du_kang_stamina_max", EV_DU_KANG_MAX))
	EV_NEW_DISH_INCOME = int(s.get("new_dish_income", EV_NEW_DISH_INCOME))
	TRAVEL_LOCATIONS = d.get("locations", {})
	TRAVEL_AFFECTION = d.get("affection", {})
	TRAVEL_ITEM_POOL = d.get("item_pool", [])
	# JSON数字全是float，好感阈值和物品数量统一转int
	for fid in TRAVEL_AFFECTION.keys():
		TRAVEL_AFFECTION[fid] = int(TRAVEL_AFFECTION[fid])
	for entry in TRAVEL_ITEM_POOL:
		entry["count"] = int(entry["count"])

# 获取门客配置（只读模板）
func get_hero_config(hero_id: String) -> Dictionary:
	return _hero_configs.get(hero_id, {}).duplicate(true)

# 获取挚友配置（只读模板）
func get_friend_config(friend_id: String) -> Dictionary:
	return _friend_configs.get(friend_id, {}).duplicate(true)

# 获取全部门客配置ID（用于UI显示未解锁）
func get_all_hero_ids() -> Array:
	return _hero_configs.keys()

# 获取全部挚友配置ID
func get_all_friend_ids() -> Array:
	return _friend_configs.keys()

# 获取VIP奖励表
func get_vip_rewards() -> Dictionary:
	return _vip_rewards

func get_shop_config(shop_id: String) -> Dictionary:
	return _shop_configs.get(shop_id, {}).duplicate(true)

func get_shop_unlock_chapter(shop_id: String) -> int:
	return SHOP_UNLOCK_TABLE.get(shop_id, 999999)

func can_unlock_shop(shop_id: String) -> bool:
	if shops.has(shop_id): return false
	return stage_main >= get_shop_unlock_chapter(shop_id)

func unlock_shop(shop_id: String) -> bool:
	if not can_unlock_shop(shop_id): return false
	if not _shop_configs.has(shop_id): return false
	shops[shop_id] = _shop_configs[shop_id].duplicate(true)
	return true


# ========== 角色解锁（所有获得途径统一走这里） ==========
func unlock_hero(hero_id: String) -> bool:
	if heroes.has(hero_id): return false
	var cfg = get_hero_config(hero_id)
	if cfg.is_empty(): return false
	heroes[hero_id] = cfg
	return true

func unlock_friend(friend_id: String) -> bool:
	if friends.has(friend_id): return false
	var cfg = get_friend_config(friend_id)
	if cfg.is_empty(): return false
	friends[friend_id] = cfg
	_init_friend_shop_skills(friend_id)
	return true




# ========== 计算函数 ==========

# 挚友店铺技能列表
func _init_friend_shop_skills(friend_id: String):
	if not friends.has(friend_id): return
	var f = friends[friend_id]
	var categories = ["士", "农", "工", "商", "侠"]
	var skills = []
	for i in range(400):
		skills.append({
			"category": categories[i % 5],
			"bonus": 0.05,
			"refresh_count": 0
		})
	f.shop_skills = skills

func get_friend_shop_skills(friend_id: String) -> Array:
	if not friends.has(friend_id): return []
	var f = friends[friend_id]
	if not f.has("shop_skills"):
		_init_friend_shop_skills(friend_id)
	var max_slots = min(400, int(f.friendly / 500))
	var skills = f.shop_skills
	var result = []
	for i in range(min(max_slots, skills.size())):
		result.append(skills[i])
	return result

func refresh_friend_shop_skill(friend_id: String, skill_index: int, use_wish_stone: bool = false) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	if not f.has("shop_skills"): _init_friend_shop_skills(friend_id)
	var skills = f.shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var max_slots = min(400, int(f.friendly / 500))
	if skill_index >= max_slots: return false
	
	var skill = skills[skill_index]
	if skill.bonus >= 0.30: return false
	
	if use_wish_stone:
		var wish_cost = 1
		if items.get("wish_stone", 0) < wish_cost:
			return false
		items.wish_stone -= wish_cost
		skill.refresh_count += 1
		var new_bonus = randf_range(0.20, 0.31)
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	else:
		var cost = 100 * int(pow(2, skill.refresh_count))
		if money < cost: return false
		money -= cost
		skill.refresh_count += 1
		
		var roll = randf()
		var new_bonus: float
		if roll < 0.9:
			# 90% 概率刷新出 5% ~ 19% 的加成
			new_bonus = randf_range(0.05, 0.199)
		else:
			# 10% 概率刷新出 20% ~ 30% 的加成
			new_bonus = randf_range(0.20, 0.31)
		
		skill.bonus = max(skill.bonus, new_bonus)
		if skill.bonus >= 0.295:
			skill.bonus = 0.30
	return true

# 挚友给门客的加成
func get_friend_hero_bonus(friend_id: String) -> int:
	if not friends.has(friend_id): return 0
	var f = friends[friend_id]
	var fixed_total = f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))
	var percent = 1.0 + f.percent_skill_level * 0.05
	return int(fixed_total * percent)

# 挚友的固定加成（天生丽质 → 额外赚速）
func get_friend_fixed_bonus(friend_id: String) -> int:
	if not friends.has(friend_id): return 0
	var f = friends[friend_id]
	return f.fixed_skill_level * (100 + 10 * (f.fixed_skill_level - 1))

# 挚友的百分比加成（花开富贵 → 百分比）
func get_friend_percent_bonus(friend_id: String) -> float:
	if not friends.has(friend_id): return 0.0
	var f = friends[friend_id]
	return f.percent_skill_level * 0.05

# 门客的额外赚速总和（人参 + 挚友固定加成）
func get_hero_extra_income(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var extra = heroes[hero_id].get("base_income", 0)
	for fid in friends.keys():
		if hero_id in friends[fid].bound_heroes:
			extra += get_friend_fixed_bonus(fid)
	return extra

# 门客的百分比加成总和（挚友 + 预留灵兽/藏宝）
func get_hero_percent_bonus(hero_id: String) -> float:
	if not heroes.has(hero_id): return 0.0
	var bonus = 0.0
	for fid in friends.keys():
		if hero_id in friends[fid].bound_heroes:
			bonus += get_friend_percent_bonus(fid)
	# 珍兽百分比加成
	var beast = get_hero_beast_bonus(hero_id)
	bonus += beast.percent
	# TODO: 藏宝加成
	return bonus

func get_hero_aptitude_bonus(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var bonus = 0
	# 珍兽资质加成
	var beast_id = heroes[hero_id].get("equipped_beast", "")
	if beast_id != "":
		var idx = heroes[hero_id].get("equipped_beast_index", 0)
		bonus += get_beast_aptitude(beast_id, idx)
	return bonus

# 门客总赚速（供 UI 显示）
func get_hero_income(hero_id: String) -> int:
	if not heroes.has(hero_id): return 0
	var h = heroes[hero_id]
	var total_apt = HeroData.get_total_aptitude(h) + get_hero_aptitude_bonus(hero_id)
	var base = int(total_apt * h.level * pow(h.breakthrough_count, 2))
	var percent = get_hero_percent_bonus(hero_id)
	var extra = get_hero_extra_income(hero_id)
	return int(base * (1.0 + percent) + extra)

# 门客对全局的贡献（供自动收入）
func get_hero_contribution(hero_id: String) -> int:
	var income = get_hero_income(hero_id)
	if income == 0: return 0
	var h = heroes[hero_id]
	return int(income * h.breakthrough_count * 0.5)

# 谈心
# 谈心：随机一位已拥有挚友，缘分+才华，有空位则领养徒弟
# 【修改】月老层数>0且有徒弟空位：本次谈心对象改为友好最高的挚友；观音层数>0且有徒弟空位：本次领养必为双胞胎
func chat_with_friend(once: bool = true) -> Dictionary:
	if energy <= 0: return {"ok": false, "reason": "精力不足"}
	
	var results = []
	if once:
		energy -= 1
		var keys = friends.keys()
		var fid = keys[randi() % keys.size()]
		# 【新增】月老/观音祝福结算（没有徒弟空位时不消耗层数）
		var bless = _prepare_chat_adoption(fid)
		fid = bless.target
		var f = friends[fid]
		f.bond += f.talent
		# 有空位则与本次谈心的挚友领养一位徒弟（观音生效时必双胞胎）
		var n = adopt_apprentice(fid, bless.force_twin)
		results.append({"friend_id": fid, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	else:
		while energy > 0:
			energy -= 1
			var keys = friends.keys()
			var fid = keys[randi() % keys.size()]
			# 【新增】一键谈心逐次结算月老/观音祝福
			var bless = _prepare_chat_adoption(fid)
			fid = bless.target
			var f = friends[fid]
			f.bond += f.talent
			# 一键谈心：有几个空位，前几位挚友就各领养一位
			var n = adopt_apprentice(fid, bless.force_twin)
			results.append({"friend_id": fid, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "yuelao": bless.yuelao, "guanyin": bless.guanyin})
	
	return {"ok": true, "results": results}

# 与指定挚友谈心（游山玩水/吟诗作对共用）：缘分+才华，有空位则领养徒弟
# 不消耗精力，消耗由调用方（元宝/玫瑰香水）负责
# 【修改】指定谈心不触发月老（对象已由玩家指定），观音祝福正常生效（必双胞胎）
func chat_with_specific_friend(friend_id: String) -> Dictionary:
	if not friends.has(friend_id): return {"ok": false, "reason": "未拥有该挚友"}
	var f = friends[friend_id]
	f.bond += f.talent
	# 【新增】观音祝福：有徒弟空位才生效并消耗一层
	var force_twin = false
	var guanyin_used = false
	if guanyin_count > 0 and _has_empty_apprentice_slot():
		guanyin_count -= 1
		force_twin = true
		guanyin_used = true
	var n = adopt_apprentice(friend_id, force_twin)
	return {"ok": true, "name": f.name, "gain": f.talent, "adopted": n > 0, "twin": n == 2, "guanyin": guanyin_used}

# 升级固定技能
func upgrade_friend_fixed(friend_id: String) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	var cost = (f.fixed_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.fixed_skill_level += 1
	return true

# 升级百分比技能
func upgrade_friend_percent(friend_id: String) -> bool:
	if not friends.has(friend_id): return false
	var f = friends[friend_id]
	var cost = (f.percent_skill_level + 1) * 100
	if f.bond < cost: return false
	f.bond -= cost
	f.percent_skill_level += 1
	return true

# 赠送
func gift_friend(friend_id: String, item_id: String) -> bool:
	if not friends.has(friend_id): return false
	if not items.has(item_id) or items[item_id] <= 0: return false
	var f = friends[friend_id]
	match item_id:
		"wood_comb":
			items.wood_comb -= 1
			f.friendly += 1
		"rouge":
			items.rouge -= 1
			f.talent += 1
		"energy_pill":
			items.energy_pill -= 1
			energy = min(100, energy + 3)
		_:
			return false
	return true

# 挚友当前美名下标：友好和才华都达标才算，-1=无美名
func get_friend_title_index(friend_id: String) -> int:
	if not friends.has(friend_id): return -1
	var f = friends[friend_id]
	var idx = -1
	for i in range(FRIEND_TITLES.size()):
		if f.friendly >= FRIEND_TITLES[i].req and f.talent >= FRIEND_TITLES[i].req:
			idx = i
	return idx

# 挚友当前美名（无美名返回"无"）
func get_friend_title(friend_id: String) -> String:
	var idx = get_friend_title_index(friend_id)
	return FRIEND_TITLES[idx].title if idx >= 0 else "无"

# ========== 徒弟：槽位 ==========

# 已解锁的徒弟槽位数（按身份等级）
func get_apprentice_slot_count() -> int:
	var count = 0
	for lv in APPRENTICE_UNLOCK_LEVELS:
		if identity_level >= lv:
			count += 1
	return count

# 指定槽位是否已解锁
func is_apprentice_slot_unlocked(slot: int) -> bool:
	return slot >= 0 and slot < get_apprentice_slot_count()

# 懒结算槽位活力：每分钟恢复1点，500只是自动恢复的上限（道具可超上限）
func _settle_slot_vigor(slot: int):
	var now = Time.get_unix_time_from_system()
	var last = apprentice_vigor_time[slot]
	if last <= 0:
		apprentice_vigor_time[slot] = now
		return
	# 活力已满（或超出上限）：不再恢复，但绝不能截断超出部分
	if apprentice_vigor[slot] >= APPRENTICE_VIGOR_MAX:
		apprentice_vigor_time[slot] = now
		return
	@warning_ignore("narrowing_conversion")
	var regen = int((now - last) / 60)
	if regen > 0:
		apprentice_vigor[slot] = min(APPRENTICE_VIGOR_MAX, apprentice_vigor[slot] + regen)
		@warning_ignore("narrowing_conversion")
		apprentice_vigor_time[slot] = last + regen * 60

# 获取槽位当前活力（先结算恢复）
func get_slot_vigor(slot: int) -> int:
	_settle_slot_vigor(slot)
	return apprentice_vigor[slot]

# ========== 徒弟：领养 ==========

# 与挚友领养徒弟：占用第一个已解锁的空位，1%概率双胞胎（同槽位两名，性别职业各自独立随机）
# 【修改】force_twin=true（观音祝福）时必定双胞胎
# 返回领养数量：0=没有空位，1=单人，2=双胞胎
func adopt_apprentice(friend_id: String, force_twin: bool = false) -> int:
	if not friends.has(friend_id): return 0
	for i in range(5):
		if not is_apprentice_slot_unlocked(i): break
		var entry = apprentices[i]
		if entry == null or (entry is Array and entry.is_empty()):
			var list = [_create_apprentice(friend_id)]
			if force_twin or randf() < APPRENTICE_TWIN_CHANCE:
				list.append(_create_apprentice(friend_id))
			apprentices[i] = list
			return list.size()
	return 0

# 创建一个徒弟（性别/职业独立随机，品质按领养时挚友美名定格）
func _create_apprentice(friend_id: String) -> Dictionary:
	var gender = "男" if randi() % 2 == 0 else "女"
	var pool = APPRENTICE_MALE_NAMES if gender == "男" else APPRENTICE_FEMALE_NAMES
	return {
		"name": SURNAMES[randi() % SURNAMES.size()] + pool[randi() % pool.size()],
		"gender": gender,
		"career": APPRENTICE_CAREERS[randi() % APPRENTICE_CAREERS.size()],
		"friend_id": friend_id,        # 领养来源挚友
		"quality_idx": max(0, get_friend_title_index(friend_id)),  # 品质按领养时美名定格
		"progress": 0,                 # 培养进度
		"state": "training",           # training/adult/magician/lover/married
		"magic_bonus": 0.0,            # 魔法师加成比例
		"spouse": {},                  # 配偶信息
		"spouse_income": 0,            # 联姻获得的赚速
		"income_bonus": 0,               # 【新增】徒弟赚速加成（结业时按职业加成池定格）
	}

# ========== 徒弟：赚速 ==========

# 单个徒弟的当前赚速
# 顺序：成年值 = 品质赚速+友好×10%+徒弟赚速加成 → 按进度线性 → 魔法师加成 → 联姻加成
func _get_single_apprentice_income(a: Dictionary) -> int:
	var f = friends.get(a.friend_id, {})
	var q = clamp(a.get("quality_idx", 0), 0, FRIEND_TITLES.size() - 1)
	var adult = FRIEND_TITLES[q].income + int(f.get("friendly", 0) * 0.1) + a.get("income_bonus", 0)
	var income = int(adult * a.progress / float(APPRENTICE_MAX_PROGRESS))
	if a.state == "magician":
		income = int(income * (1.0 + a.magic_bonus))
	elif a.state == "married":
		income += a.get("spouse_income", 0)
	return income

# 槽位总赚速：同槽每个徒弟单独计算后求和（双胞胎即两倍）
func get_apprentice_income(slot: int) -> int:
	var entry = apprentices[slot]
	if entry == null: return 0
	var list = entry if entry is Array else [entry]   # 兼容旧存档
	var total = 0
	for a in list:
		total += _get_single_apprentice_income(a)
	return total

# 已结业徒弟赚速（结业列表里都是单人条目）
func get_graduated_income(index: int) -> int:
	if index < 0 or index >= graduated_apprentices.size(): return 0
	return _get_single_apprentice_income(graduated_apprentices[index])

# ========== 徒弟：培养 / 结业 / 联姻 ==========

# 培养：10000铜钱 + 1活力 → 同槽所有徒弟进度各+4、阅历+3100；满进度成年
func train_apprentice(slot: int) -> Dictionary:
	if slot < 0 or slot >= 5: return {"ok": false, "reason": "槽位错误"}
	var entry = apprentices[slot]
	if entry == null: return {"ok": false, "reason": "空位"}
	var list = entry if entry is Array else [entry]
	if list.is_empty(): return {"ok": false, "reason": "空位"}
	if list[0].state != "training": return {"ok": false, "reason": "培养已完成"}
	if money < APPRENTICE_TRAIN_COST: return {"ok": false, "reason": "铜钱不足"}
	_settle_slot_vigor(slot)
	if apprentice_vigor[slot] < 1: return {"ok": false, "reason": "活力不足"}
	money -= APPRENTICE_TRAIN_COST
	apprentice_vigor[slot] -= 1
	# 双胞胎占同一槽位，一起培养
	for a in list:
		a.progress = min(APPRENTICE_MAX_PROGRESS, a.progress + APPRENTICE_PROGRESS_PER_TRAIN)
	items.experience += APPRENTICE_TRAIN_EXP
	var adult = list[0].progress >= APPRENTICE_MAX_PROGRESS
	if adult:
		for a in list:
			a.state = "adult"
	return {"ok": true, "adult": adult}

# 一键培养：连续培养直到活力耗尽 / 铜钱不足 / 已成年
func train_apprentice_batch(slot: int) -> Dictionary:
	var count = 0
	var adult = false
	while true:
		var r = train_apprentice(slot)
		if not r.ok:
			# 至少成功过一次就算成功，带上中断原因
			if count > 0:
				return {"ok": true, "count": count, "adult": adult, "stop_reason": r.reason}
			return r
		count += 1
		adult = adult or r.get("adult", false)
		if adult: break
	return {"ok": true, "count": count, "adult": adult}


# 使用活力丹：指定槽位活力 +5/个，不受自动恢复上限限制
func use_vitality_pill(slot: int, count: int) -> bool:
	if slot < 0 or slot >= 5 or count <= 0: return false
	if items.get("vitality_pill", 0) < count: return false
	_settle_slot_vigor(slot)
	items.vitality_pill -= count
	apprentice_vigor[slot] += 5 * count
	return true

# 结业转职（逐个进行，双胞胎轮流选择）："magician"=魔法师 / "lover"=现充
# 每次处理槽位里第一个待结业的徒弟，全部结业后槽位空出
func graduate_apprentice_one(slot: int, path: String) -> bool:
	if slot < 0 or slot >= 5: return false
	var entry = apprentices[slot]
	if entry == null: return false
	var list = entry if entry is Array else [entry]
	if list.is_empty(): return false
	var a = list[0]
	if a.state != "adult": return false
	a.income_bonus = get_charity_career_bonus(a.career)
	if path == "magician":
		a.magic_bonus = randf_range(0.7, 1.4)
		a.state = "magician"
	elif path == "lover":
		a.state = "lover"
	else:
		return false
	# 移入已结业列表
	graduated_apprentices.append(a)
	list.remove_at(0)
	# 槽位腾空（双胞胎的另一个还在的话保留槽位）
	if list.size() > 0:
		apprentices[slot] = list
	else:
		apprentices[slot] = null
	return true

# 生成联姻对象：性别相反、赚速与当前徒弟相同（index为已结业列表下标）
func generate_spouse(index: int) -> Dictionary:
	if index < 0 or index >= graduated_apprentices.size(): return {}
	var a = graduated_apprentices[index]
	if a == null: return {}
	var gender = "女" if a.gender == "男" else "男"
	var pool = APPRENTICE_MALE_NAMES if gender == "男" else APPRENTICE_FEMALE_NAMES
	return {
		"name": SURNAMES[randi() % SURNAMES.size()] + pool[randi() % pool.size()],
		"gender": gender,
		"career": APPRENTICE_CAREERS[randi() % APPRENTICE_CAREERS.size()],
		"income": get_graduated_income(index),
	}

# 联姻：获得对象赚速，进入已婚（index为已结业列表下标）
func marry_apprentice(index: int, spouse: Dictionary) -> bool:
	if index < 0 or index >= graduated_apprentices.size(): return false
	var a = graduated_apprentices[index]
	if a == null or a.state != "lover": return false
	a.spouse = spouse
	a.spouse_income = spouse.get("income", 0)
	a.state = "married"
	return true

func get_identity_reward(level: int) -> Dictionary:
	if IDENTITY_REWARD_TABLE.has(level):
		return IDENTITY_REWARD_TABLE[level]
	if level >= 37 and level <= 100:
		return {"type": "beast", "id": "zou_yu", "name": "驺虞"}
	return {}

func claim_identity_reward(level: int) -> Dictionary:
	var reward = get_identity_reward(level)
	if reward.is_empty():
		return {"ok": false, "reason": "该等级无奖励"}
	if identity_rewards_claimed.get(str(level), false):
		return {"ok": false, "reason": "已领取"}
	if identity_level < level:
		return {"ok": false, "reason": "身份等级不足"}
	
	var result = {"ok": true, "reward": reward, "duplicate": false}
	
	if reward.type == "hero":
		if heroes.has(reward.id):
			result.ok = false
			result.reason = "门客重复"
			result.duplicate = true
		else:
			unlock_hero(reward.id)
	elif reward.type == "beast":
		add_beast(reward.id)
	
	if result.ok:
		identity_rewards_claimed[str(level)] = true
	
	return result



#钱庄赚速
func get_hq_auto_income() -> int:
	return int(hq.auto_base * pow(hq.income_mult, hq.level - 1))

#钱庄全局加成
func get_global_bonus_percent() -> float:
	return hq.global_bonus * (hq.level - 1)

#店铺赚速
func get_shop_auto_income(shop_id: String) -> int:
	var s = shops[shop_id]
	#基础赚速
	var base = int(s.auto_base * pow(s.income_mult, s.level - 1))
	#店员赚速
	var staff = s.staff * s.staff_income
	
	# 门客派遣加成
	var hero_bonus = 0.0
	for hero_id in heroes.keys():
		if heroes[hero_id].assigned_shop == shop_id:
			hero_bonus += HeroData.get_shop_bonus(heroes[hero_id])

	# 挚友加成
	var friend_shop_bonus = 0.0
	for fid in friends.keys():
		for sk in get_friend_shop_skills(fid):
			if sk.category == s.get("category", ""):
				friend_shop_bonus += sk.bonus

	#基础+店员
	var subtotal = base + staff
	
	#总百分比
	var bonus = 1.0 + get_global_bonus_percent()+hero_bonus + friend_shop_bonus
	#返回最终赚速
	return int(subtotal * bonus)

#总赚速
func get_total_auto_income() -> int:
	var total = get_hq_auto_income()
	for shop_id in shops.keys():
		total += get_shop_auto_income(shop_id)
	for hero_id in heroes.keys():
		total += get_hero_contribution(hero_id)
	# 徒弟赚速（含魔法师/联姻加成）
	for i in range(5):
		total += get_apprentice_income(i)
	return total

# ========== 身份晋升 ==========
func get_identity_income_req(target_level: int) -> int:
	return int(100 * pow(1.4, target_level - 1))

func get_identity_reputation_req(target_level: int) -> int:
	return int(10 * pow(1.22, target_level - 1))

func can_promote_identity() -> bool:
	if identity_level >= 100: return false
	var next = identity_level + 1
	return get_total_auto_income() >= get_identity_income_req(next) and reputation >= get_identity_reputation_req(next)

func promote_identity() -> bool:
	if not can_promote_identity(): return false
	identity_level += 1
	return true

func rename_player(new_name: String) -> bool:
	var trimmed = new_name.strip_edges()
	if trimmed == "": return false
	player_name = trimmed
	return true

# ========== 每日宝箱 ==========
func can_claim_daily_reward() -> bool:
	if last_daily_reward_time <= 0: return true
	var now = Time.get_unix_time_from_system()
	var now_dict = Time.get_date_dict_from_system(now)
	var last_dict = Time.get_date_dict_from_system(last_daily_reward_time)
	return now_dict.year != last_dict.year or now_dict.month != last_dict.month or now_dict.day != last_dict.day

func claim_daily_reward() -> int:
	if not can_claim_daily_reward(): return 0
	var reward = identity_level * 10000
	yuanbao += reward
	@warning_ignore("narrowing_conversion")
	last_daily_reward_time = Time.get_unix_time_from_system()
	return reward

# ========== 通用道具使用（数量型） ==========
# 背包"使用/打开"按钮统一走这里，返回 {"ok", "msg"}；加新数量型道具只需加个分支
func use_item(item_id: String, count: int) -> Dictionary:
	if count <= 0: return {"ok": false, "msg": "数量错误"}
	if items.get(item_id, 0) < count: return {"ok": false, "msg": "道具不足"}
	match item_id:
		"exp_box":
			items.exp_box -= count
			items.experience += 99999 * count
			return {"ok": true, "msg": "获得阅历 ×%d" % (99999 * count)}
		"hour_card":
			items.hour_card -= count
			var gain = get_total_auto_income() * 3600 * count
			money += gain
			return {"ok": true, "msg": "获得铜钱 ×%d" % gain}
		"reputation_card":
			items.reputation_card -= count
			reputation += 10 * count
			return {"ok": true, "msg": "声望 +%d" % (10 * count)}
		"reputation_card_adv":
			items.reputation_card_adv -= count
			reputation += 100 * count
			return {"ok": true, "msg": "声望 +%d" % (100 * count)}
		"recruit_bronze", "recruit_silver", "recruit_gold":
			# 募工牌：随机已解锁店铺店员 +1/3/5，不消耗铜钱
			if shops.is_empty(): return {"ok": false, "msg": "还没有已解锁的店铺"}
			var per_use = {"recruit_bronze": 1, "recruit_silver": 3, "recruit_gold": 5}[item_id]
			items[item_id] -= count
			var gains = {}
			for i in range(count):
				var keys = shops.keys()
				var sid = keys[randi() % keys.size()]
				shops[sid].staff += per_use
				gains[sid] = gains.get(sid, 0) + per_use
			var parts = []
			for sid in gains.keys():
				parts.append("【%s】店员+%d" % [shops[sid].name, gains[sid]])
			return {"ok": true, "msg": "、".join(parts)}
		"huo_qi", "ci_qi", "qiong_jiang", "cha_ye", "xuan_zhi":
			# 【新增】游历道具：每使用1个，随机一名对应职业门客基础赚速+500（逐个随机，可命中同一门客）
			var buff_category = {"huo_qi": "侠", "ci_qi": "商", "qiong_jiang": "工", "cha_ye": "农", "xuan_zhi": "士"}[item_id]
			var buff_pool = []
			for hid in heroes.keys():
				if heroes[hid].get("category", "") == buff_category:
					buff_pool.append(hid)
			if buff_pool.is_empty():
				return {"ok": false, "msg": "没有已拥有的%s类门客" % buff_category}
			items[item_id] -= count
			var buff_gains = {}
			for i in range(count):
				var hid = buff_pool[randi() % buff_pool.size()]
				heroes[hid].base_income += 500
				buff_gains[hid] = buff_gains.get(hid, 0) + 500
			var buff_parts = []
			for hid in buff_gains.keys():
				buff_parts.append("【%s】基础赚速+%d" % [heroes[hid].name, buff_gains[hid]])
			return {"ok": true, "msg": "、".join(buff_parts)}
		"random_book":
			# 【新增】随机书籍：每打开1个，从五种之道中随机获得一本
			items.random_book -= count
			var book_pool = ["shi_way", "nong_way", "gong_way", "shang_way", "xia_way"]
			var book_gains = {}
			for i in range(count):
				var bid = book_pool[randi() % book_pool.size()]
				items[bid] = items.get(bid, 0) + 1
				book_gains[bid] = book_gains.get(bid, 0) + 1
			var book_parts = []
			for bid in book_gains.keys():
				book_parts.append("【%s】×%d" % [ITEM_CONFIG[bid].name, book_gains[bid]])
			return {"ok": true, "msg": "获得：" + "、".join(book_parts)}
	return {"ok": false, "msg": "该道具不可使用"}

func get_beast_config(beast_id: String) -> Dictionary:
	return _beast_configs.get(beast_id, {}).duplicate(true)

func get_all_beast_ids() -> Array:
	return _beast_configs.keys()

func get_beast_instance(beast_id: String, index: int = 0):
	if not beasts.has(beast_id): return null
	var d = beasts[beast_id]
	if d is Array:
		if index >= 0 and index < d.size(): return d[index]
		return null
	return d

func get_beast_instance_count(beast_id: String) -> int:
	if not beasts.has(beast_id): return 0
	var d = beasts[beast_id]
	if d is Array: return d.size()
	return 1

func get_beast_aptitude(beast_id: String, instance_index: int = 0) -> int:
	var cfg = get_beast_config(beast_id)
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0
	var base = cfg.get("aptitude", 0)
	var lv = instance.get("level", 1)
	return base + (lv - 1) * 8

func get_beast_skill_bonus(beast_id: String, instance_index: int = 0) -> float:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return 0.0
	var skills = instance.get("skills", [])
	var total = 0.0
	for sk in skills:
		total += sk.get("percent", 0.0)
	return total

func get_beast_aura_bonus(beast_id: String, _instance_index: int = 0) -> float:
	var cfg = get_beast_config(beast_id)
	var auras = cfg.get("auras", [])
	if auras.is_empty(): return 0.0
	var special_count = _get_special_beast_count()
	var bonus = 0.10 + (special_count - 1) * 0.10
	bonus += 0.05
	return bonus

func _get_special_beast_count() -> int:
	var count = 0
	for bid in beasts.keys():
		if get_beast_config(bid).get("max_count", 1) == 1:
			count += 1
	return count

func get_hero_beast_bonus(hero_id: String) -> Dictionary:
	if not heroes.has(hero_id): return {"aptitude": 0, "percent": 0.0}
	var h = heroes[hero_id]
	var beast_id = h.get("equipped_beast", "")
	if beast_id == "": return {"aptitude": 0, "percent": 0.0}
	var idx = h.get("equipped_beast_index", 0)
	return {
		"aptitude": get_beast_aptitude(beast_id, idx),
		"percent": get_beast_skill_bonus(beast_id, idx) + get_beast_aura_bonus(beast_id, idx)
	}

func _init_beast_skills(count: int) -> Array:
	var skills = []
	for i in range(count):
		skills.append({"percent": 0.01, "refresh_count": 0})
	return skills

func add_beast(beast_id: String) -> bool:
	var cfg = get_beast_config(beast_id)
	if cfg.is_empty(): return false
	var max_count = cfg.get("max_count", 1)
	var init_data = {"level": 1, "equipped_hero": "", "skills": _init_beast_skills(cfg.get("skill_count", 0))}
	if max_count == 1:
		if beasts.has(beast_id): return false
		beasts[beast_id] = init_data
	else:
		if not beasts.has(beast_id): beasts[beast_id] = []
		beasts[beast_id].append(init_data)
	return true

func upgrade_beast(beast_id: String, instance_index: int = 0) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	if instance.level >= 200: return false
	if beast_fruit < 80: return false
	beast_fruit -= 80
	instance.level += 1
	return true

func refresh_beast_skill(beast_id: String, instance_index: int, skill_index: int, use_aroma: bool = false) -> bool:
	var instance = get_beast_instance(beast_id, instance_index)
	if instance == null: return false
	var skills = instance.get("skills", [])
	if skill_index < 0 or skill_index >= skills.size(): return false
	
	var skill = skills[skill_index]
	if skill.percent >= 0.249:  # 满级 25%，留一点浮点余量
		skill.percent = 0.25
		return false
	
	if use_aroma:
		# 奇香果刷新：固定消耗1个，15%-25%
		if aroma_fruit < 1: return false
		aroma_fruit -= 1
		skill.refresh_count += 1
		var new_val = randf_range(0.15, 0.251)
		if new_val > 0.25: new_val = 0.25
		skill.percent = max(skill.percent, new_val)
	else:
		# 铜钱刷新：指数增长费用
		var cost = 100 * int(pow(2, skill.refresh_count))
		if money < cost: return false
		money -= cost
		skill.refresh_count += 1
		
		var roll = randf()
		var new_val: float
		if roll < 0.9:
			new_val = randf_range(0.01, 0.149)
		else:
			new_val = randf_range(0.15, 0.251)
		
		if new_val > 0.25: new_val = 0.25
		skill.percent = max(skill.percent, new_val)
	
	# 接近满级直接封顶
	if skill.percent >= 0.245:
		skill.percent = 0.25
	
	return true

func equip_beast(hero_id: String, beast_id: String, instance_index: int) -> bool:
	if not heroes.has(hero_id): return false
	if not beasts.has(beast_id): return false
	
	# 【新增】先卸下当前门客的旧珍兽，并清空 beasts 中的标记
	var old_beast_id = heroes[hero_id].get("equipped_beast", "")
	var old_idx = heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	
	# 把新珍兽从其他门客身上卸下
	for hid in heroes.keys():
		if heroes[hid].get("equipped_beast", "") == beast_id and heroes[hid].get("equipped_beast_index", 0) == instance_index:
			heroes[hid].equipped_beast = ""
			heroes[hid].equipped_beast_index = 0
	
	# 【新增】设置 beasts 中新实例的 equipped_hero
	var new_inst = get_beast_instance(beast_id, instance_index)
	if new_inst != null:
		new_inst.equipped_hero = hero_id
	
	heroes[hero_id].equipped_beast = beast_id
	heroes[hero_id].equipped_beast_index = instance_index
	return true

func unequip_beast(hero_id: String) -> bool:
	if not heroes.has(hero_id): return false
	# 【新增】同步清空 beasts 中旧实例的 equipped_hero
	var old_beast_id = heroes[hero_id].get("equipped_beast", "")
	var old_idx = heroes[hero_id].get("equipped_beast_index", 0)
	if old_beast_id != "":
		var old_inst = get_beast_instance(old_beast_id, old_idx)
		if old_inst != null:
			old_inst.equipped_hero = ""
	heroes[hero_id].equipped_beast = ""
	heroes[hero_id].equipped_beast_index = 0
	return true

# 购买特惠礼包（自娱自乐版，直接成功）
func buy_special_pack(pack: Dictionary) -> bool:
	vip_exp += pack.cost * 10
	vip_level = get_vip_level()
	for item_id in pack.items.keys():
		items[item_id] = items.get(item_id, 0) + pack.items[item_id]
	return true

# 购买商城礼包（通用，加礼包只改上面的表）
func buy_mall_pack(pack: Dictionary) -> bool:
	if yuanbao < pack.cost: return false
	yuanbao -= pack.cost
	for item_id in pack.get("items", {}).keys():
		items[item_id] = items.get(item_id, 0) + pack.items[item_id]
	if pack.has("beast"):
		add_beast(pack.beast)
	beast_fruit += pack.get("beast_fruit", 0)
	aroma_fruit += pack.get("aroma_fruit", 0)
	return true


# 购买声望礼包：988元宝 → 高级声望卡×10 + 声望卡×100
func buy_reputation_pack() -> bool:
	if yuanbao < 988: return false
	yuanbao -= 988
	items.reputation_card_adv = items.get("reputation_card_adv", 0) + 10
	items.reputation_card = items.get("reputation_card", 0) + 100
	return true

func buy_test_beast_pack() -> bool:
	if yuanbao < 19888: return false
	yuanbao -= 19888
	add_beast("zou_yu")
	beast_fruit += 988
	aroma_fruit += 988
	return true

# 门客总赚钱（战力）= 所有门客 get_hero_income 之和
func get_heroes_total_income() -> int:
	var total = 0
	for hero_id in heroes.keys():
		total += get_hero_income(hero_id)
	return total

# ========== 关卡公式 ==========
func get_stage_trade_cost(main: int = stage_main, sub: int = stage_sub) -> int:
	return int(500 * pow(main, 3.2) * (1.0 + (sub - 1) * 0.2))

func get_stage_boss_income(main: int = stage_main) -> int:
	return int(50 * pow(main, 2.3))

func is_stage_boss_ready() -> bool:
	return stage_sub == 5 and stage_trade_count >= 3

# ========== 关卡操作 ==========
func do_stage_trade() -> Dictionary:
	var cost = get_stage_trade_cost()
	var boss_income = get_stage_boss_income()
	var hero_power = get_heroes_total_income()
	var discount = clamp(float(boss_income) / float(max(hero_power, 1)), 0.1, 1.0)
	var actual_cost = int(cost * discount)
	
	if money < actual_cost:
		return {"ok": false, "reason": "铜钱不足", "need": actual_cost, "have": money}
	
	money -= actual_cost
	reputation += 1
	stage_trade_count += 1
	
	# 每次贸易获得阅历（随章节递增，但不高）
	var exp_reward = 10 * stage_main
	items.experience += exp_reward
	
	# 达到3次，推进
	if stage_trade_count >= 3:
		items["stage_box"] = items.get("stage_box", 0) + 1
		
		if stage_sub < 5:
			stage_trade_count = 0      # 【改】只有进下小关才重置
			stage_sub += 1
			return {"ok": true, "type": "next_sub", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
		else:
			# 【改】Boss已出现，保持trade_count>=3，让is_stage_boss_ready能检测到
			return {"ok": true, "type": "boss_ready", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}
	
	return {"ok": true, "type": "trade", "actual_cost": actual_cost, "discount": discount, "exp_reward": exp_reward}

func do_stage_boss() -> Dictionary:
	var boss_income = get_stage_boss_income()
	var hero_power = get_heroes_total_income()
	
	if hero_power > boss_income:
		reputation += 10
		lottery_ticket += 1
		stage_main += 1
		stage_sub = 1
		stage_trade_count = 0
		return {"ok": true, "win": true, "boss_income": boss_income, "hero_power": hero_power}
	else:
		return {"ok": true, "win": false, "boss_income": boss_income, "hero_power": hero_power}

#钱庄升级
func upgrade_hq() -> bool:
	if items.hq_blueprint >= hq.upgrade_cost:
		items.hq_blueprint -= hq.upgrade_cost
		hq.level += 1
		hq.upgrade_cost = int(ceil(hq.upgrade_cost * 1.3))
		hq.click_income *= 1.5 
		return true
	return false
	
#店铺升级
func upgrade_shop(shop_id: String) -> bool:
	if shop_id == "": return false
	if not shops.has(shop_id): return false
	var s = shops[shop_id]
	if items.shop_blueprint >= s.upgrade_cost:
		items.shop_blueprint -= s.upgrade_cost
		s.level += 1
		s.upgrade_cost = int(ceil(s.upgrade_cost * 1.5))
		return true
	return false

#店铺招募
func hire_staff(shop_id: String) -> bool:
	if shop_id == "": return false
	if not shops.has(shop_id): return false
	var s = shops[shop_id]
	if money >= s.hire_cost:
		money -= s.hire_cost
		s.staff += 1
		s.hire_cost = int(ceil(s.hire_cost*1.01))
		return true
	return false

#门客升级
func upgrade_hero_level(hero_id: String, batch: bool = false) -> int:
	if not heroes.has(hero_id): return 0
	var hero = heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level >= max_level:
		return 0
	
	var exp_count = items.get("experience", 0)
	if exp_count <= 0: return 0
	
	var target = hero.level + (10 if batch else 1)
	target = min(target, max_level)  # 不能超过上限
	
	var total_cost = 0
	var levels = 0
	for lv in range(hero.level, target):
		var cost = int(ceil(100 * pow(1.05, lv)))
		if exp_count < total_cost + cost:
			break
		total_cost += cost
		levels += 1
	
	if levels > 0:
		items.experience -= total_cost
		hero.level += levels
		hero.base_income += levels * hero.breakthrough_count * hero.breakthrough_count * 100
		return levels
	return 0

#门客突破
func breakthrough_hero(hero_id: String) -> bool:
	if not heroes.has(hero_id): return false
	var hero = heroes[hero_id]
	var max_level = 50 + hero.breakthrough_count * 50
	if hero.level < max_level:
		return false  # 还没到突破节点
	
	var cost = hero.breakthrough_count * 10
	if not items.has("fengyasong") or items.fengyasong < cost:
		return false
	
	items.fengyasong -= cost
	hero.breakthrough_count += 1
	return true

#门客资质技能升级
func upgrade_hero_aptitude_skill(hero_id: String, skill_index: int) -> bool:
	if not heroes.has(hero_id): return false
	var skills = heroes[hero_id].aptitude_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	skill.level += 1
	return true

#门客店铺技能升级
func upgrade_hero_shop_skill(hero_id: String, skill_index: int, mode: String = "single") -> bool:
	if not heroes.has(hero_id): return false
	var skills = heroes[hero_id].shop_skills
	if skill_index < 0 or skill_index >= skills.size(): return false
	var skill = skills[skill_index]
	if skill.level >= skill.max_level: return false
	
	var abacus_count = items.get("abacus", 0)
	if abacus_count <= 0: return false
	
	if mode == "single":
		var cost = max(1, int(ceil(pow(1.05, skill.level - 1))))
		if abacus_count < cost: return false
		items.abacus -= cost
		skill.level += 1
		return true
	else:
		# 一键升满：能升多少升多少
		var remaining = skill.max_level - skill.level
		var upgraded = 0
		while upgraded < remaining:
			var cost = max(1, int(ceil(pow(1.05, skill.level + upgraded - 1))))
			if items.abacus < cost: break
			items.abacus -= cost
			upgraded += 1
		if upgraded > 0:
			skill.level += upgraded
			return true
		return false

# 门客晋升升级（通用，不绑定任何具体门客）
func upgrade_promotion(hero_id: String, batch: bool = false) -> int:
	if not heroes.has(hero_id): return 0
	var hero = heroes[hero_id]
	if not hero.has("promotion"): return 0
	var promo = hero.promotion
	if promo.level >= promo.max_level: return 0
	
	var cost = promo.cost_amount
	var max_item = items.get(promo.cost_item, 0)
	
	var max_times = 1
	if batch:
		max_times = min(promo.max_level - promo.level, int(max_item / cost))
	else:
		if max_item < cost: return 0
	
	if max_times <= 0: return 0
	
	var upgraded = 0
	for i in range(max_times):
		if promo.level >= promo.max_level: break
		if items.get(promo.cost_item, 0) < cost: break
		items[promo.cost_item] -= cost
		promo.level += 1
		upgraded += 1
		_check_promotion(hero)
	
	return upgraded

func _check_promotion(hero: Dictionary):
	if not hero.has("promotion"): return
	var promo = hero.promotion
	var lv = promo.level
	
	for tier in promo.tiers:
		if lv >= tier.threshold:
			if tier.has("quality"):
				hero.quality = tier.quality
			if tier.has("initial_aptitude"):
				hero.initial_aptitude = tier.initial_aptitude
			if tier.has("new_skills"):
				for new_skill in tier.new_skills:
					var has_it = false
					for sk in hero.aptitude_skills:
						if sk.name == new_skill.name:
							has_it = true
							break
					if not has_it:
						hero.aptitude_skills.append({
							"name": new_skill.name,
							"level": 0,
							"max_level": 200,
							"aptitude_per_level": new_skill.aptitude_per_level
						})


# 充值（自娱自乐版，直接成功）
func do_recharge(amount: int) -> bool:
	if amount <= 0: return false
	yuanbao += amount * 10
	vip_exp += amount * 10
	vip_level = get_vip_level()  # 根据经验重新计算等级
	return true

# ========== VIP 等级函数 ==========
func get_vip_level() -> int:
	for i in range(VIP_EXP_TABLE.size() - 1, -1, -1):
		if vip_exp >= VIP_EXP_TABLE[i]:
			return i
	return 0

func get_vip_next_level_exp() -> int:
	var current = get_vip_level()
	if current >= VIP_EXP_TABLE.size() - 1:
		return 0  # 已满级
	return VIP_EXP_TABLE[current + 1]

func get_vip_exp_progress() -> float:
	var current = get_vip_level()
	if current >= VIP_EXP_TABLE.size() - 1:
		return 1.0
	var current_exp = VIP_EXP_TABLE[current]
	var next_exp = VIP_EXP_TABLE[current + 1]
	var progress = float(vip_exp - current_exp) / float(next_exp - current_exp)
	return clamp(progress, 0.0, 1.0)

# 获取门客解锁所需VIP等级（初始门客返回0）
func get_hero_unlock_vip(hero_id: String) -> int:
	for level in _vip_rewards.keys():
		for reward in _vip_rewards[level]:
			if reward.type == "hero" and reward.id == hero_id:
				return int(level)
	return 0

# 获取挚友解锁所需VIP等级（初始挚友返回0）
func get_friend_unlock_vip(friend_id: String) -> int:
	for level in _vip_rewards.keys():
		for reward in _vip_rewards[level]:
			if reward.type == "friend" and reward.id == friend_id:
				return int(level)
	return 0

# 判断VIP奖励是否已领取
func is_vip_reward_claimed(level: int) -> bool:
	return vip_claimed_rewards.get(str(level), false)

# 手动领取VIP奖励
func claim_vip_reward(level: int) -> bool:
	if level <= 0: return false
	if get_vip_level() < level: return false
	if is_vip_reward_claimed(level): return false
	if not _vip_rewards.has(str(level)): return false   # 注意：JSON key 是字符串
	
	for reward in _vip_rewards[str(level)]:
		match reward.type:
			"hero": unlock_hero(reward.id)
			"friend": unlock_friend(reward.id)
	
	vip_claimed_rewards[str(level)] = true
	return true

# 门客帖兑换（门客/挚友统一消耗 hero_token）
func exchange_role_with_token(role_type: String, role_id: String, cost: int) -> Dictionary:
	if items.get("hero_token", 0) < cost:
		return {"ok": false, "reason": "门客帖不足"}
	var success = false
	if role_type == "hero":
		if heroes.has(role_id):
			return {"ok": false, "reason": "已拥有该门客"}
		success = unlock_hero(role_id)
	else:
		if friends.has(role_id):
			return {"ok": false, "reason": "已拥有该挚友"}
		success = unlock_friend(role_id)
	if not success:
		return {"ok": false, "reason": "兑换失败"}
	items.hero_token -= cost
	return {"ok": true}

# 跨天重置行善消耗次数
func _refresh_charity_daily():
	var today = Time.get_date_string_from_system()
	if charity_last_day != today:
		charity_last_day = today
		charity_click_count = 0

# 当前行善消耗：首次1万，每次×1.5，每天重置
func get_charity_cost() -> int:
	_refresh_charity_daily()
	return int(CHARITY_BASE_COST * pow(CHARITY_COST_MULT, charity_click_count))

# 某地点当前档所需次数：第1档2次，之后每档+1（2、3、4、5…）
func get_charity_tier_need(loc_id: String) -> int:
	var tier = charity_progress.get(loc_id, {}).get("tier", 0)
	return tier + 2

# 某职业的徒弟赚速加成池（每档+50）
# 注意：这是累计池，不直接加到徒弟身上，徒弟结业转职时才定格到自己身上
func get_charity_career_bonus(career: String) -> int:
	for loc in CHARITY_LOCATIONS:
		if loc.career == career:
			return charity_progress.get(loc.id, {}).get("tier", 0) * CHARITY_EFFECT_PER_TIER
	return 0

# 行善：扣铜钱 → 随机地点进度+1 → 发奖励；满档加成池+50，余数带进下一档
func do_charity() -> Dictionary:
	_refresh_charity_daily()
	var cost = get_charity_cost()
	if money < cost: return {"ok": false, "reason": "铜钱不足"}
	money -= cost
	charity_click_count += 1
	
	# 随机一个地点
	var loc = CHARITY_LOCATIONS[randi() % CHARITY_LOCATIONS.size()]
	var p = charity_progress.get(loc.id, {"progress": 0, "tier": 0})
	p.progress += 1
	var need = p.tier + 2
	var completed = false
	if p.progress >= need:
		p.progress -= need
		p.tier += 1
		completed = true
	charity_progress[loc.id] = p
	
	var rewards = []
	# 必定奖励1：才华1-2，加给随机一位已拥有挚友
	var talent_gain = randi_range(1, 2)
	if not friends.is_empty():
		var fkeys = friends.keys()
		var fid = fkeys[randi() % fkeys.size()]
		friends[fid].talent += talent_gain
		rewards.append("才华+%d（%s）" % [talent_gain, friends[fid].name])
	# 必定奖励2：对应该地点的"之道"×1
	items[loc.way_item] = items.get(loc.way_item, 0) + 1
	rewards.append(ITEM_CONFIG[loc.way_item].name + "×1")
	# 其他道具：90%随机1个，10%随机2个
	var pool = [
		{"item": "rouge", "weight": 30},
		{"item": "recruit_bronze", "weight": 30},
		{"item": "recruit_silver", "weight": 5},
		{"item": "recruit_gold", "weight": 3},
		{"item": "shop_blueprint", "weight": 30},
		{"item": "aptitude_pill", "weight": 2},
	]
	var total_w = 0
	for e in pool: total_w += e.weight
	var extra_count = 2 if randf() < 0.1 else 1
	for i in range(extra_count):
		var r = randi() % total_w
		for e in pool:
			if r < e.weight:
				items[e.item] = items.get(e.item, 0) + 1
				rewards.append(ITEM_CONFIG[e.item].name + "×1")
				break
			r -= e.weight
	
	return {"ok": true, "location": loc.name, "career": loc.career, "rewards": rewards,
		"completed": completed, "tier": p.tier, "cost": cost}

# ========== 存档 ==========
func save_game():
	@warning_ignore("narrowing_conversion")
	last_logout_time = Time.get_unix_time_from_system()
	var save_data = {
		"money": money,
		"items": items,
		"hq": hq,
		"shops": shops,
		"last_login_time": last_login_time,
		"last_logout_time": last_logout_time,
		"heroes": heroes,
		"energy": energy,
		"friends": friends,
		"vip_level": vip_level,
		"vip_exp": vip_exp,
		"yuanbao": yuanbao,
		"vip_claimed_rewards": vip_claimed_rewards,
		"stage_main": stage_main,
		"stage_sub": stage_sub,
		"stage_trade_count": stage_trade_count,
		"reputation": reputation,
		"lottery_ticket": lottery_ticket,
		"player_name": player_name,
		"identity_level": identity_level,
		"last_daily_reward_time": last_daily_reward_time,
		"beasts": beasts,
		"beast_fruit": beast_fruit,
		"aroma_fruit": aroma_fruit,
		"lottery_draw_count": lottery_draw_count,
		"identity_rewards_claimed": identity_rewards_claimed,
		"apprentices": apprentices,
		"apprentice_vigor": apprentice_vigor,
		"apprentice_vigor_time": apprentice_vigor_time,
		"graduated_apprentices": graduated_apprentices,
		"charity_progress": charity_progress,
		"charity_click_count": charity_click_count,
		"charity_last_day": charity_last_day,
		"stamina": stamina,                     # 【新增】游历体力
		"stamina_time": stamina_time,           # 【新增】体力恢复时间戳
		"friend_affection": friend_affection,   # 【新增】表2挚友好感进度
		"yuelao_count": yuelao_count,           # 【新增】月老祝福层数
		"guanyin_count": guanyin_count,         # 【新增】观音祝福层数
	}
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()
	

func load_game():
	#先加载配置再读档
	if _hero_configs.is_empty():_load_all_configs()
	
	randomize()
	if player_name == "":
		player_name = SURNAMES[randi() % SURNAMES.size()] + NAME_PARTS[randi() % NAME_PARTS.size()]
	
	if not FileAccess.file_exists(SAVE_PATH): return
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file: return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		file.close(); return
	var data = json.get_data()
	file.close()	

	if data.has("money"): money = data.money
	if data.has("items"): 
		items = data.items
		for item_id in ITEM_CONFIG.keys():
			if not items.has(item_id):
				items[item_id] = 0
	if data.has("hq"): hq = data.hq
	if _shop_configs.is_empty():
		_shop_configs = _load_json("res://data/shops.json")

	if data.has("shops"):
		var saved = data.shops
		shops.clear()
		for sid in saved.keys():
			if _shop_configs.has(sid):shops[sid] = saved[sid].duplicate(true)
	else:shops.clear()
	if data.has("last_login_time"): last_login_time = data.last_login_time
	if data.has("last_logout_time"): last_logout_time = data.last_logout_time
	if data.has("heroes"):
		# 只覆盖存档里有的门客（保留老进度）
		# 存档里没有的新门客，自动保持上面的初始值
		heroes = data.heroes.duplicate(true)
	if data.has("energy"): energy = data.energy
	if data.has("friends"): friends = data.friends
	if data.has("vip_level"): vip_level = data.vip_level
	if data.has("vip_exp"): vip_exp = data.vip_exp
	if data.has("yuanbao"): yuanbao = data.yuanbao
	if data.has("vip_claimed_rewards"):
		vip_claimed_rewards = data.vip_claimed_rewards
	# 加载配置表（如果还没加载）
	if _hero_configs.is_empty():_load_all_configs()
	if data.has("stage_main"): stage_main = data.stage_main
	if data.has("stage_sub"): stage_sub = data.stage_sub
	if data.has("stage_trade_count"): stage_trade_count = data.stage_trade_count
	if data.has("reputation"): reputation = data.reputation
	if data.has("lottery_ticket"): lottery_ticket = data.lottery_ticket
	if data.has("player_name"): player_name = data.player_name
	if data.has("identity_level"): identity_level = data.identity_level
	if data.has("last_daily_reward_time"): last_daily_reward_time = data.last_daily_reward_time
	
	if data.has("beasts"): 
		beasts = data.beasts
		# 兼容旧存档：给没有 refresh_count 的珍兽技能补上
		for bid in beasts.keys():
			var d = beasts[bid]
			var instances = d if d is Array else [d]
			for inst in instances:
				for sk in inst.get("skills", []):
					if not sk.has("refresh_count"):
						sk.refresh_count = 0
	if data.has("beast_fruit"): beast_fruit = data.beast_fruit
	if data.has("aroma_fruit"): aroma_fruit = data.aroma_fruit
	if data.has("lottery_draw_count"): lottery_draw_count = data.lottery_draw_count
	if data.has("identity_rewards_claimed"): identity_rewards_claimed = data.identity_rewards_claimed
	
	if data.has("apprentices"):
		apprentices = data.apprentices
		# 兼容旧存档：补齐到5个槽位
		while apprentices.size() < 5:
			apprentices.append(null)
		# 旧存档单人徒弟（字典）包成数组；已结业的移到结业列表
		for i in range(apprentices.size()):
			var entry = apprentices[i]
			if entry == null: continue
			if entry is Dictionary:
				entry = [entry]
			var remaining = []
			for a in entry:
				if a.get("state", "") in ["magician", "lover", "married"]:
					graduated_apprentices.append(a)
				else:
					remaining.append(a)
			if remaining.size() > 0:
				apprentices[i] = remaining
			else:
				apprentices[i] = null
	
	if data.has("charity_progress"): charity_progress = data.charity_progress
	if data.has("charity_click_count"): charity_click_count = data.charity_click_count
	if data.has("charity_last_day"): charity_last_day = data.charity_last_day
	
	# 【新增】游历系统存档读取（老存档没有这些字段则保持初始值）
	if data.has("stamina"): stamina = data.stamina
	if data.has("stamina_time"): stamina_time = data.stamina_time
	if data.has("friend_affection"): friend_affection = data.friend_affection
	if data.has("yuelao_count"): yuelao_count = data.yuelao_count
	if data.has("guanyin_count"): guanyin_count = data.guanyin_count
	
	# 清理存档中已不存在的角色（防止配置删了存档还残留）
	for hero_id in heroes.keys():
		if not _hero_configs.has(hero_id):
			heroes.erase(hero_id)
	for friend_id in friends.keys():
		if not _friend_configs.has(friend_id):
			friends.erase(friend_id)
	# 挚友店铺技能旧存档兼容
	for friend_id in friends.keys():
		if not friends[friend_id].has("shop_skills"):
			_init_friend_shop_skills(friend_id)

func _draw_from_pool() -> Dictionary:
	var r = randf()
	var cumulative = 0.0
	for entry in LOTTERY_POOL:
		cumulative += entry.weight
		if r <= cumulative:
			return entry.duplicate(true)
	# 未命中，给铜钱安慰奖
	return {"item": "money", "count": randi_range(1000, 10000)}

func _give_lottery_reward(reward: Dictionary):
	if reward.get("is_beast", false):
		add_beast(reward.item)
	elif reward.item == "money":
		money += reward.count
	else:
		items[reward.item] = items.get(reward.item, 0) + reward.count

func do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao_for_short: bool = false) -> Dictionary:
	var ticket_cost = min(ticket_need, lottery_ticket)
	var ticket_short = ticket_need - ticket_cost
	var yuanbao_cost = ticket_short * LOTTERY_TICKET_YUANBAO_RATE
	
	if use_yuanbao_for_short:
		if yuanbao < yuanbao_cost:
			return {"ok": false, "reason": "元宝不足"}
		yuanbao -= yuanbao_cost
		lottery_ticket -= ticket_cost
	else:
		if lottery_ticket < draw_count:
			return {"ok": false, "reason": "抽奖券不足"}
		lottery_ticket -= draw_count
	
	var results = []
	for i in range(draw_count):
		lottery_draw_count += 1
		var reward = null
		if lottery_draw_count >= LOTTERY_GUARANTEE:
			reward = {"item": "hero_token", "count": 1}
			lottery_draw_count = 0
		else:
			reward = _draw_from_pool()
		_give_lottery_reward(reward)
		results.append(reward)
	
	return {"ok": true, "results": results, "ticket_cost": ticket_cost, "yuanbao_cost": yuanbao_cost}

#计算离线收益
func calculate_offline_income() -> int:
	
	if last_logout_time <= 0 and last_login_time <= 0: return 0
	var now = Time.get_unix_time_from_system()
	var offline_seconds: int = 0
	
	if last_logout_time > last_login_time:
		# 上次正常退出过：用"上次退出 → 现在"这段时间
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - last_logout_time
		print("正常离线，时长：", offline_seconds, "秒")
	elif last_login_time > 0:
		# 闪退或强退：last_logout_time 没被更新，用"上次登录 → 现在"
		@warning_ignore("narrowing_conversion")
		offline_seconds = now - last_login_time
		print("检测到闪退，按上次在线时间计算，时长：", offline_seconds, "秒")
	
	# 限制最多24小时，防止数据爆炸
	offline_seconds = clamp(offline_seconds, 0, 86400)
	return int(get_total_auto_income() * offline_seconds * OFFLINE_RATE)
