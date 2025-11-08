import 'package:flutter/material.dart';

class TPTextSpan extends TextSpan {


  /// split text with words(english characters, digits and "_")
  static final RegExp _splitRegExp = RegExp(r'(?<=\W)(?=\w)|(?<=\w)(?=\W)');

  /// english characters, digits and "_"
  static final RegExp _wordCharacter = RegExp(r'\w');

  TPTextSpan({
    String? text,
    List<InlineSpan>? children,
    super.style,
    super.recognizer,
    super.mouseCursor,
    super.onEnter,
    super.onExit,
    super.semanticsLabel,
    super.locale,
    super.spellOut,
  }) : super(
          text: null,
          children: [
            ...?text?.split(_splitRegExp).map(
                  (text) => switch (text.contains(_wordCharacter)) {
                    true => TextSpan(
                        text: text,
                        style: switch (style) {
                          TextStyle style => style.copyWith(fontFamily: 'Roboto'),
                          null => const TextStyle(fontFamily: 'Roboto'),
                        },
                      ),
                    false => TextSpan(
                        text: text,
                        style: switch (style) {
                          TextStyle style => style.copyWith(fontFamily: 'PingFangTC'),
                          null => const TextStyle(fontFamily: 'PingFangTC'),
                        },
                      ),
                  },
                ),
            ...?children,
          ],
        );
}
