import 'package:bloc/bloc.dart';

enum DeckPage {
  deck('Deck'),
  remote('Remote'),
  audio('Audio'),
  commands('Commands'),
  more('More'),
  screen('Screen'),
  files('Files'),
  modes('Modes'),
  system('System'),
  config('Config'),
  settings('Settings');

  const DeckPage(this.label);
  final String label;

  bool get underMore => index > DeckPage.more.index;
}

class NavCubit extends Cubit<DeckPage> {
  NavCubit() : super(DeckPage.deck);
  void go(DeckPage p) => emit(p);

  /// Returns false when already home (let the system handle back).
  void back() => emit(state.underMore ? DeckPage.more : DeckPage.deck);

  void goNamed(String name) {
    for (final p in DeckPage.values) {
      if (p.name == name) emit(p);
    }
  }
}
