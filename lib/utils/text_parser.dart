/// 智能文本解析引擎：将自然语言描述提取为结构化记账数据。
///
/// 核心策略：多模式金额提取 + 语义优先级排序 + 否定过滤 + 上下文关联
class TextParser {
  // ==================== 金额提取正则（按优先级降序排列）====================

  /// 模式1: 人均/AA/分摊/平摊 后的金额（最高优先级）
  /// 例："总共200，人均50"、"AA各付60"、"平摊下来每人45"
  static final RegExp _perCapitaPattern = RegExp(
    r'(?:人均|AA|各付|平摊|分摊)\s*(?:各付|下来|每人|每个人|每人)?\s*(?:了)?\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:块|元|块钱|元钱|￥|¥)?',
    caseSensitive: false,
  );

  /// 模式2: 垫付/实际支付/实付/自付 后的金额
  /// 例："垫付了186"、"实际支付128元"
  static final RegExp _actualPayPattern = RegExp(
    r'(?:垫付|实际支付|实付|自己付|自付)\s*(?:了)?\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:块|元|块钱|元钱|￥|¥)?',
    caseSensitive: false,
  );

  /// 模式3: 花了/用了/支出/支付/付了/消费/缴纳/交 等动词后的金额
  /// 例："花了35块"、"交话费100"
  static final RegExp _verbPayPattern = RegExp(
    r'(?:花了|用了|支出|支付|付了|消费|缴纳|交|买|付)\s*(?:了)?\s*[:：]?\s*(\d+(?:\.\d+)?)\s*(?:块|元|块钱|元钱|￥|¥)?',
    caseSensitive: false,
  );

  /// 模式4: 收入动词后的金额
  /// 例："收到工资8500"、"红包200"
  static final RegExp _verbIncomePattern = RegExp(
    r'(?:收到|到账|领了|获得|发了)\s*(?:了)?\s*[:：]?\s*(?:工资|红包|奖金|补贴|退款)?\s*(\d+(?:\.\d+)?)\s*(?:块|元|块钱|元钱|￥|¥)?',
    caseSensitive: false,
  );

  /// 模式5: 数字紧跟中文货币单位
  /// 例："35块"、"128元"、"50块钱"
  static final RegExp _currencyPattern = RegExp(
    r'(\d+(?:\.\d+)?)\s*(?:块|元|块钱|元钱|￥|¥)',
  );

  /// 模式6: 纯数字兜底（最低优先级）
  /// 例："打车26"
  static final RegExp _numberPattern = RegExp(r'(\d+(?:\.\d+)?)');

  // ==================== 否定/排除过滤 ====================

  /// 金额前出现否定词，则该金额无效
  /// 例："不是35块"、"没花50"、"不要128的"
  static final RegExp _negativePattern = RegExp(
    r'(?:不是|并非|没|没有|未|别|不要|不用|无需|不必|不算)\s*.{0,8}?(\d+(?:\.\d+)?)',
  );

  // ==================== 收支类型判断 ====================

  /// 收入关键词（按匹配强度分组）
  static final List<_KeywordRule> _incomeRules = [
    // 强收入信号
    _KeywordRule(RegExp(r'工资|薪水|月薪|年薪|底薪|绩效|年终奖|十三薪'), '工资'),
    _KeywordRule(RegExp(r'红包|压岁钱|份子钱|随礼'), '礼金'),
    _KeywordRule(RegExp(r'退款|退货|返现|返款|退回'), '其他'),
    _KeywordRule(RegExp(r'兼职|副业|临时工|代驾|跑腿|众包|接单'), '兼职'),
    _KeywordRule(RegExp(r'投资|理财|基金|股票|债券|期货|黄金|利息|收益|分红|股息|盈利|赢利'), '投资'),
    _KeywordRule(RegExp(r'收到|到账|转入|转来|拨款|汇款|转账给我|卖.*钱|变现'), '其他'),
    _KeywordRule(RegExp(r'奖金|提成|分红|年终奖|绩效奖|全勤奖|项目奖|销售奖'), '工资'),
    _KeywordRule(RegExp(r'报销|差旅报销|发票报销'), '工资'),
    _KeywordRule(RegExp(r'养老金|退休金|失业金|公积金提取|医保返款'), '工资'),
    _KeywordRule(RegExp(r'津贴|补助|补贴|租房补贴|交通补贴|餐补|话补'), '工资'),
    _KeywordRule(RegExp(r'奖学金|助学金|助学贷款'), '礼金'),
  ];

