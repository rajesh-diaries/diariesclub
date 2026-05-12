import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/utils/currency.dart';
import '../widgets/admin_buttons.dart';
import '../widgets/admin_list_scaffold.dart';

/// Birthday packages CRUD list (Module 2.7). Card grid because there
/// are typically only 3–4 tiers and the visual emphasis is on cover
/// photo + tier name + price.
class PackagesListScreen extends ConsumerWidget {
  const PackagesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(packagesAdminListProvider);
    return AdminListScaffold(
      title: 'Birthday packages',
      subtitle:
          'Tier, photo, price, capacity, status. Each package has menu options + non-food offerings + PDF download.',
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: AdminPrimaryButton(
            icon: PhosphorIconsRegular.plus,
            label: 'New package',
            onPressed: () => context.go('/admin/packages/new'),
          ),
        ),
      ],
      isEmpty: async.maybeWhen(
        data: (rows) => rows.isEmpty,
        orElse: () => false,
      ),
      emptyState: const AdminListEmptyState(
        icon: PhosphorIconsRegular.cake,
        message: 'No packages yet.',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (rows) => SingleChildScrollView(
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final r in rows) _PackageCard(row: r, ref: ref),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final WidgetRef ref;
  const _PackageCard({required this.row, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cover = row['cover_image_url'] as String?;
    final isActive = (row['is_active'] as bool?) ?? true;
    final pdfUrl = row['pdf_url'] as String?;

    return SizedBox(
      width: 320,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.lightSurface,
          border: Border.all(color: AppColors.lightBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: cover == null || cover.isEmpty
                  ? Container(
                      color: AppColors.gold.withValues(alpha: 0.18),
                      alignment: Alignment.center,
                      child: const Icon(PhosphorIconsFill.cake,
                          size: 56, color: AppColors.gold),
                    )
                  : Image.network(cover, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.gold.withValues(alpha: 0.18),
                      )),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (row['name'] as String?) ?? '—',
                          style: AppTextStyles.h3(context).copyWith(
                            decoration: isActive ? null : TextDecoration.lineThrough,
                            color: isActive ? null : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                      _ActiveBadge(isActive: isActive),
                    ],
                  ),
                  Text(
                    (row['tier'] as String?) ?? '—',
                    style: AppTextStyles.caption(
                      context, color: AppColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        Money.fromPaise((row['price_paise'] as int?) ?? 0),
                        style: AppTextStyles.h2(context, color: AppColors.gold),
                      ),
                      const Spacer(),
                      Text(
                        '${row['max_kids'] ?? 0} kids · ${row['max_adults'] ?? 0} adults',
                        style: AppTextStyles.caption(
                          context, color: AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _Chip(
                        icon: pdfUrl != null
                            ? PhosphorIconsFill.filePdf
                            : PhosphorIconsRegular.warningCircle,
                        label: pdfUrl != null ? 'PDF uploaded' : 'No PDF',
                        color: pdfUrl != null
                            ? AppColors.activeGreen
                            : AppColors.lightTextSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(PhosphorIconsRegular.pencilSimple,
                              size: 14),
                          label: const Text('Edit'),
                          onPressed: () =>
                              context.go('/admin/packages/${row['id']}/edit'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: Icon(
                            pdfUrl == null
                                ? PhosphorIconsRegular.upload
                                : PhosphorIconsRegular.arrowsClockwise,
                            size: 14,
                          ),
                          label: Text(pdfUrl == null ? 'Upload PDF' : 'Replace PDF'),
                          onPressed: () =>
                              _pickAndUploadPdf(context, row['id'] as String),
                        ),
                      ),
                    ],
                  ),
                  if (pdfUrl != null) ...[
                    const SizedBox(height: 6),
                    TextButton.icon(
                      icon: const Icon(PhosphorIconsRegular.arrowSquareOut,
                          size: 14),
                      label: const Text('Open current PDF'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => launchUrl(Uri.parse(pdfUrl)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _bucket = 'package-pdfs';

  Future<void> _pickAndUploadPdf(
      BuildContext context, String packageId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't read that file.")),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Uploading PDF…')),
    );

    try {
      final path =
          '$packageId/menu-${DateTime.now().millisecondsSinceEpoch}.pdf';
      await Supabase.instance.client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      final publicUrl =
          Supabase.instance.client.storage.from(_bucket).getPublicUrl(path);

      await Supabase.instance.client.rpc<dynamic>(
        'admin_package_set_pdf_url',
        params: {'p_package_id': packageId, 'p_pdf_url': publicUrl},
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF uploaded — customers can download now.')),
      );
      ref.invalidate(packagesAdminListProvider);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't upload PDF: $e")),
      );
    }
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip({required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption(context, color: color)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  final bool isActive;
  const _ActiveBadge({required this.isActive});
  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.activeGreen : AppColors.lightTextSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Hidden',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

final packagesAdminListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('birthday_packages')
      .select(
        'id, name, tier, cover_image_url, price_paise, deposit_paise, '
        'duration_hours, max_kids, max_adults, is_active, sort_order, pdf_url',
      )
      .order('sort_order', ascending: true);
  return List<Map<String, dynamic>>.from(rows);
});
