import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import 'angkor_logo.dart';

/// The one header used on every screen: a floating dark pill with a gold title.
/// Shows a back arrow by itself when there is a screen to go back to.
class AngkorAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showLogo;

  /// Force the dark pill on a page that is not Home (for example over the camera).
  final bool strong;

  /// Replaces the automatic back arrow (for example a close button).
  final Widget? leading;
  final bool? showBack;
  final List<Widget> actions;

  const AngkorAppBar({
    super.key,
    required this.title,
    this.showLogo = false,
    this.strong = false,
    this.leading,
    this.showBack,
    this.actions = const [],
  });

  static const double _bar = 60;
  static const double _quietBar = 54;

  // Home pages (logo) and forced pages get the dark brand pill; inner pages a quiet bar.
  bool get _brand => showLogo || strong;

  @override
  Size get preferredSize => Size.fromHeight((_brand ? _bar : _quietBar) + 20);

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final back = showBack ?? ModalRoute.of(context)?.canPop ?? false;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Container(
            height: _brand ? _bar : _quietBar,
            padding: EdgeInsets.only(
              left: leading != null || back ? 6 : 18,
              right: 10,
            ),
            decoration: BoxDecoration(
              color: _brand ? pal.strong : pal.surface,
              borderRadius: BorderRadius.circular(_brand ? 24 : 20),
              border: (dark || !_brand) ? Border.all(color: pal.border) : null,
              boxShadow: _brand
                  ? const [
                      BoxShadow(
                        color: Color(0x24000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: IconTheme(
              data: IconThemeData(color: _brand ? pal.onStrong : pal.text),
              child: Row(
                children: [
                  if (leading != null)
                    leading!
                  else if (back)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  if (showLogo) ...[
                    AngkorLogo(size: leading != null || back ? 26 : 32),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'serif',
                        color: _brand ? pal.onStrong : pal.text,
                        fontWeight: FontWeight.bold,
                        fontSize: _brand ? 22 : 20,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
