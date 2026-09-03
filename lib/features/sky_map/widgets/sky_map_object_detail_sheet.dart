import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/catalog_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalog_object.dart';
import '../../../data/models/equipment.dart';
import '../viewmodel/sky_map_view_model.dart';

Future<void> showSkyMapObjectDetailSheet({
  required BuildContext context,
  required SkyMapViewModel viewModel,
  required CatalogObject object,
}) {
  final isWindows =
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  if (isWindows) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _SkyMapObjectDetailDialog(
        viewModel: viewModel,
        object: object,
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => _SkyMapObjectDetailContent(
      viewModel: viewModel,
      object: object,
      showDragHandle: true,
    ),
  );
}

class _SkyMapObjectDetailDialog extends StatelessWidget {
  const _SkyMapObjectDetailDialog({
    required this.viewModel,
    required this.object,
  });

  final SkyMapViewModel viewModel;
  final CatalogObject object;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => Navigator.of(context).maybePop(),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: AppColors.surface,
            insetPadding: const EdgeInsets.all(32),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 560,
                maxHeight: MediaQuery.sizeOf(context).height * 0.82,
              ),
              child: _SkyMapObjectDetailContent(
                viewModel: viewModel,
                object: object,
                showDragHandle: false,
                showCloseButton: true,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkyMapObjectDetailContent extends StatelessWidget {
  const _SkyMapObjectDetailContent({
    required this.viewModel,
    required this.object,
    required this.showDragHandle,
    this.showCloseButton = false,
  });

  final SkyMapViewModel viewModel;
  final CatalogObject object;
  final bool showDragHandle;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final equipment = viewModel.imagingEquipment;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              12,
              20,
              24 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showDragHandle) ...[
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              object.displayName,
                              style: TextStyle(
                                color: object.catalog.accentColor,
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              object.displayCommonName,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (showCloseButton)
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close),
                          tooltip: '닫기',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _metaRow('Type', object.displayType),
                  _metaRow('위치 RA', object.ra),
                  _metaRow('위치 DEC', object.dec),
                  _metaRow(
                    '크기',
                    object.angularSize ??
                        (object.majorAxis != null
                            ? "${object.majorAxis!.toStringAsFixed(0)}'"
                            : '-'),
                  ),
                  _metaRow('촬영 기록', object.captured ? '있음' : '없음'),
                  if (equipment.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      '촬영 구도 보기',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...equipment.map(
                      (eq) => _equipmentTile(
                        context: context,
                        viewModel: viewModel,
                        equipment: eq,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    Text(
                      'FOV가 설정된 촬영 장비가 없습니다.\n설정에서 장비를 추가하세요.',
                      style: TextStyle(
                        color: AppColors.textSecondary.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Widget _metaRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _equipmentTile({
  required BuildContext context,
  required SkyMapViewModel viewModel,
  required Equipment equipment,
}) {
  final advice = viewModel.framingAdviceFor(equipment);
  final isActive = viewModel.showFovOverlay &&
      viewModel.fovPreview?.equipmentId == equipment.id;

  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: isActive
          ? AppColors.solar.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          viewModel.showFovForEquipment(equipment);
          Navigator.of(context).pop();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      equipment.name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    equipment.fovLabel,
                    style: const TextStyle(
                      color: AppColors.solar,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (advice != null) ...[
                const SizedBox(height: 8),
                Text(
                  '추천: ${advice.tips.join(' · ')}',
                  style: TextStyle(
                    color: AppColors.textSecondary.withValues(alpha: 0.95),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
