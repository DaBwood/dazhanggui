# ============================================================
# 《大掌柜》数据中枢（第2批重构版）
# 职责：全部状态变量 / 常量表 / 配置加载 / 存档读写 / 身份与每日奖励
#       + 持有11个子系统并转发其API（对外接口与旧版完全一致，controller零改动）
# ============================================================
class_name GameData
extends RefCounted


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
	{"name": "体力礼包", "desc": "体力丹×100 + 木梳×100 + 胭脂×100", "cost": 1988, "items": {"stamina_pill": 100, "wood_comb": 100, "rouge": 100}},
	
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
# 【新增】关卡宝箱掉落表：外置到 res://data/stage_box.json，启动时由 _load_stage_box_config() 加载
var STAGE_BOX_POOL: Array = []

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

# 已领取的VIP奖励等级（true=已领取）
var vip_claimed_rewards: Dictionary = {}

# ========== 关卡系统 ==========
var stage_main: int = 1

var stage_sub: int = 1

var stage_trade_count: int = 0

# 【新增】一键贸易开关：仅在线期间有效，不进存档（关掉游戏重开后默认关闭，需重新勾选）
var stage_auto_trade: bool = false
# 【新增】一键贸易停止原因：停止当下不弹提示，玩家点进关卡页时消费并弹出（不进存档）
var stage_auto_stop_reason: String = ""

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

#=========道具初始数量===========
# 【重构】由 _load_items_config() 按 items.json 的 initial 段填充；未列出的道具自动补0
var items: Dictionary = {}

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

# ========== 庄园状态（第4批新增；逻辑在 systems/manor_system.gd） ==========
var manor_plots: Dictionary = {}      # {品种id: [{"level":品种等级,"land":土地血统等级}×4]} 每块独立
var manor_goods: Dictionary = {}      # 庄园仓库 {产物名: 数量}（独立仓库，不进背包）
var manor_last_settle: int = 0        # 上次产量结算时间戳（在线懒结算用）

# ========== 商战状态（第5批新增；逻辑在 systems/war_system.gd） ==========
var war_tax_level: int = 1            # 税所等级（上限200）
var war_tax_accum: float = 0.0        # 税所已累积秒数（封顶500分钟）
var war_tax_last: int = 0             # 上次累积结算时间戳
var war_squads: Array = []            # 小队编队 [[hero_id×6]...]，空位为""
var war_last_battle: Dictionary = {}  # {小队序号: "YYYY-MM-DD"} 每队每天1战
var war_points: float = 0.0           # 商战积分（兑换商店货币）
var war_tax_yin: float = 0.0          # 商战税引（税所升级货币）
# ========== 挚友目标计数（第6批新增；逻辑在 systems/goal_system.gd） ==========
var goal_stats: Dictionary = {}   # {统计项: 累计值} recharge_done/war_kills/travel_count/hour_card_used/marry_count
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
# 【重构】const改var：数值由 travel.json 的 settings 段覆盖，这里保留默认值兜底
var STAMINA_MAX: int = 30                # 体力自动恢复上限（杜康事件可超上限）

var STAMINA_RECOVER_SECONDS: int = 1200  # 每20分钟恢复1点体力

var stamina: int = STAMINA_MAX         # 当前体力（游历消耗，1点/次）

var stamina_time: int = 0              # 上次体力恢复结算时间戳（懒结算用）

# ========== 【新增】游历系统（XLS表1：地点/物品/事件） ==========
# 【重构】const改var，travel.json 覆盖，默认值兜底
var TRAVEL_REPUTATION: int = 20          # 每次游历固定获得的声望

var TRAVEL_LOCATION_CHANCE: float = 0.5  # 抽到"地点"的概率

var TRAVEL_ITEM_CHANCE: float = 0.4      # 抽到"物品"的概率（其余10%为事件）

# 【重构新增】游历事件数值：原为硬编码，外置便于调节（travel.json settings）
var EV_CAI_SHEN_YUANBAO: int = 1000      # 财神到：元宝+N

