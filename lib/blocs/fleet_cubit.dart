import 'package:bloc/bloc.dart';

import '../data/hypr_client.dart';
import '../data/models.dart';

class FleetCubit extends Cubit<List<FleetHost>> {
  FleetCubit(this._c) : super(const []);
  final HyprClient _c;
  Future<void> load() async {
    try {
      final j = await _c.getJson('/fleet') as List;
      if (!isClosed) {
        emit([for (final e in j) FleetHost.fromJson((e as Map).cast())]);
      }
    } on ApiException {
      // keep the last roster
    }
  }
}
