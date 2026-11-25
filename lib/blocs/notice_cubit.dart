import 'package:bloc/bloc.dart';

import '../data/hypr_client.dart';

class Notice {
  Notice(this.text, {this.error = false});
  final String text;
  final bool error;
}

/// App-wide transient messages. Notices compare by identity, so repeating the
/// same text still shows again.
class NoticeCubit extends Cubit<Notice?> {
  NoticeCubit() : super(null);
  void info(String t) => isClosed ? null : emit(Notice(t));
  void error(Object e) {
    if (isClosed || (e is ApiException && e.unauthorized)) return;
    emit(Notice('$e', error: true));
  }
}