  /// 支出关键词
  static final List<_KeywordRule> _expenseRules = [
    _KeywordRule(RegExp(r'花了|支出|消费|支付|付了|用了|缴纳|交|花|付\b'), '其他'),
    _KeywordRule(RegExp(r'垫付|代付|请客|请客吃饭|请客唱歌|请客喝酒'), '餐饮'),
    _KeywordRule(RegExp(r'捐赠|捐款|捐钱|慈善'), '其他'),
    _KeywordRule(RegExp(r'还贷|还款|还花呗|还信用卡|还白条|还贷款'), '住房'),
    _KeywordRule(RegExp(r'买|购买|采购|购置|入手|下单'), '购物'),
  ];

  // ==================== 分类映射（支出）====================

  static final Map<String, List<String>> _expenseCategoryKeywords = {
    '餐饮': [
      '饭', '吃', '外卖', '餐厅', '饭店', '食堂', '火锅', '烧烤', '烤肉', '串串',
      '奶茶', '咖啡', '星巴克', '瑞幸', '喜茶', '奈雪', '蜜雪', 'coco', '茶百道',
      '早餐', '午餐', '晚餐', '夜宵', '宵夜', '零食', '水果', '买菜', '食材',
      '大餐', '聚餐', '请客吃饭', '下馆子', '面馆', '快餐', '汉堡', '披萨',
      '寿司', '日料', '西餐', '中餐', '川菜', '湘菜', '粤菜', '东北菜', '拉面',
      '甜品', '面包', '蛋糕', '糕点', '点心', '饮料', '酒水', '啤酒', '白酒',
      '红酒', '鸡尾酒', '奶茶', '果汁', '豆浆', '牛奶', '酸奶',
      '螺蛳粉', '麻辣烫', '煎饼', '包子', '饺子', '馄饨', '粥',
    ],
    '交通': [
      '打车', '滴滴', '花小猪', '高德打车', 't3', '曹操', '首汽',
      '地铁', '公交', '公交车', 'brt', '轻轨', '有轨电车',
      '油费', '加油', '油价', '充电', '电费', '停车费', '车位',
      '过路费', '高速费', '路桥费', 'etc', '收费站',
      '高铁', '动车', '火车', '绿皮', '卧铺',
      '飞机', '机票', '航班', '航空', '机场',
      '车票', '船票', '轮渡', '索道',
      '共享单车', '共享电单车', '美团单车', '哈啰', '青桔',
      '网约车', '专车', '快车', '顺风车', '出租', '的士', '出租车',
      '摩的', '电动车', '电瓶车', '摩托车', '班车', '通勤车',
      '地铁卡', '交通卡', '公交卡', '一卡通',
      '保养', '维修', '洗车', '美容', '贴膜', '轮胎', '保险', '年检',
    ],
    '购物': [
      '衣服', '服装', 't恤', '衬衫', '裤子', '裙子', '外套', '羽绒服', '西装',
      '鞋子', '运动鞋', '皮鞋', '靴子', '凉鞋', '拖鞋', '高跟鞋',
      '包包', '背包', '手提包', '钱包', '挎包', '行李箱',
      '化妆品', '护肤品', '口红', '面膜', '粉底', '眼影', '香水',
      '日用品', '生活用品', '洗护', '洗发水', '沐浴露', '牙膏', '牙刷',
      '纸巾', '湿巾', '卫生纸', '卫生巾', '化妆棉', '棉签',
      '淘宝', '京东', '拼多多', '抖音商城', '小红书', '唯品会', '得物',
      '网购', '网拍', '直播带货', '代购', '海淘',
      '数码', '手机', '电脑', '笔记本', '平板', '耳机', '音箱', '键盘', '鼠标',
      '配件', '充电器', '数据线', '充电宝', '手机壳', '贴膜',
      '饰品', '首饰', '项链', '手链', '戒指', '耳环', '手表',
      '眼镜', '墨镜', '隐形眼镜', '美瞳', '配镜',
      '文具', '笔', '本子', '便签', '文件夹', '订书机',
      '超市', '便利店', '711', '全家', '罗森', '美宜佳', ' Walmart', 'costco',
    ],
    '住房': [
      '房租', '租金', '月租', '季租', '年租', '押一付三',
      '房贷', '月供', '首付', '按揭', '公积金贷款', '商业贷款',
      '物业费', '管理费', '小区物业费',
      '水电', '水费', '电费', '燃气费', '煤气费', '天然气',
      '宽带', '网费', 'wifi', '路由器', '光纤',
      '装修', '装潢', '改造', '翻新', '刷墙', '铺地板', '吊顶',
      '家具', '沙发', '床', '床垫', '桌子', '椅子', '衣柜', '书架', '鞋柜',
      '家电', '冰箱', '洗衣机', '空调', '电视', '热水器', '微波炉', '烤箱',
      '取暖费', '暖气费', '空调费',
      '维修', '修理', '水管', '电路', '门锁', '窗户',
    ],
    '娱乐': [
      '电影', '电影票', 'imax', '杜比', '观影', '电影院', '万达影城',
      'ktv', '唱歌', '歌厅', '卡拉ok',
      '游戏', '网游', '手游', 'steam', 'switch', 'ps5', 'xbox',
      '会员', '视频会员', '音乐会员', 'qq音乐', '网易云', '酷狗', '酷我',
      'spotify', 'apple music', 'youtube', 'b站', '哔哩哔哩', '大会员',
      '演唱会', '音乐节', 'livehouse', '话剧', '舞台剧', '音乐剧', '脱口秀',
      '旅游', '旅行', '出游', '度假', '酒店', '民宿', '青旅', '客栈',
      '门票', '景区门票', '游乐园', '迪士尼', '环球影城', '欢乐谷', '方特',
      '剧本杀', '密室逃脱', '桌游', '狼人杀', 'uno',
      '台球', '桌球', '网吧', '网咖', '电竞馆',
      '酒吧', '清吧', '夜店', '蹦迪',
      '棋牌', '麻将', '扑克', '象棋', '围棋',
      '钓鱼', '摄影', '滑雪', '游泳', '健身', '运动',
      '打球', '篮球', '足球', '羽毛球', '乒乓球', '网球', '排球',
      '足疗', '按摩', 'spa', '采耳', '泡澡', '桑拿',
      '追剧', '综艺', '动漫', '漫画', '小说', '阅读',
    ],
    '医疗': [
      '医院', '看病', '就诊', '门诊', '急诊', '住院', '病房',
      '药', '药品', '西药', '中药', '中成药', '处方药', '非处方药', 'otc',
      '体检', '健康检查', '入职体检', '年度体检',
      '挂号', '挂号费', '专家号', '特需号',
      '诊所', '牙科', '牙医', '拔牙', '补牙', '洗牙', '矫正', '种牙',
      '眼科', '配镜', '验光', '隐形眼镜', '近视手术',
      '保健品', '维生素', '钙片', '蛋白粉', '鱼油', '益生菌',
      '口罩', '创可贴', '消毒液', '酒精', '体温计', '血压计',
      '医疗费', '治疗费', '检查费', '化验费', '检验费', '医药费',
      '手术费', '护理费', '床位费', '材料费',
      '医保', '社保', '报销', '统筹',
      '产检', '分娩', '疫苗', '打针', '输液', '点滴',
    ],
    '教育': [
      '学费', '学杂费', '书本费', '教材费', '资料费',
      '书', '教材', '教辅', '参考书', '习题集', '试卷',
      '课程', '网课', '在线课程', 'mooc', '慕课',
      '培训', '培训班', '辅导班', '补习', '家教', '一对一',
      '考试', '考证', '考研', '考公', '考编', '考驾照', '考雅思', '考托福',
      '雅思', '托福', 'gre', 'gmat', 'sat', 'act',
      '驾照', '驾校', '学车', '科目', '路考',
      '资料', '打印', '复印', '扫描', '彩印',
      '文具', '笔', '铅笔', '圆珠笔', '签字笔', '钢笔', '马克笔',
      '本子', '笔记本', '草稿纸', 'a4纸', '便签',
      '书包', '背包', '电脑包',
      '考试费', '报名费', '报考费', '注册费', '认证费',
      '留学', '申请费', '签证', '护照', '语言学校',
    ],
  };

