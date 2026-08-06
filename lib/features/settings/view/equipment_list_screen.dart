import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/equipment.dart';
import '../viewmodel/equipment_view_model.dart';
import 'equipment_form_screen.dart';

class EquipmentListScreen extends StatefulWidget {
  const EquipmentListScreen({super.key});

  @override
  State<EquipmentListScreen> createState() => _EquipmentListScreenState();
}

class _EquipmentListScreenState extends State<EquipmentListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EquipmentViewModel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<EquipmentViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('장비 관리'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context),
        icon: const Icon(Icons.add),
        label: const Text('장비 등록'),
      ),
      body: viewModel.isLoading && viewModel.equipment.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : viewModel.equipment.isEmpty
              ? const Center(
                  child: Text(
                    '등록된 장비가 없습니다.\n+ 버튼으로 장비를 등록하세요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: viewModel.equipment.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = viewModel.equipment[index];
                    return _EquipmentCard(
                      equipment: item,
                      onTap: () => _openForm(context, equipment: item),
                      onToggleActive: () => viewModel.toggleActive(item),
                      onDelete: () => _confirmDelete(context, item),
                    );
                  },
                ),
    );
  }

  Future<void> _openForm(
    BuildContext context, {
    Equipment? equipment,
  }) async {
    final viewModel = context.read<EquipmentViewModel>();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ChangeNotifierProvider.value(
          value: viewModel,
          child: EquipmentFormScreen(
            initial: equipment ?? viewModel.newEquipment(),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, Equipment item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('장비 삭제'),
        content: Text('"${item.name}" 장비를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final ok = await context.read<EquipmentViewModel>().delete(item.id);
      if (!context.mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.read<EquipmentViewModel>().errorMessage ?? '삭제 실패',
            ),
          ),
        );
      }
    }
  }
}

class _EquipmentCard extends StatelessWidget {
  const _EquipmentCard({
    required this.equipment,
    required this.onTap,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Equipment equipment;
  final VoidCallback onTap;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final subtitle = equipment.isImaging
        ? '${equipment.kind.label} · ${equipment.focalLengthMm?.toStringAsFixed(0) ?? '-'}mm · FOV ${equipment.fovLabel}'
        : '${equipment.kind.label} · ${equipment.apertureMm?.toStringAsFixed(0) ?? '-'}mm · f/${equipment.fRatio?.toStringAsFixed(1) ?? '-'} · 아이피스 ${equipment.eyepieces.length}개';

    return Card(
      color: AppColors.surface,
      child: ListTile(
        onTap: onTap,
        title: Text(
          equipment.name.isEmpty ? '(이름 없음)' : equipment.name,
          style: TextStyle(
            color: equipment.isActive
                ? AppColors.textPrimary
                : AppColors.textSecondary,
            decoration:
                equipment.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          '${equipment.purpose.label} · $subtitle',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                equipment.isActive ? Icons.visibility : Icons.visibility_off,
                color: equipment.isActive
                    ? AppColors.solar
                    : AppColors.textSecondary,
              ),
              tooltip: equipment.isActive ? '비활성화' : '활성화',
              onPressed: onToggleActive,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
