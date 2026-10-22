import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/core_providers.dart';
import '../data/support_models.dart';
import '../data/support_repository.dart';

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(apiClientProvider));
});

final notificationsProvider = FutureProvider.autoDispose<List<DriverNotification>>((ref) {
  return ref.watch(supportRepositoryProvider).getNotifications();
});

final supportTitlesProvider = FutureProvider.autoDispose<List<SupportTitle>>((ref) {
  return ref.watch(supportRepositoryProvider).getSupportTitles();
});

final myTicketsProvider = FutureProvider.autoDispose<List<SupportTicket>>((ref) {
  return ref.watch(supportRepositoryProvider).listMyTickets();
});

class TicketThreadState {
  final SupportTicket? ticket;
  final bool loading;
  final bool replying;

  const TicketThreadState({this.ticket, this.loading = false, this.replying = false});

  TicketThreadState copyWith({SupportTicket? ticket, bool? loading, bool? replying}) {
    return TicketThreadState(
      ticket: ticket ?? this.ticket,
      loading: loading ?? this.loading,
      replying: replying ?? this.replying,
    );
  }
}

class TicketThreadNotifier extends StateNotifier<TicketThreadState> {
  final SupportRepository _repository;
  final String ticketCode;

  TicketThreadNotifier(this._repository, this.ticketCode) : super(const TicketThreadState()) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(loading: true);
    try {
      final ticket = await _repository.getTicket(ticketCode);
      state = state.copyWith(ticket: ticket, loading: false);
    } catch (_) {
      state = state.copyWith(loading: false);
    }
  }

  Future<void> reply(String message) async {
    state = state.copyWith(replying: true);
    try {
      final ticket = await _repository.replyTicket(ticketCode, message);
      state = state.copyWith(ticket: ticket, replying: false);
    } catch (e) {
      state = state.copyWith(replying: false);
      rethrow;
    }
  }
}

final ticketThreadProvider =
    StateNotifierProvider.autoDispose.family<TicketThreadNotifier, TicketThreadState, String>((ref, ticketCode) {
  return TicketThreadNotifier(ref.watch(supportRepositoryProvider), ticketCode);
});