  // ==================== 分类映射（收入）====================

  static final Map<String, List<String>> _incomeCategoryKeywords = {
    '工资': [
      '工资', '薪水', '月薪', '年薪', '底薪', '基本工资', '岗位工资',
      '绩效', '绩效工资', 'kpi', '考核',
      '年终奖', '年终奖金', '十三薪', '十四薪', 'n薪',
      '奖金', '全勤奖', '项目奖', '销售奖', '季度奖', '优秀员工奖',
      '提成', '销售提成', '业绩提成',
      '加班费', '加班工资', '调休折算',
      '报销', '差旅报销', '发票报销', '费用报销',
      '养老金', '退休金', '退休金', '失业金', '公积金提取',
      '津贴', '补助', '补贴', '租房补贴', '交通补贴', '餐补', '话补', '高温补贴',
    ],
    '兼职': [
      '兼职', '副业', '临时工', '小时工', '日结',
      '代驾', '跑腿', '众包', '接单', '外卖骑手', '众包骑手',
      '网约车司机', '顺风车司机',
      '家教', '补课', '辅导',
      ' freelance', '自由职业', '接私活', '外包',
      '摆摊', '夜市', '地摊', '微商', '代购',
      '翻译', '写手', '设计', '插画', '配音', '剪辑', '编程',
      '直播', '带货', '打赏', '礼物',
    ],
    '投资': [
      '投资', '理财', '基金', '股票', '债券', '期货', '黄金', '白银',
      '利息', '存款利息', '理财收益',
      '收益', '盈利', '赢利', '赚', '挣钱',
      '分红', '股息', '股利',
      '逆回购', '国债', '企业债',
      'p2p', '网贷', '余额宝', '零钱通',
      '赎回', '变现', '套现', '卖出', '清仓',
    ],
    '礼金': [
      '礼金', '红包', '压岁钱', '份子钱', '随礼',
      '礼物', '送礼', '收礼', '收受',
      '生日红包', '结婚红包', '满月红包', '乔迁红包',
      '奖学金', '助学金', '助学贷款', '贫困补助',
      '慰问金', '抚恤金', '丧葬费',
    ],
  };