var EV_DU_KANG_MIN: int = 1              # 杜康赠酒：体力+MIN~MAX

var EV_DU_KANG_MAX: int = 3

var EV_NEW_DISH_INCOME: int = 2000       # 今日新菜：基础赚速+N

# 游历地点表：id -> {name=显示名, friends=该地点可相遇挚友ID列表（含表2挚友）}
# 【重构】地点表外置到 res://data/travel.json，启动时由 _load_travel_config() 加载
var TRAVEL_LOCATIONS: Dictionary = {}

# 表2：好感解锁挚友（未拥有时游历相遇好感+1，达到要求即 unlock_friend 获得）
var TRAVEL_AFFECTION: Dictionary = {}

# 游历物品池：20项等概率，{item=道具ID, count=抽中后给N个}
# 注意：表格里的"许愿果"映射到现有许愿石 wish_stone；珍兽果/奇香果是独立货币，结算时加变量不加items
# 游历物品池：等概率，{"item"=道具ID, "count"=抽中后给N个}
var TRAVEL_ITEM_POOL: Array = []

# 未拥有表2挚友的好感进度（fid -> 好感值），达标获得后清除
var friend_affection: Dictionary = {}

# 月老/观音祝福层数：可一直累计，只有谈心真正领养到徒弟时才消耗
var yuelao_count: int = 0    # 月老：下次谈心（能领养时）对象改为当前友好最高的挚友

var guanyin_count: int = 0   # 观音：下次谈心（能领养时）必定双胞胎

# ===== 子系统实例（_init 中创建；纯逻辑模块，通过 g 共享本中枢状态） =====
var hero_system   # 门客系统
var friend_system   # 挚友系统
var apprentice_system   # 徒弟系统
var beast_system   # 珍兽系统
var shop_system   # 店铺系统（含钱庄）
var stage_system   # 关卡系统
var item_system   # 道具系统
var travel_system   # 游历系统
var charity_system   # 行善系统
var lottery_system   # 抽奖系统
var mall_system   # 商城/VIP系统
var manor_system   # 庄园系统（第4批新增）
var _manor_configs: Dictionary = {}   # 庄园配置（manor.json，由 _load_all_configs 加载）
var war_system   # 商战系统（第5批新增）
var _war_configs: Dictionary = {}   # 商战配置（war.json，由 _load_all_configs 加载）
var goal_system   # 挚友目标系统（第6批新增）
var _goal_configs: Dictionary = {}   # 挚友目标配置（goals.json，由 _load_all_configs 加载）
# ==================== 初始化 ====================
# 初始化：创建各子系统（纯逻辑模块，持有本中枢引用），再加载全部配置
func _init():
	hero_system = HeroSystem.new(self)
	friend_system = FriendSystem.new(self)
	apprentice_system = ApprenticeSystem.new(self)
	beast_system = BeastSystem.new(self)
	shop_system = ShopSystem.new(self)
	stage_system = StageSystem.new(self)
	item_system = ItemSystem.new(self)
	travel_system = TravelSystem.new(self)
	charity_system = CharitySystem.new(self)
	lottery_system = LotterySystem.new(self)
	mall_system = MallSystem.new(self)
	manor_system = ManorSystem.new(self)
	war_system = WarSystem.new(self)
	goal_system = GoalSystem.new(self)
	_load_all_configs()

# ==================== 配置加载 ====================

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

func _load_all_configs():
	_hero_configs = _load_json("res://data/heroes.json")
	_friend_configs = _load_json("res://data/friends.json")
	_vip_rewards = _load_json("res://data/vip_rewards.json")
	_shop_configs = _load_json("res://data/shops.json")
	_beast_configs = _load_json(BEAST_CONFIG_PATH)
	_manor_configs = _load_json("res://data/manor.json")   # 【第4批新增】庄园配置
	_war_configs = _load_json("res://data/war.json")   # 【第5批新增】商战配置
	_goal_configs = _load_json("res://data/goals.json")   # 【第6批新增】挚友目标配置
	_load_items_config()   # 【重构新增】道具表
	_load_travel_config()  # 【重构新增】游历配置
	_load_stage_box_config()  # 【新增】关卡宝箱掉落表
	

