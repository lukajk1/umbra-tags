import 'package:flutter/material.dart';
import '../ml/similarity_controller.dart';

class SimilarityStatus extends StatelessWidget {
  const SimilarityStatus({super.key, required this.controller});
  final SimilarityController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Row(
      children: [
        Flexible(
          child: Tooltip(
            message: controller.error ?? controller.summary,
            child: TextButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _IndexDetails(controller: controller),
              ),
              icon: Icon(
                controller.error == null
                    ? Icons.image_search
                    : Icons.warning_amber,
                size: 18,
              ),
              label: Text(
                controller.summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: controller.enabled && controller.error == null
              ? 'Pause indexing after this image'
              : 'Resume indexing',
          onPressed: () => controller.setEnabled(
            !controller.enabled || controller.error != null,
          ),
          icon: Icon(
            controller.enabled && controller.error == null
                ? Icons.pause
                : Icons.play_arrow,
            size: 18,
          ),
        ),
      ],
    ),
  );
}

class _IndexDetails extends StatelessWidget {
  const _IndexDetails({required this.controller});
  final SimilarityController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Similarity index'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(controller.summary),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: controller.total == 0
                    ? 0
                    : controller.ready / controller.total,
              ),
              const SizedBox(height: 12),
              const Text(
                'Indexes non-archived, available images in this library. New imports join the queue automatically. Your images stay on this computer.',
              ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(controller.error!),
                ),
              if (controller.failed > 0)
                FutureBuilder<List<Map<String, Object?>>>(
                  future: controller.failures(),
                  builder: (context, snapshot) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (snapshot.data ?? [])
                        .map(
                          (row) => Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${row['original_filename']}: ${row['error']}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (controller.failed > 0 || controller.error != null)
          TextButton(
            onPressed: () async {
              await controller.retryFailures();
            },
            child: const Text('Retry failed'),
          ),
        TextButton(
          onPressed: () => controller.setEnabled(
            !controller.enabled || controller.error != null,
          ),
          child: Text(
            controller.enabled && controller.error == null ? 'Pause' : 'Resume',
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
