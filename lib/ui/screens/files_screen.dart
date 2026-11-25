import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../../blocs/deck_bloc.dart';
import '../../blocs/files_cubit.dart';
import '../../blocs/notice_cubit.dart';
import '../palette.dart';
import '../widgets.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});
  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  String? _source;
  final _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<FilesCubit>().loadCameras();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final cubit = context.read<FilesCubit>();
    final mons = context.select((DeckBloc b) => b.state.frame.hypr.monitors);
    return BlocBuilder<FilesCubit, FilesState>(
      builder: (context, s) {
        final sources = {
          for (final m in mons) m.name: m.name,
          for (final c in s.cameras) 'cam:${c.node}': c.name,
        };
        final src = sources.containsKey(_source)
            ? _source
            : sources.keys.firstOrNull;
        return PageBody(
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Capture'),
                  Seg<String>(
                    items: sources,
                    value: src,
                    onChanged: (v) => setState(() => _source = v),
                  ),
                  const SizedBox(height: 10),
                  DeckButton(
                    'Grab',
                    icon: Icons.camera_alt,
                    tone: Tone.primary,
                    busy: s.grabbing,
                    onTap: src == null ? null : () => cubit.grab(src),
                  ),
                  if (s.shot != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          fullscreenDialog: true,
                          builder: (_) => _Viewer(s.shot!),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(s.shot!, gaplessPlayback: true),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DeckButton(
                      'Save to phone',
                      icon: Icons.download,
                      onTap: cubit.saveShot,
                    ),
                  ],
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Send files to the rig'),
                  Text(
                    'They land in ~/hyprhand-drop.',
                    style: TextStyle(fontSize: 12, color: p.onVar),
                  ),
                  const SizedBox(height: 10),
                  DeckButton(
                    'Choose files',
                    icon: Icons.upload_file,
                    onTap: cubit.pickAndUpload,
                  ),
                  for (final u in s.uploads) _UploadRow(u),
                ],
              ),
            ),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Clipboard'),
                  DeckButton(
                    'Get from rig',
                    icon: Icons.content_paste_go,
                    busy: s.clipBusy,
                    onTap: cubit.receiveClip,
                  ),
                  if (s.clip != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: p.low,
                        border: Border.all(color: p.outline),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          s.clip!.isEmpty
                              ? 'The rig clipboard is empty'
                              : s.clip!,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    DeckButton(
                      'Copy to phone',
                      icon: Icons.copy,
                      onTap: s.clip!.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: s.clip!));
                              context.read<NoticeCubit>().info(
                                'Copied to phone',
                              );
                            },
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextField(
                    controller: _text,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      hintText: 'Text for the rig…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DeckButton(
                          'Paste',
                          icon: Icons.paste,
                          onTap: () async {
                            final d = await Clipboard.getData('text/plain');
                            _text.text = d?.text ?? _text.text;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DeckButton(
                          'Send',
                          tone: Tone.primary,
                          icon: Icons.send,
                          onTap: () async {
                            if (_text.text.isEmpty) return;
                            if (await cubit.sendClip(_text.text)) _text.clear();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _UploadRow extends StatelessWidget {
  const _UploadRow(this.u);
  final UploadItem u;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final mb = (u.file.size / 1048576).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${u.file.name} · $mb MB',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          if (u.error != null)
            Text(
              u.error!,
              style: const TextStyle(fontSize: 12, color: Palette.danger),
            )
          else if (u.result != null)
            Text(u.result!, style: TextStyle(fontSize: 12, color: p.primary))
          else
            LinearProgressIndicator(
              value: u.progress == 0 ? null : u.progress,
              backgroundColor: p.high,
            ),
        ],
      ),
    );
  }
}

class _Viewer extends StatefulWidget {
  const _Viewer(this.png);
  final Uint8List png;
  @override
  State<_Viewer> createState() => _ViewerState();
}

/// Fits the shot to the screen; pinch or double-tap to zoom, drag to pan.
class _ViewerState extends State<_Viewer> with SingleTickerProviderStateMixin {
  final _zoom = TransformationController();
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addListener(() => _zoom.value = _tween!.evaluate(_anim));
  Matrix4Tween? _tween;
  Offset _tap = Offset.zero;

  void _toggle() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    final to = zoomed
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(-_tap.dx * 2, -_tap.dy * 2, 0, 1)
            ..scaleByDouble(3, 3, 1, 1));
    _tween = Matrix4Tween(begin: _zoom.value, end: to);
    _anim.forward(from: 0);
  }

  @override
  void dispose() {
    _anim.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          onDoubleTapDown: (d) => _tap = d.localPosition,
          onDoubleTap: _toggle,
          child: InteractiveViewer(
            transformationController: _zoom,
            maxScale: 8,
            child: Image.memory(
              widget.png,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Semantics(
                button: true,
                label: 'Close',
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