# 【第1批新增】加载 res://data/items.json：道具定义 + 新档初始数量（未列出的道具自动补0）
func _load_items_config():
	var d = _load_json("res://data/items.json")
	ITEM_CONFIG = d.get("config", {})
	items.clear()
	var init: Dictionary = d.get("initial", {})
	for item_id in ITEM_CONFIG.keys():
		# JSON读出的数字全是float，统一转int，避免计数和"%d"显示出错
		items[item_id] = int(init.get(item_id, 0))

# 【第1批新增】加载 res://data/travel.json：settings数值 + 地点表 + 表2好感表 + 物品池
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

# 【新增】加载 res://data/stage_box.json：关卡宝箱掉落表（item=道具id, count=数量, chance=概率权重）
func _load_stage_box_config():
	var d = _load_json("res://data/stage_box.json")
	STAGE_BOX_POOL = d.get("pool", [])

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

# ==================== 存档 ====================
# 保存游戏：核心字段 + 各子系统字段合并成同一张扁平表（键集合与旧版完全一致，老存档兼容）
func save_game():
	@warning_ignore("narrowing_conversion")
	last_logout_time = Time.get_unix_time_from_system()
	var save_data = {
		"money": money,
		"yuanbao": yuanbao,
		"reputation": reputation,
		"player_name": player_name,
		"identity_level": identity_level,
		"identity_rewards_claimed": identity_rewards_claimed,
		"last_daily_reward_time": last_daily_reward_time,
		"last_login_time": last_login_time,
		"last_logout_time": last_logout_time,
	}
	# 各子系统把自己的字段合并进来（新系统加存档字段只需改它自己的 get_save_data）
	var systems = [hero_system, friend_system, apprentice_system, beast_system, shop_system,
		stage_system, item_system, travel_system, charity_system, lottery_system, mall_system,
		manor_system,war_system,goal_system]
	for sys in systems:
		save_data.merge(sys.get_save_data(), true)
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(save_data))
		file.close()

# 读取存档：先加载配置，核心字段由本中枢读取，其余各子系统从同一张扁平表认领自己的字段
func load_game():
	#先加载配置再读档
	if _hero_configs.is_empty(): _load_all_configs()

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

	# ===== 核心字段（货币/声望/身份/时间戳） =====
	if data.has("money"): money = data.money
	if data.has("yuanbao"): yuanbao = data.yuanbao
	if data.has("reputation"): reputation = data.reputation
	if data.has("player_name"): player_name = data.player_name
	if data.has("identity_level"): identity_level = data.identity_level
	if data.has("identity_rewards_claimed"): identity_rewards_claimed = data.identity_rewards_claimed
	if data.has("last_daily_reward_time"): last_daily_reward_time = data.last_daily_reward_time
	if data.has("last_login_time"): last_login_time = data.last_login_time
	if data.has("last_logout_time"): last_logout_time = data.last_logout_time

	# ===== 各子系统认领自己的字段（含旧存档兼容逻辑） =====
	var systems = [hero_system, friend_system, apprentice_system, beast_system, shop_system,
		stage_system, item_system, travel_system, charity_system, lottery_system, mall_system,
		manor_system,war_system,goal_system]
	for sys in systems:
		sys.load_save_data(data)

# ==================== 子系统API转发区 ====================
# ==================== 【转发】门客系统 → systems/hero_system.gd ====================

func exchange_series_hero(hero_id: String, item_id: String, cost: int, friend_id: String = "") -> Dictionary:
	return hero_system.exchange_series_hero(hero_id, item_id, cost, friend_id)

