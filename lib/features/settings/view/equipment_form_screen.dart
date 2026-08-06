import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/equipment_kind.dart';
import '../../../core/constants/equipment_purpose.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/fov_input_parser.dart';
import '../../../data/models/equipment.dart';
import '../../../data/models/eyepiece.dart';
import '../viewmodel/equipment_view_model.dart';

class EquipmentFormScreen extends StatefulWidget {
  const EquipmentFormScreen({super.key, required this.initial});

  final Equipment initial;

  @override
  State<EquipmentFormScreen> createState() => _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends State<EquipmentFormScreen> {
  late final TextEditingController _nameCtrl;
  late EquipmentKind _kind;
  late EquipmentPurpose _purpose;
  late bool _isActive;
  late final TextEditingController _focalCtrl;
  late final TextEditingController _fovWidthCtrl;
  late final TextEditingController _fovHeightCtrl;
  late final TextEditingController _apertureCtrl;
  late List<Eyepiece> _eyepieces;
  String? _autofocusEyepieceId;

  bool _isSaving = false;
  bool get _isEditing =>
      context.read<EquipmentViewModel>().equipment.any(
            (e) => e.id == widget.initial.id,
          );

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _nameCtrl = TextEditingController(text: e.name);
    _kind = e.kind;
    _purpose = e.purpose;
    _isActive = e.isActive;
    _focalCtrl = TextEditingController(
      text: e.focalLengthMm?.toStringAsFixed(0) ?? '',
    );
    _fovWidthCtrl = TextEditingController(
      text: e.fovWidthDegrees != null
          ? FovInputParser.format(e.fovWidthDegrees!)
          : '',
    );
    _fovHeightCtrl = TextEditingController(
      text: e.fovHeightDegrees != null
          ? FovInputParser.format(e.fovHeightDegrees!)
          : '',
    );
    _apertureCtrl = TextEditingController(
      text: e.apertureMm?.toStringAsFixed(0) ?? '',
    );
    _eyepieces = List<Eyepiece>.from(e.eyepieces);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _focalCtrl.dispose();
    _fovWidthCtrl.dispose();
    _fovHeightCtrl.dispose();
    _apertureCtrl.dispose();
    super.dispose();
  }

  double? _parseDouble(String text) {
    final v = double.tryParse(text.trim());
    return v;
  }

  double? get _computedFRatio {
    final fl = _parseDouble(_focalCtrl.text);
    final ap = _parseDouble(_apertureCtrl.text);
    if (fl == null || ap == null || ap <= 0) return null;
    return fl / ap;
  }

  (double, double)? _parseFovPair() {
    final width = _parseDouble(_fovWidthCtrl.text);
    final height = _parseDouble(_fovHeightCtrl.text);
    if (width != null && height != null && width > 0 && height > 0) {
      return (width, height);
    }

    final combined = FovInputParser.parsePair(_fovWidthCtrl.text);
    if (combined != null) return combined;

    return null;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showError('장비명을 입력하세요.');
      return;
    }

    final focal = _parseDouble(_focalCtrl.text);
    double? fovWidth;
    double? fovHeight;
    if (_purpose == EquipmentPurpose.imaging) {
      final fov = _parseFovPair();
      if (focal == null || fov == null) {
        _showError('초점거리와 FOV(가로×세로 °)를 입력하세요.');
        return;
      }
      fovWidth = fov.$1;
      fovHeight = fov.$2;
    } else {
      final aperture = _parseDouble(_apertureCtrl.text);
      if (focal == null || aperture == null) {
        _showError('구경과 초점거리를 입력하세요.');
        return;
      }
      if (_eyepieces.isEmpty) {
        _showError('아이피스를 1개 이상 등록하세요.');
        return;
      }
      for (final ep in _eyepieces) {
        if (ep.name.trim().isEmpty) {
          _showError('아이피스 이름을 입력하세요.');
          return;
        }
        if (ep.focalLengthMm <= 0 || ep.afovDegrees <= 0) {
          _showError('아이피스 초점거리와 AFOV를 입력하세요.');
          return;
        }
      }
    }

    setState(() => _isSaving = true);

    final equipment = Equipment(
      id: widget.initial.id,
      name: name,
      kind: _kind,
      purpose: _purpose,
      isActive: _isActive,
      focalLengthMm: focal,
      fovWidthDegrees:
          _purpose == EquipmentPurpose.imaging ? fovWidth : null,
      fovHeightDegrees:
          _purpose == EquipmentPurpose.imaging ? fovHeight : null,
      apertureMm: _purpose == EquipmentPurpose.visual
          ? _parseDouble(_apertureCtrl.text)
          : null,
      sortOrder: widget.initial.sortOrder,
      eyepieces: _eyepieces
          .map(
            (ep) => ep.copyWith(
              name: ep.name.trim().isEmpty
                  ? '${ep.focalLengthMm.toStringAsFixed(0)}mm'
                  : ep.name.trim(),
            ),
          )
          .toList(),
    );

