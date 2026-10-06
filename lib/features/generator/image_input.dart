/// 图片输入：跨端统一入口。
///
/// 各端能力不同，这里做一次归一：
///   * 移动端 / Web：调用系统相册或相机（`image_picker`）
///   * 桌面端：文件选择器（`file_selector`）
///   * 桌面端额外支持**拖放**（Flutter 的 DragTarget，无需插件）
///   * 所有端都支持**粘贴**（`pasteboard` 读剪贴板里的图片）
///
/// 之所以不引第三方"万能选图"包：各平台的官方插件已经很稳，
/// 多余的抽象层反而会在某端出问题。
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../theme/tokens.dart';
import '../../theme/typography.dart';

/// 选到的图片。保留原始字节，因为要直接发给模型。
@immutable
class PickedImage {
  const PickedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  int get sizeBytes => bytes.length;

  String get sizeLabel {
    final kb = bytes.length / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// 从系统选择图片。
Future<PickedImage?> pickImageFromSystem() async {
  // 桌面平台用文件选择器；移动与 Web 用 image_picker（能直接调相机）
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    const group = XTypeGroup(
      label: '图片',
      extensions: <String>['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImage(bytes: bytes, name: file.name);
  }

  final picker = ImagePicker();
  final x = await picker.pickImage(source: ImageSource.gallery);
  if (x == null) return null;
  final bytes = await x.readAsBytes();
  return PickedImage(bytes: bytes, name: x.name);
}

/// 读取剪贴板里的图片。返回 null 表示剪贴板没有图片。
///
/// 这个入口很关键：玩家看到阵容图多半是**截图**，截图后直接粘贴
/// 比"先存文件再选文件"少两步。
Future<PickedImage?> pickImageFromClipboard() async {
  try {
    final bytes = await Pasteboard.image;
    if (bytes == null || bytes.isEmpty) return null;
    return PickedImage(bytes: bytes, name: '剪贴板图片');
  } catch (_) {
    // 某些平台（如部分 Linux）不支持读剪贴板图片，静默返回 null 由调用方提示
    return null;
  }
}

/// 图片放置区。既显示已选图片，也接受拖放。
class ImageDropZone extends StatefulWidget {
  const ImageDropZone({
    super.key,
    required this.image,
    required this.onPicked,
    required this.onCleared,
    this.busy = false,
  });

  final PickedImage? image;
  final ValueChanged<PickedImage> onPicked;
  final VoidCallback onCleared;
  final bool busy;

  @override
  State<ImageDropZone> createState() => _ImageDropZoneState();
}

class _ImageDropZoneState extends State<ImageDropZone> {
  bool _hovering = false;

  Future<void> _handleDrop(XFile file) async {
    final bytes = await file.readAsBytes();
    widget.onPicked(PickedImage(bytes: bytes, name: file.name));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final image = widget.image;

    return DragTarget<XFile>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _handleDrop(d.data),
      onMove: (_) => setState(() => _hovering = true),
      onLeave: (_) => setState(() => _hovering = false),
      builder: (context, candidate, rejected) {
        return AnimatedContainer(
          duration: AppMotion.instant,
          decoration: BoxDecoration(
            color: _hovering ? c.accentSubtle : c.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(
              color: _hovering ? c.accent : c.separator,
              width: _hovering ? 1.5 : 1,
            ),
          ),
          child: image == null
              ? _empty(context)
              : _preview(context, image),
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final c = context.colors;
    // 空状态要"构图完整 + 告知如何填充"，不是一句"暂无图片"
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xxl,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: c.accentSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.add_photo_alternate_outlined,
                size: 26, color: c.accent),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('放一张阵容截图', style: context.texts.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '可以直接把截图拖到这里，或者粘贴、从相册选择',
            style: TextStyle(
              fontSize: AppType.sSubhead,
              color: c.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: widget.busy ? null : _pick,
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('选择图片'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : _paste,
                icon: const Icon(Icons.content_paste_outlined, size: 18),
                label: const Text('粘贴'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context, PickedImage image) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: AppRadii.thumbR,
            child: Image.memory(
              image.bytes,
              width: double.infinity,
              fit: BoxFit.contain,
              // 限制高度，避免长图把整页顶出去
              height: 280,
              errorBuilder: (context, error, stack) => Container(
                height: 120,
                alignment: Alignment.center,
                color: c.bgGrouped,
                child: Text(
                  '这张图片无法预览（格式或大小问题）',
                  style: TextStyle(
                    fontSize: AppType.sFootnote,
                    color: c.textSecondary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${image.name}  ·  ${image.sizeLabel}',
                  style: TextStyle(
                    fontSize: AppType.sFootnote,
                    color: c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: widget.busy ? null : widget.onCleared,
                icon: const Icon(Icons.close, size: 16),
                label: const Text('换一张'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pick() async {
    final img = await pickImageFromSystem();
    if (img != null) widget.onPicked(img);
  }

  Future<void> _paste() async {
    final img = await pickImageFromClipboard();
    if (img != null) {
      widget.onPicked(img);
      return;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪贴板里没有图片。先截个图再试一次。')),
      );
    }
  }
}
