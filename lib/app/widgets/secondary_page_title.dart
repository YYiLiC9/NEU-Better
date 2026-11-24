import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class SecondaryPageTitle extends StatelessWidget {
  const SecondaryPageTitle(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final bodyStyle = Theme.of(context).textTheme.bodyMedium;
    return Text(
      title,
      style: (bodyStyle ?? const TextStyle()).copyWith(
        inherit: false,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    );
  }
}