func unlock_hero(hero_id: String) -> bool:
	return hero_system.unlock_hero(hero_id)

func get_hero_extra_income(hero_id: String) -> int:
	return hero_system.get_hero_extra_income(hero_id)

func get_hero_percent_bonus(hero_id: String) -> float:
	return hero_system.get_hero_percent_bonus(hero_id)

func get_hero_aptitude_bonus(hero_id: String) -> int:
	return hero_system.get_hero_aptitude_bonus(hero_id)

func get_hero_income(hero_id: String) -> int:
	return hero_system.get_hero_income(hero_id)

func get_hero_contribution(hero_id: String) -> int:
	return hero_system.get_hero_contribution(hero_id)

func get_heroes_total_income() -> int:
	return hero_system.get_heroes_total_income()

func upgrade_hero_level(hero_id: String, batch: bool = false) -> int:
	return hero_system.upgrade_hero_level(hero_id, batch)

func breakthrough_hero(hero_id: String) -> bool:
	return hero_system.breakthrough_hero(hero_id)

func upgrade_hero_aptitude_skill(hero_id: String, skill_index: int) -> bool:
	return hero_system.upgrade_hero_aptitude_skill(hero_id, skill_index)

func upgrade_hero_shop_skill(hero_id: String, skill_index: int, mode: String = "single") -> bool:
	return hero_system.upgrade_hero_shop_skill(hero_id, skill_index, mode)

func upgrade_promotion(hero_id: String, batch: bool = false) -> int:
	return hero_system.upgrade_promotion(hero_id, batch)

func _check_promotion(hero: Dictionary):
	hero_system._check_promotion(hero)


# ==================== 【转发】挚友系统 → systems/friend_system.gd ====================

func _get_highest_friendly_friend() -> String:
	return friend_system._get_highest_friendly_friend()

func _prepare_chat_adoption(default_friend_id: String) -> Dictionary:
	return friend_system._prepare_chat_adoption(default_friend_id)

func unlock_friend(friend_id: String) -> bool:
	return friend_system.unlock_friend(friend_id)

func _init_friend_shop_skills(friend_id: String):
	friend_system._init_friend_shop_skills(friend_id)

func get_friend_shop_skills(friend_id: String) -> Array:
	return friend_system.get_friend_shop_skills(friend_id)

func refresh_friend_shop_skill(friend_id: String, skill_index: int, use_wish_stone: bool = false) -> bool:
	return friend_system.refresh_friend_shop_skill(friend_id, skill_index, use_wish_stone)

func get_friend_hero_bonus(friend_id: String) -> int:
	return friend_system.get_friend_hero_bonus(friend_id)

func get_friend_fixed_bonus(friend_id: String) -> int:
	return friend_system.get_friend_fixed_bonus(friend_id)

func get_friend_percent_bonus(friend_id: String) -> float:
	return friend_system.get_friend_percent_bonus(friend_id)

func chat_with_friend(once: bool = true) -> Dictionary:
	return friend_system.chat_with_friend(once)

func chat_with_specific_friend(friend_id: String) -> Dictionary:
	return friend_system.chat_with_specific_friend(friend_id)

func upgrade_friend_fixed(friend_id: String) -> bool:
	return friend_system.upgrade_friend_fixed(friend_id)

func upgrade_friend_percent(friend_id: String) -> bool:
	return friend_system.upgrade_friend_percent(friend_id)

func gift_friend(friend_id: String, item_id: String) -> bool:
	return friend_system.gift_friend(friend_id, item_id)

func get_friend_title_index(friend_id: String) -> int:
	return friend_system.get_friend_title_index(friend_id)

func get_friend_title(friend_id: String) -> String:
	return friend_system.get_friend_title(friend_id)


# ==================== 【转发】徒弟系统 → systems/apprentice_system.gd ====================

func _has_empty_apprentice_slot() -> bool:
	return apprentice_system._has_empty_apprentice_slot()

