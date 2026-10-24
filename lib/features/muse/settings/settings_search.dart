// 穿云 1.5.0 #101 - 设置 search sheet: type a word, tap a result to open the page it lives on.
// Part of 穿云 (GPLv3).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hiddify/features/muse/logic/settings_index.dart';
import 'package:hiddify/features/muse/widget/muse_tokens.dart';

Future<MuseSettingEntry?> showMuseSettingsSearch(BuildContext context, {bool? android, bool? windows}) =>
    showModalBottomSheet<MuseSettingEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => MuseSettingsSearch(android: android ?? Platform.isAndroid, windows: windows ?? Platform.isWindows),
    );

class MuseSettingsSearch extends StatefulWidget {
  const MuseSettingsSearch({super.key, required this.android, required this.windows});

  final bool android;
  final bool windows;

  @override
  State<MuseSettingsSearch> createState() => _MuseSettingsSearchState();
}

class _MuseSettingsSearchState extends State<MuseSettingsSearch> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final mt = MuseTheme.of(context);
    final hits = museSearchSettings(_query, android: widget.android, windows: widget.windows);
    final height = MediaQuery.sizeOf(context).height * 0.7;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
              child: TextField(
                key: const ValueKey('settings_search_field'),
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search_outlined), hintText: '搜索设置，如 DNS、去广告、备份'),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: MuseSpace.s8),
            Expanded(
              child: _query.trim().isNotEmpty && hits.isEmpty
                  ? Center(child: Text('没有找到相关设置', style: MuseType.caption(context)))
                  : ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (c, i) => ListTile(
                        key: ValueKey('settings_hit_$i'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: MuseSpace.s16),
                        title: Text(hits[i].title, style: MuseType.body(context)),
                        subtitle: Text(hits[i].page.path, style: MuseType.caption(context).copyWith(color: mt.text2)),
                        trailing: Icon(Icons.chevron_right_outlined, size: MuseIconSize.small, color: mt.text3),
                        onTap: () => Navigator.of(context).pop(hits[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
