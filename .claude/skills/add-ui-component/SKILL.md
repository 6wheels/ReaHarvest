---
name: add-ui-component
description: Add or rework a ReaHarvest UI component. The component goes into the shared kit and into the showcase first, before any screen uses it. It uses theme tokens only, and gets a golden test in both themes. Use whenever an issue adds or changes a reusable visual component (button, field, panel, row, badge, dialog part…).
argument-hint: <component name> [issue number]
---

# Add a UI component: $ARGUMENTS

Order: **kit, then showcase, then golden test, then screens**. A screen never gets a component that the showcase does not show.

## Steps

1. **Look for an existing component**: check `apps/desktop/lib/ui/widgets.dart`, `glass_dialog.dart` and the other files of `apps/desktop/lib/ui/`. When one fits, or fits with a parameter, propose to reuse or extend it, and stop there unless the user disagrees.
2. **Map the tokens**: list every color, spacing, radius, text style, size and duration the component needs, each mapped to an existing token of `apps/desktop/lib/theme/app_theme.dart` (`Space`, `Radii`, `AppColors`, `Fonts`, `context.legend`, `context.readout`…). Write no literal value: no `Color(…)`, no hard-coded `EdgeInsets` numbers, radius, font size or `Duration`.
3. **Write the component in the kit**:
   - a public widget with a doc comment;
   - small components go in `ui/widgets.dart`, a larger one in its own file `ui/<name>.dart` (one file per component);
   - states are never told apart by hue alone: add luminance, shape, icon or glow;
   - texts come from ARB, in both files.
4. **Add it to the showcase**: a section in `apps/desktop/lib/main_showcase.dart`, on mock data, showing every state (default, hover or focus when relevant, disabled, error, busy) in both themes. The showcase must compile the first time; a change to `main()` needs a full restart. Tell the user how to see it (`flutter run -d windows -t lib/main_showcase.dart` in `apps/desktop`). **Wait for the user to validate the look.**
5. **Golden test**: `apps/desktop/test/goldens/<name>_golden_test.dart`.
   - Cover the main states in the dark and light themes, with the app fonts loaded (Inter, JetBrains Mono).
   - Generate the images with `flutter test --update-goldens` on the platform the CI compares them on (the widget job runs on `ubuntu-latest`).
   - Commit the images.
6. **Widget test** of the behavior (taps, keyboard, semantics), counted in the `app` coverage suite.
7. **Only then** use the component in the screens the issue names.

## Stop conditions

- A needed value has no token: stop and propose the new token (name, value in each theme). Never add a literal.
- The component is not in the scope of the current issue: stop and ask.
- The user has not validated the look in the showcase: change no screen.
- The golden images cannot be generated on the CI platform: stop and ask. Never commit images made on another platform.
- `flutter analyze` or the tests fail: fix them, or stop and report the output.