  // ==================== 备注清洗规则 ====================

  /// 无意义虚词，从备注中剔除
  static final List<String> _fillerWords = [
    '了', '的', '啊', '呢', '吧', '哦', '嗯',
    '总共', '一共', '合计', '共计', '总计',
    '大概', '大约', '差不多', '左右', '上下',
    '其实', '实际上', '本来', '原来',
    '就是', '也就是', '就是说',
  ];

  /// 备注中要去掉的金额相关表达
  static final RegExp _amountCleanupPattern = RegExp(
    r'(?:花了|用了|支出|支付|付了|消费|缴纳|交|垫付|买|付|收到|到账|发了|领了|获得)?\s*(?:了)?\s*(?:总共|一共|合计|共计|总计)?\s*\d+(?:\.\d+)?\s*(?:块|元|块钱|元钱|￥|¥)?',
    caseSensitive: false,
  );

  // ==================== 公共 API ====================

  /// 解析入口
  static ParseResult parse(String input) {
    if (input.trim().isEmpty) {
      return ParseResult.empty();
    }

    final text = input.trim();

    // 1. 提取金额
    final amount = _extractAmount(text);

    // 2. 判断收支类型
    final typeInfo = _detectType(text, amount);

    // 3. 匹配分类
    final category = _detectCategory(text, typeInfo.isIncome);

    // 4. 清洗备注
    final note = _cleanNote(text, amount);

    return ParseResult(
      amount: amount,
      isIncome: typeInfo.isIncome,
      category: category,
      note: note,
      confidence: amount != null ? 'high' : 'low',
    );
  }

  // ==================== 金额提取（核心）====================

  static double? _extractAmount(String text) {
    final candidates = <_AmountCandidate>[];

    // 收集各模式的匹配结果
    _collectMatches(text, _perCapitaPattern, candidates, 100);
    _collectMatches(text, _actualPayPattern, candidates, 90);
    _collectMatches(text, _verbPayPattern, candidates, 80);
    _collectMatches(text, _verbIncomePattern, candidates, 80);
    _collectMatches(text, _currencyPattern, candidates, 60);
    _collectMatches(text, _numberPattern, candidates, 40);

    if (candidates.isEmpty) return null;

    // 过滤掉被否定词修饰的金额
    final negativeMatches = _negativePattern.allMatches(text);
    final negativeRanges = negativeMatches.map((m) => m.start).toList();

    candidates.removeWhere((c) {
      for (final negStart in negativeRanges) {
        // 如果金额在否定词后8个字符内，视为被否定
        if (c.start >= negStart && c.start <= negStart + 12) {
          return true;
        }
      }
      return false;
    });

    if (candidates.isEmpty) return null;

    // 按优先级排序，取最高分的
    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates.first.value;
  }

  static void _collectMatches(
    String text,
    RegExp pattern,
    List<_AmountCandidate> candidates,
    int baseScore,
  ) {
    for (final match in pattern.allMatches(text)) {
      final value = double.tryParse(match.group(1) ?? '');
      if (value != null && value > 0 && value < 99999999) {
        candidates.add(_AmountCandidate(
          value: value,
          start: match.start,
          score: baseScore,
        ));
      }
    }
  }

  // ==================== 收支类型判断 ====================

