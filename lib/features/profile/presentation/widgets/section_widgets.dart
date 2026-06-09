import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

/// Standard scaffold for a profile section editor.
class SectionScaffold extends StatelessWidget {
  const SectionScaffold({super.key, required this.title, required this.child, this.onAdd, this.addLabel = 'Add'});
  final String title;
  final Widget child;
  final VoidCallback? onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      floatingActionButton: onAdd == null
          ? null
          : FloatingActionButton.extended(
              onPressed: onAdd,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
      body: child,
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.title, this.subtitle, this.icon, this.onDelete});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.check_circle, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class EmptySection extends StatelessWidget {
  const EmptySection({super.key, required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}

/// Shows a modal bottom sheet form and returns true if saved.
Future<bool?> showFormSheet(BuildContext context, {required String title, required List<Widget> Function(StateSetter) fields, required Future<void> Function() onSave}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) {
      bool saving = false;
      return StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              ...fields(setSheet),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setSheet(() => saving = true);
                        try {
                          await onSave();
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (e) {
                          setSheet(() => saving = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$e')));
                          }
                        }
                      },
                child: saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
