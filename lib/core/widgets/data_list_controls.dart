import 'package:flutter/material.dart';

/// Shared controls for data-heavy screens: search, deterministic sorting,
/// paging, and optional bulk selection.
class DataListControls extends StatefulWidget {
  const DataListControls({
    required this.searchLabel,
    required this.onSearchChanged,
    required this.sortOptions,
    required this.sortValue,
    required this.onSortChanged,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.query = '',
    this.selectedCount = 0,
    this.totalCount,
    this.allSelected = false,
    this.onSelectAll,
    this.onClearSelection,
    this.bulkActions = const <Widget>[],
    super.key,
  });

  final String searchLabel;
  final ValueChanged<String> onSearchChanged;
  final List<DataListSortOption> sortOptions;
  final String sortValue;
  final ValueChanged<String> onSortChanged;
  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final String query;
  final int selectedCount;
  final int? totalCount;
  final bool allSelected;
  final ValueChanged<bool?>? onSelectAll;
  final VoidCallback? onClearSelection;
  final List<Widget> bulkActions;

  @override
  State<DataListControls> createState() => _DataListControlsState();
}

class _DataListControlsState extends State<DataListControls> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant DataListControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query &&
        _searchController.text != widget.query) {
      _searchController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchLabel = widget.searchLabel;
    final onSearchChanged = widget.onSearchChanged;
    final sortOptions = widget.sortOptions;
    final sortValue = widget.sortValue;
    final onSortChanged = widget.onSortChanged;
    final page = widget.page;
    final pageCount = widget.pageCount;
    final onPageChanged = widget.onPageChanged;
    final query = widget.query;
    final selectedCount = widget.selectedCount;
    final totalCount = widget.totalCount;
    final allSelected = widget.allSelected;
    final onSelectAll = widget.onSelectAll;
    final onClearSelection = widget.onClearSelection;
    final bulkActions = widget.bulkActions;
    final theme = Theme.of(context);
    final hasSelection = selectedCount > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Keep every control inside the available viewport. The old fixed
        // widths caused the sort field (and its arrow) to overflow on narrow
        // browser/mobile layouts instead of wrapping to the next line.
        final availableWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 360.0;
        final searchWidth = availableWidth < 360
            ? availableWidth
            : 360.0;
        final sortWidth = availableWidth < 220 ? availableWidth : 220.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: searchWidth,
                  child: TextField(
                    controller: _searchController,
                    onChanged: onSearchChanged,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      labelText: searchLabel,
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () => onSearchChanged(''),
                              icon: const Icon(Icons.clear_rounded),
                            ),
                    ),
                  ),
                ),
                if (sortOptions.isNotEmpty)
                  SizedBox(
                    width: sortWidth,
                    child: DropdownButtonFormField<String>(
                      initialValue: sortValue,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sort by',
                        prefixIcon: Icon(Icons.sort_rounded),
                      ),
                      items: [
                        for (final option in sortOptions)
                          DropdownMenuItem(
                            value: option.value,
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onSortChanged(value);
                      },
                    ),
                  ),
                if (onSelectAll != null)
                  FilterChip(
                    selected: allSelected,
                    onSelected: onSelectAll,
                    avatar: Icon(
                      allSelected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded,
                    ),
                    label: Text(
                      hasSelection ? '$selectedCount selected' : 'Select all',
                    ),
                  ),
                if (hasSelection && onClearSelection != null)
                  OutlinedButton.icon(
                    onPressed: onClearSelection,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Clear selection'),
                  ),
                if (hasSelection) ...bulkActions,
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    totalCount == null
                        ? 'Page ${page + 1} of $pageCount'
                        : '$totalCount result${totalCount == 1 ? '' : 's'} · page ${page + 1} of $pageCount',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: page + 1 < pageCount
                      ? () => onPageChanged(page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class DataListSortOption {
  const DataListSortOption(this.value, this.label);

  final String value;
  final String label;
}

List<T> pageItems<T>(List<T> items, int page, {int pageSize = 25}) {
  final start = page * pageSize;
  if (start >= items.length) return const <Never>[] as List<T>;
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}

int pageCountFor(int itemCount, {int pageSize = 25}) =>
    itemCount == 0 ? 1 : (itemCount / pageSize).ceil();
