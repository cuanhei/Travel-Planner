import 'dart:math';

import 'package:flutter/material.dart';

import '../../models/avatar_config.dart';
import '../../services/locale_service.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_preview.dart';
import '../../widgets/detail_header.dart';
import '../../widgets/gradient_button.dart';

enum _Cat { skin, hair, face, hat, top, bottom, socks, shoes, accessories }

class _Choice {
  const _Choice(this.apply);
  final AvatarConfig Function(AvatarConfig current) apply;
}

class AvatarCreatorScreen extends StatefulWidget {
  const AvatarCreatorScreen({super.key, this.initialConfig});

  final AvatarConfig? initialConfig;

  @override
  State<AvatarCreatorScreen> createState() => _AvatarCreatorScreenState();
}

class _AvatarCreatorScreenState extends State<AvatarCreatorScreen> {
  late AvatarConfig _config =
      widget.initialConfig ?? AvatarConfig.defaultFor(AvatarGender.male);
  _Cat _cat = _Cat.hair;
  bool _saving = false;

  void _applyChoice(_Choice choice) {
    setState(() => _config = choice.apply(_config));
  }

  void _randomize() {
    final r = Random();
    T pick<T>(List<T> options) => options[r.nextInt(options.length)];
    setState(() {
      _config = _config.copyWith(
        skinTone: pick(AvatarCatalog.skinTones),
        hairStyle: pick(AvatarCatalog.hair).id,
        hairColor: pick(AvatarCatalog.palette),
        expression: pick(AvatarCatalog.expressions).id,
        hat: pick(AvatarCatalog.hats).id,
        hatColor: pick(AvatarCatalog.palette),
        top: pick(AvatarCatalog.tops).id,
        topColor: pick(AvatarCatalog.palette),
        bottom: pick(AvatarCatalog.bottoms).id,
        bottomColor: pick(AvatarCatalog.palette),
        socks: pick(AvatarCatalog.socks).id,
        socksColor: pick(AvatarCatalog.palette),
        shoes: pick(AvatarCatalog.shoes).id,
        shoesColor: pick(AvatarCatalog.palette),
      );
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ProfileService.instance.setAvatarDesign(_config);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: context.colors.ink,
          content: Text(tr('avatar_saved')),
        ),
      );
    } catch (e) {
      debugPrint('Avatar save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(tr('common_error_generic')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            DetailHeader(
              title: tr('avatar_creator_title'),
              subtitle: tr('avatar_creator_subtitle'),
              trailing: IconButton(
                onPressed: _randomize,
                icon: Icon(Icons.shuffle_rounded, color: context.colors.ink),
              ),
            ),
            _dragTargetPreview(),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _genderToggle(),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _categoryChips(),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                child: _buildOptions(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: GradientButton(
                label: tr('avatar_save'),
                icon: Icons.check_rounded,
                onPressed: _save,
                loading: _saving,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dragTargetPreview() {
    return DragTarget<_Choice>(
      onAcceptWithDetails: (details) => _applyChoice(details.data),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(hovering ? 6 : 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            color: hovering ? AppColors.accent.withValues(alpha: 0.08) : null,
            border: hovering
                ? Border.all(color: AppColors.accent, width: 2)
                : null,
          ),
          child: AvatarPreview(config: _config, width: 190, height: 240),
        );
      },
    );
  }

  Widget _genderToggle() {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.muted.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _genderBtn(tr('avatar_gender_male'), AvatarGender.male),
          ),
          Expanded(
            child: _genderBtn(tr('avatar_gender_female'), AvatarGender.female),
          ),
        ],
      ),
    );
  }

  Widget _genderBtn(String label, AvatarGender g) {
    final active = _config.gender == g;
    return GestureDetector(
      onTap: () => setState(() => _config = _config.copyWith(gender: g)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? context.colors.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : context.colors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _categoryChips() {
    final cats = [
      (_Cat.skin, tr('avatar_cat_skin'), Icons.palette_outlined),
      (
        _Cat.hair,
        tr('avatar_cat_hair'),
        Icons.face_retouching_natural_outlined,
      ),
      (_Cat.face, tr('avatar_cat_face'), Icons.emoji_emotions_outlined),
      (_Cat.hat, tr('avatar_cat_hat'), Icons.checkroom_outlined),
      (_Cat.top, tr('avatar_cat_top'), Icons.dry_cleaning_outlined),
      (_Cat.bottom, tr('avatar_cat_bottom'), Icons.style_outlined),
      (_Cat.socks, tr('avatar_cat_socks'), Icons.line_style_rounded),
      (_Cat.shoes, tr('avatar_cat_shoes'), Icons.hiking_outlined),
      (_Cat.accessories, tr('avatar_cat_accessories'), Icons.watch_outlined),
    ];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: cats.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (cat, label, icon) = cats[i];
          final active = _cat == cat;
          return GestureDetector(
            onTap: () => setState(() => _cat = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? context.colors.ink : context.colors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: active ? Colors.white : context.colors.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: active ? Colors.white : context.colors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildOptions() {
    switch (_cat) {
      case _Cat.skin:
        return _colorRow(
          AvatarCatalog.skinTones,
          current: _config.skinTone,
          onPick: (v) => _Choice((c) => c.copyWith(skinTone: v)),
        );
      case _Cat.face:
        return _styleGrid(
          AvatarCatalog.expressions,
          currentId: _config.expression,
          previewFor: (id) => _config.copyWith(expression: id),
          onPick: (id) => _Choice((c) => c.copyWith(expression: id)),
        );
      case _Cat.hair:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.hair,
              currentId: _config.hairStyle,
              previewFor: (id) => _config.copyWith(hairStyle: id),
              onPick: (id) => _Choice((c) => c.copyWith(hairStyle: id)),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.hairColor,
              onPick: (v) => _Choice((c) => c.copyWith(hairColor: v)),
            ),
          ],
        );
      case _Cat.hat:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.hats,
              currentId: _config.hat,
              previewFor: (id) => _config.copyWith(hat: id),
              onPick: (id) => _Choice((c) => c.copyWith(hat: id)),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.hatColor,
              onPick: (v) => _Choice((c) => c.copyWith(hatColor: v)),
            ),
          ],
        );
      case _Cat.top:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.tops,
              currentId: _config.top,
              previewFor: (id) => _config.copyWith(top: id),
              onPick: (id) => _Choice((c) => c.copyWith(top: id)),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.topColor,
              onPick: (v) => _Choice((c) => c.copyWith(topColor: v)),
            ),
          ],
        );
      case _Cat.bottom:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.bottoms,
              currentId: _config.bottom,
              previewFor: (id) => _config.copyWith(
                bottom: id,
                top: _config.top == 'dress' ? 'tshirt' : _config.top,
              ),
              onPick: (id) => _Choice(
                (c) => c.copyWith(
                  bottom: id,
                  top: c.top == 'dress' ? 'tshirt' : c.top,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.bottomColor,
              onPick: (v) => _Choice((c) => c.copyWith(bottomColor: v)),
            ),
          ],
        );
      case _Cat.socks:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.socks,
              currentId: _config.socks,
              previewFor: (id) => _config.copyWith(socks: id),
              onPick: (id) => _Choice((c) => c.copyWith(socks: id)),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.socksColor,
              onPick: (v) => _Choice((c) => c.copyWith(socksColor: v)),
            ),
          ],
        );
      case _Cat.shoes:
        return Column(
          children: [
            _styleGrid(
              AvatarCatalog.shoes,
              currentId: _config.shoes,
              previewFor: (id) => _config.copyWith(shoes: id),
              onPick: (id) => _Choice((c) => c.copyWith(shoes: id)),
            ),
            const SizedBox(height: 16),
            _colorRow(
              AvatarCatalog.palette,
              current: _config.shoesColor,
              onPick: (v) => _Choice((c) => c.copyWith(shoesColor: v)),
            ),
          ],
        );
      case _Cat.accessories:
        return _styleGrid(
          AvatarCatalog.accessories,
          currentId: null,
          isSelected: (id) => _config.accessories.contains(id),
          previewFor: (id) =>
              _config.copyWith(accessories: {..._config.accessories, id}),
          onPick: (id) => _Choice((c) {
            final s = {...c.accessories};
            if (!s.remove(id)) s.add(id);
            return c.copyWith(accessories: s);
          }),
        );
    }
  }

  Widget _styleGrid(
    List<AvatarOption> options, {
    required String? currentId,
    bool Function(String id)? isSelected,
    required AvatarConfig Function(String id) previewFor,
    required _Choice Function(String id) onPick,
  }) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: options.length,
      itemBuilder: (context, i) {
        final opt = options[i];
        final selected = isSelected != null
            ? isSelected(opt.id)
            : opt.id == currentId;
        return _OptionTile(
          previewConfig: previewFor(opt.id),
          label: opt.label,
          selected: selected,
          choice: onPick(opt.id),
          onApply: _applyChoice,
        );
      },
    );
  }

  Widget _colorRow(
    List<int> colors, {
    required int current,
    required _Choice Function(int v) onPick,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colors.map((v) {
        return _ColorSwatch(
          color: Color(v),
          selected: v == current,
          choice: onPick(v),
          onApply: _applyChoice,
        );
      }).toList(),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.previewConfig,
    required this.label,
    required this.selected,
    required this.choice,
    required this.onApply,
  });

  final AvatarConfig previewConfig;
  final String label;
  final bool selected;
  final _Choice choice;
  final ValueChanged<_Choice> onApply;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 2,
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 64,
            width: 56,
            child: AvatarPreview(config: previewConfig, width: 56, height: 72),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: context.colors.ink,
            ),
          ),
        ],
      ),
    );
    return Draggable<_Choice>(
      data: choice,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(width: 70, height: 96, child: content),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: content),
      child: GestureDetector(onTap: () => onApply(choice), child: content),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.choice,
    required this.onApply,
  });

  final Color color;
  final bool selected;
  final _Choice choice;
  final ValueChanged<_Choice> onApply;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? AppColors.accent : Colors.black12,
          width: selected ? 3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
    return Draggable<_Choice>(
      data: choice,
      feedback: Material(
        color: Colors.transparent,
        child: Transform.scale(scale: 1.3, child: dot),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: dot),
      child: GestureDetector(onTap: () => onApply(choice), child: dot),
    );
  }
}