  static _TypeInfo _detectType(String text, double? amount) {
    // 先判断是否有明确收入信号
    for (final rule in _incomeRules) {
      if (rule.pattern.hasMatch(text)) {
        return _TypeInfo(isIncome: true, trigger: rule.mappedCategory);
      }
    }

    // 再判断支出信号
    for (final rule in _expenseRules) {
      if (rule.pattern.hasMatch(text)) {
        return _TypeInfo(isIncome: false, trigger: rule.mappedCategory);
      }
    }

    // 默认支出
    return _TypeInfo(isIncome: false, trigger: null);
  }

  // ==================== 分类匹配 ====================

  static String? _detectCategory(String text, bool isIncome) {
    final map = isIncome ? _incomeCategoryKeywords : _expenseCategoryKeywords;

    // 记录每个分类的匹配次数和匹配位置
    final scores = <String, _CategoryScore>{};

    for (final entry in map.entries) {
      final category = entry.key;
      final keywords = entry.value;

      for (final kw in keywords) {
        // 全词匹配或包含匹配
        final exactPattern = RegExp(r'\b' + RegExp.escape(kw) + r'\b');
        final fuzzyPattern = RegExp(RegExp.escape(kw));

        final exactMatches = exactPattern.allMatches(text);
        final fuzzyMatches = fuzzyPattern.allMatches(text);

        for (final m in exactMatches) {
          scores[category] = _CategoryScore(
            category,
            (scores[category]?.score ?? 0) + 10,
            m.start,
          );
        }

        for (final m in fuzzyMatches) {
          // 模糊匹配如果已经被精确匹配统计过，不再加分
          final alreadyExact = exactMatches.any((e) => e.start == m.start);
          if (!alreadyExact) {
            scores[category] = _CategoryScore(
              category,
              (scores[category]?.score ?? 0) + 5,
              m.start,
            );
          }
        }
      }
    }

    if (scores.isEmpty) return null;

    // 取分数最高的；分数相同时取位置最靠前的
    final best = scores.values.reduce((a, b) {
      if (a.score != b.score) return a.score > b.score ? a : b;
      return a.position < b.position ? a : b;
    });

    return best.category;
  }

  // ==================== 备注清洗 ====================

  static String _cleanNote(String text, double? amount) {
    var note = text;

    // 1. 去掉金额及修饰语
    note = note.replaceAll(_amountCleanupPattern, '');

    // 2. 去掉无意义虚词（仅在词边界时）
    for (final word in _fillerWords) {
      note = note.replaceAll(RegExp(r'\b' + RegExp.escape(word) + r'\b'), '');
    }

    // 3. 清理多余标点
    note = note.replaceAll(RegExp(r'[,，.。!！?？;；:：\s]+'), ' ');

    // 4. 去掉首尾空白和常见冗余词
    note = note.trim();
    note = note.replaceAll(RegExp(r'^(?:我|今天|昨天|前天|上周|这周|刚才)\s*'), '');

    // 5. 如果清洗后为空，保留原始文本（去掉纯数字部分）
    if (note.isEmpty) {
      note = text.replaceAll(RegExp(r'\d+(?:\.\d+)?'), '').trim();
      note = note.replaceAll(RegExp(r'[,，.。!！?？;；:：\s]+'), ' ').trim();
    }

    // 6. 如果还是空，返回原始文本
    if (note.isEmpty) {
      note = text;
    }

    return note.length > 50 ? '${note.substring(0, 50)}...' : note;
  }
}

// ==================== 数据模型 ====================

class ParseResult {
  final double? amount;
  final bool isIncome;
  final String? category;
  final String note;
  final String confidence;

  ParseResult({
    this.amount,
    required this.isIncome,
    this.category,
    required this.note,
    required this.confidence,
  });

  ParseResult.empty()
      : amount = null,
        isIncome = false,
        category = null,
        note = '',
        confidence = 'low';

  bool get isValid => amount != null;

  @override
  String toString() {
    final type = isIncome ? '收入' : '支出';
    final amt = amount?.toStringAsFixed(2) ?? '?';
    final cat = category ?? '未分类';
    return 'ParseResult($type ¥$amt, $cat, "$note", confidence=$confidence)';
  }
}

// ==================== 内部辅助类 ====================

class _AmountCandidate {
  final double value;
  final int start;
  final int score;

  _AmountCandidate({required this.value, required this.start, required this.score});
}

class _TypeInfo {
  final bool isIncome;
  final String? trigger;

  _TypeInfo({required this.isIncome, this.trigger});
}

class _KeywordRule {
  final RegExp pattern;
  final String mappedCategory;

  _KeywordRule(this.pattern, this.mappedCategory);
}

class _CategoryScore {
  final String category;
  final int score;
  final int position;

  _CategoryScore(this.category, this.score, this.position);
}
