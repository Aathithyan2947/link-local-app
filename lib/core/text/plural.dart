/// "1 Member", "2 Members", "0 Members". [plural] defaults to [singular] + "s".
String countLabel(int count, String singular, [String? plural]) =>
    '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';
