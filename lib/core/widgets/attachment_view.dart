import 'package:flutter/material.dart';

import '../network/file_urls.dart';
import '../network/session.dart';
import '../theme/app_colors.dart';

/// Thumbnail for one image attachment; tapping opens it full screen. Used
/// wherever a saved answer is shown read-only — an approver reviewing a
/// site photo needs to actually see it, not read its URL.
class AttachmentImage extends StatelessWidget {
  const AttachmentImage({super.key, required this.url, this.size = 110});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _AttachmentViewerPage(url: url)),
      ),
      child: Container(
        height: size,
        width: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.light,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.network(
          absoluteFileUrl(url, stream: true),
          headers: sdk.api.requestHeaders,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
          errorBuilder: (_, _, _) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              size: 26,
              color: AppColors.slate,
            ),
          ),
        ),
      ),
    );
  }
}

/// One non-image attachment: paperclip + the original filename.
class AttachmentFileRow extends StatelessWidget {
  const AttachmentFileRow({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.light,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_file, size: 16, color: AppColors.navy),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              fileNameFromUrl(url),
              style: const TextStyle(fontSize: 13, color: AppColors.text),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen, pinch-zoomable view of one image attachment.
class _AttachmentViewerPage extends StatelessWidget {
  const _AttachmentViewerPage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          fileNameFromUrl(url),
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Image.network(
            absoluteFileUrl(url, stream: true),
            headers: sdk.api.requestHeaders,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Padding(
              padding: EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                "This attachment couldn't be loaded.",
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
