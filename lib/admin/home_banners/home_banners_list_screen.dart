import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../widgets/admin_buttons.dart';
import '../widgets/admin_list_scaffold.dart';

final homeBannersAdminProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) async {
    final res = await Supabase.instance.client
        .from('home_banners')
        .select('id, title, image_url, type, target_route, visible_from, visible_until, is_active, display_order')
        .order('display_order');
    return List<Map<String, dynamic>>.from(res);
  },
);

class HomeBannersListScreen extends ConsumerWidget {
  const HomeBannersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bannersAsync = ref.watch(homeBannersAdminProvider);

    return AdminListScaffold(
      title: 'Home Banners',
      subtitle: 'Full-image carousel. Creative + CTA live in the image.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AdminPrimaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'Add banner',
            onPressed: () => context.go('/admin/home-banners/new'),
          ),
        ),
      ],
      body: bannersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: AppTextStyles.body(context)),
        ),
        data: (banners) {
          if (banners.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    PhosphorIconsRegular.image,
                    size: 48,
                    color: AppColors.lightTextSecondary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No banners yet',
                    style: AppTextStyles.h3(context),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Add your first promotional banner.',
                    style: AppTextStyles.body(context),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            buildDefaultDragHandles: false,
            header: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Align(
                alignment: Alignment.centerRight,
                child: AdminPrimaryButton(
                  icon: PhosphorIconsRegular.plus,
                  label: 'Add banner',
                  onPressed: () => context.go('/admin/home-banners/new'),
                ),
              ),
            ),
            itemCount: banners.length,
            onReorder: (oldIndex, newIndex) async {
              if (oldIndex < newIndex) newIndex--;
              final moved = banners.removeAt(oldIndex);
              banners.insert(newIndex, moved);

              for (var i = 0; i < banners.length; i++) {
                await Supabase.instance.client
                    .from('home_banners')
                    .update({'display_order': i})
                    .eq('id', banners[i]['id'] as String);
              }
              ref.invalidate(homeBannersAdminProvider);
            },
            itemBuilder: (_, i) {
              final b = banners[i];
              final id = b['id'] as String;
              final isActive = b['is_active'] as bool? ?? false;
              final title = b['title'] as String? ?? '';
              final imageUrl = b['image_url'] as String? ?? '';
              final type = b['type'] as String? ?? 'promo';
              final route = b['target_route'] as String?;
              final from = b['visible_from'] as String?;
              final until = b['visible_until'] as String?;

              final typeColor = switch (type) {
                'urgent' => AppColors.adminRed,
                'info' => AppColors.ellieBlue,
                _ => AppColors.gold,
              };

              return ReorderableDragStartListener(
                key: ValueKey(id),
                index: i,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isActive ? AppColors.lightBorder : AppColors.lightBorder.withValues(alpha: 0.5),
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.go('/admin/home-banners/$id/edit'),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Thumbnail
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    width: 96,
                                    height: 64,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => _placeholder,
                                  )
                                : _placeholder,
                          ),
                          const SizedBox(width: 12),

                          // Text
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: AppTextStyles.body(context)
                                            .copyWith(fontWeight: FontWeight.w700),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  route == null || route.isEmpty
                                      ? 'Static image'
                                      : 'Taps to $route',
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _scheduleLabel(from, until),
                                  style: AppTextStyles.caption(
                                    context,
                                    color: AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Tap count
                          FutureBuilder<int>(
                            future: _tapCount(id),
                            builder: (_, snap) {
                              final count = snap.data ?? 0;
                              return Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '$count taps',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                backgroundColor: AppColors.lightBorder,
                                side: BorderSide.none,
                              );
                            },
                          ),
                          const SizedBox(width: 8),

                          // Active toggle
                          Switch(
                            value: isActive,
                            onChanged: (v) async {
                              await Supabase.instance.client
                                  .from('home_banners')
                                  .update({'is_active': v})
                                  .eq('id', id);
                              ref.invalidate(homeBannersAdminProvider);
                            },
                          ),

                          // Drag handle
                          const Icon(
                            PhosphorIconsRegular.dotsSixVertical,
                            color: AppColors.lightTextSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget get _placeholder => Container(
        width: 96,
        height: 64,
        color: AppColors.lightBorder,
        child: const Icon(
          PhosphorIconsRegular.image,
          color: AppColors.lightTextSecondary,
        ),
      );

  String _scheduleLabel(String? from, String? until) {
    final parts = <String>[];
    if (from != null) {
      final dt = DateTime.tryParse(from);
      if (dt != null) parts.add('From ${_fmt(dt)}');
    }
    if (until != null) {
      final dt = DateTime.tryParse(until);
      if (dt != null) parts.add('Until ${_fmt(dt)}');
    }
    return parts.isEmpty ? 'Always visible' : parts.join(' · ');
  }

  String _fmt(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<int> _tapCount(String bannerId) async {
    try {
      final res = await Supabase.instance.client
          .rpc<int>('admin_home_banner_tap_count', params: {'p_banner_id': bannerId});
      return res;
    } catch (e) {
      return 0;
    }
  }
}