    final ok = await context.read<EquipmentViewModel>().save(equipment);
    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      Navigator.of(context).pop();
    } else {
      _showError(
        context.read<EquipmentViewModel>().errorMessage ?? '저장 실패',
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addEyepiece() {
    final viewModel = context.read<EquipmentViewModel>();
    final eyepiece = viewModel.newEyepiece(widget.initial.id);
    setState(() {
      _eyepieces.insert(0, eyepiece);
      _autofocusEyepieceId = eyepiece.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _autofocusEyepieceId = null);
    });
  }

  void _removeEyepiece(int index) {
    setState(() => _eyepieces.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? '장비 수정' : '장비 등록'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('저장'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTextField(
            _nameCtrl,
            '장비명',
            '예: Seestar S30 Pro',
            numeric: false,
          ),
          const SizedBox(height: 16),
          _buildDropdown<EquipmentKind>(
            label: '장비 종류',
            value: _kind,
            items: EquipmentKind.values,
            labelOf: (k) => k.label,
            onChanged: (v) => setState(() => _kind = v!),
          ),
          const SizedBox(height: 16),
          _buildDropdown<EquipmentPurpose>(
            label: '사용 목적',
            value: _purpose,
            items: EquipmentPurpose.values,
            labelOf: (p) => p.label,
            onChanged: (v) => setState(() => _purpose = v!),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: const Text('활성'),
            subtitle: const Text('비활성 장비는 추천 대상에서 제외됩니다'),
            value: _isActive,
            onChanged: (v) => setState(() => _isActive = v),
          ),
          const SizedBox(height: 16),
          if (_purpose == EquipmentPurpose.imaging) ...[
            _buildTextField(_focalCtrl, '초점거리 (mm)', '160'),
            const SizedBox(height: 12),
            _buildFovFields(),
          ] else ...[
            _buildTextField(_apertureCtrl, '구경 (mm)', '90'),
            const SizedBox(height: 12),
            _buildTextField(_focalCtrl, '초점거리 (mm)', '500'),
            if (_computedFRatio != null) ...[
              const SizedBox(height: 8),
              Text(
                'F값: f/${_computedFRatio!.toStringAsFixed(1)} (자동 계산)',
                style: const TextStyle(
                  color: AppColors.solar,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  '아이피스',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addEyepiece,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('추가'),
                ),
              ],
            ),
            ..._eyepieces.asMap().entries.map((entry) {
              final index = entry.key;
              final ep = entry.value;
              return _EyepieceEditor(
                eyepiece: ep,
                autofocus: _autofocusEyepieceId == ep.id,
                onChanged: (updated) {
                  setState(() => _eyepieces[index] = updated);
                },
                onRemove: _eyepieces.length > 1
                    ? () => _removeEyepiece(index)
                    : null,
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildFovFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FOV (가로 × 세로 °)',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildTextField(
                _fovWidthCtrl,
                '가로',
                '2.24',
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(8, 28, 8, 0),
              child: Text(
                '×',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: _buildTextField(
                _fovHeightCtrl,
                '세로',
                '3.99',
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '예: S50 0.72×1.28°, S30 Pro 2.24×3.99°',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint, {
    bool numeric = true,
  }) {
    return TextField(
      controller: controller,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: numeric
          ? [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: AppColors.surface,
      ),
      onChanged: (_) {
        if (_purpose == EquipmentPurpose.visual) {
          setState(() {});
        }
      },
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: AppColors.surface,
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(labelOf(item)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _EyepieceEditor extends StatefulWidget {
  const _EyepieceEditor({
    required this.eyepiece,
    required this.onChanged,
    this.onRemove,
    this.autofocus = false,
  });

  final Eyepiece eyepiece;
  final ValueChanged<Eyepiece> onChanged;
  final VoidCallback? onRemove;
  final bool autofocus;

  @override
  State<_EyepieceEditor> createState() => _EyepieceEditorState();
}

class _EyepieceEditorState extends State<_EyepieceEditor> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _focalCtrl;
  late final TextEditingController _afovCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.eyepiece.name);
    _focalCtrl = TextEditingController(text: _formatLength(widget.eyepiece.focalLengthMm));
    _afovCtrl = TextEditingController(text: _formatLength(widget.eyepiece.afovDegrees));
  }

  String _formatLength(double value) {
    if (value <= 0) {
      return '';
    }
    return value.toStringAsFixed(0);
  }

  @override
  void didUpdateWidget(covariant _EyepieceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eyepiece.id != widget.eyepiece.id) {
      _nameCtrl.text = widget.eyepiece.name;
      _focalCtrl.text = _formatLength(widget.eyepiece.focalLengthMm);
      _afovCtrl.text = _formatLength(widget.eyepiece.afovDegrees);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _focalCtrl.dispose();
    _afovCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const Text(
                  '아이피스',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            _ClearOnFocusTextField(
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '25mm',
                border: OutlineInputBorder(),
              ),
              controller: _nameCtrl,
              autofocus: widget.autofocus,
              onChanged: (v) =>
                  widget.onChanged(widget.eyepiece.copyWith(name: v)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ClearOnFocusTextField(
                    decoration: const InputDecoration(
                      labelText: '초점거리 (mm)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: _focalCtrl,
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        widget.onChanged(
                          widget.eyepiece.copyWith(focalLengthMm: parsed),
                        );
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ClearOnFocusTextField(
                    decoration: const InputDecoration(
                      labelText: 'AFOV (°)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: _afovCtrl,
                    onChanged: (v) {
                      final parsed = double.tryParse(v);
                      if (parsed != null) {
                        widget.onChanged(
                          widget.eyepiece.copyWith(afovDegrees: parsed),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ClearOnFocusTextField extends StatefulWidget {
  const _ClearOnFocusTextField({
    required this.controller,
    required this.decoration,
    this.keyboardType,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<_ClearOnFocusTextField> createState() => _ClearOnFocusTextFieldState();
}

class _ClearOnFocusTextFieldState extends State<_ClearOnFocusTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.controller.clear();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      keyboardType: widget.keyboardType,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
    );
  }
}