func get_apprentice_slot_count() -> int:
	return apprentice_system.get_apprentice_slot_count()

func is_apprentice_slot_unlocked(slot: int) -> bool:
	return apprentice_system.is_apprentice_slot_unlocked(slot)

func _settle_slot_vigor(slot: int):
	apprentice_system._settle_slot_vigor(slot)

func get_slot_vigor(slot: int) -> int:
	return apprentice_system.get_slot_vigor(slot)

func adopt_apprentice(friend_id: String, force_twin: bool = false) -> int:
	return apprentice_system.adopt_apprentice(friend_id, force_twin)

func _create_apprentice(friend_id: String) -> Dictionary:
	return apprentice_system._create_apprentice(friend_id)

func _get_single_apprentice_income(a: Dictionary) -> int:
	return apprentice_system._get_single_apprentice_income(a)

func get_apprentice_income(slot: int) -> int:
	return apprentice_system.get_apprentice_income(slot)

func get_graduated_income(index: int) -> int:
	return apprentice_system.get_graduated_income(index)

func train_apprentice(slot: int) -> Dictionary:
	return apprentice_system.train_apprentice(slot)

func train_apprentice_batch(slot: int) -> Dictionary:
	return apprentice_system.train_apprentice_batch(slot)

func use_vitality_pill(slot: int, count: int) -> bool:
	return apprentice_system.use_vitality_pill(slot, count)

func graduate_apprentice_one(slot: int, path: String) -> bool:
	return apprentice_system.graduate_apprentice_one(slot, path)

func generate_spouse(index: int) -> Dictionary:
	return apprentice_system.generate_spouse(index)

func marry_apprentice(index: int, spouse: Dictionary) -> bool:
	return apprentice_system.marry_apprentice(index, spouse)


# ==================== 【转发】珍兽系统 → systems/beast_system.gd ====================

func get_beast_config(beast_id: String) -> Dictionary:
	return beast_system.get_beast_config(beast_id)

func get_all_beast_ids() -> Array:
	return beast_system.get_all_beast_ids()

func get_beast_instance(beast_id: String, index: int = 0):
	return beast_system.get_beast_instance(beast_id, index)

func get_beast_instance_count(beast_id: String) -> int:
	return beast_system.get_beast_instance_count(beast_id)

func get_beast_aptitude(beast_id: String, instance_index: int = 0) -> int:
	return beast_system.get_beast_aptitude(beast_id, instance_index)

func get_beast_skill_bonus(beast_id: String, instance_index: int = 0) -> float:
	return beast_system.get_beast_skill_bonus(beast_id, instance_index)

func get_beast_aura_bonus(beast_id: String, _instance_index: int = 0) -> float:
	return beast_system.get_beast_aura_bonus(beast_id, _instance_index)

func _get_special_beast_count() -> int:
	return beast_system._get_special_beast_count()

func get_hero_beast_bonus(hero_id: String) -> Dictionary:
	return beast_system.get_hero_beast_bonus(hero_id)

func _init_beast_skills(count: int) -> Array:
	return beast_system._init_beast_skills(count)

func add_beast(beast_id: String) -> bool:
	return beast_system.add_beast(beast_id)

func upgrade_beast(beast_id: String, instance_index: int = 0) -> bool:
	return beast_system.upgrade_beast(beast_id, instance_index)

func refresh_beast_skill(beast_id: String, instance_index: int, skill_index: int, use_aroma: bool = false) -> bool:
	return beast_system.refresh_beast_skill(beast_id, instance_index, skill_index, use_aroma)

func equip_beast(hero_id: String, beast_id: String, instance_index: int) -> bool:
	return beast_system.equip_beast(hero_id, beast_id, instance_index)

func unequip_beast(hero_id: String) -> bool:
	return beast_system.unequip_beast(hero_id)


# ==================== 【转发】店铺系统（含钱庄） → systems/shop_system.gd ====================

func get_shop_config(shop_id: String) -> Dictionary:
	return shop_system.get_shop_config(shop_id)

