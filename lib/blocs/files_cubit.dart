import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

import '../data/hypr_client.dart';
import '../data/models.dart';
import '../data/native.dart';
import 'notice_cubit.dart';

class FilesState extends Equatable {
  const FilesState({
    this.cameras = const [],
    this.grabbing = false,
    this.shot,
    this.shotName = '',
    this.uploads = const [],
    this.clip,
    this.clipBusy = false,
  });
  final List<RigCamera> cameras;
  final bool grabbing, clipBusy;
  final Uint8List? shot;
  final String shotName;
  final List<UploadItem> uploads;
  final String? clip;

  FilesState copyWith({
    List<RigCamera>? cameras,
    bool? grabbing,
    Uint8List? shot,
    String? shotName,
    List<UploadItem>? uploads,
    String? clip,
    bool? clipBusy,
  }) => FilesState(
    cameras: cameras ?? this.cameras,
    grabbing: grabbing ?? this.grabbing,
    shot: shot ?? this.shot,
    shotName: shotName ?? this.shotName,
    uploads: uploads ?? this.uploads,
    clip: clip ?? this.clip,
    clipBusy: clipBusy ?? this.clipBusy,
  );
  @override
  List<Object?> get props => [
    cameras,
    grabbing,
    identityHashCode(shot),
    shotName,
    uploads,
    clip,
    clipBusy,
  ];
}

class UploadItem extends Equatable {
  const UploadItem(this.file, {this.progress = 0, this.result, this.error});
  final PickedFile file;
  final double progress;
  final String? result, error;
  bool get done => result != null || error != null;
  @override
  List<Object?> get props => [file.path, progress, result, error];
}

class FilesCubit extends Cubit<FilesState> {
  FilesCubit(this._c, this._native, this._n) : super(const FilesState());
  final HyprClient _c;
  final Native _native;
  final NoticeCubit _n;
  bool _uploading = false;

  Future<void> loadCameras() async {
    try {
      final j = await _c.getJson('/cameras') as List;
      if (isClosed) return;
      emit(
        state.copyWith(
          cameras: [for (final e in j) RigCamera.fromJson((e as Map).cast())],
        ),
      );
    } on ApiException {
      // monitors alone still work
    }
  }

  /// [source] is a monitor name or `cam:<node>`.
  Future<void> grab(String source) async {
    if (state.grabbing) return;
    emit(state.copyWith(grabbing: true));
    try {
      final cam = source.startsWith('cam:');
      final name = cam ? source.substring(4) : source;
      final png = await _c.getBytes(
        '/screenshot',
        query: {cam ? 'camera' : 'monitor': name},
      );
      if (isClosed) return;
      final t = DateTime.now()
          .toIso8601String()
          .split('.')
          .first
          .replaceAll(':', '-');
      emit(
        state.copyWith(grabbing: false, shot: png, shotName: '$name-$t.png'),
      );
    } on ApiException catch (e) {
      _n.error(e.status == 404 ? "The rig couldn't capture $source" : e);
      if (!isClosed) emit(state.copyWith(grabbing: false));
    }
  }

  Future<void> saveShot() async {
    final s = state.shot;
    if (s == null) return;
    await _native.saveImage(s, state.shotName)
        ? _n.info('Saved to Pictures/hyprhand')
        : _n.error("Couldn't save the image");
  }

  Future<void> pickAndUpload() async {
    final files = await _native.pickFiles();
    if (files.isNotEmpty) await upload(files);
  }

  Future<void> upload(List<PickedFile> files) async {
    emit(
      state.copyWith(
        uploads: [
          ...state.uploads.where((u) => !u.done),
          for (final f in files) UploadItem(f),
        ],
      ),
    );
    if (_uploading) return;
    _uploading = true;
    try {
      while (!isClosed) {
        final next = state.uploads.where((u) => !u.done).firstOrNull;
        if (next == null) break;
        await _uploadOne(next.file);
      }
    } finally {
      _uploading = false;
    }
  }

  Future<void> _uploadOne(PickedFile f) async {
    void set(UploadItem u) {
      if (isClosed) return;
      emit(
        state.copyWith(
          uploads: [
            for (final x in state.uploads) x.file.path == f.path ? u : x,
          ],
        ),
      );
    }

    var shown = 0.0;
    try {
      final r = await _c.upload(
        File(f.path),
        f.name,
        onProgress: (p) {
          if (p - shown > .02) {
            shown = p;
            set(UploadItem(f, progress: p));
          }
        },
      );
      set(UploadItem(f, progress: 1, result: 'saved as ${r['name']}'));
    } on ApiException catch (e) {
      set(UploadItem(f, error: e.message));
    } catch (_) {
      set(UploadItem(f, error: 'Could not read the file'));
    }
    try {
      await File(f.path).parent.delete(recursive: true);
    } catch (_) {
      /* swept by the native side later */
    }
  }

  Future<void> receiveClip() async {
    if (state.clipBusy) return;
    emit(state.copyWith(clipBusy: true));
    try {
      final r = HyprClient.okOrThrow(await _c.getJson('/clipboard'));
      if (!isClosed) emit(state.copyWith(clip: '${r['text'] ?? ''}'));
    } on ApiException catch (e) {
      _n.error(e);
    } finally {
      if (!isClosed) emit(state.copyWith(clipBusy: false));
    }
  }

  Future<bool> sendClip(String text) async {
    try {
      await _c.call('/clipboard', {'text': text});
      _n.info('On the rig clipboard');
      return true;
    } on ApiException catch (e) {
      _n.error(e);
      return false;
    }
  }

  Future<void> openOnRig(String text) async {
    try {
      _n.info(await _c.shareText(text));
    } on ApiException catch (e) {
      _n.error(e);
    }
  }

  /// Saves one image and puts it on the rig clipboard.
  Future<void> shareImage(PickedFile f) async {
    try {
      final r = await _c.upload(
        File(f.path),
        f.name,
        path: '/share/api',
        field: 'files',
      );
      _n.info('${r['detail']} · on clipboard');
    } on ApiException catch (e) {
      _n.error(e);
    }
  }
}
