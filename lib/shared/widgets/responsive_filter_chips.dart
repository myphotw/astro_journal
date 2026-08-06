import 'package:flutter/material.dart';

/// 화면 너비에 맞춰 필터 칩을 행 단위로 균등 분할 배치한다.
class ResponsiveFilterChipGrid extends StatelessWidget {
  const ResponsiveFilterChipGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.spacing = 6,
    this.runSpacing = 6,
    this.maxColumns,
    this.singleRow = false,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final double runSpacing;
  final int? maxColumns;
  final bool singleRow;

  static int columnsForWidth(
    double width,
    int itemCount, {
    int? maxColumns,
    bool singleRow = false,
  }) {
    if (itemCount <= 1) return 1;
    if (singleRow) return itemCount;
    final cap = maxColumns ??
        switch (width) {
          >= 840 => 6,
          >= 600 => 4,
          _ => 4,
        };
    if (itemCount <= cap) return itemCount;
    return cap;
  }

  @override
  Widget build(BuildContext context) {
    if (itemCount == 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = columnsForWidth(
          constraints.maxWidth,
          itemCount,
          maxColumns: maxColumns,
          singleRow: singleRow,
        );
        final rowCount = (itemCount + cols - 1) ~/ cols;

        return Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var row = 0; row < rowCount; row++) ...[
                if (row > 0) SizedBox(height: runSpacing),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var col = 0; col < cols; col++) ...[
                      if (col > 0) SizedBox(width: spacing),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final index = row * cols + col;
                            if (index >= itemCount) {
                              return const SizedBox.shrink();
                            }
                            return itemBuilder(context, index);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// [FilterChip]을 셀 너비에 맞게 중앙 정렬한다.
class ExpandedFilterChip extends StatelessWidget {
  const ExpandedFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.showCheckmark = false,
    this.visualDensity = VisualDensity.compact,
    this.labelStyle,
    this.backgroundColor,
    this.selectedColor,
    this.side,
    this.avatar,
    this.pressElevation = 0,
    this.elevation = 0,
    this.compact = false,
  });

  final Widget label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final bool showCheckmark;
  final VisualDensity visualDensity;
  final TextStyle? labelStyle;
  final Color? backgroundColor;
  final Color? selectedColor;
  final BorderSide? side;
  final Widget? avatar;
  final double pressElevation;
  final double elevation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilterChip(
        label: SizedBox(
          width: double.infinity,
          child: DefaultTextStyle.merge(
            style: labelStyle ?? const TextStyle(),
            textAlign: TextAlign.center,
            child: label,
          ),
        ),
        selected: selected,
        showCheckmark: showCheckmark,
        visualDensity: visualDensity,
        onSelected: onSelected,
        labelStyle: labelStyle,
        backgroundColor: backgroundColor,
        selectedColor: selectedColor,
        side: side,
        avatar: avatar,
        pressElevation: pressElevation,
        elevation: elevation,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 2 : 0,
        ),
        labelPadding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 4,
          vertical: compact ? 0 : 2,
        ),
      ),
    );
  }
}

/// SegmentedButton을 가로 전체에 균등 배치한다.
class FullWidthSegmentedButton<T extends Object> extends StatelessWidget {
  const FullWidthSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.style,
    this.showSelectedIcon = false,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final void Function(Set<T>) onSelectionChanged;
  final ButtonStyle? style;
  final bool showSelectedIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        segments: segments,
        selected: selected,
        onSelectionChanged: onSelectionChanged,
        showSelectedIcon: showSelectedIcon,
        style: (style ?? const ButtonStyle()).merge(
          const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}