func get_shop_unlock_chapter(shop_id: String) -> int:
	return shop_system.get_shop_unlock_chapter(shop_id)

func can_unlock_shop(shop_id: String) -> bool:
	return shop_system.can_unlock_shop(shop_id)

func unlock_shop(shop_id: String) -> bool:
	return shop_system.unlock_shop(shop_id)

func get_hq_auto_income() -> int:
	return shop_system.get_hq_auto_income()

func get_global_bonus_percent() -> float:
	return shop_system.get_global_bonus_percent()

func get_shop_auto_income(shop_id: String) -> int:
	return shop_system.get_shop_auto_income(shop_id)

func get_total_auto_income() -> int:
	return shop_system.get_total_auto_income()

func upgrade_hq() -> bool:
	return shop_system.upgrade_hq()

func upgrade_shop(shop_id: String) -> bool:
	return shop_system.upgrade_shop(shop_id)

func hire_staff(shop_id: String) -> bool:
	return shop_system.hire_staff(shop_id)

func calculate_offline_income() -> int:
	return shop_system.calculate_offline_income()


# ==================== 【转发】关卡系统 → systems/stage_system.gd ====================

func get_stage_trade_cost(main: int = -1, sub: int = -1) -> int:
	return stage_system.get_stage_trade_cost(main, sub)

func get_stage_boss_income(main: int = -1) -> int:
	return stage_system.get_stage_boss_income(main)

func is_stage_boss_ready() -> bool:
	return stage_system.is_stage_boss_ready()

func do_stage_trade() -> Dictionary:
	return stage_system.do_stage_trade()

func do_stage_boss() -> Dictionary:
	return stage_system.do_stage_boss()

# 【新增】一键贸易节拍：转发到 StageSystem.auto_trade_tick（每秒一次，返回事件供 controller 提示）
func stage_auto_trade_tick() -> Dictionary:
	return stage_system.auto_trade_tick()

# ==================== 【转发】道具系统 → systems/item_system.gd ====================

func use_item(item_id: String, count: int) -> Dictionary:
	return item_system.use_item(item_id, count)

func exchange_role_with_token(role_type: String, role_id: String, cost: int) -> Dictionary:
	return item_system.exchange_role_with_token(role_type, role_id, cost)


# ==================== 【转发】游历系统 → systems/travel_system.gd ====================

func _settle_stamina():
	travel_system._settle_stamina()

func get_stamina() -> int:
	return travel_system.get_stamina()

func do_travel() -> Dictionary:
	return travel_system.do_travel()

# 【新增】一键游历：转发到 TravelSystem.do_travel_all（消耗当前全部体力，返回结构化汇总）
func do_travel_all() -> Dictionary:
	return travel_system.do_travel_all()

func _do_travel_location() -> Dictionary:
	return travel_system._do_travel_location()

func _do_travel_item() -> Dictionary:
	return travel_system._do_travel_item()

func _do_travel_event() -> Dictionary:
	return travel_system._do_travel_event()


# ==================== 【转发】行善系统 → systems/charity_system.gd ====================

func _refresh_charity_daily():
	charity_system._refresh_charity_daily()

func get_charity_cost() -> int:
	return charity_system.get_charity_cost()

func get_charity_tier_need(loc_id: String) -> int:
	return charity_system.get_charity_tier_need(loc_id)

func get_charity_career_bonus(career: String) -> int:
	return charity_system.get_charity_career_bonus(career)

func do_charity() -> Dictionary:
	return charity_system.do_charity()


# ==================== 【转发】抽奖系统 → systems/lottery_system.gd ====================

func _draw_from_pool() -> Dictionary:
	return lottery_system._draw_from_pool()

func _give_lottery_reward(reward: Dictionary):
	lottery_system._give_lottery_reward(reward)

