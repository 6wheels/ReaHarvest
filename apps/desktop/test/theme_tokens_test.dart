import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reaharvest/theme/app_theme.dart';
import 'package:reaharvest_library/reaharvest_library.dart'
    show AccentPreference;

void main() {
  test('the text styles have the same sizes on both themes', () {
    final dark = AppText.of(AppColors.dark);
    final light = AppText.of(AppColors.light);
    expect(dark.body.fontSize, light.body.fontSize);
    expect(dark.legend.fontSize, light.legend.fontSize);
    expect(dark.body.color, AppColors.dark.text);
    expect(light.body.color, AppColors.light.text);
    expect(dark.readout.color, AppColors.dark.muted);
  });

  test('the type scale grows from micro to title', () {
    final t = AppText.of(AppColors.dark);
    final sizes = [
      t.micro,
      t.small,
      t.caption,
      t.body,
      t.item,
      t.title,
    ].map((s) => s.fontSize!).toList();
    expect(sizes, [...sizes]..sort());
    expect(sizes.toSet().length, sizes.length);
  });

  test('copyWith and lerp keep every style', () {
    final dark = AppText.of(AppColors.dark);
    final light = AppText.of(AppColors.light);
    final same = dark.copyWith();
    expect(same.item, dark.item);
    final replaced = dark.copyWith(body: light.body);
    expect(replaced.body.color, AppColors.light.text);
    expect(dark.lerp(null, 0.5), dark);
    final half = dark.lerp(light, 1);
    expect(half.body.color, AppColors.light.text);
    expect(half.readoutSmall.fontSize, dark.readoutSmall.fontSize);
    expect(AppText.color(Colors.red).color, Colors.red);
  });

  test('the colors lerp each field to its own counterpart', () {
    final mid = AppColors.dark.lerp(AppColors.light, 1);
    expect(mid.accent, AppColors.light.accent);
    expect(mid.ledRed, AppColors.light.ledRed);
    expect(AppColors.dark.lerp(null, 0.5), AppColors.dark);
  });

  test('the text styles lerp each field to its own counterpart', () {
    final dark = AppText.of(AppColors.dark);
    final light = AppText.of(AppColors.light);
    final mid = dark.lerp(light, 0.5);
    for (final (a, b, m) in [
      (dark.micro, light.micro, mid.micro),
      (dark.small, light.small, mid.small),
      (dark.caption, light.caption, mid.caption),
      (dark.body, light.body, mid.body),
      (dark.item, light.item, mid.item),
      (dark.title, light.title, mid.title),
      (dark.legend, light.legend, mid.legend),
      (dark.legendSmall, light.legendSmall, mid.legendSmall),
      (dark.readout, light.readout, mid.readout),
      (dark.readoutSmall, light.readoutSmall, mid.readoutSmall),
    ]) {
      expect(m.fontSize, a.fontSize);
      expect(m.color, Color.lerp(a.color, b.color, 0.5));
    }
  });

  test('copyWith replaces each field', () {
    final dark = AppText.of(AppColors.dark);
    final other = AppText.of(AppColors.light);
    expect(dark.copyWith(micro: other.micro).micro, other.micro);
    expect(dark.copyWith(small: other.small).small, other.small);
    expect(dark.copyWith(caption: other.caption).caption, other.caption);
    expect(dark.copyWith(item: other.item).item, other.item);
    expect(dark.copyWith(title: other.title).title, other.title);
    expect(dark.copyWith(legend: other.legend).legend, other.legend);
    expect(
      dark.copyWith(legendSmall: other.legendSmall).legendSmall,
      other.legendSmall,
    );
    expect(dark.copyWith(readout: other.readout).readout, other.readout);
    expect(
      dark.copyWith(readoutSmall: other.readoutSmall).readoutSmall,
      other.readoutSmall,
    );
  });

  double contrast(Color a, Color b) {
    final (la, lb) = (a.computeLuminance(), b.computeLuminance());
    return (la > lb ? la + 0.05 : lb + 0.05) /
        (la > lb ? lb + 0.05 : la + 0.05);
  }

  test('every accent stands out from the background of its theme', () {
    for (final brightness in Brightness.values) {
      final background = brightness == Brightness.dark
          ? AppColors.dark.background
          : AppColors.light.background;
      for (final preference in AccentPreference.values) {
        final accent = Accents.of(preference, brightness);
        expect(
          contrast(accent, background),
          greaterThanOrEqualTo(3),
          reason: '$preference on $brightness',
        );
      }
    }
  });

  test('the accent of a preference reaches the theme', () {
    for (final brightness in Brightness.values) {
      for (final preference in AccentPreference.values) {
        final theme = buildTheme(brightness, accent: preference);
        expect(
          theme.extension<AppColors>()!.accent,
          Accents.of(preference, brightness),
        );
      }
    }
  });

  test('the alpha levels grow', () {
    const levels = [
      Alpha.faint,
      Alpha.tint,
      Alpha.soft,
      Alpha.medium,
      Alpha.strong,
      Alpha.dense,
    ];
    expect(levels, [...levels]..sort());
  });
}
