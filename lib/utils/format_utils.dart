/// 1000 이상이면 1.0k, 5.2k, 1.2M 형식으로 표시
String formatCompactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// 작성 시각 기준 상대 시간. [locale]이 있으면 해당 언어로 반환 (us/kr/jp/cn).
String formatTimeAgo(DateTime at, [String? locale]) {
  final now = DateTime.now();
  final diff = now.difference(at);
  if (locale != null && locale.isNotEmpty) {
    final s = _timeAgoStrings(locale);
    if (diff.inSeconds < 60) return s.justNow;
    if (diff.inMinutes < 60) return s.minutes.replaceAll('%d', '${diff.inMinutes}');
    if (diff.inHours < 24) return s.hours.replaceAll('%d', '${diff.inHours}');
    if (diff.inDays < 7) return s.days.replaceAll('%d', '${diff.inDays}');
    if (diff.inDays < 30) return s.weeks.replaceAll('%d', '${(diff.inDays / 7).floor()}');
    if (diff.inDays < 365) return s.months.replaceAll('%d', '${(diff.inDays / 30).floor()}');
    return s.years.replaceAll('%d', '${(diff.inDays / 365).floor()}');
  }
  if (diff.inSeconds < 60) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주 전';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}개월 전';
  return '${(diff.inDays / 365).floor()}년 전';
}

({String justNow, String minutes, String hours, String days, String weeks, String months, String years}) _timeAgoStrings(String locale) {
  const keys = ['timeAgoJustNow', 'timeAgoMinutes', 'timeAgoHours', 'timeAgoDays', 'timeAgoWeeks', 'timeAgoMonths', 'timeAgoYears'];
  final map = _timeAgoMap[locale] ?? _timeAgoMap['us']!;
  return (
    justNow: map[keys[0]]!,
    minutes: map[keys[1]]!,
    hours: map[keys[2]]!,
    days: map[keys[3]]!,
    weeks: map[keys[4]]!,
    months: map[keys[5]]!,
    years: map[keys[6]]!,
  );
}

const Map<String, Map<String, String>> _timeAgoMap = {
  'us': {
    'timeAgoJustNow': 'Just now',
    'timeAgoMinutes': '%dmin',
    'timeAgoHours': '%dh',
    'timeAgoDays': '%dd',
    'timeAgoWeeks': '%dw',
    'timeAgoMonths': '%dm',
    'timeAgoYears': '%dy',
  },
  'kr': {
    'timeAgoJustNow': '방금 전',
    'timeAgoMinutes': '%d분 전',
    'timeAgoHours': '%d시간 전',
    'timeAgoDays': '%d일 전',
    'timeAgoWeeks': '%d주 전',
    'timeAgoMonths': '%d개월 전',
    'timeAgoYears': '%d년 전',
  },
  'jp': {
    'timeAgoJustNow': 'たった今',
    'timeAgoMinutes': '%d分前',
    'timeAgoHours': '%d時間前',
    'timeAgoDays': '%d日前',
    'timeAgoWeeks': '%d週間前',
    'timeAgoMonths': '%dヶ月前',
    'timeAgoYears': '%d年前',
  },
  'cn': {
    'timeAgoJustNow': '刚刚',
    'timeAgoMinutes': '%d分钟前',
    'timeAgoHours': '%d小时前',
    'timeAgoDays': '%d天前',
    'timeAgoWeeks': '%d周前',
    'timeAgoMonths': '%d个月前',
    'timeAgoYears': '%d年前',
  },
};
