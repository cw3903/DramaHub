import 'package:flutter/cupertino.dart';

import '../models/custom_drama_list.dart';
import 'custom_drama_list_detail_screen.dart';

Future<void> openCustomDramaListDetail(
  BuildContext context,
  CustomDramaList list,
) {
  return Navigator.push<void>(
    context,
    CupertinoPageRoute<void>(
      builder: (_) => CustomDramaListDetailScreen(list: list),
    ),
  );
}