func do_lottery_draw(draw_count: int, ticket_need: int, use_yuanbao_for_short: bool = false) -> Dictionary:
	return lottery_system.do_lottery_draw(draw_count, ticket_need, use_yuanbao_for_short)


# ==================== 【转发】商城/VIP系统 → systems/mall_system.gd ====================

func buy_special_pack(pack: Dictionary) -> bool:
	return mall_system.buy_special_pack(pack)

func buy_mall_pack(pack: Dictionary) -> bool:
	return mall_system.buy_mall_pack(pack)

func buy_reputation_pack() -> bool:
	return mall_system.buy_reputation_pack()

func buy_test_beast_pack() -> bool:
	return mall_system.buy_test_beast_pack()

func do_recharge(amount: int) -> bool:
	return mall_system.do_recharge(amount)

func get_vip_level() -> int:
	return mall_system.get_vip_level()

func get_vip_next_level_exp() -> int:
	return mall_system.get_vip_next_level_exp()

func get_vip_exp_progress() -> float:
	return mall_system.get_vip_exp_progress()

func get_hero_unlock_vip(hero_id: String) -> int:
	return mall_system.get_hero_unlock_vip(hero_id)

func get_friend_unlock_vip(friend_id: String) -> int:
	return mall_system.get_friend_unlock_vip(friend_id)

func is_vip_reward_claimed(level: int) -> bool:
	return mall_system.is_vip_reward_claimed(level)

func claim_vip_reward(level: int) -> bool:
	return mall_system.claim_vip_reward(level)

# ==================== 【转发】庄园系统 → systems/manor_system.gd ====================

# 品种表（kind = "crops" 农场 / "animals" 牧场）
func get_manor_species_list(kind: String):
	return manor_system.get_species_list(kind)

# 品种是否已解锁（身份等级驱动）
func is_manor_species_unlocked(species_id: String):
	return manor_system.is_species_unlocked(species_id)

# 某品种已解锁的地/圈数量（0~4）
func get_manor_unlocked_plots(species_id: String):
	return manor_system.get_unlocked_plot_count(species_id)

# 第N块解锁所需身份等级
func get_manor_plot_need_identity(species_id: String, plot_index: int):
	return manor_system.get_plot_need_identity(species_id, plot_index)

# 每品种的地/圈数量（配置驱动，当前为4）
func get_manor_plots_per_species():
	return manor_system.get_plots_per_species()

# 某一块的数据 {"level": 品种等级, "land": 土地/血统等级}
func get_manor_plot(species_id: String, plot_index: int):
	return manor_system.get_plot(species_id, plot_index)

# 品种等级上限 = 土地/血统等级 × 50
func get_manor_plot_level_cap(land_level: int):
	return manor_system.get_plot_level_cap(land_level)

# 单块产量/分钟 = (60+品种等级-1) × (1+土地血统×25%)
func get_manor_plot_rate(species_id: String, plot_index: int):
	return manor_system.get_plot_rate(species_id, plot_index)

# 品种总产量/分钟（已解锁地块之和）
func get_manor_species_rate(species_id: String):
	return manor_system.get_species_rate(species_id)

# 品种升级铜钱费用 = 5000×当前等级²
func get_manor_level_up_cost(cur_level: int):
	return manor_system.get_level_up_cost(cur_level)

# 土地/血统升级图纸费用（前5次20张，之后+5/+10/+15循环）
func get_manor_land_up_cost(cur_land: int):
	return manor_system.get_land_up_cost(cur_land)

# 升级某块品种等级（耗铜钱）
func upgrade_manor_plot_level(species_id: String, plot_index: int):
	return manor_system.upgrade_plot_level(species_id, plot_index)

# 升级某块土地/血统（耗商铺图纸）
func upgrade_manor_plot_land(species_id: String, plot_index: int):
	return manor_system.upgrade_plot_land(species_id, plot_index)

# 仓库产物数量
func get_manor_goods_count(product: String):
	return manor_system.get_goods_count(product)

