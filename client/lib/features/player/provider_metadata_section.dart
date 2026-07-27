import 'package:flutter/material.dart';

import '../../api/models/item.dart';

/// Generic, schema-driven renderer for per-source provider metadata. Each
/// source on an Item may carry a free-form `metadata` blob; this widget walks
/// them and renders known fields nicely (YouTube's description/viewCount/
/// uploadDate/channelName today) with a key/value fallback for unknown
/// providers. Empty sources hide entirely — the section never blocks the
/// player on missing data ("optimistic").
class ProviderMetadataSection extends StatelessWidget {
  const ProviderMetadataSection({
    super.key,
    required this.item,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final Item item;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[];
    for (final source in item.sources) {
      final meta = source.metadata;
      if (meta == null || meta.isEmpty) continue;
      cards.add(_SourceMetaCard(source: source, meta: meta));
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            cards[i],
          ],
        ],
      ),
    );
  }
}

/// One card per source. Returns null if there's nothing meaningful to render.
class _SourceMetaCard extends StatelessWidget {
  const _SourceMetaCard({required this.source, required this.meta});
  final Source source;
  final Map<String, dynamic> meta;

  static const _schemas = <String, List<_MetaField>>{
    'youtube': [
      _MetaField(key: 'description', label: 'About', type: _MetaType.longtext),
      _MetaField(key: 'viewCount', label: 'Views', type: _MetaType.count),
      _MetaField(key: 'uploadDate', label: 'Uploaded', type: _MetaType.date),
      _MetaField(key: 'channelName', label: 'Channel', type: _MetaType.text),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final schema = _schemas[source.provider] ?? const [];
    final rendered = <Widget>[];

    for (final f in schema) {
      final v = meta[f.key];
      if (v == null) continue;
      final w = _renderField(context, f, v);
      if (w != null) rendered.add(w);
    }

    // Schema didn't cover any keys (or no schema) → render everything as
    // key/value rows so unknown providers still surface their data.
    if (rendered.isEmpty) {
      final knownKeys = schema.map((f) => f.key).toSet();
      for (final e in meta.entries) {
        if (knownKeys.contains(e.key)) continue;
        rendered.add(_KeyValueRow(label: e.key, value: '${e.value}'));
      }
    }

    if (rendered.isEmpty) return const SizedBox.shrink();

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProviderHeader(provider: source.provider),
            const SizedBox(height: 10),
            for (var i = 0; i < rendered.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              rendered[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget? _renderField(BuildContext context, _MetaField f, Object value) {
    switch (f.type) {
      case _MetaType.longtext:
        final s = value is String ? value : '$value';
        if (s.isEmpty) return null;
        return _ExpandableText(text: s);
      case _MetaType.count:
        final n = value is num ? value.toDouble() : double.tryParse('$value');
        if (n == null || n <= 0) return null;
        return _KeyValueRow(label: f.label, value: _formatCount(n));
      case _MetaType.date:
        final s = value is String ? value : '$value';
        final formatted = _formatDate(s);
        if (formatted == null) return null;
        return _KeyValueRow(label: f.label, value: formatted);
      case _MetaType.text:
        final s = value is String ? value : '$value';
        if (s.isEmpty) return null;
        return _KeyValueRow(label: f.label, value: s);
    }
  }

  static String _formatCount(double n) {
    if (n >= 1e9) return '${(n / 1e9).toStringAsFixed(1)}B';
    if (n >= 1e6) return '${(n / 1e6).toStringAsFixed(1)}M';
    if (n >= 1e3) return '${(n / 1e3).toStringAsFixed(1)}K';
    return n.toStringAsFixed(0);
  }

  // YouTube uploadDate is "YYYYMMDD". Anything else → null (hide).
  static String? _formatDate(String raw) {
    if (raw.length != 8 || int.tryParse(raw) == null) return null;
    final y = raw.substring(0, 4);
    final m = raw.substring(4, 6);
    final d = raw.substring(6, 8);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final mi = int.parse(m);
    if (mi < 1 || mi > 12) return null;
    return '${months[mi - 1]} $d, $y';
  }
}

class _ProviderHeader extends StatelessWidget {
  const _ProviderHeader({required this.provider});
  final String provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = provider.isEmpty
        ? 'Source'
        : provider[0].toUpperCase() + provider.substring(1);
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            label.isEmpty ? '?' : label.characters.first.toUpperCase(),
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$label  ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});
  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final collapsed = !_expanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Text(
            widget.text,
            maxLines: collapsed ? 3 : null,
            overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.visible,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  _expanded ? 'Show less' : 'Show more',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _MetaType { text, longtext, count, date }

class _MetaField {
  const _MetaField({
    required this.key,
    required this.label,
    required this.type,
  });
  final String key;
  final String label;
  final _MetaType type;
}
