extends SceneTree
# 扫描：Patrons 里哪个组件的 list 模板是 DestinyBeautyItem（即挚友页）

const DIR := "res://assets/fgui/"
const NAMES := ["ScrollPanel2", "TalentItem2", "SkinInfoItem", "spineNode", "BtnPromote1", "BtnPromote2", "AnimalsChangeItem", "MainItem", "ScrollPanel", "ContentPanel", "ContentItem", "Content", "ArrowItem", "TenUpgradeItem", "BtnFollowerTongChai", "BtnFollowerQXGY", "AnimalsItem1", "CricketItem", "CricketChangeItem", "BtnCookGod", "BtnApprenticeTTBL", "BtnQinHe", "QinHeSkillItem", "DestinyChooseItem", "FlowerFrameCom", "btnIdentityItem", "militaryRank", "JinLanSkillItem", "detailsTitleItem", "TokenSkillItem", "btnMuLan", "BtnJinLan", "JinLanLeft", "BtnJinLanAdd", "BtnJinLanRefresh", "ScrollPanel2Info", "BtnPractice", "combPracticePanel1", "btnSkin", "BgItem", "BtnMojin", "BloodSkillCom", "BloodSkillItem", "BtnBlood", "DestinyBeautyItem", "BtnEnShi", "touchItem", "BtnMyth", "GetWay", "BtnTalent", "BtnComb", "BtnBreak", "BtnUpgrade", "AnimalsItem", "AnimalsIconItem", "InfoSkillPanel", "TalentItem", "combPracticePanel", "combParcticeSkillPanel", "BtnFengkui", "BtnChange", "apprenticeSkillItem", "FishItem", "FishChangeItem", "teachSkillItem", "teachTitleItem2", "apprenticeTalentInfoItem1", "BtnTabTrueForm", "BtnDestiny", "GuardianItem", "BtnApprenticeLingXi", "BeautyHeadItem", "PracticePanel", "DestinyTechnologyItem", "BtnCopy", "BtnQifu", "SkillItem1", "upgradeItem", "BtnPractice1", "BtnMononoke", "DestinyBeautyContainer", "BreakingDevilPanel", "BtnQifu_1", "JinLanRight", "StagePatronSkillItem", "StageStarTxtItem", "StagePatronTalentItem", "tokenBg", "BtnXuYuan", "BtnQiYue", "apprenticeTalentItem", "apprenticeTalentInfoItem", "BtnTrueFormBack", "ApprenticeSelectItem", "BtnLiLian", "BtnApprenticeChange", "BtnGrace", "BtnRecruit", "BtnPatrons", "BtnFuZheng", "AnimalsItem3", "AnimalsIconItem", "TrueFormItem2", "btnOccupation", "BtnApprenticeTalent", "BtnGodly", "PromotionSuccess", "Promotion", "PromotionSkinInfo", "Acquire", "Animals", "AnimalsAlert", "AnimalsChange", "Break", "BreakSuccess", "Comb", "CombSuccess", "Main", "Stage", "StageSuccess", "Visit", "Introduce", "ZhenHuanTalent", "CricketChange", "CricketAlert", "BreakingDevilSkillItem", "TTBLEffectPopup", "TeachSkillUnlock", "Destiny", "IntroduceSkillItem", "QinHe", "QinHeChoose", "DestinyChoose", "Talent", "Identity", "JinLan", "JinLanChoose", "CombPracticeIntroduce", "Blood", "EnShiChoose", "Info", "SkillItem", "CombPractice", "CombPracticeSuccess", "CombPracticeChange", "FishChange", "TeachSkill", "TeachTitlePreview", "ApprenticeConvertSuccess", "PracticePreview", "Practice", "UpgradeSuccess", "BtnToken", "Token", "BreakingDevil", "StudyDownAni3", "Select", "ApprenticeTalent", "ApprenticeTalentRulePopup", "ApprenticeTalentInfoPopup", "ApprenticeSelect", "ApprenticeContentItem", "FishAlert", "ApprenticeChange", "Recruit", "TrueFormPromotionSuccess", "TrueForm", "BtnTrueForm"]

func _init() -> void:
	for n in ["Basic", "Basic2", "Basic3", "Items", "Patrons"]:
		if FGUIPackage.get_by_name(n) == null:
			FGUIPackage.add_package(DIR + n)
	var pkg: FGUIPackage = FGUIPackage.get_by_name("Patrons")
	for nm in NAMES:
		var o: FGUIObject = pkg.create_object(nm)
		if o == null:
			continue
		var c := o as FGUIComponent
		if c == null:
			continue
		var lst := c.get_child("list") as FGUIList
		if lst == null:
			continue
		lst.num_items = 1
		var cell: FGUIObject = lst.get_child_at(0)
		if cell == null:
			continue
		var cs: String = "?"
		if cell.get_script() != null:
			cs = cell.get_script().resource_path.get_file()
		var cc := cell as FGUIComponent
		var first := ""
		if cc != null and cc.num_children > 0:
			first = cc.get_child_at(0).name
		print("%s -> %s %sx%s first=%s" % [nm, cs, cell.width, cell.height, first])
		lst.num_items = 0
	quit()