# 在线懒结算（每秒调用）
func settle_manor():
	return manor_system.settle()

# 离线结算（登录时调用，须在更新 last_login_time 之前）
func settle_manor_offline():
	return manor_system.settle_offline()

# 连升某块品种等级（勾选"等级十连"时调用；逐次结算，失败即停）
func upgrade_manor_plot_level_batch(species_id: String, plot_index: int, times: int = 10):
	return manor_system.upgrade_plot_level_batch(species_id, plot_index, times)

# ==================== 【转发】商战系统 → systems/war_system.gd ====================

# 税所加成倍数（1 + 1.58×((等级-1)/98)^1.5）
func get_war_tax_multiplier():
	return war_system.get_tax_multiplier()

# 税所累积上限（分钟）
func get_war_tax_cap_minutes():
	return war_system.get_tax_cap_minutes()

# 税所升级消耗税引（10×当前等级²）
func get_war_tax_up_cost():
	return war_system.get_tax_up_cost()

# 已累积挂机时间（分钟）
func get_war_tax_accum_minutes():
	return war_system.get_tax_accum_minutes()

# 当前可领取金额
func get_war_tax_pending_income():
	return war_system.get_tax_pending_income()

# 领取税所收益
func claim_war_tax():
	return war_system.claim_tax()

# 升级税所（耗商战税引）
func upgrade_war_tax():
	return war_system.upgrade_tax()

# 小队数量上限（门客总数÷6）
func get_war_max_squads():
	return war_system.get_max_squads()

# 某小队编队数据（6格，空位""）
func get_war_squad(squad_index: int):
	return war_system.get_squad(squad_index)

# 门客所在小队（-1=未编队）
func get_war_hero_squad(hero_id: String):
	return war_system.get_hero_squad(hero_id)

# 编入门客到某队某格
func assign_war_hero(squad_index: int, slot: int, hero_id: String):
	return war_system.assign_hero(squad_index, slot, hero_id)

# 移出某队某格门客
func remove_war_hero(squad_index: int, slot: int):
	return war_system.remove_hero(squad_index, slot)

# 小队战力（队内门客赚速之和）
func get_war_squad_power(squad_index: int):
	return war_system.get_squad_power(squad_index)

# 今日是否可出战
func can_war_battle(squad_index: int):
	return war_system.can_battle(squad_index)

# 出战（NPC商队定胜负，胜全奖/负30%）
func war_battle(squad_index: int):
	return war_system.battle(squad_index)

# 兑换商店表
func get_war_exchange_list():
	return war_system.get_exchange_list()

# 商战积分兑换道具
func war_exchange(item_id: String):
	return war_system.exchange_item(item_id)

# 已拥有门客 id 列表（组队选择器用）
func get_war_hero_list():
	return war_system.get_hero_list()

# 门客显示名（组队选择器用）
func get_war_hero_name(hero_id: String):
	return war_system.get_hero_name(hero_id)

# ==================== 【转发】挚友目标系统 → systems/goal_system.gd ====================

# 挚友目标表
func get_friend_goal_list():
	return goal_system.get_goal_list()

# 单个目标是否达成
func is_friend_goal_done(goal: Dictionary):
	return goal_system.is_goal_done(goal)

# 某目标当前进度值
func get_friend_goal_progress(goal: Dictionary):
	return goal_system.get_stat(goal.get("stat", ""))


# 挚友显示名（查 friends.json，兜底返回 id）
func get_goal_friend_name(friend_id: String) -> String:
	return goal_system.get_friend_name(friend_id)

# 全部目标是否达成（府邸目标区隐藏依据）
func all_friend_goals_done():
	return goal_system.all_goals_done()

# 检查并自动解锁已达成挚友，返回新解锁名字列表（供弹窗）
func check_friend_goals():
	return goal_system.check_goals()

# 某目标统计项当前值（首充特判在系统内处理）
func get_friend_goal_stat(stat: String) -> int:
	return goal_system.get_stat(stat)
