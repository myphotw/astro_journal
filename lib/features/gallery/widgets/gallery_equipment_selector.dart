import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/equipment.dart';
import '../models/gallery_equipment_selection.dart';

class GalleryEquipmentSelector extends StatelessWidget {
  const GalleryEquipmentSelector({
    super.key,
    required this.selection,
    required this.equipment,
    required this.onSelected,
    required this.onUnlink,
    this.currentIsActive,
    this.currentIsDeleted,
  });

  final GalleryEquipmentSelection selection;
  final List<Equipment> equipment;
  final ValueChanged<Equipment> onSelected;
  final VoidCallback onUnlink;
  final bool? currentIsActive;
  final bool? currentIsDeleted;

  @override
  Widget build(BuildContext context) {
    final active = equipment
        .where((item) => item.isActive)
        .toList(growable: false);
    final activeIds = active.map((item) => item.id).toSet();
    final selectedId = activeIds.contains(selection.equipmentId)
        ? selection.equipmentId
        : null;
    final duplicateNames = <String>{
      for (final item in active)
        if (active.where((other) => other.name == item.name).length > 1)
          item.name,
    };
    final linkedUnavailable =
        selection.equipmentId != null &&
        (!activeIds.contains(selection.equipmentId) ||
            currentIsActive == false ||
            currentIsDeleted == true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('gallery-equipment-selector-$selectedId'),
          initialValue: selectedId,
          isExpanded: true,
          decoration: const InputDecoration(
            hintText: '등록된 장비를 선택하세요',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final item in active)
              DropdownMenuItem<String>(
                key: ValueKey('gallery-equipment-option-${item.id}'),
                value: item.id,
                child: Text(
                  duplicateNames.contains(item.name)
                      ? '${item.name} · ${_shortId(item.id)}'
                      : item.name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: active.isEmpty
              ? null
              : (id) {
                  if (id == null) return;
                  onSelected(active.firstWhere((item) => item.id == id));
                },
        ),
        if (selection.displayName.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            linkedUnavailable
                ? '현재 장비: ${selection.displayName} (비활성 또는 삭제됨)'
                : '현재 장비: ${selection.displayName}',
            key: const Key('gallery-equipment-current-name'),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
        if (selection.equipmentId != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            key: const Key('gallery-equipment-unlink'),
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('등록 장비 연결 해제'),
          ),
        ],
      ],
    );
  }

  static String _shortId(String id) => id.length <= 8 ? id : id.substring(0, 8);
}
