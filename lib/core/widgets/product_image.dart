import 'package:flexpos/features/catalog/data/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders a product image from the private Supabase product-images bucket.
///
/// Product image paths are deliberately kept private in the database. This
/// widget resolves a short-lived signed URL and always provides a stable
/// placeholder/error state so product lists never fail when an image is
/// missing, expired, or still loading.
class ProductImage extends ConsumerStatefulWidget {
  const ProductImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = 12,
    this.backgroundColor,
    this.iconSize,
  });

  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double borderRadius;
  final Color? backgroundColor;
  final double? iconSize;

  @override
  ConsumerState<ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends ConsumerState<ProductImage> {
  String? _url;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ProductImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) _resolve();
  }

  Future<void> _resolve() async {
    final path = widget.imagePath?.trim();
    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _url = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _url = null;
      _loading = true;
    });
    try {
      final url = await ref
          .read(catalogRepositoryProvider)
          .createSignedProductImageUrl(path);
      if (mounted && widget.imagePath?.trim() == path) {
        setState(() {
          _url = url;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && widget.imagePath?.trim() == path) {
        setState(() {
          _url = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final background =
        widget.backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: ColoredBox(
          color: background,
          child: _url == null
              ? Center(
                  child: _loading
                      ? SizedBox.square(
                          dimension: (widget.iconSize ?? 24) * .7,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Icon(
                          Icons.inventory_2_outlined,
                          size: widget.iconSize,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                )
              : Image.network(
                  _url!,
                  fit: widget.fit,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    size: widget.iconSize,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
        ),
      ),
    );
  }
}
